package engine

import "base:library"
import "base:runtime"
import "core:debug/trace"
import "core:math/linalg"
import "core:mem"
import "core:sync"
import "core:time"
import "core:engine"

import vk "vendor:vulkan"


MAX_FRAMES_IN_FLIGHT :: #config(MAX_FRAMES_IN_FLIGHT, 2)

wire_mode :: #config(WIRE_MODE, false)
@private swap_img_cnt : u32 = 3


graphics_device :: #force_inline proc "contextless" () -> vk.Device {
	return vk_device
}

// Graphics State
@private g_clear_color: [4]f32 = {0.0, 0.0, 0.0, 1.0}
@private rotation_matrix: linalg.Matrix
@private depth_fmt: texture_fmt



// Pipeline Layouts
@private shape_pipeline_layout: vk.PipelineLayout
@private tex_pipeline_layout: vk.PipelineLayout
@private animate_tex_pipeline_layout: vk.PipelineLayout
// copy_screen_pipeline_layout: vk.PipelineLayout

// Pipelines
@private shape_pipeline: vk.Pipeline
@private tex_pipeline: vk.Pipeline
@private animate_tex_pipeline: vk.Pipeline
// copy_screen_pipeline: vk.Pipeline

// Descriptor Set Layouts
@private shape_descriptor_set_layout: vk.DescriptorSetLayout
@private tex_descriptor_set_layout: vk.DescriptorSetLayout
@private tex_descriptor_set_layout2: vk.DescriptorSetLayout  // used animate tex
@private animate_tex_descriptor_set_layout: vk.DescriptorSetLayout
// copy_screen_descriptor_set_layout: vk.DescriptorSetLayout

// Samplers
@private linear_sampler: vk.Sampler
@private nearest_sampler: vk.Sampler

// Default Color Transform
@private __def_color_transform: color_transform

def_color_transform :: #force_inline proc "contextless" () -> ^color_transform {
	return &__def_color_transform
}
get_shape_pipeline_layout :: #force_inline proc "contextless" () -> vk.PipelineLayout {
	return shape_pipeline_layout
}
get_tex_pipeline_layout :: #force_inline proc "contextless" () -> vk.PipelineLayout {
	return tex_pipeline_layout
}
get_animate_tex_pipeline_layout :: #force_inline proc "contextless" () -> vk.PipelineLayout {
	return animate_tex_pipeline_layout
}
get_shape_pipeline :: #force_inline proc "contextless" () -> vk.Pipeline {
	return shape_pipeline
}
get_tex_pipeline :: #force_inline proc "contextless" () -> vk.Pipeline {
	return tex_pipeline
}
get_animate_tex_pipeline :: #force_inline proc "contextless" () -> vk.Pipeline {
	return animate_tex_pipeline
}
get_shape_descriptor_set_layout :: #force_inline proc "contextless" () -> vk.DescriptorSetLayout {
	return shape_descriptor_set_layout
}
get_tex_descriptor_set_layout :: #force_inline proc "contextless" () -> vk.DescriptorSetLayout {
	return tex_descriptor_set_layout
}
get_animate_tex_descriptor_set_layout :: #force_inline proc "contextless" () -> vk.DescriptorSetLayout {
	return animate_tex_descriptor_set_layout
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

// ============================================================================
// Graphics Operations
// ============================================================================

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
    if is_main_thread() {
        graphics_execute_ops(true)
    } else {
        vk_wait_all_op()
    }
}

// 작업 실행
graphics_execute_ops :: #force_inline proc(wait_and_destroy: bool) {
	vk_op_execute(wait_and_destroy)
}

// 작업 실행 (파괴만)
graphics_execute_ops_destroy :: #force_inline proc() {
	vk_op_execute_destroy()
}


// 단일 시간 명령 버퍼 시작
graphics_begin_single_time_cmd :: #force_inline proc "contextless" () -> command_buffer {
	return command_buffer{__handle = vk_begin_single_time_cmd()}
}

// 단일 시간 명령 버퍼 종료
graphics_end_single_time_cmd :: #force_inline proc "contextless" (cmd: command_buffer) {
	vk_end_single_time_cmd(cmd.__handle)
}

/*
Allocates command buffers from the command pool

Inputs:
- p_cmd_buffer: Pointer to the array of command buffers to allocate
- count: Number of command buffers to allocate

Returns:
- None
*/
allocate_command_buffers :: proc(p_cmd_buffer: [^]command_buffer, count: u32) {
	alloc_info := vk.CommandBufferAllocateInfo{
		sType = vk.StructureType.COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool = vk_cmd_pool,
		level = vk.CommandBufferLevel.PRIMARY,
		commandBufferCount = count,
	}
	res := vk.AllocateCommandBuffers(graphics_device(), &alloc_info, auto_cast p_cmd_buffer)
	if res != .SUCCESS do trace.panic_log("res = vk.AllocateCommandBuffers(graphics_device(), &alloc_info, &cmd.cmds[i][0]) : ", res)
}

/*
Frees command buffers back to the command pool

Inputs:
- p_cmd_buffer: Pointer to the array of command buffers to free
- count: Number of command buffers to free

Returns:
- None
*/
free_command_buffers :: proc(p_cmd_buffer: [^]command_buffer, count: u32) {
	vk.FreeCommandBuffers(graphics_device(), vk_cmd_pool, count, auto_cast p_cmd_buffer)
}

// ============================================================================
// Pipeline Operations
// ============================================================================

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
graphics_cmd_bind_vertex_buffers :: #force_inline proc "contextless" (
	cmd: command_buffer,
	first_binding: u32,
	binding_count: u32,
	p_buffers: ^vk.Buffer,
	p_offsets: ^vk.DeviceSize,
) {
	vk.CmdBindVertexBuffers(cmd.__handle, first_binding, binding_count, p_buffers, p_offsets)
}

// 인덱스 버퍼 바인딩
graphics_cmd_bind_index_buffer :: #force_inline proc "contextless" (
	cmd: command_buffer,
	buffer: vk.Buffer,
	offset: vk.DeviceSize,
	index_type: vk.IndexType,
) {
	vk.CmdBindIndexBuffer(cmd.__handle, buffer, offset, index_type)
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

// ============================================================================
// Fullscreen Operations
// ============================================================================

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
	self: ^buffer_resource,
	option: buffer_create_option,
	data: []byte,
	is_copy: bool = false,
	allocator: Maybe(runtime.Allocator) = nil,
) {
	vkbuffer_resource_create_buffer(self, option, data, is_copy, allocator)
}

buffer_resource_deinit :: #force_inline proc(self: ^$T) where T == buffer_resource || T == texture_resource {
	vkbuffer_resource_deinit(self)
}

buffer_resource_copy_update :: #force_inline proc(self: union_resource, data: ^$T, allocator: Maybe(runtime.Allocator) = nil) {
	vkbuffer_resource_copy_update(self, data, allocator)
}

buffer_resource_copy_update_slice :: #force_inline proc(self: union_resource, array: $T/[]$E, allocator: Maybe(runtime.Allocator) = nil) {
	vkbuffer_resource_copy_update_slice(self, array, allocator)
}

buffer_resource_map_update_slice :: #force_inline proc(self: union_resource, array: $T/[]$E, allocator: Maybe(runtime.Allocator) = nil) {
	vkbuffer_resource_map_update_slice(self, array, allocator)
}

buffer_resource_create_texture :: #force_inline proc(
	self: ^texture_resource,
	option: texture_create_option,
	sampler: vk.Sampler,
	data: []byte,
	is_copy: bool = false,
	allocator: Maybe(runtime.Allocator) = nil,
) {
	vkbuffer_resource_create_texture(auto_cast self, option, sampler, data, is_copy, allocator)
}

// Descriptor Set Operations
update_descriptor_sets :: #force_inline proc(descriptor_sets: []descriptor_set) {
	vk_update_descriptor_sets(descriptor_sets)
}

// ============================================================================
// Color Transform
// ============================================================================

/*
Initializes a color transform with a raw matrix

Inputs:
- self: Pointer to the color transform to initialize
- mat: The color transform matrix (default: identity matrix)

Returns:
- None
*/
color_transform_init_matrix_raw :: proc(self: ^color_transform, mat: linalg.Matrix = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1}) {
	self.mat = mat
	__color_transform_init(self)
}

@private __color_transform_init :: #force_inline proc(self: ^color_transform) {
	mem.ICheckInit_Init(&self.check_init)
	buffer_resource_create_buffer(&self.mat_uniform, {
		len = size_of(linalg.Matrix),
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
	mem.ICheckInit_Deinit(&self.check_init)
	clone_mat_uniform := new(buffer_resource, __temp_arena_allocator)
	clone_mat_uniform^ = self.mat_uniform
	buffer_resource_deinit(clone_mat_uniform)
}

/*
Updates the color transform with a raw matrix

Inputs:
- self: Pointer to the color transform to update
- _mat: The new color transform matrix

Returns:
- None
*/
color_transform_update_matrix_raw :: proc(self: ^color_transform, _mat: linalg.Matrix) {
	mem.ICheckInit_Check(&self.check_init)
	self.mat = _mat
	buffer_resource_copy_update(&self.mat_uniform, &self.mat)
}

@private graphics_create :: proc() {
	color_transform_init_matrix_raw(&__def_color_transform)
}

@private graphics_clean :: proc() {
	color_transform_deinit(&__def_color_transform)
}

// ============================================================================
// Pipeline Creation
// ============================================================================

/*
Creates a graphics pipeline for a custom object

Inputs:
- self: Pointer to the custom object pipeline
- stages: Shader stage create info array
- depth_stencil_state: Depth stencil state create info
- viewport_state: Viewport state create info
- vertex_input_state: Vertex input state create info

Returns:
- `true` if pipeline creation succeeded, `false` otherwise
*/
create_graphics_pipeline :: proc(
	self: ^object_pipeline,
	stages: []vk.PipelineShaderStageCreateInfo,
	depth_stencil_state: ^vk.PipelineDepthStencilStateCreateInfo,
	viewport_state: ^vk.PipelineViewportStateCreateInfo,
	vertex_input_state: ^vk.PipelineVertexInputStateCreateInfo,
) -> bool {
	pipeline_create_info := vk.GraphicsPipelineCreateInfoInit(
		stages = stages,
		layout = self.__pipeline_layout,
		pDepthStencilState = depth_stencil_state,
		pViewportState = viewport_state,
		pVertexInputState = vertex_input_state,
		renderPass = vk_render_pass,
		pMultisampleState = &vkPipelineMultisampleStateCreateInfo,
		pColorBlendState = &vk.DefaultPipelineColorBlendStateCreateInfo,
	)

	res := vk.CreateGraphicsPipelines(graphics_device(), 0, 1, &pipeline_create_info, nil, &self.__pipeline)
	if res != .SUCCESS {
		trace.printlnLog("create_graphics_pipeline: Failed to create graphics pipeline:", res)
		return false
	}
	return true
}


/*
Gets the graphics origin format

Returns:
- The Vulkan format used as the graphics origin format
*/
get_graphics_origin_format :: proc "contextless" () -> vk.Format {
	return vk_fmt.format
}


@(private) graphics_recreate_swapchain :: #force_inline proc() {vk_recreate_swap_chain()}
@(private) graphics_recreate_surface :: #force_inline proc() {vk_recreate_surface()}
@(private) graphics_allocator_init :: #force_inline proc() {vk_allocator_init()}
@(private) graphics_allocator_destroy :: #force_inline proc() {vk_allocator_destroy()}
