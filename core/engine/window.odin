package engine

import "core:math/linalg"
import "core:sync"
import "core:sys/windows"
import "vendor:glfw"
import "base:library"
import "core:log"

icon_image :: glfw.Image
v_sync :: enum {Double, Triple, None}

screen_mode :: enum {Window, Fullscreen}

screen_orientation :: enum {
	Unknown,
	Landscape90,
	Landscape270,
	Vertical180,
	Vertical360,
}

monitor_info :: struct {
	rect:       linalg.recti,
	name:       string,
	refresh_rate: u32,
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

@private __screen_mode: screen_mode
@private __window_title: cstring
@private __screen_orientation:screen_orientation = .Unknown

@private monitors_mtx:sync.Mutex
@private monitors: [dynamic]monitor_info
@private primary_monitor: ^monitor_info

@private __is_full_screen_ex := false
@private __v_sync:v_sync
@private monitor_locked:bool = false

@private __paused := false
@private __activated := false
@private size_updated := false

@private full_screen_mtx : sync.Mutex


paused :: proc "contextless" () -> bool {
	return __paused
}


activated :: proc "contextless" () -> bool {
	return __activated
}


set_full_screen_mode :: proc "contextless" (monitor:^monitor_info) {
	when !library.is_mobile {
		sync.mutex_lock(&full_screen_mtx)
		defer sync.mutex_unlock(&full_screen_mtx)
		save_prev_window()
		glfw_set_full_screen_mode(monitor)
		__screen_mode = .Fullscreen
	}
}

set_window_mode :: proc "contextless" () {
	when !library.is_mobile {
		sync.mutex_lock(&full_screen_mtx)
		defer sync.mutex_unlock(&full_screen_mtx)
		glfw_set_window_mode()
		__screen_mode = .Window
	}
}


get_screen_mode :: proc "contextless" () -> screen_mode {
	when !library.is_mobile {
		sync.mutex_lock(&full_screen_mtx)
		defer sync.mutex_unlock(&full_screen_mtx)
		return __screen_mode
	}
	return .Window
}

monitor_lock :: proc "contextless" () {
	sync.mutex_lock(&monitors_mtx)
}
monitor_try_lock :: proc "contextless" () -> bool {
	return sync.mutex_try_lock(&monitors_mtx)
}
monitor_unlock :: proc "contextless" () {
	sync.mutex_unlock(&monitors_mtx)
}
get_monitors :: proc "contextless" () -> []monitor_info {
	b := monitor_try_lock()
	defer if b {
		monitor_unlock()
	}
	return monitors[:len(monitors)]
}	

get_monitor_from_window :: proc "contextless" () -> ^monitor_info {
	for &value in monitors {
		if linalg.Rect_PointIn(value.rect, [2]i32{auto_cast __window_x.?, auto_cast __window_y.?}) do return &value
	}
	return primary_monitor
}

get_primary_monitor :: proc "contextless" () -> ^monitor_info {
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
