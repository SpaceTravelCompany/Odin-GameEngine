package engine

import "core:math/linalg"
import "core:mem"
import vk "vendor:vulkan"

/*
Viewport structure for managing rendering areas and camera/projection settings

Contains:
- camera: Pointer to the camera for view transformations
- projection: Pointer to the projection for projection transformations
- set: Descriptor set for uniform resources
- viewport_area: Optional rectangle defining the viewport area (default: nil means window size)
*/
viewport :: struct {
	camera : ^camera,
	projection : ^projection,
	set:descriptor_set(2),
	viewport_area : Maybe(linalg.rect),
}

viewport_descriptor_set_layout :: proc "contextless" () -> vk.DescriptorSetLayout {
	return __base_descriptor_set_layout
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
    	self.set.layout = viewport_descriptor_set_layout()
	}
	
	self.set.__resources[0] = graphics_get_resource(self.camera)
	self.set.__resources[1] = graphics_get_resource(self.projection)
	update_descriptor_set(&self.set)
}

def_viewport :: proc "contextless" () -> ^viewport {
	return &__g_default_viewport
}