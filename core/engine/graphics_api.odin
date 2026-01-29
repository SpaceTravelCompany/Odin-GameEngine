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
import "core:container/pool"
import "core:log"

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
@private __animate_img_descriptor_set_layout: vk.DescriptorSetLayout
// copy_screen_descriptor_set_layout: vk.DescriptorSetLayout

// Samplers
@private linear_sampler: vk.Sampler
@private nearest_sampler: vk.Sampler

// Default Color Transform
@private __def_color_transform: color_transform

union_resource :: union {
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

buffer_resource :: struct {
	using _: base_resource,
	self:^buffer_resource,
	option: buffer_create_option,
	__resource: vk.Buffer,
}

texture_resource :: struct {
	using _: base_resource,
	self:^texture_resource,
	img_view: vk.ImageView,
	sampler: vk.Sampler,
	option: texture_create_option,
	__resource: vk.Image,
}

buffer_create_option :: struct {
	size: graphics_size,
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
	__resources: []union_resource,
}

command_buffer :: struct #packed {
	__handle: vk.CommandBuffer,
}

color_transform :: struct {
	mat: linalg.matrix44,
}

texture :: struct {
	set: descriptor_set,
	sampler: vk.Sampler,
	pixel_data: []byte,
	width: u32,
	height: u32,
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


@private graphics_init :: #force_inline proc() {
	_ = pool.init(&gBufferPool, "self", ) 
	_ = pool.init(&gTexturePool, "self", )
	vk_start()
}

@private graphics_destroy :: #force_inline proc() {
	vk_destroy()
}

@private graphics_draw_frame :: #force_inline proc() {
	vk_draw_frame()
}

@private graphics_wait_device_idle :: #force_inline proc () {
	vk_wait_device_idle()
}

@private graphics_wait_graphics_idle :: #force_inline proc () {
	vk_wait_graphics_idle()
}

@private graphics_wait_present_idle :: #force_inline proc () {
	vk_wait_present_idle()
}

@private graphics_execute_ops :: #force_inline proc() {
	vk_op_execute()
}

allocate_command_buffers :: proc(p_cmd_buffer: [^]command_buffer, count: u32, cmd_pool: vk.CommandPool) {
	alloc_info := vk.CommandBufferAllocateInfo{
		sType = vk.StructureType.COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool = cmd_pool,
		level = vk.CommandBufferLevel.SECONDARY,
		commandBufferCount = count,
	}
	res := vk.AllocateCommandBuffers(graphics_device(), &alloc_info, auto_cast p_cmd_buffer)
	if res != .SUCCESS do log.panicf("res = vk.AllocateCommandBuffers(graphics_device(), &alloc_info, &cmd.cmds[i][0]) : %s\n", res)
}

free_command_buffers :: proc(p_cmd_buffer: [^]command_buffer, count: u32, cmd_pool: vk.CommandPool) {
	vk.FreeCommandBuffers(graphics_device(), cmd_pool, count, auto_cast p_cmd_buffer)
}

graphics_cmd_bind_pipeline :: #force_inline proc "contextless" (cmd: command_buffer, pipeline_bind_point: vk.PipelineBindPoint, pipeline: vk.Pipeline) {
	vk.CmdBindPipeline(cmd.__handle, pipeline_bind_point, pipeline)
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
	vk.CmdBindDescriptorSets(cmd.__handle, pipeline_bind_point, layout, first_set, descriptor_set_count, p_descriptor_sets, dynamic_offset_count, p_dynamic_offsets)
}

graphics_cmd_bind_vertex_buffers :: proc (
	cmd: command_buffer,
	first_binding: u32,
	binding_count: u32,
	p_buffers: []^buffer_resource,
	p_offsets: ^vk.DeviceSize,
) {
	buffers: []vk.Buffer = mem.make_non_zeroed([]vk.Buffer, len(p_buffers), context.temp_allocator)
	defer delete(buffers, context.temp_allocator)
	for b, i in p_buffers {
		buffers[i] = b.__resource
	}
	vk.CmdBindVertexBuffers(cmd.__handle, first_binding, binding_count, &buffers[0], p_offsets)
}


graphics_cmd_bind_index_buffer :: #force_inline proc "contextless" (
	cmd: command_buffer,
	buffer: ^buffer_resource,
	offset: vk.DeviceSize,
	index_type: vk.IndexType,
) {
	vk.CmdBindIndexBuffer(cmd.__handle, buffer.__resource, offset, index_type)
}

graphics_cmd_draw :: #force_inline proc "contextless" (
	cmd: command_buffer,
	vertex_count: u32,
	instance_count: u32,
	first_vertex: u32,
	first_instance: u32,
) {
	vk.CmdDraw(cmd.__handle, vertex_count, instance_count, first_vertex, first_instance)
}

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


graphics_set_fullscreen_exclusive :: #force_inline proc() {
	vk_set_full_screen_ex()
}

graphics_release_fullscreen_exclusive :: #force_inline proc() {
	vk_release_full_screen_ex()
}

buffer_resource_create_buffer :: proc(
	self: rawptr,
	option: buffer_create_option,
	data: []byte,
	is_copy: bool = false,
	allocator: Maybe(runtime.Allocator) = nil,
) {
	out_res: union_resource = graphics_add_resource_buffer(self)
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
}

buffer_resource_deinit :: proc(self: rawptr) {
	base := graphics_get_resource(self)
	if base == nil do return

	switch b in base {
	case ^buffer_resource:
		if b.option.type == .UNIFORM {
			graphics_pop_resource(self, base)
			append_op(OpReleaseUniform{src = b})
		} else {
			// 나중에 지운다.
			append_op(OpDestroyBuffer{self = self, src = b})
		}
	case ^texture_resource:
		if b.mem_buffer == nil {
			graphics_pop_resource(self, base)
			vk.DestroyImageView(vk_device, b.img_view, nil)
		} else {
			// 나중에 지운다.
			append_op(OpDestroyTexture{self = self, src = b})
		}
	}
}

buffer_resource_copy_update :: proc(self: rawptr, data: $T, allocator: Maybe(runtime.Allocator) = nil)
where intrinsics.type_is_slice(T) || intrinsics.type_is_pointer(T) {
	base := graphics_get_resource(self)
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

buffer_resource_map_update_slice :: #force_inline proc(self: rawptr, array: $T/[]$E, allocator: Maybe(runtime.Allocator) = nil) {
	_data := mem.slice_to_bytes(array)
	base := graphics_get_resource(self)
	if base == nil do return
	switch b in base {
	case ^buffer_resource:
		buffer_resource_MapCopy(b, _data, allocator)
	case ^texture_resource:
		buffer_resource_MapCopy(b, _data, allocator)
	}
}

buffer_resource_create_texture :: proc(
	self: rawptr,
	option: texture_create_option,
	sampler: vk.Sampler,
	data: []byte,
	is_copy: bool = false,
	allocator: Maybe(runtime.Allocator) = nil,
) {
	out_res: union_resource = graphics_add_resource_texture(self)
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
}

update_descriptor_sets :: #force_inline proc(descriptor_sets: []descriptor_set) {
	vk_update_descriptor_sets(descriptor_sets)
}

color_transform_init_matrix_raw :: proc(self: ^color_transform, mat: linalg.matrix44 = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1}) {
	self.mat = mat
	__color_transform_init(self)
}

@private __color_transform_init :: #force_inline proc(self: ^color_transform) {
	buffer_resource_create_buffer(self, {
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
	buffer_resource_deinit(self)
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
	graphics_wait_graphics_idle()
    vk.DestroyPipelineLayout(graphics_device(), self.__pipeline_layout, nil)
    vk.DestroyPipeline(graphics_device(), self.__pipeline, nil)
    delete(self.__descriptor_set_layouts, self.allocator)
}


@private __shader_inited := false
@private __shader_mtx:sync.Mutex

// shader compiler initialization (glslang) (once per process)
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

// shader compiler deinitialization (glslang)
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
                    shader := glslang.shader_create(&input)
                    if shader == nil {
                        log.error("custom_object_pipeline_init: failed to create shader\n")
                        return false
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
                        return false
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
                        return false
                    }
                    
                    program := glslang.program_create()
                    if program == nil {
                        log.error("custom_object_pipeline_init: failed to create program\n")
                        return false
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
                        return false
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
                    glslang.program_SPIRV_generate_with_options(program, shader_kinds[i], &spv_options)
                    
                    spirv_size := glslang.program_SPIRV_get_size(program)
                    spirv_data = mem.make_non_zeroed([]u8, size_of(u32) * spirv_size, 64, context.temp_allocator)
                    glslang.program_SPIRV_get(program, cast(^c.uint)&spirv_data[0])
                    
                    spirv_messages := glslang.program_SPIRV_get_messages(program)
                    if spirv_messages != nil {log.error(spirv_messages, "\n")}
                    
                    shader_bytes = spirv_data
                    shader_programs[i] = program
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
    self.__descriptor_set_layouts = mem.make_non_zeroed_slice([]vk.DescriptorSetLayout, len(descriptor_set_layouts), allocator)
	mem.copy_non_overlapping(&self.__descriptor_set_layouts[0], &descriptor_set_layouts[0], len(descriptor_set_layouts) * size_of(vk.DescriptorSetLayout))
    self.__pipeline_layout, res = vk.PipelineLayoutInit(graphics_device(), self.__descriptor_set_layouts)
	if res != .SUCCESS {
		log.errorf("custom_object_pipeline_init: PipelineLayoutInit : %s\n", res)
		delete(self.__descriptor_set_layouts, allocator)
		return false
	}

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
		delete(self.__descriptor_set_layouts, allocator)
		vk.DestroyPipelineLayout(graphics_device(), self.__pipeline_layout, nil)
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

graphics_destriptor_set_layout_init :: proc(bindings: []vk.DescriptorSetLayoutBinding) -> vk.DescriptorSetLayout {
	return vk.DescriptorSetLayoutInit(graphics_device(), bindings)
}

animate_img_descriptor_set_layout :: proc() -> vk.DescriptorSetLayout {
	return __animate_img_descriptor_set_layout
}

__graphics_alloc_descriptor_resources :: proc(len:int) -> []union_resource {
	return make([]union_resource, len, vk_def_allocator())
}

__graphics_free_descriptor_resources :: proc(resources: []union_resource) {
	delete(resources, vk_def_allocator())
}

// Add resource to gMapResource stack (push_back)
@private graphics_add_resource_buffer :: proc(self: rawptr) -> union_resource {
	sync.mutex_lock(&gMapResourceMtx)
	defer sync.mutex_unlock(&gMapResourceMtx)

	res: union_resource
	res = pool.get(&gBufferPool)
	
	if self not_in gMapResource {
		map_insert(&gMapResource, self, make([dynamic]union_resource, vk_def_allocator()))
	}
	append(&gMapResource[self], res)
	return res
}

@private graphics_add_resource_texture :: proc(self: rawptr) -> union_resource {
	sync.mutex_lock(&gMapResourceMtx)
	defer sync.mutex_unlock(&gMapResourceMtx)

	res: union_resource
	res = pool.get(&gTexturePool)
	
	if self not_in gMapResource {
		map_insert(&gMapResource, self, make([dynamic]union_resource, vk_def_allocator()))
	}
	append(&gMapResource[self], res)
	return res
}

// Remove specific resource from gMapResource by union_resource(not free union_resource)
@private graphics_pop_resource :: proc(self: rawptr, resource: union_resource, lock := true) -> bool {
	if lock {
		sync.mutex_lock(&gMapResourceMtx)
	}
	defer if lock {
		sync.mutex_unlock(&gMapResourceMtx)
	}
	
	if self not_in gMapResource || len(gMapResource[self]) == 0 {
		return false
	}
	
	for i in 0..<len(gMapResource[self]) {
		if gMapResource[self][i] == resource {
			ordered_remove(&gMapResource[self], i)

			if len(gMapResource[self]) == 0 {
				delete(gMapResource[self])
				delete_key(&gMapResource, self)		
			}
			return true
		}
	}
	return false
}

// Get last resource from stack (most recently created)
graphics_get_resource :: proc "contextless" (self: rawptr) -> union_resource {
	sync.mutex_lock(&gMapResourceMtx)
	defer sync.mutex_unlock(&gMapResourceMtx)
	if self not_in gMapResource || len(gMapResource[self]) == 0 {
		return nil
	}
	return gMapResource[self][len(gMapResource[self]) - 1]
}

// Get first resource from stack (for rendering - oldest)
graphics_get_resource_draw :: proc "contextless" (self: rawptr) -> union_resource {
	sync.mutex_lock(&gMapResourceMtx)
	defer sync.mutex_unlock(&gMapResourceMtx)
	if self not_in gMapResource || len(gMapResource[self]) == 0 {
		return nil
	}
	for res in gMapResource[self] {
		switch r in res {
		case ^buffer_resource:
			if r.completed do return res
		case ^texture_resource:
			if r.completed do return res
		}
	}
	return nil
}

@private gMapResource: map[rawptr][dynamic]union_resource
@private gMapResourceMtx: sync.Mutex
@private gBufferPool: pool.Pool(buffer_resource)
@private gTexturePool: pool.Pool(texture_resource)

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