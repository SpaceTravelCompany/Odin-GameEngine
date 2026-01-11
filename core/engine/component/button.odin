package component

import "core:math/linalg"
import "core:mem"
import "core:engine"

import vk "vendor:vulkan"


button_state :: enum {
    UP,OVER,DOWN,
}

image_button :: struct {
    using _:__button,
    up_texture:^engine.texture,
    over_texture:^engine.texture,
    down_texture:^engine.texture,
}

_super_button_up :: proc (self:^__button, mousePos:linalg.PointF) {
    if self.state == .DOWN {
        if linalg.Area_PointIn(self.area, mousePos) {
            self.state = .OVER
        } else {
            self.state = .UP
        }
        //UPDATE
        self.button_up_callback(self, mousePos)
    }
}
_super_button_down :: proc (self:^__button, mousePos:linalg.PointF) {
    if self.state == .UP {
        if linalg.Area_PointIn(self.area, mousePos) {
            self.state = .DOWN
            //UPDATE
            self.button_down_callback(self, mousePos)
        }    
    } else if self.state == .OVER {
        self.state = .DOWN
        //UPDATE
        self.button_down_callback(self, mousePos)
    }
}
_super_button_move :: proc (self:^__button, mousePos:linalg.PointF) {
    if linalg.Area_PointIn(self.area, mousePos) {
        if self.state == .UP {
            self.state = .OVER
            //UPDATE
        }
        self.button_move_callback(self, mousePos)
    } else {
        if self.state != .UP {
            self.state = .UP
            //UPDATE
        }
    }
}
_super_button_touch_up :: proc (self:^__button, touchPos:linalg.PointF, touchIdx:u8) {
    if self.state == .DOWN && self.touchIdx != nil && self.touchIdx.? == touchIdx {
        self.state = .UP
        self.touchIdx = nil
        //UPDATE
        self.touch_up_callback(self, touchPos, touchIdx)
    }
}
_super_button_touch_down :: proc (self:^__button, touchPos:linalg.PointF, touchIdx:u8) {
    if self.state == .UP {
        if linalg.Area_PointIn(self.area, touchPos) {
            self.state = .DOWN
            self.touchIdx = touchIdx
            //UPDATE
            self.touch_down_callback(self, touchPos, touchIdx)
        }    
    } else if self.touchIdx != nil && self.touchIdx.? == touchIdx {
        self.state = .UP
        self.touchIdx = nil
        //UPDATE
    }
}
_super_button_touch_move :: proc (self:^__button, touchPos:linalg.PointF, touchIdx:u8) {
    if linalg.Area_PointIn(self.area, touchPos) {
        if self.touchIdx == nil && self.state == .UP {
            self.touchIdx = touchIdx
            self.state = .OVER
            //UPDATE
            self.touch_move_callback(self, touchPos, touchIdx)
        }    
    } else if self.touchIdx != nil && self.touchIdx.? == touchIdx {
        self.touchIdx = nil
        if self.state != .UP {
            self.state = .UP
            //UPDATE
        }
    }
}

@private __button :: struct {
    using _:engine.iobject,
    area:linalg.AreaF,
    state : button_state,
    touchIdx:Maybe(u8),
    button_up_callback: proc (self:^__button, mousePos:linalg.PointF),
    button_down_callback: proc (self:^__button, mousePos:linalg.PointF),
    button_move_callback: proc (self:^__button, mousePos:linalg.PointF),
    touch_down_callback: proc (self:^__button, touchPos:linalg.PointF, touchIdx:u8),
    touch_up_callback: proc (self:^__button, touchPos:linalg.PointF, touchIdx:u8),
    touch_move_callback: proc (self:^__button, touchPos:linalg.PointF, touchIdx:u8),
}

shape_button :: struct {
    using _:__button,
}

button_vtable :: struct {
    using _: engine.iobject_vtable,
    button_up: proc (self:^__button, mousePos:linalg.PointF),
    button_down: proc (self:^__button, mousePos:linalg.PointF),
    button_move: proc (self:^__button, mousePos:linalg.PointF),
    touch_down: proc (self:^__button, touchPos:linalg.PointF, touchIdx:u8),
    touch_up: proc (self:^__button, touchPos:linalg.PointF, touchIdx:u8),
    touch_move: proc (self:^__button, touchPos:linalg.PointF, touchIdx:u8),
}

@private image_button_vtable :button_vtable = button_vtable {
    draw = auto_cast _super_image_button_draw,
    deinit = auto_cast _super_image_button_deinit,
}

_super_image_button_deinit :: proc(self:^image_button) {
    engine._super_iobject_deinit(auto_cast self)
}

_super_image_button_draw :: proc (self:^image_button, cmd:engine.command_buffer) {
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

    engine.image_binding_sets_and_draw(cmd, self.set, texture.set)
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
image_button_init :: proc(self:^image_button, $actualType:typeid, pos:linalg.Point3DF,
camera:^engine.camera, projection:^engine.projection,
rotation:f32 = 0.0, scale:linalg.PointF = {1,1}, colorTransform:^engine.color_transform = nil, pivot:linalg.PointF = {0.0, 0.0},
up:^engine.texture = nil, over:^engine.texture = nil, down:^engine.texture = nil, vtable:^button_vtable = nil) where intrinsics.type_is_subtype_of(actualType, image_button) {
    self.up_texture = up
    self.over_texture = over
    self.down_texture = down
}

