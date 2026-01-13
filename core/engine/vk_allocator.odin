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


vkMemBlockLen: vk.DeviceSize = mem.Megabyte * 256
vkMemSpcialBlockLen: vk.DeviceSize = mem.Megabyte * 256
vk_non_coherent_atom_size: vk.DeviceSize = 0
vkPoolBlock :: 256
vkUniformSizeBlock :: mem.Megabyte
vkSupportCacheLocal := false
vkSupportNonCacheLocal := false
@(private = "file") __tempArena: virtual.Arena
@(private = "file") gQueueMtx: sync.Atomic_Mutex
@(private = "file") gDestroyQueueMtx: sync.Atomic_Mutex

OpMapCopy :: struct {
	pData:      ^resource_data,
}
OpCopyBuffer :: struct {
	src:    ^buffer_resource,
	target: ^buffer_resource,
}
OpCopyBufferToTexture :: struct {
	src:    ^buffer_resource,
	target: ^texture_resource,
}
OpCreateBuffer :: struct {
	src:       ^buffer_resource,
}
OpCreateTexture :: struct {
	src:       ^texture_resource,
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
//doesn't need to call outside
Op__RegisterDescriptorPool :: struct {
	size: []descriptor_pool_size,
}


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

vk_mem_buffer_node :: struct {
    node : list.Node,
    size:vk.DeviceSize,
    idx:vk.DeviceSize,
    free:bool
}
vk_mem_buffer :: struct {
    cellSize:vk.DeviceSize,
    mapStart:vk.DeviceSize,
    mapSize:vk.DeviceSize,
    mapData:[^]byte,
    len:vk.DeviceSize,
    deviceMem:vk.DeviceMemory,
    single:bool,
    cache:bool,
    cur:^list.Node,
    list:list.List,
    allocateInfo:vk.MemoryAllocateInfo,
}


vk_temp_uniform_struct :: struct {
	uniform:^buffer_resource,
	data:[]byte,
	size:vk.DeviceSize,
	allocator: Maybe(runtime.Allocator),
}

vk_uniform_alloc :: struct {
	max_size: vk.DeviceSize,
	size:vk.DeviceSize,
	uniforms:[dynamic]^buffer_resource,
	buf:vk.Buffer,
	idx:resource_range,
	mem_buffer:^vk_mem_buffer,
}

@(private="file") cmdPool:vk.CommandPool
@(private="file") gCmd:vk.CommandBuffer
@(private="file") opQueue:[dynamic]OpNode
@(private="file") opSaveQueue:[dynamic]OpNode
@(private="file") opMapQueue:[dynamic]OpNode
@(private="file") opAllocQueue:[dynamic]OpNode
@(private="file") opDestroyQueue:[dynamic]OpNode
@(private="file") gVkUpdateDesciptorSetList:[dynamic]vk.WriteDescriptorSet
@(private="file") gDesciptorPools:map[[^]descriptor_pool_size][dynamic]descriptor_pool_mem
@(private="file") gUniforms:[dynamic]vk_uniform_alloc
@(private="file") gTempUniforms:[dynamic]vk_temp_uniform_struct
@(private="file") gNonInsertedUniforms:[dynamic]vk_temp_uniform_struct

@(private="file") gWaitOpSem:sync.Sema

gVkMinUniformBufferOffsetAlignment : vk.DeviceSize = 0

vk_wait_all_op :: #force_inline proc "contextless" () {
	sync.sema_wait(&gWaitOpSem)
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
	gVkMemBufs = mem.make_non_zeroed([dynamic]^vk_mem_buffer, def_allocator())

	gVkMemIdxCnts = mem.make_non_zeroed([]int, vk_physical_mem_prop.memoryTypeCount, def_allocator())
	mem.zero_slice(gVkMemIdxCnts)

	_ = virtual.arena_init_growing(&__tempArena)

	__temp_arena_allocator = virtual.arena_allocator(&__tempArena)

	cmdPoolInfo := vk.CommandPoolCreateInfo {
		sType            = vk.StructureType.COMMAND_POOL_CREATE_INFO,
		queueFamilyIndex = vk_graphics_family_index,
	}
	vk.CreateCommandPool(vk_device, &cmdPoolInfo, nil, &cmdPool)

	cmdAllocInfo := vk.CommandBufferAllocateInfo {
		sType = vk.StructureType.COMMAND_BUFFER_ALLOCATE_INFO,
		commandBufferCount = 1,
		level              = .PRIMARY,
		commandPool        = cmdPool,
	}
	vk.AllocateCommandBuffers(vk_device, &cmdAllocInfo, &gCmd)

	opQueue = mem.make_non_zeroed([dynamic]OpNode, def_allocator())
	opSaveQueue = mem.make_non_zeroed([dynamic]OpNode, def_allocator())
	opMapQueue = mem.make_non_zeroed([dynamic]OpNode, def_allocator())
	opAllocQueue = mem.make_non_zeroed([dynamic]OpNode, def_allocator())
	opDestroyQueue = mem.make_non_zeroed([dynamic]OpNode, def_allocator())
	gVkUpdateDesciptorSetList = mem.make_non_zeroed([dynamic]vk.WriteDescriptorSet, def_allocator())

	gUniforms = mem.make_non_zeroed([dynamic]vk_uniform_alloc, def_allocator())
	gTempUniforms = mem.make_non_zeroed([dynamic]vk_temp_uniform_struct, def_allocator())
	gNonInsertedUniforms = mem.make_non_zeroed([dynamic]vk_temp_uniform_struct, def_allocator())
}

vk_allocator_destroy :: proc() {
	op_alloc_queue_free()

	for b in gVkMemBufs {
		vk_mem_buffer_Deinit2(b)
		free(b, def_allocator())
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
	delete(opAllocQueue)
	delete(opDestroyQueue)

	virtual.arena_destroy(&__tempArena)

	delete(gVkMemIdxCnts, def_allocator())
}

@(private = "file") gVkMemBufs: [dynamic]^vk_mem_buffer
@(private = "file") VkMaxMemIdxCnt : int : 4
@(private = "file") gVkMemIdxCnts: []int



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
// ! don't call vulkan_res.init separately
@(private = "file") vk_mem_buffer_Init :: proc(
	cellSize: vk.DeviceSize,
	len: vk.DeviceSize,
	typeFilter: u32,
	memProp: vk.MemoryPropertyFlags,
) -> Maybe(vk_mem_buffer) {
	memBuf := vk_mem_buffer {
		cellSize = cellSize,
		len = len,
		allocateInfo = {sType = .MEMORY_ALLOCATE_INFO, allocationSize = len * cellSize},
		cache = vk.MemoryPropertyFlags{.HOST_VISIBLE, .HOST_CACHED} <= memProp,
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


	list.push_back(&memBuf.list, auto_cast new(vk_mem_buffer_node, def_allocator()))
	((^vk_mem_buffer_node)(memBuf.list.head)).free = true
	((^vk_mem_buffer_node)(memBuf.list.head)).size = memBuf.len
	((^vk_mem_buffer_node)(memBuf.list.head)).idx = 0
	memBuf.cur = memBuf.list.head

	return memBuf
}
@(private = "file") vk_mem_buffer_InitSingle :: proc(cellSize: vk.DeviceSize, typeFilter: u32) -> Maybe(vk_mem_buffer) {
	memBuf := vk_mem_buffer {
		cellSize = cellSize,
		len = 1,
		allocateInfo = {sType = .MEMORY_ALLOCATE_INFO, allocationSize = 1 * cellSize},
		single = true,
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
@(private = "file") vk_mem_buffer_Deinit2 :: proc(self: ^vk_mem_buffer) {
	vk.FreeMemory(vk_device, self.deviceMem, nil)
	if !self.single {
		n: ^list.Node
		for n = self.list.head; n.next != nil;  {
			tmp := n
			n = n.next
			free(tmp, def_allocator())
		}
		free(n, def_allocator())
		self.list.head = nil
		self.list.tail = nil
	}
}
@(private = "file") vk_mem_buffer_Deinit :: proc(self: ^vk_mem_buffer) {
	for b, i in gVkMemBufs {
		if b == self {
			ordered_remove(&gVkMemBufs, i) //!no unordered
			break
		}
	}
	if !self.single do gVkMemIdxCnts[self.allocateInfo.memoryTypeIndex] -= 1
	vk_mem_buffer_Deinit2(self)
	free(self, def_allocator())
}

vk_allocator_error :: enum {
	NONE,
	DEVICE_MEMORY_LIMIT,
}

@(private = "file") vk_mem_buffer_BindBufferNode :: proc(
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
	remain := cur.size - cellCnt
	self.cur = auto_cast cur

	range: resource_range = auto_cast cur
	curNext: ^vk_mem_buffer_node = auto_cast  (cur.node.next if cur.node.next != nil else self.list.head)
	if cur == curNext {
		if remain > 0 {
			list.push_back(&self.list, auto_cast new(vk_mem_buffer_node, def_allocator()))
			tail: ^vk_mem_buffer_node = auto_cast self.list.tail
			tail.free = true
			tail.size = remain
			tail.idx = cellCnt
		}
	} else {
		if remain > 0 {
			if !curNext.free || curNext.idx < cur.idx {
				list.insert_after(&self.list, auto_cast cur, auto_cast new(vk_mem_buffer_node, def_allocator()))
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
@(private = "file") vk_mem_buffer_UnBindBufferNode :: proc(
	self: ^vk_mem_buffer,
	vkResource: $T,
	range: resource_range,
) where T == vk.Buffer ||
	T == vk.Image {
		
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

	next: ^vk_mem_buffer_node = auto_cast (range_.node.next if range_.node.next != nil else self.list.head)
	if next.free && range_ != next && range_.idx < next.idx {
		range_.size += next.size
		list.remove(&self.list, auto_cast next)
		free(next, def_allocator())
	}

	prev: ^vk_mem_buffer_node = auto_cast (range_.node.prev if range_.node.prev != nil else self.list.tail)
	if prev.free && range_ != prev && range_.idx > prev.idx {
		range_.size += prev.size
		range_.idx -= prev.size
		list.remove(&self.list, auto_cast prev)
		free(prev, def_allocator())
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
	if self.list.head == nil {//?always self.list.head not nil when list is not empty
		list.push_back(&self.list, auto_cast new(vk_mem_buffer_node, def_allocator()))
		((^vk_mem_buffer_node)(self.list.head)).free = true
		((^vk_mem_buffer_node)(self.list.head)).size = self.len
		((^vk_mem_buffer_node)(self.list.head)).idx = 0
		self.cur = self.list.head
	}
}

@(private = "file") vk_mem_buffer_CreateFromResource :: proc(
	vkResource: $T,
	memProp: vk.MemoryPropertyFlags,
	outIdx: ^resource_range,
	maxSize: vk.DeviceSize,
) -> (memBuf: ^vk_mem_buffer) where T == vk.Buffer || T == vk.Image {
	memType:u32
	ok:bool

	_BindBufferNode :: proc(b: ^vk_mem_buffer, memType: u32, vkResource: $T, cellCnt:vk.DeviceSize, outIdx: ^resource_range, memBuf: ^^vk_mem_buffer) -> bool {
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
	_Init :: proc(BLKSize:vk.DeviceSize, maxSize_:vk.DeviceSize, memRequire: vk.MemoryRequirements, memProp_:vk.MemoryPropertyFlags) -> Maybe(vk_mem_buffer) {
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
		   ((T == vk.Buffer && maxSize_ <= 256))) &&
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
		memBuf = new(vk_mem_buffer, def_allocator())

		memFlag := vk.MemoryPropertyFlags{.HOST_VISIBLE, .DEVICE_LOCAL}
		BLKSize := vkMemSpcialBlockLen if memProp_ >= memFlag else vkMemBlockLen
		memBufT := _Init(BLKSize, maxSize_, memRequire, memProp_)

		if memBufT == nil {
			free(memBuf)
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

@(private = "file") vk_mem_buffer_CreateFromResourceSingle :: proc(vkResource: $T) -> (memBuf: ^vk_mem_buffer) 
where T == vk.Buffer || T == vk.Image {
	memBuf = nil
	memRequire: vk.MemoryRequirements

	when T == vk.Buffer {
		vk.GetBufferMemoryRequirements(vk_device, vkResource, &memRequire)
	} else when T == vk.Image {
		vk.GetImageMemoryRequirements(vk_device, vkResource, &memRequire)
	}

	memBuf = new(vk_mem_buffer, def_allocator())
	outMemBuf :=  vk_mem_buffer_InitSingle(memRequire.size, memRequire.memoryTypeBits)
	memBuf^ = outMemBuf.?

	vk_mem_buffer_BindBufferNode(memBuf, vkResource, 1) //can't (must no) error

	non_zero_append(&gVkMemBufs, memBuf)
	return
}

@(private = "file") AppendOp :: proc(node: OpNode) {
	sync.atomic_mutex_lock(&gQueueMtx)
	defer sync.atomic_mutex_unlock(&gQueueMtx)

	if exiting() {
		#partial switch n in node {
		case OpMapCopy:
			if n.pData.allocator != nil && n.pData.data != nil {
				delete(n.pData.data, n.pData.allocator.?)
				n.pData.data = nil
				n.pData.allocator = nil
			}
			return
		case OpCreateBuffer:
			if n.src.data.allocator != nil && n.src.data.data != nil {
				delete(n.src.data.data, n.src.data.allocator.?)
				n.src.data.data = nil
				n.src.data.allocator = nil
			}
			return
		case OpCreateTexture:
			if n.src.data.allocator != nil && n.src.data.data != nil {
				delete(n.src.data.data, n.src.data.allocator.?)
				n.src.data.data = nil
				n.src.data.allocator = nil
			}
			return
		}
	} else {
		_Handle :: #force_inline proc(n: $T, allocator : Maybe(runtime.Allocator)) -> bool {
			if allocator != nil {
				non_zero_append(&opQueue, n)
				non_zero_append(&opAllocQueue, n)
				return true
			}
			return false
		}
		#partial switch n in node {
		case OpMapCopy:
			n.pData.is_creating_modifing = true
			if _Handle(n, n.pData.allocator) do return
		case OpCreateBuffer:
			n.src.data.is_creating_modifing = true
			if _Handle(n, n.src.data.allocator ) do return
		case OpCreateTexture:
			n.src.data.is_creating_modifing = true
			if _Handle(n, n.src.data.allocator ) do return
		}
	}
	#partial switch &n in node {
		case OpDestroyBuffer:
			if n.src.data.is_creating_modifing {
				n.src.data.is_creating_modifing = false
				if n.src.data.allocator != nil && n.src.data.data != nil {
					delete(n.src.data.data, n.src.data.allocator.?)
					n.src.data.data = nil
					n.src.data.allocator = nil
				}
				return
			}
			tmp := n.src
			n.src = new(buffer_resource, temp_arena_allocator())
			n.src^ = tmp^
		case OpDestroyTexture:
			if n.src.data.is_creating_modifing {
				n.src.data.is_creating_modifing = false
				if n.src.data.allocator != nil && n.src.data.data != nil {
					delete(n.src.data.data, n.src.data.allocator.?)
					n.src.data.data = nil
					n.src.data.allocator = nil
				}
				return
			}
			tmp := n.src
			n.src = new(texture_resource, temp_arena_allocator())
			n.src^ = tmp^
	}
	non_zero_append(&opQueue, node)
}

@(private = "file") append_op_save :: proc(node: OpNode) {
	non_zero_append(&opSaveQueue, node)
	#partial switch n in node {
	case OpMapCopy, OpCreateBuffer, OpCreateTexture:
		sync.atomic_mutex_lock(&gQueueMtx)
		non_zero_append(&opAllocQueue, node)
		sync.atomic_mutex_unlock(&gQueueMtx)
	}
}


vkbuffer_resource_create_buffer :: proc(
	self: ^buffer_resource,
	option: buffer_create_option,
	data: []byte,
	isCopy: bool = false,
	allocator: Maybe(runtime.Allocator) = nil,
) {
	self.option = option
	if isCopy {
		copyData:[]byte
		if allocator == nil {
			copyData = mem.make_non_zeroed([]byte, len(data), def_allocator())
		} else {
			copyData = mem.make_non_zeroed([]byte, len(data), allocator.?)
		}
		mem.copy(raw_data(copyData), raw_data(data), len(data))
		self.data.allocator = allocator == nil ? def_allocator() : allocator.?
		self.data.data = copyData
		
		AppendOp(OpCreateBuffer{src = self})
	} else {
		self.data.allocator = allocator
		self.data.data = data
		AppendOp(OpCreateBuffer{src = self})
	}
}
vkbuffer_resource_create_texture :: proc(
	self: ^texture_resource,
	option: texture_create_option,
	sampler: vk.Sampler,
	data: []byte,
	isCopy: bool = false,
	allocator: Maybe(runtime.Allocator) = nil,
) {
	self.sampler = sampler
	self.option = option
	if isCopy {
		copyData:[]byte
		if allocator == nil {
			copyData = mem.make_non_zeroed([]byte, len(data), def_allocator())
		} else {
			copyData = mem.make_non_zeroed([]byte, len(data), allocator.?)
		}
		mem.copy(raw_data(copyData), raw_data(data), len(data))
		self.data.allocator = allocator == nil ? def_allocator() : allocator.?
		self.data.data = copyData
		AppendOp(OpCreateTexture{src = self})
	} else {
		self.data.allocator = allocator
		self.data.data = data
		AppendOp(OpCreateTexture{src = self})
	}
}

@(private = "file") buffer_resource_CreateBufferNoAsync :: #force_inline proc(
	self: ^buffer_resource,
	option: buffer_create_option,
) {
	self.option = option
	self.data.is_creating_modifing = true
	executeCreateBuffer(self)
}

@(private = "file") buffer_resource_DestroyBufferNoAsync :: proc(self: ^buffer_resource) {
	vk_mem_buffer_UnBindBufferNode(auto_cast self.mem_buffer, self.__resource, self.idx)

	if self.data.allocator != nil && self.data.data != nil {
		delete(self.data.data, self.data.allocator.?)	
	}
	self.data.data = nil
	self.data.allocator = nil
	self.__resource = 0
}

@(private = "file") buffer_resource_DestroyTextureNoAsync :: proc(self: ^texture_resource) {
	vk.DestroyImageView(vk_device, self.img_view, nil)
	vk_mem_buffer_UnBindBufferNode(auto_cast self.mem_buffer, self.__resource, self.idx)

	if self.data.allocator != nil && self.data.data != nil {
		delete(self.data.data, self.data.allocator.?)
	}
	self.data.data = nil
	self.data.allocator = nil
	self.__resource = 0
}

@(private = "file") buffer_resource_MapCopy :: #force_inline proc(
	self: union_resource,
	data: []byte,
	allocator: Maybe(runtime.Allocator) = nil,
) {
	pData : ^resource_data
	switch &s in self {
		case ^buffer_resource:
			pData = &s.data
		case ^texture_resource:
			pData = &s.data
	}
	pData.allocator = allocator
	pData.data = data
	AppendOp(OpMapCopy{
		pData = pData,
	})
}

@(private = "file", require_results) buffer_resource_MapCreatingModifing :: proc (
	self: union_resource,
	data: []byte,
	allocator: Maybe(runtime.Allocator),
) -> bool {
	inside :: #force_inline proc(v: ^$T, data: []byte, allocator: Maybe(runtime.Allocator)) -> bool {
		//If the data is already being created or modified, delete the existing data and apply the new data.
		if v.data.is_creating_modifing {
			if allocator != nil {
				delete(v.data.data, v.data.allocator.?)
			}
			v.data.data = data
			v.data.allocator = allocator
			return true
		}
		return false
	}
	switch &v in self {
		case ^buffer_resource:
			if inside(v, data, allocator) do return true
		case ^texture_resource:
			if inside(v, data, allocator) do return true
	}
	return false
}

//! unlike CopyUpdate, data cannot be a temporary variable.
vkbuffer_resource_map_update_slice :: #force_inline proc(
	self: union_resource,
	data: $T/[]$E,
	allocator: Maybe(runtime.Allocator) = nil,	
) {
	_data := mem.slice_to_bytes(data)
	if buffer_resource_MapCreatingModifing(self, _data, allocator) do return
	buffer_resource_MapCopy(self, _data, allocator)
}
//! unlike CopyUpdate, data cannot be a temporary variable.
vkbuffer_resource_map_update :: #force_inline proc(
	self: union_resource,
	data: ^$T,
	allocator: Maybe(runtime.Allocator) = nil,
) {
	_data := mem.ptr_to_bytes(data)
	if buffer_resource_MapCreatingModifing(self, _data, allocator) do return
	buffer_resource_MapCopy(self, _data, allocator)
}

vkbuffer_resource_copy_update_slice :: #force_inline proc(
	self: union_resource,
	data: $T/[]$E,
	allocator: Maybe(runtime.Allocator) = nil,
) {
	bytes := mem.slice_to_bytes(data)
	copyData:[]byte
	if allocator == nil {
		copyData = mem.make_non_zeroed([]byte, len(bytes), def_allocator())
	} else {
		copyData = mem.make_non_zeroed([]byte, len(bytes), allocator.?)
	}
	intrinsics.mem_copy_non_overlapping(raw_data(copyData), raw_data(bytes), len(bytes))

	if buffer_resource_MapCreatingModifing(self, copyData, allocator == nil ? def_allocator() : allocator.?) do return
	buffer_resource_MapCopy(self, copyData, allocator == nil ? def_allocator() : allocator.?)
}
vkbuffer_resource_copy_update :: proc(
	self: union_resource,
	data: ^$T,
	allocator: Maybe(runtime.Allocator) = nil,
) {
	copyData:[]byte
	bytes := mem.ptr_to_bytes(data)

	if allocator == nil {
		copyData = mem.make_non_zeroed([]byte, len(bytes), def_allocator())
	} else {
		copyData = mem.make_non_zeroed([]byte, len(bytes), allocator.?)
	}
	intrinsics.mem_copy_non_overlapping(raw_data(copyData), raw_data(bytes), len(bytes))

	if buffer_resource_MapCreatingModifing(self, copyData, allocator == nil ? def_allocator() : allocator.?) do return
	buffer_resource_MapCopy(self, copyData, allocator == nil ? def_allocator() : allocator.?)
}

vkbuffer_resource_deinit :: proc(self: ^$T) where T == buffer_resource || T == texture_resource {
	when T == buffer_resource {
		buffer: ^buffer_resource = auto_cast self
		buffer.option.len = 0
		if buffer.option.type == .UNIFORM {
			AppendOp(OpReleaseUniform{src = buffer})
		} else {
			AppendOp(OpDestroyBuffer{src = buffer})
		}
	} else when T == texture_resource {
		texture: ^texture_resource = auto_cast self
		texture.option.len = 0
		if self.mem_buffer == nil {
			vk.DestroyImageView(vk_device, texture.img_view, nil)
		} else {
			AppendOp(OpDestroyTexture{src = texture})
		}
	}
}
//no need @(private="file") buffer_resource_CreateTextureNoAsync


//not mul cellsize
@(private = "file") vk_mem_buffer_Map :: #force_inline proc "contextless" (
	self: ^vk_mem_buffer,
	start: vk.DeviceSize,
	size: vk.DeviceSize,
) -> [^]byte {
	outData: rawptr
	vk.MapMemory(vk_device, self.deviceMem, start, size, {}, &outData)
	return auto_cast outData
}
@(private = "file") vk_mem_buffer_UnMap :: #force_inline proc "contextless" (self: ^vk_mem_buffer) {
	self.mapSize = 0
	vk.UnmapMemory(vk_device, self.deviceMem)
}

@(private = "file") bind_uniform_buffer :: proc(
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

@(private = "file") executeReleaseUniform :: proc(
	buf: ^buffer_resource,
) {
	gUniforms[buf.g_uniform_indices[0]].uniforms[buf.g_uniform_indices[1]] = nil

	empty:=true
	for &v in gUniforms[buf.g_uniform_indices[0]].uniforms {
		if v != nil {
			empty = false
			break
		}
	}
	if empty {
		buffer_resource_DestroyBufferNoAsync(buf)
		delete(gUniforms[buf.g_uniform_indices[0]].uniforms)
		gUniforms[buf.g_uniform_indices[0]] = {}

		return
	}
}

@(private = "file") executeCreateBuffer :: proc(
	self: ^buffer_resource,
) {
	if !self.data.is_creating_modifing do return

	if self.option.type == .__STAGING {
		self.option.resource_usage = .CPU
		self.option.single = false
	}
	self.data.is_creating_modifing = false //clear creating, because resource is created

	memProp : vk.MemoryPropertyFlags;
	switch self.option.resource_usage {
		case .GPU:memProp = {.DEVICE_LOCAL}
		case .CPU:memProp = {.HOST_CACHED, .HOST_VISIBLE}
	}
	bufUsage:vk.BufferUsageFlags
	switch self.option.type {
		case .VERTEX: bufUsage = {.VERTEX_BUFFER}
		case .INDEX: bufUsage = {.INDEX_BUFFER}
		case .UNIFORM: //bufUsage = {.UNIFORM_BUFFER} no create each obj
			if self.option.resource_usage == .GPU do trace.panic_log("UNIFORM BUFFER can't resource_usage .GPU")
			bind_uniform_buffer(self, self.data.data, self.data.allocator)
			return
		case .STORAGE: bufUsage = {.STORAGE_BUFFER}
		case .__STAGING: bufUsage = {.TRANSFER_SRC}
	}

	//fmt.println(self.option.type, bufUsage)

	bufInfo := vk.BufferCreateInfo{
		sType = .BUFFER_CREATE_INFO,
		size = self.option.len,
		usage = bufUsage,
		sharingMode = .EXCLUSIVE
	}

	last:^buffer_resource
	if self.data.data != nil && self.option.resource_usage == .GPU {
		bufInfo.usage |= {.TRANSFER_DST}
		if self.option.len > auto_cast len(self.data.data) do trace.panic_log("create_buffer _data not enough size. ", self.option.len, ", ", len(self.data.data))
		
		last = new(buffer_resource, temp_arena_allocator())
		last^ = {}
		last.data = self.data
		buffer_resource_CreateBufferNoAsync(last, {
			len = self.option.len,
			resource_usage = .CPU,
			single = false,
			type = .__STAGING,
		})
	} else if self.option.type == .__STAGING {
		if self.data.data == nil do trace.panic_log("staging buffer data can't nil")
	}

	res := vk.CreateBuffer(vk_device, &bufInfo, nil, &self.__resource)
	if res != .SUCCESS do trace.panic_log("res := vk.CreateBuffer(vk_device, &bufInfo, nil, &self.__resource) : ", res)

	self.mem_buffer = auto_cast vk_mem_buffer_CreateFromResourceSingle(self.__resource) if self.option.single else
	auto_cast vk_mem_buffer_CreateFromResource(self.__resource, memProp, &self.idx, 0)

	if self.data.data != nil {
		if self.option.resource_usage != .GPU {
			append_op_save(OpMapCopy{
				pData = &self.data,
			})
		} else {
			 //above buffer_resource_CreateBufferNoAsync call, staging buffer is added and map_copy command is added.
			append_op_save(OpCopyBuffer{src = last, target = self})
			append_op_save(OpDestroyBuffer{src = last})
		}
	}
}
@(private = "file") executeCreateTexture :: proc(
	self: ^texture_resource,
) {
	if !self.data.is_creating_modifing do return
	
	memProp : vk.MemoryPropertyFlags;
	switch self.option.resource_usage {
		case .GPU:memProp = {.DEVICE_LOCAL}
		case .CPU:memProp = {.HOST_CACHED, .HOST_VISIBLE}
	}
	texUsage:vk.ImageUsageFlags = {}
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

	tiling :vk.ImageTiling = .OPTIMAL

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
	bit : u32 = auto_cast texture_fmt_bit_size(self.option.format)

	imgInfo := vk.ImageCreateInfo{
		sType = .IMAGE_CREATE_INFO,
		arrayLayers = self.option.len,
		usage = texUsage,
		sharingMode = .EXCLUSIVE,
		extent = {width = self.option.width, height = self.option.height, depth = 1},
		samples = samples_to_vk_sample_count_flags(self.option.samples),
		tiling = tiling,
		mipLevels = 1,
		format = texture_fmt_to_vk_fmt(self.option.format),
		imageType = texture_type_to_vk_image_type(self.option.type),
		initialLayout = .UNDEFINED,
	}

	last:^buffer_resource
	if self.data.data != nil && self.option.resource_usage == .GPU {
		imgInfo.usage |= {.TRANSFER_DST}
		
		last = new(buffer_resource, temp_arena_allocator())
		last^ = {}
		last.data = self.data
		buffer_resource_CreateBufferNoAsync(last, {
			len = auto_cast(imgInfo.extent.width * imgInfo.extent.height * imgInfo.extent.depth * imgInfo.arrayLayers * bit),
			resource_usage = .CPU,
			single = false,
			type = .__STAGING,
		})
	}

	res := vk.CreateImage(vk_device, &imgInfo, nil, &self.__resource)
	if res != .SUCCESS do trace.panic_log("res := vk.CreateImage(vk_device, &bufInfo, nil, &self.__resource) : ", res)

	self.mem_buffer = auto_cast vk_mem_buffer_CreateFromResourceSingle(self.__resource) if self.option.single else
	auto_cast vk_mem_buffer_CreateFromResource(self.__resource, memProp, &self.idx, 0)

	imgViewInfo := vk.ImageViewCreateInfo{
		sType = .IMAGE_VIEW_CREATE_INFO,
		format = imgInfo.format,
		components = {r = .IDENTITY, g = .IDENTITY, b = .IDENTITY, a = .IDENTITY},
		image = self.__resource,
		subresourceRange = {
			aspectMask = isDepth ? {.DEPTH, .STENCIL} : {.COLOR},
			baseMipLevel = 0,
			levelCount = 1,
			baseArrayLayer = 0,
			layerCount = imgInfo.arrayLayers,
		},
	}
	switch self.option.type {
		case .TEX2D: imgViewInfo.viewType = imgInfo.arrayLayers > 1 ? .D2_ARRAY : .D2
	}
	
	res = vk.CreateImageView(vk_device, &imgViewInfo, nil, &self.img_view)
	if res != .SUCCESS do trace.panic_log("res = vk.CreateImageView(vk_device, &imgViewInfo, nil, &self.img_view) : ", res)

	self.data.is_creating_modifing = false //clear creating, because resource is created

	if self.data.data != nil {
		if self.option.resource_usage != .GPU {
			append_op_save(OpMapCopy{
				pData = &self.data,
			})
		} else {
			 //above buffer_resource_CreateBufferNoAsync call, staging buffer is added and map_copy command is added.
			append_op_save(OpCopyBufferToTexture{src = last, target = self})
			append_op_save(OpDestroyBuffer{src = last})
		}
	}
}
@(private = "file") executeRegisterDescriptorPool :: #force_inline proc(size: []descriptor_pool_size) {
	//?? no need? execute_register_descriptor_pool
}
@(private = "file") __create_descriptor_pool :: proc(size:[]descriptor_pool_size, out:^descriptor_pool_mem) {
	poolSize :[]vk.DescriptorPoolSize = mem.make_non_zeroed([]vk.DescriptorPoolSize, len(size))
	defer delete(poolSize)

	for _, i in size {
		poolSize[i].descriptorCount = size[i].cnt * vkPoolBlock
		poolSize[i].type = descriptor_type_to_vk_descriptor_type(size[i].type)
	}
	poolInfo := vk.DescriptorPoolCreateInfo{
		sType = .DESCRIPTOR_POOL_CREATE_INFO,
		poolSizeCount = auto_cast len(poolSize),
		pPoolSizes = raw_data(poolSize),
		maxSets = vkPoolBlock,
	}
	res := vk.CreateDescriptorPool(vk_device, &poolInfo, nil, &out.pool)
	if res != .SUCCESS do trace.panic_log("res := vk.CreateDescriptorPool(vk_device, &poolInfo, nil, &out.pool) : ", res)
}

vk_update_descriptor_sets :: proc(sets: []descriptor_set) {
	AppendOp(Op__Updatedescriptor_sets{sets = sets})
}

@(private = "file") execute_update_descriptor_sets :: proc(sets: []descriptor_set) {
	for &s in sets {
		if s.__set == 0 {
			if raw_data(s.size) in gDesciptorPools {
			} else {
				gDesciptorPools[raw_data(s.size)] = mem.make_non_zeroed([dynamic]descriptor_pool_mem, def_allocator())
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
			allocInfo := vk.DescriptorSetAllocateInfo{
				sType = .DESCRIPTOR_SET_ALLOCATE_INFO,
				descriptorPool = last.pool,
				descriptorSetCount = 1,
				pSetLayouts = &s.layout,
			}
			res := vk.AllocateDescriptorSets(vk_device, &allocInfo, &s.__set)
			if res != .SUCCESS do trace.panic_log("res := vk.AllocateDescriptorSets(vk_device, &allocInfo, &s.__set) : ", res)
		}

		cnt:u32 = 0
		bufCnt:u32 = 0
		texCnt:u32 = 0

		//sets[i].__resources array must match v.size configuration.
		for s in s.size {
			cnt += s.cnt
		}
		
		for r in s.__resources[0:cnt] {
			switch v in r {
				case ^buffer_resource:
					bufCnt += 1
				case ^texture_resource:
					texCnt += 1
				case:
					trace.panic_log("invaild type s.__resources[0:cnt] r")
			}
		}

		bufs := mem.make_non_zeroed([]vk.DescriptorBufferInfo, bufCnt, __temp_arena_allocator)
		texs := mem.make_non_zeroed([]vk.DescriptorImageInfo, texCnt, __temp_arena_allocator)
		bufCnt = 0
		texCnt = 0

		for r in s.__resources[0:cnt] {
			switch v in r {
				case ^buffer_resource:
					bufs[bufCnt] = vk.DescriptorBufferInfo{
						buffer = ((^buffer_resource)(v)).__resource,
						offset = ((^buffer_resource)(v)).g_uniform_indices[2],
						range = ((^buffer_resource)(v)).option.len
					}
					bufCnt += 1
				case ^texture_resource:
					texs[texCnt] = vk.DescriptorImageInfo{
						imageLayout = .SHADER_READ_ONLY_OPTIMAL,
						imageView = ((^texture_resource)(v)).img_view,
						sampler = ((^texture_resource)(v)).sampler,
					}
					texCnt += 1
			}
		}

		bufCnt = 0
		texCnt = 0
		for n, i in s.size {	
			switch n.type {
				case .SAMPLER, .STORAGE_IMAGE:
					non_zero_append(&gVkUpdateDesciptorSetList, vk.WriteDescriptorSet{
						dstSet = s.__set,
						dstBinding = s.bindings[i],
						dstArrayElement = 0,
						descriptorCount = n.cnt,
						descriptorType = descriptor_type_to_vk_descriptor_type(n.type),
						pBufferInfo = nil,
						pImageInfo = &texs[texCnt],
						pTexelBufferView = nil,
						sType = .WRITE_DESCRIPTOR_SET,
						pNext = nil,
					})
					texCnt += n.cnt
				case .UNIFORM, .STORAGE, .UNIFORM_DYNAMIC:
					non_zero_append(&gVkUpdateDesciptorSetList, vk.WriteDescriptorSet{
						dstSet = s.__set,
						dstBinding = s.bindings[i],
						dstArrayElement = 0,
						descriptorCount = n.cnt,
						descriptorType = descriptor_type_to_vk_descriptor_type(n.type),
						pBufferInfo = &bufs[bufCnt],
						pImageInfo = nil,
						pTexelBufferView = nil,
						sType = .WRITE_DESCRIPTOR_SET,
						pNext = nil,
					})
					bufCnt += n.cnt
			}
		}
	}
}
@(private = "file") execute_copy_buffer :: proc(src: ^buffer_resource, target: ^buffer_resource) {
	copyRegion := vk.BufferCopy{
		size = target.option.len,
		srcOffset = 0,
		dstOffset = 0
	}
	vk.CmdCopyBuffer(gCmd, src.__resource, target.__resource, 1, &copyRegion)
}
@(private = "file") execute_copy_buffer_to_texture :: proc(src: ^buffer_resource, target: ^texture_resource) {
	vk_transition_image_layout(gCmd, target.__resource, 1, 0, target.option.len, .UNDEFINED, .TRANSFER_DST_OPTIMAL)
	region := vk.BufferImageCopy{
		bufferOffset = 0,
		bufferRowLength = 0,
		bufferImageHeight = 0,
		imageOffset = {x = 0,y = 0,z = 0},
		imageExtent = {width = target.option.width, height = target.option.height, depth = 1},
		imageSubresource = {
			aspectMask = {.COLOR},
			baseArrayLayer = 0,
			mipLevel = 0,
			layerCount = target.option.len
		}
	}
	vk.CmdCopyBufferToImage(gCmd, src.__resource, target.__resource, .TRANSFER_DST_OPTIMAL, 1, &region)
	vk_transition_image_layout(gCmd, target.__resource, 1, 0, target.option.len, .TRANSFER_DST_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL)
}
@(private = "file") op_alloc_queue_free :: proc() {
	sync.atomic_mutex_lock(&gQueueMtx)
	defer sync.atomic_mutex_unlock(&gQueueMtx)

	for node in opAllocQueue {
		#partial switch n in node {
		case OpMapCopy:
			if n.pData.allocator != nil && n.pData.data != nil {
				delete(n.pData.data, n.pData.allocator.?)
			}
			n.pData.data = nil
			n.pData.allocator = nil
		}
	}
	clear(&opAllocQueue)
}
@(private = "file") to_base_resource :: #force_inline proc "contextless" (res:union_resource) -> ^base_resource {
	switch v in res {
		case ^buffer_resource:
			return v
		case ^texture_resource:
			return v
	}
	return nil
}
@(private = "file") save_to_map_queue :: proc(inoutMemBuf: ^^vk_mem_buffer) {
	for &node in opSaveQueue {
		#partial switch &n in node {
		case OpMapCopy:
			res :^base_resource = cast(^base_resource)(n.pData)
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
@(private = "file") vk_mem_buffer_MapCopyexecute :: proc(self: ^vk_mem_buffer, nodes: []OpNode) {
	startIdx: vk.DeviceSize = max(vk.DeviceSize)
	endIdx: vk.DeviceSize = max(vk.DeviceSize)
	offIdx: u32 = 0

	ranges: [dynamic]vk.MappedMemoryRange
	if self.cache {
		ranges = mem.make_non_zeroed_dynamic_array([dynamic]vk.MappedMemoryRange, context.temp_allocator)
		overlap := mem.make_non_zeroed_dynamic_array([dynamic]^vk_mem_buffer_node, context.temp_allocator)
		defer delete(overlap)

		out: for i in 0 ..< len(nodes) {
			res :^base_resource = cast(^base_resource)(nodes[i].(OpMapCopy).pData)
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
						if r.offset != r2.offset && r2.offset < r.offset + r.size && r2.offset + r2.size > r.offset { 	//both sides overlap
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
			res :^base_resource = cast(^base_resource)(node.(OpMapCopy).pData)
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
		res :^base_resource = (cast(^base_resource)(mapCopy.pData))
		idx: ^vk_mem_buffer_node = auto_cast res.idx
		start_ := idx.idx * self.cellSize - self.mapStart + res.g_uniform_indices[2]
		mem.copy_non_overlapping(&self.mapData[start_], raw_data(res.data.data), len(res.data.data))

		res.data.is_creating_modifing = false
	}

	if self.cache {
		res := vk.FlushMappedMemoryRanges(vk_device, auto_cast len(ranges), raw_data(ranges))
		if res != .SUCCESS do trace.panic_log("res := vk.FlushMappedMemoryRanges(vk_device, auto_cast len(ranges), raw_data(ranges)) : ", res)

		delete(ranges)
	}
}

@(private = "file") executeDestroyBuffer :: proc(buf:^buffer_resource) {
	buffer_resource_DestroyBufferNoAsync(buf)
}
@(private = "file") executeDestroyTexture :: proc(tex:^texture_resource) {
	buffer_resource_DestroyTextureNoAsync(tex)
}

//? delete private when need
@(private = "file") vk_mem_buffer_IsEmpty :: proc(self: ^vk_mem_buffer) -> bool {
	return !self.single && ((self.list.head != nil &&
		self.list.head.next == nil &&
		((^vk_mem_buffer_node)(self.list.head)).free) || 
		(self.list.head == nil))
}

vk_op_execute_destroy :: proc() {
	sync.atomic_mutex_lock(&gDestroyQueueMtx)
	
	for node in opDestroyQueue {
		#partial switch n in node {
			case OpDestroyBuffer : 
				executeDestroyBuffer(n.src)
			case OpDestroyTexture : 
				executeDestroyTexture(n.src)
		}
	}
	
	clear(&opDestroyQueue)

	sync.atomic_mutex_unlock(&gDestroyQueueMtx)
	virtual.arena_free_all(&__tempArena)

	sync.sema_post(&gWaitOpSem)
}

vk_op_execute :: proc(wait_and_destroy: bool) {
	sync.atomic_mutex_lock(&gQueueMtx)
	if len(opQueue) == 0 {
		sync.atomic_mutex_unlock(&gQueueMtx)
		if wait_and_destroy {
			vk_wait_graphics_idle()
			vk_op_execute_destroy()
		}
		return
	}
	resize(&opSaveQueue, len(opQueue))
	mem.copy_non_overlapping(raw_data(opSaveQueue), raw_data(opQueue), len(opQueue) * size_of(OpNode))
	clear(&opQueue)
	sync.atomic_mutex_unlock(&gQueueMtx)

	clear(&opMapQueue)
	//!여기 없애면 작동하는데 왜 적었는지 모르겠음 조사 필요. 확인 필요!
	// for &node in opSaveQueue {
	// 	#partial switch n in node {
	// 		case OpDestroyBuffer:
	// 			executeDestroyBuffer(n.src)
	// 		case OpDestroyTexture:
	// 			executeDestroyTexture(n.src)
	// 		case:
	// 			continue
	// 	}
	// 	node = nil
	// }

	for &node in opSaveQueue {
		#partial switch n in node {
		case OpCreateBuffer:
			executeCreateBuffer(n.src)
		case OpCreateTexture:
			executeCreateTexture(n.src)
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
			all_size : vk.DeviceSize = 0
			for &t in gTempUniforms {
				all_size += t.size
			}
			resize_dynamic_array(&gUniforms, 1)
			gUniforms[0] = {
				max_size = max(vkUniformSizeBlock, all_size),
				size = all_size,
				uniforms = mem.make_non_zeroed_dynamic_array([dynamic]^buffer_resource, def_allocator()),	
			}

			bufInfo : vk.BufferCreateInfo = {
				sType = vk.StructureType.BUFFER_CREATE_INFO,
				size = gUniforms[0].max_size,
				usage = {.UNIFORM_BUFFER},
			}
			res := vk.CreateBuffer(vk_device, &bufInfo, nil, &gUniforms[0].buf)
			if res != .SUCCESS do trace.panic_log("res := vk.CreateBuffer(vk_device, &bufInfo, nil, &self.__resource) : ", res)

			gUniforms[0].mem_buffer = vk_mem_buffer_CreateFromResource(gUniforms[0].buf, {.HOST_CACHED, .HOST_VISIBLE}, &gUniforms[0].idx, 0)

			off :vk.DeviceSize = 0
			for &t, i in gTempUniforms {
				non_zero_append(&gUniforms[0].uniforms, t.uniform)
				
				t.uniform.g_uniform_indices[0] = 0
				t.uniform.g_uniform_indices[1] = auto_cast i
				t.uniform.g_uniform_indices[2] = off
				t.uniform.g_uniform_indices[3] = t.size
				t.uniform.__resource = gUniforms[0].buf
				t.uniform.mem_buffer = auto_cast gUniforms[0].mem_buffer
				t.uniform.idx = gUniforms[0].idx

				append_op_save(OpMapCopy{
					pData = &t.uniform.data,
				})
				off += t.size
			}
		} else {
			for &t, i in gTempUniforms {
				inserted := false
				out: for &g, i2 in gUniforms {
					if g.buf == 0 do continue
					outN: for i3:=0;i3 < len(g.uniforms);i3+=1 {
						if g.uniforms[i3] == nil {
							if i3 == 0 {
								for i4 in 1..<len(g.uniforms) {
									if g.uniforms[i4] != nil {
										if g.uniforms[i4].g_uniform_indices[2] >= t.size {
											g.uniforms[i3] = t.uniform
											t.uniform.g_uniform_indices[0] = auto_cast i2
											t.uniform.g_uniform_indices[1] = auto_cast i3//0
											t.uniform.g_uniform_indices[2] = 0
											t.uniform.g_uniform_indices[3] = t.size
											t.uniform.__resource = g.buf
											t.uniform.mem_buffer = auto_cast g.mem_buffer
											t.uniform.idx = g.idx

											append_op_save(OpMapCopy{
												pData = &t.uniform.data,
											})
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
									t.uniform.g_uniform_indices[0] = auto_cast i2
									t.uniform.g_uniform_indices[1] = auto_cast i3
									t.uniform.g_uniform_indices[2] = g.size
									t.uniform.g_uniform_indices[3] = t.size
									t.uniform.__resource = g.buf
									t.uniform.mem_buffer = auto_cast g.mem_buffer
									t.uniform.idx = g.idx

									append_op_save(OpMapCopy{
										pData = &t.uniform.data,
									})
									g.size += t.size
									inserted = true
									break out
								}
							} else {
								for i4 in i3+1..<len(g.uniforms) {
									if g.uniforms[i4] != nil {
										if g.uniforms[i4].g_uniform_indices[2] - (g.uniforms[i3-1].g_uniform_indices[2] + g.uniforms[i3-1].g_uniform_indices[3]) >= t.size {
											g.uniforms[i3] = t.uniform
											t.uniform.g_uniform_indices[0] = auto_cast i2
											t.uniform.g_uniform_indices[1] = auto_cast i3
											t.uniform.g_uniform_indices[2] = g.uniforms[i3-1].g_uniform_indices[2] + g.uniforms[i3-1].g_uniform_indices[3]
											t.uniform.g_uniform_indices[3] = t.size
											t.uniform.__resource = g.buf
											t.uniform.mem_buffer = auto_cast g.mem_buffer
											t.uniform.idx = g.idx

											append_op_save(OpMapCopy{
												pData = &t.uniform.data,
											})
											inserted = true
											break out
										}
										i3 = i4
										continue outN
									}
								}
								if g.max_size - g.size >= t.size {
									g.uniforms[i3] = t.uniform
									t.uniform.g_uniform_indices[0] = auto_cast i2
									t.uniform.g_uniform_indices[1] = auto_cast i3
									t.uniform.g_uniform_indices[2] = g.uniforms[i3-1].g_uniform_indices[2] + g.uniforms[i3-1].g_uniform_indices[3]
									t.uniform.g_uniform_indices[3] = t.size
									t.uniform.__resource = g.buf
									t.uniform.mem_buffer = auto_cast g.mem_buffer
									t.uniform.idx = g.idx

									append_op_save(OpMapCopy{
										pData = &t.uniform.data,
									})
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
						t.uniform.g_uniform_indices[0] = auto_cast i2
						t.uniform.g_uniform_indices[1] = auto_cast (len(g.uniforms) - 1)
						t.uniform.g_uniform_indices[2] = g.uniforms[len(g.uniforms) - 2].g_uniform_indices[2] + g.uniforms[len(g.uniforms) - 2].g_uniform_indices[3]
						t.uniform.g_uniform_indices[3] = t.size
						t.uniform.__resource = g.buf
						t.uniform.mem_buffer = auto_cast g.mem_buffer
						t.uniform.idx = g.idx

						append_op_save(OpMapCopy{
							pData = &t.uniform.data,
						})
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
				all_size : vk.DeviceSize = 0
				for &t in gNonInsertedUniforms {
					all_size += t.size
				}
				resize_dynamic_array(&gUniforms, len(gUniforms) + 1)
				gUniforms[len(gUniforms) - 1] = {
					max_size = max(vkUniformSizeBlock, all_size),
					size = all_size,
					uniforms = mem.make_non_zeroed_dynamic_array([dynamic]^buffer_resource, def_allocator()),	
				}

				bufInfo : vk.BufferCreateInfo = {
					sType = vk.StructureType.BUFFER_CREATE_INFO,
					size = gUniforms[len(gUniforms) - 1].max_size,
					usage = {.UNIFORM_BUFFER},
				}
				res := vk.CreateBuffer(vk_device, &bufInfo, nil, &gUniforms[len(gUniforms) - 1].buf)
				if res != .SUCCESS do trace.panic_log("res := vk.CreateBuffer(vk_device, &bufInfo, nil, &self.__resource) : ", res)

				gUniforms[len(gUniforms) - 1].mem_buffer = vk_mem_buffer_CreateFromResource(gUniforms[len(gUniforms) - 1].buf, {.HOST_CACHED, .HOST_VISIBLE}, &gUniforms[len(gUniforms) - 1].idx, 0)

				off :vk.DeviceSize = 0
				for &t, i in gNonInsertedUniforms {
					non_zero_append(&gUniforms[len(gUniforms) - 1].uniforms, t.uniform)
					
					t.uniform.g_uniform_indices[0] = auto_cast (len(gUniforms) - 1)
					t.uniform.g_uniform_indices[1] = auto_cast i
					t.uniform.g_uniform_indices[2] = off
					t.uniform.g_uniform_indices[3] = t.size
					t.uniform.__resource = gUniforms[len(gUniforms) - 1].buf
					t.uniform.idx = gUniforms[len(gUniforms) - 1].idx
					t.uniform.mem_buffer = auto_cast gUniforms[len(gUniforms) - 1].mem_buffer

					append_op_save(OpMapCopy{
						pData = &t.uniform.data,
					})
					off += t.size
				}
				clear(&gNonInsertedUniforms)
			}
		}
		clear(&gTempUniforms)
	}

	sync.atomic_mutex_lock(&gDestroyQueueMtx)
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
	sync.atomic_mutex_unlock(&gDestroyQueueMtx)

	memBufT: ^vk_mem_buffer = nil
	save_to_map_queue(&memBufT)
	for len(opMapQueue) > 0 {
		vk_mem_buffer_MapCopyexecute(memBufT, opMapQueue[:])
		clear(&opMapQueue)
		memBufT = nil
		save_to_map_queue(&memBufT)
	}

	op_alloc_queue_free()

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
		//?call callback this line
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
			#partial switch n in node {
			case OpCopyBuffer:
				n.target.data.data = nil
				n.target.data.allocator = nil
			case OpCopyBufferToTexture:
				n.target.data.data = nil
				n.target.data.allocator = nil
			}
		}
		vk_op_execute_destroy()
	} else if wait_and_destroy {
		vk_wait_graphics_idle()
		vk_op_execute_destroy()
	} else {
		sync.sema_post(&gWaitOpSem)
	}

	clear(&opSaveQueue)
}

/*
Converts a texture format to a Vulkan format

Inputs:
- t: The texture format to convert

Returns:
- The corresponding Vulkan format
*/
@(require_results) texture_fmt_to_vk_fmt :: proc "contextless" (t:texture_fmt) -> vk.Format {
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

