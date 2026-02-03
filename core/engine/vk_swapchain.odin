#+private
package engine

import "base:library"
import "core:mem"
import "core:sync"
import "core:thread"
import vk "vendor:vulkan"
import "core:log"
import "base:runtime"


// ============================================================================
// Surface - Create Surface
// ============================================================================

vk_create_surface :: vk_recreate_surface

vk_recreate_surface :: proc() {
	when library.is_android {
		vulkan_android_start()
	} else {// !ismobile
		glfw_vulkan_start()
	}
}

// ============================================================================
// Swapchain - Initialize Swapchain Properties
// ============================================================================

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
			log.infof("SYSLOG : vulkan swapchain format : %s, colorspace : %s\n", f.format, f.colorSpace)
			vk_fmt = f
			break;
		}
	}
	if vk_fmt.format == .UNDEFINED do log.panic("Xfit vulkan unsupported format\n")

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

	log.infof("SYSLOG : depth format : %s\n", depth_fmt)
	log.infof("SYSLOG : optimal format supports\n")
	log.infof("vkDepthHasOptimal : %t\n", vkDepthHasOptimal)
	log.infof("vkDepthHasTransferSrcOptimal : %t\n", vkDepthHasTransferSrcOptimal)
	log.infof("vkDepthHasTransferDstOptimal : %t\n", vkDepthHasTransferDstOptimal)
	log.infof("vkDepthHasSampleOptimal : %t\n", vkDepthHasSampleOptimal)
	log.infof("vkColorHasAttachOptimal : %t\n", vkColorHasAttachOptimal)
	log.infof("vkColorHasSampleOptimal : %t\n", vkColorHasSampleOptimal)
	log.infof("vkColorHasTransferSrcOptimal : %t\n", vkColorHasTransferSrcOptimal)
	log.infof("vkColorHasTransferDstOptimal : %t\n", vkColorHasTransferDstOptimal)
}


// ============================================================================
// Swapchain - Create Swapchain and Image Views
// ============================================================================

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
		if program_start do log.infof("SYSLOG : vulkan present mode fifo_khr vsync double\n")
	} else {
		if __v_sync == .Triple {
			for p in vkPresentModes {
				if p == .MAILBOX {
					if program_start do log.infof("SYSLOG : vulkan present mode mailbox_khr vsync triple\n")
					vkPresentMode = p
					break;
				}
			}
		}
		//if mailbox is not supported or not set, use immediate
		if vkPresentMode != .MAILBOX {
			for p in vkPresentModes {
				if p == .IMMEDIATE {
					if program_start {
						if __v_sync == .Triple do log.infof("SYSLOG : vulkan present mode immediate_khr mailbox_khr instead(vsync triple -> none)\n")
						else do log.infof("SYSLOG : vulkan present mode immediate_khr vsync none\n")
					} 
					vkPresentMode = p
					break;
				}
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
		log.panic("not supports supportedCompositeAlpha\n")
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
	queueFamiliesIndices := [2]u32{vk_graphics_family_index, vk_present_family_index}
	if vk_graphics_family_index != vk_present_family_index {
		swapChainCreateInfo.imageSharingMode = .CONCURRENT
		swapChainCreateInfo.queueFamilyIndexCount = 2
		swapChainCreateInfo.pQueueFamilyIndices = raw_data(queueFamiliesIndices[:])
	}

	res := vk.CreateSwapchainKHR(vk_device, &swapChainCreateInfo, nil, &vk_swapchain)
	if res != .SUCCESS {
		log.panicf("res = vk.CreateSwapchainKHR(vk_device, &swapChainCreateInfo, nil, &vk_swapchain) : %s\n", res)
	}

	vk.GetSwapchainImagesKHR(vk_device, vk_swapchain, &swap_img_cnt, nil)
	swapImgs:= mem.make_non_zeroed([]vk.Image, swap_img_cnt, context.temp_allocator)
	defer delete(swapImgs, context.temp_allocator)
	vk.GetSwapchainImagesKHR(vk_device, vk_swapchain, &swap_img_cnt, &swapImgs[0])

	vk_frame_buffers = mem.make_non_zeroed([]vk.Framebuffer, swap_img_cnt)
	vk_frame_buffer_image_views = mem.make_non_zeroed([]vk.ImageView, swap_img_cnt)
	
	texture_init_depth_stencil(&vk_frame_depth_stencil_texture, vk_extent_rotation.width, vk_extent_rotation.height)
	when msaa_count > 1 {
		texture_init_msaa(&vk_msaa_frame_texture, vk_extent_rotation.width, vk_extent_rotation.height)
	}

	refresh_pre_matrix()
	vk_op_execute_no_async()

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
		if res != .SUCCESS do log.panicf("res = vk.CreateImageView(vk_device, &imageViewCreateInfo, nil, &vk_frame_buffer_image_views[i]) : %s\n", res)


		vk_frame_depth_stencil_texture_res, ok := graphics_get_resource(&vk_frame_depth_stencil_texture).(^texture_resource)
		if !ok do log.panic("vk_frame_depth_stencil_texture not found\n")
		when msaa_count == 1 {
			frameBufferCreateInfo := vk.FramebufferCreateInfo{
				sType = vk.StructureType.FRAMEBUFFER_CREATE_INFO,
				renderPass = vk_render_pass,
				attachmentCount = 2,
				pAttachments = &([]vk.ImageView{vk_frame_buffer_image_views[i], vk_frame_depth_stencil_texture_res.img_view, })[0],
				width = vk_extent_rotation.width,
				height = vk_extent_rotation.height,
				layers = 1,
			}
		} else {
			vk_msaa_frame_texture_res, ok2 := graphics_get_resource(&vk_msaa_frame_texture).(^texture_resource)
			if !ok2 do log.panic("vk_msaa_frame_texture not found\n")
			frameBufferCreateInfo := vk.FramebufferCreateInfo{
				sType = vk.StructureType.FRAMEBUFFER_CREATE_INFO,
				renderPass = vk_render_pass,
				attachmentCount = 3,
				pAttachments = &([]vk.ImageView{vk_msaa_frame_texture_res.img_view,vk_frame_depth_stencil_texture_res.img_view, vk_frame_buffer_image_views[i]})[0],
				width = vk_extent_rotation.width,
				height = vk_extent_rotation.height,
				layers = 1,
			}
		}
		res = vk.CreateFramebuffer(vk_device, &frameBufferCreateInfo, nil, &vk_frame_buffers[i])
		if res != .SUCCESS do log.panicf("res = vk.CreateFramebuffer(vk_device, &frameBufferCreateInfo, nil, &vk_frame_buffers[i]) : %s\n", res)
	}

	return true
}


// ============================================================================
// Swapchain - Recreate Swapchain
// ============================================================================

vk_recreate_swap_chain :: proc() {
	if vk_device == nil {
		return
	}
	for 0 < thread.pool_num_outstanding(&vk_allocator_thread_pool) {
		thread.yield()
	}
	sync.mutex_lock(&full_screen_mtx)

	vk_wait_device_idle()
	vk_op_execute_no_async()
	vk_destroy_resources(true)
	

	when library.is_android {//? ANDROID ONLY
		vulkan_android_start()
	}

	vk_clean_swap_chain()

	if !vk_create_swap_chain_and_image_views() {
		sync.mutex_unlock(&full_screen_mtx)
		return
	}

	size_updated = false

	sync.mutex_unlock(&full_screen_mtx)

	layer_size_all()
	size()
	if len(__g_layer) > 0 {
		//thread pool 사용해서 각각 처리
		size_task_data :: struct {
			cmd: ^layer,
			allocator: runtime.Allocator,
		}
		
		size_task_proc :: proc(task: thread.Task) {
			data := cast(^size_task_data)task.data
			for obj in data.cmd.scene {
				iobject_size(auto_cast obj)
			}
			free(data, data.allocator)
		}

		// Add each layer as a task to thread pool
		for cmd in __g_layer {
			data := new(size_task_data, context.temp_allocator)
			data.cmd = cmd
			data.allocator = context.temp_allocator
			thread.pool_add_task(&g_thread_pool, context.allocator, size_task_proc, data)
		}
		thread.pool_wait_all(&g_thread_pool)
	}
}


// ============================================================================
// Swapchain - Clean Swapchain
// ============================================================================

vk_clean_swap_chain :: proc() {
	if vk_swapchain != 0 {
		for _, i in vk_frame_buffers {
			vk.DestroyFramebuffer(vk_device, vk_frame_buffers[i], nil)
			vk.DestroyImageView(vk_device, vk_frame_buffer_image_views[i], nil)
		}

		texture_deinit(&vk_frame_depth_stencil_texture)
		when msaa_count > 1 {
			texture_deinit(&vk_msaa_frame_texture)
		}
		vk_op_execute_no_async()
		vk_destroy_resources(true)

		delete(vk_frame_buffers)
		delete(vk_frame_buffer_image_views)

		vk.DestroySwapchainKHR(vk_device, vk_swapchain, nil)
		vk_swapchain = 0
	}
}
