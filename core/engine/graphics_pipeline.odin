#+private
package engine

import vk "vendor:vulkan"
import "core:debug/trace"
import "core:engine/geometry"


init_pipelines :: proc() {
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
	animate_img_descriptor_set_layout = graphics_destriptor_set_layout_init(
		[]vk.DescriptorSetLayoutBinding {
			vk.DescriptorSetLayoutBindingInit(0, 1),
			vk.DescriptorSetLayoutBindingInit(1, 1),
			vk.DescriptorSetLayoutBindingInit(2, 1),},
	)

	nullVertexInputInfo := vk.PipelineVertexInputStateCreateInfo{
		sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount = 0,
		pVertexBindingDescriptions = nil,
		vertexAttributeDescriptionCount = 0,
		pVertexAttributeDescriptions = nil,
	}

	defaultDepthStencilState := vk.PipelineDepthStencilStateCreateInfoInit()
	pipelines:[3]vk.Pipeline
	pipelineCreateInfos:[len(pipelines)]vk.GraphicsPipelineCreateInfo

	shapeVertexInputBindingDescription := [1]vk.VertexInputBindingDescription{{
		binding = 0,
		stride = size_of(geometry.shape_vertex2d),
		inputRate = .VERTEX,
	}}

	shapeVertexInputAttributeDescription := [3]vk.VertexInputAttributeDescription{{
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
	}}

	custom_object_pipeline_init(&shape_pipeline,
		[]vk.DescriptorSetLayout{base_descriptor_set_layout(), viewport_descriptor_set_layout()},
		shapeVertexInputBindingDescription[:], shapeVertexInputAttributeDescription[:],
		object_draw_method{type = .DrawIndexed,}, 
		#load("shaders/shape.vert", string),
		#load("shaders/shape.frag", string),
		nil,
		defaultDepthStencilState)
	
	custom_object_pipeline_init(&img_pipeline,
				[]vk.DescriptorSetLayout{base_descriptor_set_layout(), viewport_descriptor_set_layout(), img_descriptor_set_layout()},
				nil, nil,
				object_draw_method{type = .Draw,}, 
				#load("shaders/tex.vert", string),
				#load("shaders/tex.frag", string),
				nil,
				defaultDepthStencilState)
				
	custom_object_pipeline_init(&animate_img_pipeline,
				[]vk.DescriptorSetLayout{animate_img_descriptor_set_layout, viewport_descriptor_set_layout(), img_descriptor_set_layout()},
				nil, nil,
				object_draw_method{type = .Draw,}, 
				#load("shaders/animate_tex.vert", string),
				#load("shaders/animate_tex.frag", string),
				nil,
				defaultDepthStencilState)
}

 clean_pipelines :: proc() {
	object_pipeline_deinit(&shape_pipeline)
	object_pipeline_deinit(&img_pipeline)
	object_pipeline_deinit(&animate_img_pipeline)

	vk.DestroyDescriptorSetLayout(graphics_device(), __base_descriptor_set_layout, nil)
	vk.DestroyDescriptorSetLayout(graphics_device(), __img_descriptor_set_layout, nil)
	vk.DestroyDescriptorSetLayout(graphics_device(), animate_img_descriptor_set_layout, nil)
}