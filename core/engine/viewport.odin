package engine

import "core:math/linalg"
import "core:mem"

/*
Viewport structure for managing rendering areas and camera/projection settings

Contains:
- viewport_area: Optional rectangle defining the viewport area (default: nil means window size)
- camera: Pointer to the camera for view transformations
- projection: Pointer to the projection for projection transformations
- set: Descriptor set for uniform resources
*/
viewport :: struct {
	viewport_area : Maybe(linalg.RectF),
	camera : ^camera,
	projection : ^projection,
	set:descriptor_set,
}

/*
Initializes or updates the viewport's descriptor set.
You should call this function after changing the camera, projection pointer or initializing the viewport.

Inputs:
- self: Pointer to the viewport to initialize and update

Returns:
- None
*/
viewport_init_update :: proc (self:^viewport) {
	if self.set.bindings == nil {
		self.set.bindings = descriptor_set_binding__base_uniform_pool[:]
    	self.set.size = descriptor_pool_size__base_uniform_pool[:]
    	self.set.layout = base_descriptor_set_layout
	}
	
	//__temp_arena_allocator update 하면 다 지우니 중복 할당해도 됨.
	self.set.__resources = mem.make_non_zeroed_slice([]iresource, 2, temp_arena_allocator())
	self.set.__resources[0] = self.camera.mat_uniform
	self.set.__resources[1] = self.projection.mat_uniform
	update_descriptor_sets(mem.slice_ptr(&self.set, 1))
}


def_viewport :: proc() -> ^viewport {
	return &__g_default_viewport
}