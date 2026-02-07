package sprite

import "core:math/rand"
import "base:intrinsics"
import "base:runtime"
import img "core:image"
import "core:math/linalg"
import "core:mem"
import vk "vendor:vulkan"
import "core:log"
import "core:engine"


@private __sprite_object_pipeline: engine.object_pipeline
sprite_object_pipeline :: proc() -> ^engine.object_pipeline {
	return &__sprite_object_pipeline
}

@private graphics_sprite_module_init :: proc() {
	if __sprite_object_pipeline.__pipeline_layout == 0 {
		pipeline_set := engine.pipeline_set{
			init_proc = proc(data: rawptr) {
				shader_code_set_sprite := engine.shader_code_set_init(
					vk_vert =  #load(engine.ENGINE_ROOT + "/shaders/vulkan/sprite.vert", string),
					vk_frag =  #load(engine.ENGINE_ROOT + "/shaders/vulkan/sprite.frag", string),
					gl_vert = #load(engine.ENGINE_ROOT + "/shaders/gl/sprite.vert", string),
					gl_frag = #load(engine.ENGINE_ROOT + "/shaders/gl/sprite.frag", string),
					gles_vert = #load(engine.ENGINE_ROOT + "/shaders/gles/sprite.vert", string),
					gles_frag = #load(engine.ENGINE_ROOT + "/shaders/gles/sprite.frag", string))
				if !engine.object_pipeline_init(&__sprite_object_pipeline,
					[]vk.DescriptorSetLayout{engine.base_descriptor_set_layout(), engine.viewport_descriptor_set_layout(), engine.texture_descriptor_set_layout()},
					nil, nil,
					engine.object_draw_method{type = .Draw, vertex_count = 6, instance_count = 1,}, 
					shader_code_set_sprite.vert, shader_code_set_sprite.frag, nil){
					intrinsics.trap()
				}
			},
			fini_proc = proc(data: rawptr) {
				engine.object_pipeline_deinit(&__sprite_object_pipeline)
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
sprite :: struct {
    using _:engine.itransform_object,
    src: ^engine.texture,
}

@private sprite_vtable :engine.iobject_vtable = engine.iobject_vtable {
    draw = auto_cast sprite_draw,
}

sprite_deinit :: engine.itransform_object_deinit

sprite_init :: proc(self:^sprite, src:^engine.texture,
colorTransform:^engine.color_transform = nil, vtable:^engine.iobject_vtable = nil) {
	graphics_sprite_module_init()
    self.src = src
        
    if vtable == nil {
        self.vtable = &sprite_vtable
    } else {
        self.vtable = vtable
        if self.vtable.draw == nil do self.vtable.draw = auto_cast sprite_draw
    }

    engine.itransform_object_init(self, colorTransform, self.vtable)
	self.actual_type = typeid_of(sprite)
}

sprite_update_transform :: #force_inline proc(self:^sprite, pos:linalg.point3d, rotation:f32 = 0.0, scale:linalg.point = {1,1}, pivot:linalg.point = {0.0,0.0}) {
    engine.itransform_object_update_transform(self, pos, rotation, scale, pivot)
}
sprite_update_transform_matrix_raw :: #force_inline proc(self:^sprite, _mat:linalg.matrix44) {
    engine.itransform_object_update_transform_matrix_raw(self, _mat)
}
sprite_change_color_transform :: #force_inline proc(self:^sprite, colorTransform:^engine.color_transform) {
    engine.itransform_object_change_color_transform(self, colorTransform)
}

sprite_draw :: proc (self:^sprite, cmd:engine.command_buffer, viewport:^engine.viewport) {
	//self의 uniform, texture 리소스가 준비가 안됨. 드로우 하면 안됨.
	if engine.graphics_get_resource_draw(self.mat_idx) == nil do return
	if engine.graphics_get_resource_draw(self.src.idx) == nil do return

   	sprite_binding_sets_and_draw(cmd, self.set, viewport.set, self.src.set)
}

/*
Binds descriptor sets and draws an sprite

Inputs:
- cmd: Command buffer to record draw commands
- spriteSet: Descriptor set for the sprite transform uniforms
- textureSet: Descriptor set for the texture

Returns:
- None
*/
sprite_binding_sets_and_draw :: proc "contextless" (cmd:engine.command_buffer, spriteSet:vk.DescriptorSet, viewSet:vk.DescriptorSet, textureSet:vk.DescriptorSet) {
    engine.graphics_pipeline_draw(cmd, &__sprite_object_pipeline, []vk.DescriptorSet{spriteSet, viewSet, textureSet})
}