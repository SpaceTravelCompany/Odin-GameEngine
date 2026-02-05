package image

import "core:math/rand"
import "base:intrinsics"
import "base:runtime"
import img "core:image"
import "core:math/linalg"
import "core:mem"
import vk "vendor:vulkan"
import "core:log"
import "core:engine"


@private __image_object_pipeline: engine.object_pipeline
image_object_pipeline :: proc() -> ^engine.object_pipeline {
	return &__image_object_pipeline
}

@private graphics_image_module_init :: proc() {
	if __image_object_pipeline.__pipeline_layout == 0 {
		pipeline_set := engine.pipeline_set{
			init_proc = proc(data: rawptr) {
				shader_code_set_image := engine.shader_code_set_init(
					vk_vert =  #load(engine.ENGINE_ROOT + "/shaders/vulkan/image.vert", string),
					vk_frag =  #load(engine.ENGINE_ROOT + "/shaders/vulkan/image.frag", string),
					gl_vert = #load(engine.ENGINE_ROOT + "/shaders/gl/image.vert", string),
					gl_frag = #load(engine.ENGINE_ROOT + "/shaders/gl/image.frag", string),
					gles_vert = #load(engine.ENGINE_ROOT + "/shaders/gles/image.vert", string),
					gles_frag = #load(engine.ENGINE_ROOT + "/shaders/gles/image.frag", string))
				if !engine.object_pipeline_init(&__image_object_pipeline,
					[]vk.DescriptorSetLayout{engine.base_descriptor_set_layout(), engine.viewport_descriptor_set_layout(), engine.texture_descriptor_set_layout()},
					nil, nil,
					engine.object_draw_method{type = .Draw, vertex_count = 6}, 
					shader_code_set_image.vert, shader_code_set_image.frag, nil){
					intrinsics.trap()
				}
			},
			fini_proc = proc(data: rawptr) {
				engine.object_pipeline_deinit(&__image_object_pipeline)
			},
			allocator = context.allocator,
			data = nil,
		}
		engine.add_pipeline_set(pipeline_set)
	}
}


/*
Image object structure for rendering textures

Extends iobject with texture source data
*/
image :: struct {
    using _:engine.itransform_object,
    src: ^engine.texture,
}

@private image_vtable :engine.iobject_vtable = engine.iobject_vtable {
    draw = auto_cast image_draw,
}

image_deinit :: engine.itransform_object_deinit

image_init :: proc(self:^image, src:^engine.texture,
colorTransform:^engine.color_transform = nil, vtable:^engine.iobject_vtable = nil) {
	graphics_image_module_init()
    self.src = src
        
    if vtable == nil {
        self.vtable = &image_vtable
    } else {
        self.vtable = vtable
        if self.vtable.draw == nil do self.vtable.draw = auto_cast image_draw
    }

    engine.itransform_object_init(self, colorTransform, self.vtable)
	self.actual_type = typeid_of(image)
}

image_update_transform :: #force_inline proc(self:^image, pos:linalg.point3d, rotation:f32 = 0.0, scale:linalg.point = {1,1}, pivot:linalg.point = {0.0,0.0}) {
    engine.itransform_object_update_transform(self, pos, rotation, scale, pivot)
}
image_update_transform_matrix_raw :: #force_inline proc(self:^image, _mat:linalg.matrix44) {
    engine.itransform_object_update_transform_matrix_raw(self, _mat)
}
image_change_color_transform :: #force_inline proc(self:^image, colorTransform:^engine.color_transform) {
    engine.itransform_object_change_color_transform(self, colorTransform)
}

image_draw :: proc (self:^image, cmd:engine.command_buffer, viewport:^engine.viewport) {
	//self의 uniform, texture 리소스가 준비가 안됨. 드로우 하면 안됨.
	if engine.graphics_get_resource_draw(self.mat_idx) == nil do return
	if engine.graphics_get_resource_draw(self.src.set_idx) == nil do return

   	image_binding_sets_and_draw(cmd, self.set, viewport.set, self.src.set)
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
image_binding_sets_and_draw :: proc "contextless" (cmd:engine.command_buffer, imageSet:vk.DescriptorSet, viewSet:vk.DescriptorSet, textureSet:vk.DescriptorSet) {
    engine.graphics_pipeline_draw(cmd, &__image_object_pipeline, []vk.DescriptorSet{imageSet, viewSet, textureSet})
}