package engine

import "core:debug/trace"
import "core:math/linalg"
import "core:sync"
import "core:sys/windows"
import "vendor:glfw"
import "base:library"

icon_image :: glfw.Image
v_sync :: enum {Double, Triple, None}

screen_mode :: enum {Window, Borderless, Fullscreen}

screen_orientation :: enum {
	Unknown,
	Landscape90,
	Landscape270,
	Vertical180,
	Vertical360,
}

monitor_info :: struct {
	rect:       linalg.recti,
	refresh_rate: u32,
	name:       string,
	is_primary:  bool,
}

@private __window_width: Maybe(int)
@private __window_height: Maybe(int)
@private __window_x: Maybe(int)
@private __window_y: Maybe(int)

@private prev_window_x: int
@private prev_window_y: int
@private prev_window_width: int
@private prev_window_height: int

@private __screen_idx: int = 0
@private __screen_mode: screen_mode
@private __window_title: cstring
@private __screen_orientation:screen_orientation = .Unknown

@private monitors_mtx:sync.Mutex
@private monitors: [dynamic]monitor_info
@private primary_monitor: ^monitor_info
@private current_monitor: ^monitor_info = nil

@private __is_full_screen_ex := false
@private __v_sync:v_sync
@private monitor_locked:bool = false

@private __paused := false
@private __activated := false
@private size_updated := false

@private full_screen_mtx : sync.Mutex

/*
Checks if the engine is paused

Returns:
- `true` if paused, `false` otherwise
*/
paused :: proc "contextless" () -> bool {
	return __paused
}

/*
Checks if the window is activated

Returns:
- `true` if activated, `false` otherwise
*/
activated :: proc "contextless" () -> bool {
	return __activated
}

/*
Sets the window to fullscreen mode on the specified monitor

Inputs:
- monitor: Pointer to the monitor to use for fullscreen

Returns:
- None
*/
set_full_screen_mode :: proc "contextless" (monitor:^monitor_info) {
	when !library.is_mobile {
		sync.mutex_lock(&full_screen_mtx)
		defer sync.mutex_unlock(&full_screen_mtx)
		save_prev_window()
		glfw_set_full_screen_mode(monitor)
		__screen_mode = .Fullscreen
	}
}
/*
Sets the window to borderless fullscreen mode on the specified monitor

Inputs:
- monitor: Pointer to the monitor to use

Returns:
- None
*/
set_borderless_screen_mode :: proc "contextless" (monitor:^monitor_info) {
	when !library.is_mobile {
		sync.mutex_lock(&full_screen_mtx)
		defer sync.mutex_unlock(&full_screen_mtx)
		save_prev_window()
		glfw_set_borderless_screen_mode(monitor)
		__screen_mode = .Borderless
	}
}
/*
Sets the window to windowed mode

Returns:
- None
*/
set_window_mode :: proc "contextless" () {
	when !library.is_mobile {
		sync.mutex_lock(&full_screen_mtx)
		defer sync.mutex_unlock(&full_screen_mtx)
		save_prev_window()
		glfw_set_window_mode()
		__screen_mode = .Window
	}
}

monitor_lock :: proc "contextless" () {
	sync.mutex_lock(&monitors_mtx)
	if monitor_locked do trace.panic_log("already monitor_locked locked")
	monitor_locked = true
}
monitor_unlock :: proc "contextless" () {
	if !monitor_locked do trace.panic_log("already monitor_locked unlocked")
	monitor_locked = false
	sync.mutex_unlock(&monitors_mtx)
}

get_monitors :: proc "contextless" () -> []monitor_info {
	if !monitor_locked do trace.panic_log("call inside monitor_lock")
	return monitors[:len(monitors)]
}

get_current_monitor :: proc "contextless" () -> ^monitor_info {
	if !monitor_locked do trace.panic_log("call inside monitor_lock")
	return current_monitor
}

get_monitor_from_window :: proc "contextless" () -> ^monitor_info #no_bounds_check {
	if !monitor_locked do trace.panic_log("call inside monitor_lock")
	for &value in monitors {
		if linalg.Rect_PointIn(value.rect, [2]i32{auto_cast __window_x.?, auto_cast __window_y.?}) do return &value
	}
	return primary_monitor
}

/*
Gets the window width

Returns:
- Window width in pixels
*/
window_width :: proc "contextless" () -> int {
	return __window_width.?
}

/*
Gets the window height

Returns:
- Window height in pixels
*/
window_height :: proc "contextless" () -> int {
	return __window_height.?
}

/*
Gets the window X position

Returns:
- Window X position in pixels
*/
window_x :: proc "contextless" () -> int {
	return __window_x.?
}

/*
Gets the window Y position

Returns:
- Window Y position in pixels
*/
window_y :: proc "contextless" () -> int {
	return __window_y.?
}
/*
Sets the vertical sync mode

Inputs:
- v_sync: The vertical sync mode to set

Returns:
- None
*/
set_v_sync :: proc "contextless" (v_sync:v_sync) {
	__v_sync = v_sync
	size_updated = true
}

/*
Gets the current vertical sync mode

Returns:
- The current vertical sync mode
*/
get_v_sync :: proc "contextless" () -> v_sync {
	return __v_sync
}

set_window_icon :: #force_inline proc "contextless" (icons:[]icon_image) {
	when !library.is_mobile {
		glfw_set_window_icon(icons)
	}
}

@private save_prev_window :: proc "contextless" () {
	prev_window_x = __window_x.?
    prev_window_y = __window_y.?
    prev_window_width = __window_width.?
    prev_window_height = __window_height.?
}
