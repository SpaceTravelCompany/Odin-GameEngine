#+private
package engine

import "base:library"
import "base:runtime"
import "core:debug/trace"
import "core:dynlib"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:reflect"
import "core:strings"
import "core:sync"
import "core:sys/windows"
import "core:thread"
import "core:engine/geometry"
import vk "vendor:vulkan"
import "vendor:glfw"

import "core:c"

@(rodata)
DEVICE_EXTENSIONS: [3]cstring = {vk.KHR_SWAPCHAIN_EXTENSION_NAME, vk.EXT_FULL_SCREEN_EXCLUSIVE_EXTENSION_NAME, vk.KHR_SHADER_CLOCK_EXTENSION_NAME}
@(rodata)
INSTANCE_EXTENSIONS: [2]cstring = {
	vk.KHR_GET_SURFACE_CAPABILITIES_2_EXTENSION_NAME,
	vk.KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME,
}
@(rodata)
LAYERS: [1]cstring = {"VK_LAYER_KHRONOS_validation"}


vk_device: vk.Device
vk_instance: vk.Instance
vk_library: dynlib.Library
vk_swapchain: vk.SwapchainKHR

vk_debug_utils_messenger: vk.DebugUtilsMessengerEXT

vk_surface: vk.SurfaceKHR

vk_physical_device: vk.PhysicalDevice
vk_physical_mem_prop: vk.PhysicalDeviceMemoryProperties
vk_physical_prop: vk.PhysicalDeviceProperties

vk_graphics_queue: vk.Queue
vk_present_queue: vk.Queue
vk_queue_mutex: sync.Mutex

vk_graphics_family_index: u32 = max(u32)
vk_present_family_index: u32 = max(u32)


vk_render_pass: vk.RenderPass
vk_render_pass_clear: vk.RenderPass
vk_render_pass_sample: vk.RenderPass
vk_render_pass_sample_clear: vk.RenderPass

vk_frame_buffers: []vk.Framebuffer
vk_frame_depth_stencil_texture: texture
vk_msaa_frame_texture: texture
// vk_clear_frame_buffers: []vk.Framebuffer


vk_frame_buffer_image_views: []vk.ImageView

vk_image_available_semaphore: [MAX_FRAMES_IN_FLIGHT]vk.Semaphore
vk_render_finished_semaphore: [MAX_FRAMES_IN_FLIGHT][]vk.Semaphore
vk_in_flight_fence: [MAX_FRAMES_IN_FLIGHT]vk.Fence

vk_get_instance_proc_addr: proc "system" (
	_instance: vk.Instance,
	_name: cstring,
) -> vk.ProcVoidFunction

DEVICE_EXTENSIONS_CHECK: [len(DEVICE_EXTENSIONS)]bool
INSTANCE_EXTENSIONS_CHECK: [len(INSTANCE_EXTENSIONS)]bool
LAYERS_CHECK: [len(LAYERS)]bool

vulkan_version : VULKAN_VERSION

vk_debug_callback :: proc "system" (
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
	fmt.println(pCallbackData.pMessage)

	return false
}

validation_layer_support :: #force_inline proc "contextless" () -> bool {return LAYERS_CHECK[0]}
vk_khr_portability_enumeration_support :: #force_inline proc "contextless" () -> bool {return INSTANCE_EXTENSIONS_CHECK[1]}
VK_EXT_full_screen_exclusive_support :: #force_inline proc "contextless" () -> bool {return DEVICE_EXTENSIONS_CHECK[1]}


vk_fmts:[]vk.SurfaceFormatKHR
vk_fmt:vk.SurfaceFormatKHR = {
	format = .UNDEFINED,
	colorSpace = .SRGB_NONLINEAR
}
vkPresentModes:[]vk.PresentModeKHR
vkPresentMode:vk.PresentModeKHR
vk_surface_cap:vk.SurfaceCapabilitiesKHR
vk_extent:vk.Extent2D
vk_extent_rotation:vk.Extent2D

vkDepthHasOptimal:=false
vkDepthHasTransferSrcOptimal:=false
vkDepthHasTransferDstOptimal:=false
vkDepthHasSampleOptimal:=false

vkColorHasAttachOptimal:=false
vkColorHasSampleOptimal:=false
vkColorHasTransferSrcOptimal:=false
vkColorHasTransferDstOptimal:=false

is_released_full_screen_ex := true


vk_cmd_pool:vk.CommandPool
vk_cmd_buffer:[MAX_FRAMES_IN_FLIGHT]vk.CommandBuffer

msaa_count :: 1//#config(MSAA_COUNT, 1)

when msaa_count == 4 {
	VK_SAMPLE_COUNT_FLAGS :: vk.SampleCountFlags{._4}
} else when msaa_count == 8 {
	VK_SAMPLE_COUNT_FLAGS :: vk.SampleCountFlags{._8}
} else when msaa_count == 1 {
	VK_SAMPLE_COUNT_FLAGS :: vk.SampleCountFlags{._1}
} else {
	#assert("invalid msaa_count")
}

when msaa_count == 1 {
	vkPipelineMultisampleStateCreateInfo := vk.PipelineMultisampleStateCreateInfoInit(VK_SAMPLE_COUNT_FLAGS, sampleShadingEnable = false, minSampleShading = 0.0)
} else {
	vkPipelineMultisampleStateCreateInfo := vk.PipelineMultisampleStateCreateInfoInit(VK_SAMPLE_COUNT_FLAGS, sampleShadingEnable = true, minSampleShading = 1.0)	
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

init_swap_chain :: proc() {
	fmtCnt:u32
	vk.GetPhysicalDeviceSurfaceFormatsKHR(vk_physical_device, vk_surface, &fmtCnt, nil)
	vk_fmts = mem.make_non_zeroed([]vk.SurfaceFormatKHR, fmtCnt)
	vk.GetPhysicalDeviceSurfaceFormatsKHR(vk_physical_device, vk_surface, &fmtCnt, raw_data(vk_fmts))

	presentModeCnt:u32
	vk.GetPhysicalDeviceSurfacePresentModesKHR(vk_physical_device, vk_surface, &presentModeCnt, nil)
	vkPresentModes = mem.make_non_zeroed([]vk.PresentModeKHR, presentModeCnt)
	vk.GetPhysicalDeviceSurfacePresentModesKHR(vk_physical_device, vk_surface, &presentModeCnt, raw_data(vkPresentModes))

	for f in vk_fmts {
		if f.format == .R8G8B8A8_UNORM || f.format == .B8G8R8A8_UNORM {
			when is_log {
				fmt.printfln("XFIT SYSLOG : vulkan swapchain format : %s, colorspace : %s", f.format, f.colorSpace)
			}
			vk_fmt = f
			break;
		}
	}
	if vk_fmt.format == .UNDEFINED do trace.panic_log("Xfit vulkan unsupported format")

	depthProp:vk.FormatProperties
	vk.GetPhysicalDeviceFormatProperties(vk_physical_device, .D24_UNORM_S8_UINT, &depthProp)
	vkDepthHasOptimal = .DEPTH_STENCIL_ATTACHMENT in depthProp.optimalTilingFeatures

	depth_fmt = .D24UnormS8Uint
	if !vkDepthHasOptimal && .DEPTH_STENCIL_ATTACHMENT in depthProp.linearTilingFeatures {//not support D24_UNORM_S8_UINT
		vk.GetPhysicalDeviceFormatProperties(vk_physical_device, .D32_SFLOAT_S8_UINT, &depthProp)
		vkDepthHasOptimal = .DEPTH_STENCIL_ATTACHMENT in depthProp.optimalTilingFeatures

		if !vkDepthHasOptimal && .DEPTH_STENCIL_ATTACHMENT in depthProp.linearTilingFeatures {
			vk.GetPhysicalDeviceFormatProperties(vk_physical_device, .D16_UNORM_S8_UINT, &depthProp)
			vkDepthHasOptimal = .DEPTH_STENCIL_ATTACHMENT in depthProp.optimalTilingFeatures
			depth_fmt = .D16UnormS8Uint
		} else {
			depth_fmt = .D32SfloatS8Uint
		}
	}
	vkDepthHasTransferSrcOptimal = .TRANSFER_SRC in depthProp.optimalTilingFeatures
	vkDepthHasTransferDstOptimal = .TRANSFER_DST in depthProp.optimalTilingFeatures
	vkDepthHasSampleOptimal = .SAMPLED_IMAGE in depthProp.optimalTilingFeatures

	colorProp:vk.FormatProperties
	vk.GetPhysicalDeviceFormatProperties(vk_physical_device, vk_fmt.format, &colorProp)
	vkColorHasAttachOptimal = .COLOR_ATTACHMENT in colorProp.optimalTilingFeatures
	vkColorHasSampleOptimal = .SAMPLED_IMAGE in colorProp.optimalTilingFeatures
	vkColorHasTransferSrcOptimal =.TRANSFER_SRC in colorProp.optimalTilingFeatures
	vkColorHasTransferDstOptimal = .TRANSFER_DST in colorProp.optimalTilingFeatures

	when is_log {
		fmt.printfln("XFIT SYSLOG : depth format : %s", depth_fmt)
		fmt.println("XFIT SYSLOG : optimal format supports")
		fmt.printfln("vkDepthHasOptimal : %t", vkDepthHasOptimal)
		fmt.printfln("vkDepthHasTransferSrcOptimal : %t", vkDepthHasTransferSrcOptimal)
		fmt.printfln("vkDepthHasTransferDstOptimal : %t", vkDepthHasTransferDstOptimal)
		fmt.printfln("vkDepthHasSampleOptimal : %t", vkDepthHasSampleOptimal)
		fmt.printfln("vkColorHasAttachOptimal : %t", vkColorHasAttachOptimal)
		fmt.printfln("vkColorHasSampleOptimal : %t", vkColorHasSampleOptimal)
		fmt.printfln("vkColorHasTransferSrcOptimal : %t", vkColorHasTransferSrcOptimal)
		fmt.printfln("vkColorHasTransferDstOptimal : %t", vkColorHasTransferDstOptimal)
	}
}

vk_create_swap_chain_and_image_views :: proc() -> bool {
	vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(vk_physical_device, vk_surface, &vk_surface_cap)

	if(vk_surface_cap.currentExtent.width == max(u32)) {
		vk_surface_cap.currentExtent.width = clamp(u32(__window_width.?), vk_surface_cap.minImageExtent.width, vk_surface_cap.maxImageExtent.width)
		vk_surface_cap.currentExtent.height = clamp(u32(__window_height.?), vk_surface_cap.minImageExtent.height, vk_surface_cap.maxImageExtent.height)
	}
	vk_extent = vk_surface_cap.currentExtent
	vk_extent_rotation = vk_extent

	if vk_extent.width == 0 || vk_extent.height == 0 {
		return false
	}
	
	if library.is_mobile {
		if .ROTATE_90 in vk_surface_cap.currentTransform {
			vk_extent_rotation.width = vk_extent.height
			vk_extent_rotation.height = vk_extent.width
			__screen_orientation = .Landscape90
		} else if .ROTATE_270 in vk_surface_cap.currentTransform {
			vk_extent_rotation.width = vk_extent.height
			vk_extent_rotation.height = vk_extent.width
			__screen_orientation = .Landscape270
		} else if .ROTATE_180 in vk_surface_cap.currentTransform {
			__screen_orientation = .Vertical180
		} else if .IDENTITY in vk_surface_cap.currentTransform {
			__screen_orientation = .Vertical360
		}
		__window_width = int(vk_extent.width)
		__window_height = int(vk_extent.height)
	}

	vkPresentMode = .FIFO
	if __v_sync == .Double {
		when is_log {
			if program_start do fmt.println("XFIT SYSLOG : vulkan present mode fifo_khr vsync double")
		}
	} else {
		if __v_sync == .Triple {
			for p in vkPresentModes {
				if p == .MAILBOX {
					when is_log {
						if program_start do fmt.println("XFIT SYSLOG : vulkan present mode mailbox_khr vsync triple")
					}
					vkPresentMode = p
					break;
				}
			}
		}
		for p in vkPresentModes {
			if p == .IMMEDIATE {
				when is_log {
					if program_start {
						if __v_sync == .Triple do fmt.println("XFIT SYSLOG : vulkan present mode immediate_khr mailbox_khr instead(vsync triple -> none)")
						else do fmt.println("XFIT SYSLOG : vulkan present mode immediate_khr vsync none")
					} 
				}
				vkPresentMode = p
				break;
			}
		}
	}
	program_start = false

	surface_img_cnt := max(swap_img_cnt , vk_surface_cap.minImageCount)
	if vk_surface_cap.maxImageCount > 0 && surface_img_cnt > vk_surface_cap.maxImageCount {//0 is no limit max+
		surface_img_cnt = vk_surface_cap.maxImageCount
	}
	swap_img_cnt = surface_img_cnt

	if .OPAQUE in vk_surface_cap.supportedCompositeAlpha {
		vk_surface_cap.supportedCompositeAlpha = {.OPAQUE}
	} else if .INHERIT in vk_surface_cap.supportedCompositeAlpha {
		vk_surface_cap.supportedCompositeAlpha = {.INHERIT}
	} else if .PRE_MULTIPLIED in vk_surface_cap.supportedCompositeAlpha {
		vk_surface_cap.supportedCompositeAlpha = {.PRE_MULTIPLIED}
	} else if .POST_MULTIPLIED in vk_surface_cap.supportedCompositeAlpha {
		vk_surface_cap.supportedCompositeAlpha = {.POST_MULTIPLIED}
	} else {
		trace.panic_log("not supports supportedCompositeAlpha")
	}

	swapChainCreateInfo := vk.SwapchainCreateInfoKHR{
		sType = vk.StructureType.SWAPCHAIN_CREATE_INFO_KHR,
		minImageCount = swap_img_cnt,
		imageFormat = vk_fmt.format,
		imageColorSpace = vk_fmt.colorSpace,
		imageExtent = vk_extent_rotation,
		imageArrayLayers = 1,
		imageUsage = {.COLOR_ATTACHMENT},
		presentMode = vkPresentMode,
		preTransform = vk_surface_cap.currentTransform,
		compositeAlpha = vk_surface_cap.supportedCompositeAlpha,
		clipped = true,
		oldSwapchain = 0,
		imageSharingMode = .EXCLUSIVE,
		pNext = nil,
		queueFamilyIndexCount = 0,
		surface = vk_surface
	}
	when ODIN_OS == .Windows {
		if __is_full_screen_ex && VK_EXT_full_screen_exclusive_support() {
			fullScreenWinInfo : vk.SurfaceFullScreenExclusiveWin32InfoEXT
			fullScreenInfo := vk.SurfaceFullScreenExclusiveInfoEXT{
				sType = vk.StructureType.SURFACE_FULL_SCREEN_EXCLUSIVE_INFO_EXT,
				pNext = nil,
				fullScreenExclusive = .APPLICATION_CONTROLLED,
			}
			if current_monitor != nil {
				fullScreenWinInfo = vk.SurfaceFullScreenExclusiveWin32InfoEXT{
					sType = vk.StructureType.SURFACE_FULL_SCREEN_EXCLUSIVE_WIN32_INFO_EXT,
					pNext = nil,
					hmonitor = glfw_get_current_hmonitor(),
				}
				fullScreenInfo.pNext = &fullScreenWinInfo
			}
			swapChainCreateInfo.pNext = &fullScreenInfo
		}
	}
	queueFamiliesIndices := [2]u32{vk_graphics_family_index, vk_present_family_index}
	if vk_graphics_family_index != vk_present_family_index {
		swapChainCreateInfo.imageSharingMode = .CONCURRENT
		swapChainCreateInfo.queueFamilyIndexCount = 2
		swapChainCreateInfo.pQueueFamilyIndices = raw_data(queueFamiliesIndices[:])
	}

	res := vk.CreateSwapchainKHR(vk_device, &swapChainCreateInfo, nil, &vk_swapchain)
	if res != .SUCCESS {
		return false
	}

	vk.GetSwapchainImagesKHR(vk_device, vk_swapchain, &swap_img_cnt, nil)
	swapImgs:= mem.make_non_zeroed([]vk.Image, swap_img_cnt, context.temp_allocator)
	defer delete(swapImgs, context.temp_allocator)
	vk.GetSwapchainImagesKHR(vk_device, vk_swapchain, &swap_img_cnt, &swapImgs[0])

	vk_frame_buffers = mem.make_non_zeroed([]vk.Framebuffer, swap_img_cnt)
	//vk_clear_frame_buffers = mem.make_non_zeroed([]vk.Framebuffer, swapImgCnt)
	vk_frame_buffer_image_views = mem.make_non_zeroed([]vk.ImageView, swap_img_cnt)
	
	texture_init_depth_stencil(&vk_frame_depth_stencil_texture, vk_extent_rotation.width, vk_extent_rotation.height)
	when msaa_count > 1 {
		texture_init_msaa(&vk_msaa_frame_texture, vk_extent_rotation.width, vk_extent_rotation.height)
	}

	refresh_pre_matrix()
	graphics_execute_ops()

	for img, i in swapImgs {
		imageViewCreateInfo := vk.ImageViewCreateInfo{
			sType = vk.StructureType.IMAGE_VIEW_CREATE_INFO,
			image = img,
			viewType = .D2,
			format = vk_fmt.format,
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
		res = vk.CreateImageView(vk_device, &imageViewCreateInfo, nil, &vk_frame_buffer_image_views[i])
		if res != .SUCCESS do trace.panic_log("res = vk.CreateImageView(vk_device, &imageViewCreateInfo, nil, &vk_frame_buffer_image_views[i]) : ", res)

		when msaa_count == 1 {
			frameBufferCreateInfo := vk.FramebufferCreateInfo{
				sType = vk.StructureType.FRAMEBUFFER_CREATE_INFO,
				renderPass = vk_render_pass,
				attachmentCount = 2,
				pAttachments = &([]vk.ImageView{vk_frame_buffer_image_views[i], (^texture_resource)(vk_frame_depth_stencil_texture.texture).img_view, })[0],
				width = vk_extent_rotation.width,
				height = vk_extent_rotation.height,
				layers = 1,
			}
		} else {
			frameBufferCreateInfo := vk.FramebufferCreateInfo{
				sType = vk.StructureType.FRAMEBUFFER_CREATE_INFO,
				renderPass = vk_render_pass,
				attachmentCount = 3,
				pAttachments = &([]vk.ImageView{(^texture_resource)(vk_msaa_frame_texture.texture).img_view,
					 (^texture_resource)(vk_frame_depth_stencil_texture.texture).img_view,
					  vk_frame_buffer_image_views[i]})[0],
				width = vk_extent_rotation.width,
				height = vk_extent_rotation.height,
				layers = 1,
			}
		}
		res = vk.CreateFramebuffer(vk_device, &frameBufferCreateInfo, nil, &vk_frame_buffers[i])
		if res != .SUCCESS do trace.panic_log("res = vk.CreateFramebuffer(vk_device, &frameBufferCreateInfo, nil, &vk_frame_buffers[i]) : ", res)
	}

	return true
} 

vk_start :: proc() {
	ok: bool
	when ODIN_OS == .Windows {
		vk_library, ok = dynlib.load_library("vulkan-1.dll")
		if !ok do trace.panic_log(" vk_library, ok = dynlib.load_library(\"vulkan-1.dll\")")
	} else {
		vk_library, ok = dynlib.load_library("libvulkan.so.1")
		if !ok {
			vk_library, ok = dynlib.load_library("libvulkan.so")
			if !ok do trace.panic_log(" vk_library, ok = dynlib.load_library(\"libvulkan.so\")")
		}
	}
	rawFunc: rawptr
	rawFunc, ok = dynlib.symbol_address(vk_library, "vkGetInstanceProcAddr")
	if !ok do trace.panic_log("rawFunc, ok = dynlib.symbol_address(vk_library, \"vkGetInstanceProcAddr\")")
	vk_get_instance_proc_addr = auto_cast rawFunc
	vk.load_proc_addresses_global(rawFunc)

	appInfo := vk.ApplicationInfo {
		apiVersion         = vk.API_VERSION_1_4,
		engineVersion      = vk.MAKE_VERSION(1, 0, 0),
		applicationVersion = vk.MAKE_VERSION(1, 0, 0),
		pEngineName        = "Xfit",
		pApplicationName   = ODIN_BUILD_PROJECT_NAME,
	}
	FN_vkEnumerateInstanceVersion := vk.ProcEnumerateInstanceVersion(vk.GetInstanceProcAddr(nil, "vkEnumerateInstanceVersion"))
	if FN_vkEnumerateInstanceVersion == nil {
		when is_log do fmt.println("XFIT SYSLOG : vulkan 1.0 device, set api version 1.0")
		appInfo.apiVersion = vk.API_VERSION_1_0
		vulkan_version = {1,0,0}
	} else {
		vk_ver:u32
		FN_vkEnumerateInstanceVersion(&vk_ver)
		vulkan_version = { vk.VK_VERSION_MAJOR(vk_ver), vk.VK_VERSION_MINOR(vk_ver), vk.VK_VERSION_PATCH(vk_ver) }
		when is_log do fmt.println("XFIT SYSLOG : vulkan version : ", vulkan_version)
	}
	glfwLen := 0
	glfwExtensions : []cstring
	when !library.is_mobile {
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
					when is_log do fmt.printfln(
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
				when is_log do fmt.printfln(
					"XFIT SYSLOG : vulkan %s instance ext support",
					INSTANCE_EXTENSIONS[i],
				)
			}
		}
	}
	if validation_layer_support() {
		non_zero_append(&instanceExtNames, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)

		when is_log do fmt.println("XFIT SYSLOG : vulkan validation layer enable")
	} else {
		when is_log do fmt.println("XFIT SYSLOG : vulkan validation layer disable")
	}

	when library.is_android {
		non_zero_append(&instanceExtNames, "VK_KHR_android_surface")
	} else {
	}

	when !library.is_mobile {
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
		flags                   = vk.InstanceCreateFlags{.ENUMERATE_PORTABILITY_KHR} if vk_khr_portability_enumeration_support() else vk.InstanceCreateFlags{},
	}

	res := vk.CreateInstance(&instanceCreateInfo, nil, &vk_instance)
	if (res != vk.Result.SUCCESS) do trace.panic_log("vk.CreateInstance(&instanceCreateInfo, nil, &vk_instance) : ", res)

	vk.load_proc_addresses_instance(vk_instance)

	if validation_layer_support() && ODIN_DEBUG {
		debugUtilsCreateInfo := vk.DebugUtilsMessengerCreateInfoEXT {
			sType = vk.StructureType.DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
			messageSeverity = vk.DebugUtilsMessageSeverityFlagsEXT{.ERROR, .VERBOSE, .WARNING},
			messageType     = vk.DebugUtilsMessageTypeFlagsEXT {.GENERAL, .VALIDATION, .PERFORMANCE},
			pfnUserCallback = vk_debug_callback,
			pUserData       = nil,
		}
		vk.CreateDebugUtilsMessengerEXT(
			vk_instance,
			&debugUtilsCreateInfo,
			nil,
			&vk_debug_utils_messenger,
		)
	}

	vk_create_surface()

	physicalDeviceCnt: u32
	vk.EnumeratePhysicalDevices(vk_instance, &physicalDeviceCnt, nil)
	vk_physical_devices := mem.make_non_zeroed([]vk.PhysicalDevice, physicalDeviceCnt, context.temp_allocator)
	defer delete(vk_physical_devices, context.temp_allocator)
	vk.EnumeratePhysicalDevices(vk_instance, &physicalDeviceCnt, &vk_physical_devices[0])

	out: for pd in vk_physical_devices {
		queueFamilyPropCnt: u32
		vk.GetPhysicalDeviceQueueFamilyProperties(pd, &queueFamilyPropCnt, nil)
		queueFamilies := mem.make_non_zeroed([]vk.QueueFamilyProperties, queueFamilyPropCnt, context.temp_allocator)
		defer delete(queueFamilies, context.temp_allocator)
		vk.GetPhysicalDeviceQueueFamilyProperties(pd, &queueFamilyPropCnt, &queueFamilies[0])

		for i in 0 ..< queueFamilyPropCnt {
			if .GRAPHICS in queueFamilies[i].queueFlags do vk_graphics_family_index = i
			
			isPresentSupport: b32
			vk.GetPhysicalDeviceSurfaceSupportKHR(pd, i, vk_surface, &isPresentSupport)

			if isPresentSupport do vk_present_family_index = i
			if vk_graphics_family_index != max(u32) && vk_present_family_index != max(u32) {
				vk_physical_device = pd
				break out
			}
		}
	}
	queuePriorty: [1]f32 = {1}
	deviceQueueCreateInfos := [2]vk.DeviceQueueCreateInfo {
		vk.DeviceQueueCreateInfo {
			sType = vk.StructureType.DEVICE_QUEUE_CREATE_INFO,
			queueCount = 1,
			queueFamilyIndex = vk_graphics_family_index,
			pQueuePriorities = &queuePriorty[0],
		},
		vk.DeviceQueueCreateInfo {
			sType = vk.StructureType.DEVICE_QUEUE_CREATE_INFO,
			queueCount = 1,
			queueFamilyIndex = vk_present_family_index,
			pQueuePriorities = &queuePriorty[0],
		},
	}
	queueCnt: u32 = 1 if vk_graphics_family_index == vk_present_family_index else 2

	deviceExtCnt: u32
	vk.EnumerateDeviceExtensionProperties(vk_physical_device, nil, &deviceExtCnt, nil)
	deviceExts := mem.make_non_zeroed([]vk.ExtensionProperties, deviceExtCnt, context.temp_allocator)
	defer delete(deviceExts, context.temp_allocator)
	vk.EnumerateDeviceExtensionProperties(vk_physical_device, nil, &deviceExtCnt, &deviceExts[0])

	deviceExtNames := mem.make_non_zeroed([dynamic]cstring, 0, len(DEVICE_EXTENSIONS) + 1, context.temp_allocator)
	defer delete(deviceExtNames)
	non_zero_append(&deviceExtNames, vk.KHR_SWAPCHAIN_EXTENSION_NAME)

	for &e in deviceExts {
		for _, i in DEVICE_EXTENSIONS {
			if !DEVICE_EXTENSIONS_CHECK[i] &&
			   mem.compare((transmute([^]byte)DEVICE_EXTENSIONS[i])[:len(DEVICE_EXTENSIONS[i])],e.extensionName[:len(DEVICE_EXTENSIONS[i])]) == 0 {
				non_zero_append(&deviceExtNames, DEVICE_EXTENSIONS[i])
				DEVICE_EXTENSIONS_CHECK[i] = true
				when is_log do fmt.printfln(
					"XFIT SYSLOG : vulkan %s device ext support",
					DEVICE_EXTENSIONS[i],
				)
			}
		}
	}

	
	REQUIRED_VK_13_FEATURES := vk.PhysicalDeviceVulkan13Features {
		sType            = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
		//dynamicRendering = true,
		//synchronization2 = true,
		shaderDemoteToHelperInvocation = true,
	}
	REQUIRED_VK_12_FEATURES := vk.PhysicalDeviceVulkan12Features {
		sType = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
	}
	if get_vulkan_version().major > 1 || get_vulkan_version().minor >= 3 do REQUIRED_VK_12_FEATURES.pNext = &REQUIRED_VK_13_FEATURES
	REQUIRED_VK_11_FEATURES := vk.PhysicalDeviceVulkan11Features {
		sType                         = .PHYSICAL_DEVICE_VULKAN_1_1_FEATURES,
		//variablePointers              = true,
		//variablePointersStorageBuffer = true,
	}
	if get_vulkan_version().major > 1 || get_vulkan_version().minor >= 2 do REQUIRED_VK_11_FEATURES.pNext = &REQUIRED_VK_12_FEATURES
	REQUIRED_FEATURES := vk.PhysicalDeviceFeatures2 {
		sType    = .PHYSICAL_DEVICE_FEATURES_2,
		features = {
			samplerAnisotropy = true
		},
	}
	if get_vulkan_version().major > 1 || get_vulkan_version().minor >= 1 do REQUIRED_FEATURES.pNext = &REQUIRED_VK_11_FEATURES

	deviceCreateInfo := vk.DeviceCreateInfo {
		sType                   = vk.StructureType.DEVICE_CREATE_INFO,
		pQueueCreateInfos       = &deviceQueueCreateInfos[0],
		queueCreateInfoCount    = queueCnt,
		pEnabledFeatures        = nil,
		ppEnabledExtensionNames = &deviceExtNames[0],
		enabledExtensionCount   = auto_cast len(deviceExtNames),
		pNext = &REQUIRED_FEATURES,
	}

	res = vk.CreateDevice(vk_physical_device, &deviceCreateInfo, nil, &vk_device)
	if (res != vk.Result.SUCCESS) do trace.panic_log("res = vk.CreateDevice(vk_physical_device, &deviceCreateInfo, nil, &vk_device) : ", res)
	vk.load_proc_addresses_device(vk_device)

	vk.GetPhysicalDeviceMemoryProperties(vk_physical_device, &vk_physical_mem_prop)
	vk.GetPhysicalDeviceProperties(vk_physical_device, &vk_physical_prop)

	if vk_graphics_family_index == vk_present_family_index {
		vk.GetDeviceQueue(vk_device, vk_graphics_family_index, 0, &vk_graphics_queue)
		vk_present_queue = vk_graphics_queue
	} else {
		vk.GetDeviceQueue(vk_device, vk_graphics_family_index, 0, &vk_graphics_queue)
		vk.GetDeviceQueue(vk_device, vk_present_family_index, 0, &vk_present_queue)
	}

	res = vk.CreateCommandPool(vk_device, &vk.CommandPoolCreateInfo{
		sType = vk.StructureType.COMMAND_POOL_CREATE_INFO,
		flags = vk.CommandPoolCreateFlags{.RESET_COMMAND_BUFFER},
		queueFamilyIndex = vk_graphics_family_index,
	}, nil, &vk_cmd_pool)
	if res != .SUCCESS do trace.panic_log("vk.CreateCommandPool(&vk_cmd_pool) : ", res)

	res = vk.AllocateCommandBuffers(vk_device, &vk.CommandBufferAllocateInfo{
		sType = vk.StructureType.COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool = vk_cmd_pool,
		level = vk.CommandBufferLevel.PRIMARY,
		commandBufferCount = MAX_FRAMES_IN_FLIGHT,
	}, &vk_cmd_buffer[0])
	if res != .SUCCESS do trace.panic_log("vk.AllocateCommandBuffers(&vk_cmd_buffer) : ", res)

	vk_init_block_len()
	vk_allocator_init()

	graphics_create()

	init_swap_chain()

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
		maxAnisotropy           = vk_physical_prop.limits.maxSamplerAnisotropy,
		borderColor             = .INT_OPAQUE_WHITE,
	}
	vk.CreateSampler(vk_device, &samplerInfo, nil, &linear_sampler)
	samplerInfo.mipmapMode = .NEAREST
	samplerInfo.magFilter = .NEAREST
	samplerInfo.minFilter = .NEAREST
	vk.CreateSampler(vk_device, &samplerInfo, nil, &nearest_sampler)

	vk_depth_fmt := texture_fmt_to_vk_fmt(depth_fmt)
	depthAttachmentSample := vk.AttachmentDescriptionInit(
		format = vk_depth_fmt,
		loadOp = .CLEAR,
		storeOp = .STORE,
		initialLayout = .UNDEFINED,
		finalLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
		samples = VK_SAMPLE_COUNT_FLAGS,
	)
	// depthAttachmentSampleClear := vk.AttachmentDescriptionInit(
	// 	format = vkDepthFmt,
	// 	loadOp = .CLEAR,
	// 	storeOp = .STORE,
	// 	finalLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
	// 	samples = VK_SAMPLE_COUNT_FLAGS,
	// )
	// colorAttachmentSampleClear := vk.AttachmentDescriptionInit(
	// 	format = vk_fmt.format,
	// 	loadOp = .CLEAR,
	// 	storeOp = .STORE,
	// 	finalLayout = .COLOR_ATTACHMENT_OPTIMAL,
	// 	samples = VK_SAMPLE_COUNT_FLAGS,
	// )
	colorAttachmentSample := vk.AttachmentDescriptionInit(
		format = vk_fmt.format,
		loadOp = .CLEAR,
		storeOp = .STORE,
		initialLayout = .UNDEFINED,
		finalLayout = .COLOR_ATTACHMENT_OPTIMAL,
		samples = VK_SAMPLE_COUNT_FLAGS,
	)
	colorAttachmentResolve := vk.AttachmentDescriptionInit(
		format = vk_fmt.format,
		storeOp = .STORE,
		finalLayout = .PRESENT_SRC_KHR,
	)

	colorAttachmentLoadResolve := vk.AttachmentDescriptionInit(
		format = vk_fmt.format,
		loadOp = .LOAD,
		initialLayout = .COLOR_ATTACHMENT_OPTIMAL,
		finalLayout = .COLOR_ATTACHMENT_OPTIMAL,
	)
	// colorAttachmentClear := vk.AttachmentDescriptionInit(
	// 	format = vk_fmt.format,
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
		format = vk_fmt.format,
		loadOp = .CLEAR,
		storeOp = .STORE,
		finalLayout = .PRESENT_SRC_KHR,
	)
	depthAttachment := vk.AttachmentDescriptionInit(
		format = vk_depth_fmt,
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

	when msaa_count == 1 {
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
	
	vk.CreateRenderPass(vk_device, &renderPassInfo, nil, &vk_render_pass)

	init_pipelines()

	vk_create_swap_chain_and_image_views()
	vk_create_sync_object()

	vk_wait_all_op()//reset wait

	__layer_create()
}

vk_destroy :: proc() {
	__layer_clean()

	graphics_clean()

	clean_pipelines()

	vk_clean_sync_object()
	vk_clean_swap_chain()

	vk_allocator_destroy()

	vk.DestroyCommandPool(vk_device, vk_cmd_pool, nil)

	vk.DestroySampler(vk_device, linear_sampler, nil)
	vk.DestroySampler(vk_device, nearest_sampler, nil)

	vk.DestroyRenderPass(vk_device, vk_render_pass, nil)
	// vk.DestroyRenderPass(vk_device, vkRenderPassClear, nil)

	delete(vk_fmts)
	delete(vkPresentModes)

	vk.DestroySurfaceKHR(vk_instance, vk_surface, nil)

	vk.DestroyDevice(vk_device, nil)
	when ODIN_DEBUG {
		if vk_debug_utils_messenger != 0 {
			vk.DestroyDebugUtilsMessengerEXT(vk_instance, vk_debug_utils_messenger, nil)
		}
	}

	vk.DestroyInstance(vk_instance, nil)

	dynlib.unload_library(vk_library)
}

vk_wait_device_idle :: proc "contextless" () {
	res := vk.DeviceWaitIdle(vk_device)
	if res != .SUCCESS do trace.panic_log("vk_wait_device_idle : ", res )
}

vk_wait_graphics_idle :: proc "contextless" () {
	res := vk.QueueWaitIdle(vk_graphics_queue)
	if res != .SUCCESS do trace.panic_log("vk_wait_graphics_idle : ", res )
}

vk_wait_present_idle :: proc "contextless" () {
	res := vk.QueueWaitIdle(vk_present_queue)
	if res != .SUCCESS do trace.panic_log("vk_wait_present_idle : ", res )
}

vk_recreate_swap_chain :: proc() {
	if vk_device == nil || vk_swapchain == 0 {
		return
	}
	sync.mutex_lock(&full_screen_mtx)

	vk_release_full_screen_ex()

	vk_wait_device_idle()

	when library.is_android {//? ANDROID ONLY
		vulkan_android_start()
	}

	//vkCleanSyncObject()
	vk_clean_swap_chain()

	if !vk_create_swap_chain_and_image_views() {
		sync.mutex_unlock(&full_screen_mtx)
		return
	}
	//vkCreateSyncObject()

	vk_set_full_screen_ex()

	size_updated = false

	sync.mutex_unlock(&full_screen_mtx)

	layer_size_all()
	size()
	if len(__g_layer) > 0 {
		//thread pool 사용해서 각각 처리
		size_task_data :: struct {
			cmd: ^layer,
		}
		
		size_task_proc :: proc(task: thread.Task) {
			data := cast(^size_task_data)task.data
			for obj in data.cmd.scene {
				iobject_size(auto_cast obj)
			}
		}

		// Add each layer as a task to thread pool
		for cmd in __g_layer {
			data := new(size_task_data, context.temp_allocator)
			data.cmd = cmd
			thread.pool_add_task(&g_thread_pool, context.allocator, size_task_proc, data)
		}
		for thread.pool_num_done(&g_thread_pool) < len(__g_layer) {
			thread.yield()
		}
		for {
			thread.pool_pop_done(&g_thread_pool) or_break
		}
	}
}
vk_create_surface :: vk_recreate_surface

vk_set_full_screen_ex :: proc() {
	when ODIN_OS == .Windows {
		if VK_EXT_full_screen_exclusive_support() && __is_full_screen_ex {
			res := vk.AcquireFullScreenExclusiveModeEXT(vk_device, vk_swapchain)
			if res != .SUCCESS do trace.panic_log("AcquireFullScreenExclusiveModeEXT : ", res)
			is_released_full_screen_ex = false
		}
	}
}

vk_release_full_screen_ex :: proc() {
	when ODIN_OS == .Windows {
		if VK_EXT_full_screen_exclusive_support() && !is_released_full_screen_ex {
			res := vk.ReleaseFullScreenExclusiveModeEXT(vk_device, vk_swapchain)
			if res != .SUCCESS do trace.panic_log("ReleaseFullScreenExclusiveModeEXT : ", res)
			is_released_full_screen_ex = true
		}
	}
}

vk_recreate_surface :: proc() {
	when library.is_android {
		vulkan_android_start()
	} else {// !ismobile
		glfw_vulkan_start()
	}
}

vk_frame:int = 0

vk_draw_frame :: proc() {

	graphics_execute_ops()

	if vk_swapchain == 0 do return
	if vk_extent.width <= 0 || vk_extent.height <= 0 {
		vk_recreate_swap_chain()
		vk_frame = 0
		return
	}

	res := vk.WaitForFences(vk_device, 1, &vk_in_flight_fence[vk_frame], true, max(u64))
	if res != .SUCCESS do trace.panic_log("WaitForFences : ", res)


	imageIndex: u32
	res = vk.AcquireNextImageKHR(vk_device, vk_swapchain, max(u64), vk_image_available_semaphore[vk_frame], 0, &imageIndex)
	if res == .ERROR_OUT_OF_DATE_KHR {
		vk_recreate_swap_chain()
		vk_frame = 0
		return
	} else if res == .SUBOPTIMAL_KHR {
	} else if res == .ERROR_SURFACE_LOST_KHR {
	} else if res != .SUCCESS { trace.panic_log("AcquireNextImageKHR : ", res) }

	cmd_visible := false
	sync.mutex_lock(&__g_layer_mtx)
	visible_layers := make([dynamic]^layer, 0, len(__g_layer), context.temp_allocator)
	defer delete(visible_layers)
	if __g_layer != nil && len(__g_layer) > 0 {
		// Collect visible commands
		for &cmd in __g_layer {
			if cmd.visible && cmd.scene != nil && len(cmd.scene^) > 0 {
				append(&visible_layers, cmd)
				cmd_visible = true
			}
		}
	}
	res = vk.WaitForFences(vk_device, 1, &vk_allocator_fence, true, max(u64))
	if res != .SUCCESS do trace.panic_log("res := vk.WaitForFences(vk_device, 1, &vk_allocator_fence, true, max(u64)) : ", res)

	if cmd_visible {
		vk.BeginCommandBuffer(vk_cmd_buffer[vk_frame], &vk.CommandBufferBeginInfo {
			sType = vk.StructureType.COMMAND_BUFFER_BEGIN_INFO,
			flags = {vk.CommandBufferUsageFlag.RENDER_PASS_CONTINUE},
		})

		clsColor :vk.ClearValue = {color = {float32 = g_clear_color}}
		clsDepthStencil :vk.ClearValue = {depthStencil = {depth = 1.0, stencil = 0}}
		renderPassBeginInfo := vk.RenderPassBeginInfo {
			sType = vk.StructureType.RENDER_PASS_BEGIN_INFO,
			renderPass = vk_render_pass,
			framebuffer = vk_frame_buffers[imageIndex],
			renderArea = {
				offset = {x = 0, y = 0},
				extent = vk_extent_rotation,	
			},
			clearValueCount = 2,
			pClearValues = &([]vk.ClearValue{clsColor, clsDepthStencil})[0],
		}
		vk.CmdBeginRenderPass(vk_cmd_buffer[vk_frame], &renderPassBeginInfo, vk.SubpassContents.SECONDARY_COMMAND_BUFFERS)
		inheritanceInfo := vk.CommandBufferInheritanceInfo {
			sType = vk.StructureType.COMMAND_BUFFER_INHERITANCE_INFO,
			renderPass = vk_render_pass,
			framebuffer = vk_frame_buffers[imageIndex],
		}

		record_task_data :: struct {
			cmd: ^layer,
			inheritanceInfo: vk.CommandBufferInheritanceInfo,
			vk_frame: int,
		}
		
		record_task_proc :: proc(task: thread.Task) {
			data := cast(^record_task_data)task.data
			vk_record_command_buffer(data.cmd, data.inheritanceInfo, data.vk_frame)
		}

		for cmd in visible_layers {
			data := new(record_task_data, context.temp_allocator)
			data.cmd = cmd
			data.inheritanceInfo = inheritanceInfo
			data.vk_frame = vk_frame
			thread.pool_add_task(&g_thread_pool, context.allocator, record_task_proc, data)
		}
		for thread.pool_num_done(&g_thread_pool) < len(visible_layers) {
			thread.yield()
		}
		for {
			thread.pool_pop_done(&g_thread_pool) or_break
		}
		
		cmd_buffers := make([]vk.CommandBuffer, len(visible_layers), context.temp_allocator)
		defer delete(cmd_buffers, context.temp_allocator)
		for cmd, i in visible_layers {
			cmd_buffers[i] = cmd.cmd[vk_frame].__handle
		}
		vk.CmdExecuteCommands(vk_cmd_buffer[vk_frame], auto_cast len(cmd_buffers), &cmd_buffers[0])
		vk.CmdEndRenderPass(vk_cmd_buffer[vk_frame])
		res = vk.EndCommandBuffer(vk_cmd_buffer[vk_frame])
		if res != .SUCCESS do trace.panic_log("EndCommandBuffer : ", res)

		res = vk.ResetFences(vk_device, 1, &vk_in_flight_fence[vk_frame])
		if res != .SUCCESS do trace.panic_log("ResetFences : ", res)

		waitStages := vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT}
		submitInfo := vk.SubmitInfo {
			sType = vk.StructureType.SUBMIT_INFO,
			waitSemaphoreCount = 1,
			pWaitSemaphores = &[]vk.Semaphore{vk_image_available_semaphore[vk_frame]}[0],
			pWaitDstStageMask = &waitStages,
			commandBufferCount = 1,
			pCommandBuffers = &vk_cmd_buffer[vk_frame],
			signalSemaphoreCount = 1,
			pSignalSemaphores = &vk_render_finished_semaphore[vk_frame][imageIndex],
		}
		vk.WaitForFences(vk_device, 1, &vk_in_flight_fence[(vk_frame + 1) % MAX_FRAMES_IN_FLIGHT], true, max(u64))
		if res != .SUCCESS do trace.panic_log("WaitForFences : ", res)
		res = vk.QueueSubmit(vk_graphics_queue, 1, &submitInfo, vk_in_flight_fence[vk_frame])
		if res != .SUCCESS do trace.panic_log("QueueSubmit : ", res)

		sync.mutex_unlock(&__g_layer_mtx)
	} else {
		//?그릴 오브젝트가 없는 경우
		waitStages := vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT}

		clsColor :vk.ClearValue = {color = {float32 = g_clear_color}}
		clsDepthStencil :vk.ClearValue = {depthStencil = {depth = 1.0, stencil = 0}}

		renderPassBeginInfo := vk.RenderPassBeginInfo {
			sType = vk.StructureType.RENDER_PASS_BEGIN_INFO,
			renderPass = vk_render_pass,
			framebuffer = vk_frame_buffers[imageIndex],
			renderArea = {
				offset = {x = 0, y = 0},
				extent = vk_extent_rotation,	
			},
			clearValueCount = 2,
			pClearValues = &([]vk.ClearValue{clsColor, clsDepthStencil})[0],
		}
		vk.BeginCommandBuffer(vk_cmd_buffer[vk_frame], &vk.CommandBufferBeginInfo {
			sType = vk.StructureType.COMMAND_BUFFER_BEGIN_INFO,
			flags = {vk.CommandBufferUsageFlag.ONE_TIME_SUBMIT},
		})
		vk.CmdBeginRenderPass(vk_cmd_buffer[vk_frame], &renderPassBeginInfo, vk.SubpassContents.INLINE)
		vk.CmdEndRenderPass(vk_cmd_buffer[vk_frame])
		res = vk.EndCommandBuffer(vk_cmd_buffer[vk_frame])
		if res != .SUCCESS do trace.panic_log("EndCommandBuffer : ", res)

		submitInfo := vk.SubmitInfo {
			sType = vk.StructureType.SUBMIT_INFO,
			waitSemaphoreCount = 1,
			pWaitSemaphores = &vk_image_available_semaphore[vk_frame],
			pWaitDstStageMask = &waitStages,
			commandBufferCount = 1,
			pCommandBuffers = &vk_cmd_buffer[vk_frame],
			signalSemaphoreCount = 1,
			pSignalSemaphores = &vk_render_finished_semaphore[vk_frame][imageIndex],
		}

		res = vk.ResetFences(vk_device, 1, &vk_in_flight_fence[vk_frame])
		if res != .SUCCESS do trace.panic_log("ResetFences : ", res)

		res = vk.QueueSubmit(vk_graphics_queue, 1, &submitInfo, 	vk_in_flight_fence[vk_frame])
		if res != .SUCCESS do trace.panic_log("QueueSubmit : ", res)

		sync.mutex_unlock(&__g_layer_mtx)
	}
	presentInfo := vk.PresentInfoKHR {
		sType = vk.StructureType.PRESENT_INFO_KHR,
		waitSemaphoreCount = 1,
		pWaitSemaphores = &vk_render_finished_semaphore[vk_frame][imageIndex],
		swapchainCount = 1,
		pSwapchains = &vk_swapchain,
		pImageIndices = &imageIndex,
	}

	res = vk.QueuePresentKHR(vk_present_queue, &presentInfo)

	if res == .ERROR_OUT_OF_DATE_KHR {
		vk_recreate_swap_chain()
		vk_frame = 0
		return
	} else if res == .SUBOPTIMAL_KHR {
		vk_frame = 0
		return
	} else if res == .ERROR_SURFACE_LOST_KHR {
		vk_recreate_surface()
		vk_recreate_swap_chain()
		vk_frame = 0
		return
	} else if size_updated {
		vk_recreate_swap_chain()
		vk_frame = 0
		return
	} else if res != .SUCCESS { trace.panic_log("QueuePresentKHR : ", res) }

	vk_frame = (vk_frame + 1) % MAX_FRAMES_IN_FLIGHT
	sync.sema_post(&g_wait_rendering_sem)
}

vk_create_sync_object :: proc() {
	for i in 0..<MAX_FRAMES_IN_FLIGHT {
		vk.CreateSemaphore(vk_device, &vk.SemaphoreCreateInfo{
			sType = vk.StructureType.SEMAPHORE_CREATE_INFO,
		}, nil, &vk_image_available_semaphore[i])

		vk_render_finished_semaphore[i] = mem.make_non_zeroed([]vk.Semaphore, int(swap_img_cnt))
		for j in 0..<int(swap_img_cnt) {
			vk.CreateSemaphore(vk_device, &vk.SemaphoreCreateInfo{
				sType = vk.StructureType.SEMAPHORE_CREATE_INFO,
			}, nil, &vk_render_finished_semaphore[i][j])
		}

		vk.CreateFence(vk_device, &vk.FenceCreateInfo{
			sType = vk.StructureType.FENCE_CREATE_INFO,
			flags = {vk.FenceCreateFlag.SIGNALED},
		}, nil, &vk_in_flight_fence[i])
	}
}

vk_clean_sync_object :: proc() {
	for i in 0..<MAX_FRAMES_IN_FLIGHT {
		vk.DestroySemaphore(vk_device, vk_image_available_semaphore[i], nil)
		for j in 0..<int(swap_img_cnt) {
			vk.DestroySemaphore(vk_device, vk_render_finished_semaphore[i][j], nil)
		}
		delete(vk_render_finished_semaphore[i])
		vk.DestroyFence(vk_device, vk_in_flight_fence[i], nil)
	}
}

vk_clean_swap_chain :: proc() {
	if vk_swapchain != 0 {
		for _, i in vk_frame_buffers {
			vk.DestroyFramebuffer(vk_device, vk_frame_buffers[i], nil)
			//vk.DestroyFramebuffer(vk_device, vkClearFrameBuffers[i], nil)
			vk.DestroyImageView(vk_device, vk_frame_buffer_image_views[i], nil)
		}

		texture_deinit(&vk_frame_depth_stencil_texture)
		when msaa_count > 1 {
			texture_deinit(&vk_msaa_frame_texture)
		}
		graphics_execute_ops()

		delete(vk_frame_buffers)
		//delete(vkClearFrameBuffers)
		delete(vk_frame_buffer_image_views)

		vk.DestroySwapchainKHR(vk_device, vk_swapchain, nil)
		vk_swapchain = 0
	}
}


vk_transition_image_layout :: proc(cmd:vk.CommandBuffer, image:vk.Image, mip_levels:u32, array_start:u32, array_layers:u32, old_layout:vk.ImageLayout, new_layout:vk.ImageLayout) {
	barrier := vk.ImageMemoryBarrier{
		sType = vk.StructureType.IMAGE_MEMORY_BARRIER,
		oldLayout = old_layout,
		newLayout = new_layout,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image = image,
		subresourceRange = {
			aspectMask = {.COLOR},
			baseMipLevel = 0,
			levelCount = mip_levels,
			baseArrayLayer = array_start,
			layerCount = array_layers
		}
	}
	
	srcStage : vk.PipelineStageFlags
	dstStage : vk.PipelineStageFlags

	if old_layout == .UNDEFINED && new_layout == .TRANSFER_DST_OPTIMAL {
		barrier.srcAccessMask = {}
		barrier.dstAccessMask = {.TRANSFER_WRITE}

		srcStage = {.TOP_OF_PIPE}
		dstStage = {.TRANSFER}
	} else if old_layout == .TRANSFER_DST_OPTIMAL && new_layout == .SHADER_READ_ONLY_OPTIMAL {
		barrier.srcAccessMask = {.TRANSFER_WRITE}
		barrier.dstAccessMask = {.SHADER_READ}

		srcStage = {.TRANSFER}
		dstStage = {.FRAGMENT_SHADER}
	} else if old_layout == .UNDEFINED && new_layout == .COLOR_ATTACHMENT_OPTIMAL {
		barrier.srcAccessMask = {}
		barrier.dstAccessMask = {.SHADER_READ}

		srcStage = {.TOP_OF_PIPE}
		dstStage = {.FRAGMENT_SHADER}
	} else if old_layout == .UNDEFINED && new_layout == .GENERAL {
		barrier.srcAccessMask = {}
		barrier.dstAccessMask = {.SHADER_READ, .SHADER_WRITE}

		srcStage = {.TOP_OF_PIPE}
		dstStage = {.FRAGMENT_SHADER}
	} else {
		trace.panic_log("unsupported layout transition!", old_layout, new_layout)
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

vk_record_command_buffer :: proc(cmd:^layer, _inheritanceInfo:vk.CommandBufferInheritanceInfo, vk_frame:int) {
	inheritanceInfo := _inheritanceInfo
	c := cmd.cmd[vk_frame]
	beginInfo := vk.CommandBufferBeginInfo {
		sType = vk.StructureType.COMMAND_BUFFER_BEGIN_INFO,
		flags = {vk.CommandBufferUsageFlag.RENDER_PASS_CONTINUE, vk.CommandBufferUsageFlag.ONE_TIME_SUBMIT},
		pInheritanceInfo = &inheritanceInfo,
	}

	res := vk.BeginCommandBuffer(c.__handle, &beginInfo)
	if res != .SUCCESS do trace.panic_log("BeginCommandBuffer : ", res)

	vp := vk.Viewport {
		x = 0.0,
		y = 0.0,
		width = f32(vk_extent_rotation.width),
		height = f32(vk_extent_rotation.height),
		minDepth = 0.0,
		maxDepth = 1.0,
	}
	vk.CmdSetViewport(c.__handle, 0, 1, &vp)

	sync.mutex_lock(&cmd.obj_lock)
	objs := mem.make_non_zeroed_slice([]^iobject, len(cmd.scene), context.temp_allocator)
	copy_slice(objs, cmd.scene[:])
	sync.mutex_unlock(&cmd.obj_lock)
	defer delete(objs, context.temp_allocator)
	
	first := true
	prev_area :Maybe(linalg.rect) = nil
	for viewport in __g_viewports {
		if first || prev_area != viewport.viewport_area {
			scissor :vk.Rect2D
			if viewport.viewport_area != nil {
				if viewport.viewport_area.?.top <= viewport.viewport_area.?.bottom {
					trace.panic_log("viewport.viewport_area.?.top <= viewport.viewport_area.?.bottom")
				}
				scissor = {
					offset = {x = i32(viewport.viewport_area.?.left), y = i32(viewport.viewport_area.?.top)},
					extent = {width = u32(viewport.viewport_area.?.right - viewport.viewport_area.?.left), height = u32(viewport.viewport_area.?.top - viewport.viewport_area.?.bottom)},
				}
			} else {
				scissor = {
					offset = {x = 0, y = 0},
					extent = vk_extent_rotation,
				}
			}
			vk.CmdSetScissor(c.__handle, 0, 1, &scissor)
			first = false
			prev_area = viewport.viewport_area
		}
		
		for obj in objs {
			iobject_draw(auto_cast obj, c, viewport)
		}
	}
	res = vk.EndCommandBuffer(c.__handle)
	if res != .SUCCESS do trace.panic_log("EndCommandBuffer : ", res)
}