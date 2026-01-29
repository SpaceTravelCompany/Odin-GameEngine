package glslang

import "core:c"
import "core:strings"
import "core:mem"
import "base:library"


when ODIN_OS == .Windows && !library.is_android{
    foreign import glslang {
        library.LIBPATH  + "/libglslang_combined" + library.ARCH_end,
    }
} else when library.is_android {
    @(extra_linker_flags = "-lc++_static -lc++abi -std=c++17")
    foreign import glslang {
        library.LIBPATH  + "/libglslang_combined" + library.ARCH_end,
    }
} else {
    @(extra_linker_flags = "-lstdc++ -std=c++17")
    foreign import glslang {
        library.LIBPATH  + "/libglslang_combined" + library.ARCH_end,
    }
}


Shader_Stage :: enum c.int {
    VERTEX,
    TESSCONTROL,
    TESSEVALUATION,
    GEOMETRY,
    FRAGMENT,
    COMPUTE,
    RAYGEN,
    RAYGEN_NV = RAYGEN,
    INTERSECT,
    INTERSECT_NV = INTERSECT,
    ANYHIT,
    ANYHIT_NV = ANYHIT,
    CLOSESTHIT,
    CLOSESTHIT_NV = CLOSESTHIT,
    MISS,
    MISS_NV = MISS,
    CALLABLE,
    CALLABLE_NV = CALLABLE,
    TASK,
    TASK_NV = TASK,
    MESH,
    MESH_NV = MESH,
    COUNT,
}

Shader_Stage_Mask :: enum c.int {
    VERTEX_MASK = 1 << 0,
    TESSCONTROL_MASK = 1 << 1,
    TESSEVALUATION_MASK = 1 << 2,
    GEOMETRY_MASK = 1 << 3,
    FRAGMENT_MASK = 1 << 4,
    COMPUTE_MASK = 1 << 5,
    RAYGEN_MASK = 1 << 6,
    INTERSECT_MASK = 1 << 7,
    ANYHIT_MASK = 1 << 8,
    CLOSESTHIT_MASK = 1 << 9,
    MISS_MASK = 1 << 10,
    CALLABLE_MASK = 1 << 11,
    TASK_MASK = 1 << 12,
    MESH_MASK = 1 << 13,
}

Source :: enum c.int {
    NONE,
    GLSL,
    HLSL,
    COUNT,
}

Client :: enum c.int {
    NONE,
    VULKAN,
    OPENGL,
    COUNT,
}

Target_Language :: enum c.int {
    NONE,
    SPV,
    COUNT,
}

Target_Client_Version :: enum c.int {
    VULKAN_1_0 = (1 << 22),
    VULKAN_1_1 = (1 << 22) | (1 << 12),
    VULKAN_1_2 = (1 << 22) | (2 << 12),
    VULKAN_1_3 = (1 << 22) | (3 << 12),
    VULKAN_1_4 = (1 << 22) | (4 << 12),
    OPENGL_450 = 450,
    COUNT = 6,
}

Target_Language_Version :: enum c.int {
    SPV_1_0 = (1 << 16),
    SPV_1_1 = (1 << 16) | (1 << 8),
    SPV_1_2 = (1 << 16) | (2 << 8),
    SPV_1_3 = (1 << 16) | (3 << 8),
    SPV_1_4 = (1 << 16) | (4 << 8),
    SPV_1_5 = (1 << 16) | (5 << 8),
    SPV_1_6 = (1 << 16) | (6 << 8),
    COUNT = 7,
}

Profile :: enum c.int {
    BAD_PROFILE = 0,
    NO_PROFILE = (1 << 0),
    CORE_PROFILE = (1 << 1),
    COMPATIBILITY_PROFILE = (1 << 2),
    ES_PROFILE = (1 << 3),
    COUNT,
}

Messages :: enum c.int {
    DEFAULT_BIT = 0,
    RELAXED_ERRORS_BIT = (1 << 0),
    SUPPRESS_WARNINGS_BIT = (1 << 1),
    AST_BIT = (1 << 2),
    SPV_RULES_BIT = (1 << 3),
    VULKAN_RULES_BIT = (1 << 4),
    ONLY_PREPROCESSOR_BIT = (1 << 5),
    READ_HLSL_BIT = (1 << 6),
    CASCADING_ERRORS_BIT = (1 << 7),
    KEEP_UNCALLED_BIT = (1 << 8),
    HLSL_OFFSETS_BIT = (1 << 9),
    DEBUG_INFO_BIT = (1 << 10),
    HLSL_ENABLE_16BIT_TYPES_BIT = (1 << 11),
    HLSL_LEGALIZATION_BIT = (1 << 12),
    HLSL_DX9_COMPATIBLE_BIT = (1 << 13),
    BUILTIN_SYMBOL_TABLE_BIT = (1 << 14),
    ENHANCED = (1 << 15),
    ABSOLUTE_PATH = (1 << 16),
    DISPLAY_ERROR_COLUMN = (1 << 17),
    LINK_TIME_OPTIMIZATION_BIT = (1 << 18),
    VALIDATE_CROSS_STAGE_IO_BIT = (1 << 19),
    COUNT,
}

Shader_Options :: enum c.int {
    DEFAULT_BIT = 0,
    AUTO_MAP_BINDINGS = (1 << 0),
    AUTO_MAP_LOCATIONS = (1 << 1),
    VULKAN_RULES_RELAXED = (1 << 2),
    COUNT,
}

Resource_Type :: enum c.int {
    SAMPLER,
    TEXTURE,
    IMAGE,
    UBO,
    SSBO,
    UAV,
    COMBINED_SAMPLER,
    AS,
    TENSOR,
    COUNT,
}

Version :: struct {
    major: c.int,
    minor: c.int,
    patch: c.int,
    flavor: cstring,
}

Limits :: struct {
    non_inductive_for_loops: c.bool,
    while_loops: c.bool,
    do_while_loops: c.bool,
    general_uniform_indexing: c.bool,
    general_attribute_matrix_vector_indexing: c.bool,
    general_varying_indexing: c.bool,
    general_sampler_indexing: c.bool,
    general_variable_indexing: c.bool,
    general_constant_matrix_vector_indexing: c.bool,
}

Resource :: struct {
    max_lights: c.int,
    max_clip_planes: c.int,
    max_texture_units: c.int,
    max_texture_coords: c.int,
    max_vertex_attribs: c.int,
    max_vertex_uniform_components: c.int,
    max_varying_floats: c.int,
    max_vertex_texture_image_units: c.int,
    max_combined_texture_image_units: c.int,
    max_texture_image_units: c.int,
    max_fragment_uniform_components: c.int,
    max_draw_buffers: c.int,
    max_vertex_uniform_vectors: c.int,
    max_varying_vectors: c.int,
    max_fragment_uniform_vectors: c.int,
    max_vertex_output_vectors: c.int,
    max_fragment_input_vectors: c.int,
    min_program_texel_offset: c.int,
    max_program_texel_offset: c.int,
    max_clip_distances: c.int,
    max_compute_work_group_count_x: c.int,
    max_compute_work_group_count_y: c.int,
    max_compute_work_group_count_z: c.int,
    max_compute_work_group_size_x: c.int,
    max_compute_work_group_size_y: c.int,
    max_compute_work_group_size_z: c.int,
    max_compute_uniform_components: c.int,
    max_compute_texture_image_units: c.int,
    max_compute_image_uniforms: c.int,
    max_compute_atomic_counters: c.int,
    max_compute_atomic_counter_buffers: c.int,
    max_varying_components: c.int,
    max_vertex_output_components: c.int,
    max_geometry_input_components: c.int,
    max_geometry_output_components: c.int,
    max_fragment_input_components: c.int,
    max_image_units: c.int,
    max_combined_image_units_and_fragment_outputs: c.int,
    max_combined_shader_output_resources: c.int,
    max_image_samples: c.int,
    max_vertex_image_uniforms: c.int,
    max_tess_control_image_uniforms: c.int,
    max_tess_evaluation_image_uniforms: c.int,
    max_geometry_image_uniforms: c.int,
    max_fragment_image_uniforms: c.int,
    max_combined_image_uniforms: c.int,
    max_geometry_texture_image_units: c.int,
    max_geometry_output_vertices: c.int,
    max_geometry_total_output_components: c.int,
    max_geometry_uniform_components: c.int,
    max_geometry_varying_components: c.int,
    max_tess_control_input_components: c.int,
    max_tess_control_output_components: c.int,
    max_tess_control_texture_image_units: c.int,
    max_tess_control_uniform_components: c.int,
    max_tess_control_total_output_components: c.int,
    max_tess_evaluation_input_components: c.int,
    max_tess_evaluation_output_components: c.int,
    max_tess_evaluation_texture_image_units: c.int,
    max_tess_evaluation_uniform_components: c.int,
    max_tess_patch_components: c.int,
    max_patch_vertices: c.int,
    max_tess_gen_level: c.int,
    max_viewports: c.int,
    max_vertex_atomic_counters: c.int,
    max_tess_control_atomic_counters: c.int,
    max_tess_evaluation_atomic_counters: c.int,
    max_geometry_atomic_counters: c.int,
    max_fragment_atomic_counters: c.int,
    max_combined_atomic_counters: c.int,
    max_atomic_counter_bindings: c.int,
    max_vertex_atomic_counter_buffers: c.int,
    max_tess_control_atomic_counter_buffers: c.int,
    max_tess_evaluation_atomic_counter_buffers: c.int,
    max_geometry_atomic_counter_buffers: c.int,
    max_fragment_atomic_counter_buffers: c.int,
    max_combined_atomic_counter_buffers: c.int,
    max_atomic_counter_buffer_size: c.int,
    max_transform_feedback_buffers: c.int,
    max_transform_feedback_interleaved_components: c.int,
    max_cull_distances: c.int,
    max_combined_clip_and_cull_distances: c.int,
    max_samples: c.int,
    max_mesh_output_vertices_nv: c.int,
    max_mesh_output_primitives_nv: c.int,
    max_mesh_work_group_size_x_nv: c.int,
    max_mesh_work_group_size_y_nv: c.int,
    max_mesh_work_group_size_z_nv: c.int,
    max_task_work_group_size_x_nv: c.int,
    max_task_work_group_size_y_nv: c.int,
    max_task_work_group_size_z_nv: c.int,
    max_mesh_view_count_nv: c.int,
    max_mesh_output_vertices_ext: c.int,
    max_mesh_output_primitives_ext: c.int,
    max_mesh_work_group_size_x_ext: c.int,
    max_mesh_work_group_size_y_ext: c.int,
    max_mesh_work_group_size_z_ext: c.int,
    max_task_work_group_size_x_ext: c.int,
    max_task_work_group_size_y_ext: c.int,
    max_task_work_group_size_z_ext: c.int,
    _max_union : struct #raw_union {
        max_mesh_view_count_ext: c.int,
        max_dual_source_draw_buffers_ext: c.int,
    },
    limits: Limits,
}

Include_Result :: struct {
    header_name: cstring,
    header_data: cstring,
    header_length: c.size_t,
}

Include_Local_Func :: #type proc(ctx: rawptr, header_name: cstring, includer_name: cstring, include_depth: c.size_t) -> ^Include_Result
Include_System_Func :: #type proc(ctx: rawptr, header_name: cstring, includer_name: cstring, include_depth: c.size_t) -> ^Include_Result
Free_Include_Result_Func :: #type proc(ctx: rawptr, result: ^Include_Result) -> c.int

Include_Callbacks :: struct {
    include_system: Include_System_Func,
    include_local: Include_Local_Func,
    free_include_result: Free_Include_Result_Func,
}

Input :: struct {
    language: Source,
    stage: Shader_Stage,
    client: Client,
    client_version: Target_Client_Version,
    target_language: Target_Language,
    target_language_version: Target_Language_Version,
    code: cstring,
    default_version: c.int,
    default_profile: Profile,
    force_default_version_and_profile: c.int,
    forward_compatible: c.int,
    messages: Messages,
    resource: ^Resource,
    callbacks: Include_Callbacks,
    callbacks_ctx: rawptr,
}

SPV_Options :: struct {
    generate_debug_info: c.bool,
    strip_debug_info: c.bool,
    disable_optimizer: c.bool,
    optimize_size: c.bool,
    disassemble: c.bool,
    validate: c.bool,
    emit_nonsemantic_shader_debug_info: c.bool,
    emit_nonsemantic_shader_debug_source: c.bool,
    compile_only: c.bool,
    optimize_allow_expanded_id_bound: c.bool,
}

Shader :: struct {}
Program :: struct {}
Mapper :: struct {}
Resolver :: struct {}

@(default_calling_convention = "c")
foreign glslang {
    @(link_name = "glslang_get_version")
    get_version :: proc(version: ^Version) ---
    
    @(link_name = "glslang_initialize_process")
    initialize_process :: proc() -> c.int ---
    @(link_name = "glslang_finalize_process")
    finalize_process :: proc() ---
    
    @(link_name = "glslang_shader_create")
    shader_create :: proc(input: ^Input) -> ^Shader ---
    @(link_name = "glslang_shader_delete")
    shader_delete :: proc(shader: ^Shader) ---
    @(link_name = "glslang_shader_set_preamble")
    shader_set_preamble :: proc(shader: ^Shader, s: cstring) ---
    @(link_name = "glslang_shader_set_entry_point")
    shader_set_entry_point :: proc(shader: ^Shader, s: cstring) ---
    @(link_name = "glslang_shader_set_invert_y")
    shader_set_invert_y :: proc(shader: ^Shader, y: c.bool) ---
    @(link_name = "glslang_shader_shift_binding")
    shader_shift_binding :: proc(shader: ^Shader, res: Resource_Type, base: c.uint) ---
    @(link_name = "glslang_shader_shift_binding_for_set")
    shader_shift_binding_for_set :: proc(shader: ^Shader, res: Resource_Type, base: c.uint, set: c.uint) ---
    @(link_name = "glslang_shader_set_options")
    shader_set_options :: proc(shader: ^Shader, options: c.int) ---
    @(link_name = "glslang_shader_set_glsl_version")
    shader_set_glsl_version :: proc(shader: ^Shader, version: c.int) ---
    @(link_name = "glslang_shader_set_default_uniform_block_set_and_binding")
    shader_set_default_uniform_block_set_and_binding :: proc(shader: ^Shader, set: c.uint, binding: c.uint) ---
    @(link_name = "glslang_shader_set_default_uniform_block_name")
    shader_set_default_uniform_block_name :: proc(shader: ^Shader, name: cstring) ---
    @(link_name = "glslang_shader_set_resource_set_binding")
    shader_set_resource_set_binding :: proc(shader: ^Shader, bindings: ^cstring, num_bindings: c.uint) ---
    @(link_name = "glslang_shader_preprocess")
    shader_preprocess :: proc(shader: ^Shader, input: ^Input) -> c.int ---
    @(link_name = "glslang_shader_parse")
    shader_parse :: proc(shader: ^Shader, input: ^Input) -> c.int ---
    @(link_name = "glslang_shader_get_preprocessed_code")
    shader_get_preprocessed_code :: proc(shader: ^Shader) -> cstring ---
    @(link_name = "glslang_shader_set_preprocessed_code")
    shader_set_preprocessed_code :: proc(shader: ^Shader, code: cstring) ---
    @(link_name = "glslang_shader_get_info_log")
    shader_get_info_log :: proc(shader: ^Shader) -> cstring ---
    @(link_name = "glslang_shader_get_info_debug_log")
    shader_get_info_debug_log :: proc(shader: ^Shader) -> cstring ---
    
    @(link_name = "glslang_program_create")
    program_create :: proc() -> ^Program ---
    @(link_name = "glslang_program_delete")
    program_delete :: proc(program: ^Program) ---
    @(link_name = "glslang_program_add_shader")
    program_add_shader :: proc(program: ^Program, shader: ^Shader) ---
    @(link_name = "glslang_program_link")
    program_link :: proc(program: ^Program, messages: c.int) -> c.int ---
    @(link_name = "glslang_program_add_source_text")
    program_add_source_text :: proc(program: ^Program, stage: Shader_Stage, text: cstring, len: c.size_t) ---
    @(link_name = "glslang_program_set_source_file")
    program_set_source_file :: proc(program: ^Program, stage: Shader_Stage, file: cstring) ---
    @(link_name = "glslang_program_map_io")
    program_map_io :: proc(program: ^Program) -> c.int ---
    @(link_name = "glslang_program_map_io_with_resolver_and_mapper")
    program_map_io_with_resolver_and_mapper :: proc(program: ^Program, resolver: ^Resolver, mapper: ^Mapper) -> c.int ---
    @(link_name = "glslang_program_SPIRV_generate")
    program_SPIRV_generate :: proc(program: ^Program, stage: Shader_Stage) ---
    @(link_name = "glslang_program_SPIRV_generate_with_options")
    program_SPIRV_generate_with_options :: proc(program: ^Program, stage: Shader_Stage, spv_options: ^SPV_Options) ---
    @(link_name = "glslang_program_SPIRV_get_size")
    program_SPIRV_get_size :: proc(program: ^Program) -> c.size_t ---
    @(link_name = "glslang_program_SPIRV_get")
    program_SPIRV_get :: proc(program: ^Program, spirv: ^c.uint) ---
    @(link_name = "glslang_program_SPIRV_get_ptr")
    program_SPIRV_get_ptr :: proc(program: ^Program) -> ^c.uint ---
    @(link_name = "glslang_program_SPIRV_get_messages")
    program_SPIRV_get_messages :: proc(program: ^Program) -> cstring ---
    @(link_name = "glslang_program_get_info_log")
    program_get_info_log :: proc(program: ^Program) -> cstring ---
    @(link_name = "glslang_program_get_info_debug_log")
    program_get_info_debug_log :: proc(program: ^Program) -> cstring ---
    
    @(link_name = "glslang_glsl_mapper_create")
    glsl_mapper_create :: proc() -> ^Mapper ---
    @(link_name = "glslang_glsl_mapper_delete")
    glsl_mapper_delete :: proc(mapper: ^Mapper) ---
    
    @(link_name = "glslang_glsl_resolver_create")
    glsl_resolver_create :: proc(program: ^Program, stage: Shader_Stage) -> ^Resolver ---
    @(link_name = "glslang_glsl_resolver_delete")
    glsl_resolver_delete :: proc(resolver: ^Resolver) ---

    @(link_name = "glslang_default_resource")
    default_resource :: proc() -> ^Resource ---
}