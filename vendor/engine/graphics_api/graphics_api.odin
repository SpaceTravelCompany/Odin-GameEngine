package graphics_api

import vk "vendor:vulkan"
import "base:runtime"
import "core:mem"
import "core:sync"
import "core:math/linalg"
import "core:time"
import "core:debug/trace"
import "core:mem/virtual"

import "../"

programStart := true
loopStart := false
maxFrame : f64
deltaTime : u64
processorCoreLen : int
gClearColor : [4]f32 = {0.0, 0.0, 0.0, 1.0}



ShapePipelineLayout: vk.PipelineLayout
TexPipelineLayout: vk.PipelineLayout
AnimateTexPipelineLayout: vk.PipelineLayout
//CopyScreenPipelineLayout: vk.PipelineLayout

ShapePipeline: vk.Pipeline
TexPipeline: vk.Pipeline
AnimateTexPipeline: vk.Pipeline
//CopyScreenPipeline: vk.Pipeline

graphics_Device : vk.Device

ShapeDescriptorSetLayout: vk.DescriptorSetLayout
TexDescriptorSetLayout: vk.DescriptorSetLayout
//used animate tex
TexDescriptorSetLayout2: vk.DescriptorSetLayout
AnimateTexDescriptorSetLayout: vk.DescriptorSetLayout
//CopyScreenDescriptorSetLayout: vk.DescriptorSetLayout

//CopyScreenDescriptorSet : vk.DescriptorSet
//CopyScreenDescriptorPool : vk.DescriptorPool

exiting : bool = false

DescriptorPoolMem :: struct {pool:vk.DescriptorPool, cnt:u32}

UnionResource :: union #no_nil {
    ^BufferResource,
    ^TextureResource
}

ResourceUsage :: enum {GPU,CPU}

TextureType :: enum {
    TEX2D,
   // TEX3D,
}
TextureUsage :: enum {
    IMAGE_RESOURCE,
    FRAME_BUFFER,
    __INPUT_ATTACHMENT,
    __TRANSIENT_ATTACHMENT,
    __STORAGE_IMAGE,
}
TextureUsages :: bit_set[TextureUsage]


color_fmt :: enum {
    Unknown,
	RGB,
    BGR,
    RGBA,
    BGRA,
    ARGB,
    ABGR,
    Gray,
    RGB16,
    BGR16,
    RGBA16,
    BGRA16,
    ARGB16,
    ABGR16,
    Gray16,
    RGB32,
    BGR32,
    RGBA32,
    BGRA32,
    ARGB32,
    ABGR32,
    Gray32,
    RGB32F,
    BGR32F,
    RGBA32F,
    BGRA32F,
    ARGB32F,
    ABGR32F,
    Gray32F,
}

TextureFmt :: enum {
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

Size :: vk.DeviceSize
ResourceRange :: rawptr

BaseResource :: struct {
    data : ResourceData,
    gUniformIndices : [4]Size,
    idx:ResourceRange,//unused uniform buffer
    vkMemBuffer:^VkMemBuffer,
}
ResourceData :: struct {
    data:[]byte,
    allocator:Maybe(runtime.Allocator),
    is_creating_modifing:bool,
}
BufferResource :: struct {
    using _:BaseResource,
    option:BufferCreateOption,
    __resource:vk.Buffer,
}
TextureResource :: struct {
    using _:BaseResource,
    imgView:vk.ImageView,
    sampler:vk.Sampler,
    option:TextureCreateOption,
    __resource:vk.Image,
}

BufferResource_CreateBuffer :: #force_inline proc (self: ^BufferResource,
	option: BufferCreateOption,
	data: []byte,
	isCopy: bool = false,
	allocator: Maybe(runtime.Allocator) = nil) {
    VkBufferResource_CreateBuffer(self, option, data, isCopy, allocator)
}
BufferResource_Deinit :: #force_inline proc(self: ^$T) where T == BufferResource || T == TextureResource {
    VkBufferResource_Deinit(self)
}
BufferResource_CopyUpdate :: #force_inline proc(self: UnionResource, data: ^$T, allocator: Maybe(runtime.Allocator) = nil) {
    VkBufferResource_CopyUpdate(self, data, allocator)
}


__defColorTransform : ColorTransform
@private Graphics_Create :: proc() {
    ColorTransform_InitMatrixRaw(&__defColorTransform)
}

@private Graphics_Clean :: proc() {
    ColorTransform_Deinit(&__defColorTransform)
}

ColorTransform :: struct {
    mat: linalg.Matrix,
    matUniform:BufferResource,
    checkInit: mem.ICheckInit,
}



ColorTransform_InitMatrixRaw :: proc(self:^ColorTransform, mat:linalg.Matrix = {1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1}) {
    self.mat = mat
    __ColorTransform_Init(self)
}

@private __ColorTransform_Init :: #force_inline proc(self:^ColorTransform) {
    mem.ICheckInit_Init(&self.checkInit)
    BufferResource_CreateBuffer(&self.matUniform, {
        len = size_of(linalg.Matrix),
        type = .UNIFORM,
        resourceUsage = .CPU,
    }, mem.ptr_to_bytes(&self.mat), true)
}

ColorTransform_Deinit :: proc(self:^ColorTransform) {
    mem.ICheckInit_Deinit(&self.checkInit)
    BufferResource_Deinit(&self.matUniform)
}

ColorTransform_UpdateMatrixRaw :: proc(self:^ColorTransform, _mat:linalg.Matrix) {
    mem.ICheckInit_Check(&self.checkInit)
    self.mat = _mat
    BufferResource_CopyUpdate(&self.matUniform, &self.mat)
}


TextureCreateOption :: struct {
    len:u32,
    width:u32,
    height:u32,
    type:TextureType,
    textureUsage:TextureUsages,
    resourceUsage:ResourceUsage,
    format:TextureFmt,
    samples:u8,
    single:bool,
    useGCPUMem:bool,
}

BufferCreateOption :: struct {
    len:Size,
    type:BufferType,
    resourceUsage:ResourceUsage,
    single:bool,
    useGCPUMem:bool,
}

BufferType :: enum {
    VERTEX,
    INDEX,
    UNIFORM,
    STORAGE,
    __STAGING
}

custom_object_DescriptorType :: enum {
    SAMPLER,  //vk.DescriptorType.COMBINED_IMAGE_SAMPLER
    UNIFORM_DYNAMIC,  //vk.DescriptorType.UNIFORM_BUFFER_DYNAMIC
    UNIFORM,  //vk.DescriptorType.UNIFORM_BUFFER
    STORAGE,
    STORAGE_IMAGE,//TODO (xfitgd)
}
custom_object_DescriptorPoolSize :: struct {type:custom_object_DescriptorType, cnt:u32}

DescriptorSet :: struct {
    layout: vk.DescriptorSetLayout,
    ///created inside update_descriptor_sets call
    __set: vk.DescriptorSet,
    size: []custom_object_DescriptorPoolSize,
    bindings: []u32,
    __resources: []UnionResource,
};
linearSampler: vk.Sampler
nearestSampler: vk.Sampler


Texture :: struct {
    texture:TextureResource,
    set:DescriptorSet,
    sampler: vk.Sampler,
    checkInit: mem.ICheckInit,
}

Texture_Init :: proc(self:^Texture, width:u32, height:u32, pixels:[]byte, sampler:vk.Sampler = 0, resourceUsage:ResourceUsage = .GPU, inPixelFmt:color_fmt = .RGBA) {
    mem.ICheckInit_Init(&self.checkInit)
    self.sampler = sampler == 0 ? linearSampler : sampler
    self.set.bindings = __singlePoolBinding[:]
    self.set.size = __singleSamplerPoolSizes[:]
    self.set.layout = TexDescriptorSetLayout2
    self.set.__set = 0
}

Texture_InitGrey :: proc(self:^Texture, #any_int width:int, #any_int height:int, pixels:[]byte, sampler:vk.Sampler = 0, resourceUsage:ResourceUsage = .GPU) {
    mem.ICheckInit_Init(&self.checkInit)
    self.sampler = sampler == 0 ? linearSampler : sampler
    self.set.bindings = __singlePoolBinding[:]
    self.set.size = __singleSamplerPoolSizes[:]
    self.set.layout = TexDescriptorSetLayout2
    self.set.__set = 0

    allocPixels := mem.make_non_zeroed_slice([]byte, width * height, engineDefAllocator)
    mem.copy_non_overlapping(&allocPixels[0], &pixels[0], len(pixels))
   
    BufferResource_CreateTexture(&self.texture, {
        width = auto_cast width,
        height = auto_cast height,
        useGCPUMem = false,
        format = .R8Unorm,
        samples = 1,
        len = 1,
        textureUsage = {.IMAGE_RESOURCE},
        type = .TEX2D,
        resourceUsage = resourceUsage,
        single = false,
    }, self.sampler, allocPixels, false, engineDefAllocator)

    self.set.__resources = mem.make_non_zeroed_slice([]UnionResource, 1, tempArenaAllocator)
    self.set.__resources[0] = &self.texture
    UpdateDescriptorSets(mem.slice_ptr(&self.set, 1))
}

BufferResource_CreateTexture :: #force_inline proc(self: ^TextureResource, 
    option: TextureCreateOption, 
    sampler: vk.Sampler, 
    data: []byte,
    isCopy: bool = false, 
    allocator: Maybe(runtime.Allocator) = nil) {
    VkBufferResource_CreateTexture(auto_cast self, option, sampler, data, isCopy, allocator)
}

BufferResource_MapUpdateSlice :: #force_inline proc(self: UnionResource, array:$T/[]$E, allocator: Maybe(runtime.Allocator) = nil) {
    VkBufferResource_MapUpdateSlice(self, array, allocator)
}

BufferResource_CopyUpdateSlice :: #force_inline proc(self: UnionResource, array:$T/[]$E, allocator: Maybe(runtime.Allocator) = nil) {
    VkBufferResource_CopyUpdateSlice(self, array, allocator)
}



UpdateDescriptorSets :: #force_inline proc(descriptorSets: []DescriptorSet) {
    VkUpdateDescriptorSets(descriptorSets)
}

CommandBuffer :: struct #packed {
	__handle: vk.CommandBuffer,
}

@(private = "file") __arena: virtual.Arena
tempArenaAllocator : mem.Allocator
engineDefAllocator : mem.Allocator


swapImgCnt : u32 = 3


system_start :: #force_inline proc() {
	_ = virtual.arena_init_growing(&__arena)
	engineDefAllocator = virtual.arena_allocator(&__arena)
}

// Graphics API 초기화
graphics_init :: #force_inline proc() {
	vkStart()
}

// Graphics API 정리
graphics_destroy :: #force_inline proc() {
	vkDestory()
}

graphics_after_destroy :: #force_inline proc() {
	virtual.arena_destroy(&__arena)
}

// 프레임 렌더링
graphics_draw_frame :: #force_inline proc() {
	vkDrawFrame()
}

// 디바이스 대기
graphics_wait_device_idle :: #force_inline proc "contextless" () {
	vkWaitDeviceIdle()
}

// 그래픽 큐 대기
graphics_wait_graphics_idle :: #force_inline proc "contextless" () {
	vkWaitGraphicsIdle()
}

// 프레젠트 큐 대기
graphics_wait_present_idle :: #force_inline proc "contextless" () {
	vkWaitPresentIdle()
}

// 스왑체인 재생성
@(private)
graphics_recreate_swapchain :: #force_inline proc() {
	vkRecreateSwapChain()
}

// 모든 비동기 작업 대기
graphics_wait_all_ops :: #force_inline proc "contextless" () {
	vkWaitAllOp()
}

// 단일 시간 명령 버퍼 시작
graphics_begin_single_time_cmd :: #force_inline proc "contextless" () -> CommandBuffer {
	return CommandBuffer{__handle = vkBeginSingleTimeCmd()}
}

// 단일 시간 명령 버퍼 종료
graphics_end_single_time_cmd :: #force_inline proc "contextless" (cmd: CommandBuffer) {
	vkEndSingleTimeCmd(cmd.__handle)
}

// 풀스크린 독점 모드 설정
graphics_set_fullscreen_exclusive :: #force_inline proc() {
	vkSetFullScreenEx()
}

// 풀스크린 독점 모드 해제
graphics_release_fullscreen_exclusive :: #force_inline proc() {
	vkReleaseFullScreenEx()
}

// 서페이스 재생성
@(private)
graphics_recreate_surface :: #force_inline proc() {
	vkRecreateSurface()
}

// 메모리 할당자 초기화
@(private)
graphics_allocator_init :: #force_inline proc() {
	vkAllocatorInit()
}

// 메모리 할당자 정리
@(private)
graphics_allocator_destroy :: #force_inline proc() {
	vkAllocatorDestroy()
}

// 작업 실행
graphics_execute_ops :: #force_inline proc(wait_and_destroy: bool) {
	vkOpExecute(wait_and_destroy)
}

MSAACount :: 4
WIREMODE :: false


// 작업 실행 (파괴만)
graphics_execute_ops_destroy :: #force_inline proc() {
	vkOpExecuteDestroy()
}

// 파이프라인 바인딩
graphics_cmd_bind_pipeline :: #force_inline proc "contextless" (cmd: CommandBuffer, pipelineBindPoint: vk.PipelineBindPoint, pipeline: vk.Pipeline) {
	vk.CmdBindPipeline(cmd.__handle, pipelineBindPoint, pipeline)
}

// 디스크립터 셋 바인딩
graphics_cmd_bind_descriptor_sets :: #force_inline proc "contextless" (
	cmd: CommandBuffer,
	pipelineBindPoint: vk.PipelineBindPoint,
	layout: vk.PipelineLayout,
	firstSet: u32,
	descriptorSetCount: u32,
	pDescriptorSets: ^vk.DescriptorSet,
	dynamicOffsetCount: u32,
	pDynamicOffsets: ^u32,
) {
	vk.CmdBindDescriptorSets(cmd.__handle, pipelineBindPoint, layout, firstSet, descriptorSetCount, pDescriptorSets, dynamicOffsetCount, pDynamicOffsets)
}

// 버텍스 버퍼 바인딩
graphics_cmd_bind_vertex_buffers :: #force_inline proc "contextless" (
	cmd: CommandBuffer,
	firstBinding: u32,
	bindingCount: u32,
	pBuffers: ^vk.Buffer,
	pOffsets: ^vk.DeviceSize,
) {
	vk.CmdBindVertexBuffers(cmd.__handle, firstBinding, bindingCount, pBuffers, pOffsets)
}

// 인덱스 버퍼 바인딩
graphics_cmd_bind_index_buffer :: #force_inline proc "contextless" (
	cmd: CommandBuffer,
	buffer: vk.Buffer,
	offset: vk.DeviceSize,
	indexType: vk.IndexType,
) {
	vk.CmdBindIndexBuffer(cmd.__handle, buffer, offset, indexType)
}

// 드로우
graphics_cmd_draw :: #force_inline proc "contextless" (
	cmd: CommandBuffer,
	vertexCount: u32,
	instanceCount: u32,
	firstVertex: u32,
	firstInstance: u32,
) {
	vk.CmdDraw(cmd.__handle, vertexCount, instanceCount, firstVertex, firstInstance)
}

// 인덱스 드로우
graphics_cmd_draw_indexed :: #force_inline proc "contextless" (
	cmd: CommandBuffer,
	indexCount: u32,
	instanceCount: u32,
	firstIndex: u32,
	vertexOffset: i32,
	firstInstance: u32,
) {
	vk.CmdDrawIndexed(cmd.__handle, indexCount, instanceCount, firstIndex, vertexOffset, firstInstance)
}


@private CalcFrameTime :: proc(Paused_: bool) {
	@static start:time.Time
	@static now:time.Time

	if !loopStart {
		loopStart = true
		start = time.now()
		now = start
	} else {
		maxFrame_ := engine.GetMaxFrame()
		if Paused_ && maxFrame_ == 0 {
			maxFrame_ = 60
		}
		n := time.now()
		delta := n._nsec - now._nsec

		if maxFrame_ > 0 {
			maxF := u64(1 * (1 / maxFrame_)) * 1000000000
			if maxF > auto_cast delta {
				time.sleep(auto_cast (i64(maxF) - delta))
				n = time.now()
				delta = n._nsec - now._nsec
			}
		}
		now = n
		deltaTime = auto_cast delta
	}
}

allocate_command_buffers :: proc(pCmdBuffer:[^]CommandBuffer, count:u32) {
    allocInfo := vk.CommandBufferAllocateInfo{
        sType = vk.StructureType.COMMAND_BUFFER_ALLOCATE_INFO,
        commandPool = vkCmdPool,
        level = vk.CommandBufferLevel.PRIMARY,
        commandBufferCount = count,
    }
    res := vk.AllocateCommandBuffers(graphics_Device, &allocInfo, auto_cast pCmdBuffer)
    if res != .SUCCESS do trace.panic_log("res = vk.AllocateCommandBuffers(graphics_Device, &allocInfo, &cmd.cmds[i][0]) : ", res)
}
free_command_buffers :: proc(pCmdBuffer:[^]CommandBuffer, count:u32) {
    vk.FreeCommandBuffers(graphics_Device, vkCmdPool, count, auto_cast pCmdBuffer)
}

RenderLoop :: proc() {
	Paused_ := engine.Paused()

	CalcFrameTime(Paused_)
	
	engine.Update()
	if engine.__gMainRenderCmdIdx >= 0 {
		for obj in engine.__gRenderCmd[engine.__gMainRenderCmdIdx].scene {
			engine.IObject_Update(auto_cast obj)
		}
	}

	if !Paused_ {
		graphics_draw_frame()
	}
}

create_graphics_pipeline :: proc(self:^engine.custom_object_pipeline,
    stages: []vk.PipelineShaderStageCreateInfo,
    depth_stencil_state: ^vk.PipelineDepthStencilStateCreateInfo,
    viewportState: ^vk.PipelineViewportStateCreateInfo,
    vertexInputState: ^vk.PipelineVertexInputStateCreateInfo) -> bool {

    pipelineCreateInfo := vk.GraphicsPipelineCreateInfoInit(
        stages = stages,
        layout = self.__pipeline_layout,
        pDepthStencilState = depth_stencil_state,
        pViewportState = viewportState,
        pVertexInputState = vertexInputState,
        renderPass = vkRenderPass,
        pMultisampleState = &vkPipelineMultisampleStateCreateInfo,
        pColorBlendState = &vk.DefaultPipelineColorBlendStateCreateInfo,
    )

    res := vk.CreateGraphicsPipelines(graphics_Device, 0, 1, &pipelineCreateInfo, nil, &self.__pipeline)
    if res != .SUCCESS {
		trace.printlnLog("create_graphics_pipeline: Failed to create graphics pipeline:", res)
        return false
	}
    return true

}

get_graphics_origin_format :: proc "contextless" () -> vk.Format {
    return vkFmt.format
}

depthFmt : TextureFmt