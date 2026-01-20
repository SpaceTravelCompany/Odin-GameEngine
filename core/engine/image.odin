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
}

tile_texture_array :: struct {
    using _: texture,
}

/*
Image object structure for rendering textures

Extends iobject with texture source data
*/
image :: struct {
    using _:iobject,
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
    deinit = auto_cast _super_image_deinit,
}

/*
Initializes an image object

Inputs:
- self: Pointer to the image to initialize
- actualType: The actual type of the image (must be a subtype of image)
- src: Pointer to the texture source
- pos: Position of the image
- camera: Pointer to the camera
- projection: Pointer to the projection
- rotation: Rotation angle in radians (default: 0.0)
- scale: Scale factors (default: {1, 1})
- colorTransform: Pointer to color transform (default: nil)
- pivot: Pivot point for transformations (default: {0.0, 0.0})
- vtable: Custom vtable (default: nil, uses default image vtable)

Returns:
- None
*/
image_init :: proc(self:^image, $actualType:typeid, src:^texture, pos:linalg.Point3DF,
rotation:f32 = 0.0, scale:linalg.PointF = {1,1}, colorTransform:^color_transform = nil, pivot:linalg.PointF = {0.0, 0.0},
 vtable:^iobject_vtable = nil) where intrinsics.type_is_subtype_of(actualType, image) {
    self.src = src
        
    self.set.bindings = descriptor_set_binding__base_uniform_pool[:]
    self.set.size = descriptor_pool_size__base_uniform_pool[:]
    self.set.layout = base_descriptor_set_layout

    self.vtable = vtable == nil ? &image_vtable : vtable
    if self.vtable.draw == nil do self.vtable.draw = auto_cast _super_image_draw
    if self.vtable.deinit == nil do self.vtable.deinit = auto_cast _super_image_deinit

    if self.vtable.get_uniform_resources == nil do self.vtable.get_uniform_resources = auto_cast get_uniform_resources_default

    iobject_init(self, actualType, pos, rotation, scale, colorTransform, pivot)
}

image_init2 :: proc(self:^image, $actualType:typeid, src:^texture,
colorTransform:^color_transform = nil, vtable:^iobject_vtable = nil) where intrinsics.type_is_subtype_of(actualType, image) {
    self.src = src
        
    self.set.bindings = descriptor_set_binding__base_uniform_pool[:]
    self.set.size = descriptor_pool_size__base_uniform_pool[:]
    self.set.layout = base_descriptor_set_layout

    self.vtable = vtable == nil ? &image_vtable : vtable
    if self.vtable.draw == nil do self.vtable.draw = auto_cast _super_image_draw
    if self.vtable.deinit == nil do self.vtable.deinit = auto_cast _super_image_deinit

    if self.vtable.get_uniform_resources == nil do self.vtable.get_uniform_resources = auto_cast get_uniform_resources_default

    iobject_init2(self, actualType, colorTransform)
}

_super_image_deinit :: proc(self:^image) {
    _super_iobject_deinit(self)
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
    return iobject_get_color_transform(self)
}

image_update_transform :: #force_inline proc(self:^image, pos:linalg.Point3DF, rotation:f32 = 0.0, scale:linalg.PointF = {1,1}, pivot:linalg.PointF = {0.0,0.0}) {
    iobject_update_transform(self, pos, rotation, scale, pivot)
}
image_update_transform_matrix_raw :: #force_inline proc(self:^image, _mat:linalg.Matrix) {
    iobject_update_transform_matrix_raw(self, _mat)
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
    iobject_change_color_transform(self, colorTransform)
}

_super_image_draw :: proc (self:^image, cmd:command_buffer, viewport:^viewport) {
    mem.ICheckInit_Check(&self.check_init)
    mem.ICheckInit_Check(&self.src.check_init)

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
    graphics_cmd_bind_pipeline(cmd, .GRAPHICS, img_pipeline)
    graphics_cmd_bind_descriptor_sets(cmd, .GRAPHICS, img_pipeline_layout, 0, 3,
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
			trace.panic_log(errCode)
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
	mem.ICheckInit_Init(&self.check_init)
	self.sampler = sampler == 0 ? linear_sampler : sampler
	self.set.bindings = descriptor_set_binding__single_pool[:]
	self.set.size = descriptor_pool_size__single_sampler_pool[:]
	self.set.layout = tex_descriptor_set_layout
	self.set.__set = 0

	color_fmt_convert_default_overlap(pixels, pixels, in_pixel_fmt)

	self.texture = buffer_resource_create_texture({
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

	self.set.__resources = mem.make_non_zeroed_slice([]iresource, 1, __temp_arena_allocator)
	self.set.__resources[0] = self.texture
	update_descriptor_sets(mem.slice_ptr(&self.set, 1))
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
	mem.ICheckInit_Init(&self.check_init)
	self.sampler = sampler == 0 ? linear_sampler : sampler
	self.set.bindings = descriptor_set_binding__single_pool[:]
	self.set.size = descriptor_pool_size__single_sampler_pool[:]
	self.set.layout = tex_descriptor_set_layout
	self.set.__set = 0

	self.texture = buffer_resource_create_texture({
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

	self.set.__resources = mem.make_non_zeroed_slice([]iresource, 1, __temp_arena_allocator)
	self.set.__resources[0] = self.texture
	update_descriptor_sets(mem.slice_ptr(&self.set, 1))
}

//sampler nil default //TODO (xfitgd)
// texture_init_r8 :: proc(self:^texture, width:u32, height:u32) {
//     mem.ICheckInit_Init(&self.check_init)
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
    mem.ICheckInit_Init(&self.check_init)
    self.sampler = 0
    self.set.bindings = nil
    self.set.size = nil
    self.set.layout = 0
    self.set.__set = 0

    self.texture = buffer_resource_create_texture({
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
    mem.ICheckInit_Init(&self.check_init)
    self.sampler = 0
    self.set.bindings = nil
    self.set.size = nil
    self.set.layout = 0
    self.set.__set = 0

    self.texture = buffer_resource_create_texture({
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
}

/*
Deinitializes and cleans up texture resources

Inputs:
- self: Pointer to the texture to deinitialize

Returns:
- None
*/
texture_deinit :: #force_inline proc(self:^texture) {
    mem.ICheckInit_Deinit(&self.check_init)
    buffer_resource_deinit(self.texture)
	self.texture = nil
}

/*
Gets the width of the texture

Inputs:
- self: Pointer to the texture

Returns:
- Width of the texture in pixels
*/
texture_width :: #force_inline proc "contextless" (self:^texture) -> u32{
	if self.texture == nil {
		return 0
	}
	tex: ^texture_resource = auto_cast self.texture
    return auto_cast tex.option.width
}

/*
Gets the height of the texture

Inputs:
- self: Pointer to the texture

Returns:
- Height of the texture in pixels
*/
texture_height :: #force_inline proc "contextless" (self:^texture) -> u32 {
	if self.texture == nil {
		return 0
	}
	tex: ^texture_resource = auto_cast self.texture
    return auto_cast tex.option.height
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
Updates the sampler for the texture

Inputs:
- self: Pointer to the texture
- sampler: The new sampler to use

Returns:
- None
*/
texture_update_sampler :: #force_inline proc "contextless" (self:^texture, sampler:vk.Sampler) {
    self.sampler = sampler
}

/*
Gets the sampler used by the texture

Inputs:
- self: Pointer to the texture

Returns:
- The sampler used by the texture
*/
texture_get_sampler :: #force_inline proc "contextless" (self:^texture) -> vk.Sampler {
    return self.sampler
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
    mem.ICheckInit_Init(&self.check_init)
    self.sampler = sampler == 0 ? linear_sampler : sampler
    self.set.bindings = descriptor_set_binding__single_pool[:]
    self.set.size = descriptor_pool_size__single_sampler_pool[:]
    self.set.layout = tex_descriptor_set_layout
    self.set.__set = 0

    allocPixels := mem.make_non_zeroed_slice([]byte, count * width * height * 4, context.allocator)
    color_fmt_convert_default(pixels, allocPixels, inPixelFmt)

    self.texture = buffer_resource_create_texture({
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

    self.set.__resources = mem.make_non_zeroed_slice([]iresource, 1, __temp_arena_allocator)
    self.set.__resources[0] = self.texture
    update_descriptor_sets(mem.slice_ptr(&self.set, 1))
}

/*
Deinitializes and cleans up texture array resources

Inputs:
- self: Pointer to the texture array to deinitialize

Returns:
- None
*/
texture_array_deinit :: #force_inline proc(self:^texture_array) {
    mem.ICheckInit_Deinit(&self.check_init)
    buffer_resource_deinit(self.texture)
	self.texture = nil
}
/*
Gets the width of textures in the texture array

Inputs:
- self: Pointer to the texture array

Returns:
- Width of each texture in pixels
*/
texture_array_width :: #force_inline proc "contextless" (self:^texture_array) -> u32 {
	if self.texture == nil {
		return 0
	}
	tex: ^texture_resource = auto_cast self.texture
    return auto_cast tex.option.width
}

/*
Gets the height of textures in the texture array

Inputs:
- self: Pointer to the texture array

Returns:
- Height of each texture in pixels
*/
texture_array_height :: #force_inline proc "contextless" (self:^texture_array) -> u32 {
	if self.texture == nil {
		return 0
	}
	tex: ^texture_resource = auto_cast self.texture
    return auto_cast tex.option.height
}

/*
Gets the number of textures in the texture array

Inputs:
- self: Pointer to the texture array

Returns:
- Number of textures in the array
*/
texture_array_count :: #force_inline proc "contextless" (self:^texture_array) -> u32 {
    if self.texture == nil {
        return 0
    }
    tex: ^texture_resource = auto_cast self.texture
    return auto_cast tex.option.len
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
color_fmt_convert_default :: proc "contextless" (pixels:[]byte, out:[]byte, inPixelFmt:img.color_fmt = .RGBA) {
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
        trace.printlnLog("color_fmt_convert_default: Unsupported pixel format: ", inPixelFmt)
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
color_fmt_convert_default_overlap :: proc "contextless" (pixels:[]byte, out:[]byte, inPixelFmt:img.color_fmt = .RGBA) {
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
        trace.printlnLog("color_fmt_convert_default: Unsupported pixel format: ", inPixelFmt)
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
image_pixel_perfect_point :: proc "contextless" (img:^$ANY_IMAGE, p:linalg.PointF, canvasW:f32, canvasH:f32, pivot:image_center_pt_pos) -> linalg.PointF 
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
	img_width := (^texture_resource)(img.src).option.width
	img_height := (^texture_resource)(img.src).option.height

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
default_color_fmt :: proc "contextless" () -> img.color_fmt {
    return texture_fmt_to_color_fmt(vk_fmt_to_texture_fmt(get_graphics_origin_format()))
}

/*
Converts a texture format to a color format

Inputs:
- t: The texture format to convert

Returns:
- The corresponding color format, or `.Unknown` if unsupported
*/
@(require_results) texture_fmt_to_color_fmt :: proc "contextless" (t:texture_fmt) -> img.color_fmt {
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