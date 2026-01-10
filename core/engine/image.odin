package engine

import "base:intrinsics"
import "base:runtime"
import "core:debug/trace"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:slice"
import "core:sync"
import vk "vendor:vulkan"


// ============================================================================
// Type Definitions
// ============================================================================

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

/*
Animated image object structure for rendering animated textures

Extends ianimate_object with texture array source data
*/
animate_image :: struct {
    using _:ianimate_object,
    src: ^texture_array,
}

/*
Tile image object structure for rendering tiled textures

Extends iobject with tile texture array and tile index
*/
tile_image :: struct {
    using object:iobject,
    tile_uniform:buffer_resource,
    tile_idx:u32,
    src: ^tile_texture_array,
}

// ============================================================================
// Type Checking
// ============================================================================

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
camera:^camera, projection:^projection,
rotation:f32 = 0.0, scale:linalg.PointF = {1,1}, colorTransform:^color_transform = nil, pivot:linalg.PointF = {0.0, 0.0},
 vtable:^iobject_vtable = nil) where intrinsics.type_is_subtype_of(actualType, image) {
    self.src = src
        
    self.set.bindings = descriptor_set_binding__transform_uniform_pool[:]
    self.set.size = descriptor_pool_size__transform_uniform_pool[:]
    self.set.layout = tex_descriptor_set_layout

    self.vtable = vtable == nil ? &image_vtable : vtable
    if self.vtable.draw == nil do self.vtable.draw = auto_cast _super_image_draw
    if self.vtable.deinit == nil do self.vtable.deinit = auto_cast _super_image_deinit

    if self.vtable.get_uniform_resources == nil do self.vtable.get_uniform_resources = auto_cast get_uniform_resources_default

    iobject_init(self, actualType, pos, rotation, scale, camera, projection, colorTransform, pivot)
}

image_init2 :: proc(self:^image, $actualType:typeid, src:^texture,
camera:^camera, projection:^projection,
colorTransform:^color_transform = nil, vtable:^iobject_vtable = nil) where intrinsics.type_is_subtype_of(actualType, image) {
    self.src = src
        
    self.set.bindings = descriptor_set_binding__transform_uniform_pool[:]
    self.set.size = descriptor_pool_size__transform_uniform_pool[:]
    self.set.layout = tex_descriptor_set_layout

    self.vtable = vtable == nil ? &image_vtable : vtable
    if self.vtable.draw == nil do self.vtable.draw = auto_cast _super_image_draw
    if self.vtable.deinit == nil do self.vtable.deinit = auto_cast _super_image_deinit

    if self.vtable.get_uniform_resources == nil do self.vtable.get_uniform_resources = auto_cast get_uniform_resources_default

    iobject_init2(self, actualType, camera, projection, colorTransform)
}

// ============================================================================
// Image Cleanup
// ============================================================================

_super_image_deinit :: proc(self:^image) {
    _super_iobject_deinit(self)
}

// ============================================================================
// Image Accessors
// ============================================================================

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

/*
Gets the camera of the image

Inputs:
- self: Pointer to the image

Returns:
- Pointer to the camera
*/
image_get_camera :: proc "contextless" (self:^image) -> ^camera {
    return iobject_get_camera(self)
}

/*
Gets the projection of the image

Inputs:
- self: Pointer to the image

Returns:
- Pointer to the projection
*/
image_get_projection :: proc "contextless" (self:^image) -> ^projection {
    return iobject_get_projection(self)
}

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

// ============================================================================
// Image Update Functions
// ============================================================================

image_update_transform :: #force_inline proc(self:^image, pos:linalg.Point3DF, rotation:f32 = 0.0, scale:linalg.PointF = {1,1}, pivot:linalg.PointF = {0.0,0.0}) {
    iobject_update_transform(self, pos, rotation, scale, pivot)
}
image_update_transform_matrix_raw :: #force_inline proc(self:^image, _mat:linalg.Matrix) {
    iobject_update_transform_matrix_raw(self, _mat)
}
image_update_camera :: #force_inline proc(self:^image, camera:^camera) {
    iobject_update_camera(self, camera)
}
image_update_projection :: #force_inline proc(self:^image, projection:^projection) {
    iobject_update_projection(self, projection)
}
image_update_texture :: #force_inline proc "contextless" (self:^image, src:^texture) {
    self.src = src
}
image_change_color_transform :: #force_inline proc(self:^image, colorTransform:^color_transform) {
    iobject_change_color_transform(self, colorTransform)
}

// ============================================================================
// Image Drawing
// ============================================================================

_super_image_draw :: proc (self:^image, cmd:command_buffer) {
    mem.ICheckInit_Check(&self.check_init)
    mem.ICheckInit_Check(&self.src.check_init)

   image_binding_sets_and_draw(cmd, self.set, self.src.set)
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
image_binding_sets_and_draw :: proc "contextless" (cmd:command_buffer, imageSet:descriptor_set, textureSet:descriptor_set) {
    graphics_cmd_bind_pipeline(cmd, .GRAPHICS, tex_pipeline)
    graphics_cmd_bind_descriptor_sets(cmd, .GRAPHICS, tex_pipeline_layout, 0, 2,
        &([]vk.DescriptorSet{imageSet.__set, textureSet.__set})[0], 0, nil)

    graphics_cmd_draw(cmd, 6, 1, 0, 0)
}

// ============================================================================
// Animate Image Management
// ============================================================================

@private animate_image_vtable :ianimate_object_vtable = ianimate_object_vtable {
    draw = auto_cast _super_animate_image_draw,
    deinit = auto_cast _super_animate_image_deinit,
    get_frame_cnt = auto_cast _super_animate_image_get_frame_cnt,
}

animate_image_init :: proc(self:^animate_image, $actualType:typeid, src:^texture_array, pos:linalg.Point3DF, rotation:f32, scale:linalg.PointF = {1,1}, 
camera:^camera, projection:^projection, colorTransform:^color_transform = nil, pivot:linalg.PointF = {0.0, 0.0}, vtable:^ianimate_object_vtable = nil) where intrinsics.type_is_subtype_of(actualType, animate_image) {
    self.src = src
    
    self.set.bindings = descriptor_set_binding__animate_image_uniform_pool[:]
    self.set.size = descriptor_pool_size__animate_image_uniform_pool[:]
    self.set.layout = animate_tex_descriptor_set_layout

    self.vtable = auto_cast (vtable == nil ? &animate_image_vtable : vtable)
    if self.vtable.draw == nil do self.vtable.draw = auto_cast _super_animate_image_draw
    if self.vtable.deinit == nil do self.vtable.deinit = auto_cast _super_animate_image_deinit
    if ((^ianimate_object_vtable)(self.vtable)).get_frame_cnt == nil do ((^ianimate_object_vtable)(self.vtable)).get_frame_cnt = auto_cast _super_animate_image_get_frame_cnt

    if self.vtable.get_uniform_resources == nil do self.vtable.get_uniform_resources = auto_cast get_uniform_resources_animate_image

    buffer_resource_create_buffer(&self.frame_uniform, {
        len = size_of(u32),
        type = .UNIFORM,
        resource_usage = .CPU,
    }, mem.ptr_to_bytes(&self.frame), true)

    iobject_init(self, actualType, pos, rotation, scale, camera, projection, colorTransform, pivot)
}

animate_image_init2 :: proc(self:^animate_image, $actualType:typeid, src:^texture_array,
camera:^camera, projection:^projection, colorTransform:^color_transform = nil, vtable:^ianimate_object_vtable = nil) where intrinsics.type_is_subtype_of(actualType, animate_image) {
    self.src = src
    
    self.set.bindings = descriptor_set_binding__animate_image_uniform_pool[:]
    self.set.size = descriptor_pool_size__animate_image_uniform_pool[:]
    self.set.layout = animate_tex_descriptor_set_layout

    self.vtable = auto_cast (vtable == nil ? &animate_image_vtable : vtable)
    if self.vtable.draw == nil do self.vtable.draw = auto_cast _super_animate_image_draw
    if self.vtable.deinit == nil do self.vtable.deinit = auto_cast _super_animate_image_deinit
    if ((^ianimate_object_vtable)(self.vtable)).get_frame_cnt == nil do ((^ianimate_object_vtable)(self.vtable)).get_frame_cnt = auto_cast _super_animate_image_get_frame_cnt

    if self.vtable.get_uniform_resources == nil do self.vtable.get_uniform_resources = auto_cast get_uniform_resources_animate_image

    buffer_resource_create_buffer(&self.frame_uniform, {
        len = size_of(u32),
        type = .UNIFORM,
        resource_usage = .CPU,
    }, mem.ptr_to_bytes(&self.frame), true)

    iobject_init2(self, actualType, camera, projection, colorTransform)
}

// ============================================================================
// Animate Image Cleanup
// ============================================================================

_super_animate_image_deinit :: proc(self:^animate_image) {
    clone_frame_uniform := new(buffer_resource, temp_arena_allocator)
    clone_frame_uniform^ = self.frame_uniform
    buffer_resource_deinit(clone_frame_uniform)

    _super_iobject_deinit(auto_cast self)
}

// ============================================================================
// Animate Image Accessors
// ============================================================================

animate_image_get_frame_cnt :: _super_animate_image_get_frame_cnt

/*
Gets the total number of frames for the animated image

Inputs:
- self: Pointer to the animated image

Returns:
- The total number of frames in the texture array
*/
_super_animate_image_get_frame_cnt :: proc "contextless" (self:^animate_image) -> u32 {
    return self.src.texture.option.len
}

/*
Gets the texture array source of the animated image

Inputs:
- self: Pointer to the animated image

Returns:
- Pointer to the texture array source
*/
animate_image_get_texture_array :: #force_inline proc "contextless" (self:^animate_image) -> ^texture_array {
    return self.src
}

/*
Gets the camera of the animated image

Inputs:
- self: Pointer to the animated image

Returns:
- Pointer to the camera
*/
animate_image_get_camera :: proc "contextless" (self:^animate_image) -> ^camera {
    return self.camera
}

/*
Gets the projection of the animated image

Inputs:
- self: Pointer to the animated image

Returns:
- Pointer to the projection
*/
animate_image_get_projection :: proc "contextless" (self:^animate_image) -> ^projection {
    return self.projection
}

/*
Gets the color transform of the animated image

Inputs:
- self: Pointer to the animated image

Returns:
- Pointer to the color transform
*/
animate_image_get_color_transform :: proc "contextless" (self:^animate_image) -> ^color_transform {
    return self.color_transform
}

// ============================================================================
// Animate Image Update Functions
// ============================================================================

animate_image_update_transform :: #force_inline proc(self:^animate_image, pos:linalg.Point3DF, rotation:f32, scale:linalg.PointF = {1,1}, pivot:linalg.PointF = {0.0,0.0}) {
    iobject_update_transform(self, pos, rotation, scale, pivot)
}
animate_image_update_transform_matrix_raw :: #force_inline proc(self:^animate_image, _mat:linalg.Matrix) {
    iobject_update_transform_matrix_raw(self, _mat)
}
animate_image_change_color_transform :: #force_inline proc(self:^animate_image, colorTransform:^color_transform) {
    iobject_change_color_transform(self, colorTransform)
}
animate_image_update_camera :: #force_inline proc(self:^animate_image, camera:^camera) {
    iobject_update_camera(self, camera)
}
animate_image_update_texture_array :: #force_inline proc "contextless" (self:^animate_image, src:^texture_array) {
    self.src = src
}
animate_image_update_projection :: #force_inline proc(self:^animate_image, projection:^projection) {
    iobject_update_projection(self, projection)
}

// ============================================================================
// Animate Image Drawing
// ============================================================================

_super_animate_image_draw :: proc (self:^animate_image, cmd:command_buffer) {
    mem.ICheckInit_Check(&self.check_init)
    mem.ICheckInit_Check(&self.src.check_init)

    graphics_cmd_bind_pipeline(cmd, .GRAPHICS, animate_tex_pipeline)
    graphics_cmd_bind_descriptor_sets(cmd, .GRAPHICS, animate_tex_pipeline_layout, 0, 2,
        &([]vk.DescriptorSet{self.set.__set, self.src.set.__set})[0], 0, nil)

    graphics_cmd_draw(cmd, 6, 1, 0, 0)
}

// ============================================================================
// Tile Image Management
// ============================================================================

@private tile_image_vtable :iobject_vtable = iobject_vtable {
    draw = auto_cast _super_tile_image_draw,
    deinit = auto_cast _super_tile_image_deinit,
}

tile_image_init :: proc(self:^tile_image, $actualType:typeid, src:^tile_texture_array, pos:linalg.Point3DF, rotation:f32, scale:linalg.PointF = {1,1}, 
camera:^camera, projection:^projection, colorTransform:^color_transform = nil, pivot:linalg.PointF = {0, 0}, vtable:^iobject_vtable = nil) where intrinsics.type_is_subtype_of(actualType, tile_image) {
    self.src = src

    self.set.bindings = descriptor_set_binding__tile_image_uniform_pool[:]
    self.set.size = descriptor_pool_size__tile_image_uniform_pool[:]
    self.set.layout = animate_tex_descriptor_set_layout //animate_tex_descriptor_set_layout 공용

    self.vtable = vtable == nil ? &tile_image_vtable : vtable
    if self.vtable.draw == nil do self.vtable.draw = auto_cast _super_tile_image_draw
    if self.vtable.deinit == nil do self.vtable.deinit = auto_cast _super_tile_image_deinit

    if self.vtable.get_uniform_resources == nil do self.vtable.get_uniform_resources = auto_cast get_uniform_resources_tile_image


    buffer_resource_create_buffer(&self.tile_uniform, {
        len = size_of(u32),
        type = .UNIFORM,
        resource_usage = .CPU,
    }, mem.ptr_to_bytes(&self.tile_idx), true)

    iobject_init(self, actualType, pos, rotation, scale, camera, projection, colorTransform, pivot)
}

tile_image_init2 :: proc(self:^tile_image, $actualType:typeid, src:^tile_texture_array,
camera:^camera, projection:^projection, colorTransform:^color_transform = nil, vtable:^iobject_vtable = nil) where intrinsics.type_is_subtype_of(actualType, tile_image) {
    self.src = src

    self.set.bindings = descriptor_set_binding__tile_image_uniform_pool[:]
    self.set.size = descriptor_pool_size__tile_image_uniform_pool[:]
    self.set.layout = animate_tex_descriptor_set_layout

    self.vtable = vtable == nil ? &tile_image_vtable : vtable
    if self.vtable.draw == nil do self.vtable.draw = auto_cast _super_tile_image_draw
    if self.vtable.deinit == nil do self.vtable.deinit = auto_cast _super_tile_image_deinit

    if self.vtable.get_uniform_resources == nil do self.vtable.get_uniform_resources = auto_cast get_uniform_resources_tile_image

    iobject_init2(self, actualType, camera, projection, colorTransform)
}

// ============================================================================
// Tile Image Cleanup
// ============================================================================

_super_tile_image_deinit :: proc(self:^tile_image) {
    clone_tile_uniform := new(buffer_resource, temp_arena_allocator)
    clone_tile_uniform^ = self.tile_uniform
    buffer_resource_deinit(clone_tile_uniform)

    _super_iobject_deinit(auto_cast self)
}

// ============================================================================
// Tile Image Accessors
// ============================================================================

/*
Gets the tile texture array source of the tile image

Inputs:
- self: Pointer to the tile image

Returns:
- Pointer to the tile texture array source
*/
tile_image_get_tile_texture_array :: #force_inline proc "contextless" (self:^tile_image) -> ^tile_texture_array {
    return self.src
}

/*
Updates the tile texture array source of the tile image

Inputs:
- self: Pointer to the tile image
- src: Pointer to the new tile texture array source

Returns:
- None
*/
tile_image_update_tile_texture_array :: #force_inline proc "contextless" (self:^tile_image, src:^tile_texture_array) {
    self.src = src
}

tile_image_change_color_transform :: #force_inline proc(self:^tile_image, colorTransform:^color_transform) {
    iobject_change_color_transform(self, colorTransform)
}
tile_image_update_camera :: #force_inline proc(self:^tile_image, camera:^camera) {
    iobject_update_camera(self, camera)
}

tile_image_update_projection :: #force_inline proc(self:^tile_image, projection:^projection) {
    iobject_update_projection(self, projection)
}

/*
Gets the camera of the tile image

Inputs:
- self: Pointer to the tile image

Returns:
- Pointer to the camera
*/
tile_image_get_camera :: proc "contextless" (self:^tile_image) -> ^camera {
    return iobject_get_camera(self)
}

/*
Gets the projection of the tile image

Inputs:
- self: Pointer to the tile image

Returns:
- Pointer to the projection
*/
tile_image_get_projection :: proc "contextless" (self:^tile_image) -> ^projection {
    return iobject_get_projection(self)
}

/*
Gets the color transform of the tile image

Inputs:
- self: Pointer to the tile image

Returns:
- Pointer to the color transform
*/
tile_image_get_color_transform :: proc "contextless" (self:^tile_image) -> ^color_transform {
    return iobject_get_color_transform(self)
}

// ============================================================================
// Tile Image Update Functions
// ============================================================================

tile_image_update_transform :: #force_inline proc(self:^tile_image, pos:linalg.Point3DF, rotation:f32, scale:linalg.PointF = {1,1}, pivot:linalg.PointF = {0.0, 0.0}) {
    iobject_update_transform(self, pos, rotation, scale, pivot)
}

tile_image_update_transform_matrix_raw :: #force_inline proc(self:^tile_image, _mat:linalg.Matrix) {
    iobject_update_transform_matrix_raw(self, _mat)
}

/*
Updates the tile index for the tile image

Inputs:
- self: Pointer to the tile image
- idx: The new tile index

Returns:
- None
*/
tile_image_update_idx :: proc(self:^tile_image, idx:u32) {
    mem.ICheckInit_Check(&self.check_init)
    self.tile_idx = idx

    buffer_resource_copy_update(&self.tile_uniform, &self.tile_idx)
}

_super_tile_image_draw :: proc (self:^tile_image, cmd:command_buffer) {
    mem.ICheckInit_Check(&self.check_init)
    mem.ICheckInit_Check(&self.src.check_init)

    graphics_cmd_bind_pipeline(cmd, .GRAPHICS, animate_tex_pipeline)
    graphics_cmd_bind_descriptor_sets(cmd, .GRAPHICS, animate_tex_pipeline_layout, 0, 2,
        &([]vk.DescriptorSet{self.set.__set, self.src.set.__set})[0], 0, nil)

    graphics_cmd_draw(cmd, 6, 1, 0, 0)
}

// ============================================================================
// Texture Management
// ============================================================================

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
			qoiD :^engine.qoi_converter = auto_cast allocator_data
			engine.qoi_converter_deinit(qoiD)
			free(qoiD, engine.def_allocator())
		}
		return nil, nil
	}
	
	init :: proc() {
		qoiD := new(engine.qoi_converter, engine.def_allocator())
		
		imgData, errCode := engine.image_converter_load(qoiD, panda_img, .RGBA)
		if errCode != nil {
			trace.panic_log(errCode)
		}
		
		engine.texture_init(&texture,
		u32(engine.image_converter_width(qoiD)), u32(engine.image_converter_height(qoiD)), imgData,
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
	in_pixel_fmt: color_fmt = .RGBA,
) {
	mem.ICheckInit_Init(&self.check_init)
	self.sampler = sampler == 0 ? linear_sampler : sampler
	self.set.bindings = descriptor_set_binding__single_pool[:]
	self.set.size = descriptor_pool_size__single_sampler_pool[:]
	self.set.layout = tex_descriptor_set_layout2
	self.set.__set = 0

	color_fmt_convert_default_overlap(pixels, pixels, in_pixel_fmt)

	buffer_resource_create_texture(&self.texture, {
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

	self.set.__resources = mem.make_non_zeroed_slice([]union_resource, 1, temp_arena_allocator)
	self.set.__resources[0] = &self.texture
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
	self.set.layout = tex_descriptor_set_layout2
	self.set.__set = 0

	buffer_resource_create_texture(&self.texture, {
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

	self.set.__resources = mem.make_non_zeroed_slice([]union_resource, 1, temp_arena_allocator)
	self.set.__resources[0] = &self.texture
	update_descriptor_sets(mem.slice_ptr(&self.set, 1))
}

// ============================================================================
// Texture Specialized Initialization
// ============================================================================

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

    buffer_resource_create_texture(&self.texture, {
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

    buffer_resource_create_texture(&self.texture, {
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
    clone_texture := new(texture_resource, temp_arena_allocator)
    clone_texture^ = self.texture
    buffer_resource_deinit(clone_texture)
}

/*
Gets the width of the texture

Inputs:
- self: Pointer to the texture

Returns:
- Width of the texture in pixels
*/
texture_width :: #force_inline proc "contextless" (self:^texture) -> u32{
    return auto_cast self.texture.option.width
}

/*
Gets the height of the texture

Inputs:
- self: Pointer to the texture

Returns:
- Height of the texture in pixels
*/
texture_height :: #force_inline proc "contextless" (self:^texture) -> u32 {
    return auto_cast self.texture.option.height
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
texture_array_init :: proc(self:^texture_array, width:u32, height:u32, count:u32, pixels:[]byte, sampler:vk.Sampler = 0, inPixelFmt:color_fmt = .RGBA) {
    mem.ICheckInit_Init(&self.check_init)
    self.sampler = sampler == 0 ? linear_sampler : sampler
    self.set.bindings = descriptor_set_binding__single_pool[:]
    self.set.size = descriptor_pool_size__single_sampler_pool[:]
    self.set.layout = tex_descriptor_set_layout2
    self.set.__set = 0

    allocPixels := mem.make_non_zeroed_slice([]byte, count * width * height * 4, engine_def_allocator)
    color_fmt_convert_default(pixels, allocPixels, inPixelFmt)

    buffer_resource_create_texture(&self.texture, {
        width = width,
        height = height,
        use_gcpu_mem = false,
        format = .DefaultColor,
        samples = 1,
        len = count,
        texture_usage = {.IMAGE_RESOURCE},
        type = .TEX2D,
        resource_usage = .GPU,
    }, self.sampler, allocPixels, false, engine_def_allocator)

    self.set.__resources = mem.make_non_zeroed_slice([]union_resource, 1, temp_arena_allocator)
    self.set.__resources[0] = &self.texture
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
    clone_texture := new(texture_resource, temp_arena_allocator)
    clone_texture^ = self.texture
    buffer_resource_deinit(clone_texture)
}
/*
Gets the width of textures in the texture array

Inputs:
- self: Pointer to the texture array

Returns:
- Width of each texture in pixels
*/
texture_array_width :: #force_inline proc "contextless" (self:^texture_array) -> u32 {
    return self.texture.option.width
}

/*
Gets the height of textures in the texture array

Inputs:
- self: Pointer to the texture array

Returns:
- Height of each texture in pixels
*/
texture_array_height :: #force_inline proc "contextless" (self:^texture_array) -> u32 {
    return self.texture.option.height
}

/*
Gets the number of textures in the texture array

Inputs:
- self: Pointer to the texture array

Returns:
- Number of textures in the array
*/
texture_array_count :: #force_inline proc "contextless" (self:^texture_array) -> u32 {
    return self.texture.option.len
}

// ============================================================================
// Color Format Conversion
// ============================================================================

/*
Converts pixel format to the default graphics format

Inputs:
- pixels: Input pixel data
- out: Output buffer for converted pixels
- inPixelFmt: Input pixel format (default: .RGBA)

Returns:
- None
*/
color_fmt_convert_default :: proc "contextless" (pixels:[]byte, out:[]byte, inPixelFmt:color_fmt = .RGBA) {
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
color_fmt_convert_default_overlap :: proc "contextless" (pixels:[]byte, out:[]byte, inPixelFmt:color_fmt = .RGBA) {
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
Initializes a tile texture array from a tilemap

Inputs:
- self: Pointer to the tile texture array to initialize
- tile_width: Width of each tile
- tile_height: Height of each tile
- width: Width of the tilemap
- count: Number of tiles
- pixels: Pixel data of the tilemap
- sampler: Sampler to use (default: 0, uses default linear sampler)
- inPixelFmt: Input pixel format (default: .RGBA)

Returns:
- None
*/
tile_texture_array_init :: proc(self:^tile_texture_array, tile_width:u32, tile_height:u32, width:u32, count:u32, pixels:[]byte, sampler:vk.Sampler = 0, 
inPixelFmt:color_fmt = .RGBA) {
    mem.ICheckInit_Init(&self.check_init)
    self.sampler = sampler == 0 ? linear_sampler : sampler
    self.set.bindings = descriptor_set_binding__single_pool[:]
    self.set.size = descriptor_pool_size__single_sampler_pool[:]
    self.set.layout = tex_descriptor_set_layout2
    self.set.__set = 0
    bit :: 4//outBit count default 4
    allocPixels := mem.make_non_zeroed_slice([]byte, count * tile_width * tile_height * bit, engine_def_allocator)

    //convert tilemap pixel data format to tile image data format arranged sequentially
    cnt:u32
    row := math.floor_div(width, tile_width)
    col := math.floor_div(count, row)

    for y in 0..<col {
        for x in 0..<row {
            for h in 0..<tile_height {
                start := cnt * (tile_width * tile_height * bit) + h * tile_width * bit
                startP := (y * tile_height + h) * (width * bit) + x * tile_width * bit
                color_fmt_convert_default(pixels[startP:startP + tile_width * bit], allocPixels[start:start + tile_width * bit], inPixelFmt)
            }
            cnt += 1
        }
    }
  
    buffer_resource_create_texture(&self.texture, {
        width = tile_width,
        height = tile_height,
        use_gcpu_mem = false,
        format = .DefaultColor,
        samples = 1,
        len = count,
        texture_usage = {.IMAGE_RESOURCE},
        type = .TEX2D,
    }, self.sampler, allocPixels, false, engine_def_allocator)

    self.set.__resources = mem.make_non_zeroed_slice([]union_resource, 1, temp_arena_allocator)
    self.set.__resources[0] = &self.texture
    update_descriptor_sets(mem.slice_ptr(&self.set, 1))
}

/*
Deinitializes and cleans up tile texture array resources

Inputs:
- self: Pointer to the tile texture array to deinitialize

Returns:
- None
*/
tile_texture_array_deinit :: #force_inline proc(self:^tile_texture_array) {
    mem.ICheckInit_Deinit(&self.check_init)
    clone_texture := new(texture_resource, temp_arena_allocator)
    clone_texture^ = self.texture
    buffer_resource_deinit(clone_texture)
}
/*
Gets the width of tiles in the tile texture array

Inputs:
- self: Pointer to the tile texture array

Returns:
- Width of each tile in pixels
*/
tile_texture_array_width :: #force_inline proc "contextless" (self:^tile_texture_array) -> u32 {
    return self.texture.option.width
}

/*
Gets the height of tiles in the tile texture array

Inputs:
- self: Pointer to the tile texture array

Returns:
- Height of each tile in pixels
*/
tile_texture_array_height :: #force_inline proc "contextless" (self:^tile_texture_array) -> u32 {
    return self.texture.option.height
}

/*
Gets the number of tiles in the tile texture array

Inputs:
- self: Pointer to the tile texture array

Returns:
- Number of tiles in the array
*/
tile_texture_array_count :: #force_inline proc "contextless" (self:^tile_texture_array) -> u32 {
    return self.texture.option.len
}

// ============================================================================
// Image Utility Functions
// ============================================================================

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

    #partial switch pivot {
        case .Center:
            if img.src.texture.option.width % 2 != 0 do p.x += 0.5
            if img.src.texture.option.height % 2 != 0 do p.y -= 0.5
        case .Left, .Right:
            if img.src.texture.option.height % 2 != 0 do p.y -= 0.5
        case .Top, .Bottom:
            if img.src.texture.option.width % 2 != 0 do p.x += 0.5
    }
    return p
}
