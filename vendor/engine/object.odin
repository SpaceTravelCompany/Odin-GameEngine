package engine

import "core:math"
import "core:mem"
import "core:slice"
import "core:sync"
import "core:thread"
import "core:debug/trace"
import "core:math/linalg"
import "base:intrinsics"
import "base:runtime"
import vk "vendor:vulkan"
import sys "./sys"



color_transform :: sys.color_transform


iobject_vtable :: struct {
    get_uniform_resources: #type proc (self:^iobject) -> []sys.union_resource,
    draw: #type proc (self:^iobject, cmd:sys.command_buffer),
    deinit: #type proc (self:^iobject),
    update: #type proc (self:^iobject),
    size: #type proc (self:^iobject),
}

ianimate_object_vtable :: struct {
    using _: iobject_vtable,
    get_frame_cnt: #type proc "contextless" (self:^ianimate_object) -> u32,
}

iobject :: struct {
    using _: __matrix_in,
    set:sys.descriptor_set,
    camera: ^camera,
    projection: ^projection,
    color_transform: ^color_transform,
    actual_type: typeid,
    vtable: ^iobject_vtable,
}

__matrix_in :: struct {
    mat: linalg.Matrix,
    mat_uniform:sys.buffer_resource,
    check_init: mem.ICheckInit,
}

color_transform_init_matrix_raw :: sys.color_transform_init_matrix_raw
color_transform_deinit :: sys.color_transform_deinit
color_transform_update_matrix_raw :: sys.color_transform_update_matrix_raw


@(require_results)
__SRTC_2D_MATRIX :: proc "contextless" (t: linalg.Point3DF, s: linalg.PointF, r: f32, cp:linalg.PointF) -> linalg.Matrix4x4f32 {
	pivot := linalg.matrix4_translate(linalg.Point3DF{cp.x,cp.y,0.0})
	translation := linalg.matrix4_translate(t)
	rotation := linalg.matrix4_rotate_f32(r, linalg.Vector3f32{0.0, 0.0, 1.0})
	scale := linalg.matrix4_scale(linalg.Point3DF{s.x,s.y,1.0})
	return linalg.mul(translation, linalg.mul(rotation, linalg.mul(pivot, scale)))
}

@(require_results)
__SRT_2D_MATRIX :: proc "contextless" (t: linalg.Point3DF, s: linalg.PointF, r: f32) -> linalg.Matrix4x4f32 {
	translation := linalg.matrix4_translate(t)
	rotation := linalg.matrix4_rotate_f32(r, linalg.Vector3f32{0.0, 0.0, 1.0})
	scale := linalg.matrix4_scale(linalg.Point3DF{s.x,s.y,1.0})
	return linalg.mul(translation, linalg.mul(rotation, scale))
}

@(require_results)
__ST_2D_MATRIX :: proc "contextless" (t: linalg.Point3DF, s: linalg.PointF) -> linalg.Matrix4x4f32 {
	translation := linalg.matrix4_translate(t)
	scale := linalg.matrix4_scale(linalg.Point3DF{s.x,s.y,1.0})
	return linalg.mul(translation, scale)
}

@(require_results)
__RT_2D_MATRIX :: proc "contextless" (t: linalg.Point3DF, r: f32) -> linalg.Matrix4x4f32 {
	translation := linalg.matrix4_translate(t)
    rotation := linalg.matrix4_rotate_f32(r, linalg.Vector3f32{0.0, 0.0, 1.0})
	return linalg.mul(translation, rotation)
}


@(require_results)
__T_2D_MATRIX :: proc "contextless" (t: linalg.Point3DF) -> linalg.Matrix4x4f32 {
	translation := linalg.matrix4_translate(t)
	return translation
}


srt_2d_matrix :: proc {
    __SRTC_2D_MATRIX,
    __ST_2D_MATRIX,
    __RT_2D_MATRIX,
    __T_2D_MATRIX,
    __SRT_2D_MATRIX,
}

@(require_results)
__SRC_2D_MATRIX :: proc "contextless" (s: linalg.PointF, r: f32, cp:linalg.PointF) -> linalg.Matrix4x4f32 {
	pivot := linalg.matrix4_translate(linalg.Point3DF{cp.x,cp.y,0.0})
	rotation := linalg.matrix4_rotate_f32(r, linalg.Vector3f32{0.0, 0.0, 1.0})
	scale := linalg.matrix4_scale(linalg.Point3DF{s.x,s.y,1.0})
	return linalg.mul(rotation, linalg.mul(pivot, scale))
}

@(require_results)
__SR_2D_MATRIX :: proc "contextless" (s: linalg.PointF, r: f32) -> linalg.Matrix4x4f32 {
	rotation := linalg.matrix4_rotate_f32(r, linalg.Vector3f32{0.0, 0.0, 1.0})
	scale := linalg.matrix4_scale(linalg.Point3DF{s.x,s.y,1.0})
	return linalg.mul(rotation, scale)
}

@(require_results)
__S_2D_MATRIX :: proc "contextless" (s: linalg.PointF) -> linalg.Matrix4x4f32 {
	scale := linalg.matrix4_scale(linalg.Point3DF{s.x,s.y,1.0})
	return scale
}

@(require_results)
__R_2D_MATRIX :: proc "contextless" (r: f32) -> linalg.Matrix4x4f32 {
    rotation := linalg.matrix4_rotate_f32(r, linalg.Vector3f32{0.0, 0.0, 1.0})
	return rotation
}

SR_2D_MATRIX :: proc {
    __SRC_2D_MATRIX,
    __S_2D_MATRIX,
    __R_2D_MATRIX,
    __SR_2D_MATRIX,
}

@(require_results)
SRT_2D_MATRIX2 :: proc "contextless" (t: linalg.Point3DF, s: linalg.PointF, r: f32, cp:linalg.PointF) -> linalg.Matrix4x4f32 {
    if cp != {0.0, 0.0} {
        return __SRTC_2D_MATRIX(t,s,r,cp)
    }
    if r != 0.0 {
        if s != {1.0, 1.0} {
            return __SRT_2D_MATRIX(t,s,r)
        } else {
            return __RT_2D_MATRIX(t,r)
        }
    }
    if s != {1.0, 1.0} {
        return __ST_2D_MATRIX(t,s)
    }
    return __T_2D_MATRIX(t)
}

@(require_results)
SR_2D_MATRIX2 :: proc "contextless" (s: linalg.PointF, r: f32, cp:linalg.PointF) -> Maybe(linalg.Matrix4x4f32) {
    if cp != {0.0, 0.0} {
        return __SRC_2D_MATRIX(s,r,cp)
    }
    if r != 0.0 {
        if s != {1.0, 1.0} {
            return __SR_2D_MATRIX(s,r)
        } else {
            return __R_2D_MATRIX(r)
        }
    }
    if s != {1.0, 1.0} {
        return __S_2D_MATRIX(s)
    }
    return nil
}

iobject_init :: proc(self:^iobject, $actual_type:typeid,
    pos:linalg.Point3DF, rotation:f32, scale:linalg.PointF = {1,1},
    _camera:^camera, _projection:^projection, _color_transform:^color_transform = nil, pivot:linalg.PointF = {0.0, 0.0})
    where actual_type != iobject && intrinsics.type_is_subtype_of(actual_type, iobject) {

    mem.ICheckInit_Init(&self.check_init)
    self.camera = _camera
    self.projection = _projection
    self.color_transform = _color_transform == nil ? &sys.__def_color_transform : _color_transform
    
    self.mat = SRT_2D_MATRIX2(pos, scale, rotation, pivot)

    sys.buffer_resource_create_buffer(&self.mat_uniform, {
        len = size_of(linalg.Matrix),
        type = .UNIFORM,
        resource_usage = .CPU,
    }, mem.ptr_to_bytes(&self.mat), true)

    resources := get_uniform_resources(self)
    defer delete(resources, context.temp_allocator)
    __iobject_update_uniform(self, resources)

    self.actual_type = actual_type
}

_super_iobject_deinit :: #force_inline proc (self:^iobject) {
    mem.ICheckInit_Deinit(&self.check_init)
    clone_mat_uniform := new(sys.buffer_resource, sys.temp_arena_allocator)
    clone_mat_uniform^ = self.mat_uniform
    sys.buffer_resource_deinit(clone_mat_uniform)
}

iobject_init2 :: proc(self:^iobject, $actual_type:typeid,
    _camera:^camera, _projection:^projection, _color_transform:^color_transform = nil)
    where actual_type != iobject && intrinsics.type_is_subtype_of(actual_type, iobject) {

    mem.ICheckInit_Init(&self.check_init)
    self.camera = _camera
    self.projection = _projection
    self.color_transform = _color_transform == nil ? &sys.__def_color_transform : _color_transform

    self.actual_type = actual_type
}

//!alloc result array in temp_allocator
@private get_uniform_resources :: proc(self:^iobject) -> []sys.union_resource {
    if self.vtable != nil && self.vtable.get_uniform_resources != nil {
        return self.vtable.get_uniform_resources(self)
    } else {
        trace.panic_log("get_uniform_resources is not implemented")
    }
}

@private get_uniform_resources_animate_image :: #force_inline proc(self:^iobject) -> []sys.union_resource {
    res := mem.make_non_zeroed([]sys.union_resource, 5, context.temp_allocator)
    res[0] = &self.mat_uniform
    res[1] = &self.camera.mat_uniform
    res[2] = &self.projection.mat_uniform
    res[3] = &self.color_transform.mat_uniform

    animate_image_ : ^animate_image = auto_cast self
    res[4] = &animate_image_.frame_uniform
    return res[:]
}

@private get_uniform_resources_tile_image :: #force_inline proc(self:^iobject) -> []sys.union_resource {
    res := mem.make_non_zeroed([]sys.union_resource, 5, context.temp_allocator)
    res[0] = &self.mat_uniform
    res[1] = &self.camera.mat_uniform
    res[2] = &self.projection.mat_uniform
    res[3] = &self.color_transform.mat_uniform

    tile_image_ : ^tile_image = auto_cast self
    res[4] = &tile_image_.tile_uniform
    return res[:]
}

@private get_uniform_resources_default :: #force_inline proc(self:^iobject) -> []sys.union_resource {
    res := mem.make_non_zeroed([]sys.union_resource, 4, context.temp_allocator)
    res[0] = &self.mat_uniform
    res[1] = &self.camera.mat_uniform
    res[2] = &self.projection.mat_uniform
    res[3] = &self.color_transform.mat_uniform

    return res[:]
}


@private __iobject_update_uniform :: proc(self:^iobject, resources:[]sys.union_resource) {
    mem.ICheckInit_Check(&self.check_init)

    //업데이트 하면 tempArenaAllocator를 다 지우니 중복 할당해도 됨.
    self.set.__resources = mem.make_non_zeroed_slice([]sys.union_resource, len(resources), sys.temp_arena_allocator)
    mem.copy_non_overlapping(&self.set.__resources[0], &resources[0], len(resources) * size_of(sys.union_resource))
    sys.update_descriptor_sets(mem.slice_ptr(&self.set, 1))
}

iobject_update_transform :: proc(self:^iobject, pos:linalg.Point3DF, rotation:f32 = 0.0, scale:linalg.PointF = {1.0,1.0}, pivot:linalg.PointF = {0.0,0.0}) {
    mem.ICheckInit_Check(&self.check_init)
    self.mat = SRT_2D_MATRIX2(pos, scale, rotation, pivot)

    if self.mat_uniform.__resource == 0 {
        sys.buffer_resource_create_buffer(&self.mat_uniform, {
            len = size_of(linalg.Matrix),
            type = .UNIFORM,
            resource_usage = .CPU,
        }, mem.ptr_to_bytes(&self.mat), true)

        resources := get_uniform_resources(self)
        defer delete(resources, context.temp_allocator)
        __iobject_update_uniform(self, resources)
    } else {
        sys.buffer_resource_copy_update(&self.mat_uniform, &self.mat)
    }
}
iobject_update_transform_matrix_raw :: proc(self:^iobject, _mat:linalg.Matrix) {
    mem.ICheckInit_Check(&self.check_init)
    self.mat = _mat
    
    if self.mat_uniform.__resource == 0 {
        sys.buffer_resource_create_buffer(&self.mat_uniform, {
            len = size_of(linalg.Matrix),
            type = .UNIFORM,
            resource_usage = .CPU,
        }, mem.ptr_to_bytes(&self.mat), true)

        resources := get_uniform_resources(self)
        defer delete(resources, context.temp_allocator)
        __iobject_update_uniform(self, resources)
    } else {
        sys.buffer_resource_copy_update(&self.mat_uniform, &self.mat)
    }
}

iobject_update_transform_matrix :: proc(self:^iobject) {
    mem.ICheckInit_Check(&self.check_init)
    
    if self.mat_uniform.__resource == 0 {
        sys.buffer_resource_create_buffer(&self.mat_uniform, {
            len = size_of(linalg.Matrix),
            type = .UNIFORM,
            resource_usage = .CPU,
        }, mem.ptr_to_bytes(&self.mat), true)

        resources := get_uniform_resources(self)
        defer delete(resources, context.temp_allocator)
        __iobject_update_uniform(self, resources)
    } else {
        sys.buffer_resource_copy_update(&self.mat_uniform, &self.mat)
    }
}

iobject_change_color_transform :: proc(self:^iobject, _color_transform:^color_transform) {
    mem.ICheckInit_Check(&self.check_init)
    self.color_transform = _color_transform
    __iobject_update_uniform(self, get_uniform_resources(self))
}
iobject_update_camera :: proc(self:^iobject, _camera:^camera) {
    mem.ICheckInit_Check(&self.check_init)
    self.camera = _camera
    __iobject_update_uniform(self, get_uniform_resources(self))
}
iobject_update_projection :: proc(self:^iobject, _projection:^projection) {
    mem.ICheckInit_Check(&self.check_init)
    self.projection = _projection
    __iobject_update_uniform(self, get_uniform_resources(self))
}
iobject_get_color_transform :: #force_inline proc "contextless" (self:^iobject) -> ^color_transform {
    mem.ICheckInit_Check(&self.check_init)
    return self.color_transform
}
iobject_get_camera :: #force_inline proc "contextless" (self:^iobject) -> ^camera {
    mem.ICheckInit_Check(&self.check_init)
    return self.camera
}
iobject_get_projection :: #force_inline proc "contextless" (self:^iobject) -> ^projection {
    mem.ICheckInit_Check(&self.check_init)
    return self.projection
}

iobject_get_actual_type :: #force_inline proc "contextless" (self:^iobject) -> typeid {
    return self.actual_type
}

iobject_draw :: proc (self:^iobject, cmd:sys.command_buffer) {
    if self.vtable != nil && self.vtable.draw != nil {
        self.vtable.draw(self, cmd)
    } else {
        trace.panic_log("iobjectType_Draw: unknown object type")
    }
}

iobject_deinit :: proc(self:^iobject) {
    if self.vtable != nil && self.vtable.deinit != nil {
        self.vtable.deinit(self)
    } else {
        trace.panic_log("iobjectType_Deinit: unknown object type")
    }
}

iobject_update :: proc(self:^iobject) {
    if self.vtable != nil && self.vtable.update != nil {
        self.vtable.update(self)
    }
    //Update Not Required Default
}

iobject_size :: proc(self:^iobject) {
    if self.vtable != nil && self.vtable.size != nil {
        self.vtable.size(self)
    }
    //Size Not Required Default
}



set_render_clear_color :: proc "contextless" (_color:linalg.Point3DwF) {
    sys.g_clear_color = _color
}

//AUTO DELETE USE engine_def_allocator
@private __vertex_buf_init :: proc (self:^__vertex_buf($NodeType), array:[]NodeType, _flag:sys.resource_usage, _useGPUMem := false) {
    mem.ICheckInit_Init(&self.check_init)
    if len(array) == 0 do trace.panic_log("vertex_buf_init: array is empty")
    sys.buffer_resource_create_buffer(&self.buf, {
        len = vk.DeviceSize(len(array) * size_of(NodeType)),
        type = .VERTEX,
        resource_usage = _flag,
        single = false,
        use_gcpu_mem = _useGPUMem,
    }, mem.slice_to_bytes(array), false, sys.engine_def_allocator)
}

@private __vertex_buf_deinit :: proc (self:^__vertex_buf($NodeType)) {
    mem.ICheckInit_Deinit(&self.check_init)

    clone_buf := new(sys.buffer_resource, sys.temp_arena_allocator)
    clone_buf^ = self.buf
    sys.buffer_resource_deinit(clone_buf)
}

@private __vertex_buf_update :: proc (self:^__vertex_buf($NodeType), array:[]NodeType) {
    sys.buffer_resource_map_update_slice(&self.buf, array, sys.engine_def_allocator)
}

//AUTO DELETE USE engine_def_allocator
@private __storage_buf_init :: proc (self:^__storage_buf($NodeType), array:[]NodeType, _flag:sys.resource_usage, _useGPUMem := false) {
    mem.ICheckInit_Init(&self.check_init)
    if len(array) == 0 do trace.panic_log("storage_buf_init: array is empty")
    sys.buffer_resource_create_buffer(&self.buf, {
        len = vk.DeviceSize(len(array) * size_of(NodeType)),
        type = .STORAGE,
        resource_usage = _flag,
        single = false,
        use_gcpu_mem = _useGPUMem,
    }, mem.slice_to_bytes(array), false, sys.engine_def_allocator)
}

@private __storage_buf_deinit :: proc (self:^__storage_buf($NodeType)) {
    mem.ICheckInit_Deinit(&self.check_init)

    clone_buf := new(sys.buffer_resource, sys.temp_arena_allocator)
    clone_buf^ = self.buf
    sys.buffer_resource_deinit(clone_buf)
}

@private __storage_buf_update :: proc (self:^__storage_buf($NodeType), array:[]NodeType) {
    sys.buffer_resource_map_update_slice(&self.buf, array, sys.engine_def_allocator)
}

//AUTO DELETE USE engine_def_allocator
@private __index_buf_init :: proc (self:^__index_buf, array:[]u32, _flag:sys.resource_usage, _useGPUMem := false) {
    mem.ICheckInit_Init(&self.check_init)
    if len(array) == 0 do trace.panic_log("index_buf_init: array is empty")
    sys.buffer_resource_create_buffer(&self.buf, {
        len = vk.DeviceSize(len(array) * size_of(u32)),
        type = .INDEX,
        resource_usage = _flag,
        use_gcpu_mem = _useGPUMem,
    }, mem.slice_to_bytes(array), false, sys.engine_def_allocator)
}


@private __index_buf_deinit :: proc (self:^__index_buf) {
    mem.ICheckInit_Deinit(&self.check_init)

    clone_buf := new(sys.buffer_resource, sys.temp_arena_allocator)
    clone_buf^ = self.buf
    sys.buffer_resource_deinit(clone_buf)
}

@private __index_buf_update :: #force_inline proc (self:^__index_buf, array:[]u32) {
    sys.buffer_resource_map_update_slice(&self.buf, array, sys.engine_def_allocator)
}

@private __vertex_buf :: struct($NodeType:typeid) {
    buf:sys.buffer_resource,
    check_init: mem.ICheckInit,
}

@private __index_buf :: distinct __vertex_buf(u32)
@private __storage_buf :: struct($NodeType:typeid) {
    buf:sys.buffer_resource,
    check_init: mem.ICheckInit,
}

graphics_wait_all_ops :: #force_inline proc () {
    if sys.is_main_thread() {
        sys.graphics_execute_ops(true)
    } else {
        sys.graphics_wait_all_ops()
    }
}