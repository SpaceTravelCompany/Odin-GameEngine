package engine

import "core:math/linalg"
import vk "vendor:vulkan"
import "base:runtime"

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
	set:vk.DescriptorSet,
	set_idx:u32,
	viewport_area : Maybe(linalg.rect),
	allocator: runtime.Allocator,
}

//내부구조는 base_descriptor_set_layout와 동일
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
viewport_init_update :: proc (self:^viewport, allocator := context.allocator) {
	self.allocator = allocator
	if vulkan_version.major > 0 {
		if self.set == 0 {
			self.set, self.set_idx = get_descriptor_set(descriptor_pool_size__base_uniform_pool[:], base_descriptor_set_layout())
		}
		update_descriptor_set(self.set, descriptor_pool_size__base_uniform_pool[:], {
			graphics_get_resource(self.camera.mat_idx), graphics_get_resource(self.projection.mat_idx) 
		})
	}
}

viewport_deinit :: proc(self:^viewport) {
	if self.set != 0 {
        put_descriptor_set(self.set_idx, base_descriptor_set_layout())
        self.set = 0
    }
}
def_viewport :: proc "contextless" () -> ^viewport {
	return &__g_default_viewport
}