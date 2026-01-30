#+private
package engine

import "base:runtime"
import "core:mem"
import vk "vendor:vulkan"
import "core:container/pool"
import "core:log"


// ============================================================================
// Uniform - Bind Uniform Buffer
// ============================================================================

bind_uniform_buffer :: proc(
	self: ^buffer_resource,
	data: []byte,
	allocator: Maybe(runtime.Allocator),
) {
	if gVkMinUniformBufferOffsetAlignment > 0 {
		// Align the length up to the minimum uniform buffer offset alignment requirement
		self.option.size = (self.option.size + gVkMinUniformBufferOffsetAlignment - 1) & ~(gVkMinUniformBufferOffsetAlignment - 1)
	}
	non_zero_append(&gTempUniforms, vk_temp_uniform_struct{uniform = self, data = data, size = self.option.size, allocator = allocator})
}


// ============================================================================
// Uniform - Assign Uniform to Buffer
// ============================================================================

// Assign uniform to a specific buffer
assign_uniform_to_buffer :: proc(
	opExecQueue: ^[dynamic]OpNode,
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
	}, opExecQueue)
}


// ============================================================================
// Uniform - Create New Uniform Buffer
// ============================================================================

// Create new uniform buffer and assign uniforms
create_new_uniform_buffer :: proc(
	opExecQueue: ^[dynamic]OpNode,
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
		uniforms = mem.make_non_zeroed_dynamic_array([dynamic]^buffer_resource, gVkMemTlsfAllocator),
	}

	bufInfo: vk.BufferCreateInfo = {
		sType = vk.StructureType.BUFFER_CREATE_INFO,
		size  = g.max_size,
		usage = {.UNIFORM_BUFFER},
	}
	res := vk.CreateBuffer(vk_device, &bufInfo, nil, &g.buf)
	if res != .SUCCESS do log.panicf("res := vk.CreateBuffer(vk_device, &bufInfo, nil, &g.buf) : %s\n", res)

	g.mem_buffer = vk_mem_buffer_CreateFromResource(g.buf, {.HOST_CACHED, .HOST_VISIBLE}, &g.idx, 0, .UNIFORM)

	off: vk.DeviceSize = 0
	for &t, i in uniforms {
		non_zero_append(&g.uniforms, t.uniform)
		assign_uniform_to_buffer(opExecQueue, &t, g, g_idx, i, off)
		off += t.size
	}
}


// ============================================================================
// Uniform - Execute Release Uniform
// ============================================================================

executeReleaseUniform :: proc(
	opExecQueue: ^[dynamic]OpNode,
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
		pool.put(&gBufferPool, buf)
	}
}
