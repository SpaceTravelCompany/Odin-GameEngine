package image

import "core:engine"
import vk "vendor:vulkan"
import "base:intrinsics"
import "core:mem"

array_image :: struct {
	using _:engine.itransform_object,
    src: ^engine.texture_array,
	idx_idx: Maybe(u32),
	idx: u32,
}


@rodata descriptor_pool_size_array_image_uniform_pool : [1]engine.descriptor_pool_size = {{type = .UNIFORM, cnt = 3, binding = 0}}

@private __array_image_object_pipeline: engine.object_pipeline
@private __array_image_descriptor_set_layout: vk.DescriptorSetLayout

@private array_image_vtable :engine.iobject_vtable = engine.iobject_vtable {
    draw = auto_cast array_image_draw,
    deinit = auto_cast array_image_deinit,
    update_descriptor_set = auto_cast array_image_update_descriptor_set,
}

array_image_descriptor_set_layout :: proc() -> vk.DescriptorSetLayout {
	return __array_image_descriptor_set_layout
}
array_image_object_pipeline :: proc() -> ^engine.object_pipeline {
	return &__array_image_object_pipeline
}


@private graphics_array_image_module_init :: proc() {
	if __array_image_object_pipeline.__pipeline_layout == 0 {
		pipeline_set := engine.pipeline_set{
			init_proc = proc(data: rawptr) {
				shader_code_set_image := engine.shader_code_set_init(
					vk_vert =  #load(engine.ENGINE_ROOT + "/shaders/vulkan/array_image.vert", string),
					vk_frag =  #load(engine.ENGINE_ROOT + "/shaders/vulkan/array_image.frag", string),
					gl_vert = #load(engine.ENGINE_ROOT + "/shaders/gl/array_image.vert", string),
					gl_frag = #load(engine.ENGINE_ROOT + "/shaders/gl/array_image.frag", string),
					gles_vert = #load(engine.ENGINE_ROOT + "/shaders/gles/array_image.vert", string),
					gles_frag = #load(engine.ENGINE_ROOT + "/shaders/gles/array_image.frag", string))
				if !engine.object_pipeline_init(&__array_image_object_pipeline,
					[]vk.DescriptorSetLayout{__array_image_descriptor_set_layout,
						engine.viewport_descriptor_set_layout(),
						engine.texture_descriptor_set_layout(),
						},
					nil, nil,
					engine.object_draw_method{type = .Draw, vertex_count = 6}, 
					shader_code_set_image.vert, shader_code_set_image.frag, nil){
					intrinsics.trap()
				}
			},
			fini_proc = proc(data: rawptr) {
				engine.object_pipeline_deinit(&__array_image_object_pipeline)
			},
			allocator = context.allocator,
			data = nil,
		}
		engine.add_pipeline_set(pipeline_set)
	}
}

@private array_image_update_descriptor_set :: proc(self:^array_image) {
	if self.set == 0 {
		self.set, self.set_idx = engine.get_descriptor_set(descriptor_pool_size_array_image_uniform_pool[:], __array_image_descriptor_set_layout)
	}
	engine.update_descriptor_set(self.set, descriptor_pool_size_array_image_uniform_pool[:], {
		engine.graphics_get_resource(self.mat_idx),
		engine.graphics_get_resource(self.color_transform.mat_idx),
		engine.graphics_get_resource(self.idx_idx)
	})
}

array_image_init :: proc(self:^array_image, src:^engine.texture_array, colorTransform:^engine.color_transform = nil, vtable:^engine.iobject_vtable = nil) {
	graphics_array_image_module_init()
	self.src = src

    if vtable == nil {
        self.vtable = &array_image_vtable
    } else {
        self.vtable = vtable
        if self.vtable.draw == nil do self.vtable.draw = auto_cast array_image_draw
    }
	res:engine.punion_resource
	res, self.idx_idx = engine.buffer_resource_create_buffer(self.idx_idx, {
		size = size_of(u32),
		type = .UNIFORM,
		resource_usage = .CPU,
	}, mem.ptr_to_bytes(&self.idx))

    engine.itransform_object_init(self, colorTransform, self.vtable)
	self.actual_type = typeid_of(array_image)
}

array_image_deinit :: proc(self:^array_image) {
	if self.idx_idx != nil do engine.buffer_resource_deinit(self.idx_idx.?)
	engine.itransform_object_deinit(self)
}

array_image_draw :: proc(self:^array_image, cmd:engine.command_buffer, viewport:^engine.viewport) {
	if engine.graphics_get_resource_draw(self.mat_idx) == nil do return
	if engine.graphics_get_resource_draw(self.src.idx) == nil do return

	array_image_binding_sets_and_draw(cmd, self.set, viewport.set, self.src.set)
}

array_image_binding_sets_and_draw :: proc "contextless" (cmd:engine.command_buffer, array_imageSet:vk.DescriptorSet, 
	viewSet:vk.DescriptorSet, 
	textureSet:vk.DescriptorSet) {
    engine.graphics_pipeline_draw(cmd, &__array_image_object_pipeline, []vk.DescriptorSet{array_imageSet, viewSet, textureSet})
}