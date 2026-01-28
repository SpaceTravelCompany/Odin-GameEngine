package sound

import "base:intrinsics"
import "base:runtime"
import "core:debug/trace"
import "core:sync"
import "core:thread"
import "vendor:miniaudio"
import "core:log"


@(private = "file") sound_private :: struct #packed {
    __miniaudio_sound:miniaudio.sound,
    __miniaudio_audioBuf:miniaudio.audio_buffer,
    __inited:bool
}

sound_error :: miniaudio.result

sound :: struct {
    src:^sound_src,
   __private : sound_private,
}

sound_format::miniaudio.format

sound_src :: struct {
    format:sound_format,
    channels:u32,
    sample_rate:u32,
    size_in_frames:u64,
    decoder_config:miniaudio.decoder_config,
    decoder:miniaudio.decoder
}


@(private = "file") miniaudio_engine:miniaudio.engine

@(private = "file") miniaudio_p_custom_backend_v_tables:[2]^miniaudio.decoding_backend_vtable
@(private = "file") miniaudio_p_custom_backend_v_tables2:[2]^miniaudio.decoding_backend_vtable
@(private = "file") miniaudio_resource_manager:miniaudio.resource_manager
@(private = "file") miniaudio_resource_manager_config:miniaudio.resource_manager_config
@(private = "file") miniaudio_engine_config:miniaudio.engine_config

@(private = "file") g_sounds_mtx:sync.Mutex
@(private = "file") g_end_sounds_mtx:sync.Mutex
@(private = "file") g_sema:sync.Sema
@(private = "file") g_thread:^thread.Thread

@(private = "file") started:bool = false

@(private = "file") g_end_sounds:[dynamic]^sound
@(private = "file") g_sounds:map[^sound]^sound


@private g_init :: proc() {
	context.allocator = runtime.default_allocator()// avoid g_sounds, g_end_sounds affects tracking allocator
    g_sounds = make(map[^sound]^sound)
    g_end_sounds = make([dynamic]^sound)

    miniaudio_resource_manager_config = miniaudio.resource_manager_config_init()
    miniaudio_p_custom_backend_v_tables[0] = miniaudio.get_decoding_backend_libvorbis()
    miniaudio_p_custom_backend_v_tables[1] = miniaudio.get_decoding_backend_libopus()
    miniaudio_p_custom_backend_v_tables2[0] = miniaudio.get_decoding_backend_libvorbis()
    miniaudio_p_custom_backend_v_tables2[1] = miniaudio.get_decoding_backend_libopus()

    miniaudio_resource_manager_config.ppCustomDecodingBackendVTables = &miniaudio_p_custom_backend_v_tables[0]
    miniaudio_resource_manager_config.customDecodingBackendCount = 2
    miniaudio_resource_manager_config.pCustomDecodingBackendUserData = nil

    res := miniaudio.resource_manager_init(&miniaudio_resource_manager_config, &miniaudio_resource_manager)
    if res != .SUCCESS do log.panicf("miniaudio.resource_manager_init : %s\n", res)

    miniaudio_engine_config = miniaudio.engine_config_init()
    miniaudio_engine_config.pResourceManager = &miniaudio_resource_manager
    
    
    res = miniaudio.engine_init(&miniaudio_engine_config, &miniaudio_engine)
    if res != .SUCCESS do log.panicf("miniaudio.engine_init : %s\n", res)

    started = true
    g_thread = thread.create(callback)
    thread.start(g_thread)
}

@(private = "file") callback :: proc(_: ^thread.Thread) {
    for intrinsics.atomic_load_explicit(&started, .Acquire) {
        sync.sema_wait(&g_sema)
        if !intrinsics.atomic_load_explicit(&started, .Acquire) do break

        this : ^sound = nil
        sync.mutex_lock(&g_end_sounds_mtx)
        if len(g_end_sounds) > 0 {
            this = pop(&g_end_sounds)
        }
        sync.mutex_unlock(&g_end_sounds_mtx)

        if this != nil {
            sync.mutex_lock(&g_sounds_mtx)
            defer sync.mutex_unlock(&g_sounds_mtx)
            if !miniaudio.sound_is_looping(&this.__private.__miniaudio_sound) {
                deinit2(this)
            }
        }
    }
}

/*
Deinitializes and cleans up sound resources

Inputs:
- self: Pointer to the sound to deinitialize

Returns:
- None
*/
sound_deinit :: proc(self:^sound) {
    sync.mutex_lock(&g_sounds_mtx)
    defer sync.mutex_unlock(&g_sounds_mtx)
    deinit2(self)
}
@(private = "file") deinit2 :: proc(self:^sound) {
    if !self.__private.__inited do return
    miniaudio.sound_uninit(&self.__private.__miniaudio_sound)
    miniaudio.audio_buffer_uninit(&self.__private.__miniaudio_audioBuf)
    free(self)
    if intrinsics.atomic_load_explicit(&started, .Acquire) do delete_key(&g_sounds, self)
}

@(private = "file") end_callback :: proc "c" (userdata:rawptr, _:^miniaudio.sound) {
    self := cast(^sound)(userdata)

    context = runtime.default_context()
    sync.mutex_lock(&g_end_sounds_mtx)
    non_zero_append(&g_end_sounds, self)
    sync.mutex_unlock(&g_end_sounds_mtx)
    sync.sema_post(&g_sema)
}

@(fini, private) g_deinit :: proc "contextless" () {
    if !intrinsics.atomic_load_explicit(&started, .Acquire) do return
    intrinsics.atomic_store_explicit(&started, false, .Release)
    sync.sema_post(&g_sema)
    
    context = runtime.default_context()
    thread.join(g_thread)

    miniaudio.engine_uninit(&miniaudio_engine)

    sync.mutex_lock(&g_sounds_mtx)
    for key in g_sounds {
        deinit2(key)
    }
    sync.mutex_unlock(&g_sounds_mtx)

    delete(g_end_sounds)
    delete(g_sounds)
}

/*
Deinitializes a sound source and all sounds using it

Inputs:
- self: Pointer to the sound source to deinitialize

Returns:
- None
*/
sound_src_deinit :: proc(self:^sound_src) {
    sync.mutex_lock(&g_sounds_mtx)
    for key in g_sounds {
        if key.src == self do deinit2(key)
    }
    sync.mutex_unlock(&g_sounds_mtx)
    miniaudio.decoder_uninit(&self.decoder)
    free(self)
}

/*
Plays a sound from memory using a sound source

Inputs:
- self: Pointer to the sound source
- volume: Volume level (0.0 to 1.0)
- loop: Whether to loop the sound

Returns:
- Pointer to the playing sound
- An error if playback failed
*/
sound_src_play_sound_memory :: proc(self:^sound_src, volume:f32, loop:bool) -> (snd: ^sound, err: sound_error) {
    if !intrinsics.atomic_load_explicit(&started, .Acquire) do log.panicf("sound_src_play_sound_memory : sound not started.\n")

    err = .SUCCESS
    snd = new(sound)
    defer if err != .SUCCESS do free(snd)
    snd^ = sound{ src = self }

    err = miniaudio.sound_init_from_data_source(
        pEngine = &miniaudio_engine,
        pDataSource = snd.src.decoder.ds.pCurrent,
        flags = {.DECODE},
        pGroup = nil,
        pSound = &snd.__private.__miniaudio_sound,
    )
    if err != .SUCCESS do return
    miniaudio.sound_set_end_callback(&snd.__private.__miniaudio_sound, end_callback, auto_cast snd)
    miniaudio.sound_set_looping(&snd.__private.__miniaudio_sound, auto_cast loop)

    miniaudio.sound_set_volume(&snd.__private.__miniaudio_sound, volume)

    err = miniaudio.sound_start(&snd.__private.__miniaudio_sound)
    if err != .SUCCESS {
        miniaudio.sound_uninit(&snd.__private.__miniaudio_sound)
        return
    }

    sync.mutex_lock(&g_sounds_mtx)
    map_insert(&g_sounds, snd, snd)
    sync.mutex_unlock(&g_sounds_mtx)

    snd.__private.__inited = true
    return
}

set_volume :: #force_inline proc "contextless" (self:^sound, volume:f32) {
    miniaudio.sound_set_volume(&self.__private.__miniaudio_sound, volume)
}

//= playing speed
set_pitch :: #force_inline proc "contextless" (self:^sound, pitch:f32) {
    miniaudio.sound_set_pitch(&self.__private.__miniaudio_sound, pitch)
}

pause :: #force_inline proc (self:^sound) {
    res := miniaudio.sound_stop(&self.__private.__miniaudio_sound)
    if res != .SUCCESS {
		log.panicf("sound_stop: %s\n", res)
	}
}

resume :: #force_inline proc (self:^sound) {
   res := miniaudio.sound_start(&self.__private.__miniaudio_sound)
   if res != .SUCCESS {
		log.panicf("sound_start: %s\n", res)
	}
}

@require_results get_len_sec :: #force_inline proc (self:^sound) -> f32 {
    sec:f32
    res := miniaudio.sound_get_length_in_seconds(&self.__private.__miniaudio_sound, &sec)
    if res != .SUCCESS {
		log.panicf("sound_get_length_in_seconds: %s\n", res)
	}
    return sec
}

@require_results get_len :: #force_inline proc (self:^sound) -> u64 {
    frames:u64
    res := miniaudio.sound_get_length_in_pcm_frames(&self.__private.__miniaudio_sound, &frames)
    if res != .SUCCESS {
		log.panicf("sound_get_length_in_pcm_frames: %s\n", res)
	}
    return frames
}

@require_results get_pos_sec :: #force_inline proc (self:^sound) -> f32 {
    sec:f32
    res := miniaudio.sound_get_cursor_in_seconds(&self.__private.__miniaudio_sound, &sec)
    if res != .SUCCESS {
		log.panicf("sound_get_cursor_in_seconds: %s\n", res)
	}
    return sec
}

@require_results get_pos :: #force_inline proc (self:^sound) -> u64 {
    frames:u64
    res := miniaudio.sound_get_cursor_in_pcm_frames(&self.__private.__miniaudio_sound, &frames)
    if res != .SUCCESS {
		log.panicf("sound_get_cursor_in_pcm_frames: %s\n", res)
	}
    return frames
}

set_pos :: #force_inline proc (self:^sound, pos:u64) {
    res := miniaudio.sound_seek_to_pcm_frame(&self.__private.__miniaudio_sound, pos)
    if res != .SUCCESS {
		log.panicf("sound_seek_to_pcm_frame: %s\n", res)
	}
}

set_pos_sec :: #force_inline proc (self:^sound, pos_sec:f32) -> bool {
    pos:u64 = u64(f64(pos_sec) * f64(self.src.sample_rate))
    if pos >= get_len(self) do return false
    res := miniaudio.sound_seek_to_pcm_frame(&self.__private.__miniaudio_sound, pos)
    if res != .SUCCESS {
		log.panicf("sound_seek_to_pcm_frame: %s\n", res)
	}
    return true
}

set_looping :: #force_inline proc "contextless" (self:^sound, loop:bool) {
    miniaudio.sound_set_looping(&self.__private.__miniaudio_sound, auto_cast loop)
}

@require_results is_looping :: #force_inline proc "contextless" (self:^sound) -> bool {
   return auto_cast miniaudio.sound_is_looping(&self.__private.__miniaudio_sound)
}

@require_results is_playing :: #force_inline proc "contextless" (self:^sound) -> bool {
    return auto_cast miniaudio.sound_is_playing(&self.__private.__miniaudio_sound)
}

@require_results sound_src_decode_sound_memory :: proc(data:[]byte) -> (result : ^sound_src, err: sound_error) {
    if !intrinsics.atomic_load_explicit(&started, .Acquire) do g_init()//?g_init 따로 호출하지 않고 최초로 사용할때 시작

    result = new(sound_src)
    defer if err != .SUCCESS do free(result)

    result.decoder_config = miniaudio.decoder_config_init_default()
    result.decoder_config.ppCustomBackendVTables = &miniaudio_p_custom_backend_v_tables2[0]
    result.decoder_config.customBackendCount = 2

    err = miniaudio.decoder_init_memory(raw_data(data), len(data), &result.decoder_config, &result.decoder)
    if err != .SUCCESS {
        return
    }
    return
}
