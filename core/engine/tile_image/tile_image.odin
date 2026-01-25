package tile_image

import "core:engine"
import "core:mem"
import "core:math/linalg"
import "core:math"
import vk "vendor:vulkan"
import img "core:image"


tile_texture_array :: engine.tile_texture_array

/*
Tile image object structure for rendering tiled textures

Extends iobject with tile texture array and tile index
*/
tile_image :: struct {
    using _:engine.itransform_object,
    tile_uniform:engine.iresource,
    tile_idx:u32,
    src: ^tile_texture_array,
}

@private get_uniform_resources_tile_image :: #force_inline proc(self:^tile_image) -> []engine.iresource {
    res := mem.make_non_zeroed([]engine.iresource, 3, context.temp_allocator)
    res[0] = self.mat_uniform
    res[1] = self.color_transform.mat_uniform
    res[2] = self.tile_uniform
    return res[:]
}


@private tile_image_vtable :engine.iobject_vtable = engine.iobject_vtable {
    draw = auto_cast _super_tile_image_draw,
    deinit = auto_cast _super_tile_image_deinit,
    get_uniform_resources = auto_cast get_uniform_resources_tile_image,
}

tile_image_init :: proc(self:^tile_image, src:^tile_texture_array,
colorTransform:^engine.color_transform = nil, vtable:^engine.iobject_vtable = nil) {
    self.src = src

    self.set.bindings = engine.descriptor_set_binding__animate_img_uniform_pool[:]
    self.set.size = engine.descriptor_pool_size__animate_img_uniform_pool[:]
    self.set.layout = engine.get_animate_img_descriptor_set_layout()

    self.vtable = vtable == nil ? &tile_image_vtable : vtable
    if self.vtable.draw == nil do self.vtable.draw = auto_cast _super_tile_image_draw
    if self.vtable.deinit == nil do self.vtable.deinit = auto_cast _super_tile_image_deinit

    if self.vtable.get_uniform_resources == nil do self.vtable.get_uniform_resources = auto_cast get_uniform_resources_tile_image

    engine.itransform_object_init(self, colorTransform, self.vtable)
	self.actual_type = typeid_of(tile_image)
}

_super_tile_image_deinit :: proc(self:^tile_image) {
    engine.buffer_resource_deinit(self.tile_uniform)
    self.tile_uniform = nil

    engine._super_itransform_object_deinit(auto_cast self)
}


/*
Gets the tile texture array source of the tile image

Inputs:
- self: Pointer to the tile image

Returns:
- Pointer to the tile texture array source
*/
tile_image_get_tile_texture_array :: #force_inline proc "contextless" (self:^tile_image) -> ^tile_texture_array {
    return self.src
}

/*
Updates the tile texture array source of the tile image

Inputs:
- self: Pointer to the tile image
- src: Pointer to the new tile texture array source

Returns:
- None
*/
tile_image_update_tile_texture_array :: #force_inline proc "contextless" (self:^tile_image, src:^tile_texture_array) {
    self.src = src
}

tile_image_change_color_transform :: #force_inline proc(self:^tile_image, colorTransform:^engine.color_transform) {
    engine.itransform_object_change_color_transform(self, colorTransform)
}
// tile_image_update_camera :: #force_inline proc(self:^tile_image, camera:^engine.camera) {
//     engine.iobject_update_camera(self, camera)
// }
// tile_image_update_projection :: #force_inline proc(self:^tile_image, projection:^engine.projection) {
//     engine.iobject_update_projection(self, projection)
// }

// /*
// Gets the camera of the tile image

// Inputs:
// - self: Pointer to the tile image

// Returns:
// - Pointer to the camera
// */
// tile_image_get_camera :: proc "contextless" (self:^tile_image) -> ^engine.camera {
//     return engine.iobject_get_camera(self)
// }

// /*
// Gets the projection of the tile image

// Inputs:
// - self: Pointer to the tile image

// Returns:
// - Pointer to the projection
// */
// tile_image_get_projection :: proc "contextless" (self:^tile_image) -> ^engine.projection {
//     return engine.iobject_get_projection(self)
// }

/*
Gets the color transform of the tile image

Inputs:
- self: Pointer to the tile image

Returns:
- Pointer to the color transform
*/
tile_image_get_color_transform :: proc "contextless" (self:^tile_image) -> ^engine.color_transform {
    return engine.itransform_object_get_color_transform(self)
}

tile_image_update_transform :: #force_inline proc(self:^tile_image, pos:linalg.point3d, rotation:f32, scale:linalg.point = {1,1}, pivot:linalg.point = {0.0, 0.0}) {
    engine.itransform_object_update_transform(self, pos, rotation, scale, pivot)
}

tile_image_update_transform_matrix_raw :: #force_inline proc(self:^tile_image, _mat:linalg.matrix44) {
    engine.itransform_object_update_transform_matrix_raw(self, _mat)
}

/*
Updates the tile index for the tile image

Inputs:
- self: Pointer to the tile image
- idx: The new tile index

Returns:
- None
*/
tile_image_update_idx :: proc(self:^tile_image, idx:u32) {
    self.tile_idx = idx

    engine.buffer_resource_copy_update(self.tile_uniform, &self.tile_idx)
}

_super_tile_image_draw :: proc (self:^tile_image, cmd:engine.command_buffer, viewport:^engine.viewport) {
    engine.graphics_cmd_bind_pipeline(cmd, .GRAPHICS, engine.get_animate_img_pipeline().__pipeline)
    engine.graphics_cmd_bind_descriptor_sets(cmd, .GRAPHICS, engine.get_animate_img_pipeline_layout(), 0, 3,
        &([]vk.DescriptorSet{self.set.__set,  viewport.set.__set, self.src.set.__set,})[0], 0, nil)

    engine.graphics_cmd_draw(cmd, 6, 1, 0, 0)
}


/*
Initializes a tile texture array from a tilemap

Inputs:
- self: Pointer to the tile texture array to initialize
- tile_width: Width of each tile
- tile_height: Height of each tile
- width: Width of the tilemap
- count: Number of tiles
- pixels: Pixel data of the tilemap
- sampler: Sampler to use (default: 0, uses default linear sampler)
- inPixelFmt: Input pixel format (default: .RGBA)

Returns:
- None
*/
tile_texture_array_init :: proc(self:^tile_texture_array, tile_width:u32, tile_height:u32, width:u32, count:u32, pixels:[]byte, sampler:vk.Sampler = 0, 
inPixelFmt:img.color_fmt = .RGBA, allocator := context.allocator) {
    self.sampler = sampler == 0 ? engine.get_linear_sampler() : sampler
    self.set.bindings = engine.descriptor_set_binding__single_pool[:]
    self.set.size = engine.descriptor_pool_size__single_sampler_pool[:]
    self.set.layout = engine.get_tex_descriptor_set_layout()
    self.set.__set = 0
    bit :: 4//outBit count default 4
    allocPixels := mem.make_non_zeroed_slice([]byte, count * tile_width * tile_height * bit, allocator)

    //convert tilemap pixel data format to tile image data format arranged sequentially
    cnt:u32
    row := math.floor_div(width, tile_width)
    col := math.floor_div(count, row)

    for y in 0..<col {
        for x in 0..<row {
            for h in 0..<tile_height {
                start := cnt * (tile_width * tile_height * bit) + h * tile_width * bit
                startP := (y * tile_height + h) * (width * bit) + x * tile_width * bit
                engine.color_fmt_convert_default(pixels[startP:startP + tile_width * bit], allocPixels[start:start + tile_width * bit], inPixelFmt)
            }
            cnt += 1
        }
    }
  
    self.texture = engine.buffer_resource_create_texture({
        width = tile_width,
        height = tile_height,
        use_gcpu_mem = false,
        format = .DefaultColor,
        samples = 1,
        len = count,
        texture_usage = {.IMAGE_RESOURCE},
        type = .TEX2D,
    }, self.sampler, allocPixels, false, allocator)

    self.set.__resources = mem.make_non_zeroed_slice([]engine.iresource, 1, engine.temp_arena_allocator())
    self.set.__resources[0] = self.texture
    engine.update_descriptor_sets(mem.slice_ptr(&self.set, 1))
}

/*
Deinitializes and cleans up tile texture array resources

Inputs:
- self: Pointer to the tile texture array to deinitialize

Returns:
- None
*/
tile_texture_array_deinit :: #force_inline proc(self:^tile_texture_array) {
    engine.buffer_resource_deinit(self.texture)
	self.texture = nil
}
/*
Gets the width of tiles in the tile texture array

Inputs:
- self: Pointer to the tile texture array

Returns:
- Width of each tile in pixels
*/
tile_texture_array_width :: #force_inline proc "contextless" (self:^tile_texture_array) -> u32 {
    return (^engine.texture_resource)(self.texture).option.width
}

/*
Gets the height of tiles in the tile texture array

Inputs:
- self: Pointer to the tile texture array

Returns:
- Height of each tile in pixels
*/
tile_texture_array_height :: #force_inline proc "contextless" (self:^tile_texture_array) -> u32 {
    return (^engine.texture_resource)(self.texture).option.height
}

/*
Gets the number of tiles in the tile texture array

Inputs:
- self: Pointer to the tile texture array

Returns:
- Number of tiles in the array
*/
tile_texture_array_count :: #force_inline proc "contextless" (self:^tile_texture_array) -> u32 {
    return (^engine.texture_resource)(self.texture).option.len
}