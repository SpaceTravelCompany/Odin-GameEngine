package miniaudio

import "core:c"
import "core:c/libc"
import "core:mem"
import "../vorbisfile"
import "../vorbis"
import "../ogg"
import "base:library"

LIB_VORBIS :: library.LIBPATH + "/libminiaudio_libvorbis" + library.ARCH_end
foreign import lib {
    "../vorbisfile" + vorbisfile.LIB,
    "../vorbis" + vorbis.LIB,
    "../ogg" + ogg.LIB,
	LIB_VORBIS,
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
    pAllocationCallbacks:^allocation_callbacks,
    pVorbis:^libvorbis) -> result ---
    
    libvorbis_init_file :: proc (pFilePath:cstring,
        pConfig:^decoding_backend_config,
        pAllocationCallbacks:^allocation_callbacks,
        pVorbis:^libvorbis) -> result ---
    
    libvorbis_uninit :: proc (pVorbis:^libvorbis,pAllocationCallbacks:^allocation_callbacks,) ---
    
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

    get_decoding_backend_libvorbis :: proc () -> ^decoding_backend_vtable ---
}