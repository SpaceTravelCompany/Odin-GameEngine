#+private
package engine

import "base:runtime"
import "base:intrinsics"
import "core:mem"
import "core:mem/virtual"
import "core:sync"
import "core:thread"
import "core:fmt"
import vk "vendor:vulkan"
import "core:log"


// ============================================================================
// Public API - Allocator
// ============================================================================

vk_def_allocator :: proc() -> runtime.Allocator {
	return __vk_def_allocator
}

vk_init_block_len :: proc() {
	_ChangeSize :: #force_inline proc(heapSize: vk.DeviceSize) {
		if heapSize < mem.Gigabyte {
			vkMemBlockLen /= 16
			vkMemSpcialBlockLen /= 16
		} else if heapSize < 2 * mem.Gigabyte {
			vkMemBlockLen /= 8
			vkMemSpcialBlockLen /= 8
		} else if heapSize < 4 * mem.Gigabyte {
			vkMemBlockLen /= 4
			vkMemSpcialBlockLen /= 4
		} else if heapSize < 8 * mem.Gigabyte {
			vkMemBlockLen /= 2
			vkMemSpcialBlockLen /= 2
		}
	}

	change := false
	mainHeapIdx: u32 = max(u32)
	for h, i in vk_physical_mem_prop.memoryHeaps[:vk_physical_mem_prop.memoryHeapCount] {
		if .DEVICE_LOCAL in h.flags {
			_ChangeSize(h.size)
			change = true
			log.infof("SYSLOG : Vulkan Graphic Card Dedicated Memory Block %d MB Dedicated Memory : %d MB\n",
				vkMemBlockLen / mem.Megabyte,
				h.size / mem.Megabyte,
			)
			mainHeapIdx = auto_cast i
			break
		}
	}
	if !change {
		_ChangeSize(vk_physical_mem_prop.memoryHeaps[0].size)
		log.infof(
			"SYSLOG : Vulkan No Graphic Card System Memory Block %d MB\nSystem Memory : %d MB\n",
			vkMemBlockLen / mem.Megabyte,
			vk_physical_mem_prop.memoryHeaps[0].size / mem.Megabyte,
		)
		mainHeapIdx = 0
	}

	vk_non_coherent_atom_size = auto_cast vk_physical_prop.limits.nonCoherentAtomSize

	reduced := false
	for t, i in vk_physical_mem_prop.memoryTypes[:vk_physical_mem_prop.memoryTypeCount] {
		if t.propertyFlags >= {.DEVICE_LOCAL, .HOST_CACHED, .HOST_VISIBLE} {
			vkSupportCacheLocal = true
			log.info("SYSLOG : Vulkan Device Supported Cache Local Memory\n")
		} else if t.propertyFlags >= {.DEVICE_LOCAL, .HOST_COHERENT, .HOST_VISIBLE} {
			vkSupportNonCacheLocal = true
			log.info("SYSLOG : Vulkan Device Supported Non Cache Local Memory\n")
		} else {
			continue
		}
		if mainHeapIdx != t.heapIndex && !reduced {
			vkMemSpcialBlockLen /= min(
				16,
				max(
					1,
					vk_physical_mem_prop.memoryHeaps[mainHeapIdx].size /
					vk_physical_mem_prop.memoryHeaps[t.heapIndex].size,
				),
			)
			reduced = true
		}
	}

	gVkMinUniformBufferOffsetAlignment = vk_physical_prop.limits.minUniformBufferOffsetAlignment
}

vk_allocator_init :: proc() {
	__vk_def_allocator = context.allocator

	gVkMemBufs = mem.make_non_zeroed([dynamic]^vk_mem_buffer, vk_def_allocator())

	gVkMemIdxCnts = mem.make_non_zeroed([]int, vk_physical_mem_prop.memoryTypeCount, vk_def_allocator())
	mem.zero_slice(gVkMemIdxCnts)

	__init :: proc() {
		cmdPoolInfo := vk.CommandPoolCreateInfo {
			sType            = vk.StructureType.COMMAND_POOL_CREATE_INFO,
			flags = {},
			queueFamilyIndex = vk_graphics_family_index,
		}
		res := vk.CreateCommandPool(vk_device, &cmdPoolInfo, nil, &thread_cmdPool)
		if res != .SUCCESS do log.panicf("vk.CreateCommandPool failed in thread init: %s\n", res)

		vk.CreateFence(vk_device, &vk.FenceCreateInfo{
				sType = vk.StructureType.FENCE_CREATE_INFO,
				flags = {vk.FenceCreateFlag.SIGNALED},
			}, nil, &vk_allocator_fence)

		cmdAllocInfo := vk.CommandBufferAllocateInfo {
			sType              = vk.StructureType.COMMAND_BUFFER_ALLOCATE_INFO,
			commandBufferCount = 1,
			level              = .PRIMARY,
			commandPool        = thread_cmdPool,
		}
		res = vk.AllocateCommandBuffers(vk_device, &cmdAllocInfo, &thread_cmd)
		if res != .SUCCESS do log.panicf("vk.AllocateCommandBuffers failed: %s\n", res)	
	}

	// Thread initialization: create command pool for each thread
	vk_thread_init_proc :: proc(thread: ^thread.Thread, user_data: rawptr) {
		__init()
	}
	__init()

	// Thread finalization: destroy command pool for each thread
	vk_thread_fini_proc :: proc(thread: ^thread.Thread, user_data: rawptr) {
		vk.DestroyCommandPool(vk_device, thread_cmdPool, nil)
		vk.DestroyFence(vk_device, vk_allocator_fence, nil)
	}

	thread.pool_init(&vk_allocator_thread_pool, __vk_def_allocator, get_processor_core_len(), vk_thread_init_proc, nil, vk_thread_fini_proc, nil)
	thread.pool_start(&vk_allocator_thread_pool)

	opQueue = mem.make_non_zeroed([dynamic]OpNode, vk_def_allocator())
	opDestroyQueues = mem.make_non_zeroed([dynamic]destroy_node, vk_def_allocator())

	gUniforms = mem.make_non_zeroed([dynamic]vk_uniform_alloc, vk_def_allocator())
	gTempUniforms = mem.make_non_zeroed([dynamic]vk_temp_uniform_struct, vk_def_allocator())
	gNonInsertedUniforms = mem.make_non_zeroed([dynamic]vk_temp_uniform_struct, vk_def_allocator())

	gMapResource = make_map(map[rawptr][dynamic]union_resource, vk_def_allocator())
}



vk_allocator_destroy :: proc() {
	thread.pool_wait_all(&vk_allocator_thread_pool)
	thread.pool_join(&vk_allocator_thread_pool)
	thread.pool_destroy(&vk_allocator_thread_pool)

	vk.DestroyCommandPool(vk_device, thread_cmdPool, nil)
	vk.DestroyFence(vk_device, vk_allocator_fence, nil)

	for b in gVkMemBufs {
		vk_mem_buffer_Deinit2(b)
		free(b, vk_def_allocator())
	}
	delete(gVkMemBufs)

	for _, &value in gDesciptorPools {
		for i in value {
			vk.DestroyDescriptorPool(vk_device, i.pool, nil)
		}
		delete(value)
	}
	for i in gUniforms {
		delete(i.uniforms)
	}

	delete(gDesciptorPools)
	delete(gUniforms)
	delete(gTempUniforms)
	delete(gNonInsertedUniforms)
	delete(opQueue)
	delete(opDestroyQueues)
	delete(gMapResource)
	delete(gVkMemIdxCnts, vk_def_allocator())
}

vk_find_mem_type :: proc "contextless" (
	typeFilter: u32,
	memProp: vk.MemoryPropertyFlags,
) -> (
	memType: u32,
	success: bool = true,
) {
	for i: u32 = 0; i < vk_physical_mem_prop.memoryTypeCount; i += 1 {
		if ((typeFilter & (1 << i)) != 0) &&
		   (memProp <= vk_physical_mem_prop.memoryTypes[i].propertyFlags) {
			memType = i
			return
		}
	}
	success = false
	return
}

// ============================================================================
// Public API - Op Execute
// ============================================================================

vk_op_execute :: proc() {
	opExecQueue := __vk_op_execute_in()
	if opExecQueue == nil {
		return
	}

	// Execute GPU commands asynchronously in vk_allocator_thread_pool
	thread.pool_add_task(&vk_allocator_thread_pool, vk_def_allocator(), vk_exec_gpu_commands_task, opExecQueue)
}

test_mtx:sync.Mutex

__vk_op_execute_in :: proc() -> ^[dynamic]OpNode {
	if !sync.mutex_try_lock(&test_mtx) {
		runtime.debug_trap()
	}
	defer sync.mutex_unlock(&test_mtx)

	sync.atomic_mutex_lock(&gQueueMtx)
	if len(opQueue) == 0 {
		sync.atomic_mutex_unlock(&gQueueMtx)
		return nil
	}
	opExecQueue := new([dynamic]OpNode, vk_def_allocator())
	opExecQueue^ = mem.make_non_zeroed([dynamic]OpNode, len(opQueue), vk_def_allocator())

	mem.copy_non_overlapping(&opExecQueue[0], raw_data(opQueue), len(opQueue) * size_of(OpNode))
	clear(&opQueue)
	sync.atomic_mutex_unlock(&gQueueMtx)

	opMapCopyQueue := mem.make_non_zeroed([dynamic]OpNode, context.temp_allocator)
	defer delete(opMapCopyQueue)

	for &node in opExecQueue {
		#partial switch n in node {
		case OpMapCopy:
			non_zero_append(&opMapCopyQueue, node)
			node = nil
		}
	}

	for node in opExecQueue {
		#partial switch n in node {
		case OpCreateBuffer:
			executeCreateBuffer(opExecQueue, n.src, n.data, n.allocator)
		case OpCreateTexture:
			executeCreateTexture(opExecQueue, n.src, n.data, n.allocator)
		case:
			continue
		}
	}

	for node in opExecQueue {
		#partial switch n in node {
		case OpReleaseUniform:
			executeReleaseUniform(opExecQueue, n.src)
		case:
			continue
		}
	}

	if len(gTempUniforms) > 0 {
		if len(gUniforms) == 0 {
			create_new_uniform_buffer(opExecQueue, gTempUniforms[:])
		} else {
			for &t, i in gTempUniforms {
				inserted := false
				out: for &g, i2 in gUniforms {
					if g.buf == 0 do continue
					outN: for i3 := 0; i3 < len(g.uniforms); i3 += 1 {
						if g.uniforms[i3] == nil {
							if i3 == 0 {
								for i4 in 1 ..< len(g.uniforms) {
									if g.uniforms[i4] != nil {
										if g.uniforms[i4].g_uniform_indices[2] >= t.size {
											g.uniforms[i3] = t.uniform
											assign_uniform_to_buffer(opExecQueue, &t, &g, i2, i3, 0)
											inserted = true
											break out
										}
										i3 = i4
										break outN
									}
								}
							} else if i3 == len(g.uniforms) - 1 {
								if g.max_size - g.size >= t.size {
									g.uniforms[i3] = t.uniform
									assign_uniform_to_buffer(opExecQueue, &t, &g, i2, i3, g.size)
									g.size += t.size
									inserted = true
									break out
								}
							} else {
								for i4 in i3 + 1 ..< len(g.uniforms) {
									if g.uniforms[i4] != nil {
										prev_end := g.uniforms[i3 - 1].g_uniform_indices[2] + g.uniforms[i3 - 1].g_uniform_indices[3]
										if g.uniforms[i4].g_uniform_indices[2] - prev_end >= t.size {
											g.uniforms[i3] = t.uniform
											assign_uniform_to_buffer(opExecQueue, &t, &g, i2, i3, prev_end)
											inserted = true
											break out
										}
										i3 = i4
										continue outN
									}
								}
								if g.max_size - g.size >= t.size {
									prev_end := g.uniforms[i3 - 1].g_uniform_indices[2] + g.uniforms[i3 - 1].g_uniform_indices[3]
									g.uniforms[i3] = t.uniform
									assign_uniform_to_buffer(opExecQueue, &t, &g, i2, i3, prev_end)
									g.size += t.size
									inserted = true
									break out
								}
								break outN
							}
						}
					}
					if g.max_size - g.size >= t.size {
						non_zero_append(&g.uniforms, t.uniform)
						prev_end := g.uniforms[len(g.uniforms) - 2].g_uniform_indices[2] + g.uniforms[len(g.uniforms) - 2].g_uniform_indices[3]
						assign_uniform_to_buffer(opExecQueue, &t, &g, i2, len(g.uniforms) - 1, prev_end)
						g.size += t.size
						inserted = true
						break out
					}
				}
				if !inserted {
					non_zero_append(&gNonInsertedUniforms, t)
				}
			}
			if len(gNonInsertedUniforms) > 0 {
				create_new_uniform_buffer(opExecQueue, gNonInsertedUniforms[:])
				clear(&gNonInsertedUniforms)
			}
		}
		clear(&gTempUniforms)
	}
	for &node in opMapCopyQueue {
		non_zero_append(opExecQueue, node)
	}

	return opExecQueue
}

vk_op_execute_no_async :: proc() {
	opExecQueue := __vk_op_execute_in()
	if opExecQueue == nil {
		return
	}

	task := thread.Task{
		data = opExecQueue,
	}
	vk_exec_gpu_commands_task(task)
}

vk_destroy_resources :: proc(destroy_all := false) {
	sync.mutex_lock(&opDestroyQueueMtx)
	defer sync.mutex_unlock(&opDestroyQueueMtx)

	for i := 0; i < len(opDestroyQueues); {
		nodes := &opDestroyQueues[i]
		if nodes.stack_count >= MAX_FRAMES_IN_FLIGHT || destroy_all {
			for &node in nodes.op {
				#partial switch n in node {
				case OpDestroyBuffer:
					executeDestroyBuffer(n.src)
				case OpDestroyTexture:
					executeDestroyTexture(n.src)
				case OpCopyBuffer:
					executeDestroyBuffer(n.src)
					if n.allocator != nil do delete(n.data, n.allocator.?)
				case OpCopyBufferToTexture:
					executeDestroyBuffer(n.src)
					if n.allocator != nil do delete(n.data, n.allocator.?)
				}
			}
			delete(nodes.op)
			ordered_remove(&opDestroyQueues, i)
		} else {
			nodes.stack_count += 1
			i += 1
		}
	}
}

vk_exec_gpu_commands_task :: proc(task: thread.Task) {
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena, context.allocator, context.allocator)
	defer mem.dynamic_arena_destroy(&arena)
	arena_allocator := mem.dynamic_arena_allocator(&arena)

	opExecQueue :^[dynamic]OpNode = (^[dynamic]OpNode)(task.data)
	defer {
		delete(opExecQueue^)
		free(opExecQueue, vk_def_allocator())
	}
	if len(opExecQueue) == 0 {
		return
	}

	opMapQueue := mem.make_non_zeroed([dynamic]OpNode, arena_allocator)

	memBufT: ^vk_mem_buffer = nil
	save_to_map_queue(&memBufT, opExecQueue[:], &opMapQueue)
	for len(opMapQueue) > 0 {
		vk_mem_buffer_MapCopyexecute(memBufT, opMapQueue[:])
		clear(&opMapQueue)
		memBufT = nil
		save_to_map_queue(&memBufT, opExecQueue[:], &opMapQueue)
	}

	haveCmds := false
	gVkUpdateDesciptorSetList := mem.make_non_zeroed([dynamic]vk.WriteDescriptorSet, arena_allocator)
	for node in opExecQueue {
		#partial switch n in node {
		case Op__UpdateDescriptorSet:
			execute_update_descriptor_set(n.set, &gVkUpdateDesciptorSetList, arena_allocator)
		case OpCopyBuffer:
			haveCmds = true
		case OpCopyBufferToTexture:
			haveCmds = true
		}
	}

	if len(gVkUpdateDesciptorSetList) > 0 {
		vk.UpdateDescriptorSets(
			vk_device,
			auto_cast len(gVkUpdateDesciptorSetList),
			raw_data(gVkUpdateDesciptorSetList),
			0,
			nil,
		)
	}

	if haveCmds {
		beginInfo := vk.CommandBufferBeginInfo {
			flags = {.ONE_TIME_SUBMIT},
			sType = vk.StructureType.COMMAND_BUFFER_BEGIN_INFO,
		}
		res := vk.ResetCommandPool(vk_device, thread_cmdPool, {})
		if res != .SUCCESS do log.panicf("res := vk.ResetCommandPool(vk_device, thread_cmdPool, {}) : %s\n", res)
		res = vk.BeginCommandBuffer(thread_cmd, &beginInfo)
		if res != .SUCCESS do log.panicf("res := vk.BeginCommandBuffer(cmd, &beginInfo) : %s\n", res)

		for node in opExecQueue {
			#partial switch n in node {
			case OpCopyBuffer:
				execute_copy_buffer(thread_cmd, n.src, n.target)
			case OpCopyBufferToTexture:
				execute_copy_buffer_to_texture(thread_cmd, n.src, n.target)
			}
		}

		res = vk.EndCommandBuffer(thread_cmd)
		if res != .SUCCESS do log.panicf("res := vk.EndCommandBuffer(cmd) : %s\n", res)

		submitInfo := vk.SubmitInfo {
			commandBufferCount = 1,
			pCommandBuffers    = &thread_cmd,
			sType              = .SUBMIT_INFO,
		}
		vk.ResetFences(vk_device, 1, &vk_allocator_fence)
		sync.mutex_lock(&vk_queue_mutex)
		res = vk.QueueSubmit(vk_graphics_queue, 1, &submitInfo, vk_allocator_fence)
		if res != .SUCCESS do log.panicf("res := vk.QueueSubmit(vk_graphics_queue, 1, &submitInfo, 0) : %s\n", res)
		sync.mutex_unlock(&vk_queue_mutex)

		vk.WaitForFences(vk_device, 1, &vk_allocator_fence, true, max(u64))
		if res != .SUCCESS do log.panicf("res := vk.WaitForFences(vk_device, 1, &vk_allocator_fence, true, max(u64)) : %s\n", res)
	}

	sync.mutex_lock(&gMapResourceMtx)
	for node in opExecQueue {
		#partial switch n in node {
		case OpCreateBuffer:
			n.src.completed = true
		case OpCreateTexture:
			n.src.completed = true
		case OpDestroyBuffer:
			graphics_pop_resource(n.self, n.src, false)
		case OpDestroyTexture:
			graphics_pop_resource(n.self, n.src, false)
		}
	}
	sync.mutex_unlock(&gMapResourceMtx)

	sync.mutex_lock(&opDestroyQueueMtx)
	nodes := mem.make_non_zeroed([dynamic]OpNode, vk_def_allocator())
	non_zero_append(&opDestroyQueues, destroy_node{op = nodes, stack_count = MAX_FRAMES_IN_FLIGHT})
	for &node in opExecQueue {
		#partial switch &n in node {
		case OpCopyBuffer:
			non_zero_append(&opDestroyQueues[len(opDestroyQueues) - 1].op, node)
		case OpCopyBufferToTexture:
			non_zero_append(&opDestroyQueues[len(opDestroyQueues) - 1].op, node)
		}
	}
	if len(opDestroyQueues[len(opDestroyQueues) - 1].op) == 0 {
		delete(opDestroyQueues[len(opDestroyQueues) - 1].op)
		non_zero_resize(&opDestroyQueues, len(opDestroyQueues) - 1)
	}
	non_zero_append(&opDestroyQueues, destroy_node{op = nodes, stack_count = 0})
	for &node in opExecQueue {
		#partial switch &n in node {
		case OpDestroyBuffer:
			non_zero_append(&opDestroyQueues[len(opDestroyQueues) - 1].op, node)
		case OpDestroyTexture:
			non_zero_append(&opDestroyQueues[len(opDestroyQueues) - 1].op, node)
		}
	}
	if len(opDestroyQueues[len(opDestroyQueues) - 1].op) == 0 {
		delete(opDestroyQueues[len(opDestroyQueues) - 1].op)
		non_zero_resize(&opDestroyQueues, len(opDestroyQueues) - 1)
	}
	sync.mutex_unlock(&opDestroyQueueMtx)

	for {
		thread.pool_pop_done(&vk_allocator_thread_pool) or_break
	}
}


// ============================================================================
// Public API - Texture Format Conversion
// ============================================================================

/*
Converts a texture format to a Vulkan format

Inputs:
- t: The texture format to convert

Returns:
- The corresponding Vulkan format
*/
@(require_results)
texture_fmt_to_vk_fmt :: proc "contextless" (t: texture_fmt) -> vk.Format {
	switch t {
	case .DefaultColor:
		return get_graphics_origin_format()
	case .DefaultDepth:
		return texture_fmt_to_vk_fmt(depth_fmt)
	case .R8G8B8A8Unorm:
		return .R8G8B8A8_UNORM
	case .B8G8R8A8Unorm:
		return .B8G8R8A8_UNORM
	case .D24UnormS8Uint:
		return .D24_UNORM_S8_UINT
	case .D16UnormS8Uint:
		return .D16_UNORM_S8_UINT
	case .D32SfloatS8Uint:
		return .D32_SFLOAT_S8_UINT
	case .R8Unorm:
		return .R8_UNORM
	}
	return get_graphics_origin_format()
}


// ============================================================================
// Private - Op Queue Operations
// ============================================================================

append_op :: proc(node: OpNode) {
	sync.atomic_mutex_lock(&gQueueMtx)
	defer sync.atomic_mutex_unlock(&gQueueMtx)

	non_zero_append(&opQueue, node)
}

append_op_save :: proc(node: OpNode, outQueue: ^[dynamic]OpNode) {
	non_zero_append(outQueue, node)
}

save_to_map_queue :: proc(inoutMemBuf: ^^vk_mem_buffer, inQueue: []OpNode, outQueue: ^[dynamic]OpNode) {
	for &node in inQueue {
		#partial switch &n in node {
		case OpMapCopy:
			res: ^base_resource = n.p_resource
			if inoutMemBuf^ == nil {
				non_zero_append(outQueue, node)
				inoutMemBuf^ = auto_cast res.mem_buffer
				node = nil
			} else if auto_cast res.mem_buffer == inoutMemBuf^ {
				non_zero_append(outQueue, node)
				node = nil
			}
		}
	}
}
