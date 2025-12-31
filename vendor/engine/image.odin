package engine

import "core:math"
import "core:mem"
import "core:slice"
import "core:sync"
import "core:debug/trace"
import "core:math/linalg"
import "base:intrinsics"
import "base:runtime"
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

image :: struct {
    using _:iobject,
    src: ^texture,
}

animate_image :: struct {
    using _:ianimate_object,
    src: ^texture_array,
}

tile_image :: struct {
    using object:iobject,
    tile_uniform:buffer_resource,
    tile_idx:u32,
    src: ^tile_texture_array,
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

image_init :: proc(self:^image, $actualType:typeid, src:^texture, pos:linalg.Point3DF,
camera:^camera, projection:^projection,
rotation:f32 = 0.0, scale:linalg.PointF = {1,1}, colorTransform:^color_transform = nil, pivot:linalg.PointF = {0.0, 0.0}, vtable:^iobject_vtable = nil) where intrinsics.type_is_subtype_of(actualType, image) {
    self.src = src
        
    self.set.bindings = __transform_uniform_pool_binding[:]
    self.set.size = __transform_uniform_pool_sizes[:]
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
        
    self.set.bindings = __transform_uniform_pool_binding[:]
    self.set.size = __transform_uniform_pool_sizes[:]
    self.set.layout = tex_descriptor_set_layout

    self.vtable = vtable == nil ? &image_vtable : vtable
    if self.vtable.draw == nil do self.vtable.draw = auto_cast _super_image_draw
    if self.vtable.deinit == nil do self.vtable.deinit = auto_cast _super_image_deinit

    if self.vtable.get_uniform_resources == nil do self.vtable.get_uniform_resources = auto_cast get_uniform_resources_default

    iobject_init2(self, actualType, camera, projection, colorTransform)
}

_super_image_deinit :: proc(self:^image) {
    _super_iobject_deinit(self)
}

image_get_texture :: #force_inline proc "contextless" (self:^image) -> ^texture {
    return self.src
}
image_get_camera :: proc "contextless" (self:^image) -> ^camera {
    return iobject_get_camera(self)
}
image_get_projection :: proc "contextless" (self:^image) -> ^projection {
    return iobject_get_projection(self)
}
image_get_color_transform :: proc "contextless" (self:^image) -> ^color_transform {
    return iobject_get_color_transform(self)
}
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

_super_image_draw :: proc (self:^image, cmd:command_buffer) {
    mem.ICheckInit_Check(&self.check_init)
    mem.ICheckInit_Check(&self.src.check_init)

   _image_BindingSetsAndDraw(cmd, self.set, self.src.set)
}

_image_BindingSetsAndDraw :: proc "contextless" (cmd:command_buffer, imageSet:descriptor_set, textureSet:descriptor_set) {
    graphics_cmd_bind_pipeline(cmd, .GRAPHICS, tex_pipeline)
    graphics_cmd_bind_descriptor_sets(cmd, .GRAPHICS, tex_pipeline_layout, 0, 2,
        &([]vk.DescriptorSet{imageSet.__set, textureSet.__set})[0], 0, nil)

    graphics_cmd_draw(cmd, 6, 1, 0, 0)
}


@private animate_image_vtable :ianimate_object_vtable = ianimate_object_vtable {
    draw = auto_cast _super_animate_image_draw,
    deinit = auto_cast _super_animate_image_deinit,
    get_frame_cnt = auto_cast _super_animate_image_get_frame_cnt,
}

animate_image_init :: proc(self:^animate_image, $actualType:typeid, src:^texture_array, pos:linalg.Point3DF, rotation:f32, scale:linalg.PointF = {1,1}, 
camera:^camera, projection:^projection, colorTransform:^color_transform = nil, pivot:linalg.PointF = {0.0, 0.0}, vtable:^ianimate_object_vtable = nil) where intrinsics.type_is_subtype_of(actualType, animate_image) {
    self.src = src
    
    self.set.bindings = __animate_image_uniform_pool_binding[:]
    self.set.size = __animate_image_uniform_pool_sizes[:]
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
    
    self.set.bindings = __animate_image_uniform_pool_binding[:]
    self.set.size = __animate_image_uniform_pool_sizes[:]
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

_super_animate_image_deinit :: proc(self:^animate_image) {
    clone_frame_uniform := new(buffer_resource, temp_arena_allocator)
    clone_frame_uniform^ = self.frame_uniform
    buffer_resource_deinit(clone_frame_uniform)

    _super_iobject_deinit(auto_cast self)
}


animate_image_get_frame_cnt :: _super_animate_image_get_frame_cnt

_super_animate_image_get_frame_cnt :: proc "contextless" (self:^animate_image) -> u32 {
    return self.src.texture.option.len
}

animate_image_get_texture_array :: #force_inline proc "contextless" (self:^animate_image) -> ^texture_array {
    return self.src
}
animate_image_get_camera :: proc "contextless" (self:^animate_image) -> ^camera {
    return self.camera
}
animate_image_get_projection :: proc "contextless" (self:^animate_image) -> ^projection {
    return self.projection
}
animate_image_get_color_transform :: proc "contextless" (self:^animate_image) -> ^color_transform {
    return self.color_transform
}
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
_super_animate_image_draw :: proc (self:^animate_image, cmd:command_buffer) {
    mem.ICheckInit_Check(&self.check_init)
    mem.ICheckInit_Check(&self.src.check_init)

    graphics_cmd_bind_pipeline(cmd, .GRAPHICS, animate_tex_pipeline)
    graphics_cmd_bind_descriptor_sets(cmd, .GRAPHICS, animate_tex_pipeline_layout, 0, 2,
        &([]vk.DescriptorSet{self.set.__set, self.src.set.__set})[0], 0, nil)

    graphics_cmd_draw(cmd, 6, 1, 0, 0)
}

@private tile_image_vtable :iobject_vtable = iobject_vtable {
    draw = auto_cast _super_tile_image_draw,
    deinit = auto_cast _super_tile_image_deinit,
}

tile_image_init :: proc(self:^tile_image, $actualType:typeid, src:^tile_texture_array, pos:linalg.Point3DF, rotation:f32, scale:linalg.PointF = {1,1}, 
camera:^camera, projection:^projection, colorTransform:^color_transform = nil, pivot:linalg.PointF = {0, 0}, vtable:^iobject_vtable = nil) where intrinsics.type_is_subtype_of(actualType, tile_image) {
    self.src = src

    self.set.bindings = __tile_image_uniform_pool_binding[:]
    self.set.size = __tile_image_uniform_pool_sizes[:]
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

    self.set.bindings = __tile_image_uniform_pool_binding[:]
    self.set.size = __tile_image_uniform_pool_sizes[:]
    self.set.layout = animate_tex_descriptor_set_layout

    self.vtable = vtable == nil ? &tile_image_vtable : vtable
    if self.vtable.draw == nil do self.vtable.draw = auto_cast _super_tile_image_draw
    if self.vtable.deinit == nil do self.vtable.deinit = auto_cast _super_tile_image_deinit

    if self.vtable.get_uniform_resources == nil do self.vtable.get_uniform_resources = auto_cast get_uniform_resources_tile_image

    iobject_init2(self, actualType, camera, projection, colorTransform)
}   

_super_tile_image_deinit :: proc(self:^tile_image) {
    clone_tile_uniform := new(buffer_resource, temp_arena_allocator)
    clone_tile_uniform^ = self.tile_uniform
    buffer_resource_deinit(clone_tile_uniform)

    _super_iobject_deinit(auto_cast self)
}

tile_image_get_tile_texture_array :: #force_inline proc "contextless" (self:^tile_image) -> ^tile_texture_array {
    return self.src
}
tile_image_update_tile_texture_array :: #force_inline proc "contextless" (self:^tile_image, src:^tile_texture_array) {
    self.src = src
}
tile_image_update_transform :: #force_inline proc(self:^tile_image, pos:linalg.Point3DF, rotation:f32, scale:linalg.PointF = {1,1}, pivot:linalg.PointF = {0.0, 0.0}) {
    iobject_update_transform(self, pos, rotation, scale, pivot)
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
tile_image_get_camera :: proc "contextless" (self:^tile_image) -> ^camera {
    return iobject_get_camera(self)
}
tile_image_get_projection :: proc "contextless" (self:^tile_image) -> ^projection {
    return iobject_get_projection(self)
}
tile_image_get_color_transform :: proc "contextless" (self:^tile_image) -> ^color_transform {
    return iobject_get_color_transform(self)
}
tile_image_update_transform_matrix_raw :: #force_inline proc(self:^tile_image, _mat:linalg.Matrix) {
    iobject_update_transform_matrix_raw(self, _mat)
}

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


texture_init :: proc(
	self: ^texture,
	width: u32,
	height: u32,
	pixels: []byte,
	sampler: vk.Sampler = 0,
	resource_usage: resource_usage = .GPU,
	in_pixel_fmt: color_fmt = .RGBA,
) {
	mem.ICheckInit_Init(&self.check_init)
	self.sampler = sampler == 0 ? linear_sampler : sampler
	self.set.bindings = __single_pool_binding[:]
	self.set.size = __single_sampler_pool_sizes[:]
	self.set.layout = tex_descriptor_set_layout2
	self.set.__set = 0

	alloc_pixels := mem.make_non_zeroed_slice([]byte, width * height * 4, engine_def_allocator)
	color_fmt_convert_default(pixels, alloc_pixels, in_pixel_fmt)

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
	}, self.sampler, alloc_pixels, false, engine_def_allocator)

	self.set.__resources = mem.make_non_zeroed_slice([]union_resource, 1, temp_arena_allocator)
	self.set.__resources[0] = &self.texture
	update_descriptor_sets(mem.slice_ptr(&self.set, 1))
}

texture_init_grey :: proc(
	self: ^texture,
	width: u32,
	height: u32,
	pixels: []byte,
	sampler: vk.Sampler = 0,
	resource_usage: resource_usage = .GPU,
) {
	mem.ICheckInit_Init(&self.check_init)
	self.sampler = sampler == 0 ? linear_sampler : sampler
	self.set.bindings = __single_pool_binding[:]
	self.set.size = __single_sampler_pool_sizes[:]
	self.set.layout = tex_descriptor_set_layout2
	self.set.__set = 0

	alloc_pixels := mem.make_non_zeroed_slice([]byte, width * height, engine_def_allocator)
	mem.copy_non_overlapping(&alloc_pixels[0], &pixels[0], len(pixels))

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
	}, self.sampler, alloc_pixels, false, engine_def_allocator)

	self.set.__resources = mem.make_non_zeroed_slice([]union_resource, 1, temp_arena_allocator)
	self.set.__resources[0] = &self.texture
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

texture_deinit :: #force_inline proc(self:^texture) {
    mem.ICheckInit_Deinit(&self.check_init)
    clone_texture := new(texture_resource, temp_arena_allocator)
    clone_texture^ = self.texture
    buffer_resource_deinit(clone_texture)
}

texture_width :: #force_inline proc "contextless" (self:^texture) -> u32{
    return auto_cast self.texture.option.width
}
texture_height :: #force_inline proc "contextless" (self:^texture) -> u32 {
    return auto_cast self.texture.option.height
}

get_default_linear_sampler :: #force_inline proc "contextless" () -> vk.Sampler {
    return linear_sampler
}
get_default_nearest_sampler :: #force_inline proc "contextless" () -> vk.Sampler {
    return nearest_sampler
}

texture_update_sampler :: #force_inline proc "contextless" (self:^texture, sampler:vk.Sampler) {
    self.sampler = sampler
}
texture_get_sampler :: #force_inline proc "contextless" (self:^texture) -> vk.Sampler {
    return self.sampler
}

texture_array_init :: proc(self:^texture_array, width:u32, height:u32, count:u32, pixels:[]byte, sampler:vk.Sampler = 0, inPixelFmt:color_fmt = .RGBA) {
    mem.ICheckInit_Init(&self.check_init)
    self.sampler = sampler == 0 ? linear_sampler : sampler
    self.set.bindings = __single_pool_binding[:]
    self.set.size = __single_sampler_pool_sizes[:]
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

texture_array_deinit :: #force_inline proc(self:^texture_array) {
    mem.ICheckInit_Deinit(&self.check_init)
    clone_texture := new(texture_resource, temp_arena_allocator)
    clone_texture^ = self.texture
    buffer_resource_deinit(clone_texture)
}
texture_array_width :: #force_inline proc "contextless" (self:^texture_array) -> u32 {
    return self.texture.option.width
}
texture_array_height :: #force_inline proc "contextless" (self:^texture_array) -> u32 {
    return self.texture.option.height
}
texture_array_count :: #force_inline proc "contextless" (self:^texture_array) -> u32 {
    return self.texture.option.len
}

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

color_fmt_convert_default_overlap :: proc "contextless" (pixels:[]byte, out:[]byte, inPixelFmt:color_fmt = .RGBA) {
    defcol := default_color_fmt()
    if defcol == inPixelFmt {
        mem.copy(&out[0], &pixels[0], len(pixels))
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


tile_texture_array_init :: proc(self:^tile_texture_array, tile_width:u32, tile_height:u32, width:u32, count:u32, pixels:[]byte, sampler:vk.Sampler = 0, 
inPixelFmt:color_fmt = .RGBA) {
    mem.ICheckInit_Init(&self.check_init)
    self.sampler = sampler == 0 ? linear_sampler : sampler
    self.set.bindings = __single_pool_binding[:]
    self.set.size = __single_sampler_pool_sizes[:]
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
tile_texture_array_deinit :: #force_inline proc(self:^tile_texture_array) {
    mem.ICheckInit_Deinit(&self.check_init)
    clone_texture := new(texture_resource, temp_arena_allocator)
    clone_texture^ = self.texture
    buffer_resource_deinit(clone_texture)
}
tile_texture_array_width :: #force_inline proc "contextless" (self:^tile_texture_array) -> u32 {
    return self.texture.option.width
}   
tile_texture_array_height :: #force_inline proc "contextless" (self:^tile_texture_array) -> u32 {
    return self.texture.option.height
}
tile_texture_array_count :: #force_inline proc "contextless" (self:^tile_texture_array) -> u32 {
    return self.texture.option.len
}


image_pixel_perfect_point :: proc "contextless" (img:^$ANY_IMAGE, p:linalg.PointF, canvasW:f32, canvasH:f32, pivot:image_center_pt_pos) -> linalg.PointF where IsAnyimageType(ANY_IMAGE) {
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
