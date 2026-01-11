package animator

import "core:engine"
import "core:mem"
import vk "vendor:vulkan"

import "core:math/linalg"
/*
Animated object structure that extends iobject with frame animation support

Contains frame information and uniform buffer for frame data
*/
ianimate_object :: struct {
    using _:engine.iobject,
    frame_uniform:engine.buffer_resource,
    frame:u32,
}

/*
Animation player structure for managing multiple animated objects

Manages playback state, timing, and looping for a collection of animated objects
*/
animate_player :: struct {
    objs:[]^ianimate_object,
    target_fps:f64,
    __playing_dt:f64,
    playing:bool,
    loop:bool,
}

/*
Updates the animation player with delta time

Inputs:
- self: Pointer to the animation player
- _dt: Delta time since last update

Returns:
- None
*/
animate_player_update :: proc (self:^animate_player, _dt:f64) {
    if self.playing {
        self.__playing_dt += _dt
        for self.__playing_dt >= 1 / self.target_fps {
            isp := false
            for obj in self.objs {
                if self.loop || obj.frame < ianimate_object_get_frame_cnt(obj) - 1 {
                    ianimate_object_next_frame(obj)
                    isp = true
                }
            }
            if !isp {
                animate_player_stop(self)
                return
            }
            self.__playing_dt -= 1.0 / self.target_fps
        }
    }
}

/*
Starts playing the animation

Inputs:
- self: Pointer to the animation player

Returns:
- None
*/
animate_player_play :: #force_inline proc "contextless" (self:^animate_player) {
    self.playing = true
    self.__playing_dt = 0.0
}

/*
Stops playing the animation

Inputs:
- self: Pointer to the animation player

Returns:
- None
*/
animate_player_stop :: #force_inline proc "contextless" (self:^animate_player) {
    self.playing = false
}

/*
Sets the frame for all objects in the animation player

Inputs:
- self: Pointer to the animation player
- _frame: The frame number to set

Returns:
- None
*/
animate_player_set_frame :: proc (self:^animate_player, _frame:u32) {
    for obj in self.objs {
        ianimate_object_set_frame(obj, _frame)
    }
}

/*
Moves all objects to the previous frame

Inputs:
- self: Pointer to the animation player

Returns:
- None
*/
animate_player_prev_frame :: proc (self:^animate_player) {
    for obj in self.objs {
        ianimate_object_prev_frame(obj)
    }
}

/*
Moves all objects to the next frame

Inputs:
- self: Pointer to the animation player

Returns:
- None
*/
animate_player_next_frame :: proc (self:^animate_player) {
    for obj in self.objs {
        ianimate_object_next_frame(obj)
    }
}

/*
Gets the total number of frames for the animated object

Inputs:
- self: Pointer to the animated object

Returns:
- The total number of frames
*/
ianimate_object_get_frame_cnt :: #force_inline proc "contextless" (self:^ianimate_object) -> u32{
    return ((^ianimate_object_vtable)(self.vtable)).get_frame_cnt(self)
}

/*
Sets the current frame for the animated object

Inputs:
- self: Pointer to the animated object
- _frame: The frame number to set (will be clamped to valid range)

Returns:
- None
*/
ianimate_object_set_frame :: #force_inline proc (self:^ianimate_object, _frame:u32) {
    self.frame = (_frame) % ianimate_object_get_frame_cnt(self)
    ianimate_object_update_frame(self)
}

/*
Advances to the next frame (wraps around if at the end)

Inputs:
- self: Pointer to the animated object

Returns:
- None
*/
ianimate_object_next_frame :: #force_inline proc (self:^ianimate_object) {
    self.frame = (self.frame + 1) % ianimate_object_get_frame_cnt(self)
    ianimate_object_update_frame(self)
}

/*
Moves to the previous frame (wraps around if at the beginning)

Inputs:
- self: Pointer to the animated object

Returns:
- None
*/
ianimate_object_prev_frame :: #force_inline proc (self:^ianimate_object) {
    self.frame = self.frame > 0 ? (self.frame - 1) : ianimate_object_get_frame_cnt(self) - 1
    ianimate_object_update_frame(self)
}

/*
Updates the uniform buffer with the current frame data

Inputs:
- self: Pointer to the animated object

Returns:
- None
*/
ianimate_object_update_frame :: #force_inline proc (self:^ianimate_object) {
    engine.buffer_resource_copy_update(&self.frame_uniform, &self.frame)
}

/*
Animated image object structure for rendering animated textures

Extends ianimate_object with texture array source data
*/
animate_image :: struct {
    using _:ianimate_object,
    src: ^engine.texture_array,
}

ianimate_object_vtable :: struct {
    using _: engine.iobject_vtable,
    get_frame_cnt: #type proc "contextless" (self:^ianimate_object) -> u32,
}


@private animate_image_vtable :ianimate_object_vtable = ianimate_object_vtable {
    draw = auto_cast _super_animate_image_draw,
    deinit = auto_cast _super_animate_image_deinit,
    get_frame_cnt = auto_cast _super_animate_image_get_frame_cnt,
}

animate_image_init :: proc(self:^animate_image, $actualType:typeid, src:^engine.texture_array, pos:linalg.Point3DF, rotation:f32, scale:linalg.PointF = {1,1}, 
camera:^engine.camera, projection:^engine.projection, colorTransform:^engine.color_transform = nil, pivot:linalg.PointF = {0.0, 0.0}, vtable:^ianimate_object_vtable = nil) 
where intrinsics.type_is_subtype_of(actualType, animate_image) {
    self.src = src
    
    self.set.bindings = engine.descriptor_set_binding__animate_image_uniform_pool[:]
    self.set.size = engine.descriptor_pool_size__animate_image_uniform_pool[:]
    self.set.layout = engine.animate_tex_descriptor_set_layout

    self.vtable = auto_cast (vtable == nil ? &animate_image_vtable : vtable)
    if self.vtable.draw == nil do self.vtable.draw = auto_cast _super_animate_image_draw
    if self.vtable.deinit == nil do self.vtable.deinit = auto_cast _super_animate_image_deinit
    if ((^animator.ianimate_object_vtable)(self.vtable)).get_frame_cnt == nil do ((^animator.ianimate_object_vtable)(self.vtable)).get_frame_cnt = auto_cast _super_animate_image_get_frame_cnt

    if self.vtable.get_uniform_resources == nil do self.vtable.get_uniform_resources = auto_cast get_uniform_resources_animate_image

    engine.buffer_resource_create_buffer(&self.frame_uniform, {
        len = size_of(u32),
        type = .UNIFORM,
        resource_usage = .CPU,
    }, mem.ptr_to_bytes(&self.frame), true)

    iobject_init(self, actualType, pos, rotation, scale, camera, projection, colorTransform, pivot)
}

animate_image_init2 :: proc(self:^animate_image, $actualType:typeid, src:^engine.texture_array,
camera:^engine.camera, projection:^engine.projection, colorTransform:^engine.color_transform = nil, vtable:^ianimate_object_vtable = nil) 
where intrinsics.type_is_subtype_of(actualType, animate_image) {
    self.src = src
    
    self.set.bindings = engine.descriptor_set_binding__animate_image_uniform_pool[:]
    self.set.size = engine.descriptor_pool_size__animate_image_uniform_pool[:]
    self.set.layout = engine.animate_tex_descriptor_set_layout

    self.vtable = auto_cast (vtable == nil ? &animate_image_vtable : vtable)
    if self.vtable.draw == nil do self.vtable.draw = auto_cast _super_animate_image_draw
    if self.vtable.deinit == nil do self.vtable.deinit = auto_cast _super_animate_image_deinit
    if ((^ianimate_object_vtable)(self.vtable)).get_frame_cnt == nil do ((^ianimate_object_vtable)(self.vtable)).get_frame_cnt = auto_cast _super_animate_image_get_frame_cnt

    if self.vtable.get_uniform_resources == nil do self.vtable.get_uniform_resources = auto_cast get_uniform_resources_animate_image

    engine.buffer_resource_create_buffer(&self.frame_uniform, {
        len = size_of(u32),
        type = .UNIFORM,
        resource_usage = .CPU,
    }, mem.ptr_to_bytes(&self.frame), true)

    iobject_init2(self, actualType, camera, projection, colorTransform)
}

_super_animate_image_deinit :: proc(self:^animate_image) {
    clone_frame_uniform := new(engine.buffer_resource, engine.temp_arena_allocator())
    clone_frame_uniform^ = self.frame_uniform
    engine.buffer_resource_deinit(clone_frame_uniform)

    engine._super_iobject_deinit(auto_cast self)
}

animate_image_get_frame_cnt :: _super_animate_image_get_frame_cnt

/*
Gets the total number of frames for the animated image

Inputs:
- self: Pointer to the animated image

Returns:
- The total number of frames in the texture array
*/
_super_animate_image_get_frame_cnt :: proc "contextless" (self:^animate_image) -> u32 {
    return self.src.texture.option.len
}

/*
Gets the texture array source of the animated image

Inputs:
- self: Pointer to the animated image

Returns:
- Pointer to the texture array source
*/
animate_image_get_texture_array :: #force_inline proc "contextless" (self:^animate_image) -> ^engine.texture_array {
    return self.src
}

/*
Gets the camera of the animated image

Inputs:
- self: Pointer to the animated image

Returns:
- Pointer to the camera
*/
animate_image_get_camera :: proc "contextless" (self:^animate_image) -> ^engine.camera {
    return self.camera
}

/*
Gets the projection of the animated image

Inputs:
- self: Pointer to the animated image

Returns:
- Pointer to the projection
*/
animate_image_get_projection :: proc "contextless" (self:^animate_image) -> ^engine.projection {
    return self.projection
}

/*
Gets the color transform of the animated image

Inputs:
- self: Pointer to the animated image

Returns:
- Pointer to the color transform
*/
animate_image_get_color_transform :: proc "contextless" (self:^animate_image) -> ^engine.color_transform {
    return self.color_transform
}

animate_image_update_transform :: #force_inline proc(self:^animate_image, pos:linalg.Point3DF, rotation:f32, scale:linalg.PointF = {1,1}, pivot:linalg.PointF = {0.0,0.0}) {
    engine.iobject_update_transform(self, pos, rotation, scale, pivot)
}
animate_image_update_transform_matrix_raw :: #force_inline proc(self:^animate_image, _mat:linalg.Matrix) {
    engine.iobject_update_transform_matrix_raw(self, _mat)
}
animate_image_change_color_transform :: #force_inline proc(self:^animate_image, colorTransform:^engine.color_transform) {
    engine.iobject_change_color_transform(self, colorTransform)
}
animate_image_update_camera :: #force_inline proc(self:^animate_image, camera:^engine.camera) {
    engine.iobject_update_camera(self, camera)
}
animate_image_update_texture_array :: #force_inline proc "contextless" (self:^animate_image, src:^engine.texture_array) {
    self.src = src
}
animate_image_update_projection :: #force_inline proc(self:^animate_image, projection:^engine.projection) {
    engine.iobject_update_projection(self, projection)
}

_super_animate_image_draw :: proc (self:^animate_image, cmd:engine.command_buffer) {
    mem.ICheckInit_Check(&self.check_init)
    mem.ICheckInit_Check(&self.src.check_init)

    engine.graphics_cmd_bind_pipeline(cmd, .GRAPHICS, engine.get_animate_tex_pipeline())
    engine.graphics_cmd_bind_descriptor_sets(cmd, .GRAPHICS, engine.get_animate_tex_pipeline_layout(), 0, 2,
        &([]vk.DescriptorSet{self.set.__set, self.src.set.__set})[0], 0, nil)

    engine.graphics_cmd_draw(cmd, 6, 1, 0, 0)
}

@private get_uniform_resources_animate_image :: #force_inline proc(self:^engine.iobject) -> []engine.union_resource {
    res := mem.make_non_zeroed([]engine.union_resource, 5, context.temp_allocator)
    res[0] = &self.mat_uniform
    res[1] = &self.camera.mat_uniform
    res[2] = &self.projection.mat_uniform
    res[3] = &self.color_transform.mat_uniform

    animate_image_ : ^animate_image = auto_cast self
    res[4] = &animate_image_.frame_uniform
    return res[:]
}