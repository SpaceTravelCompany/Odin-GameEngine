package engine

import "base:intrinsics"
import "base:library"
import "base:runtime"
import "core:debug/trace"
import "core:strings"
import "core:math/linalg"
import "core:mem"
import "core:c"
import "core:sync"
import "vendor:glslang"

import vk "vendor:vulkan"


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
@private shape_pipeline: object_pipeline
@private img_pipeline: object_pipeline
@private animate_img_pipeline: object_pipeline

// Descriptor Set Layouts
@private __base_descriptor_set_layout: vk.DescriptorSetLayout
@private __img_descriptor_set_layout: vk.DescriptorSetLayout
@private animate_img_descriptor_set_layout: vk.DescriptorSetLayout
// copy_screen_descriptor_set_layout: vk.DescriptorSetLayout

// Samplers
@private linear_sampler: vk.Sampler
@private nearest_sampler: vk.Sampler

// Default Color Transform
@private __def_color_transform: color_transform

@private g_wait_rendering_sem: sync.Sema

@private resource_type :: enum {
	BUFFER,
	TEXTURE,
}

base_resource :: struct {
	g_uniform_indices: [4]graphics_size,
	idx: resource_range,  // unused uniform buffer
	mem_buffer: MEM_BUFFER,
	type: resource_type,
}

MEM_BUFFER :: distinct rawptr

buffer_resource :: struct {
	using _: base_resource,
	option: buffer_create_option,
	__resource: vk.Buffer,
}

texture_resource :: struct {
	using _: base_resource,
	img_view: vk.ImageView,
	sampler: vk.Sampler,
	option: texture_create_option,
	__resource: vk.Image,
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


object_pipeline :: struct {
    __pipeline:vk.Pipeline,
    __pipeline_layout:vk.PipelineLayout,
    __descriptor_set_layouts:[]vk.DescriptorSetLayout,

    draw_method:object_draw_method,
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

descriptor_set :: struct {
	layout: vk.DescriptorSetLayout,
	/// created inside update_descriptor_sets call
	__set: vk.DescriptorSet,
	size: []descriptor_pool_size,
	bindings: []u32,
	__resources: []iresource,
}

command_buffer :: struct #packed {
	__handle: vk.CommandBuffer,
}

color_transform :: struct {
	mat: linalg.matrix44,
	mat_uniform: iresource,
}

texture :: struct {
	texture: iresource,
	set: descriptor_set,
	sampler: vk.Sampler,
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

def_color_transform :: #force_inline proc "contextless" () -> ^color_transform {
	return &__def_color_transform
}

get_shape_pipeline :: #force_inline proc "contextless" () -> ^object_pipeline {
	return &shape_pipeline
}
get_img_pipeline :: #force_inline proc "contextless" () -> ^object_pipeline {
	return &img_pipeline
}
get_animate_img_pipeline :: #force_inline proc "contextless" () -> ^object_pipeline {
	return &animate_img_pipeline
}
base_descriptor_set_layout :: #force_inline proc "contextless" () -> vk.DescriptorSetLayout {
	return __base_descriptor_set_layout
}

get_linear_sampler :: #force_inline proc "contextless" () -> vk.Sampler {
	return linear_sampler
}
get_nearest_sampler :: #force_inline proc "contextless" () -> vk.Sampler {	
	return nearest_sampler
}


// Graphics API 초기화
@private graphics_init :: #force_inline proc() {
	vk_start()
}

// Graphics API 정리
@private graphics_destroy :: #force_inline proc() {
	vk_destroy()
}

// 프레임 렌더링
@private graphics_draw_frame :: #force_inline proc() {
	vk_draw_frame()
}

// 디바이스 대기
graphics_wait_device_idle :: #force_inline proc "contextless" () {
	vk_wait_device_idle()
}

// 그래픽 큐 대기
graphics_wait_graphics_idle :: #force_inline proc "contextless" () {
	vk_wait_graphics_idle()
}

// 프레젠트 큐 대기
graphics_wait_present_idle :: #force_inline proc "contextless" () {
	vk_wait_present_idle()
}

// 모든 비동기 작업 대기
graphics_wait_all_ops :: #force_inline proc () {
    vk_wait_all_op()
}

// 렌더링 까지 대기
graphics_wait_rendering :: #force_inline proc () {
    sync.sema_wait(&g_wait_rendering_sem)
}

// 작업 실행
graphics_execute_ops :: #force_inline proc() {
	vk_op_execute()
}

// 작업 실행 (파괴만)
graphics_execute_ops_destroy :: #force_inline proc() {
	vk_op_execute_destroy()
}

allocate_command_buffers :: proc(p_cmd_buffer: [^]command_buffer, count: u32, cmd_pool: vk.CommandPool) {
	alloc_info := vk.CommandBufferAllocateInfo{
		sType = vk.StructureType.COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool = cmd_pool,
		level = vk.CommandBufferLevel.SECONDARY,
		commandBufferCount = count,
	}
	res := vk.AllocateCommandBuffers(graphics_device(), &alloc_info, auto_cast p_cmd_buffer)
	if res != .SUCCESS do trace.panic_log("res = vk.AllocateCommandBuffers(graphics_device(), &alloc_info, &cmd.cmds[i][0]) : ", res)
}

free_command_buffers :: proc(p_cmd_buffer: [^]command_buffer, count: u32, cmd_pool: vk.CommandPool) {
	vk.FreeCommandBuffers(graphics_device(), cmd_pool, count, auto_cast p_cmd_buffer)
}

// 파이프라인 바인딩
graphics_cmd_bind_pipeline :: #force_inline proc "contextless" (cmd: command_buffer, pipeline_bind_point: vk.PipelineBindPoint, pipeline: vk.Pipeline) {
	vk.CmdBindPipeline(cmd.__handle, pipeline_bind_point, pipeline)
}

// 디스크립터 셋 바인딩
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
	vk.CmdBindDescriptorSets(cmd.__handle, pipeline_bind_point, layout, first_set, descriptor_set_count, p_descriptor_sets, dynamic_offset_count, p_dynamic_offsets)
}

// 버텍스 버퍼 바인딩
graphics_cmd_bind_vertex_buffers :: proc (
	cmd: command_buffer,
	first_binding: u32,
	binding_count: u32,
	p_buffers: []iresource,
	p_offsets: ^vk.DeviceSize,
) {
	buffers: []vk.Buffer = mem.make_non_zeroed([]vk.Buffer, len(p_buffers), context.temp_allocator)
	defer delete(buffers, context.temp_allocator)
	for b, i in p_buffers {
		buffers[i] = (^buffer_resource)(b).__resource
	}
	vk.CmdBindVertexBuffers(cmd.__handle, first_binding, binding_count, &buffers[0], p_offsets)
}

// 인덱스 버퍼 바인딩
graphics_cmd_bind_index_buffer :: #force_inline proc "contextless" (
	cmd: command_buffer,
	buffer: iresource,
	offset: vk.DeviceSize,
	index_type: vk.IndexType,
) {
	vk.CmdBindIndexBuffer(cmd.__handle, (^buffer_resource)(buffer).__resource, offset, index_type)
}

// 드로우
graphics_cmd_draw :: #force_inline proc "contextless" (
	cmd: command_buffer,
	vertex_count: u32,
	instance_count: u32,
	first_vertex: u32,
	first_instance: u32,
) {
	vk.CmdDraw(cmd.__handle, vertex_count, instance_count, first_vertex, first_instance)
}

// 인덱스 드로우
graphics_cmd_draw_indexed :: #force_inline proc "contextless" (
	cmd: command_buffer,
	index_count: u32,
	instance_count: u32,
	first_index: u32,
	vertex_offset: i32,
	first_instance: u32,
) {
	vk.CmdDrawIndexed(cmd.__handle, index_count, instance_count, first_index, vertex_offset, first_instance)
}


// 풀스크린 독점 모드 설정
graphics_set_fullscreen_exclusive :: #force_inline proc() {
	vk_set_full_screen_ex()
}

// 풀스크린 독점 모드 해제
graphics_release_fullscreen_exclusive :: #force_inline proc() {
	vk_release_full_screen_ex()
}

// Buffer Resource Operations
buffer_resource_create_buffer :: #force_inline proc(
	option: buffer_create_option,
	data: []byte,
	is_copy: bool = false,
	allocator: Maybe(runtime.Allocator) = nil,
) -> iresource {
	return vkbuffer_resource_create_buffer(option, data, is_copy, allocator)
}

buffer_resource_deinit :: #force_inline proc(self: iresource) {
	vkbuffer_resource_deinit(self)
}

buffer_resource_copy_update :: #force_inline proc(self: iresource, data: ^$T, allocator: Maybe(runtime.Allocator) = nil) {
	vkbuffer_resource_copy_update(self, data, allocator)
}

buffer_resource_copy_update_slice :: #force_inline proc(self: iresource, array: $T/[]$E, allocator: Maybe(runtime.Allocator) = nil) {
	vkbuffer_resource_copy_update_slice(self, array, allocator)
}

buffer_resource_map_update_slice :: #force_inline proc(self: iresource, array: $T/[]$E, allocator: Maybe(runtime.Allocator) = nil) {
	vkbuffer_resource_map_update_slice(self, array,allocator)
}

buffer_resource_create_texture :: #force_inline proc(
	option: texture_create_option,
	sampler: vk.Sampler,
	data: []byte,
	is_copy: bool = false,
	allocator: Maybe(runtime.Allocator) = nil,
) -> iresource {
	return vkbuffer_resource_create_texture(option, sampler, data, is_copy, allocator)
}

// Descriptor Set Operations
update_descriptor_sets :: #force_inline proc(descriptor_sets: []descriptor_set) {
	vk_update_descriptor_sets(descriptor_sets)
}

/*
Initializes a color transform with a raw matrix

Inputs:
- self: Pointer to the color transform to initialize
- mat: The color transform matrix (default: identity matrix)

Returns:
- None
*/
color_transform_init_matrix_raw :: proc(self: ^color_transform, mat: linalg.matrix44 = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1}) {
	self.mat = mat
	__color_transform_init(self)
}

@private __color_transform_init :: #force_inline proc(self: ^color_transform) {
	self.mat_uniform = buffer_resource_create_buffer({
		len = size_of(linalg.matrix44),
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
	buffer_resource_deinit(self.mat_uniform)
	self.mat_uniform = nil
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
	buffer_resource_copy_update(self.mat_uniform, &self.mat)
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

default_render_pass :: #force_inline proc "contextless" () -> vk.RenderPass {
	return vk_render_pass
}

default_multisample_state :: #force_inline proc "contextless" () -> ^vk.PipelineMultisampleStateCreateInfo {
	return &vkPipelineMultisampleStateCreateInfo
}


@(private) graphics_recreate_swapchain :: #force_inline proc() {vk_recreate_swap_chain()}
@(private) graphics_recreate_surface :: #force_inline proc() {vk_recreate_surface()}
@(private) graphics_allocator_init :: #force_inline proc() {vk_allocator_init()}
@(private) graphics_allocator_destroy :: #force_inline proc() {vk_allocator_destroy()}

when ODIN_DEBUG {
	@private SHADER_COMPILE_OPTION :: "none"
} else {
	@private SHADER_COMPILE_OPTION :: "speed"
}

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

shader_code ::union {
    []byte,
    string,
}

shader_lang :: enum {
    GLSL,
    HLSL,
}

descriptor_set_layout_binding_init :: vk.DescriptorSetLayoutBindingInit


object_pipeline_deinit :: proc(self:^object_pipeline) {
    vk.DestroyPipelineLayout(graphics_device(), self.__pipeline_layout, nil)
    vk.DestroyPipeline(graphics_device(), self.__pipeline, nil)
    delete(self.__descriptor_set_layouts, self.allocator)
}


@private __shader_inited := false
@private __shader_mtx:sync.Mutex

@private __shader_init :: proc "contextless" () {
	// glslang 초기화 (한 번만 호출) (프로세스 별로 호출 필요, 스레드 아님)
	if !intrinsics.atomic_load_explicit(&__shader_inited, .Relaxed) {
		sync.mutex_lock(&__shader_mtx)
		defer sync.mutex_unlock(&__shader_mtx)
		if glslang.initialize_process() == 0 {
			trace.panic_log("__shader_init: glslang initialization failed")
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

custom_object_pipeline_init :: proc(self:^object_pipeline,
    descriptor_set_layouts:[]vk.DescriptorSetLayout,
    vertex_input_binding:Maybe([]vertex_input_binding_description),
    vertex_input_attribute:Maybe([]vertex_input_attribute_description),
    draw_method:object_draw_method,
    vertex_shader:Maybe(shader_code),
    pixel_shader:Maybe(shader_code),
    geometry_shader:Maybe(shader_code) = nil,
    depth_stencil_state:Maybe(vk.PipelineDepthStencilStateCreateInfo) = nil,
    color_blend_state:Maybe(vk.PipelineColorBlendStateCreateInfo) = nil,
	shader_lang:shader_lang = .GLSL, allocator := context.allocator) -> bool {

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
        trace.panic_log("custom_object_pipeline_init: vertex_shader and pixel_shader cannot be nil")
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
					__shader_init()

					code_str := strings.clone_to_cstring(s, context.temp_allocator)
					defer delete(code_str, context.temp_allocator)

                    // Input 구조체 설정
                    input := glslang.Input{
                        language = shader_lang == .HLSL ? glslang.Source.HLSL : glslang.Source.GLSL,
                        stage = shader_kinds[i],
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
                    
                    // 셰이더 생성 및 파싱
                    shader := glslang.shader_create(&input)
                    if shader == nil {
                        trace.printlnLog("custom_object_pipeline_init: failed to create shader")
                        return false
                    }
                    defer glslang.shader_delete(shader)
                    
                    // Entry point 설정
                    glslang.shader_set_entry_point(shader, "main")

					if glslang.shader_preprocess(shader, &input) == 0 {
						info_log := glslang.shader_get_info_log(shader)
                        debug_log := glslang.shader_get_info_debug_log(shader)
                        if info_log != nil {
                            trace.printlnLog(info_log)
                        }
                        if debug_log != nil {
                            trace.printlnLog(debug_log)
                        }
                        return false
					}
                    
                    // 파싱
                    if glslang.shader_parse(shader, &input) == 0 {
                        info_log := glslang.shader_get_info_log(shader)
                        debug_log := glslang.shader_get_info_debug_log(shader)
                        if info_log != nil {
                            trace.printlnLog(info_log)
                        }
                        if debug_log != nil {
                            trace.printlnLog(debug_log)
                        }
                        return false
                    }
                    
                    // 프로그램 생성 및 링크
                    program := glslang.program_create()
                    if program == nil {
                        trace.printlnLog("custom_object_pipeline_init: failed to create program")
                        return false
                    }
                    glslang.program_add_shader(program, shader)
                    
                    link_messages := cast(c.int)(glslang.Messages.SPV_RULES_BIT) | cast(c.int)(glslang.Messages.VULKAN_RULES_BIT)
                    if glslang.program_link(program, link_messages) == 0 {
                        info_log := glslang.program_get_info_log(program)
                        debug_log := glslang.program_get_info_debug_log(program)
                        if info_log != nil {
                            trace.printlnLog(info_log)
                        }
                        if debug_log != nil {
                            trace.printlnLog(debug_log)
                        }
                        glslang.program_delete(program)
                        return false
                    }
                    
                    // SPIR-V 생성
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
						spv_options.emit_nonsemantic_shader_debug_source = true
					}
                    glslang.program_SPIRV_generate_with_options(program, shader_kinds[i], &spv_options)
                    
                    // SPIR-V 데이터 가져오기
                    spirv_size := glslang.program_SPIRV_get_size(program)
                    spirv_data = mem.make_non_zeroed([]u8, size_of(u32) * spirv_size, 64, context.temp_allocator)
                    glslang.program_SPIRV_get(program, cast(^c.uint)&spirv_data[0])
                    
                    // SPIR-V 메시지 확인
                    spirv_messages := glslang.program_SPIRV_get_messages(program)
                    if spirv_messages != nil {
                        trace.printlnLog(spirv_messages)
                    }
                    
                    shader_bytes = spirv_data
                    shader_programs[i] = program
                case []byte:
                    shader_bytes = s
            }
            shader_modules[i] = vk.CreateShaderModule2(graphics_device(), shader_bytes) or_else trace.panic_log("custom_object_pipeline_init: CreateShaderModule2")
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

    self.__descriptor_set_layouts = mem.make_non_zeroed_slice([]vk.DescriptorSetLayout, len(descriptor_set_layouts), allocator)
	mem.copy_non_overlapping(&self.__descriptor_set_layouts[0], &descriptor_set_layouts[0], len(descriptor_set_layouts) * size_of(vk.DescriptorSetLayout))
    self.__pipeline_layout = vk.PipelineLayoutInit(graphics_device(), self.__descriptor_set_layouts)

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
		trace.printlnLog("create_graphics_pipeline: Failed to create graphics pipeline:", res)
		return false
	}
	return true
}

graphics_destriptor_set_layout_init :: proc(bindings: []vk.DescriptorSetLayoutBinding) -> vk.DescriptorSetLayout {
	return vk.DescriptorSetLayoutInit(graphics_device(), bindings)
}