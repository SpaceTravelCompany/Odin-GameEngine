package engine

import "core:sync"
import "core:debug/trace"
import "core:math/linalg"
import "core:sys/windows"


paused :: proc "contextless" () -> bool {
	return __paused
}

activated :: proc "contextless" () -> bool {
	return __activated
}


set_full_screen_mode :: proc "contextless" (monitor:^monitor_info) {
	when !is_mobile {
		sync.mutex_lock(&full_screen_mtx)
		defer sync.mutex_unlock(&full_screen_mtx)
		save_prev_window()
		glfw_set_full_screen_mode(monitor)
		__screen_mode = .Fullscreen
	}
}
set_borderless_screen_mode :: proc "contextless" (monitor:^monitor_info) {
	when !is_mobile {
		sync.mutex_lock(&full_screen_mtx)
		defer sync.mutex_unlock(&full_screen_mtx)
		save_prev_window()
		glfw_set_borderless_screen_mode(monitor)
		__screen_mode = .Borderless
	}
}
set_window_mode :: proc "contextless" () {
	when !is_mobile {
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

window_width :: proc "contextless" () -> int {
	return __window_width.?
}
window_height :: proc "contextless" () -> int {
	return __window_height.?
}
window_x :: proc "contextless" () -> int {
	return __window_x.?
}
window_y :: proc "contextless" () -> int {
	return __window_y.?
}
set_v_sync :: proc "contextless" (v_sync:v_sync) {
	__v_sync = v_sync
	size_updated = true
}
get_v_sync :: proc "contextless" () -> v_sync {
	return __v_sync
}

set_window_icon :: #force_inline proc "contextless" (icons:[]icon_image) {
	when !is_mobile {
	    glfw_set_window_icon(auto_cast icons)
	}
}


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
	rect:       linalg.RectI,
	refresh_rate: u32,
	name:       string,
	is_primary:  bool,
}

__window_width: Maybe(int)
__window_height: Maybe(int)
__window_x: Maybe(int)
__window_y: Maybe(int)

prev_window_x: int
prev_window_y: int
prev_window_width: int
prev_window_height: int

__screen_idx: int = 0
__screen_mode: screen_mode
__window_title: cstring
__screen_orientation:screen_orientation = .Unknown

monitors_mtx:sync.Mutex
monitors: [dynamic]monitor_info
primary_monitor: ^monitor_info
current_monitor: ^monitor_info = nil

__is_full_screen_ex := false
__v_sync:v_sync
monitor_locked:bool = false

__paused := false
__activated := false
size_updated := false

full_screen_mtx : sync.Mutex

save_prev_window :: proc "contextless" () {
	prev_window_x = __window_x.?
    prev_window_y = __window_y.?
    prev_window_width = __window_width.?
    prev_window_height = __window_height.?
}
