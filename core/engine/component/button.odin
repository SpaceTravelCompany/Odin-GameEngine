package component

import "base:intrinsics"
import "core:math/linalg"
import "core:mem"
import "core:engine"
import "core:engine/shape"

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
        if linalg.Area_PointIn(self.area, mousePos) {
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
        if linalg.Area_PointIn(self.area, mousePos) {
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
    if linalg.Area_PointIn(self.area, mousePos) {
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
        if linalg.Area_PointIn(self.area, pointerPos) {
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
button_pointer_move :: proc (self:^button, pointerPos:linalg.point, pointerIdx:u8) {
    if linalg.Area_PointIn(self.area, pointerPos) {
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

button :: struct {
    using _:engine.iobject,
    area:linalg.AreaF,
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
    deinit = auto_cast _super_image_button_deinit,
}

@private shape_button_vtable :button_vtable = button_vtable {
    draw = auto_cast _super_shape_button_draw,
    deinit = auto_cast _super_shape_button_deinit,
}

_super_image_button_deinit :: proc(self:^image_button) {
    engine._super_iobject_deinit(auto_cast self)
}

_super_image_button_draw :: proc (self:^image_button, cmd:engine.command_buffer, viewport:engine.viewport) {
    mem.ICheckInit_Check(&self.check_init)
    texture :^engine.texture

    switch self.state {
        case .UP:texture = self.up_texture
        case .OVER:texture = self.over_texture
        case .DOWN:texture = self.down_texture
    }
    when ODIN_DEBUG {
        if texture == nil do panic_contextless("texture: uninitialized")
        mem.ICheckInit_Check(&texture.check_init)
    }

    engine.image_binding_sets_and_draw(cmd, self.set, viewport.set, texture.set)
}


/*
Initializes an image button

Inputs:
- self: Pointer to the image button to initialize
- actualType: The actual type of the button (must be a subtype of image_button)
- pos: Position of the button
- camera: Pointer to the camera
- projection: Pointer to the projection
- rotation: Rotation angle in radians (default: 0.0)
- scale: Scale factors (default: {1, 1})
- colorTransform: Pointer to color transform (default: nil)
- pivot: Pivot point for transformations (default: {0.0, 0.0})
- up: Texture for the up state (default: nil)
- over: Texture for the over state (default: nil)
- down: Texture for the down state (default: nil)
- vtable: Custom vtable (default: nil)

Returns:
- None
*/
image_button_init :: proc(self:^image_button, $actualType:typeid, pos:linalg.point3d,
rotation:f32 = 0.0, scale:linalg.point = {1,1}, colorTransform:^engine.color_transform = nil, pivot:linalg.point = {0.0, 0.0},
up:^engine.texture = nil, over:^engine.texture = nil, down:^engine.texture = nil, vtable:^button_vtable = nil) where intrinsics.type_is_subtype_of(actualType, image_button) {
    self.up_texture = up
    self.over_texture = over
    self.down_texture = down

	self.set.bindings = engine.descriptor_set_binding__base_uniform_pool[:]
    self.set.size = engine.descriptor_pool_size__base_uniform_pool[:]
    self.set.layout = engine.get_base_descriptor_set_layout()

	self.vtable = vtable == nil ? &image_button_vtable : vtable
    if self.vtable.draw == nil do self.vtable.draw = auto_cast _super_image_button_draw
    if self.vtable.deinit == nil do self.vtable.deinit = auto_cast _super_image_button_deinit

	if self.vtable.get_uniform_resources == nil do self.vtable.get_uniform_resources = auto_cast engine.get_uniform_resources_default

	engine.iobject_init(auto_cast self, actualType, pos, rotation, scale, colorTransform, pivot)
}

image_button_init2 :: proc(self:^image_button, $actualType:typeid, colorTransform:^engine.color_transform = nil,
up:^engine.texture = nil, over:^engine.texture = nil, down:^engine.texture = nil, vtable:^button_vtable = nil) where intrinsics.type_is_subtype_of(actualType, image_button) {
    self.up_texture = up
    self.over_texture = over
    self.down_texture = down

	self.set.bindings = engine.descriptor_set_binding__base_uniform_pool[:]
    self.set.size = engine.descriptor_pool_size__base_uniform_pool[:]
    self.set.layout = engine.get_base_descriptor_set_layout()

	self.vtable = vtable == nil ? &image_button_vtable : vtable
    if self.vtable.draw == nil do self.vtable.draw = auto_cast _super_image_button_draw
    if self.vtable.deinit == nil do self.vtable.deinit = auto_cast _super_image_button_deinit

	if self.vtable.get_uniform_resources == nil do self.vtable.get_uniform_resources = auto_cast engine.get_uniform_resources_default

	engine.iobject_init2(auto_cast self, actualType, colorTransform)
}


_super_shape_button_deinit :: proc(self:^shape_button) {
    engine._super_iobject_deinit(auto_cast self)
}

_super_shape_button_draw :: proc (self:^shape_button, cmd:engine.command_buffer, viewport:^engine.viewport) {
    mem.ICheckInit_Check(&self.check_init)
    shape_src :^shape.shape_src

    switch self.state {
        case .UP:shape_src = self.up_shape_src
        case .OVER:shape_src = self.over_shape_src
        case .DOWN:shape_src = self.down_shape_src
    }
    when ODIN_DEBUG {
        if shape_src == nil do panic_contextless("shape: uninitialized")
        mem.ICheckInit_Check(&shape_src.vertexBuf.check_init)
    }

	shape.shape_src_bind_and_draw(shape_src, &self.set, cmd, viewport)
}

/*
Initializes a shape button

Inputs:
- self: Pointer to the shape button to initialize
- actualType: The actual type of the button (must be a subtype of shape_button)
- pos: Position of the button
- camera: Pointer to the camera
- projection: Pointer to the projection
- rotation: Rotation angle in radians (default: 0.0)
- scale: Scale factors (default: {1, 1})
- colorTransform: Pointer to color transform (default: nil)
- pivot: Pivot point for transformations (default: {0.0, 0.0})
- up: Shape for the up state (default: nil)
- over: Shape for the over state (default: nil)
- down: Shape for the down state (default: nil)
- vtable: Custom vtable (default: nil)

Returns:
- None
*/
shape_button_init :: proc(self:^shape_button, $actualType:typeid, pos:linalg.point3d,
rotation:f32 = 0.0, scale:linalg.point = {1,1}, colorTransform:^engine.color_transform = nil, pivot:linalg.point = {0.0, 0.0},
up:^shape.shape_src = nil, over:^shape.shape_src = nil, down:^shape.shape_src = nil, vtable:^button_vtable = nil) where intrinsics.type_is_subtype_of(actualType, shape_button) {
    self.up_shape_src = up
    self.over_shape_src = over
    self.down_shape_src = down

	self.set.bindings = engine.descriptor_set_binding__base_uniform_pool[:]
    self.set.size = engine.descriptor_pool_size__base_uniform_pool[:]
    self.set.layout = engine.get_base_descriptor_set_layout()

	self.vtable = vtable == nil ? &shape_button_vtable : vtable
    if self.vtable.draw == nil do self.vtable.draw = auto_cast _super_shape_button_draw
    if self.vtable.deinit == nil do self.vtable.deinit = auto_cast _super_shape_button_deinit

	if self.vtable.get_uniform_resources == nil do self.vtable.get_uniform_resources = auto_cast engine.get_uniform_resources_default

	engine.iobject_init(auto_cast self, actualType, pos, rotation, scale, colorTransform, pivot)
}

shape_button_init2 :: proc(self:^shape_button, $actualType:typeid, colorTransform:^engine.color_transform = nil,
up:^shape.shape_src = nil, over:^shape.shape_src = nil, down:^shape.shape_src = nil, vtable:^button_vtable = nil) where intrinsics.type_is_subtype_of(actualType, shape_button) {
    self.up_shape_src = up
    self.over_shape_src = over
    self.down_shape_src = down

	self.set.bindings = engine.descriptor_set_binding__base_uniform_pool[:]
    self.set.size = engine.descriptor_pool_size__base_uniform_pool[:]
    self.set.layout = engine.get_base_descriptor_set_layout()

	self.vtable = vtable == nil ? &shape_button_vtable : vtable
    if self.vtable.draw == nil do self.vtable.draw = auto_cast _super_shape_button_draw
    if self.vtable.deinit == nil do self.vtable.deinit = auto_cast _super_shape_button_deinit

	if self.vtable.get_uniform_resources == nil do self.vtable.get_uniform_resources = auto_cast engine.get_uniform_resources_default

	engine.iobject_init2(auto_cast self, actualType, colorTransform)
}