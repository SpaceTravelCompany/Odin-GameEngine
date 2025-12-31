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


custom_object_draw_type :: enum {
    Draw,
    DrawIndexed,
}

custom_object_draw_method :: struct {
    type:custom_object_draw_type,
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

custom_object_pipeline :: struct {
    check_init: mem.ICheckInit,

    __pipeline:vk.Pipeline,
    __pipeline_layout:vk.PipelineLayout,
    __descriptor_set_layouts:[]vk.DescriptorSetLayout,
    __pool_binding:[][]u32,//! auto generate inside, engine_def_allocator

    draw_method:custom_object_draw_method,
    pool_sizes:[][]descriptor_pool_size,
}

custom_object :: struct {
    using _:iobject,
    p_pipeline:^custom_object_pipeline,
    pipeline_set_idx:int, // The index of the pipeline set to use for this object.
    pipeline_p_sets:[]^descriptor_set
}

custom_object_pipeline_deinit :: proc(self:^custom_object_pipeline) {
    mem.ICheckInit_Deinit(&self.check_init)

    for l in self.__descriptor_set_layouts {
        vk.DestroyDescriptorSetLayout(graphics_device, l, nil)
    }
    for p in self.__pool_binding {
        delete(p, engine_def_allocator)
    }
    for p in self.pool_sizes {
        delete(p, engine_def_allocator)
    }
    vk.DestroyPipelineLayout(graphics_device, self.__pipeline_layout, nil)
    vk.DestroyPipeline(graphics_device, self.__pipeline, nil)
    delete(self.pool_sizes, engine_def_allocator)
    delete(self.__descriptor_set_layouts, engine_def_allocator)
    delete(self.__pool_binding, engine_def_allocator)
}

shader_optimization_level :: shaderc.optimizationLevel

descriptor_set_layout_binding :: vk.DescriptorSetLayoutBinding
vertex_input_binding_description :: vk.VertexInputBindingDescription
vertex_input_attribute_description :: vk.VertexInputAttributeDescription

shader_code :: struct {
    code : shader_code_fmt,
    entry_point : cstring,
    input_file_name : cstring,
    optimize:shader_optimization_level,
}

shader_code_fmt :: union {
    []byte,
    cstring,
}

shader_lang :: enum {
    GLSL,
    HLSL,
}


descriptor_set_layout_binding_init :: vk.DescriptorSetLayoutBindingInit

custom_object_pipeline_init :: proc(self:^custom_object_pipeline,
    binding_set_layouts:[][]descriptor_set_layout_binding,
    vertex_input_binding:Maybe([]vertex_input_binding_description),
    vertex_input_attribute:Maybe([]vertex_input_attribute_description),
    draw_method:custom_object_draw_method,
    pool_sizes:[][]descriptor_pool_size,
    vertex_shader:Maybe(shader_code),
    pixel_shader:Maybe(shader_code),
    geometry_shader:Maybe(shader_code) = nil,
    shader_lang:shader_lang = .GLSL,
    depth_stencil_state:Maybe(vk.PipelineDepthStencilStateCreateInfo) = nil) -> bool {
    mem.ICheckInit_Init(&self.check_init)

    self.draw_method = draw_method
    self.pool_sizes = mem.make_non_zeroed_slice([][]descriptor_pool_size, len(pool_sizes), engine_def_allocator)
    for &p, i in self.pool_sizes {
        p = mem.make_non_zeroed_slice([]descriptor_pool_size, len(pool_sizes[i]), engine_def_allocator)
        mem.copy_non_overlapping(&self.pool_sizes[i][0], &pool_sizes[i][0], len(pool_sizes[i]) * size_of(descriptor_pool_size))
    }
    
    self.__pool_binding = mem.make_non_zeroed_slice([][]u32, len(pool_sizes), engine_def_allocator)
    for &b, i in self.__pool_binding {
        b = mem.make_non_zeroed_slice([]u32, len(pool_sizes[i]), engine_def_allocator)
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
                vk.DestroyShaderModule(graphics_device, s, nil)
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
            shader_modules[i] = vk.CreateShaderModule2(graphics_device, shader_bytes)
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

    self.__descriptor_set_layouts = mem.make_non_zeroed_slice([]vk.DescriptorSetLayout, len(binding_set_layouts), engine_def_allocator)
    for &l, i in self.__descriptor_set_layouts {
        l = vk.DescriptorSetLayoutInit(graphics_device, binding_set_layouts[i])
    }
    self.__pipeline_layout = vk.PipelineLayoutInit(graphics_device, self.__descriptor_set_layouts)

    vertexInputState:Maybe(vk.PipelineVertexInputStateCreateInfo)
    if vertex_input_binding != nil && vertex_input_attribute != nil {
        vertexInputState = vk.PipelineVertexInputStateCreateInfoInit(vertex_input_binding.?, vertex_input_attribute.?)
    } else {
        vertexInputState = nil
    }

    if !create_graphics_pipeline(self,
        shaderCreateInfo[:shaderCreateInfoLen],
        &depth_stencil_state2,
        &viewportState,
        vertexInputState == nil ? nil : &vertexInputState.?) {
        return false
    }
    return true
}

@private custom_object_vtable :iobject_vtable = iobject_vtable{
    draw = auto_cast _super_custom_object_draw,
    deinit = auto_cast _super_custom_object_deinit,
}

custom_object_init :: proc(self:^custom_object, $actual_type:typeid,
    p_pipeline:^custom_object_pipeline,
    pipeline_p_sets:[]^descriptor_set,
    pipeline_set_idx:int = 0,
    pos:linalg.Point3DF, rotation:f32, scale:linalg.PointF = {1,1},
    camera:^camera, projection:^projection, color_transform:^color_transform = nil, pivot:linalg.PointF = {0.0, 0.0}, vtable:^iobject_vtable = nil)
    where intrinsics.type_is_subtype_of(actual_type, custom_object) {

    self.pipeline_p_sets = mem.make_non_zeroed_slice([]^descriptor_set, len(pipeline_p_sets), engine_def_allocator)
    mem.copy_non_overlapping(&self.pipeline_p_sets[0], &pipeline_p_sets[0], len(pipeline_p_sets) * size_of(^descriptor_set))

    self.p_pipeline = p_pipeline
    self.pipeline_set_idx = pipeline_set_idx
    
    self.set.bindings = p_pipeline.__pool_binding[pipeline_set_idx]
    self.set.size = p_pipeline.pool_sizes[pipeline_set_idx]
    self.set.layout = p_pipeline.__descriptor_set_layouts[pipeline_set_idx]

    self.vtable = vtable == nil ? &custom_object_vtable : vtable
    if self.vtable.draw == nil do self.vtable.draw = auto_cast _super_custom_object_draw
    if self.vtable.deinit == nil do self.vtable.deinit = auto_cast _super_custom_object_deinit

    if self.vtable.get_uniform_resources == nil do self.vtable.get_uniform_resources = auto_cast get_uniform_resources_default

    iobject_init(self, actual_type, pos, rotation, scale, camera, projection, color_transform, pivot)
}


create_buffer_resource :: #force_inline proc(self:^buffer_resource, option:buffer_create_option, data:[]byte, is_copy:bool, allocator:Maybe(runtime.Allocator) = nil) {
    buffer_resource_create_buffer(self, option, data, is_copy, allocator)
}


_super_custom_object_deinit :: proc(self:^custom_object) {
    _super_iobject_deinit(auto_cast self)

    delete(self.pipeline_p_sets, engine_def_allocator)
}

_super_custom_object_draw :: proc(self:^custom_object, cmd:command_buffer) {
    mem.ICheckInit_Check(&self.check_init)

    sets := mem.make_non_zeroed_slice([]vk.DescriptorSet, len(self.pipeline_p_sets), engine_def_allocator)
    defer delete(sets, engine_def_allocator)
    for i in 0..<len(self.pipeline_p_sets) {
        sets[i] = self.pipeline_p_sets[i].__set
    }

    graphics_cmd_bind_pipeline(cmd, .GRAPHICS, self.p_pipeline.__pipeline)
    graphics_cmd_bind_descriptor_sets(cmd, .GRAPHICS, self.p_pipeline.__pipeline_layout, 0, auto_cast len(self.pipeline_p_sets),
        &sets[0], 0, nil)

    if self.p_pipeline.draw_method.type == .Draw {
        graphics_cmd_draw(cmd, self.p_pipeline.draw_method.vertex_count, self.p_pipeline.draw_method.instance_count, self.p_pipeline.draw_method.first_vertex, self.p_pipeline.draw_method.first_instance)
    } else if self.p_pipeline.draw_method.type == .DrawIndexed {
        graphics_cmd_draw_indexed(cmd, self.p_pipeline.draw_method.index_count, self.p_pipeline.draw_method.instance_count, self.p_pipeline.draw_method.first_index, self.p_pipeline.draw_method.vertex_offset, self.p_pipeline.draw_method.first_instance)
    }
}