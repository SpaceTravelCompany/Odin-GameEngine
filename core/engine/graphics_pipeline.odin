package engine

import "base:intrinsics"
import vk "vendor:vulkan"
import "core:debug/trace"
import "core:thread"
import "core:engine/geometry"
import "core:sync"
import "base:runtime"


shader_code_set :: struct {
	vert: string,
	frag: string,
	geom: string,
	comp: string,
}

shader_code_set_init :: proc "contextless" (
	vk_vert: string = "",
	vk_frag: string = "",
	vk_geom: string = "",
	vk_comp: string = "",
	gl_vert: string = "",
	gl_frag: string = "",
	gl_geom: string = "",
	gl_comp: string = "",
	gles_vert: string = "",
	gles_frag: string = "",
	gles_geom: string = "",
	gles_comp: string = "",
) -> shader_code_set {
	when is_web {
		vk_vert := vk_vert;vk_frag := vk_frag;vk_geom := vk_geom;vk_comp := vk_comp;gl_vert := gl_vert;gl_frag := gl_frag;gl_geom := gl_geom;gl_comp := gl_comp;
		return shader_code_set{
			vert = gles_vert,
			frag = gles_frag,
			geom = gles_geom,
			comp = gles_comp,
		}
	} else {
		when is_android {
			gl_vert := gl_vert;gl_frag := gl_frag;gl_geom := gl_geom;gl_comp := gl_comp;
		} else {
			gles_vert := gles_vert;gles_frag := gles_frag;gles_geom := gles_geom;gles_comp := gles_comp;
		}
		if vulkan_version.major > 0 {
			return shader_code_set{
				vert = vk_vert,
				frag = vk_frag,
				geom = vk_geom,
				comp = vk_comp,
			}
		} else {
			when is_android {
				return shader_code_set{
					vert = gles_vert,
					frag = gles_frag,
					geom = gles_geom,
					comp = gles_comp,
				}
			} else {
				return shader_code_set{
					vert = gl_vert,
					frag = gl_frag,
					geom = gl_geom,
					comp = gl_comp,
				}
			}
		}
	}
}

@private GRAPHICS_MAX_INIT_PROC_THREADS :: #config(GRAPHICS_MAX_INIT_PROC_THREADS, 8)
pipeline_set :: struct {
	init_proc: #type proc(data: rawptr),
	fini_proc: #type proc(data: rawptr),
	exec_proc: #type proc(data: rawptr),
	allocator: runtime.Allocator,
	data: rawptr,
}
@private pipeline_sets:[dynamic]pipeline_set
@private g_init_proc_thread_pool: thread.Pool
@private g_pipeline_sets_mtx: sync.Mutex

add_pipeline_set :: proc(pipeline_set: pipeline_set) {
	sync.mutex_lock(&g_pipeline_sets_mtx)
	defer sync.mutex_unlock(&g_pipeline_sets_mtx)

	append(&pipeline_sets, pipeline_set)
	task_proc :: proc(task: thread.Task) {
		pipeline_set := (^pipeline_set)(task.data)
		if pipeline_set.init_proc != nil do pipeline_set.init_proc(pipeline_set.data)
		for {
			thread.pool_pop_done(&g_init_proc_thread_pool) or_break
		}
	}
	thread.pool_add_task(&g_init_proc_thread_pool, pipeline_set.allocator, task_proc, &pipeline_sets[len(pipeline_sets) - 1])
}

@private init_pipeline_sets :: proc() {
	sync.mutex_lock(&g_pipeline_sets_mtx)

	defer sync.mutex_unlock(&g_pipeline_sets_mtx)
	pipeline_sets = make([dynamic]pipeline_set)
	thread.pool_init(&g_init_proc_thread_pool, context.allocator, 
	min(GRAPHICS_MAX_INIT_PROC_THREADS, get_processor_core_len()), nil, nil, nil, nil)
	thread.pool_start(&g_init_proc_thread_pool)
}
@private fini_pipeline_sets :: proc() {
	sync.mutex_lock(&g_pipeline_sets_mtx)
	defer sync.mutex_unlock(&g_pipeline_sets_mtx)

	thread.pool_wait_all(&g_init_proc_thread_pool)
	for pipeline_set in pipeline_sets {
		if pipeline_set.fini_proc != nil do pipeline_set.fini_proc(pipeline_set.data)
	}
	thread.pool_join(&g_init_proc_thread_pool)
	thread.pool_destroy(&g_init_proc_thread_pool)
	delete(pipeline_sets)
}


@private init_pipelines :: proc() {
	__base_descriptor_set_layout = graphics_destriptor_set_layout_init(
		[]vk.DescriptorSetLayoutBinding {
			vk.DescriptorSetLayoutBindingInit(0, 1),
			vk.DescriptorSetLayoutBindingInit(1, 1),
		}
	)
	__copy_screen_descriptor_set_layout = graphics_destriptor_set_layout_init(
		[]vk.DescriptorSetLayoutBinding {
			vk.DescriptorSetLayoutBindingInit(0, 1, stageFlags = {.FRAGMENT},  descriptorType = .INPUT_ATTACHMENT),},
	)
	init_pipeline_sets()
	
	pipeline_set_screen_copy := pipeline_set{
		init_proc = proc(data: rawptr) {
			shader_code_set_screen_copy := shader_code_set_init(
				vk_vert =  #load("shaders/vulkan/screen_copy.vert", string),
				vk_frag = #load("shaders/vulkan/screen_copy.frag", string),
				gl_vert = #load("shaders/gl/screen_copy.vert", string),
				gl_frag = #load("shaders/gl/screen_copy.frag", string),
				gles_vert = #load("shaders/gles/screen_copy.vert", string),
				gles_frag = #load("shaders/gles/screen_copy.frag", string),
			)
			if !object_pipeline_init(&screen_copy_pipeline,
				[]vk.DescriptorSetLayout{__copy_screen_descriptor_set_layout},
				nil, nil,
				object_draw_method{type = .Draw,}, 
				shader_code_set_screen_copy.vert,
				shader_code_set_screen_copy.frag,
				nil,
				vk.PipelineDepthStencilStateCreateInfoInit()){
					intrinsics.trap()
				}
		},
		fini_proc = proc(data: rawptr) {
			object_pipeline_deinit(&screen_copy_pipeline)
		},
		allocator = context.allocator,
		data = nil,
	}
	add_pipeline_set(pipeline_set_screen_copy)
	graphics_texture_module_init()
}

@private clean_pipelines :: proc() {
	fini_pipeline_sets()
	graphics_destriptor_set_layout_destroy(&__base_descriptor_set_layout)
	graphics_destriptor_set_layout_destroy(&__copy_screen_descriptor_set_layout)
}