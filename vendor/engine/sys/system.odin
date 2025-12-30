package sys

import "base:library"
import "../"

import "core:sync"
import "core:time"
import "core:mem/virtual"
import "core:mem"

when library.is_android {
	android_platform:engine.android_platform_version
} else when ODIN_OS == .Linux {
	linux_platform:engine.linux_platform_version
} else when ODIN_OS == .Windows {
	windows_platform:engine.windows_platform_version
}

@private main_thread_id: int
// Allocators
temp_arena_allocator: mem.Allocator
engine_def_allocator: mem.Allocator

is_main_thread :: #force_inline proc "contextless" () -> bool {
	return sync.current_thread_id() == main_thread_id
}

// ============================================================================
// System Initialization & Cleanup
// ============================================================================

system_start :: #force_inline proc() {
	engine_def_allocator = context.allocator
	engine.start_tracking_allocator()

    monitors = mem.make_non_zeroed([dynamic]monitor_info)
	when library.is_android {
	} else {
		glfw_system_init()
		glfw_system_start()
	}
}

system_after_destroy :: #force_inline proc() {
	delete(monitors)
}

// ============================================================================
// Render Loop
// ============================================================================

@private calc_frame_time :: proc(paused_: bool) {
	@static start: time.Time
	@static now: time.Time

	if !loop_start {
		loop_start = true
		start = time.now()
		now = start
	} else {
		max_frame_ := engine.get_max_frame()
		if paused_ && max_frame_ == 0 {
			max_frame_ = 60
		}
		n := time.now()
		delta := n._nsec - now._nsec

		if max_frame_ > 0 {
			max_f := u64(1 * (1 / max_frame_)) * 1000000000
			if max_f > auto_cast delta {
				time.sleep(auto_cast (i64(max_f) - delta))
				n = time.now()
				delta = n._nsec - now._nsec
			}
		}
		now = n
		delta_time = auto_cast delta
	}
}

render_loop :: proc() {
	paused_ := engine.paused()

	calc_frame_time(paused_)

	engine.update()
	if engine.__g_main_render_cmd_idx >= 0 {
		for obj in engine.__g_render_cmd[engine.__g_main_render_cmd_idx].scene {
			engine.iobject_update(auto_cast obj)
		}
	}

	if !paused_ {
		graphics_draw_frame()
	}
}