package engine

import "base:intrinsics"
import "base:runtime"
import "core:math/linalg"
import "core:mem"
import vk "vendor:vulkan"
import "core:log"



iobject_vtable :: struct {
    draw: #type proc (self:^iobject, cmd:command_buffer, viewport:^viewport),
    deinit: #type proc (self:^iobject),
    update: #type proc (self:^iobject),
    size: #type proc (self:^iobject),
}



/*
Base object interface structure for all renderable objects

Contains vtable for polymorphic behavior
*/
iobject :: struct {
    actual_type: typeid,
    vtable: ^iobject_vtable,
}
@private __itransform_object_vtable :iobject_vtable = iobject_vtable {
    deinit = auto_cast _super_itransform_object_deinit,
}

/*
Transformable object interface structure for all renderable objects

Contains transformation matrix, descriptor set for polymorphic behavior
*/
itransform_object :: struct {
	using _: iobject,
    using _: __matrix_in,
    set:descriptor_set(2),
    color_transform: ^color_transform,
}

@private __matrix_in :: struct {
    mat: linalg.matrix44,
}

@(require_results)
srtc_2d_matrix :: proc "contextless" (t: linalg.point3d, s: linalg.point, r: f32, cp:linalg.point) -> linalg.Matrix4x4f32 {
	pivot := linalg.matrix4_translate(linalg.point3d{cp.x,cp.y,0.0})
	translation := linalg.matrix4_translate(t)
	rotation := linalg.matrix4_rotate_f32(r, linalg.Vector3f32{0.0, 0.0, 1.0})
	scale := linalg.matrix4_scale(linalg.point3d{s.x,s.y,1.0})
	return linalg.mul(translation, linalg.mul(rotation, linalg.mul(scale, pivot)))
}

@(require_results)
srt_2d_matrix :: proc "contextless" (t: linalg.point3d, s: linalg.point, r: f32) -> linalg.Matrix4x4f32 {
	translation := linalg.matrix4_translate(t)
	rotation := linalg.matrix4_rotate_f32(r, linalg.Vector3f32{0.0, 0.0, 1.0})
	scale := linalg.matrix4_scale(linalg.point3d{s.x,s.y,1.0})
	return linalg.mul(translation, linalg.mul(rotation, scale))
}

@(require_results)
st_2d_matrix :: proc "contextless" (t: linalg.point3d, s: linalg.point) -> linalg.Matrix4x4f32 {
	translation := linalg.matrix4_translate(t)
	scale := linalg.matrix4_scale(linalg.point3d{s.x,s.y,1.0})
	return linalg.mul(translation, scale)
}

@(require_results)
rt_2d_matrix :: proc "contextless" (t: linalg.point3d, r: f32) -> linalg.Matrix4x4f32 {
	translation := linalg.matrix4_translate(t)
    rotation := linalg.matrix4_rotate_f32(r, linalg.Vector3f32{0.0, 0.0, 1.0})
	return linalg.mul(translation, rotation)
}


@(require_results)
t_2d_matrix :: proc "contextless" (t: linalg.point3d) -> linalg.Matrix4x4f32 {
	translation := linalg.matrix4_translate(t)
	return translation
}

@(require_results)
src_2d_matrix :: proc "contextless" (s: linalg.point, r: f32, cp:linalg.point) -> linalg.Matrix4x4f32 {
	pivot := linalg.matrix4_translate(linalg.point3d{cp.x,cp.y,0.0})
	rotation := linalg.matrix4_rotate_f32(r, linalg.Vector3f32{0.0, 0.0, 1.0})
	scale := linalg.matrix4_scale(linalg.point3d{s.x,s.y,1.0})
	return linalg.mul(rotation, linalg.mul(scale, pivot))
}

@(require_results)
sr_2d_matrix :: proc "contextless" (s: linalg.point, r: f32) -> linalg.Matrix4x4f32 {
	rotation := linalg.matrix4_rotate_f32(r, linalg.Vector3f32{0.0, 0.0, 1.0})
	scale := linalg.matrix4_scale(linalg.point3d{s.x,s.y,1.0})
	return linalg.mul(rotation, scale)
}

@(require_results)
s_2d_matrix :: proc "contextless" (s: linalg.point) -> linalg.Matrix4x4f32 {
	scale := linalg.matrix4_scale(linalg.point3d{s.x,s.y,1.0})
	return scale
}

@(require_results)
r_2d_matrix :: proc "contextless" (r: f32) -> linalg.Matrix4x4f32 {
    rotation := linalg.matrix4_rotate_f32(r, linalg.Vector3f32{0.0, 0.0, 1.0})
	return rotation
}

@(require_results)
srt_2d_matrix2 :: proc "contextless" (t: linalg.point3d, s: linalg.point, r: f32, cp:linalg.point) -> linalg.Matrix4x4f32 {
    if cp != {0.0, 0.0} {
        return srtc_2d_matrix(t,s,r,cp)
    }
    if r != 0.0 {
        if s != {1.0, 1.0} {
            return srt_2d_matrix(t,s,r)
        } else {
            return rt_2d_matrix(t,r)
        }
    }
    if s != {1.0, 1.0} {
        return st_2d_matrix(t,s)
    }
    return t_2d_matrix(t)
}

@(require_results)
sr_2d_matrix2 :: proc "contextless" (s: linalg.point, r: f32, cp:linalg.point) -> Maybe(linalg.Matrix4x4f32) {
    if cp != {0.0, 0.0} {
        return src_2d_matrix(s,r,cp)
    }
    if r != 0.0 {
        if s != {1.0, 1.0} {
            return sr_2d_matrix(s,r)
        } else {
            return r_2d_matrix(r)
        }
    }
    if s != {1.0, 1.0} {
        return s_2d_matrix(s)
    }
    return nil
}

_super_itransform_object_deinit :: proc (self:^itransform_object) {
	resource := graphics_get_resource(self)
	if resource != nil {
		buffer_resource_deinit(self)
	}
}

iobject_init :: proc(self:^iobject) {
    self.actual_type = typeid_of(iobject)
}

itransform_object_init :: proc(self:^itransform_object, _color_transform:^color_transform = nil, vtable:^iobject_vtable = nil) {
    self.color_transform = _color_transform == nil ? def_color_transform() : _color_transform

	if vtable == nil {
		self.vtable = &__itransform_object_vtable
	} else {
		self.vtable = vtable
		if self.vtable.deinit == nil do self.vtable.deinit = auto_cast _super_itransform_object_deinit
	}

    self.actual_type = typeid_of(itransform_object)
}

set_uniform_resources_transform_object :: proc(self:^itransform_object, resources:[]union_resource)  {
    resources[0] = graphics_get_resource(self)
    resources[1] = graphics_get_resource(self.color_transform)
}


itransform_object_update_transform :: proc(self:^itransform_object, pos:linalg.point3d, rotation:f32 = 0.0, scale:linalg.point = {1.0,1.0}, pivot:linalg.point = {0.0,0.0}) {
    itransform_object_update_transform_matrix_raw(self, srt_2d_matrix2(pos, scale, rotation, pivot))
}
itransform_object_update_transform_matrix_raw :: proc(self:^itransform_object, _mat:linalg.matrix44) {
    self.mat = _mat
    
    // Check if resource exists in gMapResource
    resource := graphics_get_resource(self)
	if resource == nil {
        buffer_resource_create_buffer(self, {
            size = size_of(linalg.matrix44),
            type = .UNIFORM,
            resource_usage = .CPU,
        }, mem.ptr_to_bytes(&self.mat), true)

        set_uniform_resources_transform_object(self, self.set.__resources[:])
		update_descriptor_set(&self.set)
	} else {
		buffer_resource_copy_update(self, &self.mat)
	}
}
itransform_object_change_color_transform :: proc(self:^itransform_object, _color_transform:^color_transform) {
    self.color_transform = _color_transform
    set_uniform_resources_transform_object(self, self.set.__resources[:])
	update_descriptor_set(&self.set)
}

/*
Draws the object using its vtable draw function

Inputs:
- self: Pointer to the object
- cmd: Command buffer to record draw commands
- viewport: viewport to draw the object. you can use multiple viewports to perform a draw call for each element in the viewport array.

Returns:
- None
*/
iobject_draw :: proc (self:^iobject, cmd:command_buffer, viewport:^viewport) {
    if self.vtable != nil && self.vtable.draw != nil {
        self.vtable.draw(self, cmd, viewport)
    }
	//Draw Not Required Default
}

/*
Deinitializes and cleans up object resources

Inputs:
- self: Pointer to the object to deinitialize

Returns:
- None
*/
iobject_deinit :: proc(self:^iobject) {
    if self.vtable != nil && self.vtable.deinit != nil {
        self.vtable.deinit(self)
    } else {
        log.panic("iobjectType_Deinit: unknown object type\n")
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

set_render_clear_color :: proc "contextless" (_color:linalg.point3dw) {
    g_clear_color = _color
}

__vertex_buf_init :: proc (self:^__vertex_buf($NodeType), array:[]NodeType, _flag:resource_usage, _useGPUMem := false, allocator :Maybe(runtime.Allocator) = nil) {
    if len(array) == 0 do log.panic("vertex_buf_init: array is empty\n")
    buffer_resource_create_buffer(self, {
        size = vk.DeviceSize(len(array) * size_of(NodeType)),
        type = .VERTEX,
        resource_usage = _flag,
        single = false,
        use_gcpu_mem = _useGPUMem,
    }, mem.slice_to_bytes(array), false, allocator)
	self.data = array
}

__vertex_buf_deinit :: proc (self:^__vertex_buf($NodeType)) {
    buffer_resource_deinit(self)
}

__vertex_buf_update :: proc (self:^__vertex_buf($NodeType), array:[]NodeType, allocator :Maybe(runtime.Allocator) = nil) {
    buffer_resource_map_update_slice(self, array, allocator)
}

__storage_buf_init :: proc (self:^__storage_buf($NodeType), array:[]NodeType, _flag:resource_usage, _useGPUMem := false) {
    if len(array) == 0 do log.panic("storage_buf_init: array is empty\n")
    buffer_resource_create_buffer(self, {
        size = vk.DeviceSize(len(array) * size_of(NodeType)),
        type = .STORAGE,
        resource_usage = _flag,
        single = false,
        use_gcpu_mem = _useGPUMem,
    }, mem.slice_to_bytes(array), false, engine_def_allocator)
	self.data = array
}

__storage_buf_deinit :: proc (self:^__storage_buf($NodeType)) {
    buffer_resource_deinit(self)
}

__storage_buf_update :: proc (self:^__storage_buf($NodeType), array:[]NodeType) {
    buffer_resource_map_update_slice(self, array, engine_def_allocator)
}

__index_buf_init :: proc (self:^__index_buf, array:[]u32, _flag:resource_usage, _useGPUMem := false, allocator :Maybe(runtime.Allocator) = nil) {
    if len(array) == 0 do log.panic("index_buf_init: array is empty\n")
    buffer_resource_create_buffer(self, {
        size = vk.DeviceSize(len(array) * size_of(u32)),
        type = .INDEX,
        resource_usage = _flag,
        use_gcpu_mem = _useGPUMem,
    }, mem.slice_to_bytes(array), false, allocator)
	self.data = array
}


__index_buf_deinit :: proc (self:^__index_buf) {
    buffer_resource_deinit(self)
}

__index_buf_update :: #force_inline proc (self:^__index_buf, array:[]u32, allocator :Maybe(runtime.Allocator) = nil) {
    buffer_resource_map_update_slice(self, array, allocator)
}

__vertex_buf :: struct($NodeType:typeid) {
	data:[]NodeType,
}
__index_buf :: distinct __vertex_buf(u32)
__storage_buf :: struct($NodeType:typeid) {
	data:[]NodeType,
}

/*
Converts the area to window coordinate. window coordinate is top-left origin and bottom-right is (window_width(), window_height()).

**Note**: if result area is [][2]f32, it allocates memory for the result area.

Inputs:
- self: Pointer to the object
- area: Area to convert
- viewport: The viewport to which `self` belongs. If nil, the default viewport will be used.
- allocator: Allocator to use for the result area.

Returns:
- Area in window coordinates
*/
itransform_object_cvt_area_window_coord :: proc(self:^itransform_object, area:linalg.AreaF, viewport:^viewport, allocator := context.allocator) -> linalg.AreaF {
	viewport_ := viewport
	if viewport_ == nil {
		viewport_ = def_viewport()
	}
	area_1 := linalg.Area_MulMatrix(area, self.mat, context.temp_allocator)
	area_2 := linalg.Area_MulMatrix(area_1, viewport_.camera.mat, context.temp_allocator)
	area_ := linalg.Area_MulMatrix(area_2, viewport_.projection.mat, allocator)
	if res, ok := area_1.([][2]f32); ok do delete(res, context.temp_allocator)
	if res, ok := area_2.([][2]f32); ok do delete(res, context.temp_allocator)

	switch &n in area_ {
	case linalg.rect:
		n.left *= f32(window_width()) / 2.0
		n.right *= f32(window_width()) / 2.0
		n.top *= f32(window_height()) / 2.0
		n.bottom *= f32(window_height()) / 2.0

		n.left += f32(window_width()) / 2.0
		n.right += f32(window_width()) / 2.0
		n.top += f32(window_height()) / 2.0
		n.bottom += f32(window_height()) / 2.0
	case [][2]f32:
		for i in 0..<len(n) {
			n[i].x *= f32(window_width()) / 2.0
			n[i].y *= f32(window_height()) / 2.0
			n[i].x += f32(window_width()) / 2.0
			n[i].y += f32(window_height()) / 2.0
		}
	case linalg.ImageArea:
		panic_contextless("ImageArea: Available only for ImageButton\n")
	}
	return area_
}