#+private
package engine

import "base:intrinsics"
import vk "vendor:vulkan"
import "core:debug/trace"
import "core:thread"
import "core:engine/geometry"

when IS_WEB {
} else {
	VULKAN_SHADER_VERT :: #load("shaders/vulkan/tex.vert", string)
	VULKAN_SHADER_FRAG :: #load("shaders/vulkan/tex.frag", string)
	VULKAN_SHADER_ANIMATE_VERT :: #load("shaders/vulkan/animate_tex.vert", string)
	VULKAN_SHADER_ANIMATE_FRAG :: #load("shaders/vulkan/animate_tex.frag", string)
	VULKAN_SHADER_SHAPE_VERT :: #load("shaders/vulkan/shape.vert", string)
	VULKAN_SHADER_SHAPE_FRAG :: #load("shaders/vulkan/shape.frag", string)

	when !is_android {
		GL_SHADER_VERT :: #load("shaders/gl/tex.vert", string)
		GL_SHADER_FRAG :: #load("shaders/gl/tex.frag", string)
		GL_SHADER_ANIMATE_VERT :: #load("shaders/gl/animate_tex.vert", string)
		GL_SHADER_ANIMATE_FRAG :: #load("shaders/gl/animate_tex.frag", string)
		GL_SHADER_SHAPE_VERT :: #load("shaders/gl/shape.vert", string)
		GL_SHADER_SHAPE_FRAG :: #load("shaders/gl/shape.frag", string)
	}
}

when is_android || IS_WEB {
	GLES_SHADER_VERT :: #load("shaders/gles/tex.vert", string)
	GLES_SHADER_FRAG :: #load("shaders/gles/tex.frag", string)
	GLES_SHADER_ANIMATE_VERT :: #load("shaders/gles/animate_tex.vert", string)
	GLES_SHADER_ANIMATE_FRAG :: #load("shaders/gles/animate_tex.frag", string)
	GLES_SHADER_SHAPE_VERT :: #load("shaders/gles/shape.vert", string)
	GLES_SHADER_SHAPE_FRAG :: #load("shaders/gles/shape.frag", string)
}


init_pipelines :: proc() {
	when !IS_WEB {
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
				vk.DescriptorSetLayoutBindingInit(0, 1),
				vk.DescriptorSetLayoutBindingInit(1, 1),
				vk.DescriptorSetLayoutBindingInit(2, 1),},
		)
	}

	shapeVertexInputBindingDescription := [1]vk.VertexInputBindingDescription{{
		binding = 0,
		stride = size_of(geometry.shape_vertex2d),
		inputRate = .VERTEX,
	}}
	shapeVertexInputAttributeDescription := [4]vk.VertexInputAttributeDescription{{
		location = 0,
		binding = 0,
		format = vk.Format.R32G32_SFLOAT,
		offset = 0,
	},
	{
		location = 1,
		binding = 0,
		format = vk.Format.R32G32B32_SFLOAT,
		offset = size_of(f32) * 2,
	},
	{
		location = 2,
		binding = 0,
		format = vk.Format.R32G32B32A32_SFLOAT,
		offset = size_of(f32) * (2 + 3),
	},
	{
		location = 3,
		binding = 0,
		format = vk.Format.R8G8B8A8_UINT,
		offset = size_of(f32) * (2 + 3 + 4),
	}}

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
				[]vk.DescriptorSetLayout{animate_img_descriptor_set_layout(), viewport_descriptor_set_layout(), img_descriptor_set_layout()},
				nil, nil,
				object_draw_method{type = .Draw,}, 
				VULKAN_SHADER_ANIMATE_VERT,
				VULKAN_SHADER_ANIMATE_FRAG,
				nil,
				vk.PipelineDepthStencilStateCreateInfoInit()){
					intrinsics.trap()
				}
	}, nil)

	if !custom_object_pipeline_init(&shape_pipeline,
				[]vk.DescriptorSetLayout{base_descriptor_set_layout(), viewport_descriptor_set_layout()},
				shapeVertexInputBindingDescription[:], shapeVertexInputAttributeDescription[:],
				object_draw_method{type = .DrawIndexed,}, 
				VULKAN_SHADER_SHAPE_VERT,
				VULKAN_SHADER_SHAPE_FRAG,
				nil,
				vk.PipelineDepthStencilStateCreateInfoInit()){
					intrinsics.trap()
				}

	thread.pool_wait_all(&g_thread_pool)
}

 clean_pipelines :: proc() {
	object_pipeline_deinit(&shape_pipeline)
	object_pipeline_deinit(&img_pipeline)
	object_pipeline_deinit(&animate_img_pipeline)

	when !IS_WEB {
		vk.DestroyDescriptorSetLayout(graphics_device(), __base_descriptor_set_layout, nil)
		vk.DestroyDescriptorSetLayout(graphics_device(), __img_descriptor_set_layout, nil)
		vk.DestroyDescriptorSetLayout(graphics_device(), __animate_img_descriptor_set_layout, nil)
	}
}