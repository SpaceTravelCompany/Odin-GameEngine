package miniaudio

import "core:c"
import "core:c/libc"
import "core:mem"
import "../opusfile"
import "../ogg"
import "../opus"

foreign import lib {
    opusfile.LIBOPUSFILE,
    opus.LIBOPUS,
	LIB,
}

libopus :: struct {
	ds:data_source_base,
	onRead:ma_read_proc,
	onSeek:ma_seek_proc,
	onTell:ma_tell_proc,
	pReadSeekTellUserData:rawptr,
    format:format,
	of:^opusfile.OggOpusFile,
}

@(default_calling_convention="c", link_prefix="ma_")
foreign lib {
    libopus_init :: proc (onRead:ma_read_proc,
    onSeek:ma_seek_proc,
    onTell:ma_tell_proc,
    pReadSeekTellUserData:rawptr,
    pConfig:^decoding_backend_config,
    _:^allocation_callbacks,//?pAllocationCallbacks
    pOpus:^libopus) -> result ---
    
    libopus_init_file :: proc (pFilePath:cstring,
        pConfig:^decoding_backend_config,
        _:^allocation_callbacks,//?pAllocationCallbacks
        pOpus:^libopus) -> result ---
    
    libopus_uninit :: proc (pOpus:^libopus,_:^allocation_callbacks,/*?pAllocationCallbacks*/) ---
    
    libopus_read_pcm_frames :: proc (pOpus:^libopus,
    pFramesOut:rawptr,
    frameCount:u64,
    pFramesRead:^u64) -> result ---
    
    libopus_seek_to_pcm_frame :: proc (pOpus: ^libopus, frameIndex: u64) -> result ---
    
    libopus_get_data_format :: proc (
        pOpus: ^libopus,
        pFormat: ^format,
        pChannels: ^u32,
        pSampleRate: ^u32,
        pChannelMap: [^]channel,
        channelMapCap: c.size_t,
    ) -> result ---
    
    libopus_get_cursor_in_pcm_frames :: proc (pOpus: ^libopus, pCursor: ^u64) -> result ---
    
    libopus_get_length_in_pcm_frames :: proc (pOpus: ^libopus, pLength: ^u64) -> result ---
}
foreign lib {
    ma_decoding_backend_libopus : ^decoding_backend_vtable
}