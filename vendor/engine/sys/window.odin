package sys

import "core:sync"
import "core:math/linalg"

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

paused := false
activated := false
size_updated := false

full_screen_mtx : sync.Mutex

save_prev_window :: proc "contextless" () {
	prev_window_x = __window_x.?
    prev_window_y = __window_y.?
    prev_window_width = __window_width.?
    prev_window_height = __window_height.?
}
