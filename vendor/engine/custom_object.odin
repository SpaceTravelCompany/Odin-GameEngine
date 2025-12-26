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
import graphics_api "./graphics_api"
import "vendor:shaderc"


custom_object_draw_type :: enum {
    Draw,
    DrawIndexed,
}

custom_object_draw_method :: struct {
    type:custom_object_draw_type,
    vertexCount:u32,
    instanceCount:u32,
    indexCount:u32,
    using _:struct #raw_union {
        firstVertex:u32,
        vertexOffset:i32,
    },
    firstInstance:u32,
    firstIndex:u32,
}

custom_object_pipeline :: struct {
    checkInit: mem.ICheckInit,

    __pipeline:vk.Pipeline,
    __pipeline_layout:vk.PipelineLayout,
    __descriptor_set_layouts:[]vk.DescriptorSetLayout,
    __pool_binding:[][]u32,//! auto generate inside, engineDefAllocator

    draw_method:custom_object_draw_method,
    pool_sizes:[][]graphics_api.custom_object_DescriptorPoolSize,
}

custom_object :: struct {
    using _:IObject,
    pPipeline:^custom_object_pipeline,
    pipeline_set_idx:int, // The index of the pipeline set to use for this object.
    pipeline_pSets:[]^graphics_api.DescriptorSet
}

custom_object_pipeline_deinit :: proc(self:^custom_object_pipeline) {
    mem.ICheckInit_Deinit(&self.checkInit)

    for l in self.__descriptor_set_layouts {
        vk.DestroyDescriptorSetLayout(graphics_api.graphics_Device, l, nil)
    }
    for p in self.__pool_binding {
        delete(p, graphics_api.engineDefAllocator)
    }
    for p in self.pool_sizes {
        delete(p, graphics_api.engineDefAllocator)
    }
    vk.DestroyPipelineLayout(graphics_api.graphics_Device, self.__pipeline_layout, nil)
    vk.DestroyPipeline(graphics_api.graphics_Device, self.__pipeline, nil)
    delete(self.pool_sizes, graphics_api.engineDefAllocator)
    delete(self.__descriptor_set_layouts, graphics_api.engineDefAllocator)
    delete(self.__pool_binding, graphics_api.engineDefAllocator)
}

shader_optimizationLevel :: shaderc.optimizationLevel

shader_code :: struct {
    code : shader_code_fmt,
    entry_point : cstring,
    input_file_name : cstring,
    optimize:shader_optimizationLevel,
}

shader_code_fmt :: union {
    []byte,
    cstring,
}

shader_lang :: enum {
    GLSL,
    HLSL,
}

DescriptorSetLayoutBinding :: vk.DescriptorSetLayoutBinding
DescriptorType :: vk.DescriptorType
ShaderStageFlags :: vk.ShaderStageFlags
VertexInputBindingDescription :: vk.VertexInputBindingDescription
VertexInputAttributeDescription :: vk.VertexInputAttributeDescription
VertexInputRate :: vk.VertexInputRate
Format :: vk.Format
DescriptorSetLayoutBindingInit :: vk.DescriptorSetLayoutBindingInit

custom_object_pipeline_init :: proc(self:^custom_object_pipeline,
    binding_set_layouts:[][]DescriptorSetLayoutBinding,
    vertex_input_binding:Maybe([]VertexInputBindingDescription),
    vertex_input_attribute:Maybe([]VertexInputAttributeDescription),
    draw_method:custom_object_draw_method,
    pool_sizes:[][]graphics_api.custom_object_DescriptorPoolSize,
    vertex_shader:Maybe(shader_code),
    pixel_shader:Maybe(shader_code),
    geometry_shader:Maybe(shader_code) = nil,
    shader_lang:shader_lang = .GLSL,
    depth_stencil_state:Maybe(vk.PipelineDepthStencilStateCreateInfo) = nil) -> bool {
    mem.ICheckInit_Init(&self.checkInit)

    self.draw_method = draw_method
    self.pool_sizes = mem.make_non_zeroed_slice([][]graphics_api.custom_object_DescriptorPoolSize, len(pool_sizes), graphics_api.engineDefAllocator)
    for &p, i in self.pool_sizes {
        p = mem.make_non_zeroed_slice([]graphics_api.custom_object_DescriptorPoolSize, len(pool_sizes[i]), graphics_api.engineDefAllocator)
        mem.copy_non_overlapping(&self.pool_sizes[i][0], &pool_sizes[i][0], len(pool_sizes[i]) * size_of(graphics_api.custom_object_DescriptorPoolSize))
    }
    
    self.__pool_binding = mem.make_non_zeroed_slice([][]u32, len(pool_sizes), graphics_api.engineDefAllocator)
    for &b, i in self.__pool_binding {
        b = mem.make_non_zeroed_slice([]u32, len(pool_sizes[i]), graphics_api.engineDefAllocator)
        b[0] = 0 // The first binding is always 0, as it is the default binding for the descriptor set.
        pool_idx :u32 = 0
        for j in 1..<len(pool_sizes[i]) {
            pool_idx += pool_sizes[i][j - 1].cnt
            b[j] = pool_idx
        }
    }

    shaders := [?]Maybe(shader_code){vertex_shader, pixel_shader, geometry_shader}
    shader_kinds := [?]shaderc.shaderKind{.VertexShader, .FragmentShader, .GeometryShader}
    shader_vkflags := [?]vk.ShaderStageFlags{{.VERTEX}, {.FRAGMENT}, {.GEOMETRY}}
    shader_res : [len(shaders)]shaderc.compilationResultT
    shader_modules : [len(shaders)]vk.ShaderModule
    defer {
        for s in shader_modules {
            if s != 0 {
                vk.DestroyShaderModule(graphics_api.graphics_Device, s, nil)
            }
        }
    }

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
                    if shaders[i].?.optimize != .Zero {
                        shaderc.compile_options_set_optimization_level(shader_compiler_options, shaders[i].?.optimize)
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
                    shader_bytes = transmute([]byte)bytes[:lenn]
                    shader_res[i] = result
                case []byte:
                    shader_bytes = s
            }
            shader_modules[i] = vk.CreateShaderModule2(graphics_api.graphics_Device, shader_bytes)
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

    self.__descriptor_set_layouts = mem.make_non_zeroed_slice([]vk.DescriptorSetLayout, len(binding_set_layouts), graphics_api.engineDefAllocator)
    for &l, i in self.__descriptor_set_layouts {
        l = vk.DescriptorSetLayoutInit(graphics_api.graphics_Device, binding_set_layouts[i])
    }
    self.__pipeline_layout = vk.PipelineLayoutInit(graphics_api.graphics_Device, self.__descriptor_set_layouts)

    vertexInputState:Maybe(vk.PipelineVertexInputStateCreateInfo)
    if vertex_input_binding != nil && vertex_input_attribute != nil {
        vertexInputState = vk.PipelineVertexInputStateCreateInfoInit(vertex_input_binding.?, vertex_input_attribute.?)
    } else {
        vertexInputState = nil
    }

    if !graphics_api.create_graphics_pipeline(self,
        shaderCreateInfo[:shaderCreateInfoLen],
        &depth_stencil_state2,
        &viewportState,
        vertexInputState == nil ? nil : &vertexInputState.?) {
        return false
    }
    return true
}

@private custom_object_VTable :IObjectVTable = IObjectVTable{
    Draw = auto_cast _super_custom_object_draw,
    Deinit = auto_cast _super_custom_object_deinit,
}

custom_object_init :: proc(self:^custom_object, $actualType:typeid,
    pPipeline:^custom_object_pipeline,
    pipeline_pSets:[]^graphics_api.DescriptorSet,
    pipeline_set_idx:int = 0,
    pos:linalg.Point3DF, rotation:f32, scale:linalg.PointF = {1,1},
    camera:^Camera, projection:^Projection, colorTransform:^ColorTransform = nil, pivot:linalg.PointF = {0.0, 0.0}, vtable:^IObjectVTable = nil)
    where intrinsics.type_is_subtype_of(actualType, custom_object) {

    self.pipeline_pSets = mem.make_non_zeroed_slice([]^graphics_api.DescriptorSet, len(pipeline_pSets), graphics_api.engineDefAllocator)
    mem.copy_non_overlapping(&self.pipeline_pSets[0], &pipeline_pSets[0], len(pipeline_pSets) * size_of(^graphics_api.DescriptorSet))

    self.pPipeline = pPipeline
    self.pipeline_set_idx = pipeline_set_idx
    
    self.set.bindings = pPipeline.__pool_binding[pipeline_set_idx]
    self.set.size = pPipeline.pool_sizes[pipeline_set_idx]
    self.set.layout = pPipeline.__descriptor_set_layouts[pipeline_set_idx]

    self.vtable = vtable == nil ? &custom_object_VTable : vtable
    if self.vtable.Draw == nil do self.vtable.Draw = auto_cast _super_custom_object_draw
    if self.vtable.Deinit == nil do self.vtable.Deinit = auto_cast _super_custom_object_deinit

    if self.vtable.GetUniformResources == nil do self.vtable.GetUniformResources = auto_cast GetUniformResources_Default

    IObject_Init(self, actualType, pos, rotation, scale, camera, projection, colorTransform, pivot)
}


CreateBufferResource :: #force_inline proc(self:^graphics_api.BufferResource, option:graphics_api.BufferCreateOption, data:[]byte, isCopy:bool, allocator:Maybe(runtime.Allocator) = nil) {
    graphics_api.BufferResource_CreateBuffer(self, option, data, isCopy, allocator)
}
BufferResource_CopyUpdate :: #force_inline proc(self:^graphics_api.BufferResource, data:^$T, allocator:Maybe(runtime.Allocator) = nil) {
    graphics_api.BufferResource_CopyUpdate(self, data, allocator)
}
BufferResource_Deinit :: #force_inline proc(self:^graphics_api.BufferResource) {
    graphics_api.BufferResource_Deinit(self)
}


_super_custom_object_deinit :: proc(self:^custom_object) {
    _Super_IObject_Deinit(auto_cast self)

    delete(self.pipeline_pSets, graphics_api.engineDefAllocator)
}

_super_custom_object_draw :: proc(self:^custom_object, cmd:graphics_api.CommandBuffer) {
    mem.ICheckInit_Check(&self.checkInit)

    sets := mem.make_non_zeroed_slice([]vk.DescriptorSet, len(self.pipeline_pSets), graphics_api.engineDefAllocator)
    defer delete(sets, graphics_api.engineDefAllocator)
    for i in 0..<len(self.pipeline_pSets) {
        sets[i] = self.pipeline_pSets[i].__set
    }

    graphics_api.graphics_cmd_bind_pipeline(cmd, .GRAPHICS, self.pPipeline.__pipeline)
    graphics_api.graphics_cmd_bind_descriptor_sets(cmd, .GRAPHICS, self.pPipeline.__pipeline_layout, 0, auto_cast len(self.pipeline_pSets),
        &sets[0], 0, nil)

    if self.pPipeline.draw_method.type == .Draw {
        graphics_api.graphics_cmd_draw(cmd, self.pPipeline.draw_method.vertexCount, self.pPipeline.draw_method.instanceCount, self.pPipeline.draw_method.firstVertex, self.pPipeline.draw_method.firstInstance)
    } else if self.pPipeline.draw_method.type == .DrawIndexed {
        graphics_api.graphics_cmd_draw_indexed(cmd, self.pPipeline.draw_method.indexCount, self.pPipeline.draw_method.instanceCount, self.pPipeline.draw_method.firstIndex, self.pPipeline.draw_method.vertexOffset, self.pPipeline.draw_method.firstInstance)
    }
}