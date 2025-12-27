package engine

import "base:intrinsics"
import "core:fmt"
import "core:c/libc"
import "core:c"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:os/os2"
import "core:sys/windows"
import "core:mem"
import "core:mem/virtual"
import "core:io"
import "core:time"
import "core:reflect"
import "core:thread"
import "core:sync"
import "core:strings"
import "base:runtime"
import "core:debug/trace"

import "core:sys/android"
import "vendor:glfw"
import sys "./sys"

// Re-export types
resource_usage :: sys.resource_usage

//@(private) render_th: ^thread.Thread

exiting :: #force_inline proc  "contextless"() -> bool {return sys.exiting}
dt :: #force_inline proc "contextless" () -> f64 { return f64(sys.delta_time) / 1000000000.0 }
dt_u64 :: #force_inline proc "contextless" () -> u64 { return sys.delta_time }
get_processor_core_len :: #force_inline proc "contextless" () -> int { return sys.processor_core_len }

init: #type proc()
update: #type proc()
destroy: #type proc()
size: #type proc() = proc () {}
activate: #type proc "contextless" () = proc "contextless" () {}
close: #type proc "contextless" () -> bool = proc "contextless" () -> bool{ return true }

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

when is_android {
	get_platform_version :: #force_inline proc "contextless" () -> android_platform_version {
		return sys.android_platform
	}
} else when ODIN_OS == .Linux {
	get_platform_version :: #force_inline proc "contextless" () -> linux_platform_version {
		return sys.linux_platform
	}
} else when ODIN_OS == .Windows {
	get_platform_version :: #force_inline proc "contextless" () -> windows_platform_version {
		return sys.windows_platform
	}
}



is_android :: ODIN_PLATFORM_SUBTARGET == .Android
is_mobile :: is_android
is_log :: #config(__log__, false)
is_console :: #config(__console__, false)

icon_image :: glfw.Image

@(private="file") inited := false

@(private) windows_h_instance:windows.HINSTANCE

def_allocator :: proc "contextless" () -> mem.Allocator {
	return sys.engine_def_allocator
}

engine_main :: proc(
	window_title:cstring = "xfit",
	window_x:Maybe(int) = nil,
	window_y:Maybe(int) = nil,
	window_width:Maybe(int) = nil,
	window_height:Maybe(int) = nil,
	v_sync:sys.v_sync = .Double,
) {
	when ODIN_OS == .Windows {
		windows_h_instance = auto_cast windows.GetModuleHandleA(nil)
	}

	sys.system_start()

	assert(!(window_width != nil && window_width.? <= 0))
	assert(!(window_height != nil && window_height.? <= 0))

	inited = true

	sys.__window_title = window_title
	when is_android {
		when is_console {
			trace.panic_log("Console mode is not supported on Android.")
		}
		sys.__window_x = 0
		sys.__window_y = 0

		sys.__android_set_app(auto_cast android.get_android_app())
	} else {
		when !is_console {
			sys.__window_x = window_x
			sys.__window_y = window_y
			sys.__window_width = window_width
			sys.__window_height = window_height
		}
	}
	sys.__v_sync = v_sync

	when is_android {
		sys.android_start()
	} else {
		when is_console {
			init()
			destroy()
			system_destroy()
			sys.system_after_destroy()
		} else {
			window_start()

			sys.graphics_init()

			init()

			for !sys.exiting {
				system_loop()
			}

			sys.graphics_wait_device_idle()

			destroy()

			sys.graphics_destroy()

			system_destroy()

			sys.system_after_destroy()
		}	
	}
}

system_loop :: proc() {
	when is_android {
	} else {
		sys.glfw_loop()
	}
}

window_start :: proc() {
	when is_android {
	} else {
		sys.glfw_start()
	}
}

system_destroy :: proc() {
	when is_android {
	} else {
		sys.glfw_destroy()
		sys.glfw_system_destroy()
	}
}

@private @thread_local track_allocator:mem.Tracking_Allocator

start_tracking_allocator :: proc() {
	when ODIN_DEBUG {
		mem.tracking_allocator_init(&track_allocator, context.allocator)
		context.allocator = mem.tracking_allocator(&track_allocator)
	}
}

destroy_tracking_allocator :: proc() {
	when ODIN_DEBUG {
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
	}
}




// @(private) CreateRenderFuncThread :: proc() {
// 	render_th = thread.create_and_start(RenderFunc)
// }

// @(private) RenderFunc :: proc() {
// 	vkStart()

// 	Init()

// 	for !exiting {
// 		RenderLoop()
// 	}

// 	vkWaitDeviceIdle()

// 	Destroy()

// 	vkDestory()
// }


get_max_frame :: #force_inline proc "contextless" () -> f64 {
	return intrinsics.atomic_load_explicit(&sys.max_frame,.Relaxed)
}


get_fps :: #force_inline proc "contextless" () -> f64 {
	if sys.delta_time == 0 do return 0
	return 1.0 / dt()
}

set_max_frame :: #force_inline proc "contextless" (_maxframe: f64) {
	intrinsics.atomic_store_explicit(&sys.max_frame, _maxframe, .Relaxed)
}

//_int * 1000000000 + _dec
second_to_nano_second :: #force_inline proc "contextless" (_int: $T, _dec: T) -> T where intrinsics.type_is_integer(T) {
    return _int * 1000000000 + _dec
}

second_to_nano_second2 :: #force_inline proc "contextless" (_sec: $T, _milisec: T, _usec: T, _nsec: T) -> T where intrinsics.type_is_integer(T) {
    return _sec * 1000000000 + _milisec * 1000000 + _usec * 1000 + _nsec
}

is_main_thread :: #force_inline proc "contextless" () -> bool {
	return sys.is_main_thread()
}


windows_set_res_icon :: proc "contextless" (icon_resource_number:int) {
	when ODIN_OS == .Windows {
		h_wnd := sys.glfw_get_hwnd()
		icon := windows.LPARAM(uintptr(windows.LoadIconW(windows_h_instance, auto_cast windows.MAKEINTRESOURCEW(icon_resource_number))))
		windows.SendMessageW(h_wnd, windows.WM_SETICON, 1, icon)
		windows.SendMessageW(h_wnd, windows.WM_SETICON, 0, icon)
	}
}

exit :: proc "contextless" () {
	when is_mobile {
	} else {
		sys.glfw_destroy()
	}
}


//only for windows
start_console :: proc() {
	when ODIN_OS == .Windows {
		windows.AllocConsole()
		// 새로운 콘솔을 할당 했으므로 stdin, stdout, stderr를 다시 설정
		os.stdin = os.get_std_handle(uint(windows.STD_INPUT_HANDLE))
		os.stdout = os.get_std_handle(uint(windows.STD_OUTPUT_HANDLE))
		os.stderr = os.get_std_handle(uint(windows.STD_ERROR_HANDLE))
	}
}