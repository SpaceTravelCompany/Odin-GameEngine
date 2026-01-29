package component

import "base:intrinsics"
import "core:math/linalg"
import "core:mem"
import "core:engine"
import "core:engine/shape"
import "core:log"
import "base:runtime"
import "core:sync"
import vk "vendor:vulkan"


button_state :: enum {
    UP,OVER,DOWN,
}

image_button :: struct {
    using _:button,
    up_texture:^engine.texture,
    over_texture:^engine.texture,
    down_texture:^engine.texture,
}

@private g_buttons:[dynamic]^button
@private g_buttons_mtx:sync.Mutex

@(private) g_buttons_init :: proc (self:^button) {
	sync.mutex_lock(&g_buttons_mtx)
	defer sync.mutex_unlock(&g_buttons_mtx)
	if g_buttons.allocator.procedure == nil {
		g_buttons = mem.make_non_zeroed([dynamic]^button,runtime.default_allocator())
	}
}

@(private, fini) g_buttons_fini :: proc "contextless" () {
	sync.mutex_lock(&g_buttons_mtx)
	defer sync.mutex_unlock(&g_buttons_mtx)
	if g_buttons.allocator.procedure != nil {
		context = runtime.default_context()
		delete(g_buttons)
	}
}

@private g_buttons_append :: proc (self:^button) {
	sync.mutex_lock(&g_buttons_mtx)
	defer sync.mutex_unlock(&g_buttons_mtx)
	if g_buttons.allocator.procedure != nil {
		non_zero_append_elem(&g_buttons, self)
	}
}
@private g_buttons_remove :: proc (self:^button) {
	sync.mutex_lock(&g_buttons_mtx)
	defer sync.mutex_unlock(&g_buttons_mtx)
	if g_buttons.allocator.procedure != nil {
		for button, i  in g_buttons {
			if button == self {
				unordered_remove(&g_buttons, i)
				break
			}
		}
	}
}

button_up :: proc (self:^button, mousePos:linalg.point) {
    if self.state == .DOWN {
		point_in := false
		btable :^button_vtable = auto_cast self.vtable
		if btable.__over_exists(self) {
			if _, ok := (cast(^image_button)self).area.(linalg.ImageArea); self.actual_type == image_button && ok {
				point_in = image_button_point_in(cast(^image_button)self, mousePos)
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
		if _, ok := (cast(^image_button)self).area.(linalg.ImageArea); self.actual_type == image_button && ok {
			point_in = image_button_point_in(cast(^image_button)self, mousePos)
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
	if _, ok := (cast(^image_button)self).area.(linalg.ImageArea); self.actual_type == image_button && ok {
		point_in = image_button_point_in(cast(^image_button)self, mousePos)
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
		if _, ok := (cast(^image_button)self).area.(linalg.ImageArea); self.actual_type == image_button && ok {
			point_in = image_button_point_in(cast(^image_button)self, pointerPos)
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
// Check if point is inside image button using texture pixel alpha value
@private image_button_point_in :: proc(self:^image_button, point:linalg.point) -> bool {
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
	if _, ok := (cast(^image_button)self).area.(linalg.ImageArea); self.actual_type == image_button && ok {
		__handle(self, pointerPos, pointerIdx, image_button_point_in(cast(^image_button)self, pointerPos))
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
    up_shape_src:^shape.shape_src,
    over_shape_src:^shape.shape_src,
    down_shape_src:^shape.shape_src,
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

@private image_button_vtable :button_vtable = button_vtable {
    draw = auto_cast _super_image_button_draw,
	__over_exists = auto_cast image_button_over_exists,
	__down_exists = auto_cast image_button_down_exists,
	__up_exists = auto_cast image_button_up_exists,
	deinit = auto_cast _super_button_deinit,
}

@private shape_button_vtable :button_vtable = button_vtable {
    draw = auto_cast _super_shape_button_draw,
	__over_exists = auto_cast shape_button_over_exists,
	__down_exists = auto_cast shape_button_down_exists,
	__up_exists = auto_cast shape_button_up_exists,
	deinit = auto_cast _super_button_deinit,
}

@private button_vtable_default :button_vtable = button_vtable {
	deinit = auto_cast _super_button_deinit,
}

handle_button_down :: proc (mousePos:linalg.point) {
	sync.mutex_lock(&g_buttons_mtx)
	defer sync.mutex_unlock(&g_buttons_mtx)
	for button in g_buttons {
		button_down(button, mousePos)
	}	
}
handle_button_up :: proc (mousePos:linalg.point) {
	sync.mutex_lock(&g_buttons_mtx)
	defer sync.mutex_unlock(&g_buttons_mtx)
	for button in g_buttons {
		button_up(button, mousePos)
	}
}
handle_button_move :: proc (mousePos:linalg.point) {
	sync.mutex_lock(&g_buttons_mtx)
	defer sync.mutex_unlock(&g_buttons_mtx)
	for button in g_buttons {
		button_move(button, mousePos)
	}
}

handle_pointer_down :: proc (pointerPos:linalg.point, pointerIdx:u8) {
	sync.mutex_lock(&g_buttons_mtx)
	defer sync.mutex_unlock(&g_buttons_mtx)
	for button in g_buttons {
		button_pointer_down(button, pointerPos, pointerIdx)
	}
}
handle_pointer_up :: proc (pointerPos:linalg.point, pointerIdx:u8) {
	sync.mutex_lock(&g_buttons_mtx)
	defer sync.mutex_unlock(&g_buttons_mtx)
	for button in g_buttons {
		button_pointer_up(button, pointerPos, pointerIdx)
	}
}
handle_pointer_move :: proc (pointerPos:linalg.point, pointerIdx:u8) {
	sync.mutex_lock(&g_buttons_mtx)
	defer sync.mutex_unlock(&g_buttons_mtx)
	for button in g_buttons {
		button_pointer_move(button, pointerPos, pointerIdx)
	}
}

image_button_over_exists :: proc (self:^image_button) -> bool {
	return self.over_texture != nil
}
image_button_down_exists :: proc (self:^image_button) -> bool {
	return self.down_texture != nil
}
image_button_up_exists :: proc (self:^image_button) -> bool {
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


_super_image_button_draw :: proc (self:^image_button, cmd:engine.command_buffer, viewport:engine.viewport) {
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
	if engine.graphics_get_resource_draw(self) == nil do return
	if engine.graphics_get_resource_draw(texture) == nil do return

    engine.image_binding_sets_and_draw(cmd, self.set, viewport.set, texture.set)
}


image_button_init :: proc(self:^image_button,
up:^engine.texture = nil, over:^engine.texture = nil, down:^engine.texture = nil, colorTransform:^engine.color_transform = nil, vtable:^button_vtable = nil,
ref_viewport:^engine.viewport = nil) {
    self.up_texture = up
    self.over_texture = over
    self.down_texture = down

	self.set.bindings = engine.descriptor_set_binding__base_uniform_pool[:]
    self.set.size = engine.descriptor_pool_size__base_uniform_pool[:]
    self.set.layout = engine.base_descriptor_set_layout()

	self.vtable = vtable == nil ? &image_button_vtable : vtable
    if self.vtable.draw == nil do self.vtable.draw = auto_cast _super_image_button_draw

	_super_button_init(self, colorTransform, auto_cast self.vtable)
	self.actual_type = typeid_of(image_button)
	self.ref_viewport = ref_viewport
}


_super_shape_button_draw :: proc (self:^shape_button, cmd:engine.command_buffer, viewport:^engine.viewport) {
    shape_src :^shape.shape_src

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

	shape.shape_src_bind_and_draw(shape_src, &self.set, cmd, viewport)
}

_super_button_deinit :: proc (self:^button) {
	g_buttons_remove(self)
	engine._super_itransform_object_deinit(self)
}

_super_button_init :: proc (self:^button, colorTransform:^engine.color_transform = nil, vtable:^button_vtable = nil,
ref_viewport:^engine.viewport = nil) {
	g_buttons_init(self)
	g_buttons_append(self)

	btable :^button_vtable = vtable == nil ? &button_vtable_default : vtable
	if btable.__over_exists == nil do btable.__over_exists = auto_cast shape_button_over_exists
	if btable.__down_exists == nil do btable.__down_exists = auto_cast shape_button_down_exists
	if btable.__up_exists == nil do btable.__up_exists = auto_cast shape_button_up_exists
	if btable.deinit == nil do btable.deinit = auto_cast _super_button_deinit
	self.vtable = btable

	engine.itransform_object_init(self, colorTransform, self.vtable)
	self.actual_type = typeid_of(button)
	self.ref_viewport = ref_viewport
}

shape_button_init :: proc(self:^shape_button,
up:^shape.shape_src = nil, over:^shape.shape_src = nil, down:^shape.shape_src = nil, colorTransform:^engine.color_transform = nil, vtable:^button_vtable = nil,
ref_viewport:^engine.viewport = nil) {
    self.up_shape_src = up
    self.over_shape_src = over
    self.down_shape_src = down

	self.set.bindings = engine.descriptor_set_binding__base_uniform_pool[:]
    self.set.size = engine.descriptor_pool_size__base_uniform_pool[:]
    self.set.layout = engine.base_descriptor_set_layout()

	self.vtable = vtable == nil ? &shape_button_vtable : vtable
    if self.vtable.draw == nil do self.vtable.draw = auto_cast _super_shape_button_draw

	_super_button_init(self, colorTransform, auto_cast self.vtable)
	self.actual_type = typeid_of(shape_button)
}