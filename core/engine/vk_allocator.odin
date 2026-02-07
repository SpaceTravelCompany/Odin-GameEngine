#+private
package engine

import "base:runtime"
import "base:intrinsics"
import "core:container/intrusive/list"
import "core:mem"
import "core:sync"
import "core:thread"
import vk "vendor:vulkan"
import "core:log"
import "core:mem/tlsf"

// Conversion Functions

samples_to_vk_sample_count_flags :: proc "contextless" (samples: u8) -> vk.SampleCountFlags {
	switch samples {
	case 1:
		return {._1}
	case 2:
		return {._2}
	case 4:
		return {._4}
	case 8:
		return {._8}
	case 16:
		return {._16}
	case 32:
		return {._32}
	case 64:
		return {._64}
	case:
		return {._1}
	}
}

texture_type_to_vk_image_type :: proc "contextless" (t: texture_type) -> vk.ImageType {
	switch t {
	case .TEX2D:
		return .D2
	}
	return .D2
}

descriptor_type_to_vk_descriptor_type :: proc "contextless" (t: descriptor_type) -> vk.DescriptorType {
	switch t {
	case .SAMPLER:
		return .COMBINED_IMAGE_SAMPLER
	case .UNIFORM_DYNAMIC:
		return .UNIFORM_BUFFER_DYNAMIC
	case .UNIFORM:
		return .UNIFORM_BUFFER
	case .STORAGE:
		return .STORAGE_BUFFER
	case .STORAGE_IMAGE:
		return .STORAGE_IMAGE
	}
	return .UNIFORM_BUFFER
}

// Constants

vkPoolBlock :u32: 256
vkUniformSizeBlock :: 2 * mem.Megabyte
VkMaxMemIdxCnt : int : 4

// Types - Enums

vk_allocator_error :: enum {
	NONE,
	DEVICE_MEMORY_LIMIT,
}

// Types - Structs (Op structs)

OpMapCopy :: struct {
	p_resource: ^base_resource,
	data:       []byte,
	allocator:  Maybe(runtime.Allocator),
}

OpCopyBuffer :: struct {
	src:    ^buffer_resource,
	target: ^buffer_resource,
	data:     []byte,
	allocator: Maybe(runtime.Allocator),
}

OpCopyBufferToTexture :: struct {
	src:    ^buffer_resource,
	target: ^texture_resource,
	data:     []byte,
	allocator: Maybe(runtime.Allocator),
}

OpCreateBuffer :: struct {
	src:        ^buffer_resource,
	data:      []byte,
	allocator: Maybe(runtime.Allocator),
}

OpCreateTexture :: struct {
	src:       ^texture_resource,
	data:      []byte,
	allocator: Maybe(runtime.Allocator),
}

OpDestroyBuffer :: struct {
	idx: u32,
	src: ^buffer_resource,
	del: ^union_resource_node,
}

OpReleaseUniform :: struct {
	src: ^buffer_resource,
	del: ^union_resource_node,
}

OpDestroyTexture :: struct {
	idx: u32,
	src: ^texture_resource,
	del: ^union_resource_node,
}

OpUpdateDescriptorSet :: struct {
	set:       vk.DescriptorSet,
	size:      []descriptor_pool_size,
	resource:  []punion_resource,
	allocator: runtime.Allocator,
}

// Types - Structs (Memory buffer)

vk_mem_buffer_node :: struct {
	node: list.Node,
	size: vk.DeviceSize,
	idx:  vk.DeviceSize,
	free: bool,
}

// Pool holds only buffers or only images to avoid bufferImageGranularity alignment rules.
vk_mem_buffer :: struct {
	cellSize:     vk.DeviceSize,
	mapStart:     vk.DeviceSize,
	mapSize:      vk.DeviceSize,
	mapData:      [^]byte,
	len:          vk.DeviceSize,
	deviceMem:    vk.DeviceMemory,
	single:       bool,
	cache:        bool,
	forImages:    bool, // true = image-only pool, false = buffer-only pool
	cur:          ^list.Node,
	list:         list.List,
	allocateInfo: vk.MemoryAllocateInfo,
}

// Types - Structs (Uniform)

vk_temp_uniform_struct :: struct {
	uniform:   ^buffer_resource,
	data:      []byte,
	size:      vk.DeviceSize,
	allocator: Maybe(runtime.Allocator),
}

vk_uniform_alloc :: struct {
	max_size:   vk.DeviceSize,
	size:       vk.DeviceSize,
	uniforms:   [dynamic]^buffer_resource,
	buf:        __graphics_api_buffer,
	idx:        resource_range,
	mem_buffer: ^vk_mem_buffer,
}

// Types - Union

OpNode :: union {
	OpMapCopy,
	OpCopyBuffer,
	OpCopyBufferToTexture,
	OpCreateBuffer,
	OpCreateTexture,
	OpDestroyBuffer,
	OpReleaseUniform,
	OpDestroyTexture,
	OpUpdateDescriptorSet,
}

// Types - Buffer and Texture Type Union (internal)

__buffer_and_texture_type :: union {
	buffer_type,
	texture_type,
}

// Global Variables - Public

vkMemBlockLen: vk.DeviceSize = mem.Megabyte * 256
vkMemSpcialBlockLen: vk.DeviceSize = mem.Megabyte * 256
vk_non_coherent_atom_size: vk.DeviceSize = 0
vkSupportCacheLocal := false
vkSupportNonCacheLocal := false
gVkMinUniformBufferOffsetAlignment: vk.DeviceSize = 0

vk_allocator_thread_pool: thread.Pool

__vk_def_allocator: runtime.Allocator

gQueueMtx: sync.Atomic_Mutex

@thread_local thread_cmdPool: vk.CommandPool
@thread_local thread_cmd: vk.CommandBuffer
@thread_local vk_allocator_fence : vk.Fence

opQueue: [dynamic]OpNode
destroy_node :: struct {
	op: [dynamic]OpNode,
	stack_count:u32,
}
opDestroyQueues: [dynamic]destroy_node
opDestroyQueueMtx: sync.Mutex

gUniforms: [dynamic]vk_uniform_alloc
gTempUniforms: [dynamic]vk_temp_uniform_struct
gNonInsertedUniforms: [dynamic]vk_temp_uniform_struct

gVkMemBufs: [dynamic]^vk_mem_buffer
gVkMemIdxCnts: []int

gVkMemTlsfAllocator: runtime.Allocator
gVkMemTlsf: tlsf.Allocator

gVkPoolTlsfAllocator: runtime.Allocator
gVkPoolTlsf: tlsf.Allocator

gVkDestroyTlsfAllocator: runtime.Allocator
gVkDestroyTlsf: tlsf.Allocator

@(private="file") vk_allocation_callback :: proc "system" (pUserData: rawptr, size: int, alignment: int, allocationScope: vk.SystemAllocationScope) -> rawptr {
	context = runtime.Context{
		allocator = gVkMemTlsfAllocator,
	}
	res, err := mem.alloc(size, alignment, context.allocator)
	if err != .None {
		return nil
	}
	return res
}

@(private="file") vk_reallocation_callback :: proc "system" (pUserData: rawptr, pOriginal: rawptr, size: int, alignment: int, allocationScope: vk.SystemAllocationScope) -> rawptr {
	// context = runtime.Context{
	// 	allocator = gVkMemTlsfAllocator,
	// }
	// res, err := mem.resize(pOriginal, size, size, alignment, context.allocator)
	// if err != .None {
	// 	return nil
	// }
	intrinsics.trap()//never execute now. why exists?
}

@(private="file") vk_free_callback :: proc "system" (pUserData: rawptr, pMemory: rawptr) {
	context = runtime.Context{
		allocator = gVkMemTlsfAllocator,
	}

	free(pMemory, context.allocator)
}

gVkAllocationCallbacks: vk.AllocationCallbacks = {
	pUserData = nil,
	pfnAllocation = vk_allocation_callback,
	pfnReallocation = vk_reallocation_callback,
	pfnFree = vk_free_callback,
	pfnInternalAllocation = nil,
	pfnInternalFree = nil,
}


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
	_ = tlsf.init_from_allocator(&gVkMemTlsf, context.allocator, mem.Megabyte * 128, mem.Megabyte * 128)
	gVkMemTlsfAllocator = tlsf.allocator(&gVkMemTlsf)
	_ = tlsf.init_from_allocator(&gVkDestroyTlsf, context.allocator, mem.Megabyte * 4, mem.Megabyte * 4)
	gVkDestroyTlsfAllocator = tlsf.allocator(&gVkDestroyTlsf)

	_ = tlsf.init_from_allocator(&gVkPoolTlsf, context.allocator, mem.Megabyte * 4, mem.Megabyte * 4)
	gVkPoolTlsfAllocator = tlsf.allocator(&gVkPoolTlsf)

	gVkMemBufs = mem.make_non_zeroed([dynamic]^vk_mem_buffer, gVkMemTlsfAllocator)

	gVkMemIdxCnts = mem.make_non_zeroed([]int, vk_physical_mem_prop.memoryTypeCount, gVkMemTlsfAllocator)
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

	gUniforms = mem.make_non_zeroed([dynamic]vk_uniform_alloc, gVkMemTlsfAllocator)
	gTempUniforms = mem.make_non_zeroed([dynamic]vk_temp_uniform_struct, gVkMemTlsfAllocator)
	gNonInsertedUniforms = mem.make_non_zeroed([dynamic]vk_temp_uniform_struct, gVkMemTlsfAllocator)
	gDesciptorPools = mem.make_map(map[vk.DescriptorSetLayout]descriptor_pool_mem, gVkMemTlsfAllocator)
	gTmpDesciptorPoolSizes = mem.make_non_zeroed([dynamic]vk.DescriptorPoolSize, gVkPoolTlsfAllocator)
	gTmpDesciptorSetLayouts = mem.make_non_zeroed([dynamic]vk.DescriptorSetLayout, gVkPoolTlsfAllocator)
}



vk_allocator_destroy :: proc() {
	thread.pool_wait_all(&vk_allocator_thread_pool)
	thread.pool_join(&vk_allocator_thread_pool)
	thread.pool_destroy(&vk_allocator_thread_pool)

	vk.DestroyCommandPool(vk_device, thread_cmdPool, nil)
	vk.DestroyFence(vk_device, vk_allocator_fence, nil)

	for b in gVkMemBufs {
		vk_mem_buffer_Deinit2(b)
		free(b, gVkMemTlsfAllocator)
	}
	delete(gVkMemBufs)

	descriptor_pool_mem_destroy_all()
	
	for i in gUniforms {
		delete(i.uniforms)
	}
	
	delete(gTmpDesciptorPoolSizes)
	delete(gTmpDesciptorSetLayouts)
	delete(gDesciptorPools)
	delete(gUniforms)
	delete(gTempUniforms)
	delete(gNonInsertedUniforms)
	delete(opQueue)
	delete(opDestroyQueues)
	delete(gVkMemIdxCnts, gVkMemTlsfAllocator)

	tlsf.destroy(&gVkMemTlsf)
	tlsf.destroy(&gVkDestroyTlsf)
	tlsf.destroy(&gVkPoolTlsf)
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
			executeReleaseUniform(opExecQueue, n.src, n.del)
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
					if g.buf.vk_buffer == 0 do continue
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
	for node in opExecQueue {
		#partial switch n in node {
		case OpUpdateDescriptorSet:
			vk_execute_update_descriptor_set(n.set, n.size, n.resource)
			delete(n.resource, n.allocator)
		case:
			continue
		}
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
		if nodes.stack_count > MAX_FRAMES_IN_FLIGHT || destroy_all {
			for &node in nodes.op {
				#partial switch n in node {
				case OpDestroyBuffer:
					executeDestroyBuffer(n.src)
					graphics_free_resource(n.del, true)
				case OpDestroyTexture:
					executeDestroyTexture(n.src)
					graphics_free_resource(n.del, true)
				case OpCopyBuffer:
					executeDestroyBuffer(n.src)
					if n.allocator != nil do delete(n.data, n.allocator.?)
					free(n.src, gVkDestroyTlsfAllocator)
				case OpCopyBufferToTexture:
					executeDestroyBuffer(n.src)
					if n.allocator != nil do delete(n.data, n.allocator.?)
					free(n.src, gVkDestroyTlsfAllocator)
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
	for &node in opExecQueue {
		#partial switch &n in node {
		case OpCreateBuffer:
			n.src.completed = true//need lock/unlock gMapResourceMtx
		case OpCreateTexture:
			n.src.completed = true//need lock/unlock gMapResourceMtx
		case OpDestroyBuffer:
			del := graphics_pop_resource(n.idx, n.src, false)
			n.del = del
		case OpDestroyTexture:
			del := graphics_pop_resource(n.idx, n.src, false)
			n.del = del
		}
	}
	sync.mutex_unlock(&gMapResourceMtx)

	sync.mutex_lock(&opDestroyQueueMtx)
	nodes := mem.make_non_zeroed([dynamic]OpNode, gVkDestroyTlsfAllocator)
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
