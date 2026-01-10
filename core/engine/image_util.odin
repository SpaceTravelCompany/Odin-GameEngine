package engine

import "base:intrinsics"
import "base:runtime"
import "core:debug/trace"
import "core:mem"
import vk "vendor:vulkan"
import "core:math/rand"

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

/*
Returns the default color format based on the graphics origin format

Returns:
- The default color format for the current graphics system
*/
default_color_fmt :: proc "contextless" () -> color_fmt {
    return texture_fmt_to_color_fmt(vk_fmt_to_texture_fmt(get_graphics_origin_format()))
}

// ============================================================================
// Texture Format Utilities
// ============================================================================

/*
Converts a texture format to a color format

Inputs:
- t: The texture format to convert

Returns:
- The corresponding color format, or `.Unknown` if unsupported
*/
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

/*
Checks if the given texture format is a depth format

Inputs:
- t: The texture format to check

Returns:
- `true` if the format is a depth format, `false` otherwise
*/
@(require_results) texture_fmt_is_depth :: proc  "contextless" (t:texture_fmt) -> bool {
	#partial switch(t) {
		case .D24UnormS8Uint, .D32SfloatS8Uint, .D16UnormS8Uint, .DefaultDepth:
		return true
	}
	return false
}

/*
Returns the bit size of the given texture format

Inputs:
- fmt: The texture format to get the bit size for

Returns:
- The number of bits per pixel for the given format
*/
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

/*
Converts a texture format to a Vulkan format

Inputs:
- t: The texture format to convert

Returns:
- The corresponding Vulkan format
*/
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

/*
Creates a random RGBA texture with the specified dimensions

Inputs:
- width: The width of the texture in pixels
- height: The height of the texture in pixels
- out_texture: Pointer to the texture structure to initialize
- allocator: The allocator to use for the texture data

Returns:
- None
*/
create_random_texture :: proc(width, height: u32, out_texture:^texture, allocator := context.allocator) {
    channels :: 4 // RGBA
    
    // 텍스처 데이터 배열 생성
    texture_data := mem.make_non_zeroed([]u8, width * height * channels, allocator)
    
    // 각 픽셀에 랜덤 RGBA 값 할당
    for y in 0..<height {
        for x in 0..<width {
            pixel_index := (y * width + x) * channels
            
            // 각 채널에 랜덤 값 할당
            texture_data[pixel_index + 0] = u8(rand.uint32() % 256) // R
            texture_data[pixel_index + 1] = u8(rand.uint32() % 256) // G  
            texture_data[pixel_index + 2] = u8(rand.uint32() % 256) // B
            texture_data[pixel_index + 3] = u8(rand.uint32() % 256) // A
        }
    }
    
    // 텍스처 생성
    texture_init(out_texture, width, height, texture_data, allocator)
}


/*
Creates a random grayscale texture with the specified dimensions

Inputs:
- width: The width of the texture in pixels
- height: The height of the texture in pixels
- out_texture: Pointer to the texture structure to initialize
- allocator: The allocator to use for the texture data

Returns:
- None
*/
create_random_texture_grey :: proc(width, height: u32, out_texture:^texture, allocator := context.allocator) {
    texture_data := mem.make_non_zeroed([]u8, width * height, allocator)

    for i in 0..<len(texture_data) {
        texture_data[i] = u8(rand.uint32() % 256)
    }
    texture_init_grey(out_texture, width, height, texture_data, allocator)
}