package component

import "base:intrinsics"
import "core:math/linalg"
import "core:engine"
import "core:engine/sprite"
import "core:engine/shape"
import "core:engine/geometry"
import "core:log"
import "base:runtime"
import vk "vendor:vulkan"


button_state :: enum {
    UP,OVER,DOWN,
}

sprite_button :: struct {
    using _:button,
    up_texture:^engine.texture,
    over_texture:^engine.texture,
    down_texture:^engine.texture,
}

button_up :: proc (self:^button, mousePos:linalg.point) {
    if self.state == .DOWN {
		point_in := false
		btable :^button_vtable = auto_cast self.vtable
		if btable.__over_exists(self) {
			if _, ok := (cast(^sprite_button)self).area.(linalg.ImageArea); self.actual_type == sprite_button && ok {
				point_in = sprite_button_point_in(cast(^sprite_button)self, mousePos)
			} else {
				tmp_area := engine.itransform_object_cvt_area_window_coord(self, self.area, self.ref_viewport, context.temp_allocator)
				point_in = linalg.Area_PointIn(tmp_area, mousePos)
				defer if f2, ok := tmp_area.([][2]f32); ok {
					delete(f2, context.temp_allocator)
				}
			}
		}
        if point_in {
            self.state = .OVER
        } else {
            self.state = .UP
        }
        //UPDATE
        if self.button_up_callback != nil do self.button_up_callback(self, mousePos)
    }
}
button_down :: proc (self:^button, mousePos:linalg.point) {
    if self.state == .UP {
		point_in := false
		if _, ok := (cast(^sprite_button)self).area.(linalg.ImageArea); self.actual_type == sprite_button && ok {
			point_in = sprite_button_point_in(cast(^sprite_button)self, mousePos)
		} else {
			tmp_area := engine.itransform_object_cvt_area_window_coord(self, self.area, self.ref_viewport, context.temp_allocator)
			point_in = linalg.Area_PointIn(tmp_area, mousePos)
			defer if f2, ok := tmp_area.([][2]f32); ok {
				delete(f2, context.temp_allocator)
			}
		}
        if point_in {
            self.state = .DOWN
            //UPDATE
            if self.button_down_callback != nil do self.button_down_callback(self, mousePos)
        }    
    } else if self.state == .OVER {
        self.state = .DOWN
        //UPDATE
        if self.button_down_callback != nil do self.button_down_callback(self, mousePos)
    }
}
button_move :: proc (self:^button, mousePos:linalg.point) {
	btable :^button_vtable = auto_cast self.vtable
	if !btable.__over_exists(self) && self.button_move_callback == nil do return

	point_in := false
	if _, ok := (cast(^sprite_button)self).area.(linalg.ImageArea); self.actual_type == sprite_button && ok {
		point_in = sprite_button_point_in(cast(^sprite_button)self, mousePos)
	} else {
		tmp_area := engine.itransform_object_cvt_area_window_coord(self, self.area, self.ref_viewport, context.temp_allocator)
		point_in = linalg.Area_PointIn(tmp_area, mousePos)
		defer if f2, ok := tmp_area.([][2]f32); ok {
			delete(f2, context.temp_allocator)
		}
	}
    if point_in {
        if self.state == .UP {
            self.state = .OVER
            //UPDATE
        }
        if self.button_move_callback != nil do self.button_move_callback(self, mousePos)
    } else {
        if self.state != .UP {
            self.state = .UP
            //UPDATE
        }
    }
}
button_pointer_up :: proc (self:^button, pointerPos:linalg.point, pointerIdx:u8) {
    if self.state == .DOWN && self.pointerIdx != nil && self.pointerIdx.? == pointerIdx {
        self.state = .UP
        self.pointerIdx = nil
        //UPDATE
        if self.pointer_up_callback != nil do self.pointer_up_callback(self, pointerPos, pointerIdx)
    }
}
button_pointer_down :: proc (self:^button, pointerPos:linalg.point, pointerIdx:u8) {
    if self.state == .UP {
		point_in := false
		if _, ok := (cast(^sprite_button)self).area.(linalg.ImageArea); self.actual_type == sprite_button && ok {
			point_in = sprite_button_point_in(cast(^sprite_button)self, pointerPos)
		} else {
			tmp_area := engine.itransform_object_cvt_area_window_coord(self, self.area, self.ref_viewport, context.temp_allocator)
			point_in = linalg.Area_PointIn(tmp_area, pointerPos)
			defer if f2, ok := tmp_area.([][2]f32); ok {
				delete(f2, context.temp_allocator)
			}
		}
        if point_in {
            self.state = .DOWN
            self.pointerIdx = pointerIdx
            //UPDATE
            if self.pointer_down_callback != nil do self.pointer_down_callback(self, pointerPos, pointerIdx)
        }    
    } else if self.pointerIdx != nil && self.pointerIdx.? == pointerIdx {
        self.state = .UP
        self.pointerIdx = nil
        //UPDATE
    }
}
// Check if point is inside sprite button using texture pixel alpha value
@private sprite_button_point_in :: proc(self:^sprite_button, point:linalg.point) -> bool {
	texture: ^engine.texture
	switch self.state {
	case .UP: texture = self.up_texture
	case .OVER: texture = self.over_texture
	case .DOWN: texture = self.down_texture
	}
	if texture == nil do texture = self.up_texture
	if texture == nil do return false
	return engine.texture_point_in(texture, point, self.mat, self.ref_viewport)
}

button_pointer_move :: proc (self:^button, pointerPos:linalg.point, pointerIdx:u8) {
	__handle :: proc (self:^button, pointerPos:linalg.point, pointerIdx:u8, check:bool) {
		if check {
			if self.pointerIdx == nil && self.state == .UP {
				self.pointerIdx = pointerIdx
				self.state = .OVER
				//UPDATE
				if self.pointer_move_callback != nil do self.pointer_move_callback(self, pointerPos, pointerIdx)
			}
		} else if self.pointerIdx != nil && self.pointerIdx.? == pointerIdx {
			self.pointerIdx = nil
			if self.state != .UP {
				self.state = .UP
				//UPDATE
			}
		}
	}
	if _, ok := (cast(^sprite_button)self).area.(linalg.ImageArea); self.actual_type == sprite_button && ok {
		__handle(self, pointerPos, pointerIdx, sprite_button_point_in(cast(^sprite_button)self, pointerPos))
	} else {
		tmp_area := engine.itransform_object_cvt_area_window_coord(self, self.area, self.ref_viewport, context.temp_allocator)
		defer {
			if f2, ok := tmp_area.([][2]f32); ok {
				delete(f2, context.temp_allocator)
			}
		}
		__handle(self, pointerPos, pointerIdx, linalg.Area_PointIn(tmp_area, pointerPos))
	}
}

button :: struct {
    using _:engine.itransform_object,
    area:linalg.AreaF,
	ref_viewport:^engine.viewport,
    state : button_state,
    pointerIdx:Maybe(u8),
    button_up_callback: proc (self:^button, mousePos:linalg.point),
    button_down_callback: proc (self:^button, mousePos:linalg.point),
    button_move_callback: proc (self:^button, mousePos:linalg.point),
    pointer_down_callback: proc (self:^button, pointerPos:linalg.point, pointerIdx:u8),
    pointer_up_callback: proc (self:^button, pointerPos:linalg.point, pointerIdx:u8),
    pointer_move_callback: proc (self:^button, pointerPos:linalg.point, pointerIdx:u8),
}

shape_button :: struct {
    using _:button,
    up_shape_src:^geometry.shapes,
    over_shape_src:^geometry.shapes,
    down_shape_src:^geometry.shapes,
}

button_vtable :: struct {
    using _: engine.iobject_vtable,
    button_up: proc (self:^button, mousePos:linalg.point),
    button_down: proc (self:^button, mousePos:linalg.point),
    button_move: proc (self:^button, mousePos:linalg.point),
    pointer_down: proc (self:^button, pointerPos:linalg.point, pointerIdx:u8),
    pointer_up: proc (self:^button, pointerPos:linalg.point, pointerIdx:u8),
    pointer_move: proc (self:^button, pointerPos:linalg.point, pointerIdx:u8),

	__over_exists : proc (self:^button) -> bool,
	__down_exists : proc (self:^button) -> bool,
	__up_exists : proc (self:^button) -> bool,
}

//leave empty
@private __button_vtable :button_vtable = button_vtable {
}

@private sprite_button_vtable :button_vtable = button_vtable {
    draw = auto_cast sprite_button_draw,
	__over_exists = auto_cast sprite_button_over_exists,
	__down_exists = auto_cast sprite_button_down_exists,
	__up_exists = auto_cast sprite_button_up_exists,
}

@private shape_button_vtable :button_vtable = button_vtable {
    draw = auto_cast shape_button_draw,
	__over_exists = auto_cast shape_button_over_exists,
	__down_exists = auto_cast shape_button_down_exists,
	__up_exists = auto_cast shape_button_up_exists,
}

sprite_button_over_exists :: proc (self:^sprite_button) -> bool {
	return self.over_texture != nil
}
sprite_button_down_exists :: proc (self:^sprite_button) -> bool {
	return self.down_texture != nil
}
sprite_button_up_exists :: proc (self:^sprite_button) -> bool {
	return self.up_texture != nil
}
shape_button_over_exists :: proc (self:^shape_button) -> bool {
	return self.over_shape_src != nil
}
shape_button_down_exists :: proc (self:^shape_button) -> bool {
	return self.down_shape_src != nil
}
shape_button_up_exists :: proc (self:^shape_button) -> bool {
	return self.up_shape_src != nil
}

sprite_button_draw :: proc (self:^sprite_button, cmd:engine.command_buffer, viewport:^engine.viewport) {
    texture :^engine.texture

    switch self.state {
        case .UP:texture = self.up_texture
        case .OVER:texture = self.over_texture
        case .DOWN:texture = self.down_texture
    }
    if texture == nil {
		texture = self.up_texture
	}
	//self의 uniform, texture 리소스가 준비가 안됨. 드로우 하면 안됨.
	if engine.graphics_get_resource_draw(self.mat_idx) == nil do return
	if engine.graphics_get_resource_draw(texture.idx) == nil do return

    sprite.sprite_binding_sets_and_draw(cmd, self.set, viewport.set, texture.set)
}


sprite_button_init :: proc(self:^sprite_button,
up:^engine.texture = nil, over:^engine.texture = nil, down:^engine.texture = nil, colorTransform:^engine.color_transform = nil, vtable:^button_vtable = nil,
ref_viewport:^engine.viewport = nil) {
    self.up_texture = up
    self.over_texture = over
    self.down_texture = down

	if vtable == nil {
		self.vtable = &sprite_button_vtable
	} else {
		self.vtable = vtable
		if self.vtable.draw == nil do self.vtable.draw = auto_cast sprite_button_draw
		if (^button_vtable)(self.vtable).__over_exists == nil do (^button_vtable)(self.vtable).__over_exists = auto_cast sprite_button_over_exists
		if (^button_vtable)(self.vtable).__down_exists == nil do (^button_vtable)(self.vtable).__down_exists = auto_cast sprite_button_down_exists
		if (^button_vtable)(self.vtable).__up_exists == nil do (^button_vtable)(self.vtable).__up_exists = auto_cast sprite_button_up_exists
	}
	button_init(self, colorTransform, auto_cast self.vtable)
	self.actual_type = typeid_of(sprite_button)
	self.ref_viewport = ref_viewport
}


shape_button_draw :: proc (self:^shape_button, cmd:engine.command_buffer, viewport:^engine.viewport) {
    shape_src :^geometry.shapes

    switch self.state {
        case .UP:shape_src = self.up_shape_src
        case .OVER:
			shape_src = self.over_shape_src
			if shape_src == nil do shape_src = self.up_shape_src
        case .DOWN:
			shape_src = self.down_shape_src
			if shape_src == nil do shape_src = self.up_shape_src
    }
    if shape_src == nil do log.panic("shape: uninitialized\n")

	shape.shape_bind_and_draw(cmd, shape_src, self.mat, viewport)
}

button_unregister :: proc (self:^button) {
}

button_init :: proc (self:^button, colorTransform:^engine.color_transform = nil, vtable:^button_vtable = nil,
ref_viewport:^engine.viewport = nil) {
	if vtable == nil {
		self.vtable = &__button_vtable
	} else {
		self.vtable = vtable
	}

	engine.itransform_object_init(self, colorTransform, self.vtable)
	self.actual_type = typeid_of(button)
	self.ref_viewport = ref_viewport
}

shape_button_init :: proc(self:^shape_button,
up:^geometry.shapes = nil, over:^geometry.shapes = nil, down:^geometry.shapes = nil, colorTransform:^engine.color_transform = nil, vtable:^button_vtable = nil,
ref_viewport:^engine.viewport = nil) {
    self.up_shape_src = up
    self.over_shape_src = over
    self.down_shape_src = down

	if vtable == nil {
		self.vtable = &shape_button_vtable
	} else {
		self.vtable = vtable
		if self.vtable.draw == nil do self.vtable.draw = auto_cast shape_button_draw
		if (^button_vtable)(self.vtable).__over_exists == nil do (^button_vtable)(self.vtable).__over_exists = auto_cast shape_button_over_exists
		if (^button_vtable)(self.vtable).__down_exists == nil do (^button_vtable)(self.vtable).__down_exists = auto_cast shape_button_down_exists
		if (^button_vtable)(self.vtable).__up_exists == nil do (^button_vtable)(self.vtable).__up_exists = auto_cast shape_button_up_exists
	}
	button_init(self, colorTransform, auto_cast self.vtable)
	self.actual_type = typeid_of(shape_button)
}