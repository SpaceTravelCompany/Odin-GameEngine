package engine

import "core:sync"
import "core:debug/trace"
import "core:math/linalg"
import "core:sys/windows"

import sys "./sys"


v_sync :: sys.v_sync
screen_mode :: sys.screen_mode
screen_orientation :: sys.screen_orientation
monitor_info :: sys.monitor_info

paused :: proc "contextless" () -> bool {
	return sys.paused
}

activated :: proc "contextless" () -> bool {
	return sys.activated
}


set_full_screen_mode :: proc "contextless" (monitor:^monitor_info) {
	when !is_mobile {
		sync.mutex_lock(&sys.full_screen_mtx)
		defer sync.mutex_unlock(&sys.full_screen_mtx)
		sys.save_prev_window()
		sys.glfw_set_full_screen_mode(monitor)
		sys.__screen_mode = .Fullscreen
	}
}
set_borderless_screen_mode :: proc "contextless" (monitor:^monitor_info) {
	when !is_mobile {
		sync.mutex_lock(&sys.full_screen_mtx)
		defer sync.mutex_unlock(&sys.full_screen_mtx)
		sys.save_prev_window()
		sys.glfw_set_borderless_screen_mode(monitor)
		sys.__screen_mode = .Borderless
	}
}
set_window_mode :: proc "contextless" () {
	when !is_mobile {
		sync.mutex_lock(&sys.full_screen_mtx)
		defer sync.mutex_unlock(&sys.full_screen_mtx)
		sys.save_prev_window()
		sys.glfw_set_window_mode()
		sys.__screen_mode = .Window
	}
}
monitor_lock :: proc "contextless" () {
	sync.mutex_lock(&sys.monitors_mtx)
	if sys.monitor_locked do trace.panic_log("already monitor_locked locked")
	sys.monitor_locked = true
}
monitor_unlock :: proc "contextless" () {
	if !sys.monitor_locked do trace.panic_log("already monitor_locked unlocked")
	sys.monitor_locked = false
	sync.mutex_unlock(&sys.monitors_mtx)
}

get_monitors :: proc "contextless" () -> []monitor_info {
	if !sys.monitor_locked do trace.panic_log("call inside monitor_lock")
	return sys.monitors[:len(sys.monitors)]
}

get_current_monitor :: proc "contextless" () -> ^monitor_info {
	if !sys.monitor_locked do trace.panic_log("call inside monitor_lock")
	return sys.current_monitor
}

get_monitor_from_window :: proc "contextless" () -> ^monitor_info #no_bounds_check {
	if !sys.monitor_locked do trace.panic_log("call inside monitor_lock")
	for &value in sys.monitors {
		if linalg.Rect_PointIn(value.rect, [2]i32{auto_cast sys.__window_x.?, auto_cast sys.__window_y.?}) do return &value
	}
	return sys.primary_monitor
}

window_width :: proc "contextless" () -> int {
	return sys.__window_width.?
}
window_height :: proc "contextless" () -> int {
	return sys.__window_height.?
}
window_x :: proc "contextless" () -> int {
	return sys.__window_x.?
}
window_y :: proc "contextless" () -> int {
	return sys.__window_y.?
}
set_v_sync :: proc "contextless" (v_sync:v_sync) {
	sys.__v_sync = v_sync
	sys.size_updated = true
}
get_v_sync :: proc "contextless" () -> v_sync {
	return sys.__v_sync
}

set_window_icon :: #force_inline proc "contextless" (icons:[]icon_image) {
	when !is_mobile {
	    sys.glfw_set_window_icon(auto_cast icons)
	}
}