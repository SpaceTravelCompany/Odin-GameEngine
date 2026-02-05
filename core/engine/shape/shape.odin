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

shape_deinit :: engine.itransform_object_deinit

@private shape_vtable :engine.iobject_vtable = engine.iobject_vtable{
    draw = auto_cast shape_draw,
}

@private __shape_compute_descriptor_set_layout: vk.DescriptorSetLayout
@private __shape_compute_pipeline: engine.compute_pipeline

@private graphics_shape_module_init :: proc() {
	if __shape_compute_descriptor_set_layout == 0 {
		__shape_compute_descriptor_set_layout = engine.graphics_destriptor_set_layout_init(
			[]vk.DescriptorSetLayoutBinding {
				vk.DescriptorSetLayoutBindingInit(0, 1, stageFlags = {.COMPUTE}, descriptorType = .STORAGE_IMAGE),},
		)
		pipeline_set := engine.pipeline_set{
			init_proc = proc(data: rawptr) {
				shader_code_set_shape_compute := engine.shader_code_set_init(
					vk_comp =  #load(engine.ENGINE_ROOT + "/shaders/vulkan/shape.comp", string),
					gl_comp = #load(engine.ENGINE_ROOT + "/shaders/gl/shape.comp", string),
					gles_comp = #load(engine.ENGINE_ROOT + "/shaders/gles/shape.comp", string),
				)
				if !engine.compute_pipeline_init(&__shape_compute_pipeline,
					shader_code_set_shape_compute.comp,
					[]vk.DescriptorSetLayout{__shape_compute_descriptor_set_layout}){
					intrinsics.trap()
				}
			},
			fini_proc = proc(data: rawptr) {
				engine.compute_pipeline_deinit(&__shape_compute_pipeline)
				engine.graphics_destriptor_set_layout_destroy(&__shape_compute_descriptor_set_layout)
			},
			exec_proc = proc(data: rawptr) {
				//TODO
			},
			allocator = context.allocator,
			data = nil,
		}
		engine.add_pipeline_set(pipeline_set)
	}
}

shape_init :: proc(self:^shape, shapes:^geometry.shapes,
colorTransform:^engine.color_transform = nil, vtable:^engine.iobject_vtable = nil) {
	graphics_shape_module_init()

    self.shapes = shapes

    self.set.bindings = engine.descriptor_set_binding__base_uniform_pool[:]
    self.set.size = engine.descriptor_pool_size__base_uniform_pool[:]
    self.set.layout = engine.base_descriptor_set_layout()

    if vtable == nil {
        self.vtable = &shape_vtable
    } else {
        self.vtable = vtable
		if self.vtable.draw == nil do self.vtable.draw = auto_cast shape_draw
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

shape_draw :: proc (self:^shape, cmd:engine.command_buffer, viewport:^engine.viewport) {
	//TODO: Implement shape draw
}