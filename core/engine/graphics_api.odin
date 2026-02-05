package engine

import "core:unicode/utf8/utf8string"
import "base:intrinsics"
import "base:library"
import "base:runtime"
import "core:strings"
import "core:math/linalg"
import "core:mem"
import "core:c"
import "core:sync"
import "vendor:glslang"
import "core:container/pool"
import "core:log"
import "core:mem/tlsf"
import "vendor:wasm/WebGL"
import "vendor:OpenGL"
import "vendor:wgpu"
import "core:thread"
import img "core:image"
import "core:container/intrusive/list"

import vk "vendor:vulkan"

msaa_count :: #config(MSAA_COUNT, 1)
MAX_FRAMES_IN_FLIGHT :: #config(MAX_FRAMES_IN_FLIGHT, 2)

@private swap_img_cnt : u32 = 3

graphics_device :: #force_inline proc "contextless" () -> vk.Device {
	return vk_device
}

// Graphics State
@private g_clear_color: [4]f32 = {0.0, 0.0, 0.0, 1.0}
@private rotation_matrix: linalg.matrix44
@private depth_fmt: texture_fmt



// Pipelines
@private screen_copy_pipeline: object_pipeline

// Descriptor Set Layouts
@private __base_descriptor_set_layout: vk.DescriptorSetLayout
@private __copy_screen_descriptor_set_layout: vk.DescriptorSetLayout

// Samplers
@private linear_sampler: vk.Sampler
@private nearest_sampler: vk.Sampler

// Default Color Transform
@private __def_color_transform: color_transform

punion_resource :: union {
	^buffer_resource,
	^texture_resource,
}

base_resource :: struct {
	g_uniform_indices: [4]graphics_size,
	idx: resource_range,  // unused uniform buffer
	mem_buffer: MEM_BUFFER,
	completed: bool,
}

MEM_BUFFER :: distinct rawptr

__graphics_api_buffer :: struct #raw_union {
	vk_buffer: vk.Buffer,
	opengl_buffer: u32,
	webgl_buffer: WebGL.Buffer,
}

__graphics_api_image :: struct #raw_union {
	vk_image: vk.Image,
	opengl_image: u32,
	webgl_image: WebGL.Texture,
}


buffer_resource :: struct {
	using _: base_resource,
	self:^buffer_resource,
	option: buffer_create_option,
	__resource: __graphics_api_buffer,
}

texture_resource :: struct {
	using _: base_resource,
	self:^texture_resource,
	img_view: vk.ImageView,
	sampler: vk.Sampler,
	option: texture_create_option,
	__resource: __graphics_api_image,
}

buffer_create_option :: struct {
	size: graphics_size,
	type: buffer_type,
	resource_usage: resource_usage,
	single: bool,
	use_gcpu_mem: bool,
}

texture_type :: enum {
	TEX2D,
	// TEX3D, //TODO
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
	binding: u32,
}


graphics_size :: vk.DeviceSize
resource_range :: rawptr


object_pipeline :: struct {
    __pipeline:vk.Pipeline,
    __pipeline_layout:vk.PipelineLayout,
    __descriptor_set_layouts:[]vk.DescriptorSetLayout,

    draw_method:object_draw_method,
	allocator: runtime.Allocator,
}

compute_pipeline :: struct {
	__pipeline:vk.Pipeline,
    __pipeline_layout:vk.PipelineLayout,
    __descriptor_set_layouts:[]vk.DescriptorSetLayout,
	allocator: runtime.Allocator,
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


VULKAN_VERSION :: struct {
	major, minor, patch:u32
}

get_vulkan_version :: proc "contextless" () -> VULKAN_VERSION {
	return vulkan_version
}

command_buffer :: struct #packed {
	__handle: vk.CommandBuffer,
}

color_transform :: struct {
	mat: linalg.matrix44,
	mat_idx:Maybe(u32),
}

resource_usage :: enum {
	GPU,
	CPU,
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
	STORAGE_IMAGE,
}


def_color_transform :: #force_inline proc "contextless" () -> ^color_transform {
	return &__def_color_transform
}

get_screen_copy_pipeline :: #force_inline proc "contextless" () -> ^object_pipeline {
	return &screen_copy_pipeline
}
base_descriptor_set_layout :: #force_inline proc "contextless" () -> vk.DescriptorSetLayout {
	return __base_descriptor_set_layout
}

get_linear_sampler :: proc "contextless" () -> vk.Sampler {
	return linear_sampler
}
get_nearest_sampler :: proc "contextless" () -> vk.Sampler {	
	return nearest_sampler
}


@private graphics_init :: proc() {
	when is_web {
		webgl_start()
	} else {
		if !vk_start() {
			//TODO start OpenGL
			log.panic("Failed to initialize Vulkan\n")
		}
	}

}

@private graphics_destroy :: proc() {
	when is_web {
		webgl_destroy()
	} else {
		if vulkan_version.major > 0 {
			vk_destroy()
		} else {
			//TODO Destroy OpenGL
		}
	}
}

@private graphics_draw_frame :: proc() {
	when is_web {
		webgl_draw_frame()
	} else {
		if vulkan_version.major > 0 {
			vk_draw_frame()
		} else {
		}
	}
}

@private graphics_wait_device_idle :: proc () {
	when is_web {
		WebGL.Finish()
	} else {
		if vulkan_version.major > 0 {
			vk_wait_device_idle()
		} else {
			OpenGL.Finish()
		}
	}
}

@private graphics_wait_graphics_idle :: proc () {
	when is_web {
		WebGL.Finish()
	} else {
		if vulkan_version.major > 0 {
			vk_wait_graphics_idle()
		} else {
			OpenGL.Finish()
		}
	}
}

@private graphics_wait_present_idle :: proc () {
	vk_wait_present_idle()
}

@private graphics_execute_ops :: proc() {
	when is_web {
	} else {
		if vulkan_version.major > 0 {
			vk_op_execute()
		}
	}
}

allocate_command_buffers :: proc(p_cmd_buffer: [^]command_buffer, count: u32, cmd_pool: vk.CommandPool) {
	when is_web {
	} else {
		if vulkan_version.major > 0 {
			alloc_info := vk.CommandBufferAllocateInfo{
				sType = vk.StructureType.COMMAND_BUFFER_ALLOCATE_INFO,
				commandPool = cmd_pool,
				level = vk.CommandBufferLevel.SECONDARY,
				commandBufferCount = count,
			}
			res := vk.AllocateCommandBuffers(graphics_device(), &alloc_info, ([^]vk.CommandBuffer)(p_cmd_buffer))
			if res != .SUCCESS do log.panicf("res = vk.AllocateCommandBuffers(graphics_device(), &alloc_info, &cmd.cmds[i][0]) : %s\n", res)
		} else {
		}
	}
}

free_command_buffers :: proc(p_cmd_buffer: [^]command_buffer, count: u32, cmd_pool: vk.CommandPool) {
	when is_web {
	} else {
		if vulkan_version.major > 0 {
			vk.FreeCommandBuffers(graphics_device(), cmd_pool, count, auto_cast p_cmd_buffer)
		} else {
		}
	}
}

graphics_cmd_bind_pipeline :: #force_inline proc "contextless" (cmd: command_buffer, pipeline_bind_point: vk.PipelineBindPoint, pipeline: vk.Pipeline) {
	when is_web {
	} else {
		if vulkan_version.major > 0 {
			vk.CmdBindPipeline(cmd.__handle, pipeline_bind_point, pipeline)
		} else {
		}
	}
}

graphics_cmd_bind_descriptor_sets :: #force_inline proc "contextless" (
	cmd: command_buffer,
	pipeline_bind_point: vk.PipelineBindPoint,
	layout: vk.PipelineLayout,
	first_set: u32,
	descriptor_set_count: u32,
	p_descriptor_sets: ^vk.DescriptorSet,
	dynamic_offset_count: u32,
	p_dynamic_offsets: ^u32,
) {
	when is_web {
	} else {
		if vulkan_version.major > 0 {
			vk.CmdBindDescriptorSets(cmd.__handle, pipeline_bind_point, layout, first_set, descriptor_set_count, p_descriptor_sets, dynamic_offset_count, p_dynamic_offsets)
		} else {
		}
	}
}

graphics_cmd_dispatch :: proc "contextless" (cmd: command_buffer, group_count_x: u32, group_count_y: u32, group_count_z: u32) {
	when is_web {
	} else {
		if vulkan_version.major > 0 {
			vk.CmdDispatch(cmd.__handle, group_count_x, group_count_y, group_count_z)
		}
	}
}

graphics_cmd_bind_vertex_buffers :: proc (
	cmd: command_buffer,
	first_binding: u32,
	binding_count: u32,
	p_buffers: []^buffer_resource,
	p_offsets: ^vk.DeviceSize,
	gl_vertex_array: GL_VertexArrayObject = 0,
) {
	when is_web {
		WebGL.BindVertexArray((WebGL.VertexArrayObject)(gl_vertex_array))
	} else {
		if vulkan_version.major > 0 {
			buffers: []vk.Buffer = mem.make_non_zeroed([]vk.Buffer, len(p_buffers), context.temp_allocator)
			defer delete(buffers, context.temp_allocator)
			for b, i in p_buffers {
				buffers[i] = b.__resource.vk_buffer
			}
			vk.CmdBindVertexBuffers(cmd.__handle, first_binding, binding_count, &buffers[0], p_offsets)
		} else {
			OpenGL.BindVertexArray(gl_vertex_array)
		}
	}

}


graphics_cmd_bind_index_buffer :: proc "contextless" (
	cmd: command_buffer,
	buffer: ^buffer_resource,
	offset: vk.DeviceSize,
	index_type: vk.IndexType,
) {
	when is_web {
		//HANDLES BY VERTEX ARRAY OBJECT
	} else {
		if vulkan_version.major > 0 {
			vk.CmdBindIndexBuffer(cmd.__handle, buffer.__resource.vk_buffer, offset, index_type)
		} else {
			//HANDLES BY VERTEX ARRAY OBJECT
		}
	}
}


graphics_cmd_draw :: proc "contextless" (
	cmd: command_buffer,
	vertex_count: u32,
	instance_count: u32,
	first_vertex: u32,
	first_instance: u32,
) {
	when is_web {
		WebGL.DrawArrays(WebGL.TRIANGLES, auto_cast first_vertex, auto_cast vertex_count)
	} else {
		if vulkan_version.major > 0 {
			vk.CmdDraw(cmd.__handle, vertex_count, instance_count, first_vertex, first_instance)
		} else {
			OpenGL.DrawArrays(OpenGL.TRIANGLES, auto_cast first_vertex, auto_cast vertex_count)
		}
	}
}

graphics_cmd_draw_indexed :: proc "contextless" (
	cmd: command_buffer,
	index_count: u32,
	instance_count: u32,
	first_index: u32,
	vertex_offset: i32,
	first_instance: u32,
) {
	when is_web {
		WebGL.DrawElements(WebGL.TRIANGLES, auto_cast index_count, WebGL.UNSIGNED_INT, nil)
	} else {
		if vulkan_version.major > 0 {
			vk.CmdDrawIndexed(cmd.__handle, index_count, instance_count, first_index, vertex_offset, first_instance)
		} else {
			OpenGL.DrawElements(OpenGL.TRIANGLES, auto_cast index_count, OpenGL.UNSIGNED_INT, nil)
		}
	}
}

buffer_resource_create_buffer :: proc(
	idx: Maybe(u32),
	option: buffer_create_option,
	data: []byte,
	is_copy: bool = false,
	allocator: Maybe(runtime.Allocator) = nil,
) -> (^buffer_resource, u32) {
	out_res, ridx := graphics_add_resource_buffer(idx)
	out_res.(^buffer_resource).option = option

	if is_copy {
		copyData: []byte
		if allocator == nil {
			copyData = mem.make_non_zeroed([]byte, len(data), vk_def_allocator())
		} else {
			copyData = mem.make_non_zeroed([]byte, len(data), allocator.?)
		}
		mem.copy_non_overlapping(raw_data(copyData), raw_data(data), len(data))
		
		append_op(OpCreateBuffer{src = out_res.(^buffer_resource), data = copyData, allocator = (allocator == nil ? vk_def_allocator() : allocator.?)})
	} else {
		append_op(OpCreateBuffer{src = out_res.(^buffer_resource), data = data, allocator = allocator})
	}
	return out_res.(^buffer_resource), ridx
}

buffer_resource_deinit :: proc(idx: u32) {
	base := graphics_get_resource(idx)
	if base == nil do return

	switch b in base {
	case ^buffer_resource:
		if b.option.type == .UNIFORM {
			graphics_pop_resource(idx, base)
			append_op(OpReleaseUniform{src = b})
		} else {
			append_op(OpDestroyBuffer{idx = idx, src = b})// 나중에 지운다.
		}
	case ^texture_resource:
		if b.mem_buffer == nil {
			graphics_pop_resource(idx, base)
			vk.DestroyImageView(vk_device, b.img_view, nil)
		} else {
			append_op(OpDestroyTexture{idx = idx, src = b})// 나중에 지운다.
		}
	}
}

buffer_resource_copy_update :: proc(idx: u32, data: $T, allocator: Maybe(runtime.Allocator) = nil)
where intrinsics.type_is_slice(T) || intrinsics.type_is_pointer(T) {
	base := graphics_get_resource(idx)
	if base == nil do return

	copyData: []byte
	bytes:[]byte
	when intrinsics.type_is_slice(T) {
		bytes = mem.slice_to_bytes(data)
	} else when intrinsics.type_is_pointer(T) {
		bytes = mem.ptr_to_bytes(data)
	} else {
		#panic("buffer_resource_copy_update: unsupported type")
	}

	if allocator == nil {
		copyData = mem.make_non_zeroed([]byte, len(bytes), vk_def_allocator())
	} else {
		copyData = mem.make_non_zeroed([]byte, len(bytes), allocator.?)
	}
	intrinsics.mem_copy_non_overlapping(raw_data(copyData), raw_data(bytes), len(bytes))
	
	switch b in base {
	case ^buffer_resource:
		buffer_resource_MapCopy(b, copyData, (allocator == nil ? vk_def_allocator() : allocator.?) )
	case ^texture_resource:
		buffer_resource_MapCopy(b, copyData, (allocator == nil ? vk_def_allocator() : allocator.?) )
	}
}

buffer_resource_map_update_slice :: proc(idx: u32, array: $T/[]$E, allocator: Maybe(runtime.Allocator) = nil) {
	_data := mem.slice_to_bytes(array)
	base := graphics_get_resource(idx)
	if base == nil do return
	switch b in base {
	case ^buffer_resource:
		buffer_resource_MapCopy(b, _data, allocator)
	case ^texture_resource:
		buffer_resource_MapCopy(b, _data, allocator)
	}
}

buffer_resource_create_texture :: proc(
	idx: Maybe(u32),
	option: texture_create_option,
	sampler: vk.Sampler,
	data: []byte,
	is_copy: bool = false,
	allocator: Maybe(runtime.Allocator) = nil,
) -> (^texture_resource, u32) {
	out_res, ridx := graphics_add_resource_texture(idx)
	out_res.(^texture_resource).sampler = sampler
	out_res.(^texture_resource).option = option

	if is_copy {
		copyData: []byte
		if allocator == nil {
			copyData = mem.make_non_zeroed([]byte, len(data), vk_def_allocator())
		} else {
			copyData = mem.make_non_zeroed([]byte, len(data), allocator.?)
		}
		mem.copy_non_overlapping(raw_data(copyData), raw_data(data), len(data))
		append_op(OpCreateTexture{src = out_res.(^texture_resource), data = copyData, allocator = (allocator == nil ? vk_def_allocator() : allocator.?)})
	} else {
		append_op(OpCreateTexture{src = out_res.(^texture_resource), data = data, allocator = allocator})
	}
	return out_res.(^texture_resource), ridx
}

update_descriptor_set :: proc(set: vk.DescriptorSet, size: []descriptor_pool_size, resources: []punion_resource) {
	when !is_web {
		if vulkan_version.major > 0 {
			vk_execute_update_descriptor_set(set, size, resources)
		}
	} else {
		set := set;size := size;resources := resources
	}
}

//get a descriptor set from the descriptor pool
get_descriptor_set :: proc(size: []descriptor_pool_size, layout: vk.DescriptorSetLayout) -> (set:vk.DescriptorSet, idx: u32) {
	when !is_web {
		if vulkan_version.major > 0 {
			return add_descriptor_set(size, layout)
		}
	} else {
		size := size;layout := layout
	}
	return 0, 0
}
//put a descriptor set back to the descriptor pool
put_descriptor_set :: proc(idx: u32, layout: vk.DescriptorSetLayout) {
	when !is_web {
		if vulkan_version.major > 0 {
			del_descriptor_set(idx, layout)
		}
	} else {
		idx := idx;layout := layout
	}
}

color_transform_init_matrix_raw :: proc(self: ^color_transform, mat: linalg.matrix44 = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1}) {
	self.mat = mat
	__color_transform_init(self)
}

@private __color_transform_init :: proc(self: ^color_transform) {
	_, self.mat_idx = buffer_resource_create_buffer(self.mat_idx, {
		size = size_of(linalg.matrix44),
		type = .UNIFORM,
		resource_usage = .CPU,
	}, mem.ptr_to_bytes(&self.mat), true)
}

/*
Deinitializes and cleans up color transform resources

Inputs:
- self: Pointer to the color transform to deinitialize

Returns:
- None
*/
color_transform_deinit :: proc(self: ^color_transform) {
	if self.mat_idx != nil do buffer_resource_deinit(self.mat_idx.?)
}

/*
Updates the color transform with a raw matrix

Inputs:
- self: Pointer to the color transform to update
- _mat: The new color transform matrix

Returns:
- None
*/
color_transform_update_matrix_raw :: proc(self: ^color_transform, _mat: linalg.matrix44) {
	self.mat = _mat
	// Get resource from gMapResource
	buffer_resource_copy_update(self,&self.mat)
}

@private graphics_create :: proc() {
	color_transform_init_matrix_raw(&__def_color_transform)
}

@private graphics_clean :: proc() {
	color_transform_deinit(&__def_color_transform)
}


/*
Gets the graphics origin format

Returns:
- The Vulkan format used as the graphics origin format
*/
get_graphics_origin_format :: proc "contextless" () -> vk.Format {
	return vk_fmt.format
}

default_render_pass :: proc "contextless" () -> vk.RenderPass {
	return vk_render_pass
}

default_multisample_state :: proc "contextless" () -> ^vk.PipelineMultisampleStateCreateInfo {
	return &vkPipelineMultisampleStateCreateInfo
}


@(private) graphics_recreate_swapchain :: proc() {vk_recreate_swap_chain()}
@(private) graphics_recreate_surface :: proc() {vk_recreate_surface()}
@(private) graphics_allocator_init :: proc() {vk_allocator_init()}
@(private) graphics_allocator_destroy :: proc() {vk_allocator_destroy()}

@(private) refresh_pre_matrix :: proc() {
	if library.is_mobile {
		orientation := __screen_orientation
		if orientation == .Landscape90 {
			rotation_matrix = linalg.matrix4_rotate_f32(linalg.to_radians(f32(90.0)), {0, 0, 1})
		} else if orientation == .Landscape270 {
			rotation_matrix = linalg.matrix4_rotate_f32(linalg.to_radians(f32(270.0)), {0, 0, 1})
		} else if orientation == .Vertical180 {
			rotation_matrix = linalg.matrix4_rotate_f32(linalg.to_radians(f32(180.0)), {0, 0, 1})
		} else if orientation == .Vertical360 {
			rotation_matrix = linalg.identity_matrix(linalg.matrix44)
		} else {
			rotation_matrix = linalg.identity_matrix(linalg.matrix44)
		}
	}
}

descriptor_set_layout_binding :: vk.DescriptorSetLayoutBinding
vertex_input_binding_description :: vk.VertexInputBindingDescription
vertex_input_attribute_description :: vk.VertexInputAttributeDescription

shader_module :: union {
	vk.ShaderModule,
	
}

shader_code ::union {
    []byte,
    string,
}

shader_lang :: enum {
    GLSL,
    HLSL,
}

descriptor_set_layout_binding_init :: vk.DescriptorSetLayoutBindingInit


@(private="file") __shader_inited := false
@(private="file") __shader_mtx:sync.Mutex
@private __shader_init :: proc "contextless" () {
	// glslang 초기화 (한 번만 호출) (프로세스 별로 호출 필요, 스레드 아님)
	if !intrinsics.atomic_load_explicit(&__shader_inited, .Relaxed) {
		sync.mutex_lock(&__shader_mtx)
		defer sync.mutex_unlock(&__shader_mtx)
		if glslang.initialize_process() == 0 {
			panic_contextless("__shader_init: glslang initialization failed")
		}
		intrinsics.atomic_store_explicit(&__shader_inited, true, .Relaxed)
	}
}
@(private, fini) __shader_deinit :: proc "contextless" () {
	if intrinsics.atomic_load_explicit(&__shader_inited, .Relaxed) {
		sync.mutex_lock(&__shader_mtx)
		defer sync.mutex_unlock(&__shader_mtx)
		glslang.finalize_process()
		intrinsics.atomic_store_explicit(&__shader_inited, false, .Relaxed)
	}
}

@private __glslang_compile_shader :: proc(shader_code:string, shader_lang:shader_lang, stage:glslang.Shader_Stage) ->
 (spirv_data:[]u8, program:^glslang.Program, success:bool = true) {
	__shader_init()

	code_str := strings.clone_to_cstring(shader_code, context.temp_allocator)
	defer delete(code_str, context.temp_allocator)

	input := glslang.Input{
		language = shader_lang == .HLSL ? glslang.Source.HLSL : glslang.Source.GLSL,
		stage = stage,
		client = glslang.Client.VULKAN,
		client_version = glslang.Target_Client_Version.VULKAN_1_4,
		target_language = glslang.Target_Language.SPV,
		target_language_version = glslang.Target_Language_Version.SPV_1_6,
		code = code_str,
		default_version = 100,
		default_profile = glslang.Profile.NO_PROFILE,
		force_default_version_and_profile = 0,
		forward_compatible = 0,
		messages = glslang.Messages.DEFAULT_BIT,
		resource = glslang.default_resource(),
		callbacks = {},
		callbacks_ctx = nil,
	}
	ver := get_vulkan_version()
	if ver.major == 1 {
		switch ver.minor {
			case 0:
				input.target_language_version = glslang.Target_Language_Version.SPV_1_0
				input.client_version = glslang.Target_Client_Version.VULKAN_1_0
			case 1:
				input.target_language_version = glslang.Target_Language_Version.SPV_1_3
				input.client_version = glslang.Target_Client_Version.VULKAN_1_1
			case 2:
				input.target_language_version = glslang.Target_Language_Version.SPV_1_5
				input.client_version = glslang.Target_Client_Version.VULKAN_1_2
			case 3:
				input.client_version = glslang.Target_Client_Version.VULKAN_1_3
			case://4 and above
		}
	}
	shader := glslang.shader_create(&input)
	if shader == nil {
		log.error("custom_object_pipeline_init: failed to create shader\n")
		return nil, nil, false
	}
	defer glslang.shader_delete(shader)
	
	glslang.shader_set_entry_point(shader, "main")

	if glslang.shader_preprocess(shader, &input) == 0 {
		info_log := glslang.shader_get_info_log(shader)
		debug_log := glslang.shader_get_info_debug_log(shader)
		if info_log != nil {
			log.error(info_log, "\n")
		}
		if debug_log != nil {
			log.error(debug_log, "\n")
		}
		return nil, nil, false
	}
	
	if glslang.shader_parse(shader, &input) == 0 {
		info_log := glslang.shader_get_info_log(shader)
		debug_log := glslang.shader_get_info_debug_log(shader)
		if info_log != nil {
			log.error(info_log, "\n")
		}
		if debug_log != nil {
			log.error(debug_log, "\n")
		}
		return nil, nil, false
	}
	
	program = glslang.program_create()
	if program == nil {
		log.error("custom_object_pipeline_init: failed to create program\n")
		return nil, nil, false
	}
	glslang.program_add_shader(program, shader)
	
	link_messages := cast(c.int)(glslang.Messages.SPV_RULES_BIT) | cast(c.int)(glslang.Messages.VULKAN_RULES_BIT)
	if glslang.program_link(program, link_messages) == 0 {
		info_log := glslang.program_get_info_log(program)
		debug_log := glslang.program_get_info_debug_log(program)
		if info_log != nil {
			log.error(info_log, "\n")
		}
		if debug_log != nil {
			log.error(debug_log, "\n")
		}
		glslang.program_delete(program)
		return nil, nil, false
	}
	
	spv_options := glslang.SPV_Options{
		generate_debug_info = false,
		strip_debug_info = false,
		disable_optimizer = false,
		optimize_size = false,
		disassemble = false,
		validate = true,
		emit_nonsemantic_shader_debug_info = false,
		emit_nonsemantic_shader_debug_source = false,
		compile_only = false,
		optimize_allow_expanded_id_bound = false,
	}
	when ODIN_DEBUG {
		spv_options.generate_debug_info = true
		spv_options.disable_optimizer = true
		spv_options.emit_nonsemantic_shader_debug_info = true
		spv_options.emit_nonsemantic_shader_debug_source = true
	}
	glslang.program_SPIRV_generate_with_options(program, stage, &spv_options)
	
	spirv_size := glslang.program_SPIRV_get_size(program)
	spirv_data = mem.make_non_zeroed([]u8, size_of(u32) * spirv_size, context.temp_allocator)
	glslang.program_SPIRV_get(program, cast(^c.uint)&spirv_data[0])
	
	spirv_messages := glslang.program_SPIRV_get_messages(program)
	if spirv_messages != nil {log.error(spirv_messages, "\n")}
	return
}

object_pipeline_init :: proc(self:^object_pipeline,
    descriptor_set_layouts:[]vk.DescriptorSetLayout,
    vertex_input_binding:Maybe([]vertex_input_binding_description),
    vertex_input_attribute:Maybe([]vertex_input_attribute_description),
    draw_method:object_draw_method,
    vertex_shader:Maybe(shader_code),
    pixel_shader:Maybe(shader_code),
    geometry_shader:Maybe(shader_code) = nil,
    depth_stencil_state:Maybe(vk.PipelineDepthStencilStateCreateInfo) = nil,
    color_blend_state:Maybe(vk.PipelineColorBlendStateCreateInfo) = nil,
	shader_lang:shader_lang = .GLSL, allocator := context.allocator) -> (success:bool) {

    self.draw_method = draw_method
	self.allocator = allocator

    shaders := [?]Maybe(shader_code){vertex_shader, pixel_shader, geometry_shader}
    shader_kinds := [?]glslang.Shader_Stage{.VERTEX, .FRAGMENT, .GEOMETRY}
    shader_vkflags := [?]vk.ShaderStageFlags{{.VERTEX}, {.FRAGMENT}, {.GEOMETRY}}
    shader_programs : [len(shaders)]^glslang.Program
    shader_modules : [len(shaders)]vk.ShaderModule
    defer {
        for s in shader_modules {
            if s != 0 {
                vk.DestroyShaderModule(graphics_device(), s, nil)
            }
        }
    }

    if vertex_shader == nil || pixel_shader == nil {
        log.panic("custom_object_pipeline_init: vertex_shader and pixel_shader cannot be nil\n")
    }

    
    defer for i in 0..<len(shader_programs) {
        if shader_programs[i] != nil {
            glslang.program_delete(shader_programs[i])
        }
    }
	spirv_data : []u8 = nil
    for i in 0..<len(shaders) {
        shader_bytes:[]byte
        if shaders[i] != nil {
            switch s in shaders[i].? {
                case string:
					success:bool
					spirv_data, shader_programs[i], success = __glslang_compile_shader(s, shader_lang, shader_kinds[i])
					if !success do return false
					shader_bytes = spirv_data
                case []byte:
                    shader_bytes = s
            }
			res: vk.Result
            shader_modules[i], res = vk.CreateShaderModule2(graphics_device(), shader_bytes)
			if res != .SUCCESS {
				log.errorf("custom_object_pipeline_init: CreateShaderModule2 : %s\n", res)
				return false
			} 
			if spirv_data != nil do delete(spirv_data, context.temp_allocator)
			spirv_data = nil
        }
    }
    shaderCreateInfo : [len(shaders)]vk.PipelineShaderStageCreateInfo
    shaderCreateInfoLen :int
    if geometry_shader == nil {
        tmp := vk.CreateShaderStages(shader_modules[0], shader_modules[1])
        shaderCreateInfo = {tmp[0], tmp[1], {}}
        shaderCreateInfoLen = 2
    } else {
        tmp := vk.CreateShaderStagesGS(shader_modules[0], shader_modules[1], shader_modules[2])
        shaderCreateInfo = {tmp[0], tmp[1], tmp[2]}
        shaderCreateInfoLen = 3
    }

    viewportState := vk.PipelineViewportStateCreateInfoInit()

	res: vk.Result
	if descriptor_set_layouts != nil && len(descriptor_set_layouts) > 0 {
    	self.__descriptor_set_layouts = mem.make_non_zeroed_slice([]vk.DescriptorSetLayout, len(descriptor_set_layouts), allocator)
		mem.copy_non_overlapping(&self.__descriptor_set_layouts[0], &descriptor_set_layouts[0], len(descriptor_set_layouts) * size_of(vk.DescriptorSetLayout))
	}
	defer if !success {delete(self.__descriptor_set_layouts, allocator)}

    self.__pipeline_layout, res = vk.PipelineLayoutInit(graphics_device(), self.__descriptor_set_layouts)
	if res != .SUCCESS {
		log.errorf("custom_object_pipeline_init: PipelineLayoutInit : %s\n", res)
		return false
	}
	defer if !success {vk.DestroyPipelineLayout(graphics_device(), self.__pipeline_layout, nil)}

    vertexInputState:Maybe(vk.PipelineVertexInputStateCreateInfo)
    if vertex_input_binding != nil && vertex_input_attribute != nil {
        vertexInputState = vk.PipelineVertexInputStateCreateInfoInit(vertex_input_binding.?, vertex_input_attribute.?)
    } else {
        vertexInputState = nil
    }

    if !create_graphics_pipeline(self,
        shaderCreateInfo[:shaderCreateInfoLen],
        depth_stencil_state == nil ? vk.PipelineDepthStencilStateCreateInfoInit() : depth_stencil_state.?,
        viewportState,
        vertexInputState == nil ? nil : &vertexInputState.?,
		color_blend_state == nil ? vk.DefaultPipelineColorBlendStateCreateInfo : color_blend_state.?) {
        return false
    }
    return true
}

compute_pipeline_init :: proc(self: ^compute_pipeline,
  	compute_shader:shader_code,
	descriptor_set_layouts:[]vk.DescriptorSetLayout,
	shader_lang:shader_lang = .GLSL,
	allocator := context.allocator) -> (success:bool) {
	
	self.allocator = allocator

    shader_kind : glslang.Shader_Stage : .COMPUTE
    shader_vkflag : vk.ShaderStageFlags : {.COMPUTE}
    shader_program : ^glslang.Program
    shader_module : vk.ShaderModule
    defer {
		if shader_module != 0 {
			vk.DestroyShaderModule(graphics_device(), shader_module, nil)
		}
    }
    defer if shader_program != nil {
        glslang.program_delete(shader_program)
    }

	spirv_data : []u8 = nil
    shader_bytes:[]byte
	switch s in compute_shader {
		case string:
			success:bool
			spirv_data, shader_program, success = __glslang_compile_shader(s, shader_lang, shader_kind)
			if !success do return false
			shader_bytes = spirv_data
		case []byte:
			shader_bytes = s
	}
	res: vk.Result
	shader_module, res = vk.CreateShaderModule2(graphics_device(), shader_bytes)
	if res != .SUCCESS {
		log.errorf("custom_object_pipeline_init: CreateShaderModule2 : %s\n", res)
		return false
	} 
	if spirv_data != nil do delete(spirv_data, context.temp_allocator)

	if descriptor_set_layouts != nil && len(descriptor_set_layouts) > 0 {
		self.__descriptor_set_layouts = mem.make_non_zeroed_slice([]vk.DescriptorSetLayout, len(descriptor_set_layouts), allocator)
		mem.copy_non_overlapping(&self.__descriptor_set_layouts[0], &descriptor_set_layouts[0], len(descriptor_set_layouts) * size_of(vk.DescriptorSetLayout))
	}
	defer if !success {delete(self.__descriptor_set_layouts, allocator)}

	self.__pipeline_layout, res = vk.PipelineLayoutInit(graphics_device(), descriptor_set_layouts)
	if res != .SUCCESS {
		log.errorf("compute_pipeline_init: PipelineLayoutInit : %s\n", res)
		return false
	}
	defer if !success {vk.DestroyPipelineLayout(graphics_device(), self.__pipeline_layout, nil)}

	compute_pipeline_create_info := vk.ComputePipelineCreateInfo{
		sType = .COMPUTE_PIPELINE_CREATE_INFO,
		stage = vk.PipelineShaderStageCreateInfo{
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = shader_vkflag,
			module = shader_module,
			pName = "main",
		},
		layout = self.__pipeline_layout,
	}
	res = vk.CreateComputePipelines(graphics_device(), 0, 1, &compute_pipeline_create_info, nil, &self.__pipeline)
	if res != .SUCCESS {
		log.errorf("compute_pipeline_init: CreateComputePipelines : %s\n", res)
		return false
	}
    return true
}

create_graphics_pipeline :: proc(
	self: ^object_pipeline,
	stages: []vk.PipelineShaderStageCreateInfo,
	depth_stencil_state: vk.PipelineDepthStencilStateCreateInfo,
	viewport_state: vk.PipelineViewportStateCreateInfo,
	pVertex_input_state: ^vk.PipelineVertexInputStateCreateInfo,
	color_blend_state: vk.PipelineColorBlendStateCreateInfo,
) -> bool {
	color_blend_state_tmp := color_blend_state
	viewport_state_tmp := viewport_state
	depth_stencil_state_tmp := depth_stencil_state

	pipeline_create_info := vk.GraphicsPipelineCreateInfoInit(
		stages = stages,
		layout = self.__pipeline_layout,
		pDepthStencilState = &depth_stencil_state_tmp,
		pViewportState = &viewport_state_tmp,
		pVertexInputState = pVertex_input_state,
		renderPass = default_render_pass(),
		pMultisampleState = default_multisample_state(),
		pColorBlendState = &color_blend_state_tmp,
	)

	res := vk.CreateGraphicsPipelines(graphics_device(), 0, 1, &pipeline_create_info, nil, &self.__pipeline)
	if res != .SUCCESS {
		log.errorf("create_graphics_pipeline: Failed to create graphics pipeline: %s\n", res)
		return false
	}
	return true
}

object_pipeline_deinit :: proc(self:^object_pipeline) {
	graphics_wait_graphics_idle()
    vk.DestroyPipelineLayout(graphics_device(), self.__pipeline_layout, nil)
    vk.DestroyPipeline(graphics_device(), self.__pipeline, nil)
    if self.__descriptor_set_layouts != nil {
        delete(self.__descriptor_set_layouts, self.allocator)
    }
}

compute_pipeline_deinit :: proc(self:^compute_pipeline) {
	graphics_wait_graphics_idle()
	vk.DestroyPipelineLayout(graphics_device(), self.__pipeline_layout, nil)
	vk.DestroyPipeline(graphics_device(), self.__pipeline, nil)
	if self.__descriptor_set_layouts != nil {
		delete(self.__descriptor_set_layouts, self.allocator)
	}
}

graphics_destriptor_set_layout_init :: proc(bindings: []vk.DescriptorSetLayoutBinding) -> vk.DescriptorSetLayout {
	when !is_web {
		if vulkan_version.major > 0 {
			return vk.DescriptorSetLayoutInit(graphics_device(), bindings)
		}
	}
	return 0
}
graphics_destriptor_set_layout_destroy :: proc(layout: ^vk.DescriptorSetLayout) {
	when !is_web {
		if vulkan_version.major > 0 && layout^ != 0 {
			vk.DestroyDescriptorSetLayout(graphics_device(), layout^, nil)
			layout^ = 0
		}
	}
}

// Add resource to gMapResource stack (push_back)
@private graphics_add_resource_buffer :: proc(idx: Maybe(u32)) -> (punion_resource, u32) {
	sync.mutex_lock(&gMapResourceMtx)
	defer sync.mutex_unlock(&gMapResourceMtx)

	res: u32
	if idx == nil {
		if gMapResource_free_len == 0 do gMapResource_add_block()
		res = gMapResource_idx[gMapResource_free_len - 1]
		gMapResource_free_len -= 1
	} else {
		res = idx.?
	}

	list.push_back(&gMapResource[res], &new(union_resource_node, gVkMemTlsfAllocator).node)
	((^union_resource_node)(gMapResource[res].head)).res = buffer_resource{}
	return &((^union_resource_node)(gMapResource[res].head)).res.(buffer_resource), res
}

@private graphics_add_resource_texture :: proc(idx: Maybe(u32)) -> (punion_resource, u32) {
	sync.mutex_lock(&gMapResourceMtx)
	defer sync.mutex_unlock(&gMapResourceMtx)

	res: u32
	if idx == nil {
		if gMapResource_free_len == 0 do gMapResource_add_block()
		res = gMapResource_idx[gMapResource_free_len - 1]
		gMapResource_free_len -= 1
	} else {
		res = idx.?
	}

	list.push_back(&gMapResource[res], &new(union_resource_node, gVkMemTlsfAllocator).node)
	((^union_resource_node)(gMapResource[res].head)).res = texture_resource{}
	return &((^union_resource_node)(gMapResource[res].head)).res.(texture_resource), res
}

// Remove specific resource from gMapResource by punion_resource(not free punion_resource)
@private graphics_pop_resource :: proc(idx: u32, resource: punion_resource, lock := true) {
	if lock {
		sync.mutex_lock(&gMapResourceMtx)
	}
	defer if lock {
		sync.mutex_unlock(&gMapResourceMtx)
	}
	
    iter := list.iterator_head( gMapResource[idx], union_resource_node, "node")
    for node, success := list.iterate_next(&iter);success; {
        switch &n in node.res {
			case buffer_resource:
				if r, ok := resource.(^buffer_resource); ok && &n == r {
					tt : ^union_resource_node
					tt, success = list.iterate_next(&iter)
					list.remove(& gMapResource[idx], auto_cast node)
					free(node, gVkMemTlsfAllocator)
					node = tt
					continue
				}
			case texture_resource:
				if r, ok := resource.(^texture_resource); ok && &n == r {
					tt : ^union_resource_node
					tt, success = list.iterate_next(&iter)
					list.remove(& gMapResource[idx], auto_cast node)
					free(node, gVkMemTlsfAllocator)
					node = tt
					continue
				}
		}
		node, success = list.iterate_next(&iter)
    }
	if gMapResource[idx].head == nil {
		gMapResource_idx[gMapResource_free_len] = idx
		gMapResource_free_len += 1
	}
}

// Get last resource from stack (most recently created)
graphics_get_resource :: proc "contextless" (idx: Maybe(u32)) -> punion_resource {
	if idx == nil do return nil
	sync.mutex_lock(&gMapResourceMtx)
	defer sync.mutex_unlock(&gMapResourceMtx)
	if gMapResource[idx.?].tail == nil do return nil
	switch &res in ((^union_resource_node)(gMapResource[idx.?].tail)).res {
		case buffer_resource:
			return &res
		case texture_resource:
			return &res
	}
	return nil
}

// Get first resource from stack (for rendering - oldest)
graphics_get_resource_draw :: proc "contextless" (idx: Maybe(u32)) -> punion_resource {
	if idx == nil do return nil
	sync.mutex_lock(&gMapResourceMtx)
	defer sync.mutex_unlock(&gMapResourceMtx)
	if gMapResource[idx.?].head == nil do return nil
	switch &res in ((^union_resource_node)(gMapResource[idx.?].head)).res {
		case buffer_resource:
			return &res
		case texture_resource:
			return &res
	}
	return nil
}

@private gMapResource_add_block :: proc() {
	old_len := u32(len(gMapResource))
	gMapResource = mem.resize_slice(gMapResource, old_len + gMapResource_Block, gVkMemTlsfAllocator)
	gMapResource_idx = mem.resize_non_zeroed_slice(gMapResource_idx, old_len + gMapResource_Block, gVkMemTlsfAllocator)
	for i: u32 = old_len; i < old_len + gMapResource_Block; i += 1 {
		gMapResource_idx[gMapResource_free_len] = i
		gMapResource_free_len += 1
	}
}

@private gMapResource_init :: proc() {
	gMapResource = mem.make([]list.List, gMapResource_Block, __graphics_tlsf_allocator)
	gMapResource_idx = mem.make_non_zeroed([]u32, gMapResource_Block, __graphics_tlsf_allocator)
	gMapResource_free_len = 0
	for i: u32 = 0; i < gMapResource_Block; i += 1 {
		gMapResource_idx[gMapResource_free_len] = i
		gMapResource_free_len += 1
	}
}

@private gMapResource_destroy :: proc() {
	sync.mutex_lock(&gMapResourceMtx)
	defer sync.mutex_unlock(&gMapResourceMtx)
	gMapResource_free_len = 0
	for res in gMapResource {
		it := list.iterator_head(res, union_resource_node, "node")
		for node in list.iterate_next(&it) {
			free(node, __graphics_tlsf_allocator)
		}
	}
	delete(gMapResource, __graphics_tlsf_allocator)
	delete(gMapResource_idx, __graphics_tlsf_allocator)
}


@private union_resource_node :: struct {
	node:list.Node,
	res : union #no_nil {
		buffer_resource,
		texture_resource,
	}
}


@private gMapResource: []list.List
@private gMapResource_idx: []u32
@private gMapResource_free_len: u32
@private gMapResourceMtx: sync.Mutex
@private gMapResource_Block :: 512

@private __graphics_tlsf : tlsf.Allocator
@private __graphics_tlsf_allocator : runtime.Allocator

//!DO NOT CALL THIS FROM WITHIN ENGINE CALLBACKS
render_lock :: proc "contextless" () {
	sync.mutex_lock(&__g_layer_mtx)
}
//!DO NOT CALL THIS FROM WITHIN ENGINE CALLBACKS
render_unlock :: proc "contextless" () {
	sync.mutex_unlock(&__g_layer_mtx)
}
//!DO NOT CALL THIS FROM WITHIN ENGINE CALLBACKS
@(deferred_in=render_unlock)
render_guard :: proc "contextless" () -> bool {
	sync.mutex_lock(&__g_layer_mtx)
	return true
}
//!DO NOT CALL THIS FROM WITHIN ENGINE CALLBACKS
render_try_lock :: proc "contextless" () -> bool {
	return sync.mutex_try_lock(&__g_layer_mtx)
}

//!vertex, index buffers set manually
graphics_pipeline_draw :: proc "contextless" (cmd:command_buffer, pipeline:^object_pipeline, sets:[]vk.DescriptorSet) {
	if vulkan_version.major > 0 {
		graphics_cmd_bind_pipeline(cmd, .GRAPHICS, pipeline.__pipeline)
		graphics_cmd_bind_descriptor_sets(cmd, .GRAPHICS, pipeline.__pipeline_layout, 0, u32(len(sets)),
			&sets[0], 0, nil)
	}

    if pipeline.draw_method.type == .Draw {
        graphics_cmd_draw(cmd, pipeline.draw_method.vertex_count, pipeline.draw_method.instance_count, pipeline.draw_method.first_vertex, pipeline.draw_method.first_instance)
    } else if pipeline.draw_method.type == .DrawIndexed {
        graphics_cmd_draw_indexed(cmd, pipeline.draw_method.index_count, pipeline.draw_method.instance_count, pipeline.draw_method.first_index, pipeline.draw_method.vertex_offset, pipeline.draw_method.first_instance)
    }
}
