#+private
package engine

import "base:runtime"
import "base:intrinsics"
import "core:container/intrusive/list"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:mem/virtual"
import "core:debug/trace"
import "core:slice"
import "core:sync"
import "core:fmt"
import "core:thread"
import "core:reflect"
import vk "vendor:vulkan"

vkMemBlockLen: VkSize = mem.Megabyte * 256
vkMemSpcialBlockLen: VkSize = mem.Megabyte * 256
vkNonCoherentAtomSize: VkSize = 0
vkPoolBlock :: 256
vkUniformSizeBlock :: mem.Megabyte
vkSupportCacheLocal := false
vkSupportNonCacheLocal := false
@(private = "file") __arena: virtual.Arena
@(private = "file") __tempArena: virtual.Arena
@(private = "file") __bufTempArena: virtual.Arena
@(private = "file") __allocArena: virtual.Arena
@(private = "file") __allocArenaMtx: mem.Mutex_Allocator
@(private = "file") gQueueMtx: sync.Atomic_Mutex
@(private = "file") gDestroyQueueMtx: sync.Atomic_Mutex
vkArenaAllocator: mem.Allocator
vkTempArenaAllocator: mem.Allocator
vkBufTempArenaAllocator: mem.Allocator

OpMapCopy :: struct {
	data:      []byte,
	resource:  VkUnionResource,
	allocator: Maybe(runtime.Allocator),
}
OpCopyBuffer :: struct {
	src:    ^VkBufferResource,
	target: ^VkBufferResource,
}
OpCopyBufferToTexture :: struct {
	src:    ^VkBufferResource,
	target: ^VkTextureResource,
}
OpCreateBuffer :: struct {
	src:       ^VkBufferResource,
	data:      []byte,
	allocator: Maybe(runtime.Allocator),
}
OpCreateTexture :: struct {
	src:       ^VkTextureResource,
	data:      []byte,
	allocator: Maybe(runtime.Allocator),
}
OpDestroyBuffer :: struct {
	src: ^VkBufferResource,
}
OpReleaseUniform :: struct {
	src: ^VkBufferResource,
}
OpDestroyTexture :: struct {
	src: ^VkTextureResource,
}
Op__UpdateDescriptorSets :: struct {
	sets: []VkDescriptorSet,
}
//doesn't need to call outside
Op__RegisterDescriptorPool :: struct {
	size: []VkDescriptorPoolSize,
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
	Op__UpdateDescriptorSets,
	Op__RegisterDescriptorPool,
}

VkMemBufferNode :: struct {
    node : list.Node,
    size:VkSize,
    idx:VkSize,
    free:bool
}
VkMemBuffer :: struct {
    cellSize:VkSize,
    mapStart:VkSize,
    mapSize:VkSize,
    mapData:[^]byte,
    len:VkSize,
    deviceMem:vk.DeviceMemory,
    single:bool,
    cache:bool,
    cur:^list.Node,
    list:list.List,
    allocateInfo:vk.MemoryAllocateInfo,
}


vkTempUniformStruct :: struct {
	uniform:^VkBufferResource,
	data:[]byte,
	size:vk.DeviceSize,
	allocator: Maybe(runtime.Allocator),
}

vkUniformAlloc :: struct {
	max_size: vk.DeviceSize,
	size:vk.DeviceSize,
	uniforms:[dynamic]^VkBufferResource,
	buf:vk.Buffer,
	idx:VkResourceRange,
	memBuffer:^VkMemBuffer,
}

@(private="file") cmdPool:vk.CommandPool
@(private="file") gCmd:vk.CommandBuffer
@(private="file") opQueue:[dynamic]OpNode
@(private="file") opSaveQueue:[dynamic]OpNode
@(private="file") opMapQueue:[dynamic]OpNode
@(private="file") opAllocQueue:[dynamic]OpNode
@(private="file") opDestroyQueue:[dynamic]OpNode
@(private="file") gVkUpdateDesciptorSetList:[dynamic]vk.WriteDescriptorSet
@(private="file") gDesciptorPools:map[[^]VkDescriptorPoolSize][dynamic]VkDescriptorPoolMem
@(private="file") gUniforms:[dynamic]vkUniformAlloc
@(private="file") gTempUniforms:[dynamic]vkTempUniformStruct
@(private="file") gNonInsertedUniforms:[dynamic]vkTempUniformStruct

@(private="file") gWaitOpSem:sync.Sema

FREE_OBJ :: struct {
	typeSize:u64,
	len:u64,
	deinit:proc(obj:^IObject),
	obj:rawptr,
}
gFreeObjects:[dynamic]FREE_OBJ
gFreeObjectMtx:sync.Mutex

gVkMinUniformBufferOffsetAlignment : vk.DeviceSize = 0

vkWaitAllOp :: #force_inline proc "contextless" () {
	sync.sema_wait(&gWaitOpSem)
}

vkInitBlockLen :: proc() {
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
	for h, i in vkPhysicalMemProp.memoryHeaps[:vkPhysicalMemProp.memoryHeapCount] {
		if .DEVICE_LOCAL in h.flags {
			_ChangeSize(h.size)
			change = true
			when is_log {
				printfln(
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
		_ChangeSize(vkPhysicalMemProp.memoryHeaps[0].size)
		when is_log {
			printfln(
				"XFIT SYSLOG : Vulkan No Graphic Card System Memory Block %d MB\nSystem Memory : %d MB",
				vkMemBlockLen / mem.Megabyte,
				vkPhysicalMemProp.memoryHeaps[0].size / mem.Megabyte,
			)
		}
		mainHeapIdx = 0
	}


	vkNonCoherentAtomSize = auto_cast vkPhysicalProp.limits.nonCoherentAtomSize

	reduced := false
	for t, i in vkPhysicalMemProp.memoryTypes[:vkPhysicalMemProp.memoryTypeCount] {
		if t.propertyFlags >= {.DEVICE_LOCAL, .HOST_CACHED, .HOST_VISIBLE} {
			vkSupportCacheLocal = true
			when is_log do printfln("XFIT SYSLOG : Vulkan Device Supported Cache Local Memory")
		} else if t.propertyFlags >= {.DEVICE_LOCAL, .HOST_COHERENT, .HOST_VISIBLE} {
			vkSupportNonCacheLocal = true
			when is_log do printfln("XFIT SYSLOG : Vulkan Device Supported Non Cache Local Memory")
		} else {
			continue
		}
		if mainHeapIdx != t.heapIndex && !reduced {
			vkMemSpcialBlockLen /= min(
				16,
				max(
					1,
					vkPhysicalMemProp.memoryHeaps[mainHeapIdx].size /
					vkPhysicalMemProp.memoryHeaps[t.heapIndex].size,
				),
			)
			reduced = true
		}
	}

	gVkMinUniformBufferOffsetAlignment = vkPhysicalProp.limits.minUniformBufferOffsetAlignment
}


vkAllocatorInit :: proc() {
	vkThreadId = sync.current_thread_id()
	gVkMemBufs = mem.make_non_zeroed([dynamic]^VkMemBuffer, engineDefAllocator)

	gVkMemIdxCnts = mem.make_non_zeroed([]int, vkPhysicalMemProp.memoryTypeCount, engineDefAllocator)
	mem.zero_slice(gVkMemIdxCnts)

	_ = virtual.arena_init_growing(&__arena)
	_ = virtual.arena_init_growing(&__tempArena)
	_ = virtual.arena_init_growing(&__bufTempArena)

	vkArenaAllocator = virtual.arena_allocator(&__arena)
	vkTempArenaAllocator = virtual.arena_allocator(&__tempArena)
	vkBufTempArenaAllocator = virtual.arena_allocator(&__bufTempArena)

	cmdPoolInfo := vk.CommandPoolCreateInfo {
		sType            = vk.StructureType.COMMAND_POOL_CREATE_INFO,
		queueFamilyIndex = vkGraphicsFamilyIndex,
	}
	vk.CreateCommandPool(vkDevice, &cmdPoolInfo, nil, &cmdPool)

	cmdAllocInfo := vk.CommandBufferAllocateInfo {
		sType = vk.StructureType.COMMAND_BUFFER_ALLOCATE_INFO,
		commandBufferCount = 1,
		level              = .PRIMARY,
		commandPool        = cmdPool,
	}
	vk.AllocateCommandBuffers(vkDevice, &cmdAllocInfo, &gCmd)

	opQueue = mem.make_non_zeroed([dynamic]OpNode, vkArenaAllocator)
	opSaveQueue = mem.make_non_zeroed([dynamic]OpNode, vkArenaAllocator)
	opMapQueue = mem.make_non_zeroed([dynamic]OpNode, vkArenaAllocator)
	opAllocQueue = mem.make_non_zeroed([dynamic]OpNode, vkArenaAllocator)
	opDestroyQueue = mem.make_non_zeroed([dynamic]OpNode, vkArenaAllocator)
	gVkUpdateDesciptorSetList = mem.make_non_zeroed([dynamic]vk.WriteDescriptorSet, vkArenaAllocator)

	gFreeObjects = mem.make_non_zeroed([dynamic]FREE_OBJ, vkArenaAllocator)
	gUniforms = mem.make_non_zeroed([dynamic]vkUniformAlloc, vkArenaAllocator)
	gTempUniforms = mem.make_non_zeroed([dynamic]vkTempUniformStruct, vkArenaAllocator)
	gNonInsertedUniforms = mem.make_non_zeroed([dynamic]vkTempUniformStruct, vkArenaAllocator)
}

vkAllocatorDestroy :: proc() {
	OpAllocQueueFree()

	for b in gVkMemBufs {
		VkMemBuffer_Deinit2(b)
	}
	delete(gVkMemBufs)

	vk.DestroyCommandPool(vkDevice, cmdPool, nil)

	for _, &value in gDesciptorPools {
		for i in value {
			vk.DestroyDescriptorPool(vkDevice, i.pool, nil)
		}
	}

	virtual.arena_destroy(&__arena)
	virtual.arena_destroy(&__tempArena)
	virtual.arena_destroy(&__bufTempArena)
	virtual.arena_destroy(&__allocArena)

	delete(gVkMemIdxCnts, engineDefAllocator)
}

@(private = "file") gVkMemBufs: [dynamic]^VkMemBuffer
@(private = "file") VkMaxMemIdxCnt : int : 4
@(private = "file") gVkMemIdxCnts: []int

vkThreadId:int

vkFindMemType :: proc "contextless" (
	typeFilter: u32,
	memProp: vk.MemoryPropertyFlags,
) -> (
	memType: u32,
	success: bool = true,
) {
	for i: u32 = 0; i < vkPhysicalMemProp.memoryTypeCount; i += 1 {
		if ((typeFilter & (1 << i)) != 0) &&
		   (memProp <= vkPhysicalMemProp.memoryTypes[i].propertyFlags) {
			memType = i
			return
		}
	}
	success = false
	return
}
// ! don't call vulkan_res.init separately
@(private = "file") VkMemBuffer_Init :: proc(
	cellSize: VkSize,
	len: VkSize,
	typeFilter: u32,
	memProp: vk.MemoryPropertyFlags,
) -> Maybe(VkMemBuffer) {
	memBuf := VkMemBuffer {
		cellSize = cellSize,
		len = len,
		allocateInfo = {sType = .MEMORY_ALLOCATE_INFO, allocationSize = len * cellSize},
		cache = vk.MemoryPropertyFlags{.HOST_VISIBLE, .HOST_CACHED} <= memProp,
	}
	success: bool
	memBuf.allocateInfo.memoryTypeIndex, success = vkFindMemType(typeFilter, memProp)
	if !success do return nil


	if memBuf.cache {
		memBuf.allocateInfo.allocationSize = math.ceil_up(len * cellSize, vkNonCoherentAtomSize)
		memBuf.len = memBuf.allocateInfo.allocationSize / cellSize
	}

	res := vk.AllocateMemory(vkDevice, &memBuf.allocateInfo, nil, &memBuf.deviceMem)
	if res != .SUCCESS do return nil


	list.push_back(&memBuf.list, auto_cast new(VkMemBufferNode, vkArenaAllocator))
	((^VkMemBufferNode)(memBuf.list.head)).free = true
	((^VkMemBufferNode)(memBuf.list.head)).size = memBuf.len
	((^VkMemBufferNode)(memBuf.list.head)).idx = 0
	memBuf.cur = memBuf.list.head

	return memBuf
}
@(private = "file") VkMemBuffer_InitSingle :: proc(cellSize: VkSize, typeFilter: u32) -> Maybe(VkMemBuffer) {
	memBuf := VkMemBuffer {
		cellSize = cellSize,
		len = 1,
		allocateInfo = {sType = .MEMORY_ALLOCATE_INFO, allocationSize = 1 * cellSize},
		single = true,
	}
	success: bool
	memBuf.allocateInfo.memoryTypeIndex, success = vkFindMemType(
		typeFilter,
		vk.MemoryPropertyFlags{.DEVICE_LOCAL},
	)
	if !success do trace.panic_log("memBuf.allocateInfo.memoryTypeIndex, success = vkFindMemType(typeFilter, vk.MemoryPropertyFlags{.DEVICE_LOCAL})")

	res := vk.AllocateMemory(vkDevice, &memBuf.allocateInfo, nil, &memBuf.deviceMem)
	if res != .SUCCESS do trace.panic_log("res := vk.AllocateMemory(vkDevice, &memBuf.allocateInfo, nil, &memBuf.deviceMem)")

	return memBuf
}
@(private = "file") VkMemBuffer_Deinit2 :: proc(self: ^VkMemBuffer) {
	vk.FreeMemory(vkDevice, self.deviceMem, nil)
	if !self.single {
		for n: ^list.Node = self.list.head; n.next != nil; n = n.next {
			free(n, vkArenaAllocator)
		}
	}
}
@(private = "file") VkMemBuffer_Deinit :: proc(self: ^VkMemBuffer) {
	for b, i in gVkMemBufs {
		if b == self {
			ordered_remove(&gVkMemBufs, i) //!no unordered
			break
		}
	}
	if !self.single do gVkMemIdxCnts[self.allocateInfo.memoryTypeIndex] -= 1
	VkMemBuffer_Deinit2(self)
	free(self, vkArenaAllocator)
}

VkAllocatorError :: enum {
	NONE,
	DEVICE_MEMORY_LIMIT,
}

@(private = "file") VkMemBuffer_BindBufferNode :: proc(
	self: ^VkMemBuffer,
	vkResource: $T,
	cellCnt: VkSize,
) -> (VkResourceRange, VkAllocatorError) where T == vk.Buffer || T == vk.Image {
	VkMemBuffer_BindBufferNodeInside :: proc(self: ^VkMemBuffer, vkResource: $T, idx: VkSize) where T == vk.Buffer || T == vk.Image {
		when (T == vk.Buffer) {
			res := vk.BindBufferMemory(vkDevice, vkResource, self.deviceMem, self.cellSize * idx)
			if res != .SUCCESS do trace.panic_log("VkMemBuffer_BindBufferNodeInside BindBufferMemory : ", res)
		} else when (T == vk.Image) {
			res := vk.BindImageMemory(vkDevice, vkResource, self.deviceMem, self.cellSize * idx)
			if res != .SUCCESS do trace.panic_log("VkMemBuffer_BindBufferNodeInside BindImageMemory : ", res)
		}
	}
	if cellCnt == 0 do trace.panic_log("if cellCnt == 0")
	if self.single {
		VkMemBuffer_BindBufferNodeInside(self, vkResource, 0)
		return nil, .NONE
	}

	cur: ^VkMemBufferNode = auto_cast self.cur
	for !(cur.free && cellCnt <= cur.size) {
		cur = auto_cast (cur.node.next if cur.node.next != nil else self.list.head)
		if cur == auto_cast self.cur {
			return nil, .DEVICE_MEMORY_LIMIT
		}
	}
	VkMemBuffer_BindBufferNodeInside(self, vkResource, cur.idx)
	cur.free = false
	remain := cur.size - cellCnt
	self.cur = auto_cast cur

	range: VkResourceRange = auto_cast cur
	curNext: ^VkMemBufferNode = auto_cast  (cur.node.next if cur.node.next != nil else self.list.head)
	if cur == curNext {
		if remain > 0 {
			list.push_back(&self.list, auto_cast new(VkMemBufferNode))
			tail: ^VkMemBufferNode = auto_cast self.list.tail
			tail.free = true
			tail.size = remain
			tail.idx = cellCnt
		}
	} else {
		if remain > 0 {
			if !curNext.free || curNext.idx < cur.idx {
				list.insert_after(&self.list, auto_cast cur, auto_cast new(VkMemBufferNode))
				next: ^VkMemBufferNode = auto_cast cur.node.next
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
@(private = "file") VkMemBuffer_UnBindBufferNode :: proc(
	self: ^VkMemBuffer,
	vkResource: $T,
	range: VkResourceRange,
) where T == vk.Buffer ||
	T == vk.Image {
		
	when T == vk.Buffer {
		vk.DestroyBuffer(vkDevice, vkResource, nil)
	} else when T == vk.Image {
		vk.DestroyImage(vkDevice, vkResource, nil)
	}

	if self.single {
		VkMemBuffer_Deinit(self)
		return
	}
	range_: ^VkMemBufferNode = auto_cast range
	range_.free = true

	next: ^VkMemBufferNode = auto_cast (range_.node.next if range_.node.next != nil else self.list.head)
	if next.free && range_ != next && range_.idx < next.idx {
		range_.size += next.size
		list.remove(&self.list, auto_cast next)
		free(next, vkArenaAllocator)
	}

	prev: ^VkMemBufferNode = auto_cast (range_.node.prev if range_.node.prev != nil else self.list.tail)
	if prev.free && range_ != prev && range_.idx > prev.idx {
		range_.size += prev.size
		range_.idx -= prev.size
		list.remove(&self.list, auto_cast prev)
		free(prev, vkArenaAllocator)
	}
	if self.len == 1 || gVkMemIdxCnts[self.allocateInfo.memoryTypeIndex] > VkMaxMemIdxCnt {
		for b in gVkMemBufs {
			if self != b && self.allocateInfo.memoryTypeIndex == b.allocateInfo.memoryTypeIndex && VkMemBuffer_IsEmpty(b) {
				gVkMemIdxCnts[b.allocateInfo.memoryTypeIndex] -= 1
				VkMemBuffer_Deinit(b)
			}
		}
		if VkMemBuffer_IsEmpty(self) {
			gVkMemIdxCnts[self.allocateInfo.memoryTypeIndex] -= 1
			VkMemBuffer_Deinit(self)
		}
	}

}

@(private = "file") VkMemBuffer_CreateFromResource :: proc(
	vkResource: $T,
	memProp: vk.MemoryPropertyFlags,
	outIdx: ^VkResourceRange,
	maxSize: VkSize,
) -> (memBuf: ^VkMemBuffer) where T == vk.Buffer || T == vk.Image {
	memType:u32
	ok:bool

	_BindBufferNode :: proc(b: ^VkMemBuffer, memType: u32, vkResource: $T, cellCnt:VkSize, outIdx: ^VkResourceRange, memBuf: ^^VkMemBuffer) -> bool {
		if b.allocateInfo.memoryTypeIndex != memType {
			return false
		}
		outIdx_, err := VkMemBuffer_BindBufferNode(b, vkResource, cellCnt)
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
	_Init :: proc(BLKSize:VkSize, maxSize_:VkSize, memRequire: vk.MemoryRequirements, memProp_:vk.MemoryPropertyFlags) -> Maybe(VkMemBuffer) {
		memBufTLen := max(BLKSize, maxSize_) / memRequire.alignment + 1
		if max(BLKSize, maxSize_) % memRequire.alignment == 0 do memBufTLen -= 1
		return VkMemBuffer_Init(
			memRequire.alignment,
			memBufTLen,
			memRequire.memoryTypeBits,
			memProp_,
		)
	}
	memRequire: vk.MemoryRequirements
	when T == vk.Buffer {
		vk.GetBufferMemoryRequirements(vkDevice, vkResource, &memRequire)
	} else when T == vk.Image {
		vk.GetImageMemoryRequirements(vkDevice, vkResource, &memRequire)
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
		memType, ok = vkFindMemType(memRequire.memoryTypeBits, memProp_)
		if !ok {
			memProp_ = memProp
			memType, ok = vkFindMemType(memRequire.memoryTypeBits, memProp_)
			if !ok do trace.panic_log("vkFindMemType Failed")
		}
		if !_BindBufferNode(b, memType, vkResource, cellCnt, outIdx, &memBuf) do continue
		break
	}

	if memBuf == nil {
		memBuf = new(VkMemBuffer, vkArenaAllocator)

		memFlag := vk.MemoryPropertyFlags{.HOST_VISIBLE, .DEVICE_LOCAL}
		BLKSize := vkMemSpcialBlockLen if memProp_ >= memFlag else vkMemBlockLen
		memBufT := _Init(BLKSize, maxSize_, memRequire, memProp_)

		if memBufT == nil {
			free(memBuf)
			memBuf = nil

			memProp_ = {.HOST_VISIBLE, .HOST_CACHED}
			for b in gVkMemBufs {
				if b.cellSize != memRequire.alignment do continue
				memType, ok := vkFindMemType(memRequire.memoryTypeBits, memProp_)
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
	}
	gVkMemIdxCnts[memBuf.allocateInfo.memoryTypeIndex] += 1
	return
}

@(private = "file") VkMemBuffer_CreateFromResourceSingle :: proc(vkResource: $T) -> (memBuf: ^VkMemBuffer) 
where T == vk.Buffer || T == vk.Image {
	memBuf = nil
	memRequire: vk.MemoryRequirements

	when T == vk.Buffer {
		vk.GetBufferMemoryRequirements(vkDevice, vkResource, &memRequire)
	} else when T == vk.Image {
		vk.GetImageMemoryRequirements(vkDevice, vkResource, &memRequire)
	}

	memBuf = new(VkMemBuffer, vkArenaAllocator)
	outMemBuf :=  VkMemBuffer_InitSingle(memRequire.size, memRequire.memoryTypeBits)
	memBuf^ = outMemBuf.?

	VkMemBuffer_BindBufferNode(memBuf, vkResource, 1) //can't (must no) error

	non_zero_append(&gVkMemBufs, memBuf)
	return
}

@(private = "file") AppendOp :: proc(node: OpNode) {
	SrcCreating :: #force_inline proc  "contextless" (node: ^OpNode) {
		#partial switch &n in node^ {	
		case OpCreateBuffer:
			n.src.creating = &n
		case OpCreateTexture:
			n.src.creating = &n
		}
	}
	if exiting {
		#partial switch n in node {
		case OpMapCopy:
			if n.allocator != nil do delete(n.data, n.allocator.?)
			return
		case OpCreateBuffer:
			if n.allocator != nil && n.data != nil do delete(n.data, n.allocator.?)
			return
		case OpCreateTexture:
			if n.allocator != nil && n.data != nil do delete(n.data, n.allocator.?)
			return
		}
	} else {
		_Handle :: #force_inline proc(n: $T, node: OpNode) -> bool {
			if n.allocator != nil {
				sync.atomic_mutex_lock(&gQueueMtx)
				non_zero_append(&opAllocQueue, node)
				non_zero_append(&opQueue, node)
				SrcCreating(&opQueue[len(opQueue) - 1])
				sync.atomic_mutex_unlock(&gQueueMtx)
				return true
			}
			return false
		}
		#partial switch n in node {
		case OpMapCopy:
			if _Handle(n, node) do return
		case OpCreateBuffer:
			if _Handle(n, node) do return
		case OpCreateTexture:
			if _Handle(n, node) do return
		}
	}
	sync.atomic_mutex_lock(&gQueueMtx)
	non_zero_append(&opQueue, node)
	SrcCreating(&opQueue[len(opQueue) - 1])
	sync.atomic_mutex_unlock(&gQueueMtx)
}

@(private = "file") AppendOpSave :: proc(node: OpNode) {
	#partial switch n in node {
	case OpMapCopy, OpCreateBuffer, OpCreateTexture:
		sync.atomic_mutex_lock(&gQueueMtx)
		non_zero_append(&opAllocQueue, node)
		sync.atomic_mutex_unlock(&gQueueMtx)
	}
	non_zero_append(&opSaveQueue, node)
}


VkBufferResource_CreateBuffer :: proc(
	self: ^VkBufferResource,
	option: BufferCreateOption,
	data: []byte,
	isCopy: bool = false,
	allocator: Maybe(runtime.Allocator) = nil,
) {
	self.option = option
	if isCopy {
		copyData:[]byte
		if allocator == nil {
			copyData = mem.make_non_zeroed([]byte, len(data), engineDefAllocator)
		} else {
			copyData = mem.make_non_zeroed([]byte, len(data), allocator.?)
		}
		mem.copy(raw_data(copyData), raw_data(data), len(data))
		AppendOp(OpCreateBuffer{src = self, data = copyData, allocator = allocator == nil ? engineDefAllocator : allocator.?})
	} else {
		AppendOp(OpCreateBuffer{src = self, data = data, allocator = allocator})
	}
}
VkBufferResource_CreateTexture :: proc(
	self: ^VkTextureResource,
	option: TextureCreateOption,
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
			copyData = mem.make_non_zeroed([]byte, len(data), engineDefAllocator)
		} else {
			copyData = mem.make_non_zeroed([]byte, len(data), allocator.?)
		}
		mem.copy(raw_data(copyData), raw_data(data), len(data))
		AppendOp(OpCreateTexture{src = self, data = copyData, allocator = allocator == nil ? engineDefAllocator : allocator.?})
	} else {
		AppendOp(OpCreateTexture{src = self, data = data, allocator = allocator})
	}
}

@(private = "file") VkBufferResource_CreateBufferNoAsync :: #force_inline proc(
	self: ^VkBufferResource,
	option: BufferCreateOption,
	data: []byte,
	allocator: Maybe(runtime.Allocator) = nil,
) {
	self.option = option
	ExecuteCreateBuffer(self, data, allocator)
}

@(private = "file") VkBufferResource_DestroyBufferNoAsync :: proc(self: ^VkBufferResource) {
	VkMemBuffer_UnBindBufferNode(self.vkMemBuffer, self.__resource, self.idx)
	self.__resource = 0
}

@(private = "file") VkBufferResource_DestroyTextureNoAsync :: proc(self: ^VkTextureResource) {
	vk.DestroyImageView(vkDevice, self.imgView, nil)
	VkMemBuffer_UnBindBufferNode(self.vkMemBuffer, self.__resource, self.idx)
	self.__resource = 0
}

@(private = "file") VkBufferResource_MapCopy :: #force_inline proc(
	self: VkUnionResource,
	data: []byte,
	allocator: Maybe(runtime.Allocator) = nil,
) {
	AppendOp(OpMapCopy{
		allocator = allocator,
		data = data,
		resource = auto_cast self,
	})
}

@(private = "file", require_results) VkBufferResource_MapCreating :: proc (
	self: VkUnionResource,
	data: []byte,
	allocator: Maybe(runtime.Allocator),
) -> bool {
	inside :: #force_inline proc(v: ^$T, data: []byte, allocator: Maybe(runtime.Allocator)) -> bool {
		if v.creating != nil {
			if allocator != nil {
				delete(v.creating.data, allocator.?)
			}
			v.creating.data = data
			v.creating.allocator = allocator
			return true
		}
		return false
	}
	#partial switch &v in self {
		case ^VkBufferResource:
			if inside(v, data, allocator) do return true
		case ^VkTextureResource:
			if inside(v, data, allocator) do return true
	}
	return false
}

//! unlike CopyUpdate, data cannot be a temporary variable.
VkBufferResource_MapUpdateSlice :: #force_inline proc(
	self: VkUnionResource,
	data: $T/[]$E,
	allocator: Maybe(runtime.Allocator) = nil,
) {
	_data := mem.slice_to_bytes(data)
	if VkBufferResource_MapCreating(self, _data, allocator) do return
	VkBufferResource_MapCopy(self, _data, allocator)
}
//! unlike CopyUpdate, data cannot be a temporary variable.
VkBufferResource_MapUpdate :: #force_inline proc(
	self: VkUnionResource,
	data: ^$T,
	allocator: Maybe(runtime.Allocator) = nil,
) {
	_data := mem.ptr_to_bytes(data)
	if VkBufferResource_MapCreating(self, _data, allocator) do return
	VkBufferResource_MapCopy(self, _data, allocator)
}

VkBufferResource_CopyUpdateSlice :: #force_inline proc(
	self: VkUnionResource,
	data: $T/[]$E,
	allocator: Maybe(runtime.Allocator) = nil,
) {
	bytes := mem.slice_to_bytes(data)
	copyData:[]byte
	if allocator == nil {
		copyData = mem.make_non_zeroed([]byte, len(bytes), engineDefAllocator)
	} else {
		copyData = mem.make_non_zeroed([]byte, len(bytes), allocator.?)
	}
	intrinsics.mem_copy_non_overlapping(raw_data(copyData), raw_data(bytes), len(bytes))

	if VkBufferResource_MapCreating(self, copyData, allocator == nil ? engineDefAllocator : allocator.?) do return
	VkBufferResource_MapCopy(self, copyData, allocator == nil ? engineDefAllocator : allocator.?)
}
VkBufferResource_CopyUpdate :: #force_inline proc(
	self: VkUnionResource,
	data: ^$T,
	allocator: Maybe(runtime.Allocator) = nil,
) {
	copyData:[]byte
	bytes := mem.ptr_to_bytes(data)

	if allocator == nil {
		copyData = mem.make_non_zeroed([]byte, len(bytes), engineDefAllocator)
	} else {
		copyData = mem.make_non_zeroed([]byte, len(bytes), allocator.?)
	}
	intrinsics.mem_copy_non_overlapping(raw_data(copyData), raw_data(bytes), len(bytes))

	if VkBufferResource_MapCreating(self, copyData, allocator == nil ? engineDefAllocator : allocator.?) do return
	VkBufferResource_MapCopy(self, copyData, allocator == nil ? engineDefAllocator : allocator.?)
}

VkBufferResource_Deinit :: proc(self: ^$T) where T == VkBufferResource || T == VkTextureResource {
	when T == VkBufferResource {
		buffer: ^VkBufferResource = auto_cast self
		buffer.option.len = 0
		if buffer.option.type == .UNIFORM {
			AppendOp(OpReleaseUniform{src = buffer})
		} else {
			AppendOp(OpDestroyBuffer{src = buffer})
		}
	} else when T == VkTextureResource {
		texture: ^VkTextureResource = auto_cast self
		texture.option.len = 0
		if self.vkMemBuffer == nil {
			vk.DestroyImageView(vkDevice, texture.imgView, nil)
		} else {
			AppendOp(OpDestroyTexture{src = texture})
		}
	}
}
//no need @(private="file") VkBufferResource_CreateTextureNoAsync


//not mul cellsize
@(private = "file") VkMemBuffer_Map :: #force_inline proc "contextless" (
	self: ^VkMemBuffer,
	start: VkSize,
	size: VkSize,
) -> [^]byte {
	outData: rawptr
	vk.MapMemory(vkDevice, self.deviceMem, start, size, {}, &outData)
	return auto_cast outData
}
@(private = "file") VkMemBuffer_UnMap :: #force_inline proc "contextless" (self: ^VkMemBuffer) {
	self.mapSize = 0
	vk.UnmapMemory(vkDevice, self.deviceMem)
}

@(private = "file") BindUniformBuffer :: proc(
	self: ^VkBufferResource,
	data: []byte,
	allocator: Maybe(runtime.Allocator),
) {
	if gVkMinUniformBufferOffsetAlignment > 0 {
		self.option.len = (self.option.len + gVkMinUniformBufferOffsetAlignment - 1) & ~(gVkMinUniformBufferOffsetAlignment - 1)
	}
	non_zero_append(&gTempUniforms, vkTempUniformStruct{uniform = self, data = data, size = self.option.len, allocator = allocator})
}

@(private = "file") ExecuteReleaseUniform :: proc(
	buf: ^VkBufferResource,
) {
	gUniforms[buf.gUniformIndices[0]].uniforms[buf.gUniformIndices[1]] = nil

	empty:=true
	for &v in gUniforms[buf.gUniformIndices[0]].uniforms {
		if v != nil {
			empty = false
			break
		}
	}
	if empty {
		VkBufferResource_DestroyBufferNoAsync(buf)
		gUniforms[buf.gUniformIndices[0]] = {}

		return
	}
}

@(private = "file") ExecuteCreateBuffer :: proc(
	self: ^VkBufferResource,
	data: []byte,
	allocator: Maybe(runtime.Allocator) = nil,
) {
	if self.option.type == .__STAGING {
		self.option.resourceUsage = .CPU
		self.option.single = false
	}
	self.creating = nil //clear creating, because resource is created

	memProp : vk.MemoryPropertyFlags;
	switch self.option.resourceUsage {
		case .GPU:memProp = {.DEVICE_LOCAL}
		case .CPU:memProp = {.HOST_CACHED, .HOST_VISIBLE}
	}
	bufUsage:vk.BufferUsageFlags
	switch self.option.type {
		case .VERTEX: bufUsage = {.VERTEX_BUFFER}
		case .INDEX: bufUsage = {.INDEX_BUFFER}
		case .UNIFORM: //bufUsage = {.UNIFORM_BUFFER} no create each obj
			if self.option.resourceUsage == .GPU do trace.panic_log("UNIFORM BUFFER can't resourceUsage .GPU")
			BindUniformBuffer(self, data, allocator)
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

	last:^VkBufferResource
	if data != nil && self.option.resourceUsage == .GPU {
		bufInfo.usage |= {.TRANSFER_DST}
		if self.option.len > auto_cast len(data) do trace.panic_log("create_buffer _data not enough size. ", self.option.len, ", ", len(data))
		
		last = new(VkBufferResource, vkBufTempArenaAllocator)
		last^ = {}
		VkBufferResource_CreateBufferNoAsync(last, {
			len = self.option.len,
			resourceUsage = .CPU,
			single = false,
			type = .__STAGING,
		}, data, allocator)
	} else if self.option.type == .__STAGING {
		if data == nil do trace.panic_log("staging buffer data can't nil")
	}

	res := vk.CreateBuffer(vkDevice, &bufInfo, nil, &self.__resource)
	if res != .SUCCESS do trace.panic_log("res := vk.CreateBuffer(vkDevice, &bufInfo, nil, &self.__resource) : ", res)

	self.vkMemBuffer = VkMemBuffer_CreateFromResourceSingle(self.__resource) if self.option.single else
	VkMemBuffer_CreateFromResource(self.__resource, memProp, &self.idx, 0)

	if data != nil {
		if self.option.resourceUsage != .GPU {
			AppendOpSave(OpMapCopy{
				resource = auto_cast self,
				data = data,
				allocator = allocator
			})
		} else {
			 //above VkBufferResource_CreateBufferNoAsync call, staging buffer is added and map_copy command is added.
			AppendOpSave(OpCopyBuffer{src = last, target = self})
			AppendOpSave(OpDestroyBuffer{src = last})
		}
	}
}
@(private = "file") ExecuteCreateTexture :: proc(
	self: ^VkTextureResource,
	data: []byte,
	allocator: Maybe(runtime.Allocator) = nil,
) {
	memProp : vk.MemoryPropertyFlags;
	switch self.option.resourceUsage {
		case .GPU:memProp = {.DEVICE_LOCAL}
		case .CPU:memProp = {.HOST_CACHED, .HOST_VISIBLE}
	}
	texUsage:vk.ImageUsageFlags = {}
	isDepth := TextureFmt_IsDepth(self.option.format)

	if .IMAGE_RESOURCE in self.option.textureUsage do texUsage |= {.SAMPLED}
	if .FRAME_BUFFER in self.option.textureUsage {
		if isDepth {
			texUsage |= {.DEPTH_STENCIL_ATTACHMENT}
		} else {
			texUsage |= {.COLOR_ATTACHMENT}
		}
	}
	if .__INPUT_ATTACHMENT in self.option.textureUsage do texUsage |= {.INPUT_ATTACHMENT}
	if .__STORAGE_IMAGE in self.option.textureUsage do texUsage |= {.STORAGE}
	if .__TRANSIENT_ATTACHMENT in self.option.textureUsage do texUsage |= {.TRANSIENT_ATTACHMENT}

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
	bit : u32 = auto_cast TextureFmt_BitSize(self.option.format)

	imgInfo := vk.ImageCreateInfo{
		sType = .IMAGE_CREATE_INFO,
		arrayLayers = self.option.len,
		usage = texUsage,
		sharingMode = .EXCLUSIVE,
		extent = {width = self.option.width, height = self.option.height, depth = 1},
		samples = samplesToVkSampleCountFlags(self.option.samples),
		tiling = tiling,
		mipLevels = 1,
		format = TextureFmtToVkFmt(self.option.format),
		imageType = TextureTypeToVkImageType(self.option.type),
		initialLayout = .UNDEFINED,
	}

	last:^VkBufferResource
	if data != nil && self.option.resourceUsage == .GPU {
		imgInfo.usage |= {.TRANSFER_DST}
		
		last = new(VkBufferResource, vkBufTempArenaAllocator)
		last^ = {}
		VkBufferResource_CreateBufferNoAsync(last, {
			len = auto_cast(imgInfo.extent.width * imgInfo.extent.height * imgInfo.extent.depth * imgInfo.arrayLayers * bit),
			resourceUsage = .CPU,
			single = false,
			type = .__STAGING,
		}, data, allocator)
	}

	res := vk.CreateImage(vkDevice, &imgInfo, nil, &self.__resource)
	if res != .SUCCESS do trace.panic_log("res := vk.CreateImage(vkDevice, &bufInfo, nil, &self.__resource) : ", res)

	self.vkMemBuffer = VkMemBuffer_CreateFromResourceSingle(self.__resource) if self.option.single else
	VkMemBuffer_CreateFromResource(self.__resource, memProp, &self.idx, 0)

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
	
	res = vk.CreateImageView(vkDevice, &imgViewInfo, nil, &self.imgView)
	if res != .SUCCESS do trace.panic_log("res = vk.CreateImageView(vkDevice, &imgViewInfo, nil, &self.imgView) : ", res)

	self.creating = nil //clear creating, because resource is created

	if data != nil {
		if self.option.resourceUsage != .GPU {
			AppendOpSave(OpMapCopy{
				resource = auto_cast self,
				data = data,
				allocator = allocator
			})
		} else {
			 //above VkBufferResource_CreateBufferNoAsync call, staging buffer is added and map_copy command is added.
			AppendOpSave(OpCopyBufferToTexture{src = last, target = self})
			AppendOpSave(OpDestroyBuffer{src = last})
		}
	}
}
@(private = "file") ExecuteRegisterDescriptorPool :: #force_inline proc(size: []VkDescriptorPoolSize) {
	//?? no need? execute_register_descriptor_pool
}
@(private = "file") __CreateDescriptorPool :: proc(size:[]VkDescriptorPoolSize, out:^VkDescriptorPoolMem) {
	poolSize :[]vk.DescriptorPoolSize = mem.make_non_zeroed([]vk.DescriptorPoolSize, len(size))
	defer delete(poolSize)

	for _, i in size {
		poolSize[i].descriptorCount = size[i].cnt * vkPoolBlock
		poolSize[i].type = DescriptorTypeToVkDescriptorType(size[i].type)
	}
	poolInfo := vk.DescriptorPoolCreateInfo{
		sType = .DESCRIPTOR_POOL_CREATE_INFO,
		poolSizeCount = auto_cast len(poolSize),
		pPoolSizes = raw_data(poolSize),
		maxSets = vkPoolBlock,
	}
	res := vk.CreateDescriptorPool(vkDevice, &poolInfo, nil, &out.pool)
	if res != .SUCCESS do trace.panic_log("res := vk.CreateDescriptorPool(vkDevice, &poolInfo, nil, &out.pool) : ", res)
}

VkUpdateDescriptorSets :: proc(sets: []VkDescriptorSet) {
	AppendOp(Op__UpdateDescriptorSets{sets = sets})
}

@(private = "file") ExecuteUpdateDescriptorSets :: proc(sets: []VkDescriptorSet) {
	for &s in sets {
		if s.__set == 0 {
			if raw_data(s.size) in gDesciptorPools {
			} else {
				gDesciptorPools[raw_data(s.size)] = mem.make_non_zeroed([dynamic]VkDescriptorPoolMem, vkArenaAllocator)
				non_zero_append(&gDesciptorPools[raw_data(s.size)], VkDescriptorPoolMem{cnt = 0})
				__CreateDescriptorPool(s.size, &gDesciptorPools[raw_data(s.size)][0])
			}

			last := &gDesciptorPools[raw_data(s.size)][len(gDesciptorPools[raw_data(s.size)]) - 1]
			if last.cnt >= vkPoolBlock {
				non_zero_append(&gDesciptorPools[raw_data(s.size)], VkDescriptorPoolMem{cnt = 0})
				last = &gDesciptorPools[raw_data(s.size)][len(gDesciptorPools[raw_data(s.size)]) - 1]
				__CreateDescriptorPool(s.size, last)
			}

			last.cnt += 1
			allocInfo := vk.DescriptorSetAllocateInfo{
				sType = .DESCRIPTOR_SET_ALLOCATE_INFO,
				descriptorPool = last.pool,
				descriptorSetCount = 1,
				pSetLayouts = &s.layout,
			}
			res := vk.AllocateDescriptorSets(vkDevice, &allocInfo, &s.__set)
			if res != .SUCCESS do trace.panic_log("res := vk.AllocateDescriptorSets(vkDevice, &allocInfo, &s.__set) : ", res)
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
				case ^VkBufferResource:
					bufCnt += 1
				case ^VkTextureResource:
					texCnt += 1
				case:
					trace.panic_log("invaild type s.__resources[0:cnt] r")
			}
		}

		bufs := mem.make_non_zeroed([]vk.DescriptorBufferInfo, bufCnt, vkTempArenaAllocator)
		texs := mem.make_non_zeroed([]vk.DescriptorImageInfo, texCnt, vkTempArenaAllocator)
		bufCnt = 0
		texCnt = 0

		for r in s.__resources[0:cnt] {
			switch v in r {
				case ^VkBufferResource:
					bufs[bufCnt] = vk.DescriptorBufferInfo{
						buffer = ((^VkBufferResource)(v)).__resource,
						offset = ((^VkBufferResource)(v)).gUniformIndices[2],
						range = ((^VkBufferResource)(v)).option.len
					}
					bufCnt += 1
				case ^VkTextureResource:
					texs[texCnt] = vk.DescriptorImageInfo{
						imageLayout = .SHADER_READ_ONLY_OPTIMAL,
						imageView = ((^VkTextureResource)(v)).imgView,
						sampler = ((^VkTextureResource)(v)).sampler,
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
						descriptorType = DescriptorTypeToVkDescriptorType(n.type),
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
						descriptorType = DescriptorTypeToVkDescriptorType(n.type),
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
@(private = "file") ExecuteCopyBuffer :: proc(src: ^VkBufferResource, target: ^VkBufferResource) {
	copyRegion := vk.BufferCopy{
		size = target.option.len,
		srcOffset = 0,
		dstOffset = 0
	}
	vk.CmdCopyBuffer(gCmd, src.__resource, target.__resource, 1, &copyRegion)
}
@(private = "file") ExecuteCopyBufferToTexture :: proc(src: ^VkBufferResource, target: ^VkTextureResource) {
	vkTransitionImageLayout(gCmd, target.__resource, 1, 0, target.option.len, .UNDEFINED, .TRANSFER_DST_OPTIMAL)
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
	vkTransitionImageLayout(gCmd, target.__resource, 1, 0, target.option.len, .TRANSFER_DST_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL)
}
@(private = "file") OpAllocQueueFree :: proc() {
	sync.atomic_mutex_lock(&gQueueMtx)
	defer sync.atomic_mutex_unlock(&gQueueMtx)

	for node in opAllocQueue {
		#partial switch n in node {
		case OpMapCopy:
			if n.allocator != nil do delete(n.data, n.allocator.?)
		}
	}
	clear(&opAllocQueue)
}
@(private = "file") ToBaseResource :: #force_inline proc "contextless" (res:VkUnionResource) -> ^VkBaseResource {
	switch v in res {
		case ^VkBufferResource:
			return v
		case ^VkTextureResource:
			return v
	}
	return nil
}
@(private = "file") SaveToMapQueue :: proc(inoutMemBuf: ^^VkMemBuffer) {
	for &node in opSaveQueue {
		#partial switch n in node {
		case OpMapCopy:
			if inoutMemBuf^ == nil {
				non_zero_append(&opMapQueue, n)
				inoutMemBuf^ = ToBaseResource(n.resource).vkMemBuffer
				node = nil
			} else if ToBaseResource(n.resource).vkMemBuffer == inoutMemBuf^ {
				non_zero_append(&opMapQueue, n)
				node = nil
			}
		}
	}
}
@(private = "file") VkMemBuffer_MapCopyExecute :: proc(self: ^VkMemBuffer, nodes: []OpNode) {
	startIdx: VkSize = max(VkSize)
	endIdx: VkSize = max(VkSize)
	offIdx: u32 = 0

	ranges: [dynamic]vk.MappedMemoryRange
	if self.cache {
		ranges = mem.make_non_zeroed_dynamic_array([dynamic]vk.MappedMemoryRange, context.temp_allocator)
		overlap := mem.make_non_zeroed_dynamic_array([dynamic]^VkMemBufferNode, context.temp_allocator)
		defer delete(overlap)

		out: for i in 0 ..< len(nodes) {
			idx: ^VkMemBufferNode = auto_cast ToBaseResource((nodes[i].(OpMapCopy)).resource).idx
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
			last.offset = math.floor_up(last.offset, vkNonCoherentAtomSize)
			last.size += tmp - last.offset
			last.size = math.ceil_up(last.size, vkNonCoherentAtomSize)

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
			idx: ^VkMemBufferNode = auto_cast ToBaseResource((node.(OpMapCopy)).resource).idx
			startIdx = min(startIdx, idx.idx * self.cellSize)
			endIdx = max(endIdx, (idx.idx + idx.size) * self.cellSize)
		}
	}

	size := endIdx - startIdx

	if self.mapStart > startIdx || self.mapSize + self.mapStart < endIdx || self.mapSize < endIdx - startIdx {
		if self.mapSize > 0 do VkMemBuffer_UnMap(self)
	outData: [^]byte = VkMemBuffer_Map(self, startIdx, size)
	self.mapData = outData
	self.mapSize = size
	self.mapStart = startIdx
	} else {
		if self.cache {
			res := vk.InvalidateMappedMemoryRanges(vkDevice, offIdx, raw_data(ranges))
			if res != .SUCCESS do trace.panic_log("res := vk.InvalidateMappedMemoryRanges(vkDevice, offIdx, raw_data(ranges)) : ", res)
		}
	}

	for &node in nodes {
		mapCopy := &node.(OpMapCopy)
		idx: ^VkMemBufferNode = auto_cast ToBaseResource(mapCopy.resource).idx
		start_ := idx.idx * self.cellSize - self.mapStart + ToBaseResource(mapCopy.resource).gUniformIndices[2]
		mem.copy_non_overlapping(&self.mapData[start_], raw_data(mapCopy.data), len(mapCopy.data))
	}

	if self.cache {
		res := vk.FlushMappedMemoryRanges(vkDevice, auto_cast len(ranges), raw_data(ranges))
		if res != .SUCCESS do trace.panic_log("res := vk.FlushMappedMemoryRanges(vkDevice, auto_cast len(ranges), raw_data(ranges)) : ", res)

		delete(ranges)
	}
}

@(private = "file") ExecuteDestroyBuffer :: proc(buf:^VkBufferResource) {
	VkBufferResource_DestroyBufferNoAsync(buf)
}
@(private = "file") ExecuteDestroyTexture :: proc(tex:^VkTextureResource) {
	VkBufferResource_DestroyTextureNoAsync(tex)
}

//? delete private when need
@(private = "file") VkMemBuffer_IsEmpty :: proc(self: ^VkMemBuffer) -> bool {
	return !self.single && ((self.list.head != nil &&
		self.list.head.next == nil &&
		((^VkMemBufferNode)(self.list.head)).free) || 
		(self.list.head == nil))
}

vkOpExecuteDestroy :: proc() {
	sync.atomic_mutex_lock(&gDestroyQueueMtx)
	if len(opDestroyQueue) == 0 {
		sync.atomic_mutex_unlock(&gDestroyQueueMtx)

		sync.sema_post(&gWaitOpSem)
		return
	}
	for node in opDestroyQueue {
		#partial switch n in node {
			case OpDestroyBuffer : 
				ExecuteDestroyBuffer(n.src)
			case OpDestroyTexture : 
				ExecuteDestroyTexture(n.src)
		}
	}
	sync.mutex_lock(&gFreeObjectMtx)
	for &o in gFreeObjects {
		for i in 0 ..< o.len {
			o.deinit(  auto_cast &(([^]byte)(o.obj))[i * o.typeSize] )
		}
		mem.free_with_size(o.obj, int(o.len * o.typeSize), engineDefAllocator)
	}
	clear(&gFreeObjects)
	sync.mutex_unlock(&gFreeObjectMtx)
	
	clear(&opDestroyQueue)

	sync.atomic_mutex_unlock(&gDestroyQueueMtx)
	virtual.arena_free_all(&__bufTempArena)

	sync.sema_post(&gWaitOpSem)
}

vkOpExecute :: proc(waitAndDestroy: bool) {
	sync.atomic_mutex_lock(&gQueueMtx)
	if len(opQueue) == 0 {
		sync.atomic_mutex_unlock(&gQueueMtx)
		if waitAndDestroy {
			vkWaitGraphicsIdle()
			vkOpExecuteDestroy()
		}
		return
	}
	resize(&opSaveQueue, len(opQueue))
	mem.copy_non_overlapping(raw_data(opSaveQueue), raw_data(opQueue), len(opQueue) * size_of(OpNode))
	clear(&opQueue)
	sync.atomic_mutex_unlock(&gQueueMtx)

	clear(&opMapQueue)
	for &node in opSaveQueue {
		#partial switch n in node {
		case OpCreateBuffer:
			ExecuteCreateBuffer(n.src, n.data, n.allocator)
		case OpCreateTexture:
			ExecuteCreateTexture(n.src, n.data, n.allocator)
		case Op__RegisterDescriptorPool:
			ExecuteRegisterDescriptorPool(n.size)
		case:
			continue
		}
		node = nil
	}

	for &node in opSaveQueue {
		#partial switch n in node {
		case OpReleaseUniform:
			ExecuteReleaseUniform(n.src)
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
				uniforms = mem.make_non_zeroed_dynamic_array([dynamic]^VkBufferResource, vkArenaAllocator),	
			}

			bufInfo : vk.BufferCreateInfo = {
				sType = vk.StructureType.BUFFER_CREATE_INFO,
				size = gUniforms[0].max_size,
				usage = {.UNIFORM_BUFFER},
			}
			res := vk.CreateBuffer(vkDevice, &bufInfo, nil, &gUniforms[0].buf)
			if res != .SUCCESS do trace.panic_log("res := vk.CreateBuffer(vkDevice, &bufInfo, nil, &self.__resource) : ", res)

			gUniforms[0].memBuffer = VkMemBuffer_CreateFromResource(gUniforms[0].buf, {.HOST_CACHED, .HOST_VISIBLE}, &gUniforms[0].idx, 0)

			off :VkSize = 0
			for &t, i in gTempUniforms {
				non_zero_append(&gUniforms[0].uniforms, t.uniform)
				
				t.uniform.gUniformIndices[0] = 0
				t.uniform.gUniformIndices[1] = auto_cast i
				t.uniform.gUniformIndices[2] = off
				t.uniform.gUniformIndices[3] = t.size
				t.uniform.__resource = gUniforms[0].buf
				t.uniform.vkMemBuffer = gUniforms[0].memBuffer
				t.uniform.idx = gUniforms[0].idx

				AppendOpSave(OpMapCopy{
					resource = t.uniform,
					data = t.data,
					allocator = t.allocator,
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
										if g.uniforms[i4].gUniformIndices[2] >= t.size {
											g.uniforms[i3] = t.uniform
											t.uniform.gUniformIndices[0] = auto_cast i2
											t.uniform.gUniformIndices[1] = auto_cast i3//0
											t.uniform.gUniformIndices[2] = 0
											t.uniform.gUniformIndices[3] = t.size
											t.uniform.__resource = g.buf
											t.uniform.vkMemBuffer = g.memBuffer
											t.uniform.idx = g.idx

											AppendOpSave(OpMapCopy{
												resource = t.uniform,
												data = t.data,
												allocator = t.allocator,
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
									t.uniform.gUniformIndices[0] = auto_cast i2
									t.uniform.gUniformIndices[1] = auto_cast i3
									t.uniform.gUniformIndices[2] = g.size
									t.uniform.gUniformIndices[3] = t.size
									t.uniform.__resource = g.buf
									t.uniform.vkMemBuffer = g.memBuffer
									t.uniform.idx = g.idx

									AppendOpSave(OpMapCopy{
										resource = t.uniform,
										data = t.data,
										allocator = t.allocator,
									})
									g.size += t.size
									inserted = true
									break out
								}
							} else {
								for i4 in i3+1..<len(g.uniforms) {
									if g.uniforms[i4] != nil {
										if g.uniforms[i4].gUniformIndices[2] - (g.uniforms[i3-1].gUniformIndices[2] + g.uniforms[i3-1].gUniformIndices[3]) >= t.size {
											g.uniforms[i3] = t.uniform
											t.uniform.gUniformIndices[0] = auto_cast i2
											t.uniform.gUniformIndices[1] = auto_cast i3
											t.uniform.gUniformIndices[2] = g.uniforms[i3-1].gUniformIndices[2] + g.uniforms[i3-1].gUniformIndices[3]
											t.uniform.gUniformIndices[3] = t.size
											t.uniform.__resource = g.buf
											t.uniform.vkMemBuffer = g.memBuffer
											t.uniform.idx = g.idx

											AppendOpSave(OpMapCopy{
												resource = t.uniform,
												data = t.data,
												allocator = t.allocator,
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
									t.uniform.gUniformIndices[0] = auto_cast i2
									t.uniform.gUniformIndices[1] = auto_cast i3
									t.uniform.gUniformIndices[2] = g.uniforms[i3-1].gUniformIndices[2] + g.uniforms[i3-1].gUniformIndices[3]
									t.uniform.gUniformIndices[3] = t.size
									t.uniform.__resource = g.buf
									t.uniform.vkMemBuffer = g.memBuffer
									t.uniform.idx = g.idx

									AppendOpSave(OpMapCopy{
										resource = t.uniform,
										data = t.data,
										allocator = t.allocator,
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
						t.uniform.gUniformIndices[0] = auto_cast i2
						t.uniform.gUniformIndices[1] = auto_cast (len(g.uniforms) - 1)
						t.uniform.gUniformIndices[2] = g.uniforms[len(g.uniforms) - 2].gUniformIndices[2] + g.uniforms[len(g.uniforms) - 2].gUniformIndices[3]
						t.uniform.gUniformIndices[3] = t.size
						t.uniform.__resource = g.buf
						t.uniform.vkMemBuffer = g.memBuffer
						t.uniform.idx = g.idx

						AppendOpSave(OpMapCopy{
							resource = t.uniform,
							data = t.data,
							allocator = t.allocator,
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
					uniforms = mem.make_non_zeroed_dynamic_array([dynamic]^VkBufferResource, vkArenaAllocator),	
				}

				bufInfo : vk.BufferCreateInfo = {
					sType = vk.StructureType.BUFFER_CREATE_INFO,
					size = gUniforms[len(gUniforms) - 1].max_size,
					usage = {.UNIFORM_BUFFER},
				}
				res := vk.CreateBuffer(vkDevice, &bufInfo, nil, &gUniforms[len(gUniforms) - 1].buf)
				if res != .SUCCESS do trace.panic_log("res := vk.CreateBuffer(vkDevice, &bufInfo, nil, &self.__resource) : ", res)

				gUniforms[len(gUniforms) - 1].memBuffer = VkMemBuffer_CreateFromResource(gUniforms[len(gUniforms) - 1].buf, {.HOST_CACHED, .HOST_VISIBLE}, &gUniforms[len(gUniforms) - 1].idx, 0)

				off :VkSize = 0
				for &t, i in gNonInsertedUniforms {
					non_zero_append(&gUniforms[len(gUniforms) - 1].uniforms, t.uniform)
					
					t.uniform.gUniformIndices[0] = auto_cast (len(gUniforms) - 1)
					t.uniform.gUniformIndices[1] = auto_cast i
					t.uniform.gUniformIndices[2] = off
					t.uniform.gUniformIndices[3] = t.size
					t.uniform.__resource = gUniforms[len(gUniforms) - 1].buf
					t.uniform.idx = gUniforms[len(gUniforms) - 1].idx
					t.uniform.vkMemBuffer = gUniforms[len(gUniforms) - 1].memBuffer

					AppendOpSave(OpMapCopy{
						resource = t.uniform,
						data = t.data,
						allocator = t.allocator,
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
			non_zero_append(&opDestroyQueue, n)
		case OpDestroyTexture:
			non_zero_append(&opDestroyQueue, n)
		case:
			continue
		}
		node = nil
	}
	sync.atomic_mutex_unlock(&gDestroyQueueMtx)

	memBufT: ^VkMemBuffer = nil
	SaveToMapQueue(&memBufT)
	for len(opMapQueue) > 0 {
		VkMemBuffer_MapCopyExecute(memBufT, opMapQueue[:])
		clear(&opMapQueue)
		memBufT = nil
		SaveToMapQueue(&memBufT)
	}

	OpAllocQueueFree()

	haveCmds := false
	for node in opSaveQueue {
		#partial switch n in node {
		case OpCopyBuffer:
			haveCmds = true
		case OpCopyBufferToTexture:
			haveCmds = true
		case Op__UpdateDescriptorSets:
			ExecuteUpdateDescriptorSets(n.sets)
		}
	}
	if len(gVkUpdateDesciptorSetList) > 0 {
		vk.UpdateDescriptorSets(
			vkDevice,
			auto_cast len(gVkUpdateDesciptorSetList),
			raw_data(gVkUpdateDesciptorSetList),
			0,
			nil,
		)
		clear(&gVkUpdateDesciptorSetList)
		//?call callback this line
	}

	if haveCmds {
		vk.ResetCommandPool(vkDevice, cmdPool, {})

		beginInfo := vk.CommandBufferBeginInfo {
			flags = {.ONE_TIME_SUBMIT},
			sType = vk.StructureType.COMMAND_BUFFER_BEGIN_INFO,
		}
		vk.BeginCommandBuffer(gCmd, &beginInfo)
		for node in opSaveQueue {
			#partial switch n in node {
			case OpCopyBuffer:
				ExecuteCopyBuffer(n.src, n.target)
			case OpCopyBufferToTexture:
				ExecuteCopyBufferToTexture(n.src, n.target)
			}
		}
		vk.EndCommandBuffer(gCmd)
		submitInfo := vk.SubmitInfo {
			commandBufferCount = 1,
			pCommandBuffers    = &gCmd,
			sType              = .SUBMIT_INFO,
		}
		res := vk.QueueSubmit(vkGraphicsQueue, 1, &submitInfo, 0)
		if res != .SUCCESS do trace.panic_log("res := vk.QueueSubmit(vkGraphicsQueue, 1, &submitInfo, 0) : ", res)

		vkWaitGraphicsIdle()
		vkOpExecuteDestroy()
	} else if waitAndDestroy {
		vkWaitGraphicsIdle()
		vkOpExecuteDestroy()
	} else {
		sync.sema_post(&gWaitOpSem)
	}

	virtual.arena_free_all(&__tempArena)

	clear(&opSaveQueue)

}

