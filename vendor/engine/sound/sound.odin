package sound

import "vendor:miniaudio"
import "core:sync"
import "core:thread"
import "core:debug/trace"
import "base:intrinsics"
import "base:runtime"

@(private = "file") Sound_private :: struct #packed {
    __miniaudio_sound:miniaudio.sound,
    __miniaudio_audioBuf:miniaudio.audio_buffer,
    __inited:bool
}

SoundError :: miniaudio.result

Sound :: struct {
    src:^SoundSrc,
   __private : Sound_private,
}

SoundFormat::miniaudio.format

SoundSrc :: struct {
    format:SoundFormat,
    channels:u32,
    sampleRate:u32,
    sizeInFrames:u64,
    decoderConfig:miniaudio.decoder_config,
    decoder:miniaudio.decoder
}

@(private = "file") miniaudio_engine:miniaudio.engine

@(private = "file") miniaudio_pCustomBackendVTables:[2]^miniaudio.decoding_backend_vtable
@(private = "file") miniaudio_pCustomBackendVTables2:[2]^miniaudio.decoding_backend_vtable
@(private = "file") miniaudio_resourceManager:miniaudio.resource_manager
@(private = "file") miniaudio_resourceManagerConfig:miniaudio.resource_manager_config
@(private = "file") miniaudio_engineConfig:miniaudio.engine_config

@(private = "file") gSoundsMtx:sync.Mutex
@(private = "file") gEndSoundsMtx:sync.Mutex
@(private = "file") gSema:sync.Sema
@(private = "file") gThread:^thread.Thread

@(private = "file") started:bool = false

@(private = "file") gEndSounds:[dynamic]^Sound
@(private = "file") gSounds:map[^Sound]^Sound

@private g_init :: proc() {
    gSounds = make(map[^Sound]^Sound)
    gEndSounds = make([dynamic]^Sound)

    miniaudio_resourceManagerConfig = miniaudio.resource_manager_config_init()
    miniaudio_pCustomBackendVTables[0] = miniaudio.ma_decoding_backend_libvorbis
    miniaudio_pCustomBackendVTables[1] = miniaudio.ma_decoding_backend_libopus
    miniaudio_pCustomBackendVTables2[0] = miniaudio.ma_decoding_backend_libvorbis
    miniaudio_pCustomBackendVTables2[1] = miniaudio.ma_decoding_backend_libopus

    miniaudio_resourceManagerConfig.ppCustomDecodingBackendVTables = &miniaudio_pCustomBackendVTables[0]
    miniaudio_resourceManagerConfig.customDecodingBackendCount = 2
    miniaudio_resourceManagerConfig.pCustomDecodingBackendUserData = nil

    res := miniaudio.resource_manager_init(&miniaudio_resourceManagerConfig, &miniaudio_resourceManager)
    if res != .SUCCESS do trace.panic_log("miniaudio.resource_manager_init : ", res)

    miniaudio_engineConfig = miniaudio.engine_config_init()
    miniaudio_engineConfig.pResourceManager = &miniaudio_resourceManager
    
    
    res = miniaudio.engine_init(&miniaudio_engineConfig, &miniaudio_engine)
    if res != .SUCCESS do trace.panic_log("miniaudio.engine_init : ", res)

    started = true
    gThread = thread.create(Callback)
    thread.start(gThread)
}

@(private = "file") Callback :: proc(_: ^thread.Thread) {
    for intrinsics.atomic_load_explicit(&started, .Acquire) {
        sync.sema_wait(&gSema)
        if !intrinsics.atomic_load_explicit(&started, .Acquire) do break

        this : ^Sound = nil
        sync.mutex_lock(&gEndSoundsMtx)
        if len(gEndSounds) > 0 {
            this = pop(&gEndSounds)
        }
        sync.mutex_unlock(&gEndSoundsMtx)

        if this != nil {
            sync.mutex_lock(&gSoundsMtx)
            defer sync.mutex_unlock(&gSoundsMtx)
            if !miniaudio.sound_is_looping(&this.__private.__miniaudio_sound) {
                deinit2(this)
            }
        }
    }
}

Sound_Deinit :: proc(self:^Sound) {
    sync.mutex_lock(&gSoundsMtx)
    defer sync.mutex_unlock(&gSoundsMtx)
    deinit2(self)
}
@(private = "file") deinit2 :: proc(self:^Sound) {
    if !self.__private.__inited do return
    miniaudio.sound_uninit(&self.__private.__miniaudio_sound)
    miniaudio.audio_buffer_uninit(&self.__private.__miniaudio_audioBuf)
    free(self)
    if intrinsics.atomic_load_explicit(&started, .Acquire) do delete_key(&gSounds, self)
}

@(private = "file") EndCallback :: proc "c" (userdata:rawptr, _:^miniaudio.sound) {
    self := cast(^Sound)(userdata)

    context = runtime.default_context()
    sync.mutex_lock(&gEndSoundsMtx)
    non_zero_append(&gEndSounds, self)
    sync.mutex_unlock(&gEndSoundsMtx)
    sync.sema_post(&gSema)
}

@(fini, private) g_deinit :: proc "contextless" () {
    if !intrinsics.atomic_load_explicit(&started, .Acquire) do return
    intrinsics.atomic_store_explicit(&started, false, .Release)
    sync.sema_post(&gSema)
    
    context = runtime.default_context()
    thread.join(gThread)

    miniaudio.engine_uninit(&miniaudio_engine)

    sync.mutex_lock(&gSoundsMtx)
    for key in gSounds {
        deinit2(key)
    }
    sync.mutex_unlock(&gSoundsMtx)

    delete(gEndSounds)
    delete(gSounds)
}

SoundSrc_Deinit :: proc(self:^SoundSrc) {
    sync.mutex_lock(&gSoundsMtx)
    for key in gSounds {
        if key.src == self do deinit2(key)
    }
    sync.mutex_unlock(&gSoundsMtx)
    miniaudio.decoder_uninit(&self.decoder)
    free(self)
}

SoundSrc_PlaySoundMemory :: proc(self:^SoundSrc, volume:f32, loop:bool) -> (snd: ^Sound, err: SoundError) {
    if !intrinsics.atomic_load_explicit(&started, .Acquire) do trace.panic_log("SoundSrc_PlaySoundMemory : sound not started.")

    err = .SUCCESS
    snd = new(Sound)
    defer if err != .SUCCESS do free(snd)
    snd^ = Sound{ src = self }

    err = miniaudio.sound_init_from_data_source(
        pEngine = &miniaudio_engine,
        pDataSource = snd.src.decoder.ds.pCurrent,
        flags = {.DECODE},
        pGroup = nil,
        pSound = &snd.__private.__miniaudio_sound,
    )
    if err != .SUCCESS do return
    miniaudio.sound_set_end_callback(&snd.__private.__miniaudio_sound, EndCallback, auto_cast snd)
    miniaudio.sound_set_looping(&snd.__private.__miniaudio_sound, auto_cast loop)

    miniaudio.sound_set_volume(&snd.__private.__miniaudio_sound, volume)

    err = miniaudio.sound_start(&snd.__private.__miniaudio_sound)
    if err != .SUCCESS {
        miniaudio.sound_uninit(&snd.__private.__miniaudio_sound)
        return
    }

    sync.mutex_lock(&gSoundsMtx)
    map_insert(&gSounds, snd, snd)
    sync.mutex_unlock(&gSoundsMtx)

    snd.__private.__inited = true
    return
}

SetVolume :: #force_inline proc "contextless" (self:^Sound, volume:f32) {
    miniaudio.sound_set_volume(&self.__private.__miniaudio_sound, volume)
}

//= playing speed
SetPitch :: #force_inline proc "contextless" (self:^Sound, pitch:f32) {
    miniaudio.sound_set_pitch(&self.__private.__miniaudio_sound, pitch)
}

Pause :: #force_inline proc "contextless" (self:^Sound) {
    res := miniaudio.sound_stop(&self.__private.__miniaudio_sound)
    if res != .SUCCESS do trace.panic_log(res)
}

Resume :: #force_inline proc "contextless" (self:^Sound) {
   res := miniaudio.sound_start(&self.__private.__miniaudio_sound)
   if res != .SUCCESS do trace.panic_log(res)
}

@require_results GetLenSec :: #force_inline proc "contextless" (self:^Sound) -> f32 {
    sec:f32
    res := miniaudio.sound_get_length_in_seconds(&self.__private.__miniaudio_sound, &sec)
    if res != .SUCCESS do trace.panic_log(res)
    return sec
}

@require_results GetLen :: #force_inline proc "contextless" (self:^Sound) -> u64 {
    frames:u64
    res := miniaudio.sound_get_length_in_pcm_frames(&self.__private.__miniaudio_sound, &frames)
    if res != .SUCCESS do trace.panic_log(res)
    return frames
}

@require_results GetPosSec :: #force_inline proc "contextless" (self:^Sound) -> f32 {
    sec:f32
    res := miniaudio.sound_get_cursor_in_seconds(&self.__private.__miniaudio_sound, &sec)
    if res != .SUCCESS do trace.panic_log(res)
    return sec
}

@require_results GetPos :: #force_inline proc "contextless" (self:^Sound) -> u64 {
    frames:u64
    res := miniaudio.sound_get_cursor_in_pcm_frames(&self.__private.__miniaudio_sound, &frames)
    if res != .SUCCESS do trace.panic_log(res)
    return frames
}

SetPos :: #force_inline proc "contextless" (self:^Sound, pos:u64) {
    res := miniaudio.sound_seek_to_pcm_frame(&self.__private.__miniaudio_sound, pos)
    if res != .SUCCESS do trace.panic_log(res)
}

SetPosSec :: #force_inline proc "contextless" (self:^Sound, posSec:f32) -> bool {
    pos:u64 = u64(f64(posSec) * f64(self.src.sampleRate))
    if pos >= GetLen(self) do return false
    res := miniaudio.sound_seek_to_pcm_frame(&self.__private.__miniaudio_sound, pos)
    if res != .SUCCESS do trace.panic_log(res)
    return true
}

SetLooping :: #force_inline proc "contextless" (self:^Sound, loop:bool) {
    miniaudio.sound_set_looping(&self.__private.__miniaudio_sound, auto_cast loop)
}

@require_results IsLooping :: #force_inline proc "contextless" (self:^Sound) -> bool {
   return auto_cast miniaudio.sound_is_looping(&self.__private.__miniaudio_sound)
}

@require_results IsPlaying :: #force_inline proc "contextless" (self:^Sound) -> bool {
    return auto_cast miniaudio.sound_is_playing(&self.__private.__miniaudio_sound)
}

@require_results SoundSrc_DecodeSoundMemory :: proc(data:[]byte) -> (result : ^SoundSrc, err: SoundError) {
    if !intrinsics.atomic_load_explicit(&started, .Acquire) do g_init()//?g_init 따로 호출하지 않고 최초로 사용할때 시작

    result = new(SoundSrc)
    defer if err != .SUCCESS do free(result)

    result.decoderConfig = miniaudio.decoder_config_init_default()
    result.decoderConfig.ppCustomBackendVTables = &miniaudio_pCustomBackendVTables2[0]
    result.decoderConfig.customBackendCount = 2

    err = miniaudio.decoder_init_memory(raw_data(data), len(data), &result.decoderConfig, &result.decoder)
    if err != .SUCCESS {
        return
    }
    return
}
