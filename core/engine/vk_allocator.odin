#+private
package engine

import "base:runtime"
import "base:intrinsics"
import "core:container/intrusive/list"
import "core:math"
import "core:mem"
import "core:mem/virtual"
import "core:debug/trace"
import "core:slice"
import "core:sync"
import "core:fmt"
import vk "vendor:vulkan"


// ============================================================================
// Constants
// ============================================================================

vkPoolBlock :: 256
vkUniformSizeBlock :: mem.Megabyte
@(private = "file") VkMaxMemIdxCnt : int : 4


// ============================================================================
// Types - Enums
// ============================================================================

vk_allocator_error :: enum {
	NONE,
	DEVICE_MEMORY_LIMIT,
}


// ============================================================================
// Types - Structs (Op structs)
// ============================================================================

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
	src:       ^buffer_resource,
	data:      []byte,
	allocator: Maybe(runtime.Allocator),
}

OpCreateTexture :: struct {
	src:       ^texture_resource,
	data:      []byte,
	allocator: Maybe(runtime.Allocator),
}

OpDestroyBuffer :: struct {
	src: ^buffer_resource,
}

OpReleaseUniform :: struct {
	src: ^buffer_resource,
}

OpDestroyTexture :: struct {
	src: ^texture_resource,
}

Op__Updatedescriptor_sets :: struct {
	sets: []descriptor_set,
}

// doesn't need to call outside
Op__RegisterDescriptorPool :: struct {
	size: []descriptor_pool_size,
}


// ============================================================================
// Types - Structs (Memory buffer)
// ============================================================================

vk_mem_buffer_node :: struct {
	node: list.Node,
	size: vk.DeviceSize,
	idx:  vk.DeviceSize,
	free: bool,
}

vk_mem_buffer :: struct {
	cellSize:     vk.DeviceSize,
	mapStart:     vk.DeviceSize,
	mapSize:      vk.DeviceSize,
	mapData:      [^]byte,
	len:          vk.DeviceSize,
	deviceMem:    vk.DeviceMemory,
	single:       bool,
	cache:        bool,
	cur:          ^list.Node,
	list:         list.List,
	allocateInfo: vk.MemoryAllocateInfo,
}


// ============================================================================
// Types - Structs (Uniform)
// ============================================================================

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
	buf:        vk.Buffer,
	idx:        resource_range,
	mem_buffer: ^vk_mem_buffer,
}


// ============================================================================
// Types - Union
// ============================================================================

OpNode :: union {
	OpMapCopy,
	OpCopyBuffer,
	OpCopyBufferToTexture,
	OpCreateBuffer,
	OpCreateTexture,
	OpDestroyBuffer,
	OpReleaseUniform,
	OpDestroyTexture,
	Op__Updatedescriptor_sets,
	Op__RegisterDescriptorPool,
}


// ============================================================================
// Global Variables - Public
// ============================================================================

vkMemBlockLen: vk.DeviceSize = mem.Megabyte * 256
vkMemSpcialBlockLen: vk.DeviceSize = mem.Megabyte * 256
vk_non_coherent_atom_size: vk.DeviceSize = 0
vkSupportCacheLocal := false
vkSupportNonCacheLocal := false
gVkMinUniformBufferOffsetAlignment: vk.DeviceSize = 0


// ============================================================================
// Global Variables - Private
// ============================================================================

@(private = "file") __vk_def_allocator: runtime.Allocator
@(private = "file") __tempArena: virtual.Arena

@(private = "file") gQueueMtx: sync.Atomic_Mutex
@(private = "file") gDestroyQueueMtx: sync.Mutex
@(private = "file") gWaitOpSem: sync.Sema

@(private = "file") cmdPool: vk.CommandPool
@(private = "file") gCmd: vk.CommandBuffer

@(private = "file") opQueue: [dynamic]OpNode
@(private = "file") opSaveQueue: [dynamic]OpNode
@(private = "file") opMapQueue: [dynamic]OpNode
@(private = "file") opMapCopyQueue: [dynamic]OpNode
@(private = "file") opDestroyQueue: [dynamic]OpNode

@(private = "file") gVkUpdateDesciptorSetList: [dynamic]vk.WriteDescriptorSet
@(private = "file") gDesciptorPools: map[[^]descriptor_pool_size][dynamic]descriptor_pool_mem

@(private = "file") gUniforms: [dynamic]vk_uniform_alloc
@(private = "file") gTempUniforms: [dynamic]vk_temp_uniform_struct
@(private = "file") gNonInsertedUniforms: [dynamic]vk_temp_uniform_struct

@(private = "file") gVkMemBufs: [dynamic]^vk_mem_buffer
@(private = "file") gVkMemIdxCnts: []int


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
			when is_log {
				fmt.printfln(
					"XFIT SYSLOG : Vulkan Graphic Card Dedicated Memory Block %d MB\nDedicated Memory : %d MB",
					vkMemBlockLen / mem.Megabyte,
					h.size / mem.Megabyte,
				)
			}
			mainHeapIdx = auto_cast i
			break
		}
	}
	if !change {
		_ChangeSize(vk_physical_mem_prop.memoryHeaps[0].size)
		when is_log {
			fmt.printfln(
				"XFIT SYSLOG : Vulkan No Graphic Card System Memory Block %d MB\nSystem Memory : %d MB",
				vkMemBlockLen / mem.Megabyte,
				vk_physical_mem_prop.memoryHeaps[0].size / mem.Megabyte,
			)
		}
		mainHeapIdx = 0
	}

	vk_non_coherent_atom_size = auto_cast vk_physical_prop.limits.nonCoherentAtomSize

	reduced := false
	for t, i in vk_physical_mem_prop.memoryTypes[:vk_physical_mem_prop.memoryTypeCount] {
		if t.propertyFlags >= {.DEVICE_LOCAL, .HOST_CACHED, .HOST_VISIBLE} {
			vkSupportCacheLocal = true
			when is_log do fmt.printfln("XFIT SYSLOG : Vulkan Device Supported Cache Local Memory")
		} else if t.propertyFlags >= {.DEVICE_LOCAL, .HOST_COHERENT, .HOST_VISIBLE} {
			vkSupportNonCacheLocal = true
			when is_log do fmt.printfln("XFIT SYSLOG : Vulkan Device Supported Non Cache Local Memory")
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

	_ = virtual.arena_init_growing(&__tempArena)

	__temp_arena_allocator = virtual.arena_allocator(&__tempArena)

	cmdPoolInfo := vk.CommandPoolCreateInfo {
		sType            = vk.StructureType.COMMAND_POOL_CREATE_INFO,
		queueFamilyIndex = vk_graphics_family_index,
	}
	vk.CreateCommandPool(vk_device, &cmdPoolInfo, nil, &cmdPool)

	cmdAllocInfo := vk.CommandBufferAllocateInfo {
		sType              = vk.StructureType.COMMAND_BUFFER_ALLOCATE_INFO,
		commandBufferCount = 1,
		level              = .PRIMARY,
		commandPool        = cmdPool,
	}
	vk.AllocateCommandBuffers(vk_device, &cmdAllocInfo, &gCmd)

	opQueue = mem.make_non_zeroed([dynamic]OpNode, vk_def_allocator())
	opSaveQueue = mem.make_non_zeroed([dynamic]OpNode, vk_def_allocator())
	opMapQueue = mem.make_non_zeroed([dynamic]OpNode, vk_def_allocator())
	opMapCopyQueue = mem.make_non_zeroed([dynamic]OpNode, vk_def_allocator())
	opDestroyQueue = mem.make_non_zeroed([dynamic]OpNode, vk_def_allocator())
	gVkUpdateDesciptorSetList = mem.make_non_zeroed([dynamic]vk.WriteDescriptorSet, vk_def_allocator())

	gUniforms = mem.make_non_zeroed([dynamic]vk_uniform_alloc, vk_def_allocator())
	gTempUniforms = mem.make_non_zeroed([dynamic]vk_temp_uniform_struct, vk_def_allocator())
	gNonInsertedUniforms = mem.make_non_zeroed([dynamic]vk_temp_uniform_struct, vk_def_allocator())
}

vk_allocator_destroy :: proc() {
	for b in gVkMemBufs {
		vk_mem_buffer_Deinit2(b)
		free(b, vk_def_allocator())
	}
	delete(gVkMemBufs)

	vk.DestroyCommandPool(vk_device, cmdPool, nil)

	for _, &value in gDesciptorPools {
		for i in value {
			vk.DestroyDescriptorPool(vk_device, i.pool, nil)
		}
		delete(value)
	}
	for i in gUniforms {
		delete(i.uniforms)
	}

	delete(gVkUpdateDesciptorSetList)
	delete(gDesciptorPools)
	delete(gUniforms)
	delete(gTempUniforms)
	delete(gNonInsertedUniforms)
	delete(opQueue)
	delete(opSaveQueue)
	delete(opMapQueue)
	delete(opMapCopyQueue)
	delete(opDestroyQueue)

	virtual.arena_destroy(&__tempArena)

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

vk_wait_all_op :: #force_inline proc "contextless" () {
	sync.sema_wait(&gWaitOpSem)
}


// ============================================================================
// Public API - Resource Operations
// ============================================================================

vkbuffer_resource_create_buffer :: proc(
	option: buffer_create_option,
	data: []byte,
	isCopy: bool = false,
	allocator: Maybe(runtime.Allocator) = nil,
) -> iresource {
	self: ^buffer_resource = new(buffer_resource, vk_def_allocator())
	self.type = .BUFFER
	self.option = option

	if isCopy {
		copyData: []byte
		if allocator == nil {
			copyData = mem.make_non_zeroed([]byte, len(data), temp_arena_allocator())
		} else {
			copyData = mem.make_non_zeroed([]byte, len(data), allocator.?)
		}
		mem.copy(raw_data(copyData), raw_data(data), len(data))
		
		append_op(OpCreateBuffer{src = self, data = copyData, allocator = allocator})
	} else {
		append_op(OpCreateBuffer{src = self, data = data, allocator = allocator})
	}
	return auto_cast self
}

vkbuffer_resource_create_texture :: proc(
	option: texture_create_option,
	sampler: vk.Sampler,
	data: []byte,
	isCopy: bool = false,
	allocator: Maybe(runtime.Allocator) = nil,
) -> iresource {
	self: ^texture_resource = new(texture_resource, vk_def_allocator())
	self.type = .TEXTURE
	self.sampler = sampler
	self.option = option
	if isCopy {
		copyData: []byte
		if allocator == nil {
			copyData = mem.make_non_zeroed([]byte, len(data), temp_arena_allocator())
		} else {
			copyData = mem.make_non_zeroed([]byte, len(data), allocator.?)
		}
		mem.copy(raw_data(copyData), raw_data(data), len(data))
		append_op(OpCreateTexture{src = self, data = copyData, allocator = allocator})
	} else {
		append_op(OpCreateTexture{src = self, data = data, allocator = allocator})
	}
	return auto_cast self
}

//! unlike CopyUpdate, data cannot be a temporary variable.
vkbuffer_resource_map_update_slice :: #force_inline proc(
	self: iresource,
	data: $T/[]$E,
	allocator: Maybe(runtime.Allocator) = nil,
) {
	self_: ^base_resource = auto_cast self
	_data := mem.slice_to_bytes(data)
	buffer_resource_MapCopy(self_, _data, allocator)
}

//! unlike CopyUpdate, data cannot be a temporary variable.
vkbuffer_resource_map_update :: #force_inline proc(
	self: iresource,
	data: ^$T,
	allocator: Maybe(runtime.Allocator) = nil,
) {
	self_: ^base_resource = auto_cast self
	_data := mem.ptr_to_bytes(data)
	buffer_resource_MapCopy(self_, _data, allocator)
}

vkbuffer_resource_copy_update_slice :: #force_inline proc(
	self: iresource,
	data: $T/[]$E,
	allocator: Maybe(runtime.Allocator) = nil,
) {
	self_: ^base_resource = auto_cast self
	bytes := mem.slice_to_bytes(data)
	copyData: []byte
	if allocator == nil {
		copyData = mem.make_non_zeroed([]byte, len(bytes), temp_arena_allocator())
	} else {
		copyData = mem.make_non_zeroed([]byte, len(bytes), allocator.?)
	}
	intrinsics.mem_copy_non_overlapping(raw_data(copyData), raw_data(bytes), len(bytes))

	buffer_resource_MapCopy(self_, copyData, allocator)
}

vkbuffer_resource_copy_update :: proc(
	self: iresource,
	data: ^$T,
	allocator: Maybe(runtime.Allocator) = nil,
) {
	self_: ^base_resource = auto_cast self
	copyData: []byte
	bytes := mem.ptr_to_bytes(data)

	if allocator == nil {
		copyData = mem.make_non_zeroed([]byte, len(bytes), temp_arena_allocator())
	} else {
		copyData = mem.make_non_zeroed([]byte, len(bytes), allocator.?)
	}
	intrinsics.mem_copy_non_overlapping(raw_data(copyData), raw_data(bytes), len(bytes))

	buffer_resource_MapCopy(self_, copyData, allocator)
}

vkbuffer_resource_deinit :: proc(self: iresource) {
	switch (^base_resource)(self).type {
	case .BUFFER:
		buffer: ^buffer_resource = auto_cast self
		if buffer.option.type == .UNIFORM {
			append_op(OpReleaseUniform{src = buffer})
		} else {
			append_op(OpDestroyBuffer{src = buffer})
		}
	case .TEXTURE:
		texture: ^texture_resource = auto_cast self
		if texture.mem_buffer == nil {
			vk.DestroyImageView(vk_device, texture.img_view, nil)
		} else {
			append_op(OpDestroyTexture{src = texture})
		}
	}
}


// ============================================================================
// Public API - Descriptor Sets
// ============================================================================

vk_update_descriptor_sets :: proc(sets: []descriptor_set) {
	append_op(Op__Updatedescriptor_sets{sets = sets})
}


// ============================================================================
// Public API - Op Execute
// ============================================================================

vk_op_execute_destroy :: proc() {
	sync.mutex_lock(&gDestroyQueueMtx)

	for node in opDestroyQueue {
		#partial switch n in node {
		case OpDestroyBuffer:
			executeDestroyBuffer(n.src)
		case OpDestroyTexture:
			executeDestroyTexture(n.src)
		}
	}

	clear(&opDestroyQueue)
	sync.mutex_unlock(&gDestroyQueueMtx)

	virtual.arena_free_all(&__tempArena)

	sync.sema_post(&gWaitOpSem)
}

vk_op_execute :: proc() {
	sync.atomic_mutex_lock(&gQueueMtx)
	if len(opQueue) == 0 {
		sync.atomic_mutex_unlock(&gQueueMtx)
		vk_wait_graphics_idle()
		vk_op_execute_destroy()
		return
	}
	resize(&opSaveQueue, len(opQueue))
	mem.copy_non_overlapping(raw_data(opSaveQueue), raw_data(opQueue), len(opQueue) * size_of(OpNode))
	clear(&opQueue)
	sync.atomic_mutex_unlock(&gQueueMtx)

	for &node in opSaveQueue {
		#partial switch n in node {
		case OpMapCopy:
			non_zero_append(&opMapCopyQueue, node)
			node = nil
		case:
			continue
		}
	}

	for &node in opSaveQueue {
		#partial switch n in node {
		case OpCreateBuffer:
			executeCreateBuffer(n.src, n.data, n.allocator)
		case OpCreateTexture:
			executeCreateTexture(n.src, n.data, n.allocator)
		case Op__RegisterDescriptorPool:
			executeRegisterDescriptorPool(n.size)
		case:
			continue
		}
		node = nil
	}

	for &node in opSaveQueue {
		#partial switch n in node {
		case OpReleaseUniform:
			executeReleaseUniform(n.src)
		case:
			continue
		}
		node = nil
	}

	if len(gTempUniforms) > 0 {
		if len(gUniforms) == 0 {
			create_new_uniform_buffer(gTempUniforms[:])
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
											assign_uniform_to_buffer(&t, &g, i2, i3, 0)
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
									assign_uniform_to_buffer(&t, &g, i2, i3, g.size)
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
											assign_uniform_to_buffer(&t, &g, i2, i3, prev_end)
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
									assign_uniform_to_buffer(&t, &g, i2, i3, prev_end)
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
						assign_uniform_to_buffer(&t, &g, i2, len(g.uniforms) - 1, prev_end)
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
				create_new_uniform_buffer(gNonInsertedUniforms[:])
				clear(&gNonInsertedUniforms)
			}
		}
		clear(&gTempUniforms)
	}
	for &node in opMapCopyQueue {
		non_zero_append(&opSaveQueue, node)
	}
	clear(&opMapCopyQueue)

	sync.mutex_lock(&gDestroyQueueMtx)
	for &node in opSaveQueue {
		#partial switch n in node {
		case OpDestroyBuffer:
			non_zero_append(&opDestroyQueue, node)
		case OpDestroyTexture:
			non_zero_append(&opDestroyQueue, node)
		case:
			continue
		}
		node = nil
	}
	sync.mutex_unlock(&gDestroyQueueMtx)

	memBufT: ^vk_mem_buffer = nil
	save_to_map_queue(&memBufT)
	for len(opMapQueue) > 0 {
		vk_mem_buffer_MapCopyexecute(memBufT, opMapQueue[:])
		clear(&opMapQueue)
		memBufT = nil
		save_to_map_queue(&memBufT)
	}

	haveCmds := false
	for node in opSaveQueue {
		#partial switch n in node {
		case OpCopyBuffer:
			haveCmds = true
		case OpCopyBufferToTexture:
			haveCmds = true
		case Op__Updatedescriptor_sets:
			execute_update_descriptor_sets(n.sets)
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
		clear(&gVkUpdateDesciptorSetList)
	}

	if haveCmds {
		vk.ResetCommandPool(vk_device, cmdPool, {})

		beginInfo := vk.CommandBufferBeginInfo {
			flags = {.ONE_TIME_SUBMIT},
			sType = vk.StructureType.COMMAND_BUFFER_BEGIN_INFO,
		}
		vk.BeginCommandBuffer(gCmd, &beginInfo)
		for node in opSaveQueue {
			#partial switch n in node {
			case OpCopyBuffer:
				execute_copy_buffer(n.src, n.target)
			case OpCopyBufferToTexture:
				execute_copy_buffer_to_texture(n.src, n.target)
			}
		}
		vk.EndCommandBuffer(gCmd)
		submitInfo := vk.SubmitInfo {
			commandBufferCount = 1,
			pCommandBuffers    = &gCmd,
			sType              = .SUBMIT_INFO,
		}
		res := vk.QueueSubmit(vk_graphics_queue, 1, &submitInfo, 0)
		if res != .SUCCESS do trace.panic_log("res := vk.QueueSubmit(vk_graphics_queue, 1, &submitInfo, 0) : ", res)

		vk_wait_graphics_idle()

		for node in opSaveQueue {
			#partial switch &n in node {
			case OpCopyBuffer:
				if n.allocator != nil {
					delete(n.data, n.allocator.?)
				}
				n.data = nil
				n.allocator = nil
			case OpCopyBufferToTexture:
				if n.allocator != nil {
					delete(n.data, n.allocator.?)
				}
				n.data = nil
				n.allocator = nil
			}
		}
		clear(&opSaveQueue)
		vk_op_execute_destroy()
	} else {
		clear(&opSaveQueue)
		vk_op_execute_destroy()
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
// Private - Memory Buffer Operations
// ============================================================================

// ! don't call vulkan_res.init separately
@(private = "file")
vk_mem_buffer_Init :: proc(
	cellSize: vk.DeviceSize,
	len: vk.DeviceSize,
	typeFilter: u32,
	memProp: vk.MemoryPropertyFlags,
) -> Maybe(vk_mem_buffer) {
	memBuf := vk_mem_buffer {
		cellSize     = cellSize,
		len          = len,
		allocateInfo = {sType = .MEMORY_ALLOCATE_INFO, allocationSize = len * cellSize},
		cache        = vk.MemoryPropertyFlags{.HOST_VISIBLE, .HOST_CACHED} <= memProp,
	}
	success: bool
	memBuf.allocateInfo.memoryTypeIndex, success = vk_find_mem_type(typeFilter, memProp)
	if !success do return nil

	if memBuf.cache {
		memBuf.allocateInfo.allocationSize = math.ceil_up(len * cellSize, vk_non_coherent_atom_size)
		memBuf.len = memBuf.allocateInfo.allocationSize / cellSize
	}

	res := vk.AllocateMemory(vk_device, &memBuf.allocateInfo, nil, &memBuf.deviceMem)
	if res != .SUCCESS do return nil

	list.push_back(&memBuf.list, auto_cast new(vk_mem_buffer_node, vk_def_allocator()))
	((^vk_mem_buffer_node)(memBuf.list.head)).free = true
	((^vk_mem_buffer_node)(memBuf.list.head)).size = memBuf.len
	((^vk_mem_buffer_node)(memBuf.list.head)).idx = 0
	memBuf.cur = memBuf.list.head

	return memBuf
}

@(private = "file")
vk_mem_buffer_InitSingle :: proc(cellSize: vk.DeviceSize, typeFilter: u32) -> Maybe(vk_mem_buffer) {
	memBuf := vk_mem_buffer {
		cellSize     = cellSize,
		len          = 1,
		allocateInfo = {sType = .MEMORY_ALLOCATE_INFO, allocationSize = 1 * cellSize},
		single       = true,
	}
	success: bool
	memBuf.allocateInfo.memoryTypeIndex, success = vk_find_mem_type(
		typeFilter,
		vk.MemoryPropertyFlags{.DEVICE_LOCAL},
	)
	if !success do trace.panic_log("memBuf.allocateInfo.memoryTypeIndex, success = vk_find_mem_type(typeFilter, vk.MemoryPropertyFlags{.DEVICE_LOCAL})")

	res := vk.AllocateMemory(vk_device, &memBuf.allocateInfo, nil, &memBuf.deviceMem)
	if res != .SUCCESS do trace.panic_log("res := vk.AllocateMemory(vk_device, &memBuf.allocateInfo, nil, &memBuf.deviceMem)")

	return memBuf
}

@(private = "file")
vk_mem_buffer_Deinit2 :: proc(self: ^vk_mem_buffer) {
	vk.FreeMemory(vk_device, self.deviceMem, nil)
	if !self.single {
		n: ^list.Node
		for n = self.list.head; n.next != nil; {
			tmp := n
			n = n.next
			free(tmp, vk_def_allocator())
		}
		free(n, vk_def_allocator())
		self.list.head = nil
		self.list.tail = nil
	}
}

@(private = "file")
vk_mem_buffer_Deinit :: proc(self: ^vk_mem_buffer) {
	for b, i in gVkMemBufs {
		if b == self {
			ordered_remove(&gVkMemBufs, i) //!no unordered
			break
		}
	}
	if !self.single do gVkMemIdxCnts[self.allocateInfo.memoryTypeIndex] -= 1
	vk_mem_buffer_Deinit2(self)
	free(self, vk_def_allocator())
}

@(private = "file")
vk_mem_buffer_BindBufferNode :: proc(
	self: ^vk_mem_buffer,
	vkResource: $T,
	cellCnt: vk.DeviceSize,
) -> (resource_range, vk_allocator_error) where T == vk.Buffer || T == vk.Image {
	vk_mem_buffer_BindBufferNodeInside :: proc(self: ^vk_mem_buffer, vkResource: $T, idx: vk.DeviceSize) where T == vk.Buffer || T == vk.Image {
		when (T == vk.Buffer) {
			res := vk.BindBufferMemory(vk_device, vkResource, self.deviceMem, self.cellSize * idx)
			if res != .SUCCESS do trace.panic_log("vk_mem_buffer_BindBufferNodeInside BindBufferMemory : ", res)
		} else when (T == vk.Image) {
			res := vk.BindImageMemory(vk_device, vkResource, self.deviceMem, self.cellSize * idx)
			if res != .SUCCESS do trace.panic_log("vk_mem_buffer_BindBufferNodeInside BindImageMemory : ", res)
		}
	}
	if cellCnt == 0 do trace.panic_log("if cellCnt == 0")
	if self.single {
		vk_mem_buffer_BindBufferNodeInside(self, vkResource, 0)
		return nil, .NONE
	}

	cur: ^vk_mem_buffer_node = auto_cast self.cur
	for !(cur.free && cellCnt <= cur.size) {
		cur = auto_cast (cur.node.next if cur.node.next != nil else self.list.head)
		if cur == auto_cast self.cur {
			return nil, .DEVICE_MEMORY_LIMIT
		}
	}
	vk_mem_buffer_BindBufferNodeInside(self, vkResource, cur.idx)
	cur.free = false
	remain := cur.size - cellCnt //remain space when vkResource bind
	self.cur = auto_cast cur

	range: resource_range = auto_cast cur
	curNext: ^vk_mem_buffer_node = auto_cast (cur.node.next if cur.node.next != nil else self.list.head)
	if cur == curNext { // only one item on list
		if remain > 0 {
			list.push_back(&self.list, auto_cast new(vk_mem_buffer_node, vk_def_allocator()))
			tail: ^vk_mem_buffer_node = auto_cast self.list.tail
			tail.free = true
			tail.size = remain
			tail.idx = cellCnt
		}
	} else {
		if remain > 0 {
			if !curNext.free || curNext.idx < cur.idx {
				list.insert_after(&self.list, auto_cast cur, auto_cast new(vk_mem_buffer_node, vk_def_allocator()))
				next: ^vk_mem_buffer_node = auto_cast cur.node.next
				next.free = true
				next.idx = cur.idx + cellCnt
				next.size = remain
			} else {
				curNext.idx -= remain
				curNext.size += remain
			}
		}
	}
	cur.size = cellCnt
	return range, .NONE
}

@(private = "file")
vk_mem_buffer_UnBindBufferNode :: proc(
	self: ^vk_mem_buffer,
	vkResource: $T,
	range: resource_range,
) where T == vk.Buffer || T == vk.Image {

	when T == vk.Buffer {
		vk.DestroyBuffer(vk_device, vkResource, nil)
	} else when T == vk.Image {
		vk.DestroyImage(vk_device, vkResource, nil)
	}

	if self.single {
		vk_mem_buffer_Deinit(self)
		return
	}
	range_: ^vk_mem_buffer_node = auto_cast range
	range_.free = true

	next_ := range_.node.next
	for next_ != nil {
		next: ^vk_mem_buffer_node = auto_cast next_
		if next.free {
			range_.size += next.size
			next_ = next.node.next
			list.remove(&self.list, auto_cast next)
			free(next, vk_def_allocator())
		} else {
			break
		}
	}

	prev_ := range_.node.prev
	for prev_ != nil {
		prev: ^vk_mem_buffer_node = auto_cast prev_
		if prev.free {
			range_.size += prev.size
			range_.idx -= prev.size
			prev_ = prev.node.prev
			list.remove(&self.list, auto_cast prev)
			free(prev, vk_def_allocator())
		} else {
			break
		}
	}
	if gVkMemIdxCnts[self.allocateInfo.memoryTypeIndex] > VkMaxMemIdxCnt {
		for b in gVkMemBufs {
			if self != b && self.allocateInfo.memoryTypeIndex == b.allocateInfo.memoryTypeIndex && vk_mem_buffer_IsEmpty(b) {
				gVkMemIdxCnts[b.allocateInfo.memoryTypeIndex] -= 1
				vk_mem_buffer_Deinit(b)
			}
		}
		if vk_mem_buffer_IsEmpty(self) {
			gVkMemIdxCnts[self.allocateInfo.memoryTypeIndex] -= 1
			vk_mem_buffer_Deinit(self)
			return
		}
	}
	if self.list.head == nil { //?always self.list.head not nil
		list.push_back(&self.list, auto_cast new(vk_mem_buffer_node, vk_def_allocator()))
		((^vk_mem_buffer_node)(self.list.head)).free = true
		((^vk_mem_buffer_node)(self.list.head)).size = self.len
		((^vk_mem_buffer_node)(self.list.head)).idx = 0
		self.cur = self.list.head
	}
}

@(private = "file")
vk_mem_buffer_CreateFromResource :: proc(
	vkResource: $T,
	memProp: vk.MemoryPropertyFlags,
	outIdx: ^resource_range,
	maxSize: vk.DeviceSize,
) -> (memBuf: ^vk_mem_buffer) where T == vk.Buffer || T == vk.Image {
	memType: u32
	ok: bool

	_BindBufferNode :: proc(b: ^vk_mem_buffer, memType: u32, vkResource: $T, cellCnt: vk.DeviceSize, outIdx: ^resource_range, memBuf: ^^vk_mem_buffer) -> bool {
		if b.allocateInfo.memoryTypeIndex != memType {
			return false
		}
		outIdx_, err := vk_mem_buffer_BindBufferNode(b, vkResource, cellCnt)
		if err != .NONE {
			return false
		}
		if outIdx_ == nil {
			trace.panic_log("")
		}
		outIdx^ = outIdx_
		memBuf^ = b
		return true
	}
	_Init :: proc(BLKSize: vk.DeviceSize, maxSize_: vk.DeviceSize, memRequire: vk.MemoryRequirements, memProp_: vk.MemoryPropertyFlags) -> Maybe(vk_mem_buffer) {
		memBufTLen := max(BLKSize, maxSize_) / memRequire.alignment + 1
		if max(BLKSize, maxSize_) % memRequire.alignment == 0 do memBufTLen -= 1
		return vk_mem_buffer_Init(
			memRequire.alignment,
			memBufTLen,
			memRequire.memoryTypeBits,
			memProp_,
		)
	}
	memRequire: vk.MemoryRequirements
	when T == vk.Buffer {
		vk.GetBufferMemoryRequirements(vk_device, vkResource, &memRequire)
	} else when T == vk.Image {
		vk.GetImageMemoryRequirements(vk_device, vkResource, &memRequire)
	}

	maxSize_ := maxSize
	if maxSize_ < memRequire.size do maxSize_ = memRequire.size

	memProp_ := memProp
	if ((vkMemBlockLen == vkMemSpcialBlockLen) ||
		   ((T == vk.Buffer && maxSize_ <= 1024*1024*1))) &&
	   (.HOST_VISIBLE in memProp_) {
		if vkSupportCacheLocal {
			memProp_ = {.HOST_VISIBLE, .HOST_CACHED, .DEVICE_LOCAL}
		} else if vkSupportNonCacheLocal {
			memProp_ = {.HOST_VISIBLE, .HOST_COHERENT, .DEVICE_LOCAL}
		}
	}

	cellCnt := maxSize_ / memRequire.alignment + 1
	if maxSize_ % memRequire.alignment == 0 do cellCnt -= 1

	memBuf = nil
	for b in gVkMemBufs {
		if b.cellSize != memRequire.alignment do continue
		memType, ok = vk_find_mem_type(memRequire.memoryTypeBits, memProp_)
		if !ok {
			memProp_ = memProp
			memType, ok = vk_find_mem_type(memRequire.memoryTypeBits, memProp_)
			if !ok do trace.panic_log("vk_find_mem_type Failed")
		}
		if !_BindBufferNode(b, memType, vkResource, cellCnt, outIdx, &memBuf) do continue
		break
	}

	if memBuf == nil {
		memBuf = new(vk_mem_buffer, vk_def_allocator())

		memFlag := vk.MemoryPropertyFlags{.HOST_VISIBLE, .DEVICE_LOCAL}
		BLKSize := vkMemSpcialBlockLen if memProp_ >= memFlag else vkMemBlockLen
		memBufT := _Init(BLKSize, maxSize_, memRequire, memProp_)

		if memBufT == nil {
			free(memBuf, vk_def_allocator())
			memBuf = nil

			memProp_ = {.HOST_VISIBLE, .HOST_CACHED}
			for b in gVkMemBufs {
				if b.cellSize != memRequire.alignment do continue
				memType, ok := vk_find_mem_type(memRequire.memoryTypeBits, memProp_)
				if !ok do trace.panic_log("")
				if !_BindBufferNode(b, memType, vkResource, cellCnt, outIdx, &memBuf) do continue
				break
			}
			if memBuf == nil {
				BLKSize = vkMemBlockLen
				memBufT = _Init(BLKSize, maxSize_, memRequire, memProp_)
				if memBufT == nil do trace.panic_log("")
				memBuf^ = memBufT.?
			}
		} else {
			memBuf^ = memBufT.?
		}

		if !_BindBufferNode(memBuf, memBuf.allocateInfo.memoryTypeIndex, vkResource, cellCnt, outIdx, &memBuf) do trace.panic_log("")
		non_zero_append(&gVkMemBufs, memBuf)
		gVkMemIdxCnts[memBuf.allocateInfo.memoryTypeIndex] += 1
	}
	return
}

@(private = "file")
vk_mem_buffer_CreateFromResourceSingle :: proc(vkResource: $T) -> (memBuf: ^vk_mem_buffer) where T == vk.Buffer || T == vk.Image {
	memBuf = nil
	memRequire: vk.MemoryRequirements

	when T == vk.Buffer {
		vk.GetBufferMemoryRequirements(vk_device, vkResource, &memRequire)
	} else when T == vk.Image {
		vk.GetImageMemoryRequirements(vk_device, vkResource, &memRequire)
	}

	memBuf = new(vk_mem_buffer, vk_def_allocator())
	outMemBuf := vk_mem_buffer_InitSingle(memRequire.size, memRequire.memoryTypeBits)
	memBuf^ = outMemBuf.?

	vk_mem_buffer_BindBufferNode(memBuf, vkResource, 1) //can't (must no) error

	non_zero_append(&gVkMemBufs, memBuf)
	return
}

// not mul cellsize
@(private = "file")
vk_mem_buffer_Map :: #force_inline proc "contextless" (
	self: ^vk_mem_buffer,
	start: vk.DeviceSize,
	size: vk.DeviceSize,
) -> [^]byte {
	outData: rawptr
	vk.MapMemory(vk_device, self.deviceMem, start, size, {}, &outData)
	return auto_cast outData
}

@(private = "file")
vk_mem_buffer_UnMap :: #force_inline proc "contextless" (self: ^vk_mem_buffer) {
	self.mapSize = 0
	vk.UnmapMemory(vk_device, self.deviceMem)
}

@(private = "file")
vk_mem_buffer_MapCopyexecute :: proc(self: ^vk_mem_buffer, nodes: []OpNode) {
	startIdx: vk.DeviceSize = max(vk.DeviceSize)
	endIdx: vk.DeviceSize = max(vk.DeviceSize)
	offIdx: u32 = 0

	ranges: [dynamic]vk.MappedMemoryRange
	if self.cache {
		ranges = mem.make_non_zeroed_dynamic_array([dynamic]vk.MappedMemoryRange, context.temp_allocator)
		overlap := mem.make_non_zeroed_dynamic_array([dynamic]^vk_mem_buffer_node, context.temp_allocator)
		defer delete(overlap)

		out: for i in 0 ..< len(nodes) {
			res: ^base_resource = cast(^base_resource)(nodes[i].(OpMapCopy).p_resource)
			idx: ^vk_mem_buffer_node = auto_cast res.idx
			for o in overlap {
				if idx == o {
					continue out
				}
			}
			non_zero_append(&overlap, idx)
			non_zero_resize(&ranges, len(ranges) + 1)
			last := &ranges[len(ranges) - 1]
			last.memory = self.deviceMem
			last.size = idx.size * self.cellSize
			last.offset = idx.idx * self.cellSize

			tmp := last.offset
			last.offset = math.floor_up(last.offset, vk_non_coherent_atom_size)
			last.size += tmp - last.offset
			last.size = math.ceil_up(last.size, vk_non_coherent_atom_size)

			startIdx = min(startIdx, last.offset)
			endIdx = max(endIdx, last.offset + last.size)

			//when range overlaps. merge them.
			for &r in ranges[:offIdx] {
				if r.offset < last.offset + last.size && r.offset + r.size > last.offset {
					end_ := max(last.offset + last.size, r.offset + r.size)
					r.offset = min(last.offset, r.offset)
					r.size = end_ - r.offset

					for &r2 in ranges[:offIdx] {
						if r.offset != r2.offset && r2.offset < r.offset + r.size && r2.offset + r2.size > r.offset { //both sides overlap
							end_2 := max(r2.offset + r.size, r.offset + r.size)
							r.offset = min(r2.offset, r.offset)
							r.size = end_2 - r.offset
							if r2.offset != ranges[offIdx - 1].offset {
								slice.ptr_swap_non_overlapping(
									&ranges[offIdx - 1].offset,
									&r2.offset,
									size_of(r2.offset),
								)
								slice.ptr_swap_non_overlapping(
									&ranges[offIdx - 1].size,
									&r2.size,
									size_of(r2.size),
								)
							}
							offIdx -= 1
							break
						}
					}
					offIdx -= 1
					break
				}
			}

			last.pNext = nil
			last.sType = vk.StructureType.MAPPED_MEMORY_RANGE
			offIdx += 1
		}
	} else {
		for node in nodes {
			res: ^base_resource = cast(^base_resource)(node.(OpMapCopy).p_resource)
			idx: ^vk_mem_buffer_node = auto_cast res.idx
			startIdx = min(startIdx, idx.idx * self.cellSize)
			endIdx = max(endIdx, (idx.idx + idx.size) * self.cellSize)
		}
	}

	size := endIdx - startIdx

	if self.mapStart > startIdx || self.mapSize + self.mapStart < endIdx || self.mapSize < endIdx - startIdx {
		if self.mapSize > 0 do vk_mem_buffer_UnMap(self)
		outData: [^]byte = vk_mem_buffer_Map(self, startIdx, size)
		self.mapData = outData
		self.mapSize = size
		self.mapStart = startIdx
	} else {
		if self.cache {
			res := vk.InvalidateMappedMemoryRanges(vk_device, offIdx, raw_data(ranges))
			if res != .SUCCESS do trace.panic_log("res := vk.InvalidateMappedMemoryRanges(vk_device, offIdx, raw_data(ranges)) : ", res)
		}
	}

	for &node in nodes {
		mapCopy := &node.(OpMapCopy)
		res: ^base_resource = mapCopy.p_resource
		idx: ^vk_mem_buffer_node = auto_cast res.idx
		start_ := idx.idx * self.cellSize - self.mapStart + res.g_uniform_indices[2]
		mem.copy_non_overlapping(&self.mapData[start_], raw_data(mapCopy.data), len(mapCopy.data))

		if mapCopy.allocator != nil {
			delete(mapCopy.data, mapCopy.allocator.?)
			mapCopy.data = nil
			mapCopy.allocator = nil
		}
	}

	if self.cache {
		res := vk.FlushMappedMemoryRanges(vk_device, auto_cast len(ranges), raw_data(ranges))
		if res != .SUCCESS do trace.panic_log("res := vk.FlushMappedMemoryRanges(vk_device, auto_cast len(ranges), raw_data(ranges)) : ", res)

		delete(ranges)
	}
}

@(private = "file")
vk_mem_buffer_IsEmpty :: proc(self: ^vk_mem_buffer) -> bool {
	return !self.single && ((self.list.head != nil &&
		self.list.head.next == nil &&
		((^vk_mem_buffer_node)(self.list.head)).free) ||
		(self.list.head == nil))
}


// ============================================================================
// Private - Op Queue Operations
// ============================================================================

@(private = "file")
append_op :: proc(node: OpNode) {
	sync.atomic_mutex_lock(&gQueueMtx)
	defer sync.atomic_mutex_unlock(&gQueueMtx)

	#partial switch &n in node {
	case OpMapCopy:
		for &op in opQueue {
			#partial switch &o in op {
			case OpMapCopy:
				if o.p_resource == n.p_resource {
					if o.allocator != nil && o.data != nil {
						delete(o.data, o.allocator.?)
					}
					o.allocator = n.allocator
					o.data = n.data
					return
				}
			}
		}
	case OpDestroyBuffer:
		for &op, i in opQueue {
			#partial switch &o in op {
			case OpCreateBuffer:
				if o.src == n.src {
					if o.allocator != nil && o.data != nil {
						delete(o.data, o.allocator.?)
					}
					free(o.src, vk_def_allocator())
					ordered_remove(&opQueue, i)
					return
				}
			}
		}
	case OpDestroyTexture:
		for &op, i in opQueue {
			#partial switch &o in op {
			case OpCreateTexture:
				if o.src == n.src {
					if o.allocator != nil && o.data != nil {
						delete(o.data, o.allocator.?)
					}
					free(o.src, vk_def_allocator())
					ordered_remove(&opQueue, i)
					return
				}
			}
		}
	case OpReleaseUniform:
		for &op, i in opQueue {
			#partial switch &o in op {
			case OpCreateBuffer:
				if o.src == n.src {
					if o.data != nil && o.data != nil {
						delete(o.data, o.allocator.?)
					}
					free(o.src, vk_def_allocator())
					ordered_remove(&opQueue, i)
					return
				}
			}
		}
	}
	non_zero_append(&opQueue, node)
}

@(private = "file")
append_op_save :: proc(node: OpNode) {
	non_zero_append(&opSaveQueue, node)
}

@(private = "file")
save_to_map_queue :: proc(inoutMemBuf: ^^vk_mem_buffer) {
	for &node in opSaveQueue {
		#partial switch &n in node {
		case OpMapCopy:
			res: ^base_resource = n.p_resource
			if inoutMemBuf^ == nil {
				non_zero_append(&opMapQueue, node)
				inoutMemBuf^ = auto_cast res.mem_buffer
				node = nil
			} else if auto_cast res.mem_buffer == inoutMemBuf^ {
				non_zero_append(&opMapQueue, node)
				node = nil
			}
		}
	}
}


// ============================================================================
// Private - Resource Create/Destroy Operations
// ============================================================================

@(private = "file")
buffer_resource_CreateBufferNoAsync :: #force_inline proc(
	self: ^buffer_resource,
	option: buffer_create_option,
	data: []byte,
	allocator: Maybe(runtime.Allocator) = nil,
) {
	self.option = option
	executeCreateBuffer(self, data, allocator)
}

@(private = "file")
buffer_resource_DestroyBufferNoAsync :: proc(self: ^buffer_resource) {
	vk_mem_buffer_UnBindBufferNode(auto_cast self.mem_buffer, self.__resource, self.idx)
	free(self, vk_def_allocator())
}

@(private = "file")
buffer_resource_DestroyTextureNoAsync :: proc(self: ^texture_resource) {
	vk.DestroyImageView(vk_device, self.img_view, nil)
	vk_mem_buffer_UnBindBufferNode(auto_cast self.mem_buffer, self.__resource, self.idx)
	free(self, vk_def_allocator())
}

@(private = "file")
buffer_resource_MapCopy :: #force_inline proc(
	self: ^base_resource,
	data: []byte,
	allocator: Maybe(runtime.Allocator) = nil,
) {
	append_op(OpMapCopy{
		p_resource = self,
		data       = data,
		allocator  = allocator,
	})
}

@(private = "file")
executeCreateBuffer :: proc(
	self: ^buffer_resource,
	data: []byte,
	allocator: Maybe(runtime.Allocator) = nil,
) {
	if self.option.type == .__STAGING {
		self.option.resource_usage = .CPU
		self.option.single = false
	}

	memProp: vk.MemoryPropertyFlags
	switch self.option.resource_usage {
	case .GPU:
		memProp = {.DEVICE_LOCAL}
	case .CPU:
		memProp = {.HOST_CACHED, .HOST_VISIBLE}
	}
	bufUsage: vk.BufferUsageFlags
	switch self.option.type {
	case .VERTEX:
		bufUsage = {.VERTEX_BUFFER}
	case .INDEX:
		bufUsage = {.INDEX_BUFFER}
	case .UNIFORM: //bufUsage = {.UNIFORM_BUFFER} no create each obj
		if self.option.resource_usage == .GPU do trace.panic_log("UNIFORM BUFFER can't resource_usage .GPU")
		bind_uniform_buffer(self, data, allocator)
		return
	case .STORAGE:
		bufUsage = {.STORAGE_BUFFER}
	case .__STAGING:
		bufUsage = {.TRANSFER_SRC}
	}

	bufInfo := vk.BufferCreateInfo {
		sType       = .BUFFER_CREATE_INFO,
		size        = self.option.len,
		usage       = bufUsage,
		sharingMode = .EXCLUSIVE,
	}

	last: ^buffer_resource
	if data != nil && self.option.resource_usage == .GPU {
		bufInfo.usage |= {.TRANSFER_DST}
		if self.option.len > auto_cast len(data) do trace.panic_log("create_buffer _data not enough size. ", self.option.len, ", ", len(data))

		last = new(buffer_resource, vk_def_allocator())
		buffer_resource_CreateBufferNoAsync(last, {
			len            = self.option.len,
			resource_usage = .CPU,
			single         = false,
			type           = .__STAGING,
		}, data, allocator)
	} else if self.option.type == .__STAGING {
		if data == nil do trace.panic_log("staging buffer data can't nil")
	}

	res := vk.CreateBuffer(vk_device, &bufInfo, nil, &self.__resource)
	if res != .SUCCESS do trace.panic_log("res := vk.CreateBuffer(vk_device, &bufInfo, nil, &self.__resource) : ", res)

	self.mem_buffer = auto_cast vk_mem_buffer_CreateFromResourceSingle(self.__resource) if self.option.single else auto_cast vk_mem_buffer_CreateFromResource(self.__resource, memProp, &self.idx, 0)

	if data != nil {
		if self.option.resource_usage != .GPU {
			append_op_save(OpMapCopy{
				p_resource = self,
				data       = data,
			})
		} else {
			//above buffer_resource_CreateBufferNoAsync call, staging buffer is added and map_copy command is added.
			append_op_save(OpCopyBuffer{src = last, target = self, data = data, allocator = allocator})
			append_op_save(OpDestroyBuffer{src = last})
		}
	}
}

@(private = "file")
executeCreateTexture :: proc(
	self: ^texture_resource,
	data: []byte,
	allocator: Maybe(runtime.Allocator) = nil,
) {
	memProp: vk.MemoryPropertyFlags
	switch self.option.resource_usage {
	case .GPU:
		memProp = {.DEVICE_LOCAL}
	case .CPU:
		memProp = {.HOST_CACHED, .HOST_VISIBLE}
	}
	texUsage: vk.ImageUsageFlags = {}
	isDepth := texture_fmt_is_depth(self.option.format)

	if .IMAGE_RESOURCE in self.option.texture_usage do texUsage |= {.SAMPLED}
	if .FRAME_BUFFER in self.option.texture_usage {
		if isDepth {
			texUsage |= {.DEPTH_STENCIL_ATTACHMENT}
		} else {
			texUsage |= {.COLOR_ATTACHMENT}
		}
	}
	if .__INPUT_ATTACHMENT in self.option.texture_usage do texUsage |= {.INPUT_ATTACHMENT}
	if .__STORAGE_IMAGE in self.option.texture_usage do texUsage |= {.STORAGE}
	if .__TRANSIENT_ATTACHMENT in self.option.texture_usage do texUsage |= {.TRANSIENT_ATTACHMENT}

	tiling: vk.ImageTiling = .OPTIMAL

	if isDepth {
		if (.DEPTH_STENCIL_ATTACHMENT in texUsage && !vkDepthHasOptimal) ||
		   (.SAMPLED in texUsage && !vkDepthHasSampleOptimal) ||
		   (.TRANSFER_SRC in texUsage && !vkDepthHasTransferSrcOptimal) ||
		   (.TRANSFER_DST in texUsage && !vkDepthHasTransferDstOptimal) {
			tiling = .LINEAR
		}
	} else {
		if (.COLOR_ATTACHMENT in texUsage && !vkColorHasAttachOptimal) ||
		   (.SAMPLED in texUsage && !vkColorHasSampleOptimal) ||
		   (.TRANSFER_SRC in texUsage && !vkColorHasTransferSrcOptimal) ||
		   (.TRANSFER_DST in texUsage && !vkColorHasTransferDstOptimal) {
			tiling = .LINEAR
		}
	}
	bit: u32 = auto_cast texture_fmt_bit_size(self.option.format)

	imgInfo := vk.ImageCreateInfo {
		sType         = .IMAGE_CREATE_INFO,
		arrayLayers   = self.option.len,
		usage         = texUsage,
		sharingMode   = .EXCLUSIVE,
		extent        = {width = self.option.width, height = self.option.height, depth = 1},
		samples       = samples_to_vk_sample_count_flags(self.option.samples),
		tiling        = tiling,
		mipLevels     = 1,
		format        = texture_fmt_to_vk_fmt(self.option.format),
		imageType     = texture_type_to_vk_image_type(self.option.type),
		initialLayout = .UNDEFINED,
	}

	last: ^buffer_resource
	if data != nil && self.option.resource_usage == .GPU {
		imgInfo.usage |= {.TRANSFER_DST}

		last = new(buffer_resource, vk_def_allocator())
		buffer_resource_CreateBufferNoAsync(last, {
			len            = auto_cast (imgInfo.extent.width * imgInfo.extent.height * imgInfo.extent.depth * imgInfo.arrayLayers * bit),
			resource_usage = .CPU,
			single         = false,
			type           = .__STAGING,
		}, data, allocator)
	}

	res := vk.CreateImage(vk_device, &imgInfo, nil, &self.__resource)
	if res != .SUCCESS do trace.panic_log("res := vk.CreateImage(vk_device, &bufInfo, nil, &self.__resource) : ", res)

	self.mem_buffer = auto_cast vk_mem_buffer_CreateFromResourceSingle(self.__resource) if self.option.single else auto_cast vk_mem_buffer_CreateFromResource(self.__resource, memProp, &self.idx, 0)

	imgViewInfo := vk.ImageViewCreateInfo {
		sType      = .IMAGE_VIEW_CREATE_INFO,
		format     = imgInfo.format,
		components = {r = .IDENTITY, g = .IDENTITY, b = .IDENTITY, a = .IDENTITY},
		image      = self.__resource,
		subresourceRange = {
			aspectMask     = isDepth ? {.DEPTH, .STENCIL} : {.COLOR},
			baseMipLevel   = 0,
			levelCount     = 1,
			baseArrayLayer = 0,
			layerCount     = imgInfo.arrayLayers,
		},
	}
	switch self.option.type {
	case .TEX2D:
		imgViewInfo.viewType = imgInfo.arrayLayers > 1 ? .D2_ARRAY : .D2
	}

	res = vk.CreateImageView(vk_device, &imgViewInfo, nil, &self.img_view)
	if res != .SUCCESS do trace.panic_log("res = vk.CreateImageView(vk_device, &imgViewInfo, nil, &self.img_view) : ", res)

	if data != nil {
		if self.option.resource_usage != .GPU {
			append_op_save(OpMapCopy{
				p_resource = self,
				data       = data,
				allocator  = allocator,
			})
		} else {
			//above buffer_resource_CreateBufferNoAsync call, staging buffer is added and map_copy command is added.
			append_op_save(OpCopyBufferToTexture{src = last, target = self, data = data, allocator = allocator})
			append_op_save(OpDestroyBuffer{src = last})
		}
	}
}

@(private = "file")
executeDestroyBuffer :: proc(buf: ^buffer_resource) {
	buffer_resource_DestroyBufferNoAsync(buf)
}

@(private = "file")
executeDestroyTexture :: proc(tex: ^texture_resource) {
	buffer_resource_DestroyTextureNoAsync(tex)
}


// ============================================================================
// Private - Uniform Operations
// ============================================================================

@(private = "file")
bind_uniform_buffer :: proc(
	self: ^buffer_resource,
	data: []byte,
	allocator: Maybe(runtime.Allocator),
) {
	if gVkMinUniformBufferOffsetAlignment > 0 {
		// Align the length up to the minimum uniform buffer offset alignment requirement
		self.option.len = (self.option.len + gVkMinUniformBufferOffsetAlignment - 1) & ~(gVkMinUniformBufferOffsetAlignment - 1)
	}
	non_zero_append(&gTempUniforms, vk_temp_uniform_struct{uniform = self, data = data, size = self.option.len, allocator = allocator})
}

// uniform을 특정 버퍼에 할당
@(private = "file")
assign_uniform_to_buffer :: proc(
	t: ^vk_temp_uniform_struct,
	g: ^vk_uniform_alloc,
	g_idx: int,
	uniform_idx: int,
	offset: vk.DeviceSize,
) {
	t.uniform.g_uniform_indices[0] = auto_cast g_idx
	t.uniform.g_uniform_indices[1] = auto_cast uniform_idx
	t.uniform.g_uniform_indices[2] = offset
	t.uniform.g_uniform_indices[3] = t.size
	t.uniform.__resource = g.buf
	t.uniform.mem_buffer = auto_cast g.mem_buffer
	t.uniform.idx = g.idx

	append_op_save(OpMapCopy{
		p_resource = t.uniform,
		data       = t.data,
		allocator  = t.allocator,
	})
}

// 새 uniform 버퍼 생성 및 uniform들 할당
@(private = "file")
create_new_uniform_buffer :: proc(
	uniforms: []vk_temp_uniform_struct,
) {
	all_size: vk.DeviceSize = 0
	for t in uniforms {
		all_size += t.size
	}

	g_idx := len(gUniforms)
	resize_dynamic_array(&gUniforms, g_idx + 1)
	g := &gUniforms[g_idx]

	g^ = {
		max_size = max(vkUniformSizeBlock, all_size),
		size     = all_size,
		uniforms = mem.make_non_zeroed_dynamic_array([dynamic]^buffer_resource, vk_def_allocator()),
	}

	bufInfo: vk.BufferCreateInfo = {
		sType = vk.StructureType.BUFFER_CREATE_INFO,
		size  = g.max_size,
		usage = {.UNIFORM_BUFFER},
	}
	res := vk.CreateBuffer(vk_device, &bufInfo, nil, &g.buf)
	if res != .SUCCESS do trace.panic_log("res := vk.CreateBuffer(vk_device, &bufInfo, nil, &self.__resource) : ", res)

	g.mem_buffer = vk_mem_buffer_CreateFromResource(g.buf, {.HOST_CACHED, .HOST_VISIBLE}, &g.idx, 0)

	off: vk.DeviceSize = 0
	for &t, i in uniforms {
		non_zero_append(&g.uniforms, t.uniform)
		assign_uniform_to_buffer(&t, g, g_idx, i, off)
		off += t.size
	}
}

@(private = "file")
executeReleaseUniform :: proc(
	buf: ^buffer_resource,
) {
	gUniforms[buf.g_uniform_indices[0]].uniforms[buf.g_uniform_indices[1]] = nil

	empty := true
	for &v in gUniforms[buf.g_uniform_indices[0]].uniforms {
		if v != nil {
			empty = false
			break
		}
	}
	if empty {
		delete(gUniforms[buf.g_uniform_indices[0]].uniforms)
		gUniforms[buf.g_uniform_indices[0]] = {}
		buffer_resource_DestroyBufferNoAsync(buf)

		return
	} else {
		free(buf, vk_def_allocator())
	}
}


// ============================================================================
// Private - Descriptor Operations
// ============================================================================

@(private = "file")
executeRegisterDescriptorPool :: #force_inline proc(size: []descriptor_pool_size) {
	//?? no need? execute_register_descriptor_pool
}

@(private = "file")
__create_descriptor_pool :: proc(size: []descriptor_pool_size, out: ^descriptor_pool_mem) {
	poolSize: []vk.DescriptorPoolSize = mem.make_non_zeroed([]vk.DescriptorPoolSize, len(size))
	defer delete(poolSize)

	for _, i in size {
		poolSize[i].descriptorCount = size[i].cnt * vkPoolBlock
		poolSize[i].type = descriptor_type_to_vk_descriptor_type(size[i].type)
	}
	poolInfo := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		poolSizeCount = auto_cast len(poolSize),
		pPoolSizes    = raw_data(poolSize),
		maxSets       = vkPoolBlock,
	}
	res := vk.CreateDescriptorPool(vk_device, &poolInfo, nil, &out.pool)
	if res != .SUCCESS do trace.panic_log("res := vk.CreateDescriptorPool(vk_device, &poolInfo, nil, &out.pool) : ", res)
}

@(private = "file")
execute_update_descriptor_sets :: proc(sets: []descriptor_set) {
	for &s in sets {
		if s.__set == 0 {
			if raw_data(s.size) in gDesciptorPools {
			} else {
				gDesciptorPools[raw_data(s.size)] = mem.make_non_zeroed([dynamic]descriptor_pool_mem, vk_def_allocator())
				non_zero_append(&gDesciptorPools[raw_data(s.size)], descriptor_pool_mem{cnt = 0})
				__create_descriptor_pool(s.size, &gDesciptorPools[raw_data(s.size)][0])
			}

			last := &gDesciptorPools[raw_data(s.size)][len(gDesciptorPools[raw_data(s.size)]) - 1]
			if last.cnt >= vkPoolBlock {
				non_zero_append(&gDesciptorPools[raw_data(s.size)], descriptor_pool_mem{cnt = 0})
				last = &gDesciptorPools[raw_data(s.size)][len(gDesciptorPools[raw_data(s.size)]) - 1]
				__create_descriptor_pool(s.size, last)
			}

			last.cnt += 1
			allocInfo := vk.DescriptorSetAllocateInfo {
				sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
				descriptorPool     = last.pool,
				descriptorSetCount = 1,
				pSetLayouts        = &s.layout,
			}
			res := vk.AllocateDescriptorSets(vk_device, &allocInfo, &s.__set)
			if res != .SUCCESS do trace.panic_log("res := vk.AllocateDescriptorSets(vk_device, &allocInfo, &s.__set) : ", res)
		}

		cnt: u32 = 0
		bufCnt: u32 = 0
		texCnt: u32 = 0

		//sets[i].__resources array must match v.size configuration.
		for s in s.size {
			cnt += s.cnt
		}

		for r in s.__resources[0:cnt] {
			switch (^base_resource)(r).type {
			case .BUFFER:
				bufCnt += 1
			case .TEXTURE:
				texCnt += 1
			}
		}

		bufs := mem.make_non_zeroed([]vk.DescriptorBufferInfo, bufCnt, __temp_arena_allocator)
		texs := mem.make_non_zeroed([]vk.DescriptorImageInfo, texCnt, __temp_arena_allocator)
		bufCnt = 0
		texCnt = 0

		for r in s.__resources[0:cnt] {
			switch (^base_resource)(r).type {
			case .BUFFER:
				bufs[bufCnt] = vk.DescriptorBufferInfo {
					buffer = ((^buffer_resource)(r)).__resource,
					offset = ((^buffer_resource)(r)).g_uniform_indices[2],
					range  = ((^buffer_resource)(r)).option.len,
				}
				bufCnt += 1
			case .TEXTURE:
				texs[texCnt] = vk.DescriptorImageInfo {
					imageLayout = .SHADER_READ_ONLY_OPTIMAL,
					imageView   = ((^texture_resource)(r)).img_view,
					sampler     = ((^texture_resource)(r)).sampler,
				}
				texCnt += 1
			}
		}

		bufCnt = 0
		texCnt = 0
		for n, i in s.size {
			switch n.type {
			case .SAMPLER, .STORAGE_IMAGE:
				non_zero_append(&gVkUpdateDesciptorSetList, vk.WriteDescriptorSet {
					dstSet          = s.__set,
					dstBinding      = s.bindings[i],
					dstArrayElement = 0,
					descriptorCount = n.cnt,
					descriptorType  = descriptor_type_to_vk_descriptor_type(n.type),
					pBufferInfo     = nil,
					pImageInfo      = &texs[texCnt],
					pTexelBufferView = nil,
					sType           = .WRITE_DESCRIPTOR_SET,
					pNext           = nil,
				})
				texCnt += n.cnt
			case .UNIFORM, .STORAGE, .UNIFORM_DYNAMIC:
				non_zero_append(&gVkUpdateDesciptorSetList, vk.WriteDescriptorSet {
					dstSet          = s.__set,
					dstBinding      = s.bindings[i],
					dstArrayElement = 0,
					descriptorCount = n.cnt,
					descriptorType  = descriptor_type_to_vk_descriptor_type(n.type),
					pBufferInfo     = &bufs[bufCnt],
					pImageInfo      = nil,
					pTexelBufferView = nil,
					sType           = .WRITE_DESCRIPTOR_SET,
					pNext           = nil,
				})
				bufCnt += n.cnt
			}
		}
	}
}


// ============================================================================
// Private - Copy Operations
// ============================================================================

@(private = "file")
execute_copy_buffer :: proc(src: ^buffer_resource, target: ^buffer_resource) {
	copyRegion := vk.BufferCopy {
		size      = target.option.len,
		srcOffset = 0,
		dstOffset = 0,
	}
	vk.CmdCopyBuffer(gCmd, src.__resource, target.__resource, 1, &copyRegion)
}

@(private = "file")
execute_copy_buffer_to_texture :: proc(src: ^buffer_resource, target: ^texture_resource) {
	vk_transition_image_layout(gCmd, target.__resource, 1, 0, target.option.len, .UNDEFINED, .TRANSFER_DST_OPTIMAL)
	region := vk.BufferImageCopy {
		bufferOffset      = 0,
		bufferRowLength   = 0,
		bufferImageHeight = 0,
		imageOffset       = {x = 0, y = 0, z = 0},
		imageExtent       = {width = target.option.width, height = target.option.height, depth = 1},
		imageSubresource  = {
			aspectMask     = {.COLOR},
			baseArrayLayer = 0,
			mipLevel       = 0,
			layerCount     = target.option.len,
		},
	}
	vk.CmdCopyBufferToImage(gCmd, src.__resource, target.__resource, .TRANSFER_DST_OPTIMAL, 1, &region)
	vk_transition_image_layout(gCmd, target.__resource, 1, 0, target.option.len, .TRANSFER_DST_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL)
}
