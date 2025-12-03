#+private
package engine

import "base:runtime"
import "core:dynlib"
import "core:fmt"
import "core:math"
import "vendor:engine/geometry"
import "core:math/linalg"
import "core:mem"
import "core:debug/trace"
import "core:strings"
import "core:reflect"
import "core:sync"
import "core:thread"
import vk "vendor:vulkan"
import "vendor:glfw"
import "core:sys/windows"

vkInstance: vk.Instance
vkDevice: vk.Device
vkLibrary: dynlib.Library
vkSwapchain: vk.SwapchainKHR

vkDebugUtilsMessenger: vk.DebugUtilsMessengerEXT

vkSurface: vk.SurfaceKHR

vkPhysicalDevice: vk.PhysicalDevice
vkPhysicalMemProp: vk.PhysicalDeviceMemoryProperties
vkPhysicalProp: vk.PhysicalDeviceProperties

vkGraphicsQueue: vk.Queue
vkPresentQueue: vk.Queue
vkQueueMutex: sync.Mutex

vkGraphicsFamilyIndex: u32 = max(u32)
vkPresentFamilyIndex: u32 = max(u32)

vkLinearSampler: vk.Sampler
vkNearestSampler: vk.Sampler

vkRenderPass: vk.RenderPass
vkRenderPassClear: vk.RenderPass
vkRenderPassSample: vk.RenderPass
vkRenderPassSampleClear: vk.RenderPass
vkRenderPassCopy: vk.RenderPass

vkFrameBuffers: []vk.Framebuffer
vkFrameDepthStencilTexture: Texture
vkMSAAFrameTexture: Texture
// vkClearFrameBuffers: []vk.Framebuffer

vkMSAACount :: 4
vkWIREMODE :: false

vkFrameBufferImageViews: []vk.ImageView

vkRotationMatrix: linalg.Matrix

MAX_FRAMES_IN_FLIGHT :: 2
vkImageAvailableSemaphore: [MAX_FRAMES_IN_FLIGHT]vk.Semaphore
vkRenderFinishedSemaphore: [MAX_FRAMES_IN_FLIGHT][]vk.Semaphore
vkInFlightFence: [MAX_FRAMES_IN_FLIGHT]vk.Fence

vkGetInstanceProcAddr: proc "system" (
	_instance: vk.Instance,
	_name: cstring,
) -> vk.ProcVoidFunction

vkDebugCallBack :: proc "system" (
	messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
	messageTypes: vk.DebugUtilsMessageTypeFlagsEXT,
	pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
	pUserData: rawptr,
) -> b32 {
	context = runtime.default_context()

	//#VUID-VkSwapchainCreateInfoKHR-pNext-07781 1284057537
	//#VUID-vkDestroySemaphore-semaphore-05149 -1813885519
	switch pCallbackData.messageIdNumber {
	case 1284057537, -1813885519:
		return false
	}
	print(pCallbackData.pMessage)

	return false
}

@(rodata)
DEVICE_EXTENSIONS: [3]cstring = {vk.KHR_SWAPCHAIN_EXTENSION_NAME, vk.EXT_FULL_SCREEN_EXCLUSIVE_EXTENSION_NAME, vk.KHR_SHADER_CLOCK_EXTENSION_NAME}
@(rodata)
INSTANCE_EXTENSIONS: [2]cstring = {
	vk.KHR_GET_SURFACE_CAPABILITIES_2_EXTENSION_NAME,
	vk.KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME,
}
@(rodata)
LAYERS: [1]cstring = {"VK_LAYER_KHRONOS_validation"}
DEVICE_EXTENSIONS_CHECK: [len(DEVICE_EXTENSIONS)]bool
INSTANCE_EXTENSIONS_CHECK: [len(INSTANCE_EXTENSIONS)]bool
LAYERS_CHECK: [len(LAYERS)]bool

validation_layer_support :: #force_inline proc "contextless" () -> bool {return LAYERS_CHECK[0]}
VK_KHR_portability_enumeration_support :: #force_inline proc "contextless" () -> bool {return INSTANCE_EXTENSIONS_CHECK[1]}
VK_EXT_full_screen_exclusive_support :: #force_inline proc "contextless" () -> bool {return DEVICE_EXTENSIONS_CHECK[1]}

vkShapeVertShader: vk.ShaderModule
vkShapeFragShader: vk.ShaderModule
vkShapeWireFragShader: vk.ShaderModule
vkTexVertShader: vk.ShaderModule
vkTexFragShader: vk.ShaderModule
vkAnimateTexVertShader: vk.ShaderModule
vkAnimateTexFragShader: vk.ShaderModule
//vkCopyScreenVertShader: vk.ShaderModule
//vkCopyScreenFragShader: vk.ShaderModule

shapeShaderStages: [2]vk.PipelineShaderStageCreateInfo
shapeWireShaderStages: [2]vk.PipelineShaderStageCreateInfo
texShaderStages: [2]vk.PipelineShaderStageCreateInfo
animateTexShaderStages: [2]vk.PipelineShaderStageCreateInfo
//copyScreenShaderStages: [2]vk.PipelineShaderStageCreateInfo

vkShapeDescriptorSetLayout: vk.DescriptorSetLayout
vkTexDescriptorSetLayout: vk.DescriptorSetLayout
//used animate tex
vkTexDescriptorSetLayout2: vk.DescriptorSetLayout
vkAnimateTexDescriptorSetLayout: vk.DescriptorSetLayout
//vkCopyScreenDescriptorSetLayout: vk.DescriptorSetLayout

//vkCopyScreenDescriptorSet : vk.DescriptorSet
//vkCopyScreenDescriptorPool : vk.DescriptorPool


vkShapePipelineLayout: vk.PipelineLayout
vkTexPipelineLayout: vk.PipelineLayout
vkAnimateTexPipelineLayout: vk.PipelineLayout
//vkCopyScreenPipelineLayout: vk.PipelineLayout

vkShapePipeline: vk.Pipeline
vkTexPipeline: vk.Pipeline
vkAnimateTexPipeline: vk.Pipeline
//vkCopyScreenPipeline: vk.Pipeline

vkCmdPool:vk.CommandPool
vkCmdBuffer:[MAX_FRAMES_IN_FLIGHT]vk.CommandBuffer

__depthFmt:TextureFmt
__swapImgCnt:u32 = 3

when vkMSAACount == 4 {
	vkSampleCountFlags :: vk.SampleCountFlags{._4}
} else when vkMSAACount == 8 {
	vkSampleCountFlags :: vk.SampleCountFlags{._8}
} else when vkMSAACount == 1 {
	vkSampleCountFlags :: vk.SampleCountFlags{._1}
} else {
	#assert("invalid vkMSAACount")
}

when vkMSAACount == 1 {
	vkPipelineMultisampleStateCreateInfo := vk.PipelineMultisampleStateCreateInfoInit(vkSampleCountFlags, sampleShadingEnable = false, minSampleShading = 0.0)
} else {
	vkPipelineMultisampleStateCreateInfo := vk.PipelineMultisampleStateCreateInfoInit(vkSampleCountFlags, sampleShadingEnable = true, minSampleShading = 1.0)	
}

@(private="file") __vkColorAlphaBlendingExternalState := [1]vk.PipelineColorBlendAttachmentState{vk.PipelineColorBlendAttachmentStateInit(
	srcColorBlendFactor = vk.BlendFactor.SRC_ALPHA,
	dstColorBlendFactor = vk.BlendFactor.ONE_MINUS_SRC_ALPHA,
	colorBlendOp = vk.BlendOp.ADD,
	srcAlphaBlendFactor = vk.BlendFactor.ONE,
	dstAlphaBlendFactor = vk.BlendFactor.ONE_MINUS_SRC_ALPHA,
	alphaBlendOp = vk.BlendOp.ADD,
)}
@(private="file") __vkNoBlendingState := [1]vk.PipelineColorBlendAttachmentState{vk.PipelineColorBlendAttachmentStateInit(
	blendEnable = false,
	srcColorBlendFactor = vk.BlendFactor.ONE,
	dstColorBlendFactor = vk.BlendFactor.ZERO,
	colorBlendOp = vk.BlendOp.ADD,
	srcAlphaBlendFactor = vk.BlendFactor.ONE,
	dstAlphaBlendFactor = vk.BlendFactor.ZERO,
	alphaBlendOp = vk.BlendOp.ADD,
	colorWriteMask = {},
)}
@(private="file") __vkCopyBlendingState := [1]vk.PipelineColorBlendAttachmentState{vk.PipelineColorBlendAttachmentStateInit(
	srcColorBlendFactor = vk.BlendFactor.ONE,
	dstColorBlendFactor = vk.BlendFactor.ONE_MINUS_SRC_ALPHA,
	colorBlendOp = vk.BlendOp.ADD,
	srcAlphaBlendFactor = vk.BlendFactor.ZERO,
	dstAlphaBlendFactor = vk.BlendFactor.ONE,
	alphaBlendOp = vk.BlendOp.ADD,
)}
///https://stackoverflow.com/a/34963588
vkColorAlphaBlendingExternal := vk.PipelineColorBlendStateCreateInfoInit(__vkColorAlphaBlendingExternalState[:1])
vkNoBlending := vk.PipelineColorBlendStateCreateInfoInit(__vkNoBlendingState[:1])
vkCopyBlending := vk.PipelineColorBlendStateCreateInfoInit(__vkNoBlendingState[:1])

vkInitShaderModules :: proc() {
	vkShapeVertShader = vk.CreateShaderModule2(vkDevice, #load("shaders/shape.vert.spv"))
	vkShapeFragShader = vk.CreateShaderModule2(vkDevice, #load("shaders/shape.frag.spv"))
	when vkWIREMODE do vkShapeWireFragShader = vk.CreateShaderModule2(vkDevice, #load("shaders/shape_wire.frag.spv"))
	vkTexVertShader = vk.CreateShaderModule2(vkDevice, #load("shaders/tex.vert.spv"))
	vkTexFragShader = vk.CreateShaderModule2(vkDevice, #load("shaders/tex.frag.spv"))
	vkAnimateTexVertShader = vk.CreateShaderModule2(vkDevice, #load("shaders/animate_tex.vert.spv"))
	vkAnimateTexFragShader = vk.CreateShaderModule2(vkDevice, #load("shaders/animate_tex.frag.spv"))
	//vkCopyScreenVertShader = vk.CreateShaderModule2(vkDevice, #load("shaders/screen_copy.vert.spv"))
	//vkCopyScreenFragShader = vk.CreateShaderModule2(vkDevice, #load("shaders/screen_copy.frag.spv"))

	shapeShaderStages = vk.CreateShaderStages(vkShapeVertShader, vkShapeFragShader)
	when vkWIREMODE do shapeWireShaderStages = vk.CreateShaderStages(vkShapeVertShader, vkShapeWireFragShader)
	texShaderStages = vk.CreateShaderStages(vkTexVertShader, vkTexFragShader)
	animateTexShaderStages = vk.CreateShaderStages(vkAnimateTexVertShader, vkAnimateTexFragShader)
	//copyScreenShaderStages = vk.CreateShaderStages(vkCopyScreenVertShader, vkCopyScreenFragShader)
}

vkCleanShaderModules :: proc() {
	vk.DestroyShaderModule(vkDevice, vkShapeVertShader, nil)
	vk.DestroyShaderModule(vkDevice, vkShapeFragShader, nil)
	when vkWIREMODE do vk.DestroyShaderModule(vkDevice, vkShapeWireFragShader, nil)
	vk.DestroyShaderModule(vkDevice, vkTexVertShader, nil)
	vk.DestroyShaderModule(vkDevice, vkTexFragShader, nil)
	vk.DestroyShaderModule(vkDevice, vkAnimateTexVertShader, nil)
	vk.DestroyShaderModule(vkDevice, vkAnimateTexFragShader, nil)
	//vk.DestroyShaderModule(vkDevice, vkCopyScreenVertShader, nil)
	//vk.DestroyShaderModule(vkDevice, vkCopyScreenFragShader, nil)
}

vkInitPipelines :: proc() {
	//vk.InitVulkanTemplate()

	vkShapeDescriptorSetLayout = vk.DescriptorSetLayoutInit(vkDevice,
		[]vk.DescriptorSetLayoutBinding {
			vk.DescriptorSetLayoutBindingInit(0, 1, stageFlags = {.VERTEX}),
			vk.DescriptorSetLayoutBindingInit(1, 1, stageFlags = {.VERTEX}),
			vk.DescriptorSetLayoutBindingInit(2, 1, stageFlags = {.VERTEX}),
			vk.DescriptorSetLayoutBindingInit(3, 1, stageFlags = {.FRAGMENT}),
		}
	)
	vkShapePipelineLayout = vk.PipelineLayoutInit(vkDevice,
		[]vk.DescriptorSetLayout{vkShapeDescriptorSetLayout},
	)

	// vkCopyScreenDescriptorSetLayout = vk.DescriptorSetLayoutInit(vkDevice,
	// 	[]vk.DescriptorSetLayoutBinding {
	// 		vk.DescriptorSetLayoutBindingInit(0, 1, descriptorType = .INPUT_ATTACHMENT, stageFlags = {.FRAGMENT}),},
	// )
	// vkCopyScreenPipelineLayout = vk.PipelineLayoutInit(vkDevice,
	// 	[]vk.DescriptorSetLayout{vkCopyScreenDescriptorSetLayout},
	// )

	vkTexDescriptorSetLayout = vk.DescriptorSetLayoutInit(vkDevice,
		[]vk.DescriptorSetLayoutBinding {
			vk.DescriptorSetLayoutBindingInit(0, 1),
			vk.DescriptorSetLayoutBindingInit(1, 1),
			vk.DescriptorSetLayoutBindingInit(2, 1),
			vk.DescriptorSetLayoutBindingInit(3, 1, stageFlags = {.FRAGMENT}),},
	)
	vkTexDescriptorSetLayout2 = vk.DescriptorSetLayoutInit(vkDevice,
		[]vk.DescriptorSetLayoutBinding {
			vk.DescriptorSetLayoutBindingInit(0, 1, descriptorType = .COMBINED_IMAGE_SAMPLER),},
	)
	vkTexPipelineLayout = vk.PipelineLayoutInit(vkDevice,
		[]vk.DescriptorSetLayout{vkTexDescriptorSetLayout, vkTexDescriptorSetLayout2},
	)

	vkAnimateTexDescriptorSetLayout = vk.DescriptorSetLayoutInit(vkDevice,
		[]vk.DescriptorSetLayoutBinding {
			vk.DescriptorSetLayoutBindingInit(0, 1),
			vk.DescriptorSetLayoutBindingInit(1, 1),
			vk.DescriptorSetLayoutBindingInit(2, 1),
			vk.DescriptorSetLayoutBindingInit(3, 1, stageFlags = {.FRAGMENT}),
			vk.DescriptorSetLayoutBindingInit(4, 1, stageFlags = {.FRAGMENT}),},
	)
	vkAnimateTexPipelineLayout = vk.PipelineLayoutInit(vkDevice,
		[]vk.DescriptorSetLayout{vkAnimateTexDescriptorSetLayout, vkTexDescriptorSetLayout2},
	)

	// vkCopyScreenDescriptorSetLayout = vk.DescriptorSetLayoutInit(vkDevice,
	// 	[]vk.DescriptorSetLayoutBinding {
	// 		vk.DescriptorSetLayoutBindingInit(
	// 			0, 1, descriptorType = .INPUT_ATTACHMENT, stageFlags = {.FRAGMENT}),},
	// )
	//vkCopyScreenPipelineLayout = vk.PipelineLayoutInit(vkDevice,
	//	[]vk.DescriptorSetLayout{vkCopyScreenDescriptorSetLayout},
	//)

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
		stride = size_of(geometry.ShapeVertex2D),
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
	viewportState := vk.PipelineViewportStateCreateInfoInit()
	shapeVertexInputState := vk.PipelineVertexInputStateCreateInfoInit(shapeVertexInputBindingDescription[:], shapeVertexInputAttributeDescription[:])
	wireFrame := vk.PipelineRasterizationStateCreateInfoInit(.LINE)

	
	when vkWIREMODE {
		pipelineCreateInfos[0] = vk.GraphicsPipelineCreateInfoInit(
			stages = shapeWireShaderStages[:],
			layout = vkShapePipelineLayout,
			renderPass = vkRenderPass,
			pMultisampleState = &vkPipelineMultisampleStateCreateInfo,
			pDepthStencilState = &defaultDepthStencilState,
			pColorBlendState = &vk.DefaultPipelineColorBlendStateCreateInfo,
			pVertexInputState = &shapeVertexInputState,
			pViewportState = &viewportState,
			pRasterizationState = &wireFrame,
		)
	} else {
		pipelineCreateInfos[0] = vk.GraphicsPipelineCreateInfoInit(
			stages = shapeShaderStages[:],
			layout = vkShapePipelineLayout,
			renderPass = vkRenderPass,
			pMultisampleState = &vkPipelineMultisampleStateCreateInfo,
			pDepthStencilState = &defaultDepthStencilState,
			pColorBlendState = &vk.DefaultPipelineColorBlendStateCreateInfo,
			pVertexInputState = &shapeVertexInputState,
			pViewportState = &viewportState,
		)
	}

	pipelineCreateInfos[1] = vk.GraphicsPipelineCreateInfoInit(
		stages = texShaderStages[:],
		layout = vkTexPipelineLayout,
		renderPass = vkRenderPass,
		pMultisampleState = &vkPipelineMultisampleStateCreateInfo,
		pDepthStencilState = &defaultDepthStencilState,
		pColorBlendState = &vk.DefaultPipelineColorBlendStateCreateInfo,
		pViewportState = &viewportState,
	)
	pipelineCreateInfos[2] = vk.GraphicsPipelineCreateInfoInit(
		stages = animateTexShaderStages[:],
		layout = vkAnimateTexPipelineLayout,
		renderPass = vkRenderPass,
		pMultisampleState = &vkPipelineMultisampleStateCreateInfo,
		pDepthStencilState = &defaultDepthStencilState,
		pColorBlendState = &vk.DefaultPipelineColorBlendStateCreateInfo,
		pViewportState = &viewportState,
	)
	// pipelineCreateInfos[3] = vk.GraphicsPipelineCreateInfoInit(
	// 	stages = copyScreenShaderStages[:],
	// 	layout = vkCopyScreenPipelineLayout,
	// 	renderPass = vkRenderPassCopy,
	// 	pMultisampleState = &vk.DefaultPipelineMultisampleStateCreateInfo,
	// 	pDepthStencilState = nil,
	// 	pColorBlendState = &vkCopyBlending,
	// 	pViewportState = &viewportState,
	// )
	res := vk.CreateGraphicsPipelines(vkDevice, 0, len(pipelines), raw_data(pipelineCreateInfos[:]), nil, raw_data(pipelines[:]))
	if res != .SUCCESS {
		trace.panic_log(res)
	}

	vkShapePipeline = pipelines[0]
	vkTexPipeline = pipelines[1]
	vkAnimateTexPipeline = pipelines[2]
	//vkCopyScreenPipeline = pipelines[3]
}

vkBeginSingleTimeCmd :: proc "contextless" () -> vk.CommandBuffer {
	cmd:vk.CommandBuffer
	res := vk.AllocateCommandBuffers(vkDevice, &vk.CommandBufferAllocateInfo{
		sType = vk.StructureType.COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool = vkCmdPool,
		level = vk.CommandBufferLevel.PRIMARY,
		commandBufferCount = 1,
	}, &cmd)
	if res != .SUCCESS do trace.panic_log("vkBeginSingleTimeCmd vk.AllocateCommandBuffers(&cmd) : ", res)

	beginInfo := vk.CommandBufferBeginInfo {
		flags = {.ONE_TIME_SUBMIT},
		sType = vk.StructureType.COMMAND_BUFFER_BEGIN_INFO,
	}
	vk.BeginCommandBuffer(cmd, &beginInfo)

	return cmd
}

vkEndSingleTimeCmd :: proc "contextless" (_cmd:vk.CommandBuffer)  {
	cmd := _cmd
	vk.EndCommandBuffer(cmd)

	submitInfo := vk.SubmitInfo {
		commandBufferCount = 1,
		pCommandBuffers    = &cmd,
		sType              = .SUBMIT_INFO,
	}
	res := vk.QueueSubmit(vkGraphicsQueue, 1, &submitInfo, 0)
	if res != .SUCCESS do trace.panic_log("vkEndSingleTimeCmd res := vk.QueueSubmit(vkGraphicsQueue, 1, &submitInfo, 0) : ", res)

	vkWaitGraphicsIdle()

	vk.FreeCommandBuffers(vkDevice, vkCmdPool, 1, &cmd)
}

vkCleanPipelines :: proc() {
	vk.DestroyDescriptorSetLayout(vkDevice, vkShapeDescriptorSetLayout, nil)
	vk.DestroyDescriptorSetLayout(vkDevice, vkTexDescriptorSetLayout, nil)
	vk.DestroyDescriptorSetLayout(vkDevice, vkTexDescriptorSetLayout2, nil)
	vk.DestroyDescriptorSetLayout(vkDevice, vkAnimateTexDescriptorSetLayout, nil)
	//vk.DestroyDescriptorSetLayout(vkDevice, vkCopyScreenDescriptorSetLayout, nil)

	vk.DestroyPipelineLayout(vkDevice, vkShapePipelineLayout, nil)
	vk.DestroyPipelineLayout(vkDevice, vkTexPipelineLayout, nil)
	vk.DestroyPipelineLayout(vkDevice, vkAnimateTexPipelineLayout, nil)
	//vk.DestroyPipelineLayout(vkDevice, vkCopyScreenPipelineLayout, nil)

	vk.DestroyPipeline(vkDevice, vkShapePipeline, nil)
	vk.DestroyPipeline(vkDevice, vkTexPipeline, nil)
	vk.DestroyPipeline(vkDevice, vkAnimateTexPipeline, nil)
	//vk.DestroyPipeline(vkDevice, vkCopyScreenPipeline, nil)
}

vkFmts:[]vk.SurfaceFormatKHR
vkFmt:vk.SurfaceFormatKHR = {
	format = .UNDEFINED,
	colorSpace = .SRGB_NONLINEAR
}
vkPresentModes:[]vk.PresentModeKHR
vkPresentMode:vk.PresentModeKHR
vkSurfaceCap:vk.SurfaceCapabilitiesKHR
vkExtent:vk.Extent2D
vkExtent_rotation:vk.Extent2D

vkDepthHasOptimal:=false
vkDepthHasTransferSrcOptimal:=false
vkDepthHasTransferDstOptimal:=false
vkDepthHasSampleOptimal:=false

vkColorHasAttachOptimal:=false
vkColorHasSampleOptimal:=false
vkColorHasTransferSrcOptimal:=false
vkColorHasTransferDstOptimal:=false

vkReleasedFullScreenEx := true


initSwapChain :: proc() {
	fmtCnt:u32
	vk.GetPhysicalDeviceSurfaceFormatsKHR(vkPhysicalDevice, vkSurface, &fmtCnt, nil)
	vkFmts = mem.make_non_zeroed([]vk.SurfaceFormatKHR, fmtCnt)
	vk.GetPhysicalDeviceSurfaceFormatsKHR(vkPhysicalDevice, vkSurface, &fmtCnt, raw_data(vkFmts))

	presentModeCnt:u32
	vk.GetPhysicalDeviceSurfacePresentModesKHR(vkPhysicalDevice, vkSurface, &presentModeCnt, nil)
	vkPresentModes = mem.make_non_zeroed([]vk.PresentModeKHR, presentModeCnt)
	vk.GetPhysicalDeviceSurfacePresentModesKHR(vkPhysicalDevice, vkSurface, &presentModeCnt, raw_data(vkPresentModes))

	for f in vkFmts {
		if f.format == .R8G8B8A8_UNORM || f.format == .B8G8R8A8_UNORM {
			when is_log {
				printfln("XFIT SYSLOG : vulkan swapchain format : %s, colorspace : %s\n", f.format, f.colorSpace)
			}
			vkFmt = f
			break;
		}
	}
	if vkFmt.format == .UNDEFINED do trace.panic_log("Xfit vulkan unsupported format")

	depthProp:vk.FormatProperties
	vk.GetPhysicalDeviceFormatProperties(vkPhysicalDevice, .D24_UNORM_S8_UINT, &depthProp)
	vkDepthHasOptimal = .DEPTH_STENCIL_ATTACHMENT in depthProp.optimalTilingFeatures

	__depthFmt = .D24UnormS8Uint
	if !vkDepthHasOptimal && .DEPTH_STENCIL_ATTACHMENT in depthProp.linearTilingFeatures {//not support D24_UNORM_S8_UINT
		vk.GetPhysicalDeviceFormatProperties(vkPhysicalDevice, .D32_SFLOAT_S8_UINT, &depthProp)
		vkDepthHasOptimal = .DEPTH_STENCIL_ATTACHMENT in depthProp.optimalTilingFeatures

		if !vkDepthHasOptimal && .DEPTH_STENCIL_ATTACHMENT in depthProp.linearTilingFeatures {
			vk.GetPhysicalDeviceFormatProperties(vkPhysicalDevice, .D16_UNORM_S8_UINT, &depthProp)
			vkDepthHasOptimal = .DEPTH_STENCIL_ATTACHMENT in depthProp.optimalTilingFeatures
			__depthFmt = .D16UnormS8Uint
		} else {
			__depthFmt = .D32SfloatS8Uint
		}
	}
	vkDepthHasTransferSrcOptimal = .TRANSFER_SRC in depthProp.optimalTilingFeatures
	vkDepthHasTransferDstOptimal = .TRANSFER_DST in depthProp.optimalTilingFeatures
	vkDepthHasSampleOptimal = .SAMPLED_IMAGE in depthProp.optimalTilingFeatures

	colorProp:vk.FormatProperties
	vk.GetPhysicalDeviceFormatProperties(vkPhysicalDevice, vkFmt.format, &colorProp)
	vkColorHasAttachOptimal = .COLOR_ATTACHMENT in colorProp.optimalTilingFeatures
	vkColorHasSampleOptimal = .SAMPLED_IMAGE in colorProp.optimalTilingFeatures
	vkColorHasTransferSrcOptimal =.TRANSFER_SRC in colorProp.optimalTilingFeatures
	vkColorHasTransferDstOptimal = .TRANSFER_DST in colorProp.optimalTilingFeatures

	when is_log {
		printfln("XFIT SYSLOG : depth format : %s", __depthFmt)
		println("XFIT SYSLOG : optimal format supports")
		printfln("vkDepthHasOptimal : %t", vkDepthHasOptimal)
		printfln("vkDepthHasTransferSrcOptimal : %t", vkDepthHasTransferSrcOptimal)
		printfln("vkDepthHasTransferDstOptimal : %t", vkDepthHasTransferDstOptimal)
		printfln("vkDepthHasSampleOptimal : %t", vkDepthHasSampleOptimal)
		printfln("vkColorHasAttachOptimal : %t", vkColorHasAttachOptimal)
		printfln("vkColorHasSampleOptimal : %t", vkColorHasSampleOptimal)
		printfln("vkColorHasTransferSrcOptimal : %t", vkColorHasTransferSrcOptimal)
		printfln("vkColorHasTransferDstOptimal : %t", vkColorHasTransferDstOptimal)
	}
}

vkCreateSwapChainAndImageViews :: proc() -> bool {
	vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(vkPhysicalDevice, vkSurface, &vkSurfaceCap)

	if(vkSurfaceCap.currentExtent.width == max(u32)) {
		vkSurfaceCap.currentExtent.width = clamp(u32(__windowWidth.?), vkSurfaceCap.minImageExtent.width, vkSurfaceCap.maxImageExtent.width)
		vkSurfaceCap.currentExtent.height = clamp(u32(__windowHeight.?), vkSurfaceCap.minImageExtent.height, vkSurfaceCap.maxImageExtent.height)
	}
	vkExtent = vkSurfaceCap.currentExtent
	vkExtent_rotation = vkExtent

	if vkExtent.width == 0 || vkExtent.height == 0 {
		return false
	}
	
	if is_mobile {
		if .ROTATE_90 in vkSurfaceCap.currentTransform {
			vkExtent_rotation.width = vkExtent.height
			vkExtent_rotation.height = vkExtent.width
			__screenOrientation = .Landscape90
		} else if .ROTATE_270 in vkSurfaceCap.currentTransform {
			vkExtent_rotation.width = vkExtent.height
			vkExtent_rotation.height = vkExtent.width
			__screenOrientation = .Landscape270
		} else if .ROTATE_180 in vkSurfaceCap.currentTransform {
			__screenOrientation = .Vertical180
		} else if .IDENTITY in vkSurfaceCap.currentTransform {
			__screenOrientation = .Vertical360
		}
		__windowWidth = int(vkExtent.width)
		__windowHeight = int(vkExtent.height)
	}

	vkPresentMode = .FIFO
	if __vSync == .Double {
		when is_log {
			if programStart do println("XFIT SYSLOG : vulkan present mode fifo_khr vsync double")
		}
	} else {
		if __vSync == .Triple {
			for p in vkPresentModes {
				if p == .MAILBOX {
					when is_log {
						if programStart do println("XFIT SYSLOG : vulkan present mode mailbox_khr vsync triple")
					}
					vkPresentMode = p
					break;
				}
			}
		}
		for p in vkPresentModes {
			if p == .IMMEDIATE {
				when is_log {
					if programStart {
						if __vSync == .Triple do println("XFIT SYSLOG : vulkan present mode immediate_khr mailbox_khr instead(vsync triple -> none)")
						else do println("XFIT SYSLOG : vulkan present mode immediate_khr vsync none")
					} 
				}
				vkPresentMode = p
				break;
			}
		}
	}
	programStart = false

	surfaceImgCnt := max(__swapImgCnt ,vkSurfaceCap.minImageCount)
	if vkSurfaceCap.maxImageCount > 0 && surfaceImgCnt > vkSurfaceCap.maxImageCount {//0 is no limit max+
		surfaceImgCnt = vkSurfaceCap.maxImageCount
	}
	__swapImgCnt = surfaceImgCnt

	if .OPAQUE in vkSurfaceCap.supportedCompositeAlpha {
		vkSurfaceCap.supportedCompositeAlpha = {.OPAQUE}
	} else if .INHERIT in vkSurfaceCap.supportedCompositeAlpha {
		vkSurfaceCap.supportedCompositeAlpha = {.INHERIT}
	} else if .PRE_MULTIPLIED in vkSurfaceCap.supportedCompositeAlpha {
		vkSurfaceCap.supportedCompositeAlpha = {.PRE_MULTIPLIED}
	} else if .POST_MULTIPLIED in vkSurfaceCap.supportedCompositeAlpha {
		vkSurfaceCap.supportedCompositeAlpha = {.POST_MULTIPLIED}
	} else {
		trace.panic_log("not supports supportedCompositeAlpha")
	}

	swapChainCreateInfo := vk.SwapchainCreateInfoKHR{
		sType = vk.StructureType.SWAPCHAIN_CREATE_INFO_KHR,
		minImageCount = __swapImgCnt,
		imageFormat = vkFmt.format,
		imageColorSpace = vkFmt.colorSpace,
		imageExtent = vkExtent_rotation,
		imageArrayLayers = 1,
		imageUsage = {.COLOR_ATTACHMENT},
		presentMode = vkPresentMode,
		preTransform = vkSurfaceCap.currentTransform,
		compositeAlpha = vkSurfaceCap.supportedCompositeAlpha,
		clipped = true,
		oldSwapchain = 0,
		imageSharingMode = .EXCLUSIVE,
		pNext = nil,
		queueFamilyIndexCount = 0,
		surface = vkSurface
	}
	when ODIN_OS == .Windows {
		if __isFullScreenEx && VK_EXT_full_screen_exclusive_support() {
			fullScreenWinInfo : vk.SurfaceFullScreenExclusiveWin32InfoEXT
			fullScreenInfo := vk.SurfaceFullScreenExclusiveInfoEXT{
				sType = vk.StructureType.SURFACE_FULL_SCREEN_EXCLUSIVE_INFO_EXT,
				pNext = nil,
				fullScreenExclusive = .APPLICATION_CONTROLLED,
			}
			if currentMonitor != nil {
				fullScreenWinInfo = vk.SurfaceFullScreenExclusiveWin32InfoEXT{
					sType = vk.StructureType.SURFACE_FULL_SCREEN_EXCLUSIVE_WIN32_INFO_EXT,
					pNext = nil,
					hmonitor = glfwGetCurrentHMONITOR(),
				}
				fullScreenInfo.pNext = &fullScreenWinInfo
			}
			swapChainCreateInfo.pNext = &fullScreenInfo
		}
	}
	queueFamiliesIndices := [2]u32{vkGraphicsFamilyIndex, vkPresentFamilyIndex}
	if vkGraphicsFamilyIndex != vkPresentFamilyIndex {
		swapChainCreateInfo.imageSharingMode = .CONCURRENT
		swapChainCreateInfo.queueFamilyIndexCount = 2
		swapChainCreateInfo.pQueueFamilyIndices = raw_data(queueFamiliesIndices[:])
	}

	res := vk.CreateSwapchainKHR(vkDevice, &swapChainCreateInfo, nil, &vkSwapchain)
	if res != .SUCCESS {
		return false
	}

	vk.GetSwapchainImagesKHR(vkDevice, vkSwapchain, &__swapImgCnt, nil)
	swapImgs:= mem.make_non_zeroed([]vk.Image, __swapImgCnt, context.temp_allocator)
	defer delete(swapImgs, context.temp_allocator)
	vk.GetSwapchainImagesKHR(vkDevice, vkSwapchain, &__swapImgCnt, &swapImgs[0])

	vkFrameBuffers = mem.make_non_zeroed([]vk.Framebuffer, __swapImgCnt)
	//vkClearFrameBuffers = mem.make_non_zeroed([]vk.Framebuffer, __swapImgCnt)
	vkFrameBufferImageViews = mem.make_non_zeroed([]vk.ImageView, __swapImgCnt)
	
	Texture_InitDepthStencil(&vkFrameDepthStencilTexture, vkExtent_rotation.width, vkExtent_rotation.height)
	when vkMSAACount > 1 {
		Texture_InitMSAA(&vkMSAAFrameTexture, vkExtent_rotation.width, vkExtent_rotation.height)
	}

	vkRefreshPreMatrix()
	vkOpExecute(true)

	for img, i in swapImgs {
		imageViewCreateInfo := vk.ImageViewCreateInfo{
			sType = vk.StructureType.IMAGE_VIEW_CREATE_INFO,
			image = img,
			viewType = .D2,
			format = vkFmt.format,
			components = {
				r = .IDENTITY,
				g = .IDENTITY,
				b = .IDENTITY,
				a = .IDENTITY,
			},
			subresourceRange = {
				aspectMask = {.COLOR},
				baseMipLevel = 0,
				levelCount = 1,
				baseArrayLayer = 0,
				layerCount = 1,
			},
		}
		res = vk.CreateImageView(vkDevice, &imageViewCreateInfo, nil, &vkFrameBufferImageViews[i])
		if res != .SUCCESS do trace.panic_log("res = vk.CreateImageView(vkDevice, &imageViewCreateInfo, nil, &vkFrameBufferImageViews[i]) : ", res)

		when vkMSAACount == 1 {
			frameBufferCreateInfo := vk.FramebufferCreateInfo{
				sType = vk.StructureType.FRAMEBUFFER_CREATE_INFO,
				renderPass = vkRenderPass,
				attachmentCount = 2,
				pAttachments = &([]vk.ImageView{vkFrameBufferImageViews[i], vkFrameDepthStencilTexture.texture.imgView, })[0],
				width = vkExtent_rotation.width,
				height = vkExtent_rotation.height,
				layers = 1,
			}
		} else {
			frameBufferCreateInfo := vk.FramebufferCreateInfo{
				sType = vk.StructureType.FRAMEBUFFER_CREATE_INFO,
				renderPass = vkRenderPass,
				attachmentCount = 3,
				pAttachments = &([]vk.ImageView{vkMSAAFrameTexture.texture.imgView, vkFrameDepthStencilTexture.texture.imgView, vkFrameBufferImageViews[i]})[0],
				width = vkExtent_rotation.width,
				height = vkExtent_rotation.height,
				layers = 1,
			}
		}
		res = vk.CreateFramebuffer(vkDevice, &frameBufferCreateInfo, nil, &vkFrameBuffers[i])
		if res != .SUCCESS do trace.panic_log("res = vk.CreateFramebuffer(vkDevice, &frameBufferCreateInfo, nil, &vkFrameBuffers[i]) : ", res)

		// frameBufferCreateInfo.renderPass = vkRenderPassClear
		// res = vk.CreateFramebuffer(vkDevice, &frameBufferCreateInfo, nil, &vkClearFrameBuffers[i])
		// if res != .SUCCESS do trace.panic_log("res = vk.CreateFramebuffer(vkDevice, &frameBufferCreateInfo, nil, &vkClearFrameBuffers[i]) : ", res)
	}

	return true
} 

vkStart :: proc() {
	ok: bool
	when ODIN_OS == .Windows {
		vkLibrary, ok = dynlib.load_library("vulkan-1.dll")
		if !ok do trace.panic_log(" vkLibrary, ok = dynlib.load_library(\"vulkan-1.dll\")")
	} else {
		vkLibrary, ok = dynlib.load_library("libvulkan.so.1")
		if !ok {
			vkLibrary, ok = dynlib.load_library("libvulkan.so")
			if !ok do trace.panic_log(" vkLibrary, ok = dynlib.load_library(\"libvulkan.so\")")
		}
	}
	rawFunc: rawptr
	rawFunc, ok = dynlib.symbol_address(vkLibrary, "vkGetInstanceProcAddr")
	if !ok do trace.panic_log("rawFunc, ok = dynlib.symbol_address(vkLibrary, \"vkGetInstanceProcAddr\")")
	vkGetInstanceProcAddr = auto_cast rawFunc
	vk.load_proc_addresses_global(rawFunc)

	appInfo := vk.ApplicationInfo {
		apiVersion         = vk.API_VERSION_1_4,
		engineVersion      = vk.MAKE_VERSION(1, 0, 0),
		applicationVersion = vk.MAKE_VERSION(1, 0, 0),
		pEngineName        = "Xfit",
		pApplicationName   = ODIN_BUILD_PROJECT_NAME,
	}
	GetInstanceProcAddr := vk.GetInstanceProcAddr(nil, "vkEnumerateInstanceVersion")
	if GetInstanceProcAddr == nil {
		when is_log do println("XFIT SYSLOG : vulkan 1.0 device, set api version 1.0")
		appInfo.apiVersion = vk.API_VERSION_1_0
	}
	glfwLen := 0
	glfwExtensions : []cstring
	when !is_mobile {
		glfwExtensions = glfw.GetRequiredInstanceExtensions()
		glfwLen = len(glfwExtensions)
	}
	instanceExtNames :[dynamic]cstring = mem.make_non_zeroed([dynamic]cstring,  context.temp_allocator)
	defer delete(instanceExtNames)
	layerNames := mem.make_non_zeroed([dynamic]cstring, 0, len(LAYERS), context.temp_allocator)
	defer delete(layerNames)

	non_zero_append(&instanceExtNames, vk.KHR_SURFACE_EXTENSION_NAME)

	layerPropCnt: u32
	vk.EnumerateInstanceLayerProperties(&layerPropCnt, nil)

	if layerPropCnt > 0 {
		availableLayers := mem.make_non_zeroed([]vk.LayerProperties, layerPropCnt, context.temp_allocator)
		defer delete(availableLayers, context.temp_allocator)

		vk.EnumerateInstanceLayerProperties(&layerPropCnt, &availableLayers[0])

		for &l in availableLayers {
			for _, i in LAYERS {
				if !LAYERS_CHECK[i] && mem.compare((transmute([^]byte)LAYERS[i])[:len(LAYERS[i])], l.layerName[:len(LAYERS[i])]) == 0 {
					when !ODIN_DEBUG {
						if LAYERS[i] == "VK_LAYER_KHRONOS_validation" do continue
					}
					non_zero_append(&layerNames, LAYERS[i])
					LAYERS_CHECK[i] = true
					when is_log do printfln(
						"XFIT SYSLOG : vulkan %s instance layer support",
						LAYERS[i],
					)
				}
			}
		}
	}

	instanceExtCnt: u32
	vk.EnumerateInstanceExtensionProperties(nil, &instanceExtCnt, nil)

	availableInstanceExts := mem.make_non_zeroed([]vk.ExtensionProperties, instanceExtCnt, context.temp_allocator)
	defer delete(availableInstanceExts, context.temp_allocator)

	vk.EnumerateInstanceExtensionProperties(nil, &instanceExtCnt, &availableInstanceExts[0])

	for &e in availableInstanceExts {
		for _, i in INSTANCE_EXTENSIONS {
			if !INSTANCE_EXTENSIONS_CHECK[i] &&
			   mem.compare((transmute([^]byte)INSTANCE_EXTENSIONS[i])[:len(INSTANCE_EXTENSIONS[i])], e.extensionName[:len(INSTANCE_EXTENSIONS[i])]) == 0 {
				non_zero_append(&instanceExtNames, INSTANCE_EXTENSIONS[i])
				INSTANCE_EXTENSIONS_CHECK[i] = true
				when is_log do printfln(
					"XFIT SYSLOG : vulkan %s instance ext support",
					INSTANCE_EXTENSIONS[i],
				)
			}
		}
	}
	if validation_layer_support() {
		non_zero_append(&instanceExtNames, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)

		when is_log do println("XFIT SYSLOG : vulkan validation layer enable")
	} else {
		when is_log do println("XFIT SYSLOG : vulkan validation layer disable")
	}

	when is_android {
		non_zero_append(&instanceExtNames, "VK_KHR_android_surface")
	} else {
	}

	when !is_mobile {
		insLen := len(instanceExtNames)
		con: for &glfw in glfwExtensions {
			for &ext in instanceExtNames[:insLen] {
				if strings.compare(string(glfw), string(ext)) == 0 do continue con
			}
			non_zero_append(&instanceExtNames, glfw)
		}
	}

	instanceCreateInfo := vk.InstanceCreateInfo {
		sType                   = vk.StructureType.INSTANCE_CREATE_INFO,
		pApplicationInfo        = &appInfo,
		enabledLayerCount       = auto_cast len(layerNames),
		ppEnabledLayerNames     = &layerNames[0] if len(layerNames) > 0 else nil,
		enabledExtensionCount   = auto_cast len(instanceExtNames),
		ppEnabledExtensionNames = &instanceExtNames[0],
		pNext                   = nil,
		flags                   = vk.InstanceCreateFlags{.ENUMERATE_PORTABILITY_KHR} if VK_KHR_portability_enumeration_support() else vk.InstanceCreateFlags{},
	}

	res := vk.CreateInstance(&instanceCreateInfo, nil, &vkInstance)
	if (res != vk.Result.SUCCESS) do trace.panic_log("vk.CreateInstance(&instanceCreateInfo, nil, &vkInstance) : ", res)

	vk.load_proc_addresses_instance(vkInstance)

	if validation_layer_support() && ODIN_DEBUG {
		debugUtilsCreateInfo := vk.DebugUtilsMessengerCreateInfoEXT {
			sType = vk.StructureType.DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
			messageSeverity = vk.DebugUtilsMessageSeverityFlagsEXT{.ERROR, .VERBOSE, .WARNING},
			messageType     = vk.DebugUtilsMessageTypeFlagsEXT {.GENERAL, .VALIDATION, .PERFORMANCE},
			pfnUserCallback = vkDebugCallBack,
			pUserData       = nil,
		}
		vk.CreateDebugUtilsMessengerEXT(
			vkInstance,
			&debugUtilsCreateInfo,
			nil,
			&vkDebugUtilsMessenger,
		)
	}

	vkCreateSurface()

	physicalDeviceCnt: u32
	vk.EnumeratePhysicalDevices(vkInstance, &physicalDeviceCnt, nil)
	vkPhysicalDevices := mem.make_non_zeroed([]vk.PhysicalDevice, physicalDeviceCnt, context.temp_allocator)
	defer delete(vkPhysicalDevices, context.temp_allocator)
	vk.EnumeratePhysicalDevices(vkInstance, &physicalDeviceCnt, &vkPhysicalDevices[0])

	out: for pd in vkPhysicalDevices {
		queueFamilyPropCnt: u32
		vk.GetPhysicalDeviceQueueFamilyProperties(pd, &queueFamilyPropCnt, nil)
		queueFamilies := mem.make_non_zeroed([]vk.QueueFamilyProperties, queueFamilyPropCnt, context.temp_allocator)
		defer delete(queueFamilies, context.temp_allocator)
		vk.GetPhysicalDeviceQueueFamilyProperties(pd, &queueFamilyPropCnt, &queueFamilies[0])

		for i in 0 ..< queueFamilyPropCnt {
			if .GRAPHICS in queueFamilies[i].queueFlags do vkGraphicsFamilyIndex = i
			
			isPresentSupport: b32
			vk.GetPhysicalDeviceSurfaceSupportKHR(pd, i, vkSurface, &isPresentSupport)

			if isPresentSupport do vkPresentFamilyIndex = i
			if vkGraphicsFamilyIndex != max(u32) && vkPresentFamilyIndex != max(u32) {
				vkPhysicalDevice = pd
				break out
			}
		}
	}
	queuePriorty: [1]f32 = {1}
	deviceQueueCreateInfos := [2]vk.DeviceQueueCreateInfo {
		vk.DeviceQueueCreateInfo {
			sType = vk.StructureType.DEVICE_QUEUE_CREATE_INFO,
			queueCount = 1,
			queueFamilyIndex = vkGraphicsFamilyIndex,
			pQueuePriorities = &queuePriorty[0],
		},
		vk.DeviceQueueCreateInfo {
			sType = vk.StructureType.DEVICE_QUEUE_CREATE_INFO,
			queueCount = 1,
			queueFamilyIndex = vkPresentFamilyIndex,
			pQueuePriorities = &queuePriorty[0],
		},
	}
	queueCnt: u32 = 1 if vkGraphicsFamilyIndex == vkPresentFamilyIndex else 2

	when vkWIREMODE {
		physicalDeviceFeatures := vk.PhysicalDeviceFeatures {
			samplerAnisotropy = true,
			sampleRateShading = true, //FOR ANTI-ALISING
			fillModeNonSolid = true,
			//geometryShader = true,
		}
	} else {
		physicalDeviceFeatures := vk.PhysicalDeviceFeatures {
			samplerAnisotropy = true,
			sampleRateShading = true, //FOR ANTI-ALISING
			//geometryShader = true,
		}
	}

	deviceExtCnt: u32
	vk.EnumerateDeviceExtensionProperties(vkPhysicalDevice, nil, &deviceExtCnt, nil)
	deviceExts := mem.make_non_zeroed([]vk.ExtensionProperties, deviceExtCnt, context.temp_allocator)
	defer delete(deviceExts, context.temp_allocator)
	vk.EnumerateDeviceExtensionProperties(vkPhysicalDevice, nil, &deviceExtCnt, &deviceExts[0])

	deviceExtNames := mem.make_non_zeroed([dynamic]cstring, 0, len(DEVICE_EXTENSIONS) + 1, context.temp_allocator)
	defer delete(deviceExtNames)
	non_zero_append(&deviceExtNames, vk.KHR_SWAPCHAIN_EXTENSION_NAME)

	for &e in deviceExts {
		for _, i in DEVICE_EXTENSIONS {
			if !DEVICE_EXTENSIONS_CHECK[i] &&
			   mem.compare((transmute([^]byte)DEVICE_EXTENSIONS[i])[:len(DEVICE_EXTENSIONS[i])],e.extensionName[:len(DEVICE_EXTENSIONS[i])]) == 0 {
				non_zero_append(&deviceExtNames, DEVICE_EXTENSIONS[i])
				DEVICE_EXTENSIONS_CHECK[i] = true
				when is_log do printfln(
					"XFIT SYSLOG : vulkan %s device ext support",
					DEVICE_EXTENSIONS[i],
				)
			}
		}
	}

	deviceCreateInfo := vk.DeviceCreateInfo {
		sType                   = vk.StructureType.DEVICE_CREATE_INFO,
		pQueueCreateInfos       = &deviceQueueCreateInfos[0],
		queueCreateInfoCount    = queueCnt,
		pEnabledFeatures        = &physicalDeviceFeatures,
		ppEnabledExtensionNames = &deviceExtNames[0],
		enabledExtensionCount   = auto_cast len(deviceExtNames),
	}
	res = vk.CreateDevice(vkPhysicalDevice, &deviceCreateInfo, nil, &vkDevice)
	if (res != vk.Result.SUCCESS) do trace.panic_log("res = vk.CreateDevice(vkPhysicalDevice, &deviceCreateInfo, nil, &vkDevice) : ", res)
	vk.load_proc_addresses_device(vkDevice)

	vk.GetPhysicalDeviceMemoryProperties(vkPhysicalDevice, &vkPhysicalMemProp)
	vk.GetPhysicalDeviceProperties(vkPhysicalDevice, &vkPhysicalProp)

	if vkGraphicsFamilyIndex == vkPresentFamilyIndex {
		vk.GetDeviceQueue(vkDevice, vkGraphicsFamilyIndex, 0, &vkGraphicsQueue)
		vkPresentQueue = vkGraphicsQueue
	} else {
		vk.GetDeviceQueue(vkDevice, vkGraphicsFamilyIndex, 0, &vkGraphicsQueue)
		vk.GetDeviceQueue(vkDevice, vkPresentFamilyIndex, 0, &vkPresentQueue)
	}

	res = vk.CreateCommandPool(vkDevice, &vk.CommandPoolCreateInfo{
		sType = vk.StructureType.COMMAND_POOL_CREATE_INFO,
		flags = vk.CommandPoolCreateFlags{.RESET_COMMAND_BUFFER},
		queueFamilyIndex = vkGraphicsFamilyIndex,
	}, nil, &vkCmdPool)
	if res != .SUCCESS do trace.panic_log("vk.CreateCommandPool(&vkCmdPool) : ", res)

	res = vk.AllocateCommandBuffers(vkDevice, &vk.CommandBufferAllocateInfo{
		sType = vk.StructureType.COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool = vkCmdPool,
		level = vk.CommandBufferLevel.PRIMARY,
		commandBufferCount = MAX_FRAMES_IN_FLIGHT,
	}, &vkCmdBuffer[0])
	if res != .SUCCESS do trace.panic_log("vk.AllocateCommandBuffers(&vkCmdBuffer) : ", res)

	RenderCmd_Create()

	vkInitBlockLen()
	vkAllocatorInit()

	Graphics_Create()

	initSwapChain()

	samplerInfo := vk.SamplerCreateInfo {
		sType                   = vk.StructureType.SAMPLER_CREATE_INFO,
		addressModeU            = .REPEAT,
		addressModeV            = .REPEAT,
		addressModeW            = .REPEAT,
		mipmapMode              = .LINEAR,
		magFilter               = .LINEAR,
		minFilter               = .LINEAR,
		mipLodBias              = 0,
		compareOp               = .ALWAYS,
		compareEnable           = false,
		unnormalizedCoordinates = false,
		minLod                  = 0,
		maxLod                  = 0,
		anisotropyEnable        = false,
		maxAnisotropy           = vkPhysicalProp.limits.maxSamplerAnisotropy,
		borderColor             = .INT_OPAQUE_WHITE,
	}
	vk.CreateSampler(vkDevice, &samplerInfo, nil, &vkLinearSampler)
	samplerInfo.mipmapMode = .NEAREST
	samplerInfo.magFilter = .NEAREST
	samplerInfo.minFilter = .NEAREST
	vk.CreateSampler(vkDevice, &samplerInfo, nil, &vkNearestSampler)

	vkDepthFmt := TextureFmtToVkFmt(__depthFmt)
	depthAttachmentSample := vk.AttachmentDescriptionInit(
		format = vkDepthFmt,
		loadOp = .CLEAR,
		storeOp = .STORE,
		initialLayout = .UNDEFINED,
		finalLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
		samples = vkSampleCountFlags,
	)
	// depthAttachmentSampleClear := vk.AttachmentDescriptionInit(
	// 	format = vkDepthFmt,
	// 	loadOp = .CLEAR,
	// 	storeOp = .STORE,
	// 	finalLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
	// 	samples = vkSampleCountFlags,
	// )
	// colorAttachmentSampleClear := vk.AttachmentDescriptionInit(
	// 	format = vkFmt.format,
	// 	loadOp = .CLEAR,
	// 	storeOp = .STORE,
	// 	finalLayout = .COLOR_ATTACHMENT_OPTIMAL,
	// 	samples = vkSampleCountFlags,
	// )
	colorAttachmentSample := vk.AttachmentDescriptionInit(
		format = vkFmt.format,
		loadOp = .CLEAR,
		storeOp = .STORE,
		initialLayout = .UNDEFINED,
		finalLayout = .COLOR_ATTACHMENT_OPTIMAL,
		samples = vkSampleCountFlags,
	)
	colorAttachmentResolve := vk.AttachmentDescriptionInit(
		format = vkFmt.format,
		storeOp = .STORE,
		finalLayout = .PRESENT_SRC_KHR,
	)

	colorAttachmentLoadResolve := vk.AttachmentDescriptionInit(
		format = vkFmt.format,
		loadOp = .LOAD,
		initialLayout = .COLOR_ATTACHMENT_OPTIMAL,
		finalLayout = .COLOR_ATTACHMENT_OPTIMAL,
	)
	// colorAttachmentClear := vk.AttachmentDescriptionInit(
	// 	format = vkFmt.format,
	// 	loadOp = .CLEAR,
	// 	storeOp = .STORE,
	// 	finalLayout = .PRESENT_SRC_KHR,
	// )
	// depthAttachmentClear := vk.AttachmentDescriptionInit(
	// 	format = vkDepthFmt,
	// 	loadOp = .CLEAR,
	// 	storeOp = .STORE,
	// 	finalLayout = .PRESENT_SRC_KHR,
	// )
	colorAttachment := vk.AttachmentDescriptionInit(
		format = vkFmt.format,
		loadOp = .CLEAR,
		storeOp = .STORE,
		finalLayout = .PRESENT_SRC_KHR,
	)
	depthAttachment := vk.AttachmentDescriptionInit(
		format = vkDepthFmt,
		loadOp = .CLEAR,
		storeOp = .STORE,
		finalLayout = .PRESENT_SRC_KHR,
	)
	shapeBackAttachment := vk.AttachmentDescriptionInit(
		format = .R8_UNORM,
		loadOp = .CLEAR,
		storeOp = .DONT_CARE,
		finalLayout = .GENERAL,
		initialLayout = .GENERAL,
	)

	colorAttachmentRef := vk.AttachmentReference {
		attachment = 0,
		layout     = .COLOR_ATTACHMENT_OPTIMAL,
	}
	colorResolveAttachmentRef := vk.AttachmentReference {
		attachment = 2,
		layout     = .COLOR_ATTACHMENT_OPTIMAL,
	}
	depthAttachmentRef := vk.AttachmentReference {
		attachment = 1,
		layout     = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
	}
	inputAttachmentRef := vk.AttachmentReference {
		attachment = 1,
		layout     = .SHADER_READ_ONLY_OPTIMAL,
	}


	subpassDesc := vk.SubpassDescription {
		pipelineBindPoint       = .GRAPHICS,
		colorAttachmentCount    = 1,
		pColorAttachments       = &colorAttachmentRef,
		pDepthStencilAttachment = &depthAttachmentRef,
	}
	subpassResolveDesc := vk.SubpassDescription {
		pipelineBindPoint       = .GRAPHICS,
		colorAttachmentCount    = 1,
		pColorAttachments       = &colorAttachmentRef,
		pDepthStencilAttachment = &depthAttachmentRef,
		pResolveAttachments = &colorResolveAttachmentRef,
	}
	subpassCopyDesc := vk.SubpassDescription {
		pipelineBindPoint    = .GRAPHICS,
		colorAttachmentCount = 1,
		inputAttachmentCount = 1,
		pColorAttachments    = &colorAttachmentRef,
		pInputAttachments    = &inputAttachmentRef,
	}

	subpassDependency := vk.SubpassDependency {
		srcSubpass    = vk.SUBPASS_EXTERNAL,
		dstSubpass    = 0,
		srcStageMask  = {.COLOR_ATTACHMENT_OUTPUT, .EARLY_FRAGMENT_TESTS},
		srcAccessMask = {},
		dstStageMask  = {.COLOR_ATTACHMENT_OUTPUT, .EARLY_FRAGMENT_TESTS},
		dstAccessMask = {.COLOR_ATTACHMENT_WRITE, .DEPTH_STENCIL_ATTACHMENT_WRITE},
	}
	subpassDependencyCopy := vk.SubpassDependency {
		srcSubpass    = vk.SUBPASS_EXTERNAL,
		dstSubpass    = 0,
		srcStageMask  = {.COLOR_ATTACHMENT_OUTPUT},
		srcAccessMask = {},
		dstStageMask  = {.COLOR_ATTACHMENT_OUTPUT},
		dstAccessMask = {.COLOR_ATTACHMENT_WRITE},
	}

	when vkMSAACount == 1 {
		renderPassInfo := vk.RenderPassCreateInfoInit(
			pAttachments = []vk.AttachmentDescription{colorAttachment, depthAttachment},
			pSubpasses = []vk.SubpassDescription{subpassDesc},
			pDependencies = []vk.SubpassDependency{subpassDependency},
		)
	} else {
		renderPassInfo := vk.RenderPassCreateInfoInit(
			pAttachments = []vk.AttachmentDescription{colorAttachmentSample, depthAttachmentSample, colorAttachmentResolve},
			pSubpasses = []vk.SubpassDescription{subpassResolveDesc},
			pDependencies = []vk.SubpassDependency{subpassDependency},
		)
	}
	
	vk.CreateRenderPass(vkDevice, &renderPassInfo, nil, &vkRenderPass)


	// renderPassClearInfo := vk.RenderPassCreateInfoInit(
	// 	pAttachments = []vk.AttachmentDescription{colorAttachmentClear, depthAttachmentClear},
	// 	pSubpasses = []vk.SubpassDescription{subpassDesc},
	// 	pDependencies = []vk.SubpassDependency{subpassDependency},
	// )
	// vk.CreateRenderPass(vkDevice, &renderPassClearInfo, nil, &vkRenderPassClear)

	//TODO (xfitgd)
	renderPassCopyInfo := vk.RenderPassCreateInfoInit(
		pAttachments = []vk.AttachmentDescription{colorAttachment, colorAttachmentLoadResolve},
		pSubpasses = []vk.SubpassDescription{subpassCopyDesc},
		pDependencies = []vk.SubpassDependency{subpassDependencyCopy},
	)
	vk.CreateRenderPass(vkDevice, &renderPassCopyInfo, nil, &vkRenderPassCopy)


	vkInitShaderModules()

	vkInitPipelines()

	vkCreateSwapChainAndImageViews()
	vkCreateSyncObject()

	vkWaitAllOp()//reset wait
}

vkDestory :: proc() {
	Graphics_Clean()

	vkCleanSyncObject()
	vkCleanSwapChain()
	vkCleanPipelines()
	vkCleanShaderModules()

	vkAllocatorDestroy()

	vk.DestroyCommandPool(vkDevice, vkCmdPool, nil)

	vk.DestroySampler(vkDevice, vkLinearSampler, nil)
	vk.DestroySampler(vkDevice, vkNearestSampler, nil)

	vk.DestroyRenderPass(vkDevice, vkRenderPass, nil)
	vk.DestroyRenderPass(vkDevice, vkRenderPassCopy, nil)
	// vk.DestroyRenderPass(vkDevice, vkRenderPassClear, nil)

	delete(vkFmts)
	delete(vkPresentModes)
	RenderCmd_Clean()

	vk.DestroySurfaceKHR(vkInstance, vkSurface, nil)

	vk.DestroyDevice(vkDevice, nil)
	when ODIN_DEBUG {
		if vkDebugUtilsMessenger != 0 {
			vk.DestroyDebugUtilsMessengerEXT(vkInstance, vkDebugUtilsMessenger, nil)
		}
	}

	vk.DestroyInstance(vkInstance, nil)

	dynlib.unload_library(vkLibrary)
}

vkWaitDeviceIdle :: proc "contextless" () {
	res := vk.DeviceWaitIdle(vkDevice)
	if res != .SUCCESS do trace.panic_log("vkWaitDeviceIdle : ", res )
}

vkWaitGraphicsIdle :: proc "contextless" () {
	res := vk.QueueWaitIdle(vkGraphicsQueue)
	if res != .SUCCESS do trace.panic_log("vkWaitGraphicsIdle : ", res )
}

vkWaitPresentIdle :: proc "contextless" () {
	res := vk.QueueWaitIdle(vkPresentQueue)
	if res != .SUCCESS do trace.panic_log("vkWaitPresentIdle : ", res )
}

vkRecreateSwapChain :: proc() {
	if vkDevice == nil || vkSwapchain == 0 {
		return
	}
	sync.mutex_lock(&fullScreenMtx)

	vkReleaseFullScreenEx()

	vkWaitDeviceIdle()

	when is_android {//? ANDROID ONLY
		vulkanAndroidStart()
	}

	//vkCleanSyncObject()
	vkCleanSwapChain()

	if !vkCreateSwapChainAndImageViews() {
		sync.mutex_unlock(&fullScreenMtx)
		return
	}
	//vkCreateSyncObject()

	vkSetFullScreenEx()

	sizeUpdated = false

	sync.mutex_unlock(&fullScreenMtx)

	RenderCmd_RefreshAll()

	Size()
	if gMainRenderCmdIdx >= 0 {
		for obj in gRenderCmd[gMainRenderCmdIdx].scene {
			IObject_Size(obj)
		}
	}
}
vkCreateSurface :: vkRecreateSurface

vkSetFullScreenEx :: proc() {
	when ODIN_OS == .Windows {
		if VK_EXT_full_screen_exclusive_support() && __isFullScreenEx {
			res := vk.AcquireFullScreenExclusiveModeEXT(vkDevice, vkSwapchain)
			if res != .SUCCESS do trace.panic_log("AcquireFullScreenExclusiveModeEXT : ", res)
			vkReleasedFullScreenEx = false
		}
	}
}

vkReleaseFullScreenEx :: proc() {
	when ODIN_OS == .Windows {
		if VK_EXT_full_screen_exclusive_support() && !vkReleasedFullScreenEx {
			res := vk.ReleaseFullScreenExclusiveModeEXT(vkDevice, vkSwapchain)
			if res != .SUCCESS do trace.panic_log("ReleaseFullScreenExclusiveModeEXT : ", res)
			vkReleasedFullScreenEx = true
		}
	}
}

vkRecreateSurface :: proc() {
	when is_android {
		vulkanAndroidStart()
	} else {// !ismobile
		glfwVulkanStart()
	}
}

vkRecordCommandBuffer :: proc(cmd:^__RenderCmd, frame:int) {
	clsColor :vk.ClearValue = {color = {float32 = gClearColor}}
	clsDepthStencil :vk.ClearValue = {depthStencil = {depth = 1.0, stencil = 0}}
	clsZero :vk.ClearValue = {depthStencil = {depth = 1.0, stencil = 0}}

	for &c, i in cmd.cmds[frame] {
		beginInfo := vk.CommandBufferBeginInfo {
			sType = vk.StructureType.COMMAND_BUFFER_BEGIN_INFO,
			flags = {},
		}
		res := vk.BeginCommandBuffer(c, &beginInfo)
		if res != .SUCCESS do trace.panic_log("BeginCommandBuffer : ", res)

		renderPassBeginInfo := vk.RenderPassBeginInfo {
			sType = vk.StructureType.RENDER_PASS_BEGIN_INFO,
			renderPass = vkRenderPass,
			framebuffer = vkFrameBuffers[i],
			renderArea = {
				offset = {x = 0, y = 0},
				extent = vkExtent_rotation,
			},
			clearValueCount = 2,
			pClearValues = &([]vk.ClearValue{clsColor, clsDepthStencil})[0],
		}

		vk.CmdBeginRenderPass(c, &renderPassBeginInfo, vk.SubpassContents.INLINE)
		
		viewport := vk.Viewport {
			x = 0.0,
			y = 0.0,
			width = f32(vkExtent_rotation.width),
			height = f32(vkExtent_rotation.height),
			minDepth = 0.0,
			maxDepth = 1.0,
		}
		vk.CmdSetViewport(c, 0, 1, &viewport)

		scissor := vk.Rect2D {
			offset = {x = 0, y = 0},
			extent = vkExtent_rotation,
		}
		vk.CmdSetScissor(c, 0, 1, &scissor)

		sync.rw_mutex_lock(&cmd.objLock)
		objs := mem.make_non_zeroed_slice([]^IObject, len(cmd.scene), context.temp_allocator)
		copy_slice(objs, cmd.scene[:])
		sync.rw_mutex_unlock(&cmd.objLock)
		defer delete(objs, context.temp_allocator)
		
		for obj in objs {
			IObject_Draw(obj, c)
		}

		vk.CmdEndRenderPass(c)
		res = vk.EndCommandBuffer(c)
		if res != .SUCCESS do trace.panic_log("EndCommandBuffer : ", res)
	}
}

vkDrawFrame :: proc() {
	@(static) frame:int = 0

	vkOpExecute(true)

	if vkSwapchain == 0 do return
	if vkExtent.width <= 0 || vkExtent.height <= 0 {
		vkRecreateSwapChain()
		frame = 0
		return
	}

	res := vk.WaitForFences(vkDevice, 1, &vkInFlightFence[frame], true, max(u64))
	if res != .SUCCESS do trace.panic_log("WaitForFences : ", res)


	imageIndex: u32
	res = vk.AcquireNextImageKHR(vkDevice, vkSwapchain, max(u64), vkImageAvailableSemaphore[frame], 0, &imageIndex)
	if res == .ERROR_OUT_OF_DATE_KHR {
		vkRecreateSwapChain()
		frame = 0
		return
	} else if res == .ERROR_SURFACE_LOST_KHR {
		vkRecreateSurface()
		vkRecreateSwapChain()
		frame = 0
		return
	} else if res != .SUCCESS { trace.panic_log("AcquireNextImageKHR : ", res) }
	
	if gRenderCmd != nil && gMainRenderCmdIdx >= 0 {
		sync.mutex_lock(&gRenderCmdMtx)
		if gRenderCmd[gMainRenderCmdIdx].refresh[frame] {
			gRenderCmd[gMainRenderCmdIdx].refresh[frame] = false
			vkRecordCommandBuffer(gRenderCmd[gMainRenderCmdIdx], frame)
		}
		waitStages := vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT}
		submitInfo := vk.SubmitInfo {
			sType = vk.StructureType.SUBMIT_INFO,
			waitSemaphoreCount = 1,
			pWaitSemaphores = &vkImageAvailableSemaphore[frame],
			pWaitDstStageMask = &waitStages,
			commandBufferCount = 1,
			pCommandBuffers = &gRenderCmd[gMainRenderCmdIdx].cmds[frame][imageIndex],
			signalSemaphoreCount = 1,
			pSignalSemaphores = &vkRenderFinishedSemaphore[frame][imageIndex],
		}

		res = vk.ResetFences(vkDevice, 1, &vkInFlightFence[frame])
		if res != .SUCCESS do trace.panic_log("ResetFences : ", res)

		res = vk.QueueSubmit(vkGraphicsQueue, 1, &submitInfo, vkInFlightFence[frame])
		if res != .SUCCESS do trace.panic_log("QueueSubmit : ", res)

		sync.mutex_unlock(&gRenderCmdMtx)
	} else {
		//?그릴 오브젝트가 없는 경우
		sync.mutex_lock(&gRenderCmdMtx)
		waitStages := vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT}

		clsColor :vk.ClearValue = {color = {float32 = gClearColor}}
		clsDepthStencil :vk.ClearValue = {depthStencil = {depth = 1.0, stencil = 0}}

		renderPassBeginInfo := vk.RenderPassBeginInfo {
			sType = vk.StructureType.RENDER_PASS_BEGIN_INFO,
			renderPass = vkRenderPass,
			framebuffer = vkFrameBuffers[imageIndex],
			renderArea = {
				offset = {x = 0, y = 0},
				extent = vkExtent_rotation,	
			},
			clearValueCount = 2,
			pClearValues = &([]vk.ClearValue{clsColor, clsDepthStencil})[0],
		}
		vk.BeginCommandBuffer(vkCmdBuffer[frame], &vk.CommandBufferBeginInfo {
			sType = vk.StructureType.COMMAND_BUFFER_BEGIN_INFO,
			flags = {vk.CommandBufferUsageFlag.ONE_TIME_SUBMIT},
		})
		vk.CmdBeginRenderPass(vkCmdBuffer[frame], &renderPassBeginInfo, vk.SubpassContents.INLINE)
		vk.CmdEndRenderPass(vkCmdBuffer[frame])
		res = vk.EndCommandBuffer(vkCmdBuffer[frame])
		if res != .SUCCESS do trace.panic_log("EndCommandBuffer : ", res)

		submitInfo := vk.SubmitInfo {
			sType = vk.StructureType.SUBMIT_INFO,
			waitSemaphoreCount = 1,
			pWaitSemaphores = &vkImageAvailableSemaphore[frame],
			pWaitDstStageMask = &waitStages,
			commandBufferCount = 1,
			pCommandBuffers = &vkCmdBuffer[frame],
			signalSemaphoreCount = 1,
			pSignalSemaphores = &vkRenderFinishedSemaphore[frame][imageIndex],
		}

		res = vk.ResetFences(vkDevice, 1, &vkInFlightFence[frame])
		if res != .SUCCESS do trace.panic_log("ResetFences : ", res)

		res = vk.QueueSubmit(vkGraphicsQueue, 1, &submitInfo, 	vkInFlightFence[frame])
		if res != .SUCCESS do trace.panic_log("QueueSubmit : ", res)

		sync.mutex_unlock(&gRenderCmdMtx)
	}

	presentInfo := vk.PresentInfoKHR {
		sType = vk.StructureType.PRESENT_INFO_KHR,
		waitSemaphoreCount = 1,
		pWaitSemaphores = &vkRenderFinishedSemaphore[frame][imageIndex],
		swapchainCount = 1,
		pSwapchains = &vkSwapchain,
		pImageIndices = &imageIndex,
	}

	res = vk.QueuePresentKHR(vkPresentQueue, &presentInfo)

	if res == .ERROR_OUT_OF_DATE_KHR {
		vkRecreateSwapChain()
		frame = 0
		return
	} else if res == .SUBOPTIMAL_KHR {
		prop : vk.SurfaceCapabilitiesKHR
		res = 	vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(vkPhysicalDevice, vkSurface, &prop)
		if res != .SUCCESS do trace.panic_log("GetPhysicalDeviceSurfaceCapabilitiesKHR : ", res)
		if prop.currentExtent.width != vkExtent.width || prop.currentExtent.height != vkExtent.height {
			vkRecreateSwapChain()
			return
		}
	} else if res == .ERROR_SURFACE_LOST_KHR {
		vkRecreateSurface()
		vkRecreateSwapChain()
		frame = 0
		return
	} else if sizeUpdated {
		vkRecreateSwapChain()
		frame = 0
		return
	} else if res != .SUCCESS { trace.panic_log("QueuePresentKHR : ", res) }

	frame = (frame + 1) % MAX_FRAMES_IN_FLIGHT
}

vkRefreshPreMatrix :: proc() {
	if is_mobile {
		orientation := __screenOrientation
		if orientation == .Landscape90 {
			vkRotationMatrix = linalg.matrix4_rotate_f32(linalg.to_radians(f32(90.0)), {0, 0, 1})
		} else if orientation == .Landscape270 {
			vkRotationMatrix = linalg.matrix4_rotate_f32(linalg.to_radians(f32(270.0)), {0, 0, 1})
		} else if orientation == .Vertical180 {
			vkRotationMatrix = linalg.matrix4_rotate_f32(linalg.to_radians(f32(180.0)), {0, 0, 1})
		} else if orientation == .Vertical360 {
			vkRotationMatrix = linalg.identity_matrix(linalg.Matrix)
		} else {
			vkRotationMatrix = linalg.identity_matrix(linalg.Matrix)
		}
	}
}

vkCreateSyncObject :: proc() {
	for i in 0..<MAX_FRAMES_IN_FLIGHT {
		vk.CreateSemaphore(vkDevice, &vk.SemaphoreCreateInfo{
			sType = vk.StructureType.SEMAPHORE_CREATE_INFO,
		}, nil, &vkImageAvailableSemaphore[i])

		vkRenderFinishedSemaphore[i] = mem.make_non_zeroed([]vk.Semaphore, int(__swapImgCnt))
		for j in 0..<int(__swapImgCnt) {
			vk.CreateSemaphore(vkDevice, &vk.SemaphoreCreateInfo{
				sType = vk.StructureType.SEMAPHORE_CREATE_INFO,
			}, nil, &vkRenderFinishedSemaphore[i][j])
		}

		vk.CreateFence(vkDevice, &vk.FenceCreateInfo{
			sType = vk.StructureType.FENCE_CREATE_INFO,
			flags = {vk.FenceCreateFlag.SIGNALED},
		}, nil, &vkInFlightFence[i])
	}
}

vkCleanSyncObject :: proc() {
	for i in 0..<MAX_FRAMES_IN_FLIGHT {
		vk.DestroySemaphore(vkDevice, vkImageAvailableSemaphore[i], nil)
		for j in 0..<int(__swapImgCnt) {
			vk.DestroySemaphore(vkDevice, vkRenderFinishedSemaphore[i][j], nil)
		}
		delete(vkRenderFinishedSemaphore[i])
		vk.DestroyFence(vkDevice, vkInFlightFence[i], nil)
	}
}

vkCleanSwapChain :: proc() {
	if vkSwapchain != 0 {
		for _, i in vkFrameBuffers {
			vk.DestroyFramebuffer(vkDevice, vkFrameBuffers[i], nil)
			//vk.DestroyFramebuffer(vkDevice, vkClearFrameBuffers[i], nil)
			vk.DestroyImageView(vkDevice, vkFrameBufferImageViews[i], nil)
		}

		Texture_Deinit(&vkFrameDepthStencilTexture)
		when vkMSAACount > 1 {
			Texture_Deinit(&vkMSAAFrameTexture)
		}
		vkOpExecute(true)

		delete(vkFrameBuffers)
		//delete(vkClearFrameBuffers)
		delete(vkFrameBufferImageViews)

		vk.DestroySwapchainKHR(vkDevice, vkSwapchain, nil)
		vkSwapchain = 0
	}
}


vkTransitionImageLayout :: proc(cmd:vk.CommandBuffer, image:vk.Image, mipLevels:u32, arrayStart:u32, arrayLayers:u32, oldLayout:vk.ImageLayout, newLayout:vk.ImageLayout) {
	barrier := vk.ImageMemoryBarrier{
		sType = vk.StructureType.IMAGE_MEMORY_BARRIER,
		oldLayout = oldLayout,
		newLayout = newLayout,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image = image,
		subresourceRange = {
			aspectMask = {.COLOR},
			baseMipLevel = 0,
			levelCount = mipLevels,
			baseArrayLayer = arrayStart,
			layerCount = arrayLayers
		}
	}
	
	srcStage : vk.PipelineStageFlags
	dstStage : vk.PipelineStageFlags

	if oldLayout == .UNDEFINED && newLayout == .TRANSFER_DST_OPTIMAL {
		barrier.srcAccessMask = {}
		barrier.dstAccessMask = {.TRANSFER_WRITE}

		srcStage = {.TOP_OF_PIPE}
		dstStage = {.TRANSFER}
	} else if oldLayout == .TRANSFER_DST_OPTIMAL && newLayout == .SHADER_READ_ONLY_OPTIMAL {
		barrier.srcAccessMask = {.TRANSFER_WRITE}
		barrier.dstAccessMask = {.SHADER_READ}

		srcStage = {.TRANSFER}
		dstStage = {.FRAGMENT_SHADER}
	} else if oldLayout == .UNDEFINED && newLayout == .COLOR_ATTACHMENT_OPTIMAL {
		barrier.srcAccessMask = {}
		barrier.dstAccessMask = {.SHADER_READ}

		srcStage = {.TOP_OF_PIPE}
		dstStage = {.FRAGMENT_SHADER}
	} else if oldLayout == .UNDEFINED && newLayout == .GENERAL {
		barrier.srcAccessMask = {}
		barrier.dstAccessMask = {.SHADER_READ, .SHADER_WRITE}

		srcStage = {.TOP_OF_PIPE}
		dstStage = {.FRAGMENT_SHADER}
	} else {
		trace.panic_log("unsupported layout transition!", oldLayout, newLayout)
	}

	vk.CmdPipelineBarrier(cmd,
	srcStage,
	dstStage,
	{},
	0,
	nil,
	0,
	nil,
	1,
	&barrier)
}