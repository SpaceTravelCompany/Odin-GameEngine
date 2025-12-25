package ogg

import "base:library"
import "core:c"

LIB :: library.LIBPATH + "/libogg" + library.ARCH_end
foreign import lib {
	LIB,
}

// ogg_types.h

ogg_int32_t :: c.int
ogg_int64_t :: c.int64_t
ogg_int8_t :: c.char
ogg_int16_t :: c.int16_t

ogg_uint32_t :: c.uint
ogg_uint64_t :: c.uint64_t
ogg_uint8_t :: byte
ogg_uint16_t :: c.uint16_t

// ogg_types.h end


ogg_iovec_t :: struct {
    iov_base:rawptr,
    iov_len:c.size_t,
}
  
oggpack_buffer :: struct {
    endbyte:c.long,
    endbit:c.int,
  
    buffer:[^]byte,
    ptr:[^]byte,
    storage:c.long,
}
  
  /* ogg_page is used to encapsulate the data in one Ogg bitstream page *****/
  
ogg_page :: struct {
    header:[^]byte,
    header_len:c.long,
    body:[^]byte,
    body_len:c.long,
}
  
  /* ogg_stream_state contains the current encode/decode state of a logical
     Ogg bitstream **********************************************************/
  
ogg_stream_state :: struct {
    body_data:[^]byte,    /* bytes from packet bodies */
    body_storage: c.long,    // storage elements allocated
    body_fill: c.long,       // elements stored; fill mark
    body_returned: c.long,   // elements of fill returned
    
    lacing_vals: [^]c.int,   // The values that will go to the segment table
    granule_vals: [^]ogg_int64_t,    // granulepos values for headers. Not compact
                            // this way, but it is simple coupled to the
                            // lacing fifo
    
    lacing_storage: c.long,
    lacing_fill: c.long,
    lacing_packet: c.long,
    lacing_returned: c.long,
    
    header: [282]byte,         // working space for header encode
    header_fill: c.int,
    
    e_o_s: c.int,           // set when we have buffered the last packet in the
                            // logical bitstream
    b_o_s: c.int,           // set after we've written the initial page
                            // of a logical bitstream
    
    serialno: c.long,
    pageno: c.long,
    packetno: ogg_int64_t,          // sequence number for decode; the framing
                            // knows where there's a hole in the data,
                            // but we need coupling so that the codec
                            // (which is in a separate abstraction
                            // layer) also knows about the gap
    
    granulepos: ogg_int64_t,
  
}
  
  /* ogg_packet is used to encapsulate the data and metadata belonging
     to a single raw Ogg/Vorbis packet *************************************/
  
ogg_packet :: struct {
    packet: [^]byte,         // unsigned char pointer in C
    bytes: c.long,
    b_o_s: c.long,
    e_o_s: c.long,
    granulepos: ogg_int64_t,
    packetno: ogg_int64_t,  // sequence number for decode; the framing
                           // knows where there's a hole in the data,
                           // but we need coupling so that the codec
                           // (which is in a separate abstraction
                           // layer) also knows about the gap
}
  
ogg_sync_state :: struct {
    data: [^]byte,          // unsigned char pointer in C
    storage: c.int,
    fill: c.int,
    returned: c.int,
    unsynced: c.int,
    headerbytes: c.int,
    bodybytes: c.int,
}

@(default_calling_convention="c")
foreign lib {
    // Ogg pack functions
    oggpack_writeinit :: proc(b: ^oggpack_buffer) ---
    oggpack_writecheck :: proc(b: ^oggpack_buffer) -> c.int ---
    oggpack_writetrunc :: proc(b: ^oggpack_buffer, bits: c.long) ---
    oggpack_writealign :: proc(b: ^oggpack_buffer) ---
    oggpack_writecopy :: proc(b: ^oggpack_buffer, source: rawptr, bits: c.long) ---
    oggpack_reset :: proc(b: ^oggpack_buffer) ---
    oggpack_writeclear :: proc(b: ^oggpack_buffer) ---
    oggpack_readinit :: proc(b: ^oggpack_buffer, buf: [^]byte, bytes: c.int) ---
    oggpack_write :: proc(b: ^oggpack_buffer, value: c.ulong, bits: c.int) ---
    oggpack_look :: proc(b: ^oggpack_buffer, bits: c.int) -> c.long ---
    oggpack_look1 :: proc(b: ^oggpack_buffer) -> c.long ---
    oggpack_adv :: proc(b: ^oggpack_buffer, bits: c.int) ---
    oggpack_adv1 :: proc(b: ^oggpack_buffer) ---
    oggpack_read :: proc(b: ^oggpack_buffer, bits: c.int) -> c.long ---
    oggpack_read1 :: proc(b: ^oggpack_buffer) -> c.long ---
    oggpack_bytes :: proc(b: ^oggpack_buffer) -> c.long ---
    oggpack_bits :: proc(b: ^oggpack_buffer) -> c.long ---
    oggpack_get_buffer :: proc(b: ^oggpack_buffer) -> [^]byte ---

    // OggpackB functions (big-endian version)
    oggpackB_writeinit :: proc(b: ^oggpack_buffer) ---
    oggpackB_writecheck :: proc(b: ^oggpack_buffer) -> c.int ---
    oggpackB_writetrunc :: proc(b: ^oggpack_buffer, bits: c.long) ---
    oggpackB_writealign :: proc(b: ^oggpack_buffer) ---
    oggpackB_writecopy :: proc(b: ^oggpack_buffer, source: rawptr, bits: c.long) ---
    oggpackB_reset :: proc(b: ^oggpack_buffer) ---
    oggpackB_writeclear :: proc(b: ^oggpack_buffer) ---
    oggpackB_readinit :: proc(b: ^oggpack_buffer, buf: [^]byte, bytes: c.int) ---
    oggpackB_write :: proc(b: ^oggpack_buffer, value: c.ulong, bits: c.int) ---
    oggpackB_look :: proc(b: ^oggpack_buffer, bits: c.int) -> c.long ---
    oggpackB_look1 :: proc(b: ^oggpack_buffer) -> c.long ---
    oggpackB_adv :: proc(b: ^oggpack_buffer, bits: c.int) ---
    oggpackB_adv1 :: proc(b: ^oggpack_buffer) ---
    oggpackB_read :: proc(b: ^oggpack_buffer, bits: c.int) -> c.long ---
    oggpackB_read1 :: proc(b: ^oggpack_buffer) -> c.long ---
    oggpackB_bytes :: proc(b: ^oggpack_buffer) -> c.long ---
    oggpackB_bits :: proc(b: ^oggpack_buffer) -> c.long ---
    oggpackB_get_buffer :: proc(b: ^oggpack_buffer) -> [^]byte ---

    // Ogg bitstream encoding primitives
    ogg_stream_packetin :: proc(os: ^ogg_stream_state, op: ^ogg_packet) -> c.int ---
    ogg_stream_iovecin :: proc(os: ^ogg_stream_state, iov: ^ogg_iovec_t, count: c.int, e_o_s: c.long, granulepos: ogg_int64_t) -> c.int ---
    ogg_stream_pageout :: proc(os: ^ogg_stream_state, og: ^ogg_page) -> c.int ---
    ogg_stream_pageout_fill :: proc(os: ^ogg_stream_state, og: ^ogg_page, nfill: c.int) -> c.int ---
    ogg_stream_flush :: proc(os: ^ogg_stream_state, og: ^ogg_page) -> c.int ---
    ogg_stream_flush_fill :: proc(os: ^ogg_stream_state, og: ^ogg_page, nfill: c.int) -> c.int ---

    // Ogg bitstream decoding primitives
    ogg_sync_init :: proc(oy: ^ogg_sync_state) -> c.int ---
    ogg_sync_clear :: proc(oy: ^ogg_sync_state) -> c.int ---
    ogg_sync_reset :: proc(oy: ^ogg_sync_state) -> c.int ---
    ogg_sync_destroy :: proc(oy: ^ogg_sync_state) -> c.int ---
    ogg_sync_check :: proc(oy: ^ogg_sync_state) -> c.int ---
    ogg_sync_buffer :: proc(oy: ^ogg_sync_state, size: c.long) -> cstring ---
    ogg_sync_wrote :: proc(oy: ^ogg_sync_state, bytes: c.long) -> c.int ---
    ogg_sync_pageseek :: proc(oy: ^ogg_sync_state, og: ^ogg_page) -> c.long ---
    ogg_sync_pageout :: proc(oy: ^ogg_sync_state, og: ^ogg_page) -> c.int ---
    ogg_stream_pagein :: proc(os: ^ogg_stream_state, og: ^ogg_page) -> c.int ---
    ogg_stream_packetout :: proc(os: ^ogg_stream_state, op: ^ogg_packet) -> c.int ---
    ogg_stream_packetpeek :: proc(os: ^ogg_stream_state, op: ^ogg_packet) -> c.int ---

    // General Ogg bitstream primitives
    ogg_stream_init :: proc(os: ^ogg_stream_state, serialno: c.int) -> c.int ---
    ogg_stream_clear :: proc(os: ^ogg_stream_state) -> c.int ---
    ogg_stream_reset :: proc(os: ^ogg_stream_state) -> c.int ---
    ogg_stream_reset_serialno :: proc(os: ^ogg_stream_state, serialno: c.int) -> c.int ---
    ogg_stream_destroy :: proc(os: ^ogg_stream_state) -> c.int ---
    ogg_stream_check :: proc(os: ^ogg_stream_state) -> c.int ---
    ogg_stream_eos :: proc(os: ^ogg_stream_state) -> c.int ---

    ogg_page_checksum_set :: proc(og: ^ogg_page) ---

    ogg_page_version :: proc(og: ^ogg_page) -> c.int ---
    ogg_page_continued :: proc(og: ^ogg_page) -> c.int ---
    ogg_page_bos :: proc(og: ^ogg_page) -> c.int ---
    ogg_page_eos :: proc(og: ^ogg_page) -> c.int ---
    ogg_page_granulepos :: proc(og: ^ogg_page) -> ogg_int64_t ---
    ogg_page_serialno :: proc(og: ^ogg_page) -> c.int ---
    ogg_page_pageno :: proc(og: ^ogg_page) -> c.long ---
    ogg_page_packets :: proc(og: ^ogg_page) -> c.int ---

    ogg_packet_clear :: proc(op: ^ogg_packet) ---
}