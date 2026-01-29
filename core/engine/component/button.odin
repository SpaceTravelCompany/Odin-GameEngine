package component

import "base:intrinsics"
import "core:math/linalg"
import "core:mem"
import "core:engine"
import "core:engine/shape"
import "core:log"

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

button_up :: proc (self:^button, mousePos:linalg.point) {
    if self.state == .DOWN {
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
	// Get texture based on current state
	texture: ^engine.texture
	switch self.state {
	case .UP: texture = self.up_texture
	case .OVER: texture = self.over_texture
	case .DOWN: texture = self.down_texture
	}
	
	if texture == nil do texture = self.up_texture
	if texture == nil do return false
	
	tex_width := engine.texture_width(texture)
	tex_height := engine.texture_height(texture)
	
	if tex_width == 0 || tex_height == 0 do return false
	if len(texture.pixel_data) == 0 do return false

	// Convert window coordinates to local coordinates using inverse matrices
	// Note: In shader, local coordinates are scaled by texture size: quad * textureSize
	// So local range is (-0.5 * tex_width, -0.5 * tex_height) to (0.5 * tex_width, 0.5 * tex_height)
	viewport_ := self.ref_viewport
	if viewport_ == nil {
		viewport_ = engine.def_viewport()
	}
	// Convert window coordinates to normalized device coordinates (NDC)
	// Window coordinates: (0,0) top-left to (window_width, window_height) bottom-right
	// NDC: (-1,-1) bottom-left to (1,1) top-right
	w := f32(engine.window_width())
	h := f32(engine.window_height())
	ndc_x := 2.0 * point.x / w - 1.0
	ndc_y := 2.0 * point.y / h - 1.0
	

	// Transform from NDC to local coordinates: shader uses proj * view * model * (quad * textureSize)
	// So inverse(proj * view * model) * ndc gives point in (quad*textureSize) space
	tmp_mat := viewport_.projection.mat * viewport_.camera.mat * self.mat * linalg.matrix4_scale(linalg.Vector3f32{f32(tex_width), f32(tex_height), 1.0})
	pt_ := linalg.point3dw{ndc_x, ndc_y, 0.0, 1.0}
	pt_ = linalg.mul(linalg.inverse(tmp_mat), pt_)
	// Point is in quad*textureSize space; normalize to -0.5..0.5 for UV
	local_pos := linalg.point{(pt_.x / pt_.w), (pt_.y * -1.0 / pt_.w)}
	
	// Check if normalized local position is within the quad bounds (-0.5 to 0.5)
	if local_pos.x < -0.5 || local_pos.x > 0.5 do return false
	if local_pos.y < -0.5 || local_pos.y > 0.5 do return false
	if texture.pixel_data == nil do return true // if texture pixel data is not set, check only rect area
	
	// Convert to texture UV coordinates
	// uv_x = normalized_local_x + 0.5  (0 to 1)
	// uv_y = normalized_local_y + 0.5  (0 to 1)
	uv_x := local_pos.x + 0.5
	uv_y := local_pos.y + 0.5
	
	// Convert UV to texture pixel coordinates
	tex_x := i32(uv_x * f32(tex_width))
	tex_y := i32(uv_y * f32(tex_height))
	
	// Clamp to texture bounds
	if tex_x < 0 || tex_x >= i32(tex_width) do return false
	if tex_y < 0 || tex_y >= i32(tex_height) do return false
	
	// Check alpha value at pixel position
	// pixel_data is RGBA format (4 bytes per pixel)
	bytes_per_pixel: u32 = 4
	pixel_idx := (u32(tex_y) * tex_width + u32(tex_x)) * bytes_per_pixel
	
	if pixel_idx + 3 >= u32(len(texture.pixel_data)) do return false
	
	alpha := texture.pixel_data[pixel_idx + 3]  // Alpha channel is the 4th byte
	alpha_threshold: u8 :  1  // Consider pixels with alpha > 0 as visible
	
	return alpha >= alpha_threshold
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
}

@private image_button_vtable :button_vtable = button_vtable {
    draw = auto_cast _super_image_button_draw,
}

@private shape_button_vtable :button_vtable = button_vtable {
    draw = auto_cast _super_shape_button_draw,
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

	engine.itransform_object_init(self, colorTransform, self.vtable)
	self.actual_type = typeid_of(image_button)
	self.ref_viewport = ref_viewport
}


_super_shape_button_draw :: proc (self:^shape_button, cmd:engine.command_buffer, viewport:^engine.viewport) {
    shape_src :^shape.shape_src

    switch self.state {
        case .UP:shape_src = self.up_shape_src
        case .OVER:shape_src = self.over_shape_src
        case .DOWN:shape_src = self.down_shape_src
    }
    if shape_src == nil do log.panic("shape: uninitialized\n")

	shape.shape_src_bind_and_draw(shape_src, &self.set, cmd, viewport)
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

	engine.itransform_object_init(self, colorTransform, self.vtable)
	self.actual_type = typeid_of(shape_button)
	self.ref_viewport = ref_viewport
}