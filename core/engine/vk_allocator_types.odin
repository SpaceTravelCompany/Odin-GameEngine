#+private
package engine

import "base:runtime"
import "core:container/intrusive/list"
import "core:mem"
import "core:mem/virtual"
import "core:sync"
import "core:thread"
import vk "vendor:vulkan"
import "core:mem/tlsf"


// ============================================================================
// Conversion Functions
// ============================================================================

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


// ============================================================================
// Constants
// ============================================================================

vkPoolBlock :: 1024
vkUniformSizeBlock :: 2 * mem.Megabyte
VkMaxMemIdxCnt : int : 4


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
	self: rawptr,
	src: ^buffer_resource,
}

OpReleaseUniform :: struct {
	src: ^buffer_resource,
}

OpDestroyTexture :: struct {
	self: rawptr,
	src: ^texture_resource,
}

Op__UpdateDescriptorSet :: struct {
	set: ^i_descriptor_set,
}

Op__AddResToObj :: struct {
	self: rawptr,
	res: union_resource,
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
	Op__UpdateDescriptorSet,
}


// ============================================================================
// Types - Buffer and Texture Type Union (internal)
// ============================================================================

__buffer_and_texture_type :: union {
	buffer_type,
	texture_type,
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

gDesciptorPools: map[[^]descriptor_pool_size][dynamic]descriptor_pool_mem

gUniforms: [dynamic]vk_uniform_alloc
gTempUniforms: [dynamic]vk_temp_uniform_struct
gNonInsertedUniforms: [dynamic]vk_temp_uniform_struct

gVkMemBufs: [dynamic]^vk_mem_buffer
gVkMemIdxCnts: []int

gVkMemTlsfAllocator: runtime.Allocator
gVkMemTlsf: tlsf.Allocator