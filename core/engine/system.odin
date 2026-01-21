package engine

import "base:library"
import "core:sys/windows"
import "base:runtime"
import "core:mem"
import "core:mem/virtual"
import "core:sync"
import "core:time"
import "core:debug/trace"
import "core:fmt"
import "core:math/linalg"
import "core:os"
import "base:intrinsics"

/*
Gets the delta time in seconds

Returns:
- Delta time in seconds
*/
dt :: #force_inline proc "contextless" () -> f64 { return f64(delta_time) / 1000000000.0 }

/*
Gets the delta time in nanoseconds as u64

Returns:
- Delta time in nanoseconds
*/
dt_u64 :: #force_inline proc "contextless" () -> u64 { return delta_time }

/*
Gets the number of processor cores

Returns:
- The number of processor cores
*/
get_processor_core_len :: #force_inline proc "contextless" () -> int { return processor_core_len }


is_android :: ODIN_PLATFORM_SUBTARGET == .Android
is_mobile :: is_android
is_log :: #config(LOG, false)
is_console :: #config(CONSOLE, false)

init: #type proc()
update: #type proc()
destroy: #type proc()
size: #type proc() = proc () {}
activate: #type proc "contextless" () = proc "contextless" () {}
closing: #type proc "contextless" () -> bool = proc "contextless" () -> bool{ return true }

@(private="file") inited := false

when library.is_android {
	android_platform:android_platform_version
} else when ODIN_OS == .Linux {
	linux_platform:linux_platform_version
} else when ODIN_OS == .Windows {
	windows_platform:windows_platform_version
}

@private main_thread_id: int
@(private = "file") __tempArena: virtual.Arena
__temp_arena_allocator: mem.Allocator

@private @thread_local track_allocator:mem.Tracking_Allocator

@private __exiting := false

temp_arena_allocator :: #force_inline proc "contextless" () -> mem.Allocator {
	return __temp_arena_allocator
}


when library.is_android {
	get_platform_version :: #force_inline proc "contextless" () -> android_platform_version {
		return android_platform
	}
} else when ODIN_OS == .Linux {
	get_platform_version :: #force_inline proc "contextless" () -> linux_platform_version {
		return linux_platform
	}
} else when ODIN_OS == .Windows {
	get_platform_version :: #force_inline proc "contextless" () -> windows_platform_version {
		return windows_platform
	}
}


@private windows_h_instance:windows.HINSTANCE
@private program_start := true
@private loop_start := false
@private max_frame: f64
@private delta_time: u64
@private processor_core_len: int


/*
Main entry point for the engine

Initializes the engine, creates a window, and runs the main loop

Inputs:
- window_title: Title of the window (default: "xfit")
- window_x: X position of the window (default: nil)
- window_y: Y position of the window (default: nil)
- window_width: Width of the window (default: nil)
- window_height: Height of the window (default: nil)
- v_sync: Vertical sync mode (default: .Double)

Returns:
- None
*/
engine_main :: proc(
	window_title:cstring = "xfit",
	window_x:Maybe(int) = nil,
	window_y:Maybe(int) = nil,
	window_width:Maybe(int) = nil,
	window_height:Maybe(int) = nil,
	v_sync:v_sync = .Double,
) {
	when ODIN_OS == .Windows {
		windows_h_instance = auto_cast windows.GetModuleHandleA(nil)
	}

	system_start()

	assert(!(window_width != nil && window_width.? <= 0))
	assert(!(window_height != nil && window_height.? <= 0))

	inited = true

	__window_title = window_title
	when is_android {
		when is_console {
			trace.panic_log("Console mode is not supported on Android.")
		}
		__window_x = 0
		__window_y = 0
	} else {
		when !is_console {
			__window_x = window_x
			__window_y = window_y
			__window_width = window_width
			__window_height = window_height
		}
	}
	__v_sync = v_sync

	when is_android {
		android_start()
	} else {
		when is_console {
			init()
			destroy()
			system_destroy()
			system_after_destroy()
		} else {
			window_start()

			graphics_init()

			init()

			for !__exiting {
				system_loop()
			}

			graphics_wait_device_idle()

			destroy()

			graphics_destroy()

			system_destroy()

			system_after_destroy()
		}
	}
}


@private system_start :: #force_inline proc() {
	main_thread_id = sync.current_thread_id()

    monitors = mem.make_non_zeroed([dynamic]monitor_info)
	when library.is_android {
	} else {
		glfw_system_init()
		glfw_system_start()
	}
}

@private system_after_destroy :: #force_inline proc() {
	delete(monitors)
	virtual.arena_free_all(&__tempArena)
}


@private system_loop :: proc() {
	when is_android {
	} else {
		glfw_loop()
	}
}

@private window_start :: proc() {
	when is_android {
	} else {
		glfw_start()
	}
}

@private system_destroy :: proc() {
	when is_android {
	} else {
		glfw_destroy()
		glfw_system_destroy()
	}
}


/*
Gets the maximum frame rate limit

Returns:
- Maximum frame rate in frames per second, or 0 if unlimited
*/
get_max_frame :: #force_inline proc "contextless" () -> f64 {
	return intrinsics.atomic_load_explicit(&max_frame,.Relaxed)
}


/*
Gets the current frames per second

Returns:
- Current FPS, or 0 if delta time is 0
*/
get_fps :: #force_inline proc "contextless" () -> f64 {
	if delta_time == 0 do return 0
	return 1.0 / dt()
}

/*
Sets the maximum frame rate limit

Inputs:
- _maxframe: Maximum frame rate in frames per second (0 for unlimited)

Returns:
- None
*/
set_max_frame :: #force_inline proc "contextless" (_maxframe: f64) {
	intrinsics.atomic_store_explicit(&max_frame, _maxframe, .Relaxed)
}

//_int * 1000000000 + _dec
second_to_nano_second :: #force_inline proc "contextless" (_int: $T, _dec: T) -> T where intrinsics.type_is_integer(T) {
    return _int * 1000000000 + _dec
}

second_to_nano_second2 :: #force_inline proc "contextless" (_sec: $T, _milisec: T, _usec: T, _nsec: T) -> T where intrinsics.type_is_integer(T) {
    return _sec * 1000000000 + _milisec * 1000000 + _usec * 1000 + _nsec
}

windows_set_res_icon :: proc "contextless" (icon_resource_number:int) {
	when ODIN_OS == .Windows {
		h_wnd := glfw_get_hwnd()
		icon := windows.LPARAM(uintptr(windows.LoadIconW(windows_h_instance, auto_cast windows.MAKEINTRESOURCEW(icon_resource_number))))
		windows.SendMessageW(h_wnd, windows.WM_SETICON, 1, icon)
		windows.SendMessageW(h_wnd, windows.WM_SETICON, 0, icon)
	}
}

/*
Closes the engine program

Returns:
- None
*/
close :: proc "contextless" () {
	when is_mobile {
		android_close()
	} else {
		glfw_destroy()
	}
}

@private calc_frame_time :: proc(paused_: bool) {
	@static start: time.Time
	@static now: time.Time

	if !loop_start {
		loop_start = true
		start = time.now()
		now = start
	} else {
		max_frame_ := get_max_frame()
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

@private render_loop :: proc() {
	paused_ := paused()

	calc_frame_time(paused_)

	update()
	if __g_main_render_cmd_idx >= 0 {
		for obj in __g_render_cmd[__g_main_render_cmd_idx].scene {
			iobject_update(auto_cast obj)
		}
	}

	if !paused_ {
		graphics_draw_frame()
	}
}

/*
Converts mouse position from window coordinates to centered coordinates

Inputs:
- pos: Mouse position in window coordinates

Returns:
- Mouse position in centered coordinates (origin at window center)
*/
convert_mouse_pos :: proc "contextless" (pos:linalg.point) -> linalg.point {
    w := f32(window_width()) / 2.0
    h := f32(window_height()) / 2.0
    return linalg.point{ pos.x - w, -pos.y + h }
}

android_api_level :: enum u32 {
	Nougat = 24,
	Nougat_MR1 = 25,
	Oreo = 26,
	Oreo_MR1 = 27,
	Pie = 28,
	Q = 29,
	R = 30,
	S = 31,
	S_V2 = 32,
	Tiramisu = 33,
	UpsideDownCake = 34,
	VanillaIceCream = 35,
	Baklava = 36,
	Unknown = 0,
}

windows_version :: enum {
	Windows7,
	WindowsServer2008R2,
	Windows8,
	WindowsServer2012,
	Windows8Point1,
	WindowsServer2012R2,
	Windows10,
	WindowsServer2016,
	Windows11,
	WindowsServer2019,
	WindowsServer2022,
	Unknown,
}

windows_platform_version :: struct {
	version:windows_version,
	build_number:u32,
	service_pack:u32,
}
android_platform_version :: struct {
	api_level:android_api_level,
}
linux_platform_version :: struct {
	sys_name:string,
	node_name:string,
	release:string,
	version:string,
	machine:string,
}


/*
Checks if the engine is exiting

Returns:
- `true` if the engine is exiting, `false` otherwise
*/
exiting :: #force_inline proc  "contextless"() -> bool {return __exiting}



// @(private) CreateRenderFuncThread :: proc() {
// 	render_th = thread.create_and_start(RenderFunc)
// }

// @(private) RenderFunc :: proc() {
// 	vkStart()

// 	Init()

// 	for !__exiting {
// 		RenderLoop()
// 	}

// 	vkWaitDeviceIdle()

// 	Destroy()

// 	vkDestory()
// }


start_console :: proc() {
	when ODIN_OS == .Windows {
		windows.AllocConsole()
		// 새로운 콘솔을 할당 했으므로 stdin, stdout, stderr를 다시 설정
		os.stdin = os.get_std_handle(uint(windows.STD_INPUT_HANDLE))
		os.stdout = os.get_std_handle(uint(windows.STD_OUTPUT_HANDLE))
		os.stderr = os.get_std_handle(uint(windows.STD_ERROR_HANDLE))
	}
}

/*
Checks if the current thread is the main thread

Returns:
- `true` if the current thread is the main thread, `false` otherwise
*/
is_main_thread :: #force_inline proc "contextless" () -> bool {
	return sync.current_thread_id() == main_thread_id
}

