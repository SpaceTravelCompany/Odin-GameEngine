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
	update_descriptor_set: #type proc (self:^iobject),
	descriptor_set_layout : vk.DescriptorSetLayout,
}

/*
Base object interface structure for all renderable objects

Contains vtable for polymorphic behavior
*/
iobject :: struct {
	allocator: runtime.Allocator,
    vtable: ^iobject_vtable,
	actual_type: typeid,
	set: vk.DescriptorSet,
	set_idx: u32,
}

@private __itransform_object_vtable :iobject_vtable = iobject_vtable {
    deinit = auto_cast itransform_object_deinit,
	descriptor_set_layout = base_descriptor_set_layout(),
}

/*
Transformable object interface structure for all renderable objects

Contains transformation matrix, descriptor set for polymorphic behavior
*/
itransform_object :: struct {
	using _: iobject,
    using _: __matrix_in,
    color_transform: ^color_transform,
}

@private __matrix_in :: struct {
    mat: linalg.matrix44,
	mat_idx:Maybe(u32),
}

itransform_object_deinit :: proc (self:^itransform_object) {
	resource :punion_resource = graphics_get_resource(self.mat_idx)
	if resource != nil {
		buffer_resource_deinit(self.mat_idx.?)
	}
}

iobject_init :: proc(self:^iobject, allocator:runtime.Allocator) {
    self.allocator = allocator
    self.actual_type = typeid_of(iobject)
}

itransform_object_init :: proc(self:^itransform_object, _color_transform:^color_transform = nil, vtable:^iobject_vtable = nil) {
    self.color_transform = _color_transform == nil ? def_color_transform() : _color_transform

	if vtable == nil {
		self.vtable = &__itransform_object_vtable
	} else {
		self.vtable = vtable
		if self.vtable.deinit == nil do self.vtable.deinit = auto_cast itransform_object_deinit
		if self.vtable.update_descriptor_set == nil do self.vtable.update_descriptor_set = auto_cast itransform_object_update_descriptor_set
		if self.vtable.descriptor_set_layout == 0 do self.vtable.descriptor_set_layout = base_descriptor_set_layout()
	}

	iobject_init(self, self.allocator)
    self.actual_type = typeid_of(itransform_object)
}

@private itransform_object_update_descriptor_set :: proc(self:^itransform_object) {
	if self.set == 0 {
		self.set, self.set_idx = get_descriptor_set(descriptor_pool_size__base_uniform_pool[:], base_descriptor_set_layout())
	}
	update_descriptor_set(self.set, descriptor_pool_size__base_uniform_pool[:], {
		graphics_get_resource(self.mat_idx.?),
		graphics_get_resource(self.color_transform.mat_idx.?),
	})
}

itransform_object_update_transform :: proc(self:^itransform_object, pos:linalg.point3d, rotation:f32 = 0.0, scale:linalg.point = {1.0,1.0}, pivot:linalg.point = {0.0,0.0}) {
    itransform_object_update_transform_matrix_raw(self, linalg.srtc_2d_matrix(pos, scale, rotation, pivot))
}
itransform_object_update_transform_matrix_raw :: proc(self:^itransform_object, _mat:linalg.matrix44) {
    self.mat = _mat
    
    resource :punion_resource = graphics_get_resource(self.mat_idx)
	if resource == nil {
        _, self.mat_idx = buffer_resource_create_buffer(nil, {
            size = size_of(linalg.matrix44),
            type = .UNIFORM,
            resource_usage = .CPU,
        }, mem.ptr_to_bytes(&self.mat))

		self.vtable.update_descriptor_set(self)
	} else {
		buffer_resource_copy_update(self.mat_idx.?, &self.mat)
	}
}
itransform_object_change_color_transform :: proc(self:^itransform_object, _color_transform:^color_transform) {
    self.color_transform = _color_transform
	resource :punion_resource = graphics_get_resource(self.mat_idx)
	if resource == nil {
		_, self.mat_idx = buffer_resource_create_buffer(nil, {
			size = size_of(linalg.matrix44),
			type = .UNIFORM,
			resource_usage = .CPU,
		}, mem.ptr_to_bytes(&self.mat))
	}
	self.vtable.update_descriptor_set(self)
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
    }
    if self.set != 0 {
        put_descriptor_set(self.set_idx, self.vtable.descriptor_set_layout)
        self.set = 0
    }
	self.vtable = nil
}

iobject_update :: proc(self:^iobject) {
    if self.vtable != nil && self.vtable.update != nil {
        self.vtable.update(self)
    }
}

iobject_size :: proc(self:^iobject) {
    if self.vtable != nil && self.vtable.size != nil {
        self.vtable.size(self)
    }
}

set_render_clear_color :: proc "contextless" (_color:linalg.point3dw) {
    g_clear_color = _color
}

__vertex_buf_init :: proc (self:^__vertex_buf($NodeType), array:[]NodeType, _flag:resource_usage, _useGPUMem := false, allocator :Maybe(runtime.Allocator) = nil) {
    assert(len(array) > 0)
    _, self.idx = buffer_resource_create_buffer(self.idx, {
        size = vk.DeviceSize(len(array) * size_of(NodeType)),
        type = .VERTEX,
        resource_usage = _flag,
        single = false,
        use_gcpu_mem = _useGPUMem,
    }, mem.slice_to_bytes(array), false, allocator)
	self.data = array
}

__vertex_buf_deinit :: proc (self:^__vertex_buf($NodeType)) {
  	 if self.idx != nil {
		buffer_resource_deinit(self.idx.?)
	}
}

__vertex_buf_update :: proc (self:^__vertex_buf($NodeType), array:[]NodeType, allocator :Maybe(runtime.Allocator) = nil) {
    buffer_resource_map_update_slice(self, array, allocator)
}

__storage_buf_init :: proc (self:^__storage_buf($NodeType), array:[]NodeType, _flag:resource_usage, _useGPUMem := false) {
     assert(len(array) > 0)
    _, self.idx = buffer_resource_create_buffer(self.idx, {
        size = vk.DeviceSize(len(array) * size_of(NodeType)),
        type = .STORAGE,
        resource_usage = _flag,
        single = false,
        use_gcpu_mem = _useGPUMem,
    }, mem.slice_to_bytes(array), false, engine_def_allocator)
	self.data = array
}

__storage_buf_deinit :: proc (self:^__storage_buf($NodeType)) {
    if self.idx != nil {
		buffer_resource_deinit(self.idx.?)
	}
}

__storage_buf_update :: proc (self:^__storage_buf($NodeType), array:[]NodeType) {
    buffer_resource_map_update_slice(self, array, engine_def_allocator)
}

__index_buf_init :: proc (self:^__index_buf, array:[]u32, _flag:resource_usage, _useGPUMem := false, allocator :Maybe(runtime.Allocator) = nil) {
    assert(len(array) > 0)
    _, self.idx = buffer_resource_create_buffer(self.idx, {
        size = vk.DeviceSize(len(array) * size_of(u32)),
        type = .INDEX,
        resource_usage = _flag,
        use_gcpu_mem = _useGPUMem,
    }, mem.slice_to_bytes(array), false, allocator)
	self.data = array
}


__index_buf_deinit :: proc (self:^__index_buf) {
	if self.idx != nil {
		buffer_resource_deinit(self.idx.?)
	}
}

__index_buf_update :: #force_inline proc (self:^__index_buf, array:[]u32, allocator :Maybe(runtime.Allocator) = nil) {
    if self.idx != nil do buffer_resource_map_update_slice(self.idx.?, array, allocator)
}

__vertex_buf :: struct($NodeType:typeid) {
	data:[]NodeType,
	idx:Maybe(u32),
}
__index_buf :: distinct __vertex_buf(u32)
__storage_buf :: struct($NodeType:typeid) {
	data:[]NodeType,
	idx:Maybe(u32),
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