package engine

import graphics_api "./graphics_api"

ianimate_object :: struct {
    using object:IObject,
    frameUniform:graphics_api.BufferResource,
    frame:u32,
}

animate_player :: struct {
    objs:[]^ianimate_object,
    target_fps:f64,
    __playing_dt:f64,
    playing:bool,
    loop:bool,
}

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


animate_player_stop :: #force_inline proc "contextless" (self:^animate_player) {
    self.playing = false
}

animate_player_play :: #force_inline proc "contextless" (self:^animate_player) {
    self.playing = true
    self.__playing_dt = 0.0
}

animate_player_set_frame :: proc (self:^animate_player, _frame:u32) {
    for obj in self.objs {
        ianimate_object_set_frame(obj, _frame)
    }
}

animate_player_prev_frame :: proc (self:^animate_player) {
    for obj in self.objs {
        ianimate_object_prev_frame(obj)
    }
}

animate_player_next_frame :: proc (self:^animate_player) {
    for obj in self.objs {
        ianimate_object_next_frame(obj)
    }
}

ianimate_object_get_frame_cnt :: #force_inline proc "contextless" (self:^ianimate_object) -> u32{
    return ((^IAnimateObjectVTable)(self.vtable)).get_frame_cnt(self)
}

ianimate_object_update_frame :: #force_inline proc (self:^ianimate_object) {
    BufferResource_CopyUpdate(&self.frameUniform, &self.frame)
}

ianimate_object_next_frame :: #force_inline proc (self:^ianimate_object) {
    self.frame = (self.frame + 1) % ianimate_object_get_frame_cnt(self)
    ianimate_object_update_frame(self)
}

ianimate_object_prev_frame :: #force_inline proc (self:^ianimate_object) {
    self.frame = self.frame > 0 ? (self.frame - 1) : ianimate_object_get_frame_cnt(self) - 1
    ianimate_object_update_frame(self)
}

ianimate_object_set_frame :: #force_inline proc (self:^ianimate_object, _frame:u32) {
    self.frame = (_frame) % ianimate_object_get_frame_cnt(self)
    ianimate_object_update_frame(self)
}
