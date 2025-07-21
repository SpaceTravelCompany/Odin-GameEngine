//using custom shader
package engine

import "core:math"
import "core:mem"
import "core:fmt"
import "core:slice"
import "core:sync"
import "core:thread"
import "core:debug/trace"
import "core:math/linalg"
import "base:intrinsics"
import "base:runtime"
import vk "vendor:vulkan"
import "core:mem/virtual"
import "vendor:shaderc"

@(private = "file") custom_object_allocator:runtime.Allocator
@(private = "file") __arena: virtual.Arena

@(private="file", init)
custom_object_allocator_start :: proc() {
    _ = virtual.arena_init_growing(&__arena)
    __allocator := virtual.arena_allocator(&__arena)
    mtx_allocator : mem.Mutex_Allocator
	mem.mutex_allocator_init(&mtx_allocator, __allocator)
    custom_object_allocator = mem.mutex_allocator(&mtx_allocator)
}
@(private="file", fini)
custom_object_allocator_finish :: proc() {
    virtual.arena_destroy(&__arena)
}


custom_object_DescriptorType :: enum {
    SAMPLER,  //vk.DescriptorType.COMBINED_IMAGE_SAMPLER
    UNIFORM_DYNAMIC,  //vk.DescriptorType.UNIFORM_BUFFER_DYNAMIC
    UNIFORM,  //vk.DescriptorType.UNIFORM_BUFFER
    STORAGE,
    STORAGE_IMAGE,//TODO (xfitgd)
}
custom_object_DescriptorPoolSize :: struct {type:custom_object_DescriptorType, cnt:u32}

custom_object_draw_type :: enum {
    Draw,
    DrawIndexed,
}

custom_object_draw_method :: struct {
    type:custom_object_draw_type,
    vertexCount:u32,
    instanceCount:u32,
    indexCount:u32,
}

custom_object_pipeline :: struct {
    checkInit: mem.ICheckInit,

    __pipeline:vk.Pipeline,
    __pipeline_layout:vk.PipelineLayout,
    __descriptor_set_layouts:[]vk.DescriptorSetLayout,
    __pool_binding:[]u32,//! auto generate inside, custom_object_allocator

    draw_method:custom_object_draw_method,
    pool_sizes:[]custom_object_DescriptorPoolSize,
}

custom_object :: struct {
    using _:IObject,
    pPipeline:^custom_object_pipeline,
}

custom_object_pipeline_deinit :: proc(self:^custom_object_pipeline) {
    mem.ICheckInit_Deinit(&self.checkInit)

    for l in self.__descriptor_set_layouts {
        vk.DestroyDescriptorSetLayout(vkDevice, l, nil)
    }
    vk.DestroyPipelineLayout(vkDevice, self.__pipeline_layout, nil)
    vk.DestroyPipeline(vkDevice, self.__pipeline, nil)
    delete(self.pool_sizes, custom_object_allocator)
    delete(self.__descriptor_set_layouts, custom_object_allocator)
    delete(self.__pool_binding, custom_object_allocator)
}

shader_code :: struct {
    code : shader_code_fmt,
    entry_point : cstring,
    input_file_name : cstring,
}

shader_code_fmt :: union {
    []byte,
    cstring,
}

shader_lang :: enum {
    GLSL,
    HLSL,
}

custom_object_pipeline_init :: proc(self:^custom_object_pipeline,
    binding_set_layouts:[][]vk.DescriptorSetLayoutBinding,
    vertex_input_binding:Maybe([]vk.VertexInputBindingDescription),
    vertex_input_attribute:Maybe([]vk.VertexInputAttributeDescription),
    draw_method:custom_object_draw_method,
    pool_sizes:[]custom_object_DescriptorPoolSize,
    vertex_shader:Maybe(shader_code),
    pixel_shader:Maybe(shader_code),
    geometry_shader:Maybe(shader_code),
    shader_lang:shader_lang = .GLSL,
    depth_stencil_state:Maybe(vk.PipelineDepthStencilStateCreateInfo) = nil) -> bool {
    mem.ICheckInit_Init(&self.checkInit)

    self.draw_method = draw_method
    self.pool_sizes = mem.make_non_zeroed_slice([]custom_object_DescriptorPoolSize, len(pool_sizes), custom_object_allocator)
    mem.copy_non_overlapping(&self.pool_sizes[0], &pool_sizes[0], len(pool_sizes) * size_of(custom_object_DescriptorPoolSize))

    shaders := [?]Maybe(shader_code){vertex_shader, pixel_shader, geometry_shader}
    shader_kinds := [?]shaderc.shaderKind{.VertexShader, .FragmentShader, .GeometryShader}
    shader_vkflags := [?]vk.ShaderStageFlags{{.VERTEX}, {.FRAGMENT}, {.GEOMETRY}}
    shader_res : [len(shaders)]shaderc.compilationResultT
    shader_modules : [len(shaders)]vk.ShaderModule

    if vertex_shader == nil || pixel_shader == nil {
        trace.panic_log("custom_object_pipeline_init: vertex_shader and pixel_shader cannot be nil")
    }
    defer #unroll for i in 0..<len(shader_res) {
        if shader_res[i] != nil {
            shaderc.result_release(shader_res[i])
        }
    }
    #unroll for i in 0..<len(shaders) {
        shader_bytes:[]byte
        if shaders[i] != nil {
            switch s in shaders[i].?.code {
                case cstring:
                    shader_compiler := shaderc.compiler_initialize()
                    shader_compiler_options := shaderc.compile_options_initialize()
                    if shader_lang == .HLSL {
                        shaderc.compile_options_set_source_language(shader_compiler_options, .Hlsl)
                    }
                    defer shaderc.compile_options_release(shader_compiler_options)
                    defer shaderc.compiler_release(shader_compiler)
                    
                    result := shaderc.compile_into_spv(
                        shader_compiler,
                        s,
                        len(s),
                        shader_kinds[i],
                        shaders[i].?.input_file_name,
                        shaders[i].?.entry_point,
                        shader_compiler_options,
                    )
                    if (shaderc.result_get_compilation_status(result) != shaderc.compilationStatus.Success) {
                        trace.printlnLog(shaderc.result_get_error_message(result))
                        return false
                    }

                    lenn := shaderc.result_get_length(result)
                    bytes := shaderc.result_get_bytes(result)
                    shader_bytes := transmute([]byte)bytes[:lenn]
                    shader_res[i] = result
                case []byte:
                    shader_bytes = s
            }
            shader_modules[i] = vk.CreateShaderModule2(vkDevice, shader_bytes)
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

    depth_stencil_state2 := depth_stencil_state == nil ? vk.PipelineDepthStencilStateCreateInfoInit() : depth_stencil_state.?
    viewportState := vk.PipelineViewportStateCreateInfoInit()

    self.__descriptor_set_layouts = mem.make_non_zeroed_slice([]vk.DescriptorSetLayout, len(binding_set_layouts), custom_object_allocator)
    for &l, i in self.__descriptor_set_layouts {
        l = vk.DescriptorSetLayoutInit(vkDevice, binding_set_layouts[i])
    }
    self.__pipeline_layout = vk.PipelineLayoutInit(vkDevice, self.__descriptor_set_layouts)

    vertexInputState:Maybe(vk.PipelineVertexInputStateCreateInfo)
    if vertex_input_binding != nil && vertex_input_attribute != nil {
        vertexInputState = vk.PipelineVertexInputStateCreateInfoInit(vertex_input_binding.?, vertex_input_attribute.?)
    } else {
        vertexInputState = nil
    }

    pipelineCreateInfo := vk.GraphicsPipelineCreateInfoInit(
        stages = shaderCreateInfo[:shaderCreateInfoLen],
        layout = self.__pipeline_layout,
        renderPass = vkRenderPass,
        pMultisampleState = &vkPipelineMultisampleStateCreateInfo,
        pDepthStencilState = &depth_stencil_state2,
        pColorBlendState = &vk.DefaultPipelineColorBlendStateCreateInfo,
        pViewportState = &viewportState,
        pVertexInputState = vertexInputState == nil ? nil : &vertexInputState.?,
    )

    res := vk.CreateGraphicsPipelines(vkDevice, 0, 1, &pipelineCreateInfo, nil, &self.__pipeline)
    if res != .SUCCESS {
		trace.printlnLog("custom_object_pipeline_init: Failed to create graphics pipeline:", res)
        return false
	}
    return true
}