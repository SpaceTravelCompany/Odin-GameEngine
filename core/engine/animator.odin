package engine



/*
Animated object structure that extends iobject with frame animation support

Contains frame information and uniform buffer for frame data
*/
ianimate_object :: struct {
    using object:iobject,
    frame_uniform:buffer_resource,
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

// ============================================================================
// IAnimate Object Functions
// ============================================================================

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
    buffer_resource_copy_update(&self.frame_uniform, &self.frame)
}
