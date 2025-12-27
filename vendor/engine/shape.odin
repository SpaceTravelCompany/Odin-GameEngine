package engine

import "core:math"
import "vendor:engine/geometry"
import "core:mem"
import "core:slice"
import "core:sync"
import "core:math/linalg"
import "base:intrinsics"
import "base:runtime"
import vk "vendor:vulkan"
import sys "./sys"   

shape_src :: struct {
    //?vertexBuf, indexBuf에 check_init: ICheckInit 있으므로 따로 필요없음
    vertexBuf:__vertex_buf(geometry.shape_vertex2d),
    indexBuf:__index_buf,
    rect:linalg.RectF,
}

shape :: struct {
    using object:iobject,
    src: ^shape_src,
}

@private shape_vtable :iobject_vtable = iobject_vtable{
    draw = auto_cast _super_shape_draw,
    deinit = auto_cast _super_shape_deinit,
}


shape_init :: proc(self:^shape, $actualType:typeid, src:^shape_src, pos:linalg.Point3DF,
camera:^camera, projection:^projection,  rotation:f32 = 0.0, scale:linalg.PointF = {1,1}, colorTransform:^color_transform = nil, pivot:linalg.PointF = {0.0, 0.0}, vtable:^iobject_vtable = nil)
 where intrinsics.type_is_subtype_of(actualType, shape) {
    self.src = src

    self.set.bindings = sys.__transform_uniform_pool_binding[:]
    self.set.size = sys.__transform_uniform_pool_sizes[:]
    self.set.layout = sys.shape_descriptor_set_layout

    self.vtable = vtable == nil ? &shape_vtable : vtable
    if self.vtable.draw == nil do self.vtable.draw = auto_cast _super_shape_draw
    if self.vtable.deinit == nil do self.vtable.deinit = auto_cast _super_shape_deinit

    if self.vtable.get_uniform_resources == nil do self.vtable.get_uniform_resources = get_uniform_resources_default

    iobject_init(self, actualType, pos, rotation, scale, camera, projection, colorTransform, pivot)
}

shape_init2 :: proc(self:^shape, $actualType:typeid, src:^shape_src,
camera:^camera, projection:^projection, colorTransform:^color_transform = nil, vtable:^iobject_vtable = nil)
 where intrinsics.type_is_subtype_of(actualType, shape) {
    self.src = src

    self.set.bindings = sys.__transform_uniform_pool_binding[:]
    self.set.size = sys.__transform_uniform_pool_sizes[:]
    self.set.layout = sys.shape_descriptor_set_layout

    self.vtable = vtable == nil ? &shape_vtable : vtable
    if self.vtable.draw == nil do self.vtable.draw = auto_cast _super_shape_draw
    if self.vtable.deinit == nil do self.vtable.deinit = auto_cast _super_shape_deinit

    if self.vtable.get_uniform_resources == nil do self.vtable.get_uniform_resources = auto_cast get_uniform_resources_default

    iobject_init2(self, actualType, camera, projection, colorTransform)
}

_super_shape_deinit :: proc(self:^shape) {
    _super_iobject_deinit(auto_cast self)
}

shape_update_src :: #force_inline proc "contextless" (self:^shape, src:^shape_src) {
    mem.ICheckInit_Check(&self.check_init)
    self.src = src
}
shape_get_src :: #force_inline proc "contextless" (self:^shape) -> ^shape_src {
    mem.ICheckInit_Check(&self.check_init)
    return self.src
}
shape_get_camera :: #force_inline proc "contextless" (self:^shape) -> ^camera {
    return iobject_get_camera(self)
}
shape_get_projection :: #force_inline proc "contextless" (self:^shape) -> ^projection {
    return iobject_get_projection(self)
}
shape_get_color_transform :: #force_inline proc "contextless" (self:^shape) -> ^color_transform {
    return iobject_get_color_transform(self)
}
shape_update_transform :: #force_inline proc(self:^shape, pos:linalg.Point3DF, rotation:f32, scale:linalg.PointF = {1,1}, pivot:linalg.PointF = {0.0,0.0}) {
    iobject_update_transform(self, pos, rotation, scale, pivot)
}
shape_update_transform_matrix_raw :: #force_inline proc(self:^shape, _mat:linalg.Matrix) {
    iobject_update_transform_matrix_raw(self, _mat)
}
shape_change_color_transform :: #force_inline proc(self:^shape, colorTransform:^color_transform) {
    iobject_change_color_transform(self, colorTransform)
}
shape_update_camera :: #force_inline proc(self:^shape, camera:^camera) {
    iobject_update_camera(self, camera)
}
shape_update_projection :: #force_inline proc(self:^shape, projection:^projection) {
    iobject_update_projection(self, projection)
}

_super_shape_draw :: proc (self:^shape, cmd:sys.command_buffer) {
    mem.ICheckInit_Check(&self.check_init)

    sys.graphics_cmd_bind_pipeline(cmd, .GRAPHICS, sys.shape_pipeline)
    sys.graphics_cmd_bind_descriptor_sets(cmd, .GRAPHICS, sys.shape_pipeline_layout, 0, 1,
        &([]vk.DescriptorSet{self.set.__set})[0], 0, nil)

    offsets: vk.DeviceSize = 0
    sys.graphics_cmd_bind_vertex_buffers(cmd, 0, 1, &self.src.vertexBuf.buf.__resource, &offsets)
    sys.graphics_cmd_bind_index_buffer(cmd, self.src.indexBuf.buf.__resource, 0, .UINT32)

    sys.graphics_cmd_draw_indexed(cmd, auto_cast (self.src.indexBuf.buf.option.len / size_of(u32)), 1, 0, 0, 0)
}

shape_src_init_raw :: proc(self:^shape_src, raw:^geometry.raw_shape, flag:sys.resource_usage = .GPU, colorFlag:sys.resource_usage = .CPU) {
    rawC := geometry.raw_shape_clone(raw, sys.engine_def_allocator)
    __vertex_buf_init(&self.vertexBuf, rawC.vertices, flag)
    __index_buf_init(&self.indexBuf, rawC.indices, flag)
    self.rect = rawC.rect
}

@require_results shape_src_init :: proc(self:^shape_src, shapes:^geometry.shapes, flag:sys.resource_usage = .GPU, colorFlag:sys.resource_usage = .CPU) -> (err:geometry.shape_error = .None) {
    raw : ^geometry.raw_shape
    raw, err = geometry.shapes_compute_polygon(shapes, sys.engine_def_allocator)
    if err != .None do return

    __vertex_buf_init(&self.vertexBuf, raw.vertices, flag)
    __index_buf_init(&self.indexBuf, raw.indices, flag)

    self.rect = raw.rect

    defer free(raw)
    return
}

shape_src_update_raw :: proc(self:^shape_src, raw:^geometry.raw_shape) {
    rawC := geometry.raw_shape_clone(raw, sys.engine_def_allocator)
    __vertex_buf_update(&self.vertexBuf, rawC.vertices)
    __index_buf_update(&self.indexBuf, rawC.indices)

    defer free(rawC)
}

@require_results shape_src_update :: proc(self:^shape_src, shapes:^geometry.shapes) -> (err:geometry.shape_error = .None) {
    raw : ^geometry.raw_shape
    raw, err = geometry.shapes_compute_polygon(shapes, sys.engine_def_allocator)
    if err != .None do return

    __vertex_buf_update(&self.vertexBuf, raw.vertices)
    __index_buf_update(&self.indexBuf, raw.indices)

    defer free(raw)
    return
}

shape_src_deinit :: proc(self:^shape_src) {
    __vertex_buf_deinit(&self.vertexBuf)
    __index_buf_deinit(&self.indexBuf)
}


shape_src_is_inited :: proc "contextless" (self:^shape_src) -> bool {
    return mem.ICheckInit_IsInited(&self.vertexBuf.check_init)
}


