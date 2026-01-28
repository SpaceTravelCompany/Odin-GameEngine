#+private
package engine

import "core:debug/trace"
import "core:dynlib"
import "core:sync"
import vk "vendor:vulkan"


// ============================================================================
// Public API - Start & Destroy
// ============================================================================

vk_start :: proc() {
	vk_create_instance()
	vk_create_surface()
	vk_select_physical_device()
	vk_create_logical_device()

	vk_init_block_len()
	vk_allocator_init()

	graphics_create()

	init_swap_chain()
	vk_create_render_pass()

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

	init_pipelines()

	vk_create_swap_chain_and_image_views()
	vk_create_sync_object()

	//graphics_wait_all_ops()//reset wait

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


// ============================================================================
// Public API - Wait Functions
// ============================================================================

vk_wait_device_idle :: proc "contextless" () {
	res := vk.DeviceWaitIdle(vk_device)
	if res != .SUCCESS do trace.panic_log("vk_wait_device_idle : ", res )
}

vk_wait_graphics_idle :: proc "contextless" () {
	sync.mutex_lock(&vk_queue_mutex)
	defer sync.mutex_unlock(&vk_queue_mutex)
	res := vk.QueueWaitIdle(vk_graphics_queue)
	if res != .SUCCESS do trace.panic_log("vk_wait_graphics_idle : ", res )
}

vk_wait_present_idle :: proc "contextless" () {
	res := vk.QueueWaitIdle(vk_present_queue)
	if res != .SUCCESS do trace.panic_log("vk_wait_present_idle : ", res )
}
