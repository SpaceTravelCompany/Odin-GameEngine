package engine

import vk "vendor:vulkan"
import "base:runtime"
import "base:intrinsics"
import "core:debug/trace"

TextureFmt :: enum {
    DefaultColor,
    DefaultDepth,
    R8G8B8A8Unorm,
    B8G8R8A8Unorm,
    // B8G8R8A8Srgb,
    // R8G8B8A8Srgb,
    D24UnormS8Uint,
    D32SfloatS8Uint,
    D16UnormS8Uint,
	R8Unorm,
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

color_fmt_bit :: proc "contextless" (fmt: color_fmt) -> int {
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
    return TextureFmtToColorFmt(vkFmtToTextureFmt(vkFmt.format))
}

@(require_results) TextureFmtToColorFmt :: proc "contextless" (t:TextureFmt) -> color_fmt {
	#partial switch t {
		case .DefaultColor:
			return TextureFmtToColorFmt(vkFmtToTextureFmt(vkFmt.format))
		case .R8G8B8A8Unorm:
			return .RGBA
		case .B8G8R8A8Unorm:
			return .BGRA
	}
    trace.printlnLog("unsupport format TextureFmtToColorFmt : ", t)
    return .Unknown
}

@(require_results) TextureFmt_IsDepth :: proc  "contextless" (t:TextureFmt) -> bool {
	#partial switch(t) {
		case .D24UnormS8Uint, .D32SfloatS8Uint, .D16UnormS8Uint, .DefaultDepth:
		return true
	}
	return false
}

@(require_results) TextureFmt_BitSize :: proc  "contextless" (fmt:TextureFmt) -> int {
    switch (fmt) {
        case .DefaultColor : return TextureFmt_BitSize(vkFmtToTextureFmt(vkFmt.format))
        case .DefaultDepth : return TextureFmt_BitSize(__depthFmt)
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

@(require_results) @private TextureFmtToVkFmt :: proc "contextless" (t:TextureFmt) -> vk.Format {
	switch t {
		case .DefaultColor:
			return vkFmt.format
        case .DefaultDepth:
            return TextureFmtToVkFmt(__depthFmt)
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
    return vkFmt.format
}

@(require_results) @private vkFmtToTextureFmt :: proc "contextless" (t:vk.Format) -> TextureFmt {
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
	trace.panic_log("unsupport format vkFmtToTextureFmt : ", t)
}
