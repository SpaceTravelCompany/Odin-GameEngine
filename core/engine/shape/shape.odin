package shape

import "core:engine/geometry"
import "core:math/linalg"
import "base:intrinsics"
import "base:runtime"
import vk "vendor:vulkan"
import "core:engine"


/*
Shape object structure for rendering geometric shapes

Extends iobject with shape source data
*/
shape :: struct {
    using _:engine.itransform_object,
    shapes: ^geometry.shapes,
}

_super_shape_deinit :: engine._super_itransform_object_deinit

@private shape_vtable :engine.iobject_vtable = engine.iobject_vtable{
    draw = auto_cast _super_shape_draw,
}

shape_init :: proc(self:^shape, shapes:^geometry.shapes,
colorTransform:^engine.color_transform = nil, vtable:^engine.iobject_vtable = nil) {
    self.shapes = shapes

    self.set.bindings = engine.descriptor_set_binding__base_uniform_pool[:]
    self.set.size = engine.descriptor_pool_size__base_uniform_pool[:]
    self.set.layout = engine.base_descriptor_set_layout()

    if vtable == nil {
        self.vtable = &shape_vtable
    } else {
        self.vtable = vtable
		if self.vtable.draw == nil do self.vtable.draw = auto_cast _super_shape_draw
    }

    engine.itransform_object_init(self, colorTransform, self.vtable)
	self.actual_type = typeid_of(shape)
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

_super_shape_draw :: proc (self:^shape, cmd:engine.command_buffer, viewport:^engine.viewport) {
	//TODO: Implement shape draw
}