#+private
package engine

import "base:intrinsics"
import vk "vendor:vulkan"
import "core:debug/trace"
import "core:thread"
import "core:engine/geometry"

when is_web {
} else {
	VULKAN_SHADER_VERT :: #load("shaders/vulkan/tex.vert", string)
	VULKAN_SHADER_FRAG :: #load("shaders/vulkan/tex.frag", string)
	VULKAN_SHADER_ANIMATE_VERT :: #load("shaders/vulkan/animate_tex.vert", string)
	VULKAN_SHADER_ANIMATE_FRAG :: #load("shaders/vulkan/animate_tex.frag", string)
	VULKAN_SHADER_SHAPE_COMPUTE :: #load("shaders/vulkan/shape.comp", string)
	VULKAN_SHADER_SCREEN_COPY_VERT :: #load("shaders/vulkan/screen_copy.vert", string)
	VULKAN_SHADER_SCREEN_COPY_FRAG :: #load("shaders/vulkan/screen_copy.frag", string)

	when !is_android {
		GL_SHADER_VERT :: #load("shaders/gl/tex.vert", string)
		GL_SHADER_FRAG :: #load("shaders/gl/tex.frag", string)
		GL_SHADER_ANIMATE_VERT :: #load("shaders/gl/animate_tex.vert", string)
		GL_SHADER_ANIMATE_FRAG :: #load("shaders/gl/animate_tex.frag", string)
		GL_SHADER_SHAPE_COMPUTE :: #load("shaders/gl/shape.comp", string)
		GL_SHADER_SCREEN_COPY_VERT :: #load("shaders/gl/screen_copy.vert", string)
		GL_SHADER_SCREEN_COPY_FRAG :: #load("shaders/gl/screen_copy.frag", string)
	}
}

when is_android || is_web {
	GLES_SHADER_VERT :: #load("shaders/gles/tex.vert", string)
	GLES_SHADER_FRAG :: #load("shaders/gles/tex.frag", string)
	GLES_SHADER_ANIMATE_VERT :: #load("shaders/gles/animate_tex.vert", string)
	GLES_SHADER_ANIMATE_FRAG :: #load("shaders/gles/animate_tex.frag", string)
	GLES_SHADER_SHAPE_COMPUTE :: #load("shaders/gles/shape.comp", string)
	GLES_SHADER_SCREEN_COPY_VERT :: #load("shaders/gles/screen_copy.vert", string)
	GLES_SHADER_SCREEN_COPY_FRAG :: #load("shaders/gles/screen_copy.frag", string)
}


init_pipelines :: proc() {
	when !is_web {
		__base_descriptor_set_layout = graphics_destriptor_set_layout_init(
			[]vk.DescriptorSetLayoutBinding {
				vk.DescriptorSetLayoutBindingInit(0, 1),
				vk.DescriptorSetLayoutBindingInit(1, 1),
			}
		)
		__img_descriptor_set_layout = graphics_destriptor_set_layout_init(
			[]vk.DescriptorSetLayoutBinding {
				vk.DescriptorSetLayoutBindingInit(0, 1, descriptorType = .COMBINED_IMAGE_SAMPLER),},
		)
		__animate_img_descriptor_set_layout = graphics_destriptor_set_layout_init(
			[]vk.DescriptorSetLayoutBinding {
				vk.DescriptorSetLayoutBindingInit(0, 1, stageFlags = {.FRAGMENT}),},
		)
	}

	thread.pool_add_task(&g_thread_pool, context.allocator, proc(task: thread.Task) {
		if !custom_object_pipeline_init(&img_pipeline,
				[]vk.DescriptorSetLayout{base_descriptor_set_layout(), viewport_descriptor_set_layout(), img_descriptor_set_layout()},
				nil, nil,
				object_draw_method{type = .Draw,}, 
				VULKAN_SHADER_VERT,
				VULKAN_SHADER_FRAG,
				nil,
				vk.PipelineDepthStencilStateCreateInfoInit()) {
					intrinsics.trap()
				}
	}, nil)

	thread.pool_add_task(&g_thread_pool, context.allocator, proc(task: thread.Task) {
		if !custom_object_pipeline_init(&animate_img_pipeline,
				[]vk.DescriptorSetLayout{base_descriptor_set_layout(), viewport_descriptor_set_layout(), 
					img_descriptor_set_layout(), animate_img_descriptor_set_layout()},
				nil, nil,
				object_draw_method{type = .Draw,}, 
				VULKAN_SHADER_ANIMATE_VERT,
				VULKAN_SHADER_ANIMATE_FRAG,
				nil,
				vk.PipelineDepthStencilStateCreateInfoInit()){
					intrinsics.trap()
				}
	}, nil)

	thread.pool_add_task(&g_thread_pool, context.allocator, proc(task: thread.Task) {
		if !custom_object_pipeline_init(&screen_copy_pipeline,
				nil,
				nil, nil,
				object_draw_method{type = .Draw,}, 
				VULKAN_SHADER_SCREEN_COPY_VERT,
				VULKAN_SHADER_SCREEN_COPY_FRAG,
				nil,
				vk.PipelineDepthStencilStateCreateInfoInit()){
					intrinsics.trap()
				}
	}, nil)

	if !compute_pipeline_init(&shape_compute_pipeline,
				VULKAN_SHADER_SHAPE_COMPUTE,
				[]vk.DescriptorSetLayout{base_descriptor_set_layout(), viewport_descriptor_set_layout()}){
					intrinsics.trap()
				}

	thread.pool_wait_all(&g_thread_pool)
}

 clean_pipelines :: proc() {
	compute_pipeline_deinit(&shape_compute_pipeline)
	object_pipeline_deinit(&screen_copy_pipeline)
	object_pipeline_deinit(&img_pipeline)
	object_pipeline_deinit(&animate_img_pipeline)

	when !is_web {
		if vulkan_version.major > 0 {
			vk.DestroyDescriptorSetLayout(graphics_device(), __base_descriptor_set_layout, nil)
			vk.DestroyDescriptorSetLayout(graphics_device(), __img_descriptor_set_layout, nil)
			vk.DestroyDescriptorSetLayout(graphics_device(), __animate_img_descriptor_set_layout, nil)
		}
	}
}