package opus

import "base:library"
import "core:c"

LIBOPUS :: #directory + library.LIBPATH + "/libopus" + library.ARCH_end
foreign import lib { LIBOPUS }

// opus_types.h


opus_int :: c.int
opus_int32 :: c.int
opus_int64 :: c.int64_t
opus_int8 :: c.char
opus_int16 :: c.int16_t

opus_uint :: c.uint
opus_uint32 :: c.uint
opus_uint64 :: c.uint64_t
opus_uint8 :: byte
opus_uint16 :: c.uint16_t

// opus_types.h end

// opus_define.h


/** No error @hideinitializer*/
OPUS_OK :: 0
/** One or more invalid/out of range arguments @hideinitializer*/
OPUS_BAD_ARG :: -1
/** Not enough bytes allocated in the buffer @hideinitializer*/
OPUS_BUFFER_TOO_SMALL :: -2
/** An internal error was detected @hideinitializer*/
OPUS_INTERNAL_ERROR :: -3
/** The compressed data passed is corrupted @hideinitializer*/
OPUS_INVALID_PACKET :: -4
/** Invalid/unsupported request number @hideinitializer*/
OPUS_UNIMPLEMENTED :: -5
/** An encoder or decoder structure is invalid or already freed @hideinitializer*/
OPUS_INVALID_STATE :: -6
/** Memory allocation has failed @hideinitializer*/
OPUS_ALLOC_FAIL :: -7


/** These are the actual Encoder CTL ID numbers.
  * They should not be used directly by applications.
  * In general, SETs should be even and GETs should be odd.*/


OPUS_SET_APPLICATION_REQUEST    ::     4000
OPUS_GET_APPLICATION_REQUEST    ::     4001
OPUS_SET_BITRATE_REQUEST         ::    4002
OPUS_GET_BITRATE_REQUEST          ::   4003
OPUS_SET_MAX_BANDWIDTH_REQUEST   ::    4004
OPUS_GET_MAX_BANDWIDTH_REQUEST    ::   4005
OPUS_SET_VBR_REQUEST           ::      4006
OPUS_GET_VBR_REQUEST            ::     4007
OPUS_SET_BANDWIDTH_REQUEST      ::     4008
OPUS_GET_BANDWIDTH_REQUEST       ::    4009
OPUS_SET_COMPLEXITY_REQUEST       ::   4010
OPUS_GET_COMPLEXITY_REQUEST      ::    4011
OPUS_SET_INBAND_FEC_REQUEST      ::    4012
OPUS_GET_INBAND_FEC_REQUEST        ::  4013
OPUS_SET_PACKET_LOSS_PERC_REQUEST  ::  4014
OPUS_GET_PACKET_LOSS_PERC_REQUEST ::   4015
OPUS_SET_DTX_REQUEST               ::  4016
OPUS_GET_DTX_REQUEST              ::   4017
OPUS_SET_VBR_CONSTRAINT_REQUEST   ::   4020
OPUS_GET_VBR_CONSTRAINT_REQUEST    ::  4021
OPUS_SET_FORCE_CHANNELS_REQUEST   ::   4022
OPUS_GET_FORCE_CHANNELS_REQUEST   ::   4023
OPUS_SET_SIGNAL_REQUEST          ::    4024
OPUS_GET_SIGNAL_REQUEST          ::    4025
OPUS_GET_LOOKAHEAD_REQUEST       ::    4027
/*OPUS_RESET_STATE :: 4028 */


OPUS_GET_SAMPLE_RATE_REQUEST      ::   4029
OPUS_GET_FINAL_RANGE_REQUEST      ::   4031
OPUS_GET_PITCH_REQUEST           ::    4033
OPUS_SET_GAIN_REQUEST          ::      4034
/* Should have been 4035 */
OPUS_GET_GAIN_REQUEST         ::       4045 
OPUS_SET_LSB_DEPTH_REQUEST      ::     4036
OPUS_GET_LSB_DEPTH_REQUEST      ::     4037
OPUS_GET_LAST_PACKET_DURATION_REQUEST  :: 4039
OPUS_SET_EXPERT_FRAME_DURATION_REQUEST  :: 4040
OPUS_GET_EXPERT_FRAME_DURATION_REQUEST  :: 4041
OPUS_SET_PREDICTION_DISABLED_REQUEST  :: 4042
OPUS_GET_PREDICTION_DISABLED_REQUEST  :: 4043
/* Don't use 4045, it's already taken by OPUS_GET_GAIN_REQUEST */


OPUS_SET_PHASE_INVERSION_DISABLED_REQUEST  :: 4046
OPUS_GET_PHASE_INVERSION_DISABLED_REQUEST  :: 4047
OPUS_GET_IN_DTX_REQUEST           ::    4049
OPUS_SET_DRED_DURATION_REQUEST  :: 4050
OPUS_GET_DRED_DURATION_REQUEST  :: 4051
OPUS_SET_DNN_BLOB_REQUEST  :: 4052
/*OPUS_GET_DNN_BLOB_REQUEST   :: 4053 */


/** @defgroup opus_ctlvalues Pre-defined values for CTL interface
  * @see opus_genericctls, opus_encoderctls
  * @{
  */
/* Values for the various encoder CTLs */
OPUS_AUTO           ::                -1000 /**<Auto/default setting @hideinitializer*/
OPUS_BITRATE_MAX    ::                   -1 /**<Maximum bitrate @hideinitializer*/

/** Best for most VoIP/videoconference applications where listening quality and intelligibility matter most
 * @hideinitializer */
OPUS_APPLICATION_VOIP   ::             2048
/** Best for broadcast/high-fidelity application where the decoded audio should be as close as possible to the input
 * @hideinitializer */
OPUS_APPLICATION_AUDIO   ::            2049
/** Only use when lowest-achievable latency is what matters most. Voice-optimized modes cannot be used.
 * @hideinitializer */
OPUS_APPLICATION_RESTRICTED_LOWDELAY :: 2051

/**< Signal being encoded is voice */
OPUS_SIGNAL_VOICE        ::            3001
/**< Signal being encoded is music */
OPUS_SIGNAL_MUSIC        ::            3002
/**< 4 kHz bandpass @hideinitializer*/
OPUS_BANDWIDTH_NARROWBAND       ::     1101
/**< 6 kHz bandpass @hideinitializer*/
OPUS_BANDWIDTH_MEDIUMBAND       ::     1102
/**< 8 kHz bandpass @hideinitializer*/
OPUS_BANDWIDTH_WIDEBAND         ::     1103
/**<12 kHz bandpass @hideinitializer*/
OPUS_BANDWIDTH_SUPERWIDEBAND    ::     1104
/**<20 kHz bandpass @hideinitializer*/
OPUS_BANDWIDTH_FULLBAND         ::     1105 

/**< Select frame size from the argument (default) */
OPUS_FRAMESIZE_ARG :: 5000
/**< Use 2.5 ms frames */
OPUS_FRAMESIZE_2_5_MS :: 5001
/**< Use 5 ms frames */
OPUS_FRAMESIZE_5_MS :: 5002
/**< Use 10 ms frames */
OPUS_FRAMESIZE_10_MS :: 5003
/**< Use 20 ms frames */
OPUS_FRAMESIZE_20_MS :: 5004
/**< Use 40 ms frames */
OPUS_FRAMESIZE_40_MS :: 5005
/**< Use 60 ms frames */
OPUS_FRAMESIZE_60_MS :: 5006
/**< Use 80 ms frames */
OPUS_FRAMESIZE_80_MS :: 5007
/**< Use 100 ms frames */
OPUS_FRAMESIZE_100_MS :: 5008
/**< Use 120 ms frames */
OPUS_FRAMESIZE_120_MS :: 5009


/** Resets the codec state to be equivalent to a freshly initialized state.
  * This should be called when switching streams in order to prevent
  * the back to back decoding from giving different results from
  * one at a time decoding.
  * @hideinitializer */
OPUS_RESET_STATE :: 4028


// opus_define.h end


// opus.h


/** Opus encoder state.
  * This contains the complete state of an Opus encoder.
  * It is position independent and can be freely copied.
  * @see opus_encoder_create,opus_encoder_init
  */
OpusEncoder :: struct {}

/** Opus decoder state.
  * This contains the complete state of an Opus decoder.
  * It is position independent and can be freely copied.
  * @see opus_decoder_create,opus_decoder_init
  */
OpusDecoder :: struct {}

/** Opus DRED decoder.
  * This contains the complete state of an Opus DRED decoder.
  * It is position independent and can be freely copied.
  * @see opus_dred_decoder_create,opus_dred_decoder_init
  */
OpusDREDDecoder :: struct {}

/** Opus DRED state.
  * This contains the complete state of an Opus DRED packet.
  * It is position independent and can be freely copied.
  * @see opus_dred_create,opus_dred_init
  */
OpusDRED :: struct {}

/** @defgroup opus_repacketizer Repacketizer
* @{
*
* The repacketizer can be used to merge multiple Opus packets into a single
* packet or alternatively to split Opus packets that have previously been
* merged. Splitting valid Opus packets is always guaranteed to succeed,
* whereas merging valid packets only succeeds if all frames have the same
* mode, bandwidth, and frame size, and when the total duration of the merged
* packet is no more than 120 ms. The 120 ms limit comes from the
* specification and limits decoder memory requirements at a point where
* framing overhead becomes negligible.
*
* The repacketizer currently only operates on elementary Opus
* streams. It will not manipualte multistream packets successfully, except in
* the degenerate case where they consist of data from a single stream.
*
* The repacketizing process starts with creating a repacketizer state, either
* by calling opus_repacketizer_create() or by allocating the memory yourself,
* e.g.,
* @code
* OpusRepacketizer *rp ---
* rp = (OpusRepacketizer*)malloc(opus_repacketizer_get_size()) ---
* if (rp != NULL)
*     opus_repacketizer_init(rp) ---
* @endcode
*
* Then the application should submit packets with opus_repacketizer_cat(),
* extract new packets with opus_repacketizer_out() or
* opus_repacketizer_out_range(), and then reset the state for the next set of
* input packets via opus_repacketizer_init().
*
* For example, to split a sequence of packets into individual frames:
* @code
* unsigned char *data ---
* int len ---
* while (get_next_packet(&data, &len))
* {
*   unsigned char out[1276] ---
*   opus_int32 out_len ---
*   int nb_frames ---
*   int err ---
*   int i ---
*   err = opus_repacketizer_cat(rp, data, len) ---
*   if (err != OPUS_OK)
*   {
*     release_packet(data) ---
*     return err ---
*   }
*   nb_frames = opus_repacketizer_get_nb_frames(rp) ---
*   for (i = 0 --- i < nb_frames --- i++)
*   {
*     out_len = opus_repacketizer_out_range(rp, i, i+1, out, sizeof(out)) ---
*     if (out_len < 0)
*     {
*        release_packet(data) ---
*        return (int)out_len ---
*     }
*     output_next_packet(out, out_len) ---
*   }
*   opus_repacketizer_init(rp) ---
*   release_packet(data) ---
* }
* @endcode
*
* Alternatively, to combine a sequence of frames into packets that each
* contain up to <code>TARGET_DURATION_MS</code> milliseconds of data:
* @code
* // The maximum number of packets with duration TARGET_DURATION_MS occurs
* // when the frame size is 2.5 ms, for a total of (TARGET_DURATION_MS*2/5)
* // packets.
* unsigned char *data[(TARGET_DURATION_MS*2/5)+1] ---
* opus_int32 len[(TARGET_DURATION_MS*2/5)+1] ---
* int nb_packets ---
* unsigned char out[1277*(TARGET_DURATION_MS*2/2)] ---
* opus_int32 out_len ---
* int prev_toc ---
* nb_packets = 0 ---
* while (get_next_packet(data+nb_packets, len+nb_packets))
* {
*   int nb_frames ---
*   int err ---
*   nb_frames = opus_packet_get_nb_frames(data[nb_packets], len[nb_packets]) ---
*   if (nb_frames < 1)
*   {
*     release_packets(data, nb_packets+1) ---
*     return nb_frames ---
*   }
*   nb_frames += opus_repacketizer_get_nb_frames(rp) ---
*   // If adding the next packet would exceed our target, or it has an
*   // incompatible TOC sequence, output the packets we already have before
*   // submitting it.
*   // N.B., The nb_packets > 0 check ensures we've submitted at least one
*   // packet since the last call to opus_repacketizer_init(). Otherwise a
*   // single packet longer than TARGET_DURATION_MS would cause us to try to
*   // output an (invalid) empty packet. It also ensures that prev_toc has
*   // been set to a valid value. Additionally, len[nb_packets] > 0 is
*   // guaranteed by the call to opus_packet_get_nb_frames() above, so the
*   // reference to data[nb_packets][0] should be valid.
*   if (nb_packets > 0 && (
*       ((prev_toc & 0xFC) != (data[nb_packets][0] & 0xFC)) ||
*       opus_packet_get_samples_per_frame(data[nb_packets], 48000)*nb_frames >
*       TARGET_DURATION_MS*48))
*   {
*     out_len = opus_repacketizer_out(rp, out, sizeof(out)) ---
*     if (out_len < 0)
*     {
*        release_packets(data, nb_packets+1) ---
*        return (int)out_len ---
*     }
*     output_next_packet(out, out_len) ---
*     opus_repacketizer_init(rp) ---
*     release_packets(data, nb_packets) ---
*     data[0] = data[nb_packets] ---
*     len[0] = len[nb_packets] ---
*     nb_packets = 0 ---
*   }
*   err = opus_repacketizer_cat(rp, data[nb_packets], len[nb_packets]) ---
*   if (err != OPUS_OK)
*   {
*     release_packets(data, nb_packets+1) ---
*     return err ---
*   }
*   prev_toc = data[nb_packets][0] ---
*   nb_packets++ ---
* }
* // Output the final, partial packet.
* if (nb_packets > 0)
* {
*   out_len = opus_repacketizer_out(rp, out, sizeof(out)) ---
*   release_packets(data, nb_packets) ---
*   if (out_len < 0)
*     return (int)out_len ---
*   output_next_packet(out, out_len) ---
* }
* @endcode
*
* An alternate way of merging packets is to simply call opus_repacketizer_cat()
* unconditionally until it fails. At that point, the merged packet can be
* obtained with opus_repacketizer_out() and the input packet for which
* opus_repacketizer_cat() needs to be re-added to a newly reinitialized
* repacketizer state.
*/
OpusRepacketizer :: struct {}

// opus.h end

// opus_multistream.h

OPUS_MULTISTREAM_GET_ENCODER_STATE_REQUEST :: 5120
OPUS_MULTISTREAM_GET_DECODER_STATE_REQUEST :: 5122

OpusMSEncoder :: struct {}
OpusMSDecoder :: struct {}

// opus_multistream.h end

// opus_projection.h

OPUS_PROJECTION_GET_DEMIXING_MATRIX_GAIN_REQUEST :: 6001
OPUS_PROJECTION_GET_DEMIXING_MATRIX_SIZE_REQUEST :: 6003
OPUS_PROJECTION_GET_DEMIXING_MATRIX_REQUEST :: 6005

OpusProjectionEncoder :: struct {}
OpusProjectionDecoder :: struct {}

// opus_projection.h end

@(default_calling_convention="c")
foreign lib {
    // opus_define.h
    opus_strerror :: proc (error: c.int) -> cstring ---
    opus_get_version_string :: proc () -> cstring ---

    // opus.h


    /** Gets the size of an <code>OpusEncoder</code> structure.
    * @param[in] channels <tt>int</tt>: Number of channels.
    *                                   This must be 1 or 2.
    * @returns The size in bytes.
    */
    opus_encoder_get_size :: proc(channels: c.int) -> c.int ---

    /** Allocates and initializes an encoder state.
 * There are three coding modes:
 *
 * @ref OPUS_APPLICATION_VOIP gives best quality at a given bitrate for voice
 *    signals. It enhances the  input signal by high-pass filtering and
 *    emphasizing formants and harmonics. Optionally  it includes in-band
 *    forward error correction to protect against packet loss. Use this
 *    mode for typical VoIP applications. Because of the enhancement,
 *    even at high bitrates the output may sound different from the input.
 *
 * @ref OPUS_APPLICATION_AUDIO gives best quality at a given bitrate for most
 *    non-voice signals like music. Use this mode for music and mixed
 *    (music/voice) content, broadcast, and applications requiring less
 *    than 15 ms of coding delay.
 *
 * @ref OPUS_APPLICATION_RESTRICTED_LOWDELAY configures low-delay mode that
 *    disables the speech-optimized mode in exchange for slightly reduced delay.
 *    This mode can only be set on an newly initialized or freshly reset encoder
 *    because it changes the codec delay.
 *
 * This is useful when the caller knows that the speech-optimized modes will not be needed (use with caution).
 * @param [in] Fs <tt>opus_int32</tt>: Sampling rate of input signal (Hz)
 *                                     This must be one of 8000, 12000, 16000,
 *                                     24000, or 48000.
 * @param [in] channels <tt>int</tt>: Number of channels (1 or 2) in input signal
 * @param [in] application <tt>int</tt>: Coding mode (one of @ref OPUS_APPLICATION_VOIP, @ref OPUS_APPLICATION_AUDIO, or @ref OPUS_APPLICATION_RESTRICTED_LOWDELAY)
 * @param [out] error <tt>int*</tt>: @ref opus_errorcodes
 * @note Regardless of the sampling rate and number channels selected, the Opus encoder
 * can switch to a lower audio bandwidth or number of channels if the bitrate
 * selected is too low. This also means that it is safe to always use 48 kHz stereo input
 * and let the encoder optimize the encoding.
 */
  @(require_results) opus_encoder_create :: proc(Fs:opus_int32, channels:int, application:c.int, error:^c.int) -> ^OpusEncoder ---

    /** Initializes a previously allocated encoder state
  * The memory pointed to by st must be at least the size returned by opus_encoder_get_size().
  * This is intended for applications which use their own allocator instead of malloc.
  * @see opus_encoder_create(),opus_encoder_get_size()
  * To reset a previously initialized state, use the #OPUS_RESET_STATE CTL.
  * @param [in] st <tt>OpusEncoder*</tt>: Encoder state
  * @param [in] Fs <tt>opus_int32</tt>: Sampling rate of input signal (Hz)
 *                                      This must be one of 8000, 12000, 16000,
 *                                      24000, or 48000.
  * @param [in] channels <tt>int</tt>: Number of channels (1 or 2) in input signal
  * @param [in] application <tt>int</tt>: Coding mode (one of OPUS_APPLICATION_VOIP, OPUS_APPLICATION_AUDIO, or OPUS_APPLICATION_RESTRICTED_LOWDELAY)
  * @retval #OPUS_OK Success or @ref opus_errorcodes
  */
  opus_encoder_init :: proc(st:^OpusEncoder, Fs:opus_int32, channels:c.int, application:c.int) -> c.int ---

  /** Encodes an Opus frame.
  * @param [in] st <tt>OpusEncoder*</tt>: Encoder state
  * @param [in] pcm <tt>opus_int16*</tt>: Input signal (interleaved if 2 channels). length is frame_size*channels*sizeof(opus_int16)
  * @param [in] frame_size <tt>int</tt>: Number of samples per channel in the
  *                                      input signal.
  *                                      This must be an Opus frame size for
  *                                      the encoder's sampling rate.
  *                                      For example, at 48 kHz the permitted
  *                                      values are 120, 240, 480, 960, 1920,
  *                                      and 2880.
  *                                      Passing in a duration of less than
  *                                      10 ms (480 samples at 48 kHz) will
  *                                      prevent the encoder from using the LPC
  *                                      or hybrid modes.
  * @param [out] data <tt>unsigned char*</tt>: Output payload.
  *                                            This must contain storage for at
  *                                            least \a max_data_bytes.
  * @param [in] max_data_bytes <tt>opus_int32</tt>: Size of the allocated
  *                                                 memory for the output
  *                                                 payload. This may be
  *                                                 used to impose an upper limit on
  *                                                 the instant bitrate, but should
  *                                                 not be used as the only bitrate
  *                                                 control. Use #OPUS_SET_BITRATE to
  *                                                 control the bitrate.
  * @returns The length of the encoded packet (in bytes) on success or a
  *          negative error code (see @ref opus_errorcodes) on failure.
  */
  @(require_results) opus_encode :: proc(st:^OpusEncoder, pcm:[^]opus_int16, frame_size:c.int, data:[^]byte, max_data_bytes:opus_int32) -> opus_int32 ---

  /** Encodes an Opus frame from floating point input.
  * @param [in] st <tt>OpusEncoder*</tt>: Encoder state
  * @param [in] pcm <tt>float*</tt>: Input in float format (interleaved if 2 channels), with a normal range of +/-1.0.
  *          Samples with a range beyond +/-1.0 are supported but will
  *          be clipped by decoders using the integer API and should
  *          only be used if it is known that the far end supports
  *          extended dynamic range.
  *          length is frame_size*channels*sizeof(float)
  * @param [in] frame_size <tt>int</tt>: Number of samples per channel in the
  *                                      input signal.
  *                                      This must be an Opus frame size for
  *                                      the encoder's sampling rate.
  *                                      For example, at 48 kHz the permitted
  *                                      values are 120, 240, 480, 960, 1920,
  *                                      and 2880.
  *                                      Passing in a duration of less than
  *                                      10 ms (480 samples at 48 kHz) will
  *                                      prevent the encoder from using the LPC
  *                                      or hybrid modes.
  * @param [out] data <tt>unsigned char*</tt>: Output payload.
  *                                            This must contain storage for at
  *                                            least \a max_data_bytes.
  * @param [in] max_data_bytes <tt>opus_int32</tt>: Size of the allocated
  *                                                 memory for the output
  *                                                 payload. This may be
  *                                                 used to impose an upper limit on
  *                                                 the instant bitrate, but should
  *                                                 not be used as the only bitrate
  *                                                 control. Use #OPUS_SET_BITRATE to
  *                                                 control the bitrate.
  * @returns The length of the encoded packet (in bytes) on success or a
  *          negative error code (see @ref opus_errorcodes) on failure.
  */
  @(require_results) opus_encode_float :: proc(st:^OpusEncoder, pcm:[^]c.float, frame_size:c.int, data:[^]byte, max_data_bytes:opus_int32) -> opus_int32 ---

  /** Frees an <code>OpusEncoder</code> allocated by opus_encoder_create().
  * @param[in] st <tt>OpusEncoder*</tt>: State to be freed.
  */
  opus_encoder_destroy :: proc(st:^OpusEncoder) ---

  /** Perform a CTL function on an Opus encoder.
  *
  * Generally the request and subsequent arguments are generated
  * by a convenience macro.
  * @param st <tt>OpusEncoder*</tt>: Encoder state.
  * @param request This and all remaining parameters should be replaced by one
  *                of the convenience macros in @ref opus_genericctls or
  *                @ref opus_encoderctls.
  * @see opus_genericctls
  * @see opus_encoderctls
  */
  opus_encoder_ctl :: proc(st:^OpusEncoder, request:c.int, #c_vararg args: ..any) -> c.int ---

  /** Gets the size of an <code>OpusDecoder</code> structure.
  * @param [in] channels <tt>int</tt>: Number of channels.
  *                                    This must be 1 or 2.
  * @returns The size in bytes.
  */
  @(require_results) opus_decoder_get_size :: proc(channels:c.int) -> c.int ---

  /** Allocates and initializes a decoder state.
  * @param [in] Fs <tt>opus_int32</tt>: Sample rate to decode at (Hz).
  *                                     This must be one of 8000, 12000, 16000,
  *                                     24000, or 48000.
  * @param [in] channels <tt>int</tt>: Number of channels (1 or 2) to decode
  * @param [out] error <tt>int*</tt>: #OPUS_OK Success or @ref opus_errorcodes
  *
  * Internally Opus stores data at 48000 Hz, so that should be the default
  * value for Fs. However, the decoder can efficiently decode to buffers
  * at 8, 12, 16, and 24 kHz so if for some reason the caller cannot use
  * data at the full sample rate, or knows the compressed data doesn't
  * use the full frequency range, it can request decoding at a reduced
  * rate. Likewise, the decoder is capable of filling in either mono or
  * interleaved stereo pcm buffers, at the caller's request.
  */
  @(require_results) opus_decoder_create :: proc(Fs:opus_int32, channels:int, error:^c.int) -> ^OpusDecoder ---

  /** Initializes a previously allocated decoder state.
  * The state must be at least the size returned by opus_decoder_get_size().
  * This is intended for applications which use their own allocator instead of malloc. @see opus_decoder_create,opus_decoder_get_size
  * To reset a previously initialized state, use the #OPUS_RESET_STATE CTL.
  * @param [in] st <tt>OpusDecoder*</tt>: Decoder state.
  * @param [in] Fs <tt>opus_int32</tt>: Sampling rate to decode to (Hz).
  *                                     This must be one of 8000, 12000, 16000,
  *                                     24000, or 48000.
  * @param [in] channels <tt>int</tt>: Number of channels (1 or 2) to decode
  * @retval #OPUS_OK Success or @ref opus_errorcodes
  */
  opus_decoder_init :: proc(st:^OpusDecoder, Fs:opus_int32, channels:c.int) -> c.int ---

  /** Decode an Opus packet.
  * @param [in] st <tt>OpusDecoder*</tt>: Decoder state
  * @param [in] data <tt>char*</tt>: Input payload. Use a NULL pointer to indicate packet loss
  * @param [in] len <tt>opus_int32</tt>: Number of bytes in payload*
  * @param [out] pcm <tt>opus_int16*</tt>: Output signal (interleaved if 2 channels). length
  *  is frame_size*channels*sizeof(opus_int16)
  * @param [in] frame_size Number of samples per channel of available space in \a pcm.
  *  If this is less than the maximum packet duration (120ms --- 5760 for 48kHz), this function will
  *  not be capable of decoding some packets. In the case of PLC (data==NULL) or FEC (decode_fec=1),
  *  then frame_size needs to be exactly the duration of audio that is missing, otherwise the
  *  decoder will not be in the optimal state to decode the next incoming packet. For the PLC and
  *  FEC cases, frame_size <b>must</b> be a multiple of 2.5 ms.
  * @param [in] decode_fec <tt>int</tt>: Flag (0 or 1) to request that any in-band forward error correction data be
  *  decoded. If no such data is available, the frame is decoded as if it were lost.
  * @returns Number of decoded samples or @ref opus_errorcodes
  */
  @(require_results) opus_decode :: proc(st:^OpusDecoder, data:[^]byte, len:opus_int32, pcm:[^]opus_int16, frame_size:c.int, decode_fec:c.int) -> c.int ---

  /** Decode an Opus packet with floating point output.
  * @param [in] st <tt>OpusDecoder*</tt>: Decoder state
  * @param [in] data <tt>char*</tt>: Input payload. Use a NULL pointer to indicate packet loss
  * @param [in] len <tt>opus_int32</tt>: Number of bytes in payload
  * @param [out] pcm <tt>float*</tt>: Output signal (interleaved if 2 channels). length
  *  is frame_size*channels*sizeof(float)
  * @param [in] frame_size Number of samples per channel of available space in \a pcm.
  *  If this is less than the maximum packet duration (120ms --- 5760 for 48kHz), this function will
  *  not be capable of decoding some packets. In the case of PLC (data==NULL) or FEC (decode_fec=1),
  *  then frame_size needs to be exactly the duration of audio that is missing, otherwise the
  *  decoder will not be in the optimal state to decode the next incoming packet. For the PLC and
  *  FEC cases, frame_size <b>must</b> be a multiple of 2.5 ms.
  * @param [in] decode_fec <tt>int</tt>: Flag (0 or 1) to request that any in-band forward error correction data be
  *  decoded. If no such data is available the frame is decoded as if it were lost.
  * @returns Number of decoded samples or @ref opus_errorcodes
  */
  @(require_results) opus_decode_float :: proc(st:^OpusDecoder, data:[^]byte, len:opus_int32, pcm:[^]c.float, frame_size:c.int, decode_fec:c.int) -> c.int ---

  /** Perform a CTL function on an Opus decoder.
  *
  * Generally the request and subsequent arguments are generated
  * by a convenience macro.
  * @param st <tt>OpusDecoder*</tt>: Decoder state.
  * @param request This and all remaining parameters should be replaced by one
  *                of the convenience macros in @ref opus_genericctls or
  *                @ref opus_decoderctls.
  * @see opus_genericctls
  * @see opus_decoderctls
  */
  opus_decoder_ctl :: proc(st:^OpusDecoder, request:c.int, #c_vararg args: ..any) -> c.int ---

  /** Frees an <code>OpusDecoder</code> allocated by opus_decoder_create().
  * @param[in] st <tt>OpusDecoder*</tt>: State to be freed.
  */
  opus_decoder_destroy :: proc(st:^OpusDecoder) ---

  /** Gets the size of an <code>OpusDREDDecoder</code> structure.
  * @returns The size in bytes.
  */
  opus_dred_decoder_get_size :: proc() -> c.int ---

  /** Allocates and initializes an OpusDREDDecoder state.
    * @param [out] error <tt>int*</tt>: #OPUS_OK Success or @ref opus_errorcodes
    */
  opus_dred_decoder_create :: proc(error:^c.int) -> ^OpusDREDDecoder ---

  /** Initializes an <code>OpusDREDDecoder</code> state.
    * @param[in] dec <tt>OpusDREDDecoder*</tt>: State to be initialized.
    */
  opus_dred_decoder_init :: proc(dec:^OpusDREDDecoder) -> c.int ---

  /** Frees an <code>OpusDREDDecoder</code> allocated by opus_dred_decoder_create().
    * @param[in] dec <tt>OpusDREDDecoder*</tt>: State to be freed.
    */
  opus_dred_decoder_destroy :: proc(dec:^OpusDREDDecoder) ---

  /** Perform a CTL function on an Opus DRED decoder.
    *
    * Generally the request and subsequent arguments are generated
    * by a convenience macro.
    * @param dred_dec <tt>OpusDREDDecoder*</tt>: DRED Decoder state.
    * @param request This and all remaining parameters should be replaced by one
    *                of the convenience macros in @ref opus_genericctls or
    *                @ref opus_decoderctls.
    * @see opus_genericctls
    * @see opus_decoderctls
    */
  opus_dred_decoder_ctl :: proc(dred_dec:^OpusDREDDecoder, request:c.int, #c_vararg args: ..any) -> c.int ---

  /** Gets the size of an <code>OpusDRED</code> structure.
    * @returns The size in bytes.
    */
  opus_dred_get_size :: proc() -> c.int ---

  /** Allocates and initializes a DRED state.
    * @param [out] error <tt>int*</tt>: #OPUS_OK Success or @ref opus_errorcodes
    */
  opus_dred_alloc :: proc(error:^c.int) -> OpusDRED ---

  /** Frees an <code>OpusDRED</code> allocated by opus_dred_create().
    * @param[in] dec <tt>OpusDRED*</tt>: State to be freed.
    */
  opus_dred_free :: proc(dec:^OpusDRED) ---

  /** Decode an Opus DRED packet.
    * @param [in] dred_dec <tt>OpusDRED*</tt>: DRED Decoder state
    * @param [in] dred <tt>OpusDRED*</tt>: DRED state
    * @param [in] data <tt>char*</tt>: Input payload
    * @param [in] len <tt>opus_int32</tt>: Number of bytes in payload
    * @param [in] max_dred_samples <tt>opus_int32</tt>: Maximum number of DRED samples that may be needed (if available in the packet).
    * @param [in] sampling_rate <tt>opus_int32</tt>: Sampling rate used for max_dred_samples argument. Needs not match the actual sampling rate of the decoder.
    * @param [out] dred_end <tt>opus_int32*</tt>: Number of non-encoded (silence) samples between the DRED timestamp and the last DRED sample.
    * @param [in] defer_processing <tt>int</tt>: Flag (0 or 1). If set to one, the CPU-intensive part of the DRED decoding is deferred until opus_dred_process() is called.
    * @returns Offset (positive) of the first decoded DRED samples, zero if no DRED is present, or @ref opus_errorcodes
    */
  opus_dred_parse :: proc(dred_dec:^OpusDREDDecoder,
    dred:^OpusDRED,
    data:[^]byte,
    len:opus_int32,
    max_dred_samples:opus_int32,
    sampling_rate:opus_int32,
    dred_end:c.int,
    defer_processing:c.int) -> c.int ---

  /** Finish decoding an Opus DRED packet. The function only needs to be called if opus_dred_parse() was called with defer_processing=1.
    * The source and destination will often be the same DRED state.
    * @param [in] dred_dec <tt>OpusDRED*</tt>: DRED Decoder state
    * @param [in] src <tt>OpusDRED*</tt>: Source DRED state to start the processing from.
    * @param [out] dst <tt>OpusDRED*</tt>: Destination DRED state to store the updated state after processing.
    * @returns @ref opus_errorcodes
    */
  opus_dred_process :: proc(dred_dec:^OpusDREDDecoder, src:^OpusDRED, dst:^OpusDRED) -> c.int ---

  /** Decode audio from an Opus DRED packet with floating point output.
    * @param [in] st <tt>OpusDecoder*</tt>: Decoder state
    * @param [in] dred <tt>OpusDRED*</tt>: DRED state
    * @param [in] dred_offset <tt>opus_int32</tt>: position of the redundancy to decode (in samples before the beginning of the real audio data in the packet).
    * @param [out] pcm <tt>opus_int16*</tt>: Output signal (interleaved if 2 channels). length
    *  is frame_size*channels*sizeof(opus_int16)
    * @param [in] frame_size Number of samples per channel to decode in \a pcm.
    *  frame_size <b>must</b> be a multiple of 2.5 ms.
    * @returns Number of decoded samples or @ref opus_errorcodes
    */
  opus_decoder_dred_decode :: proc(st:^OpusDecoder, dred:^OpusDRED, dred_offset:opus_int32, pcm:[^]opus_int16, frame_size:opus_int32) -> c.int ---

  /** Decode audio from an Opus DRED packet with floating point output.
    * @param [in] st <tt>OpusDecoder*</tt>: Decoder state
    * @param [in] dred <tt>OpusDRED*</tt>: DRED state
    * @param [in] dred_offset <tt>opus_int32</tt>: position of the redundancy to decode (in samples before the beginning of the real audio data in the packet).
    * @param [out] pcm <tt>float*</tt>: Output signal (interleaved if 2 channels). length
    *  is frame_size*channels*sizeof(float)
    * @param [in] frame_size Number of samples per channel to decode in \a pcm.
    *  frame_size <b>must</b> be a multiple of 2.5 ms.
    * @returns Number of decoded samples or @ref opus_errorcodes
    */
  opus_decoder_dred_decode_float :: proc(st:^OpusDecoder, dred:^OpusDRED, dred_offset:opus_int32, pcm:[^]c.float, frame_size:opus_int32) -> c.int ---


  /** Parse an opus packet into one or more frames.
    * Opus_decode will perform this operation internally so most applications do
    * not need to use this function.
    * This function does not copy the frames, the returned pointers are pointers into
    * the input packet.
    * @param [in] data <tt>char*</tt>: Opus packet to be parsed
    * @param [in] len <tt>opus_int32</tt>: size of data
    * @param [out] out_toc <tt>char*</tt>: TOC pointer
    * @param [out] frames <tt>char*[48]</tt> encapsulated frames
    * @param [out] size <tt>opus_int16[48]</tt> sizes of the encapsulated frames
    * @param [out] payload_offset <tt>int*</tt>: returns the position of the payload within the packet (in bytes)
    * @returns number of frames
    */
  opus_packet_parse :: proc(
    data:[^]byte,
    len:opus_int32,
    out_toc:^byte,
    frames:[^]byte,    //len 48
    size:[^]opus_int16,    //len 48
    payload_offset:^c.int
  ) -> c.int ---

  /** Gets the bandwidth of an Opus packet.
    * @param [in] data <tt>char*</tt>: Opus packet
    * @retval OPUS_BANDWIDTH_NARROWBAND Narrowband (4kHz bandpass)
    * @retval OPUS_BANDWIDTH_MEDIUMBAND Mediumband (6kHz bandpass)
    * @retval OPUS_BANDWIDTH_WIDEBAND Wideband (8kHz bandpass)
    * @retval OPUS_BANDWIDTH_SUPERWIDEBAND Superwideband (12kHz bandpass)
    * @retval OPUS_BANDWIDTH_FULLBAND Fullband (20kHz bandpass)
    * @retval OPUS_INVALID_PACKET The compressed data passed is corrupted or of an unsupported type
    */
  @(require_results) opus_packet_get_bandwidth :: proc(data:[^]byte) -> c.int ---

  /** Gets the number of samples per frame from an Opus packet.
    * @param [in] data <tt>char*</tt>: Opus packet.
    *                                  This must contain at least one byte of
    *                                  data.
    * @param [in] Fs <tt>opus_int32</tt>: Sampling rate in Hz.
    *                                     This must be a multiple of 400, or
    *                                     inaccurate results will be returned.
    * @returns Number of samples per frame.
    */
  @(require_results) opus_packet_get_samples_per_frame :: proc(data:[^]byte, Fs:opus_int32) -> c.int ---

  /** Gets the number of channels from an Opus packet.
    * @param [in] data <tt>char*</tt>: Opus packet
    * @returns Number of channels
    * @retval OPUS_INVALID_PACKET The compressed data passed is corrupted or of an unsupported type
    */
  @(require_results) opus_packet_get_nb_channels :: proc(data:[^]byte) -> c.int ---

  /** Gets the number of frames in an Opus packet.
    * @param [in] packet <tt>char*</tt>: Opus packet
    * @param [in] len <tt>opus_int32</tt>: Length of packet
    * @returns Number of frames
    * @retval OPUS_BAD_ARG Insufficient data was passed to the function
    * @retval OPUS_INVALID_PACKET The compressed data passed is corrupted or of an unsupported type
    */
  @(require_results) opus_packet_get_nb_frames :: proc(packet:[^]byte, len:opus_int32) -> c.int ---

  /** Gets the number of samples of an Opus packet.
    * @param [in] packet <tt>char*</tt>: Opus packet
    * @param [in] len <tt>opus_int32</tt>: Length of packet
    * @param [in] Fs <tt>opus_int32</tt>: Sampling rate in Hz.
    *                                     This must be a multiple of 400, or
    *                                     inaccurate results will be returned.
    * @returns Number of samples
    * @retval OPUS_BAD_ARG Insufficient data was passed to the function
    * @retval OPUS_INVALID_PACKET The compressed data passed is corrupted or of an unsupported type
    */
  @(require_results) opus_packet_get_nb_samples :: proc(packet:[^]byte, len:opus_int32, Fs:opus_int32) -> c.int ---

  /** Checks whether an Opus packet has LBRR.
    * @param [in] packet <tt>char*</tt>: Opus packet
    * @param [in] len <tt>opus_int32</tt>: Length of packet
    * @returns 1 is LBRR is present, 0 otherwise
    * @retval OPUS_INVALID_PACKET The compressed data passed is corrupted or of an unsupported type
    */
  @(require_results) opus_packet_has_lbrr :: proc(packet:[^]byte, len:opus_int32) -> c.int ---

  /** Gets the number of samples of an Opus packet.
    * @param [in] dec <tt>OpusDecoder*</tt>: Decoder state
    * @param [in] packet <tt>char*</tt>: Opus packet
    * @param [in] len <tt>opus_int32</tt>: Length of packet
    * @returns Number of samples
    * @retval OPUS_BAD_ARG Insufficient data was passed to the function
    * @retval OPUS_INVALID_PACKET The compressed data passed is corrupted or of an unsupported type
    */
  @(require_results) opus_decoder_get_nb_samples :: proc(dec:^OpusDecoder, packet:[^]byte, len:opus_int32) -> c.int ---

  /** Applies soft-clipping to bring a float signal within the [-1,1] range. If
    * the signal is already in that range, nothing is done. If there are values
    * outside of [-1,1], then the signal is clipped as smoothly as possible to
    * both fit in the range and avoid creating excessive distortion in the
    * process.
    * @param [in,out] pcm <tt>float*</tt>: Input PCM and modified PCM
    * @param [in] frame_size <tt>int</tt> Number of samples per channel to process
    * @param [in] channels <tt>int</tt>: Number of channels
    * @param [in,out] softclip_mem <tt>float*</tt>: State memory for the soft clipping process (one float per channel, initialized to zero)
    */
  opus_pcm_soft_clip :: proc(pcm:[^]c.float, frame_size:c.int, channels:c.int, softclip_mem:[^]c.float) ---


  /** Gets the size of an <code>OpusRepacketizer</code> structure.
    * @returns The size in bytes.
    */
  @(require_results) opus_repacketizer_get_size :: proc() -> c.int ---

  /** (Re)initializes a previously allocated repacketizer state.
    * The state must be at least the size returned by opus_repacketizer_get_size().
    * This can be used for applications which use their own allocator instead of
    * malloc().
    * It must also be called to reset the queue of packets waiting to be
    * repacketized, which is necessary if the maximum packet duration of 120 ms
    * is reached or if you wish to submit packets with a different Opus
    * configuration (coding mode, audio bandwidth, frame size, or channel count).
    * Failure to do so will prevent a new packet from being added with
    * opus_repacketizer_cat().
    * @see opus_repacketizer_create
    * @see opus_repacketizer_get_size
    * @see opus_repacketizer_cat
    * @param rp <tt>OpusRepacketizer*</tt>: The repacketizer state to
    *                                       (re)initialize.
    * @returns A pointer to the same repacketizer state that was passed in.
    */
  opus_repacketizer_init :: proc(rp:^OpusRepacketizer) -> ^OpusRepacketizer ---

  /** Allocates memory and initializes the new repacketizer with
  * opus_repacketizer_init().
    */
  @(require_results) opus_repacketizer_create::proc() -> ^OpusRepacketizer ---

  /** Frees an <code>OpusRepacketizer</code> allocated by
    * opus_repacketizer_create().
    * @param[in] rp <tt>OpusRepacketizer*</tt>: State to be freed.
    */
  opus_repacketizer_destroy :: proc(rp:^OpusRepacketizer) ---

  /** Add a packet to the current repacketizer state.
    * This packet must match the configuration of any packets already submitted
    * for repacketization since the last call to opus_repacketizer_init().
    * This means that it must have the same coding mode, audio bandwidth, frame
    * size, and channel count.
    * This can be checked in advance by examining the top 6 bits of the first
    * byte of the packet, and ensuring they match the top 6 bits of the first
    * byte of any previously submitted packet.
    * The total duration of audio in the repacketizer state also must not exceed
    * 120 ms, the maximum duration of a single packet, after adding this packet.
    *
    * The contents of the current repacketizer state can be extracted into new
    * packets using opus_repacketizer_out() or opus_repacketizer_out_range().
    *
    * In order to add a packet with a different configuration or to add more
    * audio beyond 120 ms, you must clear the repacketizer state by calling
    * opus_repacketizer_init().
    * If a packet is too large to add to the current repacketizer state, no part
    * of it is added, even if it contains multiple frames, some of which might
    * fit.
    * If you wish to be able to add parts of such packets, you should first use
    * another repacketizer to split the packet into pieces and add them
    * individually.
    * @see opus_repacketizer_out_range
    * @see opus_repacketizer_out
    * @see opus_repacketizer_init
    * @param rp <tt>OpusRepacketizer*</tt>: The repacketizer state to which to
    *                                       add the packet.
    * @param[in] data <tt>const unsigned char*</tt>: The packet data.
    *                                                The application must ensure
    *                                                this pointer remains valid
    *                                                until the next call to
    *                                                opus_repacketizer_init() or
    *                                                opus_repacketizer_destroy().
    * @param len <tt>opus_int32</tt>: The number of bytes in the packet data.
    * @returns An error code indicating whether or not the operation succeeded.
    * @retval #OPUS_OK The packet's contents have been added to the repacketizer
    *                  state.
    * @retval #OPUS_INVALID_PACKET The packet did not have a valid TOC sequence,
    *                              the packet's TOC sequence was not compatible
    *                              with previously submitted packets (because
    *                              the coding mode, audio bandwidth, frame size,
    *                              or channel count did not match), or adding
    *                              this packet would increase the total amount of
    *                              audio stored in the repacketizer state to more
    *                              than 120 ms.
    */
  opus_repacketizer_cat :: proc(rp:^OpusRepacketizer, data:[^]byte, len:opus_int32) -> c.int ---


  /** Construct a new packet from data previously submitted to the repacketizer
    * state via opus_repacketizer_cat().
    * @param rp <tt>OpusRepacketizer*</tt>: The repacketizer state from which to
    *                                       construct the new packet.
    * @param begin <tt>int</tt>: The index of the first frame in the current
    *                            repacketizer state to include in the output.
    * @param end <tt>int</tt>: One past the index of the last frame in the
    *                          current repacketizer state to include in the
    *                          output.
    * @param[out] data <tt>const unsigned char*</tt>: The buffer in which to
    *                                                 store the output packet.
    * @param maxlen <tt>opus_int32</tt>: The maximum number of bytes to store in
    *                                    the output buffer. In order to guarantee
    *                                    success, this should be at least
    *                                    <code>1276</code> for a single frame,
    *                                    or for multiple frames,
    *                                    <code>1277*(end-begin)</code>.
    *                                    However, <code>1*(end-begin)</code> plus
    *                                    the size of all packet data submitted to
    *                                    the repacketizer since the last call to
    *                                    opus_repacketizer_init() or
    *                                    opus_repacketizer_create() is also
    *                                    sufficient, and possibly much smaller.
    * @returns The total size of the output packet on success, or an error code
    *          on failure.
    * @retval #OPUS_BAD_ARG <code>[begin,end)</code> was an invalid range of
    *                       frames (begin < 0, begin >= end, or end >
    *                       opus_repacketizer_get_nb_frames()).
    * @retval #OPUS_BUFFER_TOO_SMALL \a maxlen was insufficient to contain the
    *                                complete output packet.
    */
  @(require_results) opus_repacketizer_out_range :: proc(rp:^OpusRepacketizer, begin:c.int, end:c.int, data:[^]byte, maxlen:opus_int32) -> opus_int32 ---

  /** Return the total number of frames contained in packet data submitted to
    * the repacketizer state so far via opus_repacketizer_cat() since the last
    * call to opus_repacketizer_init() or opus_repacketizer_create().
    * This defines the valid range of packets that can be extracted with
    * opus_repacketizer_out_range() or opus_repacketizer_out().
    * @param rp <tt>OpusRepacketizer*</tt>: The repacketizer state containing the
    *                                       frames.
    * @returns The total number of frames contained in the packet data submitted
    *          to the repacketizer state.
    */
  @(require_results) opus_repacketizer_get_nb_frames :: proc(rp:^OpusRepacketizer) -> c.int ---

  /** Construct a new packet from data previously submitted to the repacketizer
    * state via opus_repacketizer_cat().
    * This is a convenience routine that returns all the data submitted so far
    * in a single packet.
    * It is equivalent to calling
    * @code
    * opus_repacketizer_out_range(rp, 0, opus_repacketizer_get_nb_frames(rp),
    *                             data, maxlen)
    * @endcode
    * @param rp <tt>OpusRepacketizer*</tt>: The repacketizer state from which to
    *                                       construct the new packet.
    * @param[out] data <tt>const unsigned char*</tt>: The buffer in which to
    *                                                 store the output packet.
    * @param maxlen <tt>opus_int32</tt>: The maximum number of bytes to store in
    *                                    the output buffer. In order to guarantee
    *                                    success, this should be at least
    *                                    <code>1277*opus_repacketizer_get_nb_frames(rp)</code>.
    *                                    However,
    *                                    <code>1*opus_repacketizer_get_nb_frames(rp)</code>
    *                                    plus the size of all packet data
    *                                    submitted to the repacketizer since the
    *                                    last call to opus_repacketizer_init() or
    *                                    opus_repacketizer_create() is also
    *                                    sufficient, and possibly much smaller.
    * @returns The total size of the output packet on success, or an error code
    *          on failure.
    * @retval #OPUS_BUFFER_TOO_SMALL \a maxlen was insufficient to contain the
    *                                complete output packet.
    */
  @(require_results) opus_repacketizer_out :: proc(rp:^OpusRepacketizer, data:[^]byte, maxlen:opus_int32) -> opus_int32 ---

  /** Pads a given Opus packet to a larger size (possibly changing the TOC sequence).
    * @param[in,out] data <tt>const unsigned char*</tt>: The buffer containing the
    *                                                   packet to pad.
    * @param len <tt>opus_int32</tt>: The size of the packet.
    *                                 This must be at least 1.
    * @param new_len <tt>opus_int32</tt>: The desired size of the packet after padding.
    *                                 This must be at least as large as len.
    * @returns an error code
    * @retval #OPUS_OK \a on success.
    * @retval #OPUS_BAD_ARG \a len was less than 1 or new_len was less than len.
    * @retval #OPUS_INVALID_PACKET \a data did not contain a valid Opus packet.
    */
  opus_packet_pad :: proc(data:[^]byte, len:opus_int32, new_len:opus_int32) -> c.int ---

  /** Remove all padding from a given Opus packet and rewrite the TOC sequence to
    * minimize space usage.
    * @param[in,out] data <tt>const unsigned char*</tt>: The buffer containing the
    *                                                   packet to strip.
    * @param len <tt>opus_int32</tt>: The size of the packet.
    *                                 This must be at least 1.
    * @returns The new size of the output packet on success, or an error code
    *          on failure.
    * @retval #OPUS_BAD_ARG \a len was less than 1.
    * @retval #OPUS_INVALID_PACKET \a data did not contain a valid Opus packet.
    */
  @(require_results) opus_packet_unpad :: proc(data:[^]byte, len:opus_int32) -> opus_int32 ---

  /** Pads a given Opus multi-stream packet to a larger size (possibly changing the TOC sequence).
    * @param[in,out] data <tt>const unsigned char*</tt>: The buffer containing the
    *                                                   packet to pad.
    * @param len <tt>opus_int32</tt>: The size of the packet.
    *                                 This must be at least 1.
    * @param new_len <tt>opus_int32</tt>: The desired size of the packet after padding.
    *                                 This must be at least 1.
    * @param nb_streams <tt>opus_int32</tt>: The number of streams (not channels) in the packet.
    *                                 This must be at least as large as len.
    * @returns an error code
    * @retval #OPUS_OK \a on success.
    * @retval #OPUS_BAD_ARG \a len was less than 1.
    * @retval #OPUS_INVALID_PACKET \a data did not contain a valid Opus packet.
    */
  opus_multistream_packet_pad :: proc(data:[^]byte, len:opus_int32, new_len:opus_int32, nb_streams:c.int) -> c.int ---

  /** Remove all padding from a given Opus multi-stream packet and rewrite the TOC sequence to
    * minimize space usage.
    * @param[in,out] data <tt>const unsigned char*</tt>: The buffer containing the
    *                                                   packet to strip.
    * @param len <tt>opus_int32</tt>: The size of the packet.
    *                                 This must be at least 1.
    * @param nb_streams <tt>opus_int32</tt>: The number of streams (not channels) in the packet.
    *                                 This must be at least 1.
    * @returns The new size of the output packet on success, or an error code
    *          on failure.
    * @retval #OPUS_BAD_ARG \a len was less than 1 or new_len was less than len.
    * @retval #OPUS_INVALID_PACKET \a data did not contain a valid Opus packet.
    */
  @(require_results) opus_multistream_packet_unpad :: proc(data:[^]byte, len:opus_int32, nb_streams:c.int) -> opus_int32 ---
  //opus.h end

  //opus_multistream.h

  /** Gets the size of an OpusMSEncoder structure.
  * @param streams <tt>int</tt>: The total number of streams to encode from the
  *                              input.
  *                              This must be no more than 255.
  * @param coupled_streams <tt>int</tt>: Number of coupled (2 channel) streams
  *                                      to encode.
  *                                      This must be no larger than the total
  *                                      number of streams.
  *                                      Additionally, The total number of
  *                                      encoded channels (<code>streams +
  *                                      coupled_streams</code>) must be no
  *                                      more than 255.
  * @returns The size in bytes on success, or a negative error code
  *          (see @ref opus_errorcodes) on error.
  */
 @(require_results) opus_multistream_encoder_get_size :: proc(streams:c.int, coupled_streams:c.int) -> opus_int32 ---

 @(require_results) opus_multistream_surround_encoder_get_size :: proc(channels:c.int, mapping_family:c.int) -> opus_int32 ---


/** Allocates and initializes a multistream encoder state.
* Call opus_multistream_encoder_destroy() to release
* this object when finished.
* @param Fs <tt>opus_int32</tt>: Sampling rate of the input signal (in Hz).
*                                This must be one of 8000, 12000, 16000,
*                                24000, or 48000.
* @param channels <tt>int</tt>: Number of channels in the input signal.
*                               This must be at most 255.
*                               It may be greater than the number of
*                               coded channels (<code>streams +
*                               coupled_streams</code>).
* @param streams <tt>int</tt>: The total number of streams to encode from the
*                              input.
*                              This must be no more than the number of channels.
* @param coupled_streams <tt>int</tt>: Number of coupled (2 channel) streams
*                                      to encode.
*                                      This must be no larger than the total
*                                      number of streams.
*                                      Additionally, The total number of
*                                      encoded channels (<code>streams +
*                                      coupled_streams</code>) must be no
*                                      more than the number of input channels.
* @param[in] mapping <code>const unsigned char[channels]</code>: Mapping from
*                    encoded channels to input channels, as described in
*                    @ref opus_multistream. As an extra constraint, the
*                    multistream encoder does not allow encoding coupled
*                    streams for which one channel is unused since this
*                    is never a good idea.
* @param application <tt>int</tt>: The target encoder application.
*                                  This must be one of the following:
* <dl>
* <dt>#OPUS_APPLICATION_VOIP</dt>
* <dd>Process signal for improved speech intelligibility.</dd>
* <dt>#OPUS_APPLICATION_AUDIO</dt>
* <dd>Favor faithfulness to the original input.</dd>
* <dt>#OPUS_APPLICATION_RESTRICTED_LOWDELAY</dt>
* <dd>Configure the minimum possible coding delay by disabling certain modes
* of operation.</dd>
* </dl>
* @param[out] error <tt>int *</tt>: Returns #OPUS_OK on success, or an error
*                                   code (see @ref opus_errorcodes) on
*                                   failure.
*/
 @(require_results) opus_multistream_encoder_create :: proc(
  Fs:opus_int32,
  channels:c.int,
  streams:c.int,
  coupled_streams:c.int,
  mapping:[^]byte,
  application:c.int,
  error:^c.int,
) -> ^OpusMSEncoder ---

 @(require_results) opus_multistream_surround_encoder_create :: proc(
  Fs:opus_int32,
  channels:c.int,
  mapping_family:c.int,
  streams:[^]c.int,
  coupled_streams:[^]c.int,
  mapping:[^]byte,
  application:c.int,
  error:^c.int,
) -> ^OpusMSEncoder ---

/** Initialize a previously allocated multistream encoder state.
* The memory pointed to by \a st must be at least the size returned by
* opus_multistream_encoder_get_size().
* This is intended for applications which use their own allocator instead of
* malloc.
* To reset a previously initialized state, use the #OPUS_RESET_STATE CTL.
* @see opus_multistream_encoder_create
* @see opus_multistream_encoder_get_size
* @param st <tt>OpusMSEncoder*</tt>: Multistream encoder state to initialize.
* @param Fs <tt>opus_int32</tt>: Sampling rate of the input signal (in Hz).
*                                This must be one of 8000, 12000, 16000,
*                                24000, or 48000.
* @param channels <tt>int</tt>: Number of channels in the input signal.
*                               This must be at most 255.
*                               It may be greater than the number of
*                               coded channels (<code>streams +
*                               coupled_streams</code>).
* @param streams <tt>int</tt>: The total number of streams to encode from the
*                              input.
*                              This must be no more than the number of channels.
* @param coupled_streams <tt>int</tt>: Number of coupled (2 channel) streams
*                                      to encode.
*                                      This must be no larger than the total
*                                      number of streams.
*                                      Additionally, The total number of
*                                      encoded channels (<code>streams +
*                                      coupled_streams</code>) must be no
*                                      more than the number of input channels.
* @param[in] mapping <code>const unsigned char[channels]</code>: Mapping from
*                    encoded channels to input channels, as described in
*                    @ref opus_multistream. As an extra constraint, the
*                    multistream encoder does not allow encoding coupled
*                    streams for which one channel is unused since this
*                    is never a good idea.
* @param application <tt>int</tt>: The target encoder application.
*                                  This must be one of the following:
* <dl>
* <dt>#OPUS_APPLICATION_VOIP</dt>
* <dd>Process signal for improved speech intelligibility.</dd>
* <dt>#OPUS_APPLICATION_AUDIO</dt>
* <dd>Favor faithfulness to the original input.</dd>
* <dt>#OPUS_APPLICATION_RESTRICTED_LOWDELAY</dt>
* <dd>Configure the minimum possible coding delay by disabling certain modes
* of operation.</dd>
* </dl>
* @returns #OPUS_OK on success, or an error code (see @ref opus_errorcodes)
*          on failure.
*/
 opus_multistream_encoder_init :: proc(
  st:^OpusMSEncoder,
  Fs:opus_int32,
  channels:c.int,
  streams:c.int,
  coupled_streams:c.int,
  mapping:[^]byte,
  application:c.int,
) -> c.int ---

opus_multistream_surround_encoder_init :: proc(
  st:^OpusMSEncoder,
  Fs:opus_int32,
  channels:c.int,
  mapping_family:c.int,
  streams:[^]c.int,
  coupled_streams:[^]c.int,
  mapping:[^]byte,
  application:c.int,
) -> c.int ---

/** Encodes a multistream Opus frame.
* @param st <tt>OpusMSEncoder*</tt>: Multistream encoder state.
* @param[in] pcm <tt>const opus_int16*</tt>: The input signal as interleaved
*                                            samples.
*                                            This must contain
*                                            <code>frame_size*channels</code>
*                                            samples.
* @param frame_size <tt>int</tt>: Number of samples per channel in the input
*                                 signal.
*                                 This must be an Opus frame size for the
*                                 encoder's sampling rate.
*                                 For example, at 48 kHz the permitted values
*                                 are 120, 240, 480, 960, 1920, and 2880.
*                                 Passing in a duration of less than 10 ms
*                                 (480 samples at 48 kHz) will prevent the
*                                 encoder from using the LPC or hybrid modes.
* @param[out] data <tt>unsigned char*</tt>: Output payload.
*                                           This must contain storage for at
*                                           least \a max_data_bytes.
* @param [in] max_data_bytes <tt>opus_int32</tt>: Size of the allocated
*                                                 memory for the output
*                                                 payload. This may be
*                                                 used to impose an upper limit on
*                                                 the instant bitrate, but should
*                                                 not be used as the only bitrate
*                                                 control. Use #OPUS_SET_BITRATE to
*                                                 control the bitrate.
* @returns The length of the encoded packet (in bytes) on success or a
*          negative error code (see @ref opus_errorcodes) on failure.
*/
 @(require_results) opus_multistream_encode :: proc(
st:^OpusMSEncoder,
pcm:[^]c.uint16_t,
frame_size:c.int,
data:[^]byte,
max_data_bytes:opus_int32,
) -> c.int ---

/** Encodes a multistream Opus frame from floating point input.
* @param st <tt>OpusMSEncoder*</tt>: Multistream encoder state.
* @param[in] pcm <tt>const float*</tt>: The input signal as interleaved
*                                       samples with a normal range of
*                                       +/-1.0.
*                                       Samples with a range beyond +/-1.0
*                                       are supported but will be clipped by
*                                       decoders using the integer API and
*                                       should only be used if it is known
*                                       that the far end supports extended
*                                       dynamic range.
*                                       This must contain
*                                       <code>frame_size*channels</code>
*                                       samples.
* @param frame_size <tt>int</tt>: Number of samples per channel in the input
*                                 signal.
*                                 This must be an Opus frame size for the
*                                 encoder's sampling rate.
*                                 For example, at 48 kHz the permitted values
*                                 are 120, 240, 480, 960, 1920, and 2880.
*                                 Passing in a duration of less than 10 ms
*                                 (480 samples at 48 kHz) will prevent the
*                                 encoder from using the LPC or hybrid modes.
* @param[out] data <tt>unsigned char*</tt>: Output payload.
*                                           This must contain storage for at
*                                           least \a max_data_bytes.
* @param [in] max_data_bytes <tt>opus_int32</tt>: Size of the allocated
*                                                 memory for the output
*                                                 payload. This may be
*                                                 used to impose an upper limit on
*                                                 the instant bitrate, but should
*                                                 not be used as the only bitrate
*                                                 control. Use #OPUS_SET_BITRATE to
*                                                 control the bitrate.
* @returns The length of the encoded packet (in bytes) on success or a
*          negative error code (see @ref opus_errorcodes) on failure.
*/
 @(require_results) opus_multistream_encode_float :: proc(
  st:^OpusMSEncoder,
  pcm:[^]c.float,
  frame_size:c.int,
  data:[^]byte,
  max_data_bytes:opus_int32,
) -> c.int ---

/** Frees an <code>OpusMSEncoder</code> allocated by
* opus_multistream_encoder_create().
* @param st <tt>OpusMSEncoder*</tt>: Multistream encoder state to be freed.
*/
 opus_multistream_encoder_destroy :: proc(st:^OpusMSEncoder) ---

/** Perform a CTL function on a multistream Opus encoder.
*
* Generally the request and subsequent arguments are generated by a
* convenience macro.
* @param st <tt>OpusMSEncoder*</tt>: Multistream encoder state.
* @param request This and all remaining parameters should be replaced by one
*                of the convenience macros in @ref opus_genericctls,
*                @ref opus_encoderctls, or @ref opus_multistream_ctls.
* @see opus_genericctls
* @see opus_encoderctls
* @see opus_multistream_ctls
*/
opus_multistream_encoder_ctl :: proc(st:^OpusMSEncoder, request:c.int, #c_vararg args:..any) -> c.int ---

/**@}*/

/**\name Multistream decoder functions */
/**@{*/

/** Gets the size of an <code>OpusMSDecoder</code> structure.
* @param streams <tt>int</tt>: The total number of streams coded in the
*                              input.
*                              This must be no more than 255.
* @param coupled_streams <tt>int</tt>: Number streams to decode as coupled
*                                      (2 channel) streams.
*                                      This must be no larger than the total
*                                      number of streams.
*                                      Additionally, The total number of
*                                      coded channels (<code>streams +
*                                      coupled_streams</code>) must be no
*                                      more than 255.
* @returns The size in bytes on success, or a negative error code
*          (see @ref opus_errorcodes) on error.
*/
 @(require_results) opus_multistream_decoder_get_size :: proc(streams:c.int, coupled_streams:c.int) -> opus_int32 ---

/** Allocates and initializes a multistream decoder state.
* Call opus_multistream_decoder_destroy() to release
* this object when finished.
* @param Fs <tt>opus_int32</tt>: Sampling rate to decode at (in Hz).
*                                This must be one of 8000, 12000, 16000,
*                                24000, or 48000.
* @param channels <tt>int</tt>: Number of channels to output.
*                               This must be at most 255.
*                               It may be different from the number of coded
*                               channels (<code>streams +
*                               coupled_streams</code>).
* @param streams <tt>int</tt>: The total number of streams coded in the
*                              input.
*                              This must be no more than 255.
* @param coupled_streams <tt>int</tt>: Number of streams to decode as coupled
*                                      (2 channel) streams.
*                                      This must be no larger than the total
*                                      number of streams.
*                                      Additionally, The total number of
*                                      coded channels (<code>streams +
*                                      coupled_streams</code>) must be no
*                                      more than 255.
* @param[in] mapping <code>const unsigned char[channels]</code>: Mapping from
*                    coded channels to output channels, as described in
*                    @ref opus_multistream.
* @param[out] error <tt>int *</tt>: Returns #OPUS_OK on success, or an error
*                                   code (see @ref opus_errorcodes) on
*                                   failure.
*/
 @(require_results) opus_multistream_decoder_create :: proc(
  Fs:opus_int32,
  channels:c.int,
  streams:c.int,
  coupled_streams:c.int,
  mapping:[^]byte,
  error:^c.int,
) -> ^OpusMSDecoder ---

/** Intialize a previously allocated decoder state object.
* The memory pointed to by \a st must be at least the size returned by
* opus_multistream_encoder_get_size().
* This is intended for applications which use their own allocator instead of
* malloc.
* To reset a previously initialized state, use the #OPUS_RESET_STATE CTL.
* @see opus_multistream_decoder_create
* @see opus_multistream_deocder_get_size
* @param st <tt>OpusMSEncoder*</tt>: Multistream encoder state to initialize.
* @param Fs <tt>opus_int32</tt>: Sampling rate to decode at (in Hz).
*                                This must be one of 8000, 12000, 16000,
*                                24000, or 48000.
* @param channels <tt>int</tt>: Number of channels to output.
*                               This must be at most 255.
*                               It may be different from the number of coded
*                               channels (<code>streams +
*                               coupled_streams</code>).
* @param streams <tt>int</tt>: The total number of streams coded in the
*                              input.
*                              This must be no more than 255.
* @param coupled_streams <tt>int</tt>: Number of streams to decode as coupled
*                                      (2 channel) streams.
*                                      This must be no larger than the total
*                                      number of streams.
*                                      Additionally, The total number of
*                                      coded channels (<code>streams +
*                                      coupled_streams</code>) must be no
*                                      more than 255.
* @param[in] mapping <code>const unsigned char[channels]</code>: Mapping from
*                    coded channels to output channels, as described in
*                    @ref opus_multistream.
* @returns #OPUS_OK on success, or an error code (see @ref opus_errorcodes)
*          on failure.
*/
 opus_multistream_decoder_init :: proc(
  st:^OpusMSDecoder,
  Fs:opus_int32,
  channels:c.int,
  streams:c.int,
  coupled_streams:c.int,
  mapping:[^]byte,
) -> c.int ---

/** Decode a multistream Opus packet.
* @param st <tt>OpusMSDecoder*</tt>: Multistream decoder state.
* @param[in] data <tt>const unsigned char*</tt>: Input payload.
*                                                Use a <code>NULL</code>
*                                                pointer to indicate packet
*                                                loss.
* @param len <tt>opus_int32</tt>: Number of bytes in payload.
* @param[out] pcm <tt>opus_int16*</tt>: Output signal, with interleaved
*                                       samples.
*                                       This must contain room for
*                                       <code>frame_size*channels</code>
*                                       samples.
* @param frame_size <tt>int</tt>: The number of samples per channel of
*                                 available space in \a pcm.
*                                 If this is less than the maximum packet duration
*                                 (120 ms --- 5760 for 48kHz), this function will not be capable
*                                 of decoding some packets. In the case of PLC (data==NULL)
*                                 or FEC (decode_fec=1), then frame_size needs to be exactly
*                                 the duration of audio that is missing, otherwise the
*                                 decoder will not be in the optimal state to decode the
*                                 next incoming packet. For the PLC and FEC cases, frame_size
*                                 <b>must</b> be a multiple of 2.5 ms.
* @param decode_fec <tt>int</tt>: Flag (0 or 1) to request that any in-band
*                                 forward error correction data be decoded.
*                                 If no such data is available, the frame is
*                                 decoded as if it were lost.
* @returns Number of samples decoded on success or a negative error code
*          (see @ref opus_errorcodes) on failure.
*/
 @(require_results) opus_multistream_decode :: proc(
  st:^OpusMSDecoder,
  data:[^]byte,
  len:opus_int32,
  pcm:[^]opus_int16,
  frame_size:c.int,
  decode_fec:c.int,
) -> c.int ---

/** Decode a multistream Opus packet with floating point output.
* @param st <tt>OpusMSDecoder*</tt>: Multistream decoder state.
* @param[in] data <tt>const unsigned char*</tt>: Input payload.
*                                                Use a <code>NULL</code>
*                                                pointer to indicate packet
*                                                loss.
* @param len <tt>opus_int32</tt>: Number of bytes in payload.
* @param[out] pcm <tt>opus_int16*</tt>: Output signal, with interleaved
*                                       samples.
*                                       This must contain room for
*                                       <code>frame_size*channels</code>
*                                       samples.
* @param frame_size <tt>int</tt>: The number of samples per channel of
*                                 available space in \a pcm.
*                                 If this is less than the maximum packet duration
*                                 (120 ms --- 5760 for 48kHz), this function will not be capable
*                                 of decoding some packets. In the case of PLC (data==NULL)
*                                 or FEC (decode_fec=1), then frame_size needs to be exactly
*                                 the duration of audio that is missing, otherwise the
*                                 decoder will not be in the optimal state to decode the
*                                 next incoming packet. For the PLC and FEC cases, frame_size
*                                 <b>must</b> be a multiple of 2.5 ms.
* @param decode_fec <tt>int</tt>: Flag (0 or 1) to request that any in-band
*                                 forward error correction data be decoded.
*                                 If no such data is available, the frame is
*                                 decoded as if it were lost.
* @returns Number of samples decoded on success or a negative error code
*          (see @ref opus_errorcodes) on failure.
*/
 @(require_results) opus_multistream_decode_float :: proc(
  st:^OpusMSDecoder,
  data:[^]byte,
  len:opus_int32,
  pcm:[^]c.float,
  frame_size:c.int,
  decode_fec:c.int,
) -> c.int ---

/** Perform a CTL function on a multistream Opus decoder.
*
* Generally the request and subsequent arguments are generated by a
* convenience macro.
* @param st <tt>OpusMSDecoder*</tt>: Multistream decoder state.
* @param request This and all remaining parameters should be replaced by one
*                of the convenience macros in @ref opus_genericctls,
*                @ref opus_decoderctls, or @ref opus_multistream_ctls.
* @see opus_genericctls
* @see opus_decoderctls
* @see opus_multistream_ctls
*/
 opus_multistream_decoder_ctl :: proc(st:^OpusMSDecoder, request:c.int, #c_vararg args:..any) -> c.int ---

/** Frees an <code>OpusMSDecoder</code> allocated by
* opus_multistream_decoder_create().
* @param st <tt>OpusMSDecoder</tt>: Multistream decoder state to be freed.
*/
 opus_multistream_decoder_destroy :: proc(st:^OpusMSDecoder) ---

  //opus_multistream.h end

  //opus_projection.h 

  /** Gets the size of an OpusProjectionEncoder structure.
  * @param channels <tt>int</tt>: The total number of input channels to encode.
  *                               This must be no more than 255.
  * @param mapping_family <tt>int</tt>: The mapping family to use for selecting
  *                                     the appropriate projection.
  * @returns The size in bytes on success, or a negative error code
  *          (see @ref opus_errorcodes) on error.
  */
@(require_results) opus_projection_ambisonics_encoder_get_size :: proc(channels:c.int, mapping_family:c.int) -> opus_int32 ---


/** Allocates and initializes a projection encoder state.
* Call opus_projection_encoder_destroy() to release
* this object when finished.
* @param Fs <tt>opus_int32</tt>: Sampling rate of the input signal (in Hz).
*                                This must be one of 8000, 12000, 16000,
*                                24000, or 48000.
* @param channels <tt>int</tt>: Number of channels in the input signal.
*                               This must be at most 255.
*                               It may be greater than the number of
*                               coded channels (<code>streams +
*                               coupled_streams</code>).
* @param mapping_family <tt>int</tt>: The mapping family to use for selecting
*                                     the appropriate projection.
* @param[out] streams <tt>int *</tt>: The total number of streams that will
*                                     be encoded from the input.
* @param[out] coupled_streams <tt>int *</tt>: Number of coupled (2 channel)
*                                 streams that will be encoded from the input.
* @param application <tt>int</tt>: The target encoder application.
*                                  This must be one of the following:
* <dl>
* <dt>#OPUS_APPLICATION_VOIP</dt>
* <dd>Process signal for improved speech intelligibility.</dd>
* <dt>#OPUS_APPLICATION_AUDIO</dt>
* <dd>Favor faithfulness to the original input.</dd>
* <dt>#OPUS_APPLICATION_RESTRICTED_LOWDELAY</dt>
* <dd>Configure the minimum possible coding delay by disabling certain modes
* of operation.</dd>
* </dl>
* @param[out] error <tt>int *</tt>: Returns #OPUS_OK on success, or an error
*                                   code (see @ref opus_errorcodes) on
*                                   failure.
*/
@(require_results) opus_projection_ambisonics_encoder_create :: proc(
  Fs:opus_int32,
  channels:c.int,
  mapping_family:c.int,
  streams:[^]c.int,
  coupled_streams:[^]c.int,
  mapping:[^]byte,
  application:c.int,
  error:^c.int,
) -> ^OpusProjectionEncoder ---


/** Initialize a previously allocated projection encoder state.
* The memory pointed to by \a st must be at least the size returned by
* opus_projection_ambisonics_encoder_get_size().
* This is intended for applications which use their own allocator instead of
* malloc.
* To reset a previously initialized state, use the #OPUS_RESET_STATE CTL.
* @see opus_projection_ambisonics_encoder_create
* @see opus_projection_ambisonics_encoder_get_size
* @param st <tt>OpusProjectionEncoder*</tt>: Projection encoder state to initialize.
* @param Fs <tt>opus_int32</tt>: Sampling rate of the input signal (in Hz).
*                                This must be one of 8000, 12000, 16000,
*                                24000, or 48000.
* @param channels <tt>int</tt>: Number of channels in the input signal.
*                               This must be at most 255.
*                               It may be greater than the number of
*                               coded channels (<code>streams +
*                               coupled_streams</code>).
* @param streams <tt>int</tt>: The total number of streams to encode from the
*                              input.
*                              This must be no more than the number of channels.
* @param coupled_streams <tt>int</tt>: Number of coupled (2 channel) streams
*                                      to encode.
*                                      This must be no larger than the total
*                                      number of streams.
*                                      Additionally, The total number of
*                                      encoded channels (<code>streams +
*                                      coupled_streams</code>) must be no
*                                      more than the number of input channels.
* @param application <tt>int</tt>: The target encoder application.
*                                  This must be one of the following:
* <dl>
* <dt>#OPUS_APPLICATION_VOIP</dt>
* <dd>Process signal for improved speech intelligibility.</dd>
* <dt>#OPUS_APPLICATION_AUDIO</dt>
* <dd>Favor faithfulness to the original input.</dd>
* <dt>#OPUS_APPLICATION_RESTRICTED_LOWDELAY</dt>
* <dd>Configure the minimum possible coding delay by disabling certain modes
* of operation.</dd>
* </dl>
* @returns #OPUS_OK on success, or an error code (see @ref opus_errorcodes)
*          on failure.
*/
opus_projection_ambisonics_encoder_init :: proc(
  st:^OpusProjectionEncoder,
  Fs:opus_int32,
  channels:c.int,
  mapping_family:c.int,
  streams:[^]c.int,
  coupled_streams:[^]c.int,
  application:c.int,
) -> c.int ---


/** Encodes a projection Opus frame.
* @param st <tt>OpusProjectionEncoder*</tt>: Projection encoder state.
* @param[in] pcm <tt>const opus_int16*</tt>: The input signal as interleaved
*                                            samples.
*                                            This must contain
*                                            <code>frame_size*channels</code>
*                                            samples.
* @param frame_size <tt>int</tt>: Number of samples per channel in the input
*                                 signal.
*                                 This must be an Opus frame size for the
*                                 encoder's sampling rate.
*                                 For example, at 48 kHz the permitted values
*                                 are 120, 240, 480, 960, 1920, and 2880.
*                                 Passing in a duration of less than 10 ms
*                                 (480 samples at 48 kHz) will prevent the
*                                 encoder from using the LPC or hybrid modes.
* @param[out] data <tt>unsigned char*</tt>: Output payload.
*                                           This must contain storage for at
*                                           least \a max_data_bytes.
* @param [in] max_data_bytes <tt>opus_int32</tt>: Size of the allocated
*                                                 memory for the output
*                                                 payload. This may be
*                                                 used to impose an upper limit on
*                                                 the instant bitrate, but should
*                                                 not be used as the only bitrate
*                                                 control. Use #OPUS_SET_BITRATE to
*                                                 control the bitrate.
* @returns The length of the encoded packet (in bytes) on success or a
*          negative error code (see @ref opus_errorcodes) on failure.
*/
@(require_results) opus_projection_encode :: proc(
  st:^OpusProjectionEncoder,
  pcm:[^]opus_int16,
  frame_size:c.int,
  data:[^]byte,
  max_data_bytes:opus_int32,
) -> c.int ---


/** Encodes a projection Opus frame from floating point input.
* @param st <tt>OpusProjectionEncoder*</tt>: Projection encoder state.
* @param[in] pcm <tt>const float*</tt>: The input signal as interleaved
*                                       samples with a normal range of
*                                       +/-1.0.
*                                       Samples with a range beyond +/-1.0
*                                       are supported but will be clipped by
*                                       decoders using the integer API and
*                                       should only be used if it is known
*                                       that the far end supports extended
*                                       dynamic range.
*                                       This must contain
*                                       <code>frame_size*channels</code>
*                                       samples.
* @param frame_size <tt>int</tt>: Number of samples per channel in the input
*                                 signal.
*                                 This must be an Opus frame size for the
*                                 encoder's sampling rate.
*                                 For example, at 48 kHz the permitted values
*                                 are 120, 240, 480, 960, 1920, and 2880.
*                                 Passing in a duration of less than 10 ms
*                                 (480 samples at 48 kHz) will prevent the
*                                 encoder from using the LPC or hybrid modes.
* @param[out] data <tt>unsigned char*</tt>: Output payload.
*                                           This must contain storage for at
*                                           least \a max_data_bytes.
* @param [in] max_data_bytes <tt>opus_int32</tt>: Size of the allocated
*                                                 memory for the output
*                                                 payload. This may be
*                                                 used to impose an upper limit on
*                                                 the instant bitrate, but should
*                                                 not be used as the only bitrate
*                                                 control. Use #OPUS_SET_BITRATE to
*                                                 control the bitrate.
* @returns The length of the encoded packet (in bytes) on success or a
*          negative error code (see @ref opus_errorcodes) on failure.
*/
@(require_results) opus_projection_encode_float :: proc(
  st:^OpusProjectionEncoder,
  pcm:[^]c.float,
  frame_size:c.int,
  data:[^]byte,
  max_data_bytes:opus_int32,
) -> c.int ---


/** Frees an <code>OpusProjectionEncoder</code> allocated by
* opus_projection_ambisonics_encoder_create().
* @param st <tt>OpusProjectionEncoder*</tt>: Projection encoder state to be freed.
*/
opus_projection_encoder_destroy :: proc(st:^OpusProjectionEncoder) ---


/** Perform a CTL function on a projection Opus encoder.
*
* Generally the request and subsequent arguments are generated by a
* convenience macro.
* @param st <tt>OpusProjectionEncoder*</tt>: Projection encoder state.
* @param request This and all remaining parameters should be replaced by one
*                of the convenience macros in @ref opus_genericctls,
*                @ref opus_encoderctls, @ref opus_multistream_ctls, or
*                @ref opus_projection_ctls
* @see opus_genericctls
* @see opus_encoderctls
* @see opus_multistream_ctls
* @see opus_projection_ctls
*/
opus_projection_encoder_ctl :: proc(st:^OpusProjectionEncoder, request:c.int , #c_vararg args:..any) -> c.int ---


/**@}*/

/**\name Projection decoder functions */
/**@{*/

/** Gets the size of an <code>OpusProjectionDecoder</code> structure.
* @param channels <tt>int</tt>: The total number of output channels.
*                               This must be no more than 255.
* @param streams <tt>int</tt>: The total number of streams coded in the
*                              input.
*                              This must be no more than 255.
* @param coupled_streams <tt>int</tt>: Number streams to decode as coupled
*                                      (2 channel) streams.
*                                      This must be no larger than the total
*                                      number of streams.
*                                      Additionally, The total number of
*                                      coded channels (<code>streams +
*                                      coupled_streams</code>) must be no
*                                      more than 255.
* @returns The size in bytes on success, or a negative error code
*          (see @ref opus_errorcodes) on error.
*/
@(require_results) opus_projection_decoder_get_size :: proc(channels:c.int, streams:c.int, coupled_streams:c.int) -> opus_int32 ---


/** Allocates and initializes a projection decoder state.
* Call opus_projection_decoder_destroy() to release
* this object when finished.
* @param Fs <tt>opus_int32</tt>: Sampling rate to decode at (in Hz).
*                                This must be one of 8000, 12000, 16000,
*                                24000, or 48000.
* @param channels <tt>int</tt>: Number of channels to output.
*                               This must be at most 255.
*                               It may be different from the number of coded
*                               channels (<code>streams +
*                               coupled_streams</code>).
* @param streams <tt>int</tt>: The total number of streams coded in the
*                              input.
*                              This must be no more than 255.
* @param coupled_streams <tt>int</tt>: Number of streams to decode as coupled
*                                      (2 channel) streams.
*                                      This must be no larger than the total
*                                      number of streams.
*                                      Additionally, The total number of
*                                      coded channels (<code>streams +
*                                      coupled_streams</code>) must be no
*                                      more than 255.
* @param[in] demixing_matrix <tt>const unsigned char[demixing_matrix_size]</tt>: Demixing matrix
*                         that mapping from coded channels to output channels,
*                         as described in @ref opus_projection and
*                         @ref opus_projection_ctls.
* @param demixing_matrix_size <tt>opus_int32</tt>: The size in bytes of the
*                                                  demixing matrix, as
*                                                  described in @ref
*                                                  opus_projection_ctls.
* @param[out] error <tt>int *</tt>: Returns #OPUS_OK on success, or an error
*                                   code (see @ref opus_errorcodes) on
*                                   failure.
*/
@(require_results) opus_projection_decoder_create :: proc(
  Fs:opus_int32,
  channels:c.int,
  streams:c.int,
  coupled_streams:c.int,
  demixing_matrix:[^]byte,
  demixing_matrix_size:opus_int32,
  error:^c.int,
) -> ^OpusProjectionDecoder ---


/** Intialize a previously allocated projection decoder state object.
* The memory pointed to by \a st must be at least the size returned by
* opus_projection_decoder_get_size().
* This is intended for applications which use their own allocator instead of
* malloc.
* To reset a previously initialized state, use the #OPUS_RESET_STATE CTL.
* @see opus_projection_decoder_create
* @see opus_projection_deocder_get_size
* @param st <tt>OpusProjectionDecoder*</tt>: Projection encoder state to initialize.
* @param Fs <tt>opus_int32</tt>: Sampling rate to decode at (in Hz).
*                                This must be one of 8000, 12000, 16000,
*                                24000, or 48000.
* @param channels <tt>int</tt>: Number of channels to output.
*                               This must be at most 255.
*                               It may be different from the number of coded
*                               channels (<code>streams +
*                               coupled_streams</code>).
* @param streams <tt>int</tt>: The total number of streams coded in the
*                              input.
*                              This must be no more than 255.
* @param coupled_streams <tt>int</tt>: Number of streams to decode as coupled
*                                      (2 channel) streams.
*                                      This must be no larger than the total
*                                      number of streams.
*                                      Additionally, The total number of
*                                      coded channels (<code>streams +
*                                      coupled_streams</code>) must be no
*                                      more than 255.
* @param[in] demixing_matrix <tt>const unsigned char[demixing_matrix_size]</tt>: Demixing matrix
*                         that mapping from coded channels to output channels,
*                         as described in @ref opus_projection and
*                         @ref opus_projection_ctls.
* @param demixing_matrix_size <tt>opus_int32</tt>: The size in bytes of the
*                                                  demixing matrix, as
*                                                  described in @ref
*                                                  opus_projection_ctls.
* @returns #OPUS_OK on success, or an error code (see @ref opus_errorcodes)
*          on failure.
*/
opus_projection_decoder_init :: proc(
  st:^OpusProjectionDecoder,
  Fs:opus_int32,
  channels:c.int,
  streams:c.int,
  coupled_streams:c.int,
  demixing_matrix:[^]byte,
  demixing_matrix_size:opus_int32,
) -> c.int ---


/** Decode a projection Opus packet.
* @param st <tt>OpusProjectionDecoder*</tt>: Projection decoder state.
* @param[in] data <tt>const unsigned char*</tt>: Input payload.
*                                                Use a <code>NULL</code>
*                                                pointer to indicate packet
*                                                loss.
* @param len <tt>opus_int32</tt>: Number of bytes in payload.
* @param[out] pcm <tt>opus_int16*</tt>: Output signal, with interleaved
*                                       samples.
*                                       This must contain room for
*                                       <code>frame_size*channels</code>
*                                       samples.
* @param frame_size <tt>int</tt>: The number of samples per channel of
*                                 available space in \a pcm.
*                                 If this is less than the maximum packet duration
*                                 (120 ms --- 5760 for 48kHz), this function will not be capable
*                                 of decoding some packets. In the case of PLC (data==NULL)
*                                 or FEC (decode_fec=1), then frame_size needs to be exactly
*                                 the duration of audio that is missing, otherwise the
*                                 decoder will not be in the optimal state to decode the
*                                 next incoming packet. For the PLC and FEC cases, frame_size
*                                 <b>must</b> be a multiple of 2.5 ms.
* @param decode_fec <tt>int</tt>: Flag (0 or 1) to request that any in-band
*                                 forward error correction data be decoded.
*                                 If no such data is available, the frame is
*                                 decoded as if it were lost.
* @returns Number of samples decoded on success or a negative error code
*          (see @ref opus_errorcodes) on failure.
*/
@(require_results) opus_projection_decode :: proc(
  st:^OpusProjectionDecoder,
  data:[^]byte,
  len:opus_int32,
  pcm:[^]opus_int16,
  frame_size:c.int,
  decode_fec:c.int
) -> c.int ---


/** Decode a projection Opus packet with floating point output.
* @param st <tt>OpusProjectionDecoder*</tt>: Projection decoder state.
* @param[in] data <tt>const unsigned char*</tt>: Input payload.
*                                                Use a <code>NULL</code>
*                                                pointer to indicate packet
*                                                loss.
* @param len <tt>opus_int32</tt>: Number of bytes in payload.
* @param[out] pcm <tt>float</tt>: Output signal, with interleaved////opus_int16*</tt>: Output signal, with interleaved
*                                       samples.
*                                       This must contain room for
*                                       <code>frame_size*channels</code>
*                                       samples.
* @param frame_size <tt>int</tt>: The number of samples per channel of
*                                 available space in \a pcm.
*                                 If this is less than the maximum packet duration
*                                 (120 ms --- 5760 for 48kHz), this function will not be capable
*                                 of decoding some packets. In the case of PLC (data==NULL)
*                                 or FEC (decode_fec=1), then frame_size needs to be exactly
*                                 the duration of audio that is missing, otherwise the
*                                 decoder will not be in the optimal state to decode the
*                                 next incoming packet. For the PLC and FEC cases, frame_size
*                                 <b>must</b> be a multiple of 2.5 ms.
* @param decode_fec <tt>int</tt>: Flag (0 or 1) to request that any in-band
*                                 forward error correction data be decoded.
*                                 If no such data is available, the frame is
*                                 decoded as if it were lost.
* @returns Number of samples decoded on success or a negative error code
*          (see @ref opus_errorcodes) on failure.
*/
@(require_results) opus_projection_decode_float :: proc(
  st:^OpusProjectionDecoder,
  data:[^]byte,
  len:opus_int32,
  pcm:[^]c.float,
  frame_size:c.int,
  decode_fec:c.int
) -> c.int ---


/** Perform a CTL function on a projection Opus decoder.
*
* Generally the request and subsequent arguments are generated by a
* convenience macro.
* @param st <tt>OpusProjectionDecoder*</tt>: Projection decoder state.
* @param request This and all remaining parameters should be replaced by one
*                of the convenience macros in @ref opus_genericctls,
*                @ref opus_decoderctls, @ref opus_multistream_ctls, or
*                @ref opus_projection_ctls.
* @see opus_genericctls
* @see opus_decoderctls
* @see opus_multistream_ctls
* @see opus_projection_ctls
*/
opus_projection_decoder_ctl :: proc(st:^OpusProjectionDecoder, request:c.int, #c_vararg args:..any) -> c.int ---


/** Frees an <code>OpusProjectionDecoder</code> allocated by
* opus_projection_decoder_create().
* @param st <tt>OpusProjectionDecoder</tt>: Projection decoder state to be freed.
*/
opus_projection_decoder_destroy :: proc(st:^OpusProjectionDecoder) ---

//opus_projection.h end
}

//TODO (xfitgd) opus_custom.h