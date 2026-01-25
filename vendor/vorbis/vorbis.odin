package vorbis

import "core:c"
import "base:library"
import "../ogg"


@private LIB :: library.LIBPATH + "/libvorbis" + library.ARCH_end
@private LIBENC :: library.LIBPATH + "/libvorbisenc" + library.ARCH_end
foreign import lib { LIB, LIBENC }


//codec.h

// Error codes
OV_FALSE      :: -1
OV_EOF        :: -2
OV_HOLE       :: -3

OV_EREAD      :: -128
OV_EFAULT     :: -129
OV_EIMPL      :: -130
OV_EINVAL     :: -131
OV_ENOTVORBIS :: -132
OV_EBADHEADER :: -133
OV_EVERSION   :: -134
OV_ENOTAUDIO  :: -135
OV_EBADPACKET :: -136
OV_EBADLINK   :: -137
OV_ENOSEEK    :: -138

// Structures
vorbis_info :: struct {
    version: c.int,
    channels: c.int,
    rate: c.long,
    
    bitrate_upper: c.long,
    bitrate_nominal: c.long,
    bitrate_lower: c.long,
    bitrate_window: c.long,
    
    codec_setup: rawptr,
}

vorbis_dsp_state :: struct {
    analysisp: c.int,
    vi: ^vorbis_info,
    
    pcm: ^^c.float,
    pcmret: ^^c.float,
    pcm_storage: c.int,
    pcm_current: c.int,
    pcm_returned: c.int,
    
    preextrapolate: c.int,
    eofflag: c.int,
    
    lW: c.long,
    W: c.long,
    nW: c.long,
    centerW: c.long,
    
    granulepos: ogg.ogg_int64_t,
    sequence: ogg.ogg_int64_t,
    
    glue_bits: ogg.ogg_int64_t,
    time_bits: ogg.ogg_int64_t,
    floor_bits: ogg.ogg_int64_t,
    res_bits: ogg.ogg_int64_t,
    
    backend_state: rawptr,
}

vorbis_block :: struct {
    pcm: ^^c.float,
    opb: ogg.oggpack_buffer,
    
    lW: c.long,
    W: c.long,
    nW: c.long,
    pcmend: c.int,
    mode: c.int,
    
    eofflag: c.int,
    granulepos: ogg.ogg_int64_t,
    sequence: ogg.ogg_int64_t,
    vd: ^vorbis_dsp_state,
    
    localstore: rawptr,
    localtop: c.long,
    localalloc: c.long,
    totaluse: c.long,
    reap: ^alloc_chain,
    
    glue_bits: c.long,
    time_bits: c.long,
    floor_bits: c.long,
    res_bits: c.long,
    
    internal: rawptr,
}

alloc_chain :: struct {
    ptr: rawptr,
    next: ^alloc_chain,
}

vorbis_comment :: struct {
    user_comments: [^]cstring,
    comment_lengths: ^c.int,
    comments: c.int,
    vendor: cstring,
}

// External functions
@(default_calling_convention="c")
foreign lib {
    vorbis_info_init :: proc(vi: ^vorbis_info) ---
    vorbis_info_clear :: proc(vi: ^vorbis_info) ---
    vorbis_info_blocksize :: proc(vi: ^vorbis_info, zo: c.int) -> c.int ---
    vorbis_comment_init :: proc(vc: ^vorbis_comment) ---
    vorbis_comment_add :: proc(vc: ^vorbis_comment, comment: cstring) ---
    vorbis_comment_add_tag :: proc(vc: ^vorbis_comment, tag: cstring, contents: cstring) ---
    vorbis_comment_query :: proc(vc: ^vorbis_comment, tag: cstring, count: c.int) -> cstring ---
    vorbis_comment_query_count :: proc(vc: ^vorbis_comment, tag: cstring) -> c.int ---
    vorbis_comment_clear :: proc(vc: ^vorbis_comment) ---

    vorbis_block_init :: proc(v: ^vorbis_dsp_state, vb: ^vorbis_block) -> c.int ---
    vorbis_block_clear :: proc(vb: ^vorbis_block) -> c.int ---
    vorbis_dsp_clear :: proc(v: ^vorbis_dsp_state) ---
    vorbis_granule_time :: proc(v: ^vorbis_dsp_state, granulepos: ogg.ogg_int64_t) -> f64 ---

    vorbis_version_string :: proc() -> cstring ---

    // Analysis layer
    vorbis_analysis_init :: proc(v: ^vorbis_dsp_state, vi: ^vorbis_info) -> c.int ---
    vorbis_commentheader_out :: proc(vc: ^vorbis_comment, op: ^ogg.ogg_packet) -> c.int ---
    vorbis_analysis_headerout :: proc(v: ^vorbis_dsp_state, vc: ^vorbis_comment,
                                    op: ^ogg.ogg_packet, op_comm: ^ogg.ogg_packet,
                                    op_code: ^ogg.ogg_packet) -> c.int ---
    vorbis_analysis_buffer :: proc(v: ^vorbis_dsp_state, vals: c.int) -> ^^c.float ---
    vorbis_analysis_wrote :: proc(v: ^vorbis_dsp_state, vals: c.int) -> c.int ---
    vorbis_analysis_blockout :: proc(v: ^vorbis_dsp_state, vb: ^vorbis_block) -> c.int ---
    vorbis_analysis :: proc(vb: ^vorbis_block, op: ^ogg.ogg_packet) -> c.int ---

    vorbis_bitrate_addblock :: proc(vb: ^vorbis_block) -> c.int ---
    vorbis_bitrate_flushpacket :: proc(vd: ^vorbis_dsp_state, op: ^ogg.ogg_packet) -> c.int ---

    // Synthesis layer
    vorbis_synthesis_idheader :: proc(op: ^ogg.ogg_packet) -> c.int ---
    vorbis_synthesis_headerin :: proc(vi: ^vorbis_info, vc: ^vorbis_comment,
                                    op: ^ogg.ogg_packet) -> c.int ---

    vorbis_synthesis_init :: proc(v: ^vorbis_dsp_state, vi: ^vorbis_info) -> c.int ---
    vorbis_synthesis_restart :: proc(v: ^vorbis_dsp_state) -> c.int ---
    vorbis_synthesis :: proc(vb: ^vorbis_block, op: ^ogg.ogg_packet) -> c.int ---
    vorbis_synthesis_trackonly :: proc(vb: ^vorbis_block, op: ^ogg.ogg_packet) -> c.int ---
    vorbis_synthesis_blockin :: proc(v: ^vorbis_dsp_state, vb: ^vorbis_block) -> c.int ---
    vorbis_synthesis_pcmout :: proc(v: ^vorbis_dsp_state, pcm: ^^^c.float) -> c.int ---
    vorbis_synthesis_lapout :: proc(v: ^vorbis_dsp_state, pcm: ^^^c.float) -> c.int ---
    vorbis_synthesis_read :: proc(v: ^vorbis_dsp_state, samples: c.int) -> c.int ---
    vorbis_packet_blocksize :: proc(vi: ^vorbis_info, op: ^ogg.ogg_packet) -> c.long ---

    vorbis_synthesis_halfrate :: proc(v: ^vorbis_info, flag: c.int) -> c.int ---
    vorbis_synthesis_halfrate_p :: proc(v: ^vorbis_info) -> c.int ---
}

//codec.h end


// Original C macro definitions converted to Odin constants
OV_ECTL_RATEMANAGE_GET :: 0x10
OV_ECTL_RATEMANAGE_SET :: 0x11
OV_ECTL_RATEMANAGE_AVG :: 0x12
OV_ECTL_RATEMANAGE_HARD :: 0x13
OV_ECTL_RATEMANAGE2_GET :: 0x14
OV_ECTL_RATEMANAGE2_SET :: 0x15
OV_ECTL_LOWPASS_GET :: 0x20
OV_ECTL_LOWPASS_SET :: 0x21
OV_ECTL_IBLOCK_GET :: 0x30
OV_ECTL_IBLOCK_SET :: 0x31
OV_ECTL_COUPLING_GET :: 0x40
OV_ECTL_COUPLING_SET :: 0x41


@(default_calling_convention="c")
foreign lib {
    vorbis_encode_init :: proc(vi: ^vorbis_info, 
                       channels: c.long,
                       rate: c.long,
                       max_bitrate: c.long,
                       nominal_bitrate: c.long,
                       min_bitrate: c.long) -> c.int ---

    vorbis_encode_setup_managed :: proc(vi: ^vorbis_info,
                               channels: c.long,
                               rate: c.long,
                               max_bitrate: c.long,
                               nominal_bitrate: c.long,
                               min_bitrate: c.long) -> c.int ---

    vorbis_encode_setup_vbr :: proc(vi: ^vorbis_info,
                            channels: c.long,
                            rate: c.long,
                            quality: c.float) -> c.int ---

    vorbis_encode_init_vbr :: proc(vi: ^vorbis_info,
                           channels: c.long,
                           rate: c.long,
                           base_quality: c.float) -> c.int ---

    vorbis_encode_setup_init :: proc(vi: ^vorbis_info) -> c.int ---

    vorbis_encode_ctl :: proc(vi: ^vorbis_info, number: c.int, arg: rawptr) -> c.int ---
}

ovectl_ratemanage_arg :: struct {
    management_active: c.int,
    bitrate_hard_min: c.long,
    bitrate_hard_max: c.long,
    bitrate_hard_window: c.double,
    bitrate_av_lo: c.long,
    bitrate_av_hi: c.long,
    bitrate_av_window: c.double,
    bitrate_av_window_center: c.double,
}

ovectl_ratemanage2_arg :: struct {
    management_active: c.int,
    bitrate_limit_min_kbps: c.long,
    bitrate_limit_max_kbps: c.long,
    bitrate_limit_reservoir_bits: c.long,
    bitrate_limit_reservoir_bias: c.double,
    bitrate_average_kbps: c.long,
    bitrate_average_damping: c.double,
}