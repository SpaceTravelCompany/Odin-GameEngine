package engine

import "core:math/rand"
import "base:intrinsics"
import "base:runtime"
import "core:debug/trace"
import "core:math"
import img "core:image"
import "core:math/linalg"
import "core:mem"
import vk "vendor:vulkan"
import "core:sync"
import "core:log"


image_center_pt_pos :: enum {
    Center,
    Left,
    Right,
    TopLeft,
    Top,
    TopRight,
    BottomLeft,
    Bottom,
    BottomRight,
}

texture_array :: struct {
    using _: texture,
    count: u32,
}

tile_texture_array :: struct {
    using _: texture,
    count: u32,
}

/*
Image object structure for rendering textures

Extends iobject with texture source data
*/
image :: struct {
    using _:itransform_object,
    src: ^texture,
}

is_any_image_type :: #force_inline proc "contextless" ($any_image:typeid) -> bool {
    return intrinsics.type_is_subtype_of(any_image, iobject) && intrinsics.type_has_field(any_image, "src") && 
    (intrinsics.type_field_type(any_image, "src") == ^texture ||
    intrinsics.type_field_type(any_image, "src") == texture_array ||
    intrinsics.type_field_type(any_image, "src") == tile_texture_array)
}

@private image_vtable :iobject_vtable = iobject_vtable {
    draw = auto_cast _super_image_draw,
}

_super_image_deinit :: _super_itransform_object_deinit

image_init :: proc(self:^image, src:^texture,
colorTransform:^color_transform = nil, vtable:^iobject_vtable = nil) {
    self.src = src
        
    self.set.bindings = descriptor_set_binding__base_uniform_pool[:]
    self.set.size = descriptor_pool_size__base_uniform_pool[:]
    self.set.layout = base_descriptor_set_layout()

    self.vtable = vtable == nil ? &image_vtable : vtable
    if self.vtable.draw == nil do self.vtable.draw = auto_cast _super_image_draw

    itransform_object_init(self, colorTransform, self.vtable)
	self.actual_type = typeid_of(image)
}

/*
Gets the texture source of the image

Inputs:
- self: Pointer to the image

Returns:
- Pointer to the texture source
*/
image_get_texture :: #force_inline proc "contextless" (self:^image) -> ^texture {
    return self.src
}

// /*
// Gets the camera of the image

// Inputs:
// - self: Pointer to the image

// Returns:
// - Pointer to the camera
// */
// image_get_camera :: proc "contextless" (self:^image) -> ^camera {
//     return iobject_get_camera(self)
// }

// /*
// Gets the projection of the image

// Inputs:
// - self: Pointer to the image

// Returns:
// - Pointer to the projection
// */
// image_get_projection :: proc "contextless" (self:^image) -> ^projection {
//     return iobject_get_projection(self)
// }

/*
Gets the color transform of the image

Inputs:
- self: Pointer to the image

Returns:
- Pointer to the color transform
*/
image_get_color_transform :: proc "contextless" (self:^image) -> ^color_transform {
    return itransform_object_get_color_transform(self)
}

image_update_transform :: #force_inline proc(self:^image, pos:linalg.point3d, rotation:f32 = 0.0, scale:linalg.point = {1,1}, pivot:linalg.point = {0.0,0.0}) {
    itransform_object_update_transform(self, pos, rotation, scale, pivot)
}
image_update_transform_matrix_raw :: #force_inline proc(self:^image, _mat:linalg.matrix44) {
    itransform_object_update_transform_matrix_raw(self, _mat)
}
// image_update_camera :: #force_inline proc(self:^image, camera:^camera) {
//     iobject_update_camera(self, camera)
// }
// image_update_projection :: #force_inline proc(self:^image, projection:^projection) {
//     iobject_update_projection(self, projection)
// }
image_update_texture :: #force_inline proc "contextless" (self:^image, src:^texture) {
    self.src = src
}
image_change_color_transform :: #force_inline proc(self:^image, colorTransform:^color_transform) {
    itransform_object_change_color_transform(self, colorTransform)
}

_super_image_draw :: proc (self:^image, cmd:command_buffer, viewport:^viewport) {
	//self의 uniform, texture 리소스가 준비가 안됨. 드로우 하면 안됨.
	if graphics_get_resource_draw(self) == nil do return
	if graphics_get_resource_draw(self.src) == nil do return

   	image_binding_sets_and_draw(cmd, self.set, viewport.set, self.src.set)
}

/*
Binds descriptor sets and draws an image

Inputs:
- cmd: Command buffer to record draw commands
- imageSet: Descriptor set for the image transform uniforms
- textureSet: Descriptor set for the texture

Returns:
- None
*/
image_binding_sets_and_draw :: proc "contextless" (cmd:command_buffer, imageSet:descriptor_set, viewSet:descriptor_set, textureSet:descriptor_set) {
    graphics_cmd_bind_pipeline(cmd, .GRAPHICS, get_img_pipeline().__pipeline)
    graphics_cmd_bind_descriptor_sets(cmd, .GRAPHICS, get_img_pipeline().__pipeline_layout, 0, 3,
        &([]vk.DescriptorSet{imageSet.__set, viewSet.__set, textureSet.__set})[0], 0, nil)

    graphics_cmd_draw(cmd, 6, 1, 0, 0)
}

/*
Initializes a texture with the given width, height, pixels, and sampler

**Note:** `pixels_allocator` is used to delete pixels when texture init is done. (async) If pixels_allocator is nil, not delete pixels.
if you pixel allocated with any image_converter, you should make custom allocator to destory this image_converter.

Inputs:
- self: Pointer to the texture to initialize
- width: Width of the texture
- height: Height of the texture
- pixels: Pixels of the texture
- pixels_allocator: The allocator to use for the pixels
- sampler: The sampler to use for the texture
- resource_usage: The resource usage to use for the texture
- in_pixel_fmt: The pixel format to use for the texture

Returns:
- None

Example:
	package image_test

	import "core:debug/trace"
	import "base:runtime"
	import "core:engine"
	import "core:log"

	panda_img : []u8 = #load("res/panda.qoi")

	panda_img_allocator_proc :: proc(allocator_data:rawptr, mode: runtime.Allocator_Mode, size:int, alignment:int, old_memory:rawptr, old_size:int, loc := #caller_location) -> ([]byte, runtime.Allocator_Error) {
		#partial switch mode {
		case .Free:
			qoiD :^qoi_converter = auto_cast allocator_data
			qoi_converter_deinit(qoiD)
			free(qoiD, def_allocator())
		}
		return nil, nil
	}
	
	init :: proc() {
		qoiD := new(qoi_converter, def_allocator())
		
		imgData, errCode := image_converter_load(qoiD, panda_img, .RGBA)
		if errCode != nil {
			log.panicf("image_converter_load : %s\n", errCode)
		}
		
		texture_init(&texture,
		u32(image_converter_width(qoiD)), u32(image_converter_height(qoiD)), imgData,
		runtime.Allocator{
			procedure = panda_img_allocator_proc,
			data = auto_cast qoiD,
		})
	}
*/
texture_init :: proc(
	self: ^texture,
	width: u32,
	height: u32,
	pixels: []byte,
    pixels_allocator: Maybe(runtime.Allocator) = nil,
	sampler: vk.Sampler = 0,
	resource_usage: resource_usage = .GPU,
	in_pixel_fmt: img.color_fmt = .RGBA,
) {
	self.sampler = sampler == 0 ? linear_sampler : sampler
	self.set.bindings = descriptor_set_binding__single_pool[:]
	self.set.size = descriptor_pool_size__single_sampler_pool[:]
	self.set.layout = __img_descriptor_set_layout
	self.set.__set = 0

	color_fmt_convert_default_overlap(pixels, pixels, in_pixel_fmt)

	buffer_resource_create_texture(self, {
		width = width,
		height = height,
		use_gcpu_mem = false,
		format = .DefaultColor,
		samples = 1,
		len = 1,
		texture_usage = {.IMAGE_RESOURCE},
		type = .TEX2D,
		resource_usage = resource_usage,
		single = false,
	}, self.sampler, pixels, false, pixels_allocator)

	if self.set.__resources != nil do __graphics_free_descriptor_resources(self.set.__resources)
	self.set.__resources = __graphics_alloc_descriptor_resources(1)
	self.set.__resources[0] = graphics_get_resource(self).(^texture_resource)
	update_descriptor_sets(mem.slice_ptr(&self.set, 1))
	self.pixel_data = pixels
	self.width = width
	self.height = height
}

/*
Initializes a grey texture with the given width, height, pixels, and sampler

Inputs:
- self: Pointer to the texture to initialize
- width: Width of the texture
- height: Height of the texture
- pixels: Pixels of the texture
- pixels_allocator: The allocator to use for the pixels

Returns:
- None
*/
texture_init_grey :: proc(
	self: ^texture,
	width: u32,
	height: u32,
	pixels: []byte,
	pixels_allocator: Maybe(runtime.Allocator) = nil,
	sampler: vk.Sampler = 0,
	resource_usage: resource_usage = .GPU,
) {
	self.sampler = sampler == 0 ? linear_sampler : sampler
	self.set.bindings = descriptor_set_binding__single_pool[:]
	self.set.size = descriptor_pool_size__single_sampler_pool[:]
	self.set.layout = __img_descriptor_set_layout
	self.set.__set = 0

	buffer_resource_create_texture(self, {
		width = width,
		height = height,
		use_gcpu_mem = false,
		format = .R8Unorm,
		samples = 1,
		len = 1,
		texture_usage = {.IMAGE_RESOURCE},
		type = .TEX2D,
		resource_usage = resource_usage,
		single = false,
	}, self.sampler, pixels, false, pixels_allocator)


	if self.set.__resources != nil do __graphics_free_descriptor_resources(self.set.__resources)
	self.set.__resources = __graphics_alloc_descriptor_resources(1)
	self.set.__resources[0] = graphics_get_resource(self).(^texture_resource)
	update_descriptor_sets(mem.slice_ptr(&self.set, 1))
	self.pixel_data = pixels
	self.width = width
	self.height = height
}


//sampler nil default //TODO (xfitgd)
// texture_init_r8 :: proc(self:^texture, width:u32, height:u32) {
//     self.sampler = 0
//     self.set.bindings = nil
//     self.set.size = nil
//     self.set.layout = 0
//     self.set.__set = 0

//     vk_buffer_resource_create_texture(&self.texture, {
//         width = width,
//         height = height,
//         use_gcpu_mem = false,
//         format = .R8Unorm,
//         samples = 1,
//         len = 1,
//         texture_usage = {.FRAME_BUFFER, .__INPUT_ATTACHMENT},
//         type = .TEX2D,
//         resource_usage = .GPU,
//         single = true,
//     }, self.sampler, nil)
// }


/*
Initializes a depth-stencil texture

Inputs:
- self: Pointer to the texture to initialize
- width: Width of the texture
- height: Height of the texture

Returns:
- None
*/
texture_init_depth_stencil :: proc(self:^texture, width:u32, height:u32) {
    self.sampler = 0
    self.set.bindings = nil
    self.set.size = nil
    self.set.layout = 0
    self.set.__set = 0

    buffer_resource_create_texture(self, {
        width = width,
        height = height,
        use_gcpu_mem = false,
        format = .DefaultDepth,
        samples = auto_cast msaa_count,
        len = 1,
        texture_usage = {.FRAME_BUFFER},
        type = .TEX2D,
        single = true,
        resource_usage = .GPU
    }, self.sampler, nil)
	self.width = width
	self.height = height
}

/*
Initializes an MSAA texture

Inputs:
- self: Pointer to the texture to initialize
- width: Width of the texture
- height: Height of the texture

Returns:
- None
*/
texture_init_msaa :: proc(self:^texture, width:u32, height:u32) {
    self.sampler = 0
    self.set.bindings = nil
    self.set.size = nil
    self.set.layout = 0
    self.set.__set = 0

    buffer_resource_create_texture(self, {
        width = width,
        height = height,
        use_gcpu_mem = false,
        format = .DefaultColor,
        samples = auto_cast msaa_count,
        len = 1,
        texture_usage = {.FRAME_BUFFER,.__TRANSIENT_ATTACHMENT},
        type = .TEX2D,
        single = true,
        resource_usage = .GPU
    }, self.sampler, nil)
	self.width = width
	self.height = height
}

/*
Deinitializes and cleans up texture resources

Inputs:
- self: Pointer to the texture to deinitialize

Returns:
- None
*/
texture_deinit :: #force_inline proc(self:^texture) {
    buffer_resource_deinit(self)
	if self.set.__resources != nil {
		__graphics_free_descriptor_resources(self.set.__resources)
		self.set.__resources = nil
	}
}


texture_width :: #force_inline proc "contextless" (self:^texture) -> u32{
    return self.width
}

texture_height :: #force_inline proc "contextless" (self:^texture) -> u32 {
    return self.height
}

/*
Gets the default linear sampler

Returns:
- The default linear sampler
*/
get_default_linear_sampler :: #force_inline proc "contextless" () -> vk.Sampler {
    return linear_sampler
}

/*
Gets the default nearest sampler

Returns:
- The default nearest sampler
*/
get_default_nearest_sampler :: #force_inline proc "contextless" () -> vk.Sampler {
    return nearest_sampler
}



/*
Initializes a texture array with multiple textures

Inputs:
- self: Pointer to the texture array to initialize
- width: Width of each texture
- height: Height of each texture
- count: Number of textures in the array
- pixels: Pixel data for all textures
- sampler: Sampler to use (default: 0, uses default linear sampler)
- inPixelFmt: Input pixel format (default: .RGBA)

Returns:
- None
*/
texture_array_init :: proc(self:^texture_array, width:u32, height:u32, count:u32, pixels:[]byte, sampler:vk.Sampler = 0, inPixelFmt:img.color_fmt = .RGBA) {
    self.sampler = sampler == 0 ? linear_sampler : sampler
    self.set.bindings = descriptor_set_binding__single_pool[:]
    self.set.size = descriptor_pool_size__single_sampler_pool[:]
    self.set.layout = __img_descriptor_set_layout
    self.set.__set = 0

    allocPixels := mem.make_non_zeroed_slice([]byte, count * width * height * 4, context.allocator)
    color_fmt_convert_default(pixels, allocPixels, inPixelFmt)

    buffer_resource_create_texture(self, {
        width = width,
        height = height,
        use_gcpu_mem = false,
        format = .DefaultColor,
        samples = 1,
        len = count,
        texture_usage = {.IMAGE_RESOURCE},
        type = .TEX2D,
        resource_usage = .GPU,
    }, self.sampler, allocPixels, false, context.allocator)

	if self.set.__resources != nil do __graphics_free_descriptor_resources(self.set.__resources)
    self.set.__resources = __graphics_alloc_descriptor_resources(1)
    self.set.__resources[0] = graphics_get_resource(self).(^texture_resource)
    update_descriptor_sets(mem.slice_ptr(&self.set, 1))
	self.pixel_data = pixels
	self.width = width
	self.height = height
	self.count = count
}

texture_array_deinit :: #force_inline proc(self:^texture_array) {
    buffer_resource_deinit(self)
	if self.set.__resources != nil {
		__graphics_free_descriptor_resources(self.set.__resources)
		self.set.__resources = nil
	}
}

texture_array_width :: #force_inline proc "contextless" (self:^texture_array) -> u32 {
    return self.width
}

texture_array_height :: #force_inline proc "contextless" (self:^texture_array) -> u32 {
    return self.height
}

texture_array_count :: #force_inline proc "contextless" (self:^texture_array) -> u32 {
    return self.count
}

/*
Converts pixel format to the default graphics format

Inputs:
- pixels: Input pixel data
- out: Output buffer for converted pixels
- inPixelFmt: Input pixel format (default: .RGBA)

Returns:
- None
*/
color_fmt_convert_default :: proc (pixels:[]byte, out:[]byte, inPixelFmt:img.color_fmt = .RGBA) {
    defcol := default_color_fmt()
    if defcol == inPixelFmt {
        mem.copy_non_overlapping(&out[0], &pixels[0], len(pixels))
    } else if inPixelFmt == .RGBA || inPixelFmt == .BGRA { //convert pixel format
        for i in 0..<len(pixels)/4 {//TODO SIMD (xfigd)    
            out[i * 4 + 0] = pixels[i * 4 + 2]
            out[i * 4 + 1] = pixels[i * 4 + 1]
            out[i * 4 + 2] = pixels[i * 4 + 0]
            out[i * 4 + 3] = pixels[i * 4 + 3]
        }   
    } else {
        log.errorf("color_fmt_convert_default: Unsupported pixel format: %s\n", inPixelFmt)
    }
}

/*
Converts pixel format to the default graphics format (in-place conversion)

Inputs:
- pixels: Input pixel data
- out: Output buffer for converted pixels (can overlap with input)
- inPixelFmt: Input pixel format (default: .RGBA)

Returns:
- None
*/
color_fmt_convert_default_overlap :: proc (pixels:[]byte, out:[]byte, inPixelFmt:img.color_fmt = .RGBA) {
    defcol := default_color_fmt()
    if defcol == inPixelFmt {
        if &pixels[0] != &out[0] do mem.copy(&out[0], &pixels[0], len(pixels))
    } else if inPixelFmt == .RGBA || inPixelFmt == .BGRA { //convert pixel format
        for i in 0..<len(pixels)/4 {//TODO SIMD (xfigd)
            temp:[4]byte
            temp[0] = pixels[i * 4 + 2]
            temp[1] = pixels[i * 4 + 1]
            temp[2] = pixels[i * 4 + 0]
            temp[3] = pixels[i * 4 + 3]

            out[i * 4 + 0] = temp[0]
            out[i * 4 + 1] = temp[1]
            out[i * 4 + 2] = temp[2]
            out[i * 4 + 3] = temp[3]
        }   
    } else {
        log.errorf("color_fmt_convert_default: Unsupported pixel format: %s\n", inPixelFmt)
    }
}

/*
Calculates pixel-perfect point position for an image

Inputs:
- img: Pointer to any image type
- p: Point to adjust
- canvasW: Canvas width
- canvasH: Canvas height
- pivot: Pivot position for the image

Returns:
- Adjusted point for pixel-perfect rendering
*/
image_pixel_perfect_point :: proc "contextless" (img:^$ANY_IMAGE, p:linalg.point, canvasW:f32, canvasH:f32, pivot:image_center_pt_pos) -> linalg.point 
where is_any_image_type(ANY_IMAGE) {
    width := __windowWidth
    height := __windowHeight
    widthF := f32(width)
    heightF := f32(height)
    if widthF / heightF > canvasW / canvasH {
        if canvasH != heightF do return p
    } else {
        if canvasW != width do return p
    }
    p = linalg.floor(p)
    if width % 2 == 0 do p.x -= 0.5
    if height % 2 == 0 do p.y += 0.5


	if img.src == nil {
		return p
	}
	img_width := img.src.ptr.tex.option.width
	img_height := img.src.ptr.tex.option.height

    #partial switch pivot {
        case .Center:
            if img_width % 2 != 0 do p.x += 0.5
            if img_height % 2 != 0 do p.y -= 0.5
        case .Left, .Right:
            if img_height % 2 != 0 do p.y -= 0.5
        case .Top, .Bottom:
            if img_width % 2 != 0 do p.x += 0.5
    }
    return p
}



/*
Returns the default color format based on the graphics origin format

Returns:
- The default color format for the current graphics system
*/
default_color_fmt :: proc () -> img.color_fmt {
    return texture_fmt_to_color_fmt(vk_fmt_to_texture_fmt(get_graphics_origin_format()))
}

/*
Converts a texture format to a color format

Inputs:
- t: The texture format to convert

Returns:
- The corresponding color format, or `.Unknown` if unsupported
*/
@(require_results) texture_fmt_to_color_fmt :: proc (t:texture_fmt) -> img.color_fmt {
	#partial switch t {
		case .DefaultColor:
			return texture_fmt_to_color_fmt(vk_fmt_to_texture_fmt(get_graphics_origin_format()))
		case .R8G8B8A8Unorm:
			return .RGBA
		case .B8G8R8A8Unorm:
			return .BGRA
	}
    log.errorf("unsupport format texture_fmt_to_color_fmt : %s\n", t)
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
@(require_results) texture_fmt_bit_size :: proc (fmt:texture_fmt) -> u32 {
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

@(require_results) @private vk_fmt_to_texture_fmt :: proc (t:vk.Format) -> texture_fmt {
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
	log.panicf("unsupport format vk_fmt_to_texture_fmt : %s\n", t)
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

img_descriptor_set_layout :: proc "contextless" () -> vk.DescriptorSetLayout {
	return __img_descriptor_set_layout
}