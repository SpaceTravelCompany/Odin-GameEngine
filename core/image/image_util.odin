package image


import "core:debug/trace"

// ============================================================================
// Color Format Utilities
// ============================================================================

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
            trace.panic_log("unknown")
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
