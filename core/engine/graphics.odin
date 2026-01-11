package engine

import "core:math/linalg"
import "core:mem"
import "base:runtime"
import vk "vendor:vulkan"

base_resource :: struct {
	data: resource_data,
	g_uniform_indices: [4]graphics_size,
	idx: resource_range,  // unused uniform buffer
	mem_buffer: MEM_BUFFER,
}

MEM_BUFFER :: distinct rawptr

buffer_resource :: struct {
	using _: base_resource,
	option: buffer_create_option,
	__resource: vk.Buffer,
}

resource_data :: struct {
	data: []byte,
	allocator: Maybe(runtime.Allocator),
	is_creating_modifing: bool,
}


texture_resource :: struct {
	using _: base_resource,
	img_view: vk.ImageView,
	sampler: vk.Sampler,
	option: texture_create_option,
	__resource: vk.Image,
}

union_resource :: union #no_nil {
	^buffer_resource,
	^texture_resource,
}

buffer_create_option :: struct {
	len: graphics_size,
	type: buffer_type,
	resource_usage: resource_usage,
	single: bool,
	use_gcpu_mem: bool,
}

texture_create_option :: struct {
	len: u32,
	width: u32,
	height: u32,
	type: texture_type,
	texture_usage: texture_usages,
	resource_usage: resource_usage,
	format: texture_fmt,
	samples: u8,
	single: bool,
	use_gcpu_mem: bool,
}

descriptor_pool_size :: struct {
	type: descriptor_type,
	cnt: u32,
}

descriptor_pool_mem :: struct {
	pool: vk.DescriptorPool,
	cnt: u32,
}

graphics_size :: vk.DeviceSize
resource_range :: rawptr



descriptor_set :: struct {
	layout: vk.DescriptorSetLayout,
	/// created inside update_descriptor_sets call
	__set: vk.DescriptorSet,
	size: []descriptor_pool_size,
	bindings: []u32,
	__resources: []union_resource,
}

command_buffer :: struct #packed {
	__handle: vk.CommandBuffer,
}

color_transform :: struct {
	mat: linalg.Matrix,
	mat_uniform: buffer_resource,
	check_init: mem.ICheckInit,
}

texture :: struct {
	texture: texture_resource,
	set: descriptor_set,
	sampler: vk.Sampler,
	check_init: mem.ICheckInit,
}

object_pipeline :: struct {
    check_init: mem.ICheckInit,

    __pipeline:vk.Pipeline,
    __pipeline_layout:vk.PipelineLayout,
    __descriptor_set_layouts:[]vk.DescriptorSetLayout,
    __pool_binding:[][]u32,//! auto generate inside, uses engine_def_allocator

    draw_method:object_draw_method,
    pool_sizes:[][]descriptor_pool_size,
}

object_draw_type :: enum {
    Draw,
    DrawIndexed,
}

object_draw_method :: struct {
    type:object_draw_type,
    vertex_count:u32,
    instance_count:u32,
    index_count:u32,
    using _:struct #raw_union {
        first_vertex:u32,
        vertex_offset:i32,
    },
    first_instance:u32,
    first_index:u32,
}

resource_usage :: enum {
	GPU,
	CPU,
}

texture_type :: enum {
	TEX2D,
	// TEX3D,
}

texture_usage :: enum {
	IMAGE_RESOURCE,
	FRAME_BUFFER,
	__INPUT_ATTACHMENT,
	__TRANSIENT_ATTACHMENT,
	__STORAGE_IMAGE,
}
texture_usages :: bit_set[texture_usage]

texture_fmt :: enum {
	DefaultColor,
	DefaultDepth,
	R8G8B8A8Unorm,
	B8G8R8A8Unorm,
	// B8G8R8A8Srgb,
	// R8G8B8A8Srgb,
	D24UnormS8Uint,
	D32SfloatS8Uint,
	D16UnormS8Uint,
	R8Unorm,
}

buffer_type :: enum {
	VERTEX,
	INDEX,
	UNIFORM,
	STORAGE,
	__STAGING,
}

descriptor_type :: enum {
	SAMPLER,  // vk.DescriptorType.COMBINED_IMAGE_SAMPLER
	UNIFORM_DYNAMIC,  // vk.DescriptorType.UNIFORM_BUFFER_DYNAMIC
	UNIFORM,  // vk.DescriptorType.UNIFORM_BUFFER
	STORAGE,
	STORAGE_IMAGE,  // TODO (xfitgd)
}

