package engine

import "base:intrinsics"
import "base:library"
import "base:runtime"
import "core:c"
import "core:c/libc"
import "core:debug/trace"
import "core:fmt"
import "core:io"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:mem/virtual"
import "core:os"
import "core:os/os2"
import "core:reflect"
import "core:strings"
import "core:sync"
import "core:sys/android"
import "core:sys/windows"
import "core:thread"
import "core:time"
import "vendor:glfw"

// ============================================================================
// Type Definitions
// ============================================================================

init: #type proc()
update: #type proc()
destroy: #type proc()
size: #type proc() = proc () {}
activate: #type proc "contextless" () = proc "contextless" () {}
close: #type proc "contextless" () -> bool = proc "contextless" () -> bool{ return true }

dt :: #force_inline proc "contextless" () -> f64 { return f64(delta_time) / 1000000000.0 }
dt_u64 :: #force_inline proc "contextless" () -> u64 { return delta_time }
get_processor_core_len :: #force_inline proc "contextless" () -> int { return processor_core_len }

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

// ============================================================================
// Platform Detection
// ============================================================================

is_android :: ODIN_PLATFORM_SUBTARGET == .Android
is_mobile :: is_android
is_log :: #config(__log__, false)
is_console :: #config(__console__, false)

icon_image :: glfw.Image

// ============================================================================
// Global Variables
// ============================================================================

@(private="file") inited := false

@(private) windows_h_instance:windows.HINSTANCE

when library.is_android {
	android_platform:android_platform_version
} else when ODIN_OS == .Linux {
	linux_platform:linux_platform_version
} else when ODIN_OS == .Windows {
	windows_platform:windows_platform_version
}

@private main_thread_id: int
temp_arena_allocator: mem.Allocator
engine_def_allocator: mem.Allocator

@private @thread_local track_allocator:mem.Tracking_Allocator

// ============================================================================
// Utility Functions
// ============================================================================

exiting :: #force_inline proc  "contextless"() -> bool {return __exiting}

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

// ============================================================================
// System Initialization & Cleanup
// ============================================================================

system_start :: #force_inline proc() {
	engine_def_allocator = context.allocator
	start_tracking_allocator()

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

def_allocator :: #force_inline proc "contextless" () -> mem.Allocator {
	return engine_def_allocator
}

// ============================================================================
// Main Entry Point
// ============================================================================

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

		__android_set_app(auto_cast android.get_android_app())
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
		__destroy_tracking_allocator()
	}
}

system_loop :: proc() {
	when is_android {
	} else {
		glfw_loop()
	}
}

// ============================================================================
// Window Management
// ============================================================================

window_start :: proc() {
	when is_android {
	} else {
		glfw_start()
	}
}

system_destroy :: proc() {
	when is_android {
	} else {
		glfw_destroy()
		glfw_system_destroy()
	}
}

// ============================================================================
// Memory Tracking
// ============================================================================

start_tracking_allocator :: proc() {
	when ODIN_DEBUG {
		mem.tracking_allocator_init(&track_allocator, context.allocator)
		if engine_def_allocator == context.allocator {
			engine_def_allocator = mem.tracking_allocator(&track_allocator)
			context.allocator = engine_def_allocator
		} else {
			context.allocator = mem.tracking_allocator(&track_allocator)
		}
	}
}

destroy_tracking_allocator :: proc() {
	when ODIN_DEBUG {
		__destroy_tracking_allocator()
	}
}

@private __destroy_tracking_allocator :: proc() {
	when ODIN_DEBUG {
		if track_allocator.backing.procedure != nil {
			if len(track_allocator.allocation_map) > 0 {
			fmt.eprintf("=== %v allocations not freed: ===\n", len(track_allocator.allocation_map))
			for _, entry in track_allocator.allocation_map {
				fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
			}
			}
			if len(track_allocator.bad_free_array) > 0 {
				fmt.eprintf("=== %v incorrect frees: ===\n", len(track_allocator.bad_free_array))
				for entry in track_allocator.bad_free_array {
					fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track_allocator)
			track_allocator = {}
		}
	}
}

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

// ============================================================================
// Frame Management
// ============================================================================

get_max_frame :: #force_inline proc "contextless" () -> f64 {
	return intrinsics.atomic_load_explicit(&max_frame,.Relaxed)
}


get_fps :: #force_inline proc "contextless" () -> f64 {
	if delta_time == 0 do return 0
	return 1.0 / dt()
}

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

// ============================================================================
// Platform-Specific Functions
// ============================================================================

windows_set_res_icon :: proc "contextless" (icon_resource_number:int) {
	when ODIN_OS == .Windows {
		h_wnd := glfw_get_hwnd()
		icon := windows.LPARAM(uintptr(windows.LoadIconW(windows_h_instance, auto_cast windows.MAKEINTRESOURCEW(icon_resource_number))))
		windows.SendMessageW(h_wnd, windows.WM_SETICON, 1, icon)
		windows.SendMessageW(h_wnd, windows.WM_SETICON, 0, icon)
	}
}

exit :: proc "contextless" () {
	when is_mobile {
	} else {
		glfw_destroy()
	}
}

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

render_loop :: proc() {
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