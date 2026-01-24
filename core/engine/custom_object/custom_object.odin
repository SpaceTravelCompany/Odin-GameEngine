package custom_object

import "base:intrinsics"
import "base:runtime"
import "core:c"
import "core:debug/trace"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:mem/virtual"
import "core:slice"
import "core:sync"
import "core:thread"
import vk "vendor:vulkan"
import "vendor:glslang"
import "core:engine"



/*
Custom object structure for rendering with custom shaders

Extends iobject with custom pipeline and descriptor sets
*/
custom_object :: struct {
    using _:engine.itransform_object,
    p_pipeline:^object_pipeline,
    pipeline_set_idx:int, // The index of the pipeline set to use for this 
    pipeline_p_sets:[]^engine.descriptor_set
}

descriptor_set_layout_binding :: vk.DescriptorSetLayoutBinding
vertex_input_binding_description :: vk.VertexInputBindingDescription
vertex_input_attribute_description :: vk.VertexInputAttributeDescription

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

descriptor_set_layout_binding_init :: vk.DescriptorSetLayoutBindingInit


/*
Deinitializes and cleans up custom object pipeline resources

Inputs:
- self: Pointer to the pipeline to deinitialize

Returns:
- None
*/
custom_object_pipeline_deinit :: proc(self:^object_pipeline) {
    for l in self.__descriptor_set_layouts {
        vk.DestroyDescriptorSetLayout(engine.graphics_device(), l, nil)
    }
    for p in self.__pool_binding {
        delete(p)
    }
    for p in self.pool_sizes {
        delete(p)
    }
    vk.DestroyPipelineLayout(engine.graphics_device(), self.__pipeline_layout, nil)
    vk.DestroyPipeline(engine.graphics_device(), self.__pipeline, nil)
    delete(self.pool_sizes)
    delete(self.__descriptor_set_layouts)
    delete(self.__pool_binding)
}

/*
Initializes a custom object pipeline with shaders

Inputs:
- self: Pointer to the pipeline to initialize
- binding_set_layouts: Descriptor set layout bindings
- vertex_input_binding: Vertex input binding descriptions
- vertex_input_attribute: Vertex input attribute descriptions
- draw_method: Draw method configuration
- pool_sizes: Descriptor pool sizes
- vertex_shader: Vertex shader code
- pixel_shader: Pixel shader code
- geometry_shader: Geometry shader code (default: nil)
- shader_lang: Shader language (default: .GLSL)
- depth_stencil_state: Depth stencil state (default: nil)

Returns:
- `true` if initialization succeeded, `false` otherwise
*/
custom_object_pipeline_init :: proc(self:^object_pipeline,
    binding_set_layouts:[][]descriptor_set_layout_binding,
    vertex_input_binding:Maybe([]vertex_input_binding_description),
    vertex_input_attribute:Maybe([]vertex_input_attribute_description),
    draw_method:object_draw_method,
    pool_sizes:[][]engine.descriptor_pool_size,
    vertex_shader:Maybe(shader_code),
    pixel_shader:Maybe(shader_code),
    geometry_shader:Maybe(shader_code) = nil,
    shader_lang:shader_lang = .GLSL,
    depth_stencil_state:Maybe(vk.PipelineDepthStencilStateCreateInfo) = nil) -> bool {

    self.draw_method = draw_method
    self.pool_sizes = mem.make_non_zeroed_slice([][]engine.descriptor_pool_size, len(pool_sizes))
    for &p, i in self.pool_sizes {
        p = mem.make_non_zeroed_slice([]engine.descriptor_pool_size, len(pool_sizes[i]))
        mem.copy_non_overlapping(&self.pool_sizes[i][0], &pool_sizes[i][0], len(pool_sizes[i]) * size_of(engine.descriptor_pool_size))
    }
    
    self.__pool_binding = mem.make_non_zeroed_slice([][]u32, len(pool_sizes))
    for &b, i in self.__pool_binding {
        b = mem.make_non_zeroed_slice([]u32, len(pool_sizes[i]))
        b[0] = 0 // The first binding is always 0, as it is the default binding for the descriptor set.
        pool_idx :u32 = 0
        for j in 1..<len(pool_sizes[i]) {
            pool_idx += pool_sizes[i][j - 1].cnt
            b[j] = pool_idx
        }
    }

    shaders := [?]Maybe(shader_code){vertex_shader, pixel_shader, geometry_shader}
    shader_kinds := [?]glslang.Shader_Stage{.VERTEX, .FRAGMENT, .GEOMETRY}
    shader_vkflags := [?]vk.ShaderStageFlags{{.VERTEX}, {.FRAGMENT}, {.GEOMETRY}}
    shader_programs : [len(shaders)]^glslang.Program
    shader_modules : [len(shaders)]vk.ShaderModule
    defer {
        for s in shader_modules {
            if s != 0 {
                vk.DestroyShaderModule(engine.graphics_device(), s, nil)
            }
        }
    }

    if vertex_shader == nil || pixel_shader == nil {
        trace.panic_log("custom_object_pipeline_init: vertex_shader and pixel_shader cannot be nil")
    }
    
    //!NEED TEST
    // glslang 초기화 (한 번만 호출)
    if glslang.initialize_process() == 0 {
        trace.printlnLog("custom_object_pipeline_init: glslang initialization failed")
        return false
    }
    defer glslang.finalize_process()
    
    defer for i in 0..<len(shader_programs) {
        if shader_programs[i] != nil {
            glslang.program_delete(shader_programs[i])
        }
    }
    for i in 0..<len(shaders) {
        shader_bytes:[]byte
        if shaders[i] != nil {
            switch s in shaders[i].?.code {
                case cstring:
                    // Input 구조체 설정
                    input := glslang.Input{
                        language = shader_lang == .HLSL ? glslang.Source.HLSL : glslang.Source.GLSL,
                        stage = shader_kinds[i],
                        client = glslang.Client.VULKAN,
                        client_version = glslang.Target_Client_Version.VULKAN_1_2,
                        target_language = glslang.Target_Language.SPV,
                        target_language_version = glslang.Target_Language_Version.SPV_1_5,
                        code = s,
                        default_version = 100,
                        default_profile = glslang.Profile.NO_PROFILE,
                        force_default_version_and_profile = 0,
                        forward_compatible = 0,
                        messages = glslang.Messages.DEFAULT_BIT,
                        resource = glslang.default_resource(),
                        callbacks = {},
                        callbacks_ctx = nil,
                    }
                    
                    // 셰이더 생성 및 파싱
                    shader := glslang.shader_create(&input)
                    if shader == nil {
                        trace.printlnLog("custom_object_pipeline_init: failed to create shader")
                        return false
                    }
                    defer glslang.shader_delete(shader)
                    
                    // Entry point 설정
                    if shaders[i].?.entry_point != nil {
                        glslang.shader_set_entry_point(shader, shaders[i].?.entry_point)
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
                    glslang.program_SPIRV_generate_with_options(program, shader_kinds[i], &spv_options)
                    
                    // SPIR-V 데이터 가져오기
                    spirv_size := glslang.program_SPIRV_get_size(program)
                    spirv_data, alloc_err := mem.alloc(cast(int)(size_of(u32) * spirv_size), align_of(u32))
                    if alloc_err != nil {
                        trace.printlnLog("custom_object_pipeline_init: failed to allocate memory for SPIR-V")
                        return false
                    }
                    defer mem.free(spirv_data)
                    glslang.program_SPIRV_get(program, cast(^c.uint)spirv_data)
                    
                    // SPIR-V 메시지 확인
                    spirv_messages := glslang.program_SPIRV_get_messages(program)
                    if spirv_messages != nil {
                        trace.printlnLog(spirv_messages)
                    }
                    
                    shader_bytes = transmute([]byte)(mem.slice_ptr(cast(^u32)spirv_data, cast(int)spirv_size))
                    shader_programs[i] = program
                case []byte:
                    shader_bytes = s
            }
            shader_modules[i] = vk.CreateShaderModule2(engine.graphics_device(), shader_bytes) or_else trace.panic_log("custom_object_pipeline_init: CreateShaderModule2")
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

    self.__descriptor_set_layouts = mem.make_non_zeroed_slice([]vk.DescriptorSetLayout, len(binding_set_layouts))
    for &l, i in self.__descriptor_set_layouts {
        l = vk.DescriptorSetLayoutInit(engine.graphics_device(), binding_set_layouts[i])
    }
    self.__pipeline_layout = vk.PipelineLayoutInit(engine.graphics_device(), self.__descriptor_set_layouts)

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


@private custom_object_vtable :engine.iobject_vtable = engine.iobject_vtable{
    draw = auto_cast _super_custom_object_draw,
    deinit = auto_cast _super_custom_object_deinit,
}

custom_object_init :: proc(self:^custom_object,
    p_pipeline:^object_pipeline,
    pipeline_p_sets:[]^engine.descriptor_set,
    pipeline_set_idx:int = 0, vtable:^engine.iobject_vtable = nil) {

    self.pipeline_p_sets = mem.make_non_zeroed_slice([]^engine.descriptor_set, len(pipeline_p_sets))
    mem.copy_non_overlapping(&self.pipeline_p_sets[0], &pipeline_p_sets[0], len(pipeline_p_sets) * size_of(^engine.descriptor_set))

    self.p_pipeline = p_pipeline
    self.pipeline_set_idx = pipeline_set_idx
    
    self.set.bindings = p_pipeline.__pool_binding[pipeline_set_idx]
    self.set.size = p_pipeline.pool_sizes[pipeline_set_idx]
    self.set.layout = p_pipeline.__descriptor_set_layouts[pipeline_set_idx]

    self.vtable = vtable == nil ? &custom_object_vtable : vtable
    if self.vtable.draw == nil do self.vtable.draw = auto_cast _super_custom_object_draw
    if self.vtable.deinit == nil do self.vtable.deinit = auto_cast _super_custom_object_deinit

    engine.itransform_object_init(self, nil, self.vtable)
    self.actual_type = typeid_of(custom_object)
}


_super_custom_object_deinit :: proc(self:^custom_object) {
    engine._super_itransform_object_deinit(auto_cast self)

    delete(self.pipeline_p_sets)
}


_super_custom_object_draw :: proc(self:^custom_object, cmd:engine.command_buffer) {
    sets := mem.make_non_zeroed_slice([]vk.DescriptorSet, len(self.pipeline_p_sets))
    defer delete(sets)
    for i in 0..<len(self.pipeline_p_sets) {
        sets[i] = self.pipeline_p_sets[i].__set
    }

    engine.graphics_cmd_bind_pipeline(cmd, .GRAPHICS, self.p_pipeline.__pipeline)
    engine.graphics_cmd_bind_descriptor_sets(cmd, .GRAPHICS, self.p_pipeline.__pipeline_layout, 0, auto_cast len(self.pipeline_p_sets),
        &sets[0], 0, nil)

    if self.p_pipeline.draw_method.type == .Draw {
        engine.graphics_cmd_draw(cmd, self.p_pipeline.draw_method.vertex_count, self.p_pipeline.draw_method.instance_count, self.p_pipeline.draw_method.first_vertex, self.p_pipeline.draw_method.first_instance)
    } else if self.p_pipeline.draw_method.type == .DrawIndexed {
        engine.graphics_cmd_draw_indexed(cmd, self.p_pipeline.draw_method.index_count, self.p_pipeline.draw_method.instance_count, self.p_pipeline.draw_method.first_index, self.p_pipeline.draw_method.vertex_offset, self.p_pipeline.draw_method.first_instance)
    }
}

/*
Creates a buffer resource

Inputs:
- option: Buffer creation options
- data: Initial data for the buffer
- is_copy: Whether to copy the data
- allocator: Optional allocator (default: nil)

Returns:
- Pointer to the buffer resource
- Pointer to the resource data
*/
create_buffer_resource :: #force_inline proc(option:engine.buffer_create_option, data:[]byte, is_copy:bool, allocator:Maybe(runtime.Allocator) = nil) -> engine.iresource {
    return engine.buffer_resource_create_buffer(option, data, is_copy, allocator)
}

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
		renderPass = engine.default_render_pass(),
		pMultisampleState = engine.default_multisample_state(),
		pColorBlendState = &vk.DefaultPipelineColorBlendStateCreateInfo,
	)

	res := vk.CreateGraphicsPipelines(engine.graphics_device(), 0, 1, &pipeline_create_info, nil, &self.__pipeline)
	if res != .SUCCESS {
		trace.printlnLog("create_graphics_pipeline: Failed to create graphics pipeline:", res)
		return false
	}
	return true
}

object_pipeline :: struct {
    __pipeline:vk.Pipeline,
    __pipeline_layout:vk.PipelineLayout,
    __descriptor_set_layouts:[]vk.DescriptorSetLayout,
    __pool_binding:[][]u32,//! auto generate inside, uses engine_def_allocator

    draw_method:object_draw_method,
    pool_sizes:[][]engine.descriptor_pool_size,
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
