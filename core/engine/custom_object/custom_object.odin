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
	sets:[]^engine.i_descriptor_set,
    p_pipeline:^engine.object_pipeline,
	allocator:runtime.Allocator,
}


@private custom_object_vtable :engine.iobject_vtable = engine.iobject_vtable{
    draw = auto_cast _super_custom_object_draw,
    deinit = auto_cast _super_custom_object_deinit,
}

custom_object_init :: proc(self:^custom_object,
    p_pipeline:^engine.object_pipeline,
	pool_binding:[][]u32,
	pool_sizes:[][]engine.descriptor_pool_size,
   vtable:^engine.iobject_vtable = nil, allocator := context.allocator) {

    self.p_pipeline = p_pipeline
	self.allocator = allocator
	assert(len(pool_sizes) == len(pool_binding))
    
	self.sets = make([]^engine.i_descriptor_set, len(pool_sizes), allocator)
	for i in 0..<len(pool_sizes) {
		//TODO pool_sizes의 cnt를 모두 더해서 descriptor_set의 num_resources를 설정
		num_resources :u32= 0
		for j in 0..<len(pool_sizes[i]) {
			num_resources += pool_sizes[i][j].cnt
		}
		pool_binding_copy := mem.make_non_zeroed_slice([]u32, len(pool_binding[i]), allocator)
		mem.copy_non_overlapping(&pool_binding_copy[0], &pool_binding[i][0], len(pool_binding[i]))
		pool_sizes_copy := mem.make_non_zeroed_slice([]engine.descriptor_pool_size, len(pool_sizes[i]), allocator)
		mem.copy_non_overlapping(&pool_sizes_copy[0], &pool_sizes[i][0], len(pool_sizes[i]))
		
		ptr, _ := mem.alloc(size_of(engine.p_descriptor_set) + ((int(num_resources)-1) * size_of(engine.union_resource)), 
		mem.DEFAULT_ALIGNMENT, allocator)
		self.sets[i] = auto_cast ptr
		self.sets[i].bindings = pool_binding_copy
		self.sets[i].size = pool_sizes_copy
		self.sets[i].layout = p_pipeline.__descriptor_set_layouts[i]
		self.sets[i].num_resources = num_resources
	}

    if vtable == nil {
        self.vtable = &custom_object_vtable
    } else {
        self.vtable = vtable
		if self.vtable.draw == nil do self.vtable.draw = auto_cast _super_custom_object_draw
    	if self.vtable.deinit == nil do self.vtable.deinit = auto_cast _super_custom_object_deinit
    }

    engine.iobject_init(self)
    self.actual_type = typeid_of(custom_object)
}


_super_custom_object_deinit :: proc(self:^custom_object) {
	for i in 0..<len(self.sets) {
		mem.free(self.sets[i], self.allocator)
		delete(self.sets[i].bindings, self.allocator)
		delete(self.sets[i].size, self.allocator)
	}
    delete(self.sets, self.allocator)
}


_super_custom_object_draw :: proc(self:^custom_object, cmd:engine.command_buffer) {
    sets := mem.make_non_zeroed_slice([]vk.DescriptorSet, len(self.sets), context.temp_allocator)
    defer delete(sets, context.temp_allocator)

    for i in 0..<len(self.sets) {
        sets[i] = self.sets[i].__set
    }

    engine.graphics_cmd_bind_pipeline(cmd, .GRAPHICS, self.p_pipeline.__pipeline)
    engine.graphics_cmd_bind_descriptor_sets(cmd, .GRAPHICS, self.p_pipeline.__pipeline_layout, 0, auto_cast len(self.sets),
        &sets[0], 0, nil)

    if self.p_pipeline.draw_method.type == .Draw {
        engine.graphics_cmd_draw(cmd, self.p_pipeline.draw_method.vertex_count, self.p_pipeline.draw_method.instance_count, self.p_pipeline.draw_method.first_vertex, self.p_pipeline.draw_method.first_instance)
    } else if self.p_pipeline.draw_method.type == .DrawIndexed {
        engine.graphics_cmd_draw_indexed(cmd, self.p_pipeline.draw_method.index_count, self.p_pipeline.draw_method.instance_count, self.p_pipeline.draw_method.first_index, self.p_pipeline.draw_method.vertex_offset, self.p_pipeline.draw_method.first_instance)
    }
}

