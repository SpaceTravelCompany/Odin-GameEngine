package engine

import "base:library"
import "core:sys/windows"
import "base:runtime"
import "core:mem"
import "core:mem/virtual"
import "core:sync"
import "core:time"
import "core:fmt"
import "core:math/linalg"
import "core:os"
import "base:intrinsics"
import "core:thread"
import "core:log"


ENGINE_ROOT :: #directory

dt :: #force_inline proc "contextless" () -> f64 {
	 return delta_time
}

get_processor_core_len :: #force_inline proc "contextless" () -> int { return processor_core_len }


is_android :: ODIN_PLATFORM_SUBTARGET == .Android
is_mobile :: is_android

is_web :: ODIN_OS == .JS

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

@private __exiting := false
@private now: time.Tick


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
@private max_frame_: f64
@private delta_time: f64
@private processor_core_len: int

@private default_context: runtime.Context
@private g_thread_pool: thread.Pool


/*
Main entry point for the engine

Initializes the engine, creates a window, and runs the main loop

Inputs:
- window_title: Title of the window (default: "SpaceEngine")
- window_x: X position of the window (default: nil)
- window_y: Y position of the window (default: nil)
- window_width: Width of the window (default: nil)
- window_height: Height of the window (default: nil)
- v_sync: Vertical sync mode (default: .Double)
- screen_mode: Screen mode (default: .Window)
- screen_idx: Screen index (default: 0)

Returns:
- None
*/
engine_main :: proc(
	window_title:cstring = "SpaceEngine",
	window_x:Maybe(int) = nil,
	window_y:Maybe(int) = nil,
	window_width:Maybe(int) = nil,
	window_height:Maybe(int) = nil,
	v_sync:v_sync = .Double,
	screen_mode:screen_mode = .Window,
	screen_idx:int = 0,
	max_frame:f64 = 0.0,
) {
	when ODIN_OS == .Windows {
		windows_h_instance = auto_cast windows.GetModuleHandleA(nil)
	}
	system_start()

	assert(!(window_width != nil && window_width.? <= 0))
	assert(!(window_height != nil && window_height.? <= 0))

	inited = true

	max_frame_ = max_frame

	__window_title = window_title
	when is_android {
		__window_x = 0
		__window_y = 0
	} else {
		__window_x = window_x
		__window_y = window_y
		__window_width = window_width
		__window_height = window_height
	}
	__v_sync = v_sync
	__screen_mode = screen_mode

	when is_android {
		thread.pool_init(&g_thread_pool, context.allocator, get_processor_core_len())
		thread.pool_start(&g_thread_pool)
		android_start()
	} else {
		thread.pool_init(&g_thread_pool, context.allocator, get_processor_core_len())
		thread.pool_start(&g_thread_pool)
		window_start(screen_idx)

		graphics_init()

		init()

		//if is web, main loop and destroy are handled by 'step' and '_end'
		when !is_web {
			for !__exiting {
				system_loop()
			}
			__destroy()
		}
	}
}


@private __destroy :: proc() {
	graphics_wait_device_idle()
	destroy()
	graphics_destroy()
	system_destroy()
	system_after_destroy()
}

@private system_start :: proc() {
	main_thread_id = sync.current_thread_id()
	default_context = context

    monitors = mem.make_non_zeroed([dynamic]monitor_info)
	when library.is_android {
	} else {
		glfw_system_init()
		glfw_system_start()
	}
}

@private system_after_destroy :: proc() {
	delete(monitors)
	thread.pool_join(&g_thread_pool)
	thread.pool_destroy(&g_thread_pool)
}


@private system_loop :: proc() {
	when is_android {
	} else {
		glfw_loop()
	}
}

@private window_start :: proc(__screen_idx: int) {
	when is_android {
	} else {
		glfw_start(__screen_idx)
	}
}

@private system_destroy :: proc() {
	when is_android {
	} else {
		glfw_destroy()
		glfw_system_destroy()
	}
}

get_max_frame :: #force_inline proc "contextless" () -> f64 {
	return intrinsics.atomic_load_explicit(&max_frame_,.Relaxed)
}


/*
Gets the current frames per second

Returns:
- Current FPS, or 0 if delta time is 0
*/
get_fps :: proc "contextless" () -> f64 {
	ddt := dt()
	if ddt == 0 do return 0
	return 1.0 / ddt
}

get_now :: #force_inline proc "contextless" () -> f64 {
	return f64(now._nsec) / 1000000000.0
}

set_max_frame :: #force_inline proc "contextless" (_maxframe: f64) {
	intrinsics.atomic_store_explicit(&max_frame_, _maxframe, .Relaxed)
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

@private calc_frame_time :: proc() {
	//delta time calc in web is handled by step(odin.js)
	when !is_web {
		if !loop_start {
			loop_start = true
			now = time.tick_now()
		} else {
			max_frame_ := get_max_frame()
			n := time.tick_now()
			delta := n._nsec - now._nsec

			now = n
			delta_time = f64(delta) / 1000000000.0
		}
	}
}

@private wait_max_frame :: proc(paused_: bool) {
	_max_frame := get_max_frame()
	if _max_frame > 0 {
		max_f := u64((1.0 / _max_frame) * 1000000000.0)
		tick := time.tick_now()
		if tick._nsec < now._nsec {
			tick = now
		}
		diff :u64 = u64(tick._nsec - now._nsec)
		for diff < max_f {
			thread.yield()
			tick = time.tick_now()
			if tick._nsec < now._nsec {
				tick = now
			}
			diff = u64(tick._nsec - now._nsec)
		}
	}
}

@private render_loop :: proc() {
	paused_ := paused()

	calc_frame_time()

	update()
	if len(__g_layer) > 0 {
		//thread pool 사용해서 각각 처리
		update_task_data :: struct {
			cmd: ^layer,
			allocator: runtime.Allocator,
		}
		
		update_task_proc :: proc(task: thread.Task) {
			data := cast(^update_task_data)task.data
			for obj in data.cmd.scene {
				iobject_update(auto_cast obj)
			}
			free(data, data.allocator)
		}
		
		// Add each render_cmd as a task to thread pool
		for cmd in __g_layer {
			data := new(update_task_data, context.temp_allocator)
			data.cmd = cmd
			data.allocator = context.temp_allocator
			thread.pool_add_task(&g_thread_pool, context.allocator, update_task_proc, data)
		}
		thread.pool_wait_all(&g_thread_pool)
	}
	graphics_draw_frame()

	wait_max_frame(paused_)
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

exiting :: #force_inline proc  "contextless"() -> bool {return __exiting}

start_console :: proc() {
	when ODIN_OS == .Windows {
		windows.AllocConsole()
		// 새로운 콘솔을 할당 했으므로 stdin, stdout, stderr를 다시 설정
		os.stdin = os.get_std_handle(uint(windows.STD_INPUT_HANDLE))
		os.stdout = os.get_std_handle(uint(windows.STD_OUTPUT_HANDLE))
		os.stderr = os.get_std_handle(uint(windows.STD_ERROR_HANDLE))
	}
}

is_main_thread :: #force_inline proc "contextless" () -> bool {
	return sync.current_thread_id() == main_thread_id
}

when is_web {
	@(export) step :: proc(dt: f64) -> bool {
		delta_time = u64(dt * 1000000000.0)
		render_loop()
		return !__exiting
	}
	@(export) _end :: proc() {
		__destroy()
	}
}