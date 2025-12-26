package components

import "../"
import vk "vendor:vulkan"
import graphics_api "../graphics_api"
import "core:math/linalg"
import "core:mem"


ButtonState :: enum {
    UP,OVER,DOWN,
}

ImageButton :: struct {
    using _:__Button,
    up_texture:^engine.Texture,
    over_texture:^engine.Texture,
    down_texture:^engine.Texture,
}

_Super_Button_Up :: proc (self:^__Button, mousePos:linalg.PointF) {
    if self.state == .DOWN {
        if linalg.Area_PointIn(self.area, mousePos) {
            self.state = .OVER
        } else {
            self.state = .UP
        }
        //UPDATE
        self.ButtonUpCallBack(self, mousePos)
    }
}
_Super_Button_Down :: proc (self:^__Button, mousePos:linalg.PointF) {
    if self.state == .UP {
        if linalg.Area_PointIn(self.area, mousePos) {
            self.state = .DOWN
            //UPDATE
            self.ButtonDownCallBack(self, mousePos)
        }    
    } else if self.state == .OVER {
        self.state = .DOWN
        //UPDATE
        self.ButtonDownCallBack(self, mousePos)
    }
}
_Super_Button_Move :: proc (self:^__Button, mousePos:linalg.PointF) {
    if linalg.Area_PointIn(self.area, mousePos) {
        if self.state == .UP {
            self.state = .OVER
            //UPDATE
        }
        self.ButtonMoveCallBack(self, mousePos)
    } else {
        if self.state != .UP {
            self.state = .UP
            //UPDATE
        }
    }
}
_Super_Button_TouchUp :: proc (self:^__Button, touchPos:linalg.PointF, touchIdx:u8) {
    if self.state == .DOWN && self.touchIdx != nil && self.touchIdx.? == touchIdx {
        self.state = .UP
        self.touchIdx = nil
        //UPDATE
        self.TouchUpCallBack(self, touchPos, touchIdx)
    }
}
_Super_Button_TouchDown :: proc (self:^__Button, touchPos:linalg.PointF, touchIdx:u8) {
    if self.state == .UP {
        if linalg.Area_PointIn(self.area, touchPos) {
            self.state = .DOWN
            self.touchIdx = touchIdx
            //UPDATE
            self.TouchDownCallBack(self, touchPos, touchIdx)
        }    
    } else if self.touchIdx != nil && self.touchIdx.? == touchIdx {
        self.state = .UP
        self.touchIdx = nil
        //UPDATE
    }
}
_Super_Button_TouchMove :: proc (self:^__Button, touchPos:linalg.PointF, touchIdx:u8) {
    if linalg.Area_PointIn(self.area, touchPos) {
        if self.touchIdx == nil && self.state == .UP {
            self.touchIdx = touchIdx
            self.state = .OVER
            //UPDATE
            self.TouchMoveCallBack(self, touchPos, touchIdx)
        }    
    } else if self.touchIdx != nil && self.touchIdx.? == touchIdx {
        self.touchIdx = nil
        if self.state != .UP {
            self.state = .UP
            //UPDATE
        }
    }
}

__Button :: struct {
    using _:engine.IObject,
    area:linalg.AreaF,
    state : ButtonState,
    touchIdx:Maybe(u8),
    ButtonUpCallBack: proc (self:^__Button, mousePos:linalg.PointF),
    ButtonDownCallBack: proc (self:^__Button, mousePos:linalg.PointF),
    ButtonMoveCallBack: proc (self:^__Button, mousePos:linalg.PointF),
    TouchDownCallBack: proc (self:^__Button, touchPos:linalg.PointF, touchIdx:u8),
    TouchUpCallBack: proc (self:^__Button, touchPos:linalg.PointF, touchIdx:u8),
    TouchMoveCallBack: proc (self:^__Button, touchPos:linalg.PointF, touchIdx:u8),
}

ShapeButton :: struct {
    using _:__Button,
}

ButtonVTable :: struct {
    using _: engine.IObjectVTable,
    ButtonUp: proc (self:^__Button, mousePos:linalg.PointF),
    ButtonDown: proc (self:^__Button, mousePos:linalg.PointF),
    ButtonMove: proc (self:^__Button, mousePos:linalg.PointF),
    TouchDown: proc (self:^__Button, touchPos:linalg.PointF, touchIdx:u8),
    TouchUp: proc (self:^__Button, touchPos:linalg.PointF, touchIdx:u8),
    TouchMove: proc (self:^__Button, touchPos:linalg.PointF, touchIdx:u8),
}

@private ImageButtonVTable :ButtonVTable = ButtonVTable {
    Draw = auto_cast _Super_ImageButton_Draw,
    Deinit = auto_cast _Super_ImageButton_Deinit,
}

_Super_ImageButton_Deinit :: proc(self:^ImageButton) {
    engine._Super_IObject_Deinit(auto_cast self)
}

_Super_ImageButton_Draw :: proc (self:^ImageButton, cmd:graphics_api.CommandBuffer) {
    mem.ICheckInit_Check(&self.checkInit)
    texture :^engine.Texture

    switch self.state {
        case .UP:texture = self.up_texture
        case .OVER:texture = self.over_texture
        case .DOWN:texture = self.down_texture
    }
    when ODIN_DEBUG {
        if texture == nil do panic_contextless("texture: uninitialized")
        mem.ICheckInit_Check(&texture.checkInit)
    }

    engine._Image_BindingSetsAndDraw(cmd, self.set, texture.set)
}

ImageButton_Init :: proc(self:^ImageButton, $actualType:typeid, pos:linalg.Point3DF,
camera:^engine.Camera, projection:^engine.Projection,
rotation:f32 = 0.0, scale:linalg.PointF = {1,1}, colorTransform:^engine.ColorTransform = nil, pivot:linalg.PointF = {0.0, 0.0},
up:^engine.Texture = nil, over:^engine.Texture = nil, down:^engine.Texture = nil, vtable:^ButtonVTable = nil) where intrinsics.type_is_subtype_of(actualType, ImageButton) {
    self.up_texture = up
    self.over_texture = over
    self.down_texture = down
}

