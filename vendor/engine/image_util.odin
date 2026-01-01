package engine

import "base:intrinsics"
import "base:runtime"
import "core:debug/trace"
import vk "vendor:vulkan"


// ============================================================================
// Color Format Utilities
// ============================================================================

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

default_color_fmt :: proc "contextless" () -> color_fmt {
    return texture_fmt_to_color_fmt(vk_fmt_to_texture_fmt(get_graphics_origin_format()))
}

// ============================================================================
// Texture Format Utilities
// ============================================================================

@(require_results) texture_fmt_to_color_fmt :: proc "contextless" (t:texture_fmt) -> color_fmt {
	#partial switch t {
		case .DefaultColor:
			return texture_fmt_to_color_fmt(vk_fmt_to_texture_fmt(get_graphics_origin_format()))
		case .R8G8B8A8Unorm:
			return .RGBA
		case .B8G8R8A8Unorm:
			return .BGRA
	}
    trace.printlnLog("unsupport format texture_fmt_to_color_fmt : ", t)
    return .Unknown
}

@(require_results) texture_fmt_is_depth :: proc  "contextless" (t:texture_fmt) -> bool {
	#partial switch(t) {
		case .D24UnormS8Uint, .D32SfloatS8Uint, .D16UnormS8Uint, .DefaultDepth:
		return true
	}
	return false
}

@(require_results) texture_fmt_bit_size :: proc  "contextless" (fmt:texture_fmt) -> u32 {
    switch (fmt) {
        case .DefaultColor : return texture_fmt_bit_size(vk_fmt_to_texture_fmt(get_graphics_origin_format()))
        case .DefaultDepth : return texture_fmt_bit_size(depth_fmt)
        case .R8G8B8A8Unorm:
		case .B8G8R8A8Unorm:
		case .D24UnormS8Uint:
            return 4
		case .D16UnormS8Uint:
            return 3
		case .D32SfloatS8Uint:
            return 5
		case .R8Unorm:
			return 1
    }
    return 4
}

@(require_results) texture_fmt_to_vk_fmt :: proc "contextless" (t:texture_fmt) -> vk.Format {
	switch t {
		case .DefaultColor:
			return get_graphics_origin_format()
        case .DefaultDepth:
            return texture_fmt_to_vk_fmt(depth_fmt)
		case .R8G8B8A8Unorm:
			return .R8G8B8A8_UNORM
		case .B8G8R8A8Unorm:
			return .B8G8R8A8_UNORM
		case .D24UnormS8Uint:
			return .D24_UNORM_S8_UINT
		case .D16UnormS8Uint:
			return .D16_UNORM_S8_UINT
		case .D32SfloatS8Uint:
			return .D32_SFLOAT_S8_UINT
		case .R8Unorm:
			return .R8_UNORM
	}
    return get_graphics_origin_format()
}

// ============================================================================
// Private Vulkan Format Conversion
// ============================================================================

@(require_results) @private vk_fmt_to_texture_fmt :: proc "contextless" (t:vk.Format) -> texture_fmt {
	#partial switch t {
		case .R8G8B8A8_UNORM:
			return .R8G8B8A8Unorm
		case .B8G8R8A8_UNORM:
			return .B8G8R8A8Unorm
		case .D24_UNORM_S8_UINT:
			return .D24UnormS8Uint
		case .D16_UNORM_S8_UINT:
			return .D16UnormS8Uint
		case .D32_SFLOAT_S8_UINT:
			return .D32SfloatS8Uint
		case .R8_UNORM:
			return .R8Unorm
	}
	trace.panic_log("unsupport format vk_fmt_to_texture_fmt : ", t)
}
