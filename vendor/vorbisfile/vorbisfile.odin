package vorbisfile

import "core:c"
import "core:c/libc"
import "base:library"
import "../ogg"
import "../vorbis"

@private LIB :: library.LIBPATH + "/libvorbisfile" + library.ARCH_end
foreign import lib { LIB }

@private _ov_header_fseek_wrap :: proc "c" (f:^libc.FILE, off:ogg.ogg_int64_t, whence:c.int) -> c.int {
    if f == nil do return -1

    return libc.fseek(f, auto_cast off, auto_cast whence)
}


// State values
NOTOPEN   :: 0
PARTOPEN  :: 1 
OPENED    :: 2
STREAMSET :: 3
INITSET   :: 4

ov_callbacks :: struct {
    read_func:  proc "c" (ptr: rawptr, size: c.size_t, nmemb: c.size_t, datasource: rawptr) -> c.size_t,
    seek_func:  proc "c" (datasource: rawptr, offset: ogg.ogg_int64_t, whence: c.int) -> c.int,
    close_func: proc "c" (datasource: rawptr) -> c.int,
    tell_func:  proc "c" (datasource: rawptr) -> c.long,
}

OV_CALLBACKS_DEFAULT : ov_callbacks = {
    read_func = auto_cast libc.fread,
    seek_func = auto_cast _ov_header_fseek_wrap,
    close_func = auto_cast libc.fclose,
    tell_func = auto_cast libc.ftell,
}
OV_CALLBACKS_NOCLOSE : ov_callbacks = {
    read_func = auto_cast libc.fread,
    seek_func = auto_cast _ov_header_fseek_wrap,
    close_func = nil,
    tell_func = auto_cast libc.ftell,
}
OV_CALLBACKS_STREAMONLY : ov_callbacks = {
    read_func = auto_cast libc.fread,
    seek_func = nil,
    close_func = auto_cast libc.fclose,
    tell_func = nil,
}
OV_CALLBACKS_STREAMONLY_NOCLOSE : ov_callbacks = {
    read_func = auto_cast libc.fread,
    seek_func = nil,
    close_func = nil,
    tell_func = nil,
}


OggVorbis_File :: struct {
    datasource: rawptr,           // Pointer to a FILE *, etc.
    seekable:   c.int,
    offset:     ogg.ogg_int64_t,
    end:        ogg.ogg_int64_t,
    oy:         ogg.ogg_sync_state,

    // If the FILE handle isn't seekable (eg, a pipe), only the current stream appears
    links:        c.int,
    offsets:      ^ogg.ogg_int64_t,
    dataoffsets:  ^ogg.ogg_int64_t,
    serialnos:    ^c.long,
    pcmlengths:   ^ogg.ogg_int64_t,   // overloaded to maintain binary compatibility; x2 size, stores both beginning and end values
    vi:           ^vorbis.vorbis_info,
    vc:           ^vorbis.vorbis_comment,

    // Decoding working state local storage
    pcm_offset:       ogg.ogg_int64_t,
    ready_state:      c.int,
    current_serialno: c.long,
    current_link:     c.int,

    bittrack:  c.double,
    samptrack: c.double,

    os: ogg.ogg_stream_state,    // take physical pages, weld into a logical stream of packets
    vd: vorbis.vorbis_dsp_state,    // central working state for the packet->PCM decoder
    vb: vorbis.vorbis_block,        // local working space for packet->PCM decode

    callbacks: ov_callbacks,
}

// External Functions
@(default_calling_convention="c")
foreign lib {
    ov_clear :: proc(vf: ^OggVorbis_File) -> c.int ---
    ov_fopen :: proc(path: cstring, vf: ^OggVorbis_File) -> c.int ---
    @(deprecated="can not use in windows https://xiph.org/vorbis/doc/vorbisfile/ov_open.html")
    ov_open :: proc(f: ^libc.FILE, vf: ^OggVorbis_File, initial: [^]c.char, ibytes: c.long) -> c.int --- 
    ov_open_callbacks :: proc(datasource: rawptr, vf: ^OggVorbis_File, initial: [^]c.char, ibytes: c.long, callbacks: ov_callbacks) -> c.int ---
    
    ov_test :: proc(f: ^libc.FILE, vf: ^OggVorbis_File, initial: [^]c.char, ibytes: c.long) -> c.int ---
    ov_test_callbacks :: proc(datasource: rawptr, vf: ^OggVorbis_File, initial: [^]c.char, ibytes: c.long, callbacks: ov_callbacks) -> c.int ---
    ov_test_open :: proc(vf: ^OggVorbis_File) -> c.int ---
    
    ov_bitrate :: proc(vf: ^OggVorbis_File, i: c.int) -> c.long ---
    ov_bitrate_instant :: proc(vf: ^OggVorbis_File) -> c.long ---
    ov_streams :: proc(vf: ^OggVorbis_File) -> c.long ---
    ov_seekable :: proc(vf: ^OggVorbis_File) -> c.long ---
    ov_serialnumber :: proc(vf: ^OggVorbis_File, i: c.int) -> c.long ---
    
    ov_raw_total :: proc(vf: ^OggVorbis_File, i: c.int) -> ogg.ogg_int64_t ---
    ov_pcm_total :: proc(vf: ^OggVorbis_File, i: c.int) -> ogg.ogg_int64_t ---
    ov_time_total :: proc(vf: ^OggVorbis_File, i: c.int) -> c.double ---
    
    ov_raw_seek :: proc(vf: ^OggVorbis_File, pos: ogg.ogg_int64_t) -> c.int ---
    ov_pcm_seek :: proc(vf: ^OggVorbis_File, pos: ogg.ogg_int64_t) -> c.int ---
    ov_pcm_seek_page :: proc(vf: ^OggVorbis_File, pos: ogg.ogg_int64_t) -> c.int ---
    ov_time_seek :: proc(vf: ^OggVorbis_File, pos: c.double) -> c.int ---
    ov_time_seek_page :: proc(vf: ^OggVorbis_File, pos: c.double) -> c.int ---
    
    ov_raw_seek_lap :: proc(vf: ^OggVorbis_File, pos: ogg.ogg_int64_t) -> c.int ---
    ov_pcm_seek_lap :: proc(vf: ^OggVorbis_File, pos: ogg.ogg_int64_t) -> c.int ---
    ov_pcm_seek_page_lap :: proc(vf: ^OggVorbis_File, pos: ogg.ogg_int64_t) -> c.int ---
    ov_time_seek_lap :: proc(vf: ^OggVorbis_File, pos: c.double) -> c.int ---
    ov_time_seek_page_lap :: proc(vf: ^OggVorbis_File, pos: c.double) -> c.int ---
    
    ov_raw_tell :: proc(vf: ^OggVorbis_File) -> ogg.ogg_int64_t ---
    ov_pcm_tell :: proc(vf: ^OggVorbis_File) -> ogg.ogg_int64_t ---
    ov_time_tell :: proc(vf: ^OggVorbis_File) -> c.double ---
    
    ov_info :: proc(vf: ^OggVorbis_File, link: c.int) -> ^vorbis.vorbis_info ---
    ov_comment :: proc(vf: ^OggVorbis_File, link: c.int) -> ^vorbis.vorbis_comment ---
    
    ov_read_float :: proc(vf: ^OggVorbis_File, pcm_channels: ^^^c.float, samples: c.int, bitstream: ^c.int) -> c.long ---
    ov_read_filter :: proc(vf: ^OggVorbis_File, buffer: [^]c.char, length: c.int, bigendianp: c.int, word: c.int, sgned: c.int, bitstream: ^c.int,
                          filter: proc(pcm: ^^c.float, channels: c.long, samples: c.long, filter_param: rawptr), filter_param: rawptr) -> c.long ---
    ov_read :: proc(vf: ^OggVorbis_File, buffer: [^]c.char, length: c.int, bigendianp: c.int, word: c.int, sgned: c.int, bitstream: ^c.int) -> c.long ---
    ov_crosslap :: proc(vf1: ^OggVorbis_File, vf2: ^OggVorbis_File) -> c.int ---
    
    ov_halfrate :: proc(vf: ^OggVorbis_File, flag: c.int) -> c.int ---
    ov_halfrate_p :: proc(vf: ^OggVorbis_File) -> c.int ---
}