package sprite

import "core:engine"
import vk "vendor:vulkan"
import "base:intrinsics"
import "core:mem"
import "../animator"

animate_sprite :: struct {
	using _:animator.ianimate_object,
    src: ^engine.texture_array,
}


@rodata descriptor_pool_size_animate_sprite_uniform_pool : [1]engine.descriptor_pool_size = {{type = .UNIFORM, cnt = 3, binding = 0}}

@private __animate_sprite_object_pipeline: engine.object_pipeline
@private __animate_sprite_descriptor_set_layout: vk.DescriptorSetLayout

@private animate_sprite_vtable :animator.ianimate_object_vtable = animator.ianimate_object_vtable {
    draw = auto_cast animate_sprite_draw,
    deinit = auto_cast animate_sprite_deinit,
    update_descriptor_set = auto_cast animate_sprite_update_descriptor_set,
}

animate_sprite_descriptor_set_layout :: proc() -> vk.DescriptorSetLayout {
	return __animate_sprite_descriptor_set_layout
}
animate_sprite_object_pipeline :: proc() -> ^engine.object_pipeline {
	return &__animate_sprite_object_pipeline
}

@private graphics_animate_sprite_module_init :: proc() {
	if __animate_sprite_object_pipeline.__pipeline_layout == 0 {
		pipeline_set := engine.pipeline_set{
			init_proc = proc(data: rawptr) {
				shader_code_set_sprite := engine.shader_code_set_init(
					vk_vert =  #load(engine.ENGINE_ROOT + "/shaders/vulkan/animate_sprite.vert", string),
					vk_frag =  #load(engine.ENGINE_ROOT + "/shaders/vulkan/animate_sprite.frag", string),
					gl_vert = #load(engine.ENGINE_ROOT + "/shaders/gl/animate_sprite.vert", string),
					gl_frag = #load(engine.ENGINE_ROOT + "/shaders/gl/animate_sprite.frag", string),
					gles_vert = #load(engine.ENGINE_ROOT + "/shaders/gles/animate_sprite.vert", string),
					gles_frag = #load(engine.ENGINE_ROOT + "/shaders/gles/animate_sprite.frag", string))
				if !engine.object_pipeline_init(&__animate_sprite_object_pipeline,
					[]vk.DescriptorSetLayout{__animate_sprite_descriptor_set_layout,
						engine.viewport_descriptor_set_layout(),
						engine.texture_descriptor_set_layout(),},
					nil, nil,
					engine.object_draw_method{type = .Draw, vertex_count = 6, instance_count = 1,}, 
					shader_code_set_sprite.vert, shader_code_set_sprite.frag, nil){
					intrinsics.trap()
				}
			},
			fini_proc = proc(data: rawptr) {
				engine.object_pipeline_deinit(&__animate_sprite_object_pipeline)
			},
			allocator = context.allocator,
			data = nil,
		}
		engine.add_pipeline_set(pipeline_set)
	}
}

@private animate_sprite_update_descriptor_set :: proc(self:^animate_sprite) {
	if self.set == 0 {
		self.set, self.set_idx = engine.get_descriptor_set(descriptor_pool_size_animate_sprite_uniform_pool[:], __animate_sprite_descriptor_set_layout)
	}
	engine.update_descriptor_set(self.set, descriptor_pool_size_animate_sprite_uniform_pool[:], {
		engine.graphics_get_resource(self.mat_idx),
		engine.graphics_get_resource(self.color_transform.mat_idx),
		engine.graphics_get_resource(self.frame_idx)
	})
}

animate_sprite_init :: proc(self:^animate_sprite, src:^engine.texture_array, colorTransform:^engine.color_transform = nil, vtable:^engine.iobject_vtable = nil) {
	graphics_animate_sprite_module_init()
	self.src = src

    if vtable == nil {
        self.vtable = &animate_sprite_vtable
    } else {
        self.vtable = vtable
        if self.vtable.draw == nil do self.vtable.draw = auto_cast animate_sprite_draw
    }

    animator.ianimate_object_init(self, colorTransform, auto_cast self.vtable)
	self.actual_type = typeid_of(animate_sprite)
}

animate_sprite_deinit :: proc(self:^animate_sprite) {
	animator.ianimate_object_deinit(self)
}

animate_sprite_draw :: proc(self:^animate_sprite, cmd:engine.command_buffer, viewport:^engine.viewport) {
	if engine.graphics_get_resource_draw(self.mat_idx) == nil do return
	if engine.graphics_get_resource_draw(self.src.idx) == nil do return

	animate_sprite_binding_sets_and_draw(cmd, self.set, viewport.set, self.src.set)
}

animate_sprite_binding_sets_and_draw :: proc "contextless" (cmd:engine.command_buffer, array_spriteSet:vk.DescriptorSet, viewSet:vk.DescriptorSet, textureSet:vk.DescriptorSet) {
    engine.graphics_pipeline_draw(cmd, &__animate_sprite_object_pipeline, []vk.DescriptorSet{array_spriteSet, viewSet, textureSet})
}