//!Not Tested Yet (xfitgd)
// Bindings for [[Brotli ; https://github.com/google/brotli]]
package brotli

import "core:c"
import "base:library"

BROTLI_COMMON_LIB :: library.LIBPATH + "/libbrotlicommon" + library.ARCH_end
BROTLI_DEC_LIB :: library.LIBPATH + "/libbrotlidec" + library.ARCH_end
BROTLI_ENC_LIB :: library.LIBPATH + "/libbrotlienc" + library.ARCH_end

foreign import lib {
	BROTLI_COMMON_LIB,
	BROTLI_DEC_LIB,
	BROTLI_ENC_LIB,
}

// Brotli quality levels
QUALITY_MIN :: 0
QUALITY_FAST_ONE_PASS_COMPRESSION :: 0
QUALITY_FAST_TWO_PASS_COMPRESSION :: 1
QUALITY_ZOPFLIFICATION :: 10
QUALITY_HQ_ZOPFLIFICATION :: 11
QUALITY_MAX :: 11
QUALITY_DEFAULT :: 11

// Brotli window bits
WINDOW_BITS_MIN :: 10
WINDOW_BITS_MAX :: 24
WINDOW_BITS_DEFAULT :: 22

// Brotli literal context modes
MODE_GENERIC :: 0
MODE_TEXT :: 1
MODE_FONT :: 2

// Brotli operation result
RESULT_ERROR :: 0
RESULT_SUCCESS :: 1
RESULT_NEEDS_MORE_INPUT :: 2
RESULT_NEEDS_MORE_OUTPUT :: 3

// Encoder operations
OPERATION_PROCESS :: 0
OPERATION_FLUSH :: 1
OPERATION_FINISH :: 2
OPERATION_EMIT_METADATA :: 3

// Decoder operations
DECODER_RESULT_ERROR :: 0
DECODER_RESULT_SUCCESS :: 1
DECODER_RESULT_NEEDS_MORE_INPUT :: 2
DECODER_RESULT_NEEDS_MORE_OUTPUT :: 3

// Encoder state
EncoderState :: struct {}

// Decoder state
DecoderState :: struct {}

@(default_calling_convention="c")
foreign lib {
	// Create encoder instance
	BrotliEncoderCreateInstance :: proc(alloc_func: rawptr, free_func: rawptr, opaque: rawptr) -> ^EncoderState ---
	
	// Compress data (one-shot)
	BrotliEncoderCompress :: proc(
		quality: c.int,
		lgwin: c.int,
		mode: c.int,
		input_size: c.size_t,
		input_buffer: [^]byte,
		encoded_size: ^c.size_t,
		encoded_buffer: [^]byte,
	) -> c.int ---
	
	// Compress stream
	BrotliEncoderCompressStream :: proc(
		s: ^EncoderState,
		op: c.int,
		available_in: ^c.size_t,
		next_in: ^[^]byte,
		available_out: ^c.size_t,
		next_out: ^[^]byte,
		total_out: ^c.size_t,
	) -> c.int ---
	
	// Finish stream
	BrotliEncoderFinishStream :: proc(
		s: ^EncoderState,
		available_out: ^c.size_t,
		next_out: ^[^]byte,
		total_out: ^c.size_t,
	) -> c.int ---
	
	// Destroy encoder instance
	BrotliEncoderDestroyInstance :: proc(s: ^EncoderState) ---
	
	// Check if encoder is finished
	BrotliEncoderIsFinished :: proc(s: ^EncoderState) -> c.int ---
	
	// Check if encoder has more output
	BrotliEncoderHasMoreOutput :: proc(s: ^EncoderState) -> c.int ---
	
	// Get maximum compressed size
	BrotliEncoderMaxCompressedSize :: proc(input_size: c.size_t) -> c.size_t ---
}

@(default_calling_convention="c")
foreign lib {
	// Create decoder instance
	BrotliDecoderCreateInstance :: proc(alloc_func: rawptr, free_func: rawptr, opaque: rawptr) -> ^DecoderState ---
	
	// Decompress data (one-shot)
	BrotliDecoderDecompress :: proc(
		encoded_size: c.size_t,
		encoded_buffer: [^]byte,
		decoded_size: ^c.size_t,
		decoded_buffer: [^]byte,
	) -> c.int ---
	
	// Decompress stream
	BrotliDecoderDecompressStream :: proc(
		s: ^DecoderState,
		available_in: ^c.size_t,
		next_in: ^[^]byte,
		available_out: ^c.size_t,
		next_out: ^[^]byte,
		total_out: ^c.size_t,
	) -> c.int ---
	
	// Check if decoder is finished
	BrotliDecoderIsFinished :: proc(s: ^DecoderState) -> c.int ---
	
	// Check if decoder has more output
	BrotliDecoderHasMoreOutput :: proc(s: ^DecoderState) -> c.int ---
	
	// Destroy decoder instance
	BrotliDecoderDestroyInstance :: proc(s: ^DecoderState) ---
	
	// Get error code
	BrotliDecoderGetErrorCode :: proc(s: ^DecoderState) -> c.int ---
}

