#+private
package engine

import "core:container/intrusive/list"
import "core:math"
import "core:mem"
import "core:slice"
import "core:log"
import vk "vendor:vulkan"


// ============================================================================
// Memory Buffer - Initialization
// ============================================================================

// ! don't call vulkan_res.init separately
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
	if !success {
		return nil
	} 

	if memBuf.cache {
		memBuf.allocateInfo.allocationSize = math.ceil_up(len * cellSize, vk_non_coherent_atom_size)
		memBuf.len = memBuf.allocateInfo.allocationSize / cellSize
	}

	res := vk.AllocateMemory(vk_device, &memBuf.allocateInfo, &gVkAllocationCallbacks, &memBuf.deviceMem)
	if res != .SUCCESS {
		return nil
	}

	list.push_back(&memBuf.list, auto_cast new(vk_mem_buffer_node, gVkMemTlsfAllocator))
	((^vk_mem_buffer_node)(memBuf.list.head)).free = true
	((^vk_mem_buffer_node)(memBuf.list.head)).size = memBuf.len
	((^vk_mem_buffer_node)(memBuf.list.head)).idx = 0
	memBuf.cur = memBuf.list.head

	return memBuf
}

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
	if !success do log.panic("memBuf.allocateInfo.memoryTypeIndex, success = vk_find_mem_type(typeFilter, vk.MemoryPropertyFlags{.DEVICE_LOCAL})\n")

	res := vk.AllocateMemory(vk_device, &memBuf.allocateInfo, &gVkAllocationCallbacks, &memBuf.deviceMem)
	if res != .SUCCESS do log.panicf("res := vk.AllocateMemory(vk_device, &memBuf.allocateInfo, nil, &memBuf.deviceMem) : %s\n", res)

	return memBuf
}


// ============================================================================
// Memory Buffer - Deinitialization
// ============================================================================

vk_mem_buffer_Deinit2 :: proc(self: ^vk_mem_buffer) {
	vk.FreeMemory(vk_device, self.deviceMem, &gVkAllocationCallbacks)
	if !self.single {
		n: ^list.Node
		for n = self.list.head; n.next != nil; {
			tmp := n
			n = n.next
			free(tmp, gVkMemTlsfAllocator)
		}
		free(n, gVkMemTlsfAllocator)
		self.list.head = nil
		self.list.tail = nil
	}
}

vk_mem_buffer_Deinit :: proc(self: ^vk_mem_buffer) {
	for b, i in gVkMemBufs {
		if b == self {
			ordered_remove(&gVkMemBufs, i) //!no unordered
			break
		}
	}
	if !self.single do gVkMemIdxCnts[self.allocateInfo.memoryTypeIndex] -= 1
	vk_mem_buffer_Deinit2(self)
	free(self, gVkMemTlsfAllocator)
}


// ============================================================================
// Memory Buffer - Bind/Unbind Operations
// ============================================================================

vk_mem_buffer_BindBufferNode :: proc(
	self: ^vk_mem_buffer,
	vkResource: $T,
	cellCnt: vk.DeviceSize,
) -> (resource_range, vk_allocator_error) where T == vk.Buffer || T == vk.Image {
	vk_mem_buffer_BindBufferNodeInside :: proc(self: ^vk_mem_buffer, vkResource: $T, idx: vk.DeviceSize) where T == vk.Buffer || T == vk.Image {
		when (T == vk.Buffer) {
			res := vk.BindBufferMemory(vk_device, vkResource, self.deviceMem, self.cellSize * idx)
			if res != .SUCCESS do log.panicf("vk_mem_buffer_BindBufferNodeInside BindBufferMemory : %s\n", res)
		} else when (T == vk.Image) {
			res := vk.BindImageMemory(vk_device, vkResource, self.deviceMem, self.cellSize * idx)
			if res != .SUCCESS do log.panicf("vk_mem_buffer_BindBufferNodeInside BindImageMemory : %s\n", res)
		}
	}
	if cellCnt == 0 do log.panic("if cellCnt == 0\n")
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
			list.push_back(&self.list, auto_cast new(vk_mem_buffer_node, gVkMemTlsfAllocator))
			tail: ^vk_mem_buffer_node = auto_cast self.list.tail
			tail.free = true
			tail.size = remain
			tail.idx = cellCnt
		}
	} else {
		if remain > 0 {
			if !curNext.free || curNext.idx < cur.idx {
				list.insert_after(&self.list, auto_cast cur, auto_cast new(vk_mem_buffer_node, gVkMemTlsfAllocator))
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

vk_mem_buffer_UnBindBufferNode :: proc(
	self: ^vk_mem_buffer,
	vkResource: $T,
	range: resource_range,
) where T == vk.Buffer || T == vk.Image {
	when T == vk.Buffer {
		vk.DestroyBuffer(vk_device, vkResource, &gVkAllocationCallbacks)
	} else when T == vk.Image {
		vk.DestroyImage(vk_device, vkResource, &gVkAllocationCallbacks)
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
			free(next, gVkMemTlsfAllocator)
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
			free(prev, gVkMemTlsfAllocator)
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
		list.push_back(&self.list, auto_cast new(vk_mem_buffer_node, gVkMemTlsfAllocator))
		((^vk_mem_buffer_node)(self.list.head)).free = true
		((^vk_mem_buffer_node)(self.list.head)).size = self.len
		((^vk_mem_buffer_node)(self.list.head)).idx = 0
		self.cur = self.list.head
	}
}


// ============================================================================
// Memory Buffer - Resource Creation
// ============================================================================

vk_mem_buffer_CreateFromResource :: proc(
	vkResource: $T,
	memProp: vk.MemoryPropertyFlags,
	outIdx: ^resource_range,
	maxSize: vk.DeviceSize,
	buf_type: __buffer_and_texture_type,
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
			log.panic("vk_mem_buffer_BindBufferNode outIdx_ == nil\n")
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
	if (.HOST_VISIBLE in memProp_) && ((vkMemBlockLen == vkMemSpcialBlockLen) ||
		   ((buf_type == .__STAGING || maxSize_ <= 1024*1024*1)))  {
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
			if !ok do log.panic("vk_find_mem_type Failed\n")
		}
		if !_BindBufferNode(b, memType, vkResource, cellCnt, outIdx, &memBuf) do continue
		break
	}

	if memBuf == nil {
		memBuf = new(vk_mem_buffer, gVkMemTlsfAllocator)

		BLKSize := vkMemSpcialBlockLen if memProp_ >= vk.MemoryPropertyFlags{.HOST_VISIBLE, .DEVICE_LOCAL} else vkMemBlockLen
		memBufT := _Init(BLKSize, maxSize_, memRequire, memProp_)

		if memBufT == nil {
			free(memBuf, gVkMemTlsfAllocator)
			memBuf = nil

			for b in gVkMemBufs {
				if b.cellSize != memRequire.alignment do continue
				memType, ok := vk_find_mem_type(memRequire.memoryTypeBits,  {.HOST_VISIBLE, .HOST_CACHED})
				if !ok do log.panic("vk_find_mem_type\n")
				if !_BindBufferNode(b, memType, vkResource, cellCnt, outIdx, &memBuf) do continue
				break
			}
			if memBuf == nil {
				BLKSize = vkMemBlockLen
				memBufT = _Init(BLKSize, maxSize_, memRequire,  {.HOST_VISIBLE, .HOST_CACHED})
				if memBufT == nil {
					memBufT = _Init(maxSize_, maxSize_, memRequire, memProp_)//원본 사이즈로 할당 재 시도
					if memBufT == nil {
						memBufT = _Init(maxSize_, maxSize_, memRequire, {.HOST_VISIBLE, .HOST_CACHED})//원본 사이즈로 할당 재 시도
						if memBufT == nil {
							log.panic("memBufT == nil\n")
						}
					}
				}
				memBuf = new(vk_mem_buffer, gVkMemTlsfAllocator)
				memBuf^ = memBufT.?
			}
		} else {
			memBuf^ = memBufT.?
		}

		if !_BindBufferNode(memBuf, memBuf.allocateInfo.memoryTypeIndex, vkResource, cellCnt, outIdx, &memBuf) do log.panic("vk_mem_buffer_BindBufferNode\n")
		non_zero_append(&gVkMemBufs, memBuf)
		gVkMemIdxCnts[memBuf.allocateInfo.memoryTypeIndex] += 1
	}
	return
}

vk_mem_buffer_CreateFromResourceSingle :: proc(vkResource: $T) -> (memBuf: ^vk_mem_buffer) where T == vk.Buffer || T == vk.Image {
	memBuf = nil
	memRequire: vk.MemoryRequirements

	when T == vk.Buffer {
		vk.GetBufferMemoryRequirements(vk_device, vkResource, &memRequire)
	} else when T == vk.Image {
		vk.GetImageMemoryRequirements(vk_device, vkResource, &memRequire)
	}

	memBuf = new(vk_mem_buffer, gVkMemTlsfAllocator)
	outMemBuf := vk_mem_buffer_InitSingle(memRequire.size, memRequire.memoryTypeBits)
	memBuf^ = outMemBuf.?

	vk_mem_buffer_BindBufferNode(memBuf, vkResource, 1) //can't (must no) error

	non_zero_append(&gVkMemBufs, memBuf)
	return
}


// ============================================================================
// Memory Buffer - Mapping Operations
// ============================================================================

// not mul cellsize
vk_mem_buffer_Map :: #force_inline proc "contextless" (
	self: ^vk_mem_buffer,
	start: vk.DeviceSize,
	size: vk.DeviceSize,
) -> [^]byte {
	outData: rawptr
	vk.MapMemory(vk_device, self.deviceMem, start, size, {}, &outData)
	return auto_cast outData
}

vk_mem_buffer_UnMap :: #force_inline proc "contextless" (self: ^vk_mem_buffer) {
	self.mapSize = 0
	vk.UnmapMemory(vk_device, self.deviceMem)
}

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
			res: ^base_resource = node.(OpMapCopy).p_resource
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
			if res != .SUCCESS do log.panicf("res := vk.InvalidateMappedMemoryRanges(vk_device, offIdx, raw_data(ranges)) : %s\n", res)
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
		if res != .SUCCESS do log.panicf("res := vk.FlushMappedMemoryRanges(vk_device, auto_cast len(ranges), raw_data(ranges)) : %s\n", res)

		delete(ranges)
	}
}


// ============================================================================
// Memory Buffer - Utility
// ============================================================================

vk_mem_buffer_IsEmpty :: proc(self: ^vk_mem_buffer) -> bool {
	return !self.single && ((self.list.head != nil &&
		self.list.head.next == nil &&
		((^vk_mem_buffer_node)(self.list.head)).free) ||
		(self.list.head == nil))
}
