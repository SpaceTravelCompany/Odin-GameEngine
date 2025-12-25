package miniaudio

import "core:c"
import "core:c/libc"
import "core:mem"
import "../vorbisfile"
import "../vorbis"
import "../ogg"

foreign import lib {
    "../vorbisfile" + vorbisfile.LIB,
    "../vorbis" + vorbis.LIB,
    "../ogg" + ogg.LIB,
	LIB,
}

libvorbis :: struct {
	ds:data_source_base,
	onRead:ma_read_proc,
	onSeek:ma_seek_proc,
	onTell:ma_tell_proc,
	pReadSeekTellUserData:rawptr,
    format:format,
	vf:vorbisfile.OggVorbis_File,
}


@(default_calling_convention="c", link_prefix="ma_")
foreign lib {
    libvorbis_init :: proc (onRead:ma_read_proc,
    onSeek:ma_seek_proc,
    onTell:ma_tell_proc,
    pReadSeekTellUserData:rawptr,
    pConfig:^decoding_backend_config,
    _:^allocation_callbacks,//?pAllocationCallbacks
    pVorbis:^libvorbis) -> result ---
    
    libvorbis_init_file :: proc (pFilePath:cstring,
        pConfig:^decoding_backend_config,
        _:^allocation_callbacks,//?pAllocationCallbacks
        pVorbis:^libvorbis) -> result ---
    
    libvorbis_uninit :: proc (pVorbis:^libvorbis,_:^allocation_callbacks,/*?pAllocationCallbacks*/) ---
    
    libvorbis_read_pcm_frames :: proc (pVorbis:^libvorbis,
    pFramesOut:rawptr,
    frameCount:u64,
    pFramesRead:^u64) -> result ---
    
    libvorbis_seek_to_pcm_frame :: proc (pVorbis: ^libvorbis, frameIndex: u64) -> result ---
    
    libvorbis_get_data_format :: proc (
        pVorbis: ^libvorbis,
        pFormat: ^format,
        pChannels: ^u32,
        pSampleRate: ^u32,
        pChannelMap: [^]channel,
        channelMapCap: c.size_t,
    ) -> result ---
    
    libvorbis_get_cursor_in_pcm_frames :: proc (pVorbis: ^libvorbis, pCursor: ^u64) -> result ---
    
    libvorbis_get_length_in_pcm_frames :: proc (pVorbis: ^libvorbis, pLength: ^u64) -> result ---
}
foreign lib {
    ma_decoding_backend_libvorbis : ^decoding_backend_vtable
}