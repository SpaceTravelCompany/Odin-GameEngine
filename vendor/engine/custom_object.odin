//using custom shader
package engine

import "core:math"
import "core:mem"
import "core:slice"
import "core:sync"
import "core:thread"
import "core:debug/trace"
import "core:math/linalg"
import "base:intrinsics"
import "base:runtime"
import vk "vendor:vulkan"
import "core:mem/virtual"

@(private = "file") custom_object_allocator:runtime.Allocator
@(private = "file") __arena: virtual.Arena
@(private="file", init)
custom_object_allocator_start :: proc() {
    _ = virtual.arena_init_growing(&__arena)
	custom_object_allocator = virtual.arena_allocator(&__arena)
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
    __pool_binding:[]u32,//! auto generate inside, custom_object_allocator
    draw_method:custom_object_draw_method,
    pool_sizes:[dynamic]custom_object_DescriptorPoolSize,
}

custom_object :: struct {
    using _:IObject,
    pPipeline:^custom_object_pipeline,
}

custom_object_pipeline_Deinit :: proc(self:^custom_object_pipeline) {
    mem.ICheckInit_Deinit(&self.checkInit)
}

//setting struct field first
custom_object_pipeline_Init :: proc(self:^custom_object_pipeline) {
    mem.ICheckInit_Init(&self.checkInit)

    
}



