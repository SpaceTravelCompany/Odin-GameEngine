package image

import "core:log"
import "core:mem"
import "core:math"

/*
Returns the bit size of the given color format

Inputs:
- fmt: The color format to get the bit size for

Returns:
- The number of bits per pixel for the given format
*/
color_fmt_bit :: proc "contextless" (fmt: color_fmt) -> u32 {
    switch fmt {
        case .RGB, .BGR : return 24
        case .RGBA, .BGRA, .ABGR, .ARGB, .Gray32, .Gray32F : return 32
        case .Gray : return 8
        case .Gray16 : return 16
        case .RGB16, .BGR16 : return 48
        case .RGBA16, .BGRA16, .ABGR16, .ARGB16 : return 64
        case .RGB32, .BGR32, .RGB32F, .BGR32F : return 96
        case .RGBA32, .BGRA32, .ABGR32, .ARGB32, .RGBA32F, .BGRA32F, .ABGR32F, .ARGB32F : return 128
		case .Unknown:
			return 0
    };
	return 0
}

color_fmt :: enum {
	Unknown,
	RGB,
	BGR,
	RGBA,
	BGRA,
	ARGB,
	ABGR,
	Gray,
	RGB16,
	BGR16,
	RGBA16,
	BGRA16,
	ARGB16,
	ABGR16,
	Gray16,
	RGB32,
	BGR32,
	RGBA32,
	BGRA32,
	ARGB32,
	ABGR32,
	Gray32,
	RGB32F,
	BGR32F,
	RGBA32F,
	BGRA32F,
	ARGB32F,
	ABGR32F,
	Gray32F,
}

@private _is_grey :: proc "contextless" (f: color_fmt) -> bool {
	return f == .Gray || f == .Gray16 || f == .Gray32 || f == .Gray32F
}

@private _swap_rb_4 :: proc(src: []byte, dst: []byte, n: int) {
	for i in 0 ..< n {
		dst[i*4+0] = src[i*4+2]
		dst[i*4+1] = src[i*4+1]
		dst[i*4+2] = src[i*4+0]
		dst[i*4+3] = src[i*4+3]
	}
}
@private _swap_rb_3 :: proc(src: []byte, dst: []byte, n: int) {
	for i in 0 ..< n {
		dst[i*3+0] = src[i*3+2]
		dst[i*3+1] = src[i*3+1]
		dst[i*3+2] = src[i*3+0]
	}
}
@private _drop_a_4_to_3 :: proc(src: []byte, dst: []byte, n: int, swap_rb: bool) {
	for i in 0 ..< n {
		if swap_rb {
			dst[i*3+0] = src[i*4+2]
			dst[i*3+1] = src[i*4+1]
			dst[i*3+2] = src[i*4+0]
		} else {
			dst[i*3+0] = src[i*4+0]
			dst[i*3+1] = src[i*4+1]
			dst[i*3+2] = src[i*4+2]
		}
	}
}
@private _add_a_3_to_4 :: proc(src: []byte, dst: []byte, n: int, swap_rb: bool, a: u8) {
	for i in 0 ..< n {
		if swap_rb {
			dst[i*4+0] = src[i*3+2]
			dst[i*4+1] = src[i*3+1]
			dst[i*4+2] = src[i*3+0]
		} else {
			dst[i*4+0] = src[i*3+0]
			dst[i*4+1] = src[i*3+1]
			dst[i*4+2] = src[i*3+2]
		}
		dst[i*4+3] = a
	}
}

/*
Converts pixel format; same bit-depth only (8/16/32/32F). Allocates output and returns it. Grey formats are not supported (return nil unless in_fmt == out_fmt then copy).
*/
color_fmt_convert :: proc(pixels: []byte, in_fmt: color_fmt, out_fmt: color_fmt, allocator := context.allocator) -> []byte {
	in_bpp := color_fmt_bit(in_fmt) / 8
	out_bpp := color_fmt_bit(out_fmt) / 8
	if in_bpp == 0 || out_bpp == 0 do return nil
	n := len(pixels) / int(in_bpp)
	if n == 0 do return nil

	if in_fmt == out_fmt {
		out := mem.make_non_zeroed_slice([]byte, len(pixels), allocator)
		mem.copy_non_overlapping(raw_data(out), raw_data(pixels), len(pixels))
		return out
	}
	if _is_grey(in_fmt) || _is_grey(out_fmt) do return nil
	if in_bpp != out_bpp do return nil

	out := mem.make_non_zeroed_slice([]byte, n * int(out_bpp), allocator)

	// 8-bit
	if in_bpp == 4 && out_bpp == 4 {
		swap_rb := (in_fmt == .RGBA && out_fmt == .BGRA) || (in_fmt == .BGRA && out_fmt == .RGBA)
		swap_argb := (in_fmt == .ARGB && out_fmt == .ABGR) || (in_fmt == .ABGR && out_fmt == .ARGB)
		if swap_rb do _swap_rb_4(pixels, out, n)
		else if swap_argb {
			for i in 0 ..< n {
				out[i*4+0] = pixels[i*4+0]
				out[i*4+1] = pixels[i*4+3]
				out[i*4+2] = pixels[i*4+2]
				out[i*4+3] = pixels[i*4+1]
			}
		} else do mem.copy_non_overlapping(raw_data(out), raw_data(pixels), n * 4)
		return out
	}
	if in_bpp == 3 && out_bpp == 3 {
		swap := (in_fmt == .RGB && out_fmt == .BGR) || (in_fmt == .BGR && out_fmt == .RGB)
		if swap do _swap_rb_3(pixels, out, n)
		else do mem.copy_non_overlapping(raw_data(out), raw_data(pixels), n * 3)
		return out
	}
	if in_bpp == 4 && out_bpp == 3 {
		swap := (in_fmt == .BGRA && out_fmt == .RGB) || (in_fmt == .RGBA && out_fmt == .BGR) ||
			(in_fmt == .ABGR && out_fmt == .RGB) || (in_fmt == .ARGB && out_fmt == .BGR)
		if in_fmt == .ARGB || in_fmt == .ABGR {
			for i in 0 ..< n {
				out[i*3+0] = pixels[i*4+1]
				out[i*3+1] = pixels[i*4+2]
				out[i*3+2] = pixels[i*4+3]
			}
			if swap {
				for i in 0 ..< n {
					out[i*3+0], out[i*3+2] = out[i*3+2], out[i*3+0]
				}
			}
		} else {
			_drop_a_4_to_3(pixels, out, n, swap)
		}
		return out
	}
	if in_bpp == 3 && out_bpp == 4 {
		swap := (in_fmt == .BGR && (out_fmt == .RGBA || out_fmt == .ARGB)) || (in_fmt == .RGB && (out_fmt == .BGRA || out_fmt == .ABGR))
		if out_fmt == .ARGB || out_fmt == .ABGR {
			for i in 0 ..< n {
				out[i*4+0] = 255
				if swap {
					out[i*4+1] = pixels[i*3+2]
					out[i*4+2] = pixels[i*3+1]
					out[i*4+3] = pixels[i*3+0]
				} else {
					out[i*4+1] = pixels[i*3+0]
					out[i*4+2] = pixels[i*3+1]
					out[i*4+3] = pixels[i*3+2]
				}
			}
		} else {
			_add_a_3_to_4(pixels, out, n, swap, 255)
		}
		return out
	}

	// 16-bit (2 bytes per channel): same patterns, A=0xFFFF
	if in_bpp == 8 && out_bpp == 8 {
		swap := (in_fmt == .RGBA16 && out_fmt == .BGRA16) || (in_fmt == .BGRA16 && out_fmt == .RGBA16) ||
			(in_fmt == .ARGB16 && out_fmt == .ABGR16) || (in_fmt == .ABGR16 && out_fmt == .ARGB16)
		for i in 0 ..< n {
			b := i * 8
			if swap {
				out[b+0], out[b+1] = pixels[b+4], pixels[b+5]
				out[b+2], out[b+3] = pixels[b+2], pixels[b+3]
				out[b+4], out[b+5] = pixels[b+0], pixels[b+1]
				out[b+6], out[b+7] = pixels[b+6], pixels[b+7]
			} else {
				mem.copy_non_overlapping(raw_data(out[b:]), raw_data(pixels[b:]), 8)
			}
		}
		return out
	}
	if in_bpp == 6 && out_bpp == 6 {
		swap := (in_fmt == .RGB16 && out_fmt == .BGR16) || (in_fmt == .BGR16 && out_fmt == .RGB16)
		for i in 0 ..< n {
			b := i * 6
			if swap {
				out[b+0], out[b+1] = pixels[b+4], pixels[b+5]
				out[b+2], out[b+3] = pixels[b+2], pixels[b+3]
				out[b+4], out[b+5] = pixels[b+0], pixels[b+1]
			} else {
				mem.copy_non_overlapping(raw_data(out[b:]), raw_data(pixels[b:]), 6)
			}
		}
		return out
	}
	if in_bpp == 8 && out_bpp == 6 {
		for i in 0 ..< n {
			sb, db := i * 8, i * 6
			#partial switch in_fmt {
			case .RGBA16:
				mem.copy_non_overlapping(raw_data(out[db:]), raw_data(pixels[sb:]), 6)
			case .BGRA16:
				out[db+0], out[db+1] = pixels[sb+4], pixels[sb+5]
				out[db+2], out[db+3] = pixels[sb+2], pixels[sb+3]
				out[db+4], out[db+5] = pixels[sb+0], pixels[sb+1]
			case .ARGB16:
				mem.copy_non_overlapping(raw_data(out[db:]), raw_data(pixels[sb+2:]), 6)
			case .ABGR16:
				out[db+0], out[db+1] = pixels[sb+6], pixels[sb+7]
				out[db+2], out[db+3] = pixels[sb+4], pixels[sb+5]
				out[db+4], out[db+5] = pixels[sb+2], pixels[sb+3]
			case:
				return nil
			}
			if out_fmt == .BGR16 {
				out[db+0], out[db+1], out[db+4], out[db+5] = out[db+4], out[db+5], out[db+0], out[db+1]
			}
		}
		return out
	}
	if in_bpp == 6 && out_bpp == 8 {
		for i in 0 ..< n {
			sb, db := i * 6, i * 8
			swap := (in_fmt == .BGR16 && (out_fmt == .RGBA16 || out_fmt == .ARGB16)) || (in_fmt == .RGB16 && (out_fmt == .BGRA16 || out_fmt == .ABGR16))
			r0, r1 := pixels[sb+0], pixels[sb+1]
			g0, g1 := pixels[sb+2], pixels[sb+3]
			b0, b1 := pixels[sb+4], pixels[sb+5]
			if swap do r0, r1, b0, b1 = b0, b1, r0, r1
			if out_fmt == .RGBA16 || out_fmt == .BGRA16 {
				out[db+0], out[db+1] = r0, r1
				out[db+2], out[db+3] = g0, g1
				out[db+4], out[db+5] = b0, b1
				out[db+6], out[db+7] = 0xFF, 0xFF
			} else {
				out[db+0], out[db+1] = 0xFF, 0xFF
				out[db+2], out[db+3] = r0, r1
				out[db+4], out[db+5] = g0, g1
				out[db+6], out[db+7] = b0, b1
			}
		}
		return out
	}

	// 32-bit int or 32F (4 bytes per channel)
	if in_bpp == 16 && out_bpp == 16 {
		swap := (in_fmt == .RGBA32 && out_fmt == .BGRA32) || (in_fmt == .BGRA32 && out_fmt == .RGBA32) ||
			(in_fmt == .RGBA32F && out_fmt == .BGRA32F) || (in_fmt == .BGRA32F && out_fmt == .RGBA32F)
		for i in 0 ..< n {
			b := i * 16
			if swap {
				mem.copy_non_overlapping(raw_data(out[b+0:]), raw_data(pixels[b+8:]), 4)
				mem.copy_non_overlapping(raw_data(out[b+4:]), raw_data(pixels[b+4:]), 4)
				mem.copy_non_overlapping(raw_data(out[b+8:]), raw_data(pixels[b+0:]), 4)
				mem.copy_non_overlapping(raw_data(out[b+12:]), raw_data(pixels[b+12:]), 4)
			} else {
				mem.copy_non_overlapping(raw_data(out[b:]), raw_data(pixels[b:]), 16)
			}
		}
		return out
	}
	if in_bpp == 12 && out_bpp == 12 {
		swap := (in_fmt == .RGB32 && out_fmt == .BGR32) || (in_fmt == .BGR32 && out_fmt == .RGB32) ||
			(in_fmt == .RGB32F && out_fmt == .BGR32F) || (in_fmt == .BGR32F && out_fmt == .RGB32F)
		for i in 0 ..< n {
			b := i * 12
			if swap {
				mem.copy_non_overlapping(raw_data(out[b+0:]), raw_data(pixels[b+8:]), 4)
				mem.copy_non_overlapping(raw_data(out[b+4:]), raw_data(pixels[b+4:]), 4)
				mem.copy_non_overlapping(raw_data(out[b+8:]), raw_data(pixels[b+0:]), 4)
			} else {
				mem.copy_non_overlapping(raw_data(out[b:]), raw_data(pixels[b:]), 12)
			}
		}
		return out
	}
	if in_bpp == 16 && out_bpp == 12 {
		swap_in := (in_fmt == .BGRA32 || in_fmt == .BGRA32F)
		swap_out := (out_fmt == .BGR32 || out_fmt == .BGR32F)
		for i in 0 ..< n {
			sb, db := i * 16, i * 12
			if swap_in {
				mem.copy_non_overlapping(raw_data(out[db+0:]), raw_data(pixels[sb+8:]), 4)
				mem.copy_non_overlapping(raw_data(out[db+4:]), raw_data(pixels[sb+4:]), 4)
				mem.copy_non_overlapping(raw_data(out[db+8:]), raw_data(pixels[sb+0:]), 4)
			} else {
				mem.copy_non_overlapping(raw_data(out[db:]), raw_data(pixels[sb:]), 12)
			}
			if swap_out {
				t: [4]byte
				mem.copy_non_overlapping(&t[0], raw_data(out[db+0:]), 4)
				mem.copy_non_overlapping(raw_data(out[db+0:]), raw_data(out[db+8:]), 4)
				mem.copy_non_overlapping(raw_data(out[db+8:]), &t[0], 4)
			}
		}
		return out
	}
	if in_bpp == 12 && out_bpp == 16 {
		is_32f := out_fmt == .RGBA32F || out_fmt == .BGRA32F
		one_f: f32 = 1.0
		for i in 0 ..< n {
			sb, db := i * 12, i * 16
			swap := (out_fmt == .BGRA32 || out_fmt == .BGRA32F)
			if swap {
				mem.copy_non_overlapping(raw_data(out[db+0:]), raw_data(pixels[sb+8:]), 4)
				mem.copy_non_overlapping(raw_data(out[db+4:]), raw_data(pixels[sb+4:]), 4)
				mem.copy_non_overlapping(raw_data(out[db+8:]), raw_data(pixels[sb+0:]), 4)
			} else {
				mem.copy_non_overlapping(raw_data(out[db:]), raw_data(pixels[sb:]), 12)
			}
			if is_32f do mem.copy_non_overlapping(raw_data(out[db+12:]), &one_f, 4)
			else do out[db+12], out[db+13], out[db+14], out[db+15] = 0xFF, 0xFF, 0xFF, 0xFF
		}
		return out
	}

	return nil
}

/*
Converts tilemap pixel data to sequential tile pixel data.

Reads pixels laid out as a tilemap (tiles in a grid of width) and writes them
as sequential tile data (tile0, tile1, ...) in the same color format.

Inputs:
- pixels: Source tilemap pixel data (row-major, full width)
- fmt: Input/output pixel format (color_fmt)
- tile_width, tile_height: Size of each tile
- width: Width of the source tilemap in pixels
- count: Total number of tiles
- allocator: Allocator for the output slice

Returns:
- Allocated slice of tile data. Caller must free.
*/
tilemap_pixels_to_tile_pixels :: proc(
	pixels: []byte,
	fmt: color_fmt,
	tile_width: u32,
	tile_height: u32,
	width: u32,
	count: u32,
	allocator := context.allocator,
) -> []byte {
	bpp := color_fmt_bit(fmt) / 8
	if bpp == 0 do return nil
	row := math.floor_div(width, tile_width)
	col := math.floor_div(count, row)
	tile_bytes := tile_width * tile_height * bpp
	out := mem.make_non_zeroed_slice([]byte, count * tile_bytes, allocator)
	cnt: u32
	for y in 0 ..< col {
		for x in 0 ..< row {
			for h in 0 ..< tile_height {
				start := cnt * tile_bytes + h * tile_width * bpp
				start_p := (y * tile_height + h) * (width * bpp) + x * tile_width * bpp
				mem.copy_non_overlapping(raw_data(out[start:]), raw_data(pixels[start_p:]), int(tile_width * bpp))
			}
			cnt += 1
		}
	}
	return out
}
