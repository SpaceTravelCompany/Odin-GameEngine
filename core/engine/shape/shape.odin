package shape

import "core:math"
import "core:engine/geometry"
import "core:mem"
import "core:slice"
import "core:sync"
import "core:math/linalg"
import "base:intrinsics"
import "base:runtime"
import vk "vendor:vulkan"
import "core:engine"


/*
Shape source structure containing vertex and index buffers

*/
shape_src :: struct {
    vertexBuf:engine.__vertex_buf(geometry.shape_vertex2d),
    indexBuf:engine.__index_buf,
    rect:linalg.rect,
}

/*
Shape object structure for rendering geometric shapes

Extends iobject with shape source data
*/
shape :: struct {
    using _:engine.itransform_object,
    src: ^shape_src,
}

_super_shape_deinit :: engine._super_itransform_object_deinit

@private shape_vtable :engine.iobject_vtable = engine.iobject_vtable{
    draw = auto_cast _super_shape_draw,
}

shape_init :: proc(self:^shape, src:^shape_src,
colorTransform:^engine.color_transform = nil, vtable:^engine.iobject_vtable = nil) {
    self.src = src

    self.set.bindings = engine.descriptor_set_binding__base_uniform_pool[:]
    self.set.size = engine.descriptor_pool_size__base_uniform_pool[:]
    self.set.layout = engine.get_base_descriptor_set_layout()

    self.vtable = vtable == nil ? &shape_vtable : vtable
    if self.vtable.draw == nil do self.vtable.draw = auto_cast _super_shape_draw

    engine.itransform_object_init(self, colorTransform, vtable)
	self.actual_type = typeid_of(shape)
}

shape_update_src :: #force_inline proc "contextless" (self:^shape, src:^shape_src) {
    self.src = src
}
shape_get_src :: #force_inline proc "contextless" (self:^shape) -> ^shape_src {
    return self.src
}
// shape_get_camera :: #force_inline proc "contextless" (self:^shape) -> ^engine.camera {
//     return engine.iobject_get_camera(self)
// }
// shape_get_projection :: #force_inline proc "contextless" (self:^shape) -> ^engine.projection {
//     return engine.iobject_get_projection(self)
// }
shape_get_color_transform :: #force_inline proc "contextless" (self:^shape) -> ^engine.color_transform {
    return engine.itransform_object_get_color_transform(self)
}
shape_update_transform :: #force_inline proc(self:^shape, pos:linalg.point3d, rotation:f32, scale:linalg.point = {1,1}, pivot:linalg.point = {0.0,0.0}) {
    engine.itransform_object_update_transform(self, pos, rotation, scale, pivot)
}
shape_update_transform_matrix_raw :: #force_inline proc(self:^shape, _mat:linalg.matrix44) {
    engine.itransform_object_update_transform_matrix_raw(self, _mat)
}
shape_change_color_transform :: #force_inline proc(self:^shape, colorTransform:^engine.color_transform) {
    engine.itransform_object_change_color_transform(self, colorTransform)
}
// shape_update_camera :: #force_inline proc(self:^shape, camera:^engine.camera) {
//     engine.iobject_update_camera(self, camera)
// }
// shape_update_projection :: #force_inline proc(self:^shape, projection:^engine.projection) {
//     engine.iobject_update_projection(self, projection)
// }

_super_shape_draw :: proc (self:^shape, cmd:engine.command_buffer, viewport:^engine.viewport) {
    shape_src_bind_and_draw(self.src, &self.set, cmd, viewport)
}

shape_src_bind_and_draw :: proc(self:^shape_src, set:^engine.descriptor_set, cmd:engine.command_buffer, viewport:^engine.viewport) {
    engine.graphics_cmd_bind_pipeline(cmd, .GRAPHICS, engine.get_shape_pipeline())
    engine.graphics_cmd_bind_descriptor_sets(cmd, .GRAPHICS, engine.get_shape_pipeline_layout(), 0, 2,
        &([]vk.DescriptorSet{set.__set, viewport.set.__set})[0], 0, nil)

	offsets: vk.DeviceSize = 0
    engine.graphics_cmd_bind_vertex_buffers(cmd, 0, 1, []engine.iresource{self.vertexBuf.buf}, &offsets)
    engine.graphics_cmd_bind_index_buffer(cmd, self.indexBuf.buf, 0, .UINT32)

    engine.graphics_cmd_draw_indexed(cmd, auto_cast ((^engine.buffer_resource)(self.indexBuf.buf).option.len / size_of(u32)), 1, 0, 0, 0)
}

shape_src_init_raw :: proc(self:^shape_src, raw:^geometry.raw_shape, flag:engine.resource_usage = .GPU, allocator :Maybe(runtime.Allocator) = nil) {
    engine.__vertex_buf_init(&self.vertexBuf, raw.vertices, flag, allocator=allocator)
    engine.__index_buf_init(&self.indexBuf, raw.indices, flag, allocator=allocator)

    self.rect = raw.rect
}

/*
Initializes shape source from geometry shapes

**Note:** `allocator` is used to allocate the raw shape and delete this when shape_src init is done. (async)

Inputs:
- self: Pointer to the shape source to initialize
- shapes: Pointer to the geometry shapes
- flag: Resource usage flag for buffers (default: .GPU)

Returns:
- An error if initialization failed
*/
shape_src_init :: proc(self:^shape_src, shapes:^geometry.shapes, flag:engine.resource_usage = .GPU, allocator :runtime.Allocator = context.allocator) -> (err:geometry.shape_error = nil) {
    raw : ^geometry.raw_shape
    raw, err = geometry.shapes_compute_polygon(shapes, allocator)
    if err != nil do return

    engine.__vertex_buf_init(&self.vertexBuf, raw.vertices, flag, allocator=allocator)
    engine.__index_buf_init(&self.indexBuf, raw.indices, flag, allocator=allocator)

    self.rect = raw.rect

    //only delete raw single pointer
    defer free(raw, allocator)
    return
}

/*
Updates the shape source with a new raw shape

**Note:** `allocator` is used to delete raw when shape_src update is done. (async) If allocator is nil, not delete raw.

Inputs:
- self: Pointer to the shape source to update
- raw: Pointer to the new raw shape
- allocator: The allocator to use for the raw shape
*/
shape_src_update_raw :: proc(self:^shape_src, raw:^geometry.raw_shape, allocator :Maybe(runtime.Allocator) = nil) {
    engine.__vertex_buf_update(&self.vertexBuf, raw.vertices, allocator)
    engine.__index_buf_update(&self.indexBuf, raw.indices, allocator)
}

@require_results shape_src_update :: proc(self:^shape_src, shapes:^geometry.shapes, allocator := context.allocator) -> (err:geometry.shape_error = nil) {
    raw : ^geometry.raw_shape
    raw, err = geometry.shapes_compute_polygon(shapes, allocator)
    if err != nil do return

    engine.__vertex_buf_update(&self.vertexBuf, raw.vertices, allocator)
    engine.__index_buf_update(&self.indexBuf, raw.indices, allocator)

    defer free(raw)
    return
}

/*
Deinitializes and cleans up shape source resources

Inputs:
- self: Pointer to the shape source to deinitialize
*/
shape_src_deinit :: proc(self:^shape_src) {
    engine.__vertex_buf_deinit(&self.vertexBuf)
    engine.__index_buf_deinit(&self.indexBuf)
}


shape_src_is_inited :: proc "contextless" (self:^shape_src) -> bool {
    return self.vertexBuf.buf != nil
}


