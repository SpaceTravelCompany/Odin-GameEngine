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
	using _:engine.itransform_object,
	 target_fps:f64,
    __playing_dt:f64,
    frame:u32,
	frame_idx:Maybe(u32),
	playing:bool,
    loop:bool,
}

ianimate_object_vtable :: struct {
	using _:engine.iobject_vtable,
	get_frame_cnt : #type proc "contextless" (self:^ianimate_object) -> u32
}

@private __ianimate_object_vtable :ianimate_object_vtable = ianimate_object_vtable {
    update = auto_cast ianimate_object_update,
}


ianimate_object_update :: proc (self:^ianimate_object) {
    if self.playing {
		if  self.target_fps == 0.0 {
			if self.frame < ianimate_object_get_frame_cnt(self) - 2 {
				ianimate_object_next_frame(self)
			} else {
				if self.loop {
					ianimate_object_set_frame(self, 0)
				} else {
					ianimate_object_stop(self)
				}
			}
		} else {
			self.__playing_dt += engine.dt()
			for self.__playing_dt >= 1 / self.target_fps {
				if self.frame < ianimate_object_get_frame_cnt(self) - 2 {
					ianimate_object_next_frame(self)
				} else {
					if self.loop {
						ianimate_object_set_frame(self, 0)
					} else {
						ianimate_object_stop(self)
					}
				}
				self.__playing_dt -= 1.0 / self.target_fps
			}
		}
    }
}

ianimate_object_init :: proc(self:^ianimate_object, colorTransform:^engine.color_transform = nil, vtable:^ianimate_object_vtable = nil) {
	res:engine.punion_resource
	res, self.frame_idx = engine.buffer_resource_create_buffer(self.frame_idx, {
		size = size_of(u32),
		type = .UNIFORM,
		resource_usage = .CPU,
	}, mem.ptr_to_bytes(&self.frame))
	if vtable == nil {
		self.vtable = &__ianimate_object_vtable
	} else {
		self.vtable = vtable
		if self.vtable.update == nil do self.vtable.update = auto_cast ianimate_object_update
	}
	engine.itransform_object_init(self, colorTransform, vtable)
	self.actual_type = typeid_of(ianimate_object)
}

ianimate_object_deinit :: proc(self:^ianimate_object) {
	if self.frame_idx != nil do engine.buffer_resource_deinit(self.frame_idx.?)
	engine.itransform_object_deinit(self)
}

ianimate_object_play :: proc "contextless" (self:^ianimate_object) {
    self.playing = true
    self.__playing_dt = 0.0
}

ianimate_object_stop :: proc "contextless" (self:^ianimate_object) {
    self.playing = false
}

ianimate_object_get_frame_cnt :: proc "contextless" (self:^ianimate_object) -> u32{
    return ((^ianimate_object_vtable)(self.vtable)).get_frame_cnt(self)
}

ianimate_object_set_frame :: proc (self:^ianimate_object, _frame:u32) {
    self.frame = (_frame) % ianimate_object_get_frame_cnt(self)
    ianimate_object_update_frame(self)
}

ianimate_object_next_frame :: proc (self:^ianimate_object) {
    self.frame = (self.frame + 1) % ianimate_object_get_frame_cnt(self)
    ianimate_object_update_frame(self)
}

ianimate_object_prev_frame :: proc (self:^ianimate_object) {
    self.frame = self.frame > 0 ? (self.frame - 1) : ianimate_object_get_frame_cnt(self) - 1
    ianimate_object_update_frame(self)
}

ianimate_object_update_frame :: proc (self:^ianimate_object) {
	if self.frame_idx != nil do engine.buffer_resource_copy_update(self.frame_idx.?, &self.frame)
}
