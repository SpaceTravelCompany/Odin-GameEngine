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
import "core:engine"



/*
Custom object structure for rendering with custom shaders

Extends iobject with custom pipeline and descriptor sets
*/
custom_object :: struct {
    using _:engine.iobject,
	sets:[]engine.descriptor_set,
    p_pipeline:^engine.object_pipeline,
    pipeline_p_sets:[]^engine.descriptor_set,
	allocator:runtime.Allocator,
}


@private custom_object_vtable :engine.iobject_vtable = engine.iobject_vtable{
    draw = auto_cast _super_custom_object_draw,
    deinit = auto_cast _super_custom_object_deinit,
}

custom_object_init :: proc(self:^custom_object,
    p_pipeline:^engine.object_pipeline,
    pipeline_p_sets:[]^engine.descriptor_set,
	pool_binding:[]u32,
	pool_sizes:[]descriptor_pool_size,
   vtable:^engine.iobject_vtable = nil, allocator := context.allocator) {

    self.pipeline_p_sets = mem.make_non_zeroed_slice([]^engine.descriptor_set, len(pipeline_p_sets))
    mem.copy_non_overlapping(&self.pipeline_p_sets[0], &pipeline_p_sets[0], len(pipeline_p_sets) * size_of(^engine.descriptor_set))

    self.p_pipeline = p_pipeline
	self.allocator = allocator
    
	self.sets = make([]engine.descriptor_set, len(pipeline_p_sets), allocator)
	for i in 0..<len(pipeline_p_sets) {
		 self.sets[i].bindings = pool_binding[i]
		 self.sets[i].size = pool_sizes[i]
		 self.sets[i].layout = p_pipeline.__descriptor_set_layouts[i]
	}

    self.vtable = vtable == nil ? &custom_object_vtable : vtable
    if self.vtable.draw == nil do self.vtable.draw = auto_cast _super_custom_object_draw
    if self.vtable.deinit == nil do self.vtable.deinit = auto_cast _super_custom_object_deinit

    engine.iobject_init(self)
    self.actual_type = typeid_of(custom_object)
}


_super_custom_object_deinit :: proc(self:^custom_object) {
    delete(self.pipeline_p_sets, self.allocator)
}


_super_custom_object_draw :: proc(self:^custom_object, cmd:engine.command_buffer) {
    sets := mem.make_non_zeroed_slice([]vk.DescriptorSet, len(self.pipeline_p_sets), context.temp_allocator)
    defer delete(sets, context.temp_allocator)
	
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

