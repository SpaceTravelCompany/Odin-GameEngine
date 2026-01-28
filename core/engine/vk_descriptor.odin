#+private
package engine

import "core:mem"
import "core:log"
import vk "vendor:vulkan"
import "base:runtime"


// ============================================================================
// Descriptor - Public API
// ============================================================================

vk_update_descriptor_sets :: proc(sets: []descriptor_set) {
	append_op(Op__Updatedescriptor_sets{sets = sets})
}


// ============================================================================
// Descriptor - Create Descriptor Pool
// ============================================================================

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
	if res != .SUCCESS do log.panicf("res := vk.CreateDescriptorPool(vk_device, &poolInfo, nil, &out.pool) : %s\n", res)
}


// ============================================================================
// Descriptor - Execute Update Descriptor Sets
// ============================================================================

execute_update_descriptor_sets :: proc(sets: []descriptor_set, update_list: ^[dynamic]vk.WriteDescriptorSet, arena: runtime.Allocator) {
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
			if res != .SUCCESS do log.panicf("res := vk.AllocateDescriptorSets(vk_device, &allocInfo, &s.__set) : %s\n", res)
		}

		cnt: u32 = 0
		bufCnt: u32 = 0
		texCnt: u32 = 0

		//sets[i].__resources array must match v.size configuration.
		for s in s.size {
			cnt += s.cnt
		}

		for r in s.__resources[0:cnt] {
			switch rr in r {
			case ^buffer_resource:
				bufCnt += 1
			case ^texture_resource:
				texCnt += 1
			}
		}

		bufs := mem.make_non_zeroed([]vk.DescriptorBufferInfo, bufCnt, arena)
		texs := mem.make_non_zeroed([]vk.DescriptorImageInfo, texCnt, arena)
		bufCnt = 0
		texCnt = 0

		for r in s.__resources[0:cnt] {
			switch rr in r {
			case ^buffer_resource:
				bufs[bufCnt] = vk.DescriptorBufferInfo {
					buffer = rr.__resource,
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
		for n, i in s.size {
			switch n.type {
			case .SAMPLER, .STORAGE_IMAGE:
				non_zero_append(update_list, vk.WriteDescriptorSet {
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
				non_zero_append(update_list, vk.WriteDescriptorSet {
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
