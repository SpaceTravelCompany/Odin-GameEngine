#+private
package engine

import "core:mem"
import "core:log"
import vk "vendor:vulkan"
import "base:runtime"
import "base:intrinsics"
import "core:sync"


@(private="file") vk_allocation_callback :: proc "system" (pUserData: rawptr, size: int, alignment: int, allocationScope: vk.SystemAllocationScope) -> rawptr {
	context = runtime.Context{
		allocator = gVkPoolTlsfAllocator,
	}
	res, err := mem.alloc(size, alignment, context.allocator)
	if err != .None {
		return nil
	}
	return res
}

@(private="file") vk_reallocation_callback :: proc "system" (pUserData: rawptr, pOriginal: rawptr, size: int, alignment: int, allocationScope: vk.SystemAllocationScope) -> rawptr {
	// context = runtime.Context{
	// 	allocator = gVkPoolTlsfAllocator,
	// }
	// res, err := mem.resize(mem.ptr_offset((^int)(pOriginal), -1), ((^int)(pOriginal))^, size + size_of(int), alignment, context.allocator)
	// if err != .None {
	// 	return nil
	// }
	// ((^int)(res))^ = size + size_of(int)
	// return mem.ptr_offset((^int)(res), 1)
	intrinsics.trap()//never execute now. why exists?
}

@(private="file") vk_free_callback :: proc "system" (pUserData: rawptr, pMemory: rawptr) {
	context = runtime.Context{
		allocator = gVkPoolTlsfAllocator,
	}

	free(pMemory, context.allocator)
}

@(private="file") gVkPoolAllocationCallbacks: vk.AllocationCallbacks = {
	pUserData = nil,
	pfnAllocation = vk_allocation_callback,
	pfnReallocation = vk_reallocation_callback,
	pfnFree = vk_free_callback,
	pfnInternalAllocation = nil,
	pfnInternalFree = nil,
}


descriptor_pool_mem :: struct {
	vk_pools:   [dynamic]vk.DescriptorPool,
	sets:[]vk.DescriptorSet,
	free_stack: []u32, // O(1) "get one free" — indices of false slots
	free_stack_len: u32,
	layout: vk.DescriptorSetLayout,
}


// Free-stack: O(1) get one free pool index. Call descriptor_pool_mem_init_free_stack after pools/vk_pools are set up (or grown).
descriptor_pool_mem_init :: proc(d: ^descriptor_pool_mem, layout: vk.DescriptorSetLayout) {
	d.free_stack = mem.make_non_zeroed([]u32, vkPoolBlock, gVkPoolTlsfAllocator)
	for i:u32 = 0; i < u32(len(d.free_stack)); i += 1 {
		d.free_stack[i] = u32(i)
	}
	d.free_stack_len = u32(len(d.free_stack))
	d.vk_pools = mem.make_non_zeroed([dynamic]vk.DescriptorPool, gVkPoolTlsfAllocator)
	d.sets = mem.make_non_zeroed([]vk.DescriptorSet, vkPoolBlock, gVkPoolTlsfAllocator)
	d.layout = layout
}
descriptor_pool_mem_get_free :: proc "contextless" (d: ^descriptor_pool_mem) -> (index: u32, ok: bool) {
	if d.free_stack_len == 0 do return 0, false
	index = d.free_stack[d.free_stack_len - 1]
	d.free_stack_len -= 1
	return index, true
}
//call if descriptor_pool_mem_get_free failed(full free_stack)
descriptor_pool_mem_add_block :: proc (d: ^descriptor_pool_mem, size: []descriptor_pool_size) {
	old_len :u32 = u32(len(d.free_stack))
	d.free_stack = mem.resize_non_zeroed_slice(d.free_stack,
	old_len + vkPoolBlock, gVkPoolTlsfAllocator)
	d.sets = mem.resize_non_zeroed_slice(d.sets,
	old_len + vkPoolBlock, gVkPoolTlsfAllocator)
	for i:u32 = old_len; i < old_len + vkPoolBlock; i += 1 {
		d.free_stack[d.free_stack_len] = u32(i)
		d.free_stack_len += 1
	}
	__create_descriptor_pool(size, d)
}
descriptor_pool_mem_release :: proc "contextless" (d: ^descriptor_pool_mem, index: u32) {
	assert_contextless(index >= 0 && index < u32(len(d.free_stack)))
	d.free_stack[d.free_stack_len] = index
	d.free_stack_len += 1
}

descriptor_pool_mem_destroy_all :: proc () {
	sync.mutex_lock(&gDesciptorPoolsMtx)
	defer sync.mutex_unlock(&gDesciptorPoolsMtx)

	for _, d in gDesciptorPools {
		for i in 0..<len(d.vk_pools) {
			vk.DestroyDescriptorPool(vk_device, d.vk_pools[i], &gVkPoolAllocationCallbacks)
		}
		delete(d.vk_pools)
		delete(d.sets, gVkPoolTlsfAllocator)
		delete(d.free_stack, gVkPoolTlsfAllocator)
	}
}

gDesciptorPools: map[vk.DescriptorSetLayout]descriptor_pool_mem
gTmpDesciptorPoolSizes: [dynamic]vk.DescriptorPoolSize
gTmpDesciptorSetLayouts: [dynamic]vk.DescriptorSetLayout



__create_descriptor_pool :: proc(size: []descriptor_pool_size, out: ^descriptor_pool_mem) {
	resize(&gTmpDesciptorPoolSizes, len(size))
	for _, i in size {
		gTmpDesciptorPoolSizes[i].descriptorCount = size[i].cnt * vkPoolBlock
		gTmpDesciptorPoolSizes[i].type = descriptor_type_to_vk_descriptor_type(size[i].type)
	}
	poolInfo := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		poolSizeCount = auto_cast len(gTmpDesciptorPoolSizes),
		pPoolSizes    = raw_data(gTmpDesciptorPoolSizes),
		maxSets       = vkPoolBlock,
	}
	resize(&out.vk_pools, len(out.vk_pools) + 1)
	res := vk.CreateDescriptorPool(vk_device, &poolInfo, &gVkPoolAllocationCallbacks, &out.vk_pools[len(out.vk_pools) - 1])
	if res != .SUCCESS do log.panicf("res := vk.CreateDescriptorPool(vk_device, &poolInfo, nil, &out.vk_pools[len(out.vk_pools) - 1]) : %s\n", res)

	resize(&gTmpDesciptorSetLayouts, vkPoolBlock)
	for i in 0..<vkPoolBlock {
		gTmpDesciptorSetLayouts[i] = out.layout
	}
	allocInfo := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = out.vk_pools[len(out.vk_pools) - 1],
		descriptorSetCount = vkPoolBlock,
		pSetLayouts        = &gTmpDesciptorSetLayouts[0],
	}
	res = vk.AllocateDescriptorSets(vk_device, &allocInfo, &out.sets[u32(len(out.vk_pools) - 1) * vkPoolBlock])
	if res != .SUCCESS do log.panicf("res := vk.AllocateDescriptorSets(vk_device, &allocInfo, &out.sets[u32(len(out.vk_pools) - 1) * vkPoolBlock]) : %s\n", res)
}

@(private="file") gDesciptorPoolsMtx: sync.Mutex

add_descriptor_set :: proc(size: []descriptor_pool_size, layout: vk.DescriptorSetLayout) -> (set:vk.DescriptorSet, idx: u32) {
	tmp : ^descriptor_pool_mem
	sync.mutex_lock(&gDesciptorPoolsMtx)
	defer sync.mutex_unlock(&gDesciptorPoolsMtx)

	if layout in gDesciptorPools {
		tmp = &gDesciptorPools[layout]
	} else {
		tmp = map_insert(&gDesciptorPools, layout, descriptor_pool_mem{})
		descriptor_pool_mem_init(tmp, layout)
		__create_descriptor_pool(size, tmp)
	}

	last, ok := descriptor_pool_mem_get_free(tmp)
	if !ok {
		descriptor_pool_mem_add_block(tmp, size)
		last, _ =  descriptor_pool_mem_get_free(tmp)
	}
	return tmp.sets[last], last
}

del_descriptor_set :: proc(idx: u32, layout: vk.DescriptorSetLayout) {
	sync.mutex_lock(&gDesciptorPoolsMtx)
	defer sync.mutex_unlock(&gDesciptorPoolsMtx)
	descriptor_pool_mem_release(&gDesciptorPools[layout], idx)
}


vk_execute_update_descriptor_set :: proc(set: vk.DescriptorSet, 
	size: []descriptor_pool_size,
	resources: []punion_resource) -> runtime.Allocator_Error {

	cnt: u32 = 0
	bufCnt: u32 = 0
	texCnt: u32 = 0

	//sets[i].__resources array must match v.size configuration.
	for ss in size {
		cnt += ss.cnt
	}

	assert(len(resources) >= int(cnt))
	for r in resources[0:cnt] {
		switch rr in r {
		case ^buffer_resource:
			bufCnt += 1
		case ^texture_resource:
			texCnt += 1
		}
	}

	update_list := mem.make_non_zeroed([dynamic]vk.WriteDescriptorSet, context.temp_allocator) or_return
	defer delete(update_list)
	bufs := mem.make_non_zeroed([]vk.DescriptorBufferInfo, bufCnt, context.temp_allocator) or_return
	defer delete(bufs, context.temp_allocator)
	texs := mem.make_non_zeroed([]vk.DescriptorImageInfo, texCnt, context.temp_allocator) or_return
	defer delete(texs, context.temp_allocator)

	bufCnt = 0
	texCnt = 0

	for r in resources[0:cnt] {
		switch rr in r {
		case ^buffer_resource:
			bufs[bufCnt] = vk.DescriptorBufferInfo {
				buffer = rr.__resource.vk_buffer,
				offset = rr.g_uniform_indices[2],
				range  = rr.option.size,
			}
			bufCnt += 1
		case ^texture_resource:
			texs[texCnt] = vk.DescriptorImageInfo {
				imageLayout = .SHADER_READ_ONLY_OPTIMAL,
				imageView   = rr.img_view,
				sampler     = rr.sampler,
			}
			texCnt += 1
		}
	}

	bufCnt = 0
	texCnt = 0
	for ss in size {
		switch ss.type {
		case .SAMPLER, .STORAGE_IMAGE:
			non_zero_append(&update_list, vk.WriteDescriptorSet {
				dstSet          = set,
				dstBinding      = ss.binding,
				dstArrayElement = 0,
				descriptorCount = ss.cnt,
				descriptorType  = descriptor_type_to_vk_descriptor_type(ss.type),
				pBufferInfo     = nil,
				pImageInfo      = &texs[texCnt],
				pTexelBufferView = nil,
				sType           = .WRITE_DESCRIPTOR_SET,
				pNext           = nil,
			})
			texCnt += ss.cnt
		case .UNIFORM, .STORAGE, .UNIFORM_DYNAMIC:
			non_zero_append(&update_list, vk.WriteDescriptorSet {
				dstSet          = set,
				dstBinding      = ss.binding,
				dstArrayElement = 0,
				descriptorCount = ss.cnt,
				descriptorType  = descriptor_type_to_vk_descriptor_type(ss.type),
				pBufferInfo     = &bufs[bufCnt],
				pImageInfo      = nil,
				pTexelBufferView = nil,
				sType           = .WRITE_DESCRIPTOR_SET,
				pNext           = nil,
			})
			bufCnt += ss.cnt
		}
	}
	vk.UpdateDescriptorSets(graphics_device(), auto_cast len(update_list), raw_data(update_list), 0, nil)
	return nil
}
