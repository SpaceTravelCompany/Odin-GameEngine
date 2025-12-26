package engine

import "base:intrinsics"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:mem"
import "core:mem/virtual"
import "core:io"
import "core:reflect"
import "core:thread"
import "core:sync"
import "core:strings"
import "base:runtime"
import "core:debug/trace"
import "vendor:glfw"
import "core:sys/android"

import "./graphics_api"


when is_mobile {
    KeyCode :: enum i32 {
        KEY_SPACE = auto_cast android.Keycode.SPACE,
        KEY_APOSTROPHE = auto_cast android.Keycode.APOSTROPHE,    /* ' */
        KEY_COMMA = auto_cast android.Keycode.COMMA,         /* , */
        KEY_MINUS = auto_cast android.Keycode.MINUS,         /* - */
        KEY_PERIOD = auto_cast android.Keycode.PERIOD,        /* . */
        KEY_SLASH = auto_cast android.Keycode.SLASH,         /* / */
        KEY_SEMICOLON = auto_cast android.Keycode.SEMICOLON,     /* ; */
        KEY_EQUAL = auto_cast android.Keycode.EQUALS,         /* = */
        KEY_LEFT_BRACKET = auto_cast android.Keycode.LEFT_BRACKET,  /* [ */
        KEY_BACKSLASH = auto_cast android.Keycode.BACKSLASH,     /* \ */
        KEY_RIGHT_BRACKET = auto_cast android.Keycode.RIGHT_BRACKET, /* ] */
        KEY_GRAVE_ACCENT = auto_cast android.Keycode.GRAVE,  /* ` */

        /* Alphanumeric characters */
        KEY_0 = auto_cast android.Keycode.KEY_0,
        KEY_1 = auto_cast android.Keycode.KEY_1,
        KEY_2 = auto_cast android.Keycode.KEY_2,
        KEY_3 = auto_cast android.Keycode.KEY_3,
        KEY_4 = auto_cast android.Keycode.KEY_4,
        KEY_5 = auto_cast android.Keycode.KEY_5,
        KEY_6 = auto_cast android.Keycode.KEY_6,
        KEY_7 = auto_cast android.Keycode.KEY_7,
        KEY_8 = auto_cast android.Keycode.KEY_8,
        KEY_9 = auto_cast android.Keycode.KEY_9,

        KEY_A = auto_cast android.Keycode.A,
        KEY_B = auto_cast android.Keycode.B,
        KEY_C = auto_cast android.Keycode.C,
        KEY_D = auto_cast android.Keycode.D,
        KEY_E = auto_cast android.Keycode.E,
        KEY_F = auto_cast android.Keycode.F,
        KEY_G = auto_cast android.Keycode.G,
        KEY_H = auto_cast android.Keycode.H,
        KEY_I = auto_cast android.Keycode.I,
        KEY_J = auto_cast android.Keycode.J,
        KEY_K = auto_cast android.Keycode.K,
        KEY_L = auto_cast android.Keycode.L,
        KEY_M = auto_cast android.Keycode.M,
        KEY_N = auto_cast android.Keycode.N,
        KEY_O = auto_cast android.Keycode.O,
        KEY_P = auto_cast android.Keycode.P,
        KEY_Q = auto_cast android.Keycode.Q,
        KEY_R = auto_cast android.Keycode.R,
        KEY_S = auto_cast android.Keycode.S,
        KEY_T = auto_cast android.Keycode.T,
        KEY_U = auto_cast android.Keycode.U,
        KEY_V = auto_cast android.Keycode.V,
        KEY_W = auto_cast android.Keycode.W,
        KEY_X = auto_cast android.Keycode.X,
        KEY_Y = auto_cast android.Keycode.Y,
        KEY_Z = auto_cast android.Keycode.Z,

        /* Function keys */
        KEY_ESCAPE = auto_cast android.Keycode.ESCAPE,
        KEY_ENTER = auto_cast android.Keycode.ENTER,
        KEY_TAB = auto_cast android.Keycode.TAB,
        KEY_INSERT = auto_cast android.Keycode.INSERT,
        KEY_DELETE = auto_cast android.Keycode.DEL,
        KEY_RIGHT = auto_cast android.Keycode.DPAD_RIGHT,
        KEY_LEFT = auto_cast android.Keycode.DPAD_LEFT,
        KEY_DOWN = auto_cast android.Keycode.DPAD_DOWN,
        KEY_UP = auto_cast android.Keycode.DPAD_UP,
        KEY_PAGE_UP = auto_cast android.Keycode.PAGE_UP,
        KEY_PAGE_DOWN = auto_cast android.Keycode.PAGE_DOWN,
        KEY_HOME = auto_cast android.Keycode.HOME,
        KEY_CAPS_LOCK = auto_cast android.Keycode.CAPS_LOCK,
        KEY_SCROLL_LOCK = auto_cast android.Keycode.SCROLL_LOCK,
        KEY_NUM_LOCK = auto_cast android.Keycode.NUM_LOCK,

        /* Function keys */
        KEY_F1 = auto_cast android.Keycode.F1,
        KEY_F2 = auto_cast android.Keycode.F2,
        KEY_F3 = auto_cast android.Keycode.F3,
        KEY_F4 = auto_cast android.Keycode.F4,
        KEY_F5 = auto_cast android.Keycode.F5,
        KEY_F6 = auto_cast android.Keycode.F6,
        KEY_F7 = auto_cast android.Keycode.F7,
        KEY_F8 = auto_cast android.Keycode.F8,
        KEY_F9 = auto_cast android.Keycode.F9,
        KEY_F10 = auto_cast android.Keycode.F10,
        KEY_F11 = auto_cast android.Keycode.F11,
        KEY_F12 = auto_cast android.Keycode.F12,

        /* Keypad numbers */
        KEY_NUM_0 = auto_cast android.Keycode.NUMPAD_0,
        KEY_NUM_1 = auto_cast android.Keycode.NUMPAD_1,
        KEY_NUM_2 = auto_cast android.Keycode.NUMPAD_2,
        KEY_NUM_3 = auto_cast android.Keycode.NUMPAD_3,
        KEY_NUM_4 = auto_cast android.Keycode.NUMPAD_4,
        KEY_NUM_5 = auto_cast android.Keycode.NUMPAD_5,
        KEY_NUM_6 = auto_cast android.Keycode.NUMPAD_6,
        KEY_NUM_7 = auto_cast android.Keycode.NUMPAD_7,
        KEY_NUM_8 = auto_cast android.Keycode.NUMPAD_8,
        KEY_NUM_9 = auto_cast android.Keycode.NUMPAD_9,

        /* Keypad named function keys */
        KEY_NUM_DOT = auto_cast android.Keycode.NUMPAD_DOT,
        KEY_NUM_DIVIDE = auto_cast android.Keycode.NUMPAD_DIVIDE,
        KEY_NUM_MULTIPLY = auto_cast android.Keycode.NUMPAD_MULTIPLY,
        KEY_NUM_SUBTRACT = auto_cast android.Keycode.NUMPAD_SUBTRACT,
        KEY_NUM_ADD = auto_cast android.Keycode.NUMPAD_ADD,
        KEY_NUM_ENTER = auto_cast android.Keycode.NUMPAD_ENTER,
        KEY_NUM_EQUAL = auto_cast android.Keycode.NUMPAD_EQUALS,

        /* Modifier keys */
        KEY_LEFT_SHIFT = auto_cast android.Keycode.SHIFT_LEFT,
        KEY_LEFT_CONTROL = auto_cast android.Keycode.CTRL_LEFT,
        KEY_LEFT_ALT = auto_cast android.Keycode.ALT_LEFT,
        KEY_RIGHT_SHIFT = auto_cast android.Keycode.SHIFT_RIGHT,
        KEY_RIGHT_CONTROL = auto_cast android.Keycode.CTRL_RIGHT,
        KEY_RIGHT_ALT = auto_cast android.Keycode.ALT_RIGHT,
        KEY_MENU = auto_cast android.Keycode.MENU,
    }
} else {
    KeyCode :: enum i32 {
        KEY_SPACE = glfw.KEY_SPACE,
        KEY_APOSTROPHE = glfw.KEY_APOSTROPHE,    /* ' */
        KEY_COMMA = glfw.KEY_COMMA,         /* , */
        KEY_MINUS = glfw.KEY_MINUS,         /* - */
        KEY_PERIOD = glfw.KEY_PERIOD,        /* . */
        KEY_SLASH = glfw.KEY_SLASH,         /* / */
        KEY_SEMICOLON = glfw.KEY_SEMICOLON,     /* ; */
        KEY_EQUAL = glfw.KEY_EQUAL,         /* = */
        KEY_LEFT_BRACKET = glfw.KEY_LEFT_BRACKET,  /* [ */
        KEY_BACKSLASH = glfw.KEY_BACKSLASH,     /* \ */
        KEY_RIGHT_BRACKET = glfw.KEY_RIGHT_BRACKET, /* ] */
        KEY_GRAVE_ACCENT = glfw.KEY_GRAVE_ACCENT,  /* ` */
        KEY_WORLD_1 = glfw.KEY_WORLD_1,       /* non-US #1 */
        KEY_WORLD_2 = glfw.KEY_WORLD_2,       /* non-US #2 */

        /* Alphanumeric characters */
        KEY_0 = glfw.KEY_0,
        KEY_1 = glfw.KEY_1,
        KEY_2 = glfw.KEY_2,
        KEY_3 = glfw.KEY_3,
        KEY_4 = glfw.KEY_4,
        KEY_5 = glfw.KEY_5,
        KEY_6 = glfw.KEY_6,
        KEY_7 = glfw.KEY_7,
        KEY_8 = glfw.KEY_8,
        KEY_9 = glfw.KEY_9,

        KEY_A = glfw.KEY_A,
        KEY_B = glfw.KEY_B,
        KEY_C = glfw.KEY_C,
        KEY_D = glfw.KEY_D,
        KEY_E = glfw.KEY_E,
        KEY_F = glfw.KEY_F,
        KEY_G = glfw.KEY_G,
        KEY_H = glfw.KEY_H,
        KEY_I = glfw.KEY_I,
        KEY_J = glfw.KEY_J,
        KEY_K = glfw.KEY_K,
        KEY_L = glfw.KEY_L,
        KEY_M = glfw.KEY_M,
        KEY_N = glfw.KEY_N,
        KEY_O = glfw.KEY_O,
        KEY_P = glfw.KEY_P,
        KEY_Q = glfw.KEY_Q,
        KEY_R = glfw.KEY_R,
        KEY_S = glfw.KEY_S,
        KEY_T = glfw.KEY_T,
        KEY_U = glfw.KEY_U,
        KEY_V = glfw.KEY_V,
        KEY_W = glfw.KEY_W,
        KEY_X = glfw.KEY_X,
        KEY_Y = glfw.KEY_Y,
        KEY_Z = glfw.KEY_Z,

        /* Function keys */
        KEY_ESCAPE = glfw.KEY_ESCAPE,
        KEY_ENTER = glfw.KEY_ENTER,
        KEY_TAB = glfw.KEY_TAB,
        KEY_BACKSPACE = glfw.KEY_BACKSPACE,
        KEY_INSERT = glfw.KEY_INSERT,
        KEY_DELETE = glfw.KEY_DELETE,
        KEY_RIGHT = glfw.KEY_RIGHT,
        KEY_LEFT = glfw.KEY_LEFT,
        KEY_DOWN = glfw.KEY_DOWN,
        KEY_UP = glfw.KEY_UP,
        KEY_PAGE_UP = glfw.KEY_PAGE_UP,
        KEY_PAGE_DOWN = glfw.KEY_PAGE_DOWN,
        KEY_HOME = glfw.KEY_HOME,
        KEY_END = glfw.KEY_END,
        KEY_CAPS_LOCK = glfw.KEY_CAPS_LOCK,
        KEY_SCROLL_LOCK = glfw.KEY_SCROLL_LOCK,
        KEY_NUM_LOCK = glfw.KEY_NUM_LOCK,
        KEY_PRINT_SCREEN = glfw.KEY_PRINT_SCREEN,
        KEY_PAUSE = glfw.KEY_PAUSE,

        /* Function keys */
        KEY_F1 = glfw.KEY_F1,
        KEY_F2 = glfw.KEY_F2,
        KEY_F3 = glfw.KEY_F3,
        KEY_F4 = glfw.KEY_F4,
        KEY_F5 = glfw.KEY_F5,
        KEY_F6 = glfw.KEY_F6,
        KEY_F7 = glfw.KEY_F7,
        KEY_F8 = glfw.KEY_F8,
        KEY_F9 = glfw.KEY_F9,
        KEY_F10 = glfw.KEY_F10,
        KEY_F11 = glfw.KEY_F11,
        KEY_F12 = glfw.KEY_F12,
        KEY_F13 = glfw.KEY_F13,
        KEY_F14 = glfw.KEY_F14,
        KEY_F15 = glfw.KEY_F15,
        KEY_F16 = glfw.KEY_F16,
        KEY_F17 = glfw.KEY_F17,
        KEY_F18 = glfw.KEY_F18,
        KEY_F19 = glfw.KEY_F19,
        KEY_F20 = glfw.KEY_F20,
        KEY_F21 = glfw.KEY_F21,
        KEY_F22 = glfw.KEY_F22,
        KEY_F23 = glfw.KEY_F23,
        KEY_F24 = glfw.KEY_F24,
        KEY_F25 = glfw.KEY_F25,

        /* Keypad numbers */
        KEY_NUM_0 = glfw.KEY_KP_0,
        KEY_NUM_1 = glfw.KEY_KP_1,
        KEY_NUM_2 = glfw.KEY_KP_2,
        KEY_NUM_3 = glfw.KEY_KP_3,
        KEY_NUM_4 = glfw.KEY_KP_4,
        KEY_NUM_5 = glfw.KEY_KP_5,
        KEY_NUM_6 = glfw.KEY_KP_6,
        KEY_NUM_7 = glfw.KEY_KP_7,
        KEY_NUM_8 = glfw.KEY_KP_8,
        KEY_NUM_9 = glfw.KEY_KP_9,

        /* Keypad named function keys */
        KEY_NUM_DOT = glfw.KEY_KP_DECIMAL,
        KEY_NUM_DIVIDE = glfw.KEY_KP_DIVIDE,
        KEY_NUM_MULTIPLY = glfw.KEY_KP_MULTIPLY,
        KEY_NUM_SUBTRACT = glfw.KEY_KP_SUBTRACT,
        KEY_NUM_ADD = glfw.KEY_KP_ADD,
        KEY_NUM_ENTER = glfw.KEY_KP_ENTER,
        KEY_NUM_EQUAL = glfw.KEY_KP_EQUAL,

        /* Modifier keys */
        KEY_LEFT_SHIFT = glfw.KEY_LEFT_SHIFT,
        KEY_LEFT_CONTROL = glfw.KEY_LEFT_CONTROL,
        KEY_LEFT_ALT = glfw.KEY_LEFT_ALT,
        KEY_LEFT_SUPER = glfw.KEY_LEFT_SUPER,
        KEY_RIGHT_SHIFT = glfw.KEY_RIGHT_SHIFT,
        KEY_RIGHT_CONTROL = glfw.KEY_RIGHT_CONTROL,
        KEY_RIGHT_ALT = glfw.KEY_RIGHT_ALT,
        KEY_RIGHT_SUPER = glfw.KEY_RIGHT_SUPER,
        KEY_MENU = glfw.KEY_MENU,
    }
}


LEFT_MOUSE_BUTTON_IDX :: 0
MIDDLE_MOUSE_BUTTON_IDX :: 1
RIGHT_MOUSE_BUTTON_IDX :: 2

KeyDown : #type proc (keycode:KeyCode) = proc (keycode:KeyCode) {}
KeyUp : #type proc (keycode:KeyCode) = proc (keycode:KeyCode) {}
KeyRepeat : #type proc (keycode:KeyCode) = proc (keycode:KeyCode) {}
MouseButtonDown : #type proc (buttonIdx:int, x:f32, y:f32) = proc (buttonIdx:int, x:f32, y:f32) {}
MouseButtonUp : #type proc (buttonIdx:int, x:f32, y:f32) = proc (buttonIdx:int, x:f32, y:f32) {}
PointerDown : #type proc (pointerIdx:int, x:f32, y:f32) = proc (pointerIdx:int, x:f32, y:f32) {}
PointerUp : #type proc (pointerIdx:int, x:f32, y:f32) = proc (pointerIdx:int, x:f32, y:f32) {}
PointerMove : #type proc (pointerIdx:int, x:f32, y:f32) = proc (pointerIdx:int, x:f32, y:f32) {}
MouseScroll : #type proc (dt:int) = proc (dt:int) {}
MouseMove : #type proc (x:f32, y:f32) = proc (x:f32, y:f32) {}
MouseIn : #type proc () = proc () {}
MouseOut : #type proc () = proc () {}

IsMouseOut :: proc "contextless" () -> bool {return graphics_api.isMouseOut}
MousePos :: #force_inline proc "contextless" () -> linalg.PointF {
    return graphics_api.mouse_pos
}

ConvertMousePos :: proc "contextless" (pos:linalg.PointF) -> linalg.PointF {
    w := f32(WindowWidth()) / 2.0
    h := f32(WindowHeight()) / 2.0
    return linalg.PointF{ pos.x - w, -pos.y + h }
}

GENERAL_INPUT_STATE :: struct {
    handle:rawptr,
    leftTrigger:f32,
    rightTrigger:f32,
    leftThumb: linalg.PointF,
    rightThumb: linalg.PointF,
    buttons:GENERAL_INPUT_BUTTONS,
}

GENERAL_INPUT_BUTTONS :: struct #packed {
    a:bool,
    b:bool,
    x:bool,
    y:bool,

    dpadUp:bool,
    dpadDown:bool,
    dpadLeft:bool,
    dpadRight:bool,

    start:bool,
    back:bool,

    leftThumb:bool,
    rightThumb:bool,

    leftShoulder:bool,
    rightShoulder:bool,

    volumeUp:bool,
    volumeDown:bool,
}

GeneralInputCallBack : proc (state:GENERAL_INPUT_STATE) = proc (state:GENERAL_INPUT_STATE) {}