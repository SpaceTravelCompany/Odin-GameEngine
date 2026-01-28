#+private
package engine

import "core:debug/trace"
import "core:math/linalg"
import "core:mem"
import "core:sync"
import "core:thread"
import vk "vendor:vulkan"


// ============================================================================
// Command Buffer - Transition Image Layout
// ============================================================================

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


// ============================================================================
// Command Buffer - Record Command Buffer
// ============================================================================

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

	objs := mem.make_non_zeroed_slice([]^iobject, len(cmd.scene), context.temp_allocator)
	copy_slice(objs, cmd.scene[:])
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


// ============================================================================
// Sync Objects - Create
// ============================================================================

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


// ============================================================================
// Sync Objects - Clean
// ============================================================================

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


// ============================================================================
// Frame - Draw Frame
// ============================================================================

vk_frame: int = 0

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
	
	vk_destroy_resources()

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
		thread.pool_wait_all(&g_thread_pool)
		
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

		sync.mutex_lock(&vk_queue_mutex)
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

		sync.mutex_lock(&vk_queue_mutex)
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
	sync.mutex_unlock(&vk_queue_mutex)

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
