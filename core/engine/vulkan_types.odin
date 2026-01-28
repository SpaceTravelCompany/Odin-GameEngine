#+private
package engine

import "base:library"
import "base:runtime"
import "core:dynlib"
import "core:mem"
import "core:sync"
import vk "vendor:vulkan"


// ============================================================================
// Constants
// ============================================================================

@(rodata)
DEVICE_EXTENSIONS: [3]cstring = {vk.KHR_SWAPCHAIN_EXTENSION_NAME, vk.EXT_FULL_SCREEN_EXCLUSIVE_EXTENSION_NAME, vk.KHR_SHADER_CLOCK_EXTENSION_NAME}

@(rodata)
INSTANCE_EXTENSIONS: [2]cstring = {
	vk.KHR_GET_SURFACE_CAPABILITIES_2_EXTENSION_NAME,
	vk.KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME,
}

@(rodata)
LAYERS: [1]cstring = {"VK_LAYER_KHRONOS_validation"}

msaa_count :: 1

when msaa_count == 4 {
	VK_SAMPLE_COUNT_FLAGS :: vk.SampleCountFlags{._4}
} else when msaa_count == 8 {
	VK_SAMPLE_COUNT_FLAGS :: vk.SampleCountFlags{._8}
} else when msaa_count == 1 {
	VK_SAMPLE_COUNT_FLAGS :: vk.SampleCountFlags{._1}
} else {
	#assert("invalid msaa_count")
}


// ============================================================================
// Global Variables - Instance & Device
// ============================================================================

vk_device: vk.Device
vk_instance: vk.Instance
vk_library: dynlib.Library
vk_debug_utils_messenger: vk.DebugUtilsMessengerEXT

vk_physical_device: vk.PhysicalDevice
vk_physical_mem_prop: vk.PhysicalDeviceMemoryProperties
vk_physical_prop: vk.PhysicalDeviceProperties

vk_graphics_queue: vk.Queue
vk_present_queue: vk.Queue
vk_queue_mutex: sync.Mutex

vk_graphics_family_index: u32 = max(u32)
vk_present_family_index: u32 = max(u32)

vk_get_instance_proc_addr: proc "system" (
	_instance: vk.Instance,
	_name: cstring,
) -> vk.ProcVoidFunction

DEVICE_EXTENSIONS_CHECK: [len(DEVICE_EXTENSIONS)]bool
INSTANCE_EXTENSIONS_CHECK: [len(INSTANCE_EXTENSIONS)]bool
LAYERS_CHECK: [len(LAYERS)]bool

vulkan_version : VULKAN_VERSION


// ============================================================================
// Global Variables - Surface & Swapchain
// ============================================================================

vk_surface: vk.SurfaceKHR
vk_swapchain: vk.SwapchainKHR

vk_fmts: []vk.SurfaceFormatKHR
vk_fmt: vk.SurfaceFormatKHR = {
	format = .UNDEFINED,
	colorSpace = .SRGB_NONLINEAR
}
vkPresentModes: []vk.PresentModeKHR
vkPresentMode: vk.PresentModeKHR
vk_surface_cap: vk.SurfaceCapabilitiesKHR
vk_extent: vk.Extent2D
vk_extent_rotation: vk.Extent2D

is_released_full_screen_ex := true


// ============================================================================
// Global Variables - Format Support Flags
// ============================================================================

vkDepthHasOptimal := false
vkDepthHasTransferSrcOptimal := false
vkDepthHasTransferDstOptimal := false
vkDepthHasSampleOptimal := false

vkColorHasAttachOptimal := false
vkColorHasSampleOptimal := false
vkColorHasTransferSrcOptimal := false
vkColorHasTransferDstOptimal := false


// ============================================================================
// Global Variables - Render Pass
// ============================================================================

vk_render_pass: vk.RenderPass
vk_render_pass_clear: vk.RenderPass
vk_render_pass_sample: vk.RenderPass
vk_render_pass_sample_clear: vk.RenderPass


// ============================================================================
// Global Variables - Framebuffers & Textures
// ============================================================================

vk_frame_buffers: []vk.Framebuffer
vk_frame_depth_stencil_texture: texture
vk_msaa_frame_texture: texture
vk_frame_buffer_image_views: []vk.ImageView


// ============================================================================
// Global Variables - Sync Objects
// ============================================================================

vk_image_available_semaphore: [MAX_FRAMES_IN_FLIGHT]vk.Semaphore
vk_render_finished_semaphore: [MAX_FRAMES_IN_FLIGHT][]vk.Semaphore
vk_in_flight_fence: [MAX_FRAMES_IN_FLIGHT]vk.Fence


// ============================================================================
// Global Variables - Command Buffers
// ============================================================================

vk_cmd_pool: vk.CommandPool
vk_cmd_buffer: [MAX_FRAMES_IN_FLIGHT]vk.CommandBuffer


// ============================================================================
// Global Variables - Pipeline States
// ============================================================================

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

vkColorAlphaBlendingExternal := vk.PipelineColorBlendStateCreateInfoInit(__vkColorAlphaBlendingExternalState[:1])
vkNoBlending := vk.PipelineColorBlendStateCreateInfoInit(__vkNoBlendingState[:1])
vkCopyBlending := vk.PipelineColorBlendStateCreateInfoInit(__vkNoBlendingState[:1])


// ============================================================================
// Helper Functions
// ============================================================================

validation_layer_support :: #force_inline proc "contextless" () -> bool {return LAYERS_CHECK[0]}
vk_khr_portability_enumeration_support :: #force_inline proc "contextless" () -> bool {return INSTANCE_EXTENSIONS_CHECK[1]}
VK_EXT_full_screen_exclusive_support :: #force_inline proc "contextless" () -> bool {return DEVICE_EXTENSIONS_CHECK[1]}
