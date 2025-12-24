//!Not Tested Yet (xfitgd)
// Bindings for [[bzip2 ; https://www.sourceware.org/bzip2/]]
package bzip2

import "core:c"
import "base:library"

BZIP2_LIB :: #directory + library.LIBPATH + "/libbz2" + library.ARCH_end

foreign import lib {
	BZIP2_LIB,
}

// Bzip2 compression levels
BLOCK_SIZE_100K_MIN :: 1
BLOCK_SIZE_100K_MAX :: 9
BLOCK_SIZE_100K_DEFAULT :: 9

// Bzip2 verbosity
VERBOSITY_SILENT :: 0
VERBOSITY_NORMAL :: 1
VERBOSITY_VERBOSE :: 2
VERBOSITY_VERY_VERBOSE :: 3
VERBOSITY_MAX :: 4

// Bzip2 work factor
WORK_FACTOR_DEFAULT :: 30
WORK_FACTOR_MAX :: 250

// Bzip2 operation results
BZ_OK                :: 0
BZ_RUN_OK            :: 1
BZ_FLUSH_OK           :: 2
BZ_FINISH_OK          :: 3
BZ_STREAM_END         :: 4
BZ_SEQUENCE_ERROR     :: -1
BZ_PARAM_ERROR        :: -2
BZ_MEM_ERROR          :: -3
BZ_DATA_ERROR         :: -4
BZ_DATA_ERROR_MAGIC   :: -5
BZ_IO_ERROR           :: -6
BZ_UNEXPECTED_EOF     :: -7
BZ_OUTBUFF_FULL       :: -8
BZ_CONFIG_ERROR       :: -9

// Bzip2 stream structure
Stream :: struct {
	next_in:   [^]byte,
	avail_in:  c.uint,
	total_in_lo32: c.uint,
	total_in_hi32: c.uint,
	
	next_out:  [^]byte,
	avail_out: c.uint,
	total_out_lo32: c.uint,
	total_out_hi32: c.uint,
	
	state:     rawptr,
	
	bzalloc:   rawptr,
	bzfree:    rawptr,
	opaque:    rawptr,
}

@(default_calling_convention="c", link_prefix="BZ2_")
foreign lib {
	// Compress initialization
	bzCompressInit :: proc(
		strm: ^Stream,
		blockSize100k: c.int,
		verbosity: c.int,
		workFactor: c.int,
	) -> c.int ---
	
	// Compress data
	bzCompress :: proc(
		strm: ^Stream,
		action: c.int,
	) -> c.int ---
	
	// Compress end
	bzCompressEnd :: proc(strm: ^Stream) -> c.int ---
	
	// Decompress initialization
	bzDecompressInit :: proc(
		strm: ^Stream,
		verbosity: c.int,
		small: c.int,
	) -> c.int ---
	
	// Decompress data
	bzDecompress :: proc(strm: ^Stream) -> c.int ---
	
	// Decompress end
	bzDecompressEnd :: proc(strm: ^Stream) -> c.int ---
	
	// Buffer compress
	bzBuffToBuffCompress :: proc(
		dest: [^]byte,
		destLen: ^c.uint,
		source: [^]byte,
		sourceLen: c.uint,
		blockSize100k: c.int,
		verbosity: c.int,
		workFactor: c.int,
	) -> c.int ---
	
	// Buffer decompress
	bzBuffToBuffDecompress :: proc(
		dest: [^]byte,
		destLen: ^c.uint,
		source: [^]byte,
		sourceLen: c.uint,
		small: c.int,
		verbosity: c.int,
	) -> c.int ---
}

// Compression actions
ACTION_RUN    :: 0
ACTION_FLUSH  :: 1
ACTION_FINISH :: 2

