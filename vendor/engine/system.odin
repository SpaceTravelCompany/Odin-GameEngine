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
import graphics_api "./graphics_api"

// Re-export types
ResourceUsage :: graphics_api.ResourceUsage

//@(private) render_th: ^thread.Thread

Exiting :: #force_inline proc  "contextless"() -> bool {return graphics_api.exiting}
dt :: #force_inline proc "contextless" () -> f64 { return f64(graphics_api.deltaTime) / 1000000000.0 }
dt_u64 :: #force_inline proc "contextless" () -> u64 { return graphics_api.deltaTime }
GetProcessorCoreLen :: #force_inline proc "contextless" () -> int { return graphics_api.processorCoreLen }

Init: #type proc()
Update: #type proc()
Destroy: #type proc()
Size: #type proc() = proc () {}
Activate: #type proc "contextless" () = proc "contextless" () {}
Close: #type proc "contextless" () -> bool = proc "contextless" () -> bool{ return true }

AndroidAPILevel :: enum u32 {
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

WindowsVersion :: enum {
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

WindowsPlatformVersion :: struct {
	version:WindowsVersion,
	buildNumber:u32,
	servicePack:u32,
}
AndroidPlatformVersion :: struct {
	apiLevel:AndroidAPILevel,
}
LinuxPlatformVersion :: struct {
	sysName:string,
	nodeName:string,
	release:string,
	version:string,
	machine:string,
}

when is_android {
	GetPlatformVersion :: #force_inline proc "contextless" () -> AndroidPlatformVersion {
		return graphics_api.androidPlatform
	}
} else when ODIN_OS == .Linux {
	GetPlatformVersion :: #force_inline proc "contextless" () -> LinuxPlatformVersion {
		return graphics_api.linuxPlatform
	}
} else when ODIN_OS == .Windows {
	GetPlatformVersion :: #force_inline proc "contextless" () -> WindowsPlatformVersion {
		return graphics_api.windowsPlatform
	}
}



is_android :: ODIN_PLATFORM_SUBTARGET == .Android
is_mobile :: is_android
is_log :: #config(__log__, false)
is_console :: #config(__console__, false)

Icon_Image :: glfw.Image

@(private="file") inited := false

@(private) windows_hInstance:windows.HINSTANCE

defAllocator :: proc "contextless" () -> mem.Allocator {
	return graphics_api.engineDefAllocator
}

engineMain :: proc(
	windowTitle:cstring = "xfit",
	windowX:Maybe(int) = nil,
	windowY:Maybe(int) = nil,
	windowWidth:Maybe(int) = nil,
	windowHeight:Maybe(int) = nil,
	vSync:VSync = .Double,
) {
	when ODIN_OS == .Windows {
		windows_hInstance = auto_cast windows.GetModuleHandleA(nil)
	}

	graphics_api.system_start()

	assert(!(windowWidth != nil && windowWidth.? <= 0))
	assert(!(windowHeight != nil && windowHeight.? <= 0))

	systemInit()
	systemStart()

	inited = true

	graphics_api.__windowTitle = windowTitle
	when is_android {
		when is_console {
			trace.panic_log("Console mode is not supported on Android.")
		}
		graphics_api.__windowX = 0
		graphics_api.__windowY = 0

		__android_SetApp(auto_cast android.get_android_app())
	} else {
		when !is_console {
			graphics_api.__windowX = windowX
			graphics_api.__windowY = windowY
			graphics_api.__windowWidth = windowWidth
			graphics_api.__windowHeight = windowHeight
		}
	}
	graphics_api.__vSync = vSync

	when is_android {
		androidStart()
	} else {
		when is_console {
			Init()
			Destroy()
			systemDestroy()
			systemAfterDestroy()
		} else {
			windowStart()

			graphics_api.graphics_init()

			Init()

			for !graphics_api.exiting {
				systemLoop()
			}

			graphics_api.graphics_wait_device_idle()

			Destroy()

			graphics_api.graphics_destroy()

			systemDestroy()

			systemAfterDestroy()
		}	
	}
}

@(private) systemLoop :: proc() {
	when is_android {
	} else {
		graphics_api.glfwLoop()
	}
}

@(private) systemInit :: proc() {
	graphics_api.monitors = mem.make_non_zeroed([dynamic]MonitorInfo)
	when is_android {
	} else {
		graphics_api.glfwSystemInit()
	}
}

@(private) systemStart :: proc() {
	when is_android {
	} else {
		graphics_api.glfwSystemStart()
	}
}

@(private) windowStart :: proc() {
	when is_android {
	} else {
		graphics_api.glfwStart()
	}
}

@(private) systemDestroy :: proc() {
	when is_android {
	} else {
		graphics_api.glfwDestroy()
		graphics_api.glfwSystemDestroy()
	}
}
@(private) systemAfterDestroy :: proc() {
	delete(graphics_api.monitors)
	graphics_api.graphics_after_destroy()
}

@private @thread_local trackAllocator:mem.Tracking_Allocator

StartTrackingAllocator :: proc() {
	when ODIN_DEBUG {
		mem.tracking_allocator_init(&trackAllocator, context.allocator)
		context.allocator = mem.tracking_allocator(&trackAllocator)
	}
}

DestroyTrackAllocator :: proc() {
	when ODIN_DEBUG {
		if len(trackAllocator.allocation_map) > 0 {
			fmt.eprintf("=== %v allocations not freed: ===\n", len(trackAllocator.allocation_map))
			for _, entry in trackAllocator.allocation_map {
				fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
			}
		}
		if len(trackAllocator.bad_free_array) > 0 {
			fmt.eprintf("=== %v incorrect frees: ===\n", len(trackAllocator.bad_free_array))
			for entry in trackAllocator.bad_free_array {
				fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
			}
		}
		mem.tracking_allocator_destroy(&trackAllocator)
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


GetMaxFrame :: #force_inline proc "contextless" () -> f64 {
	return intrinsics.atomic_load_explicit(&graphics_api.maxFrame,.Relaxed)
}


GetFPS :: #force_inline proc "contextless" () -> f64 {
	if graphics_api.deltaTime == 0 do return 0
	return 1.0 / dt()
}

SetMaxFrame :: #force_inline proc "contextless" (_maxframe: f64) {
	intrinsics.atomic_store_explicit(&graphics_api.maxFrame, _maxframe, .Relaxed)
}

//_int * 1000000000 + _dec
SecondToNanoSecond :: #force_inline proc "contextless" (_int: $T, _dec: T) -> T where intrinsics.type_is_integer(T) {
    return _int * 1000000000 + _dec
}

SecondToNanoSecond2 :: #force_inline proc "contextless" (_sec: $T, _milisec: T, _usec: T, _nsec: T) -> T where intrinsics.type_is_integer(T) {
    return _sec * 1000000000 + _milisec * 1000000 + _usec * 1000 + _nsec
}

is_main_thread :: #force_inline proc "contextless" () -> bool {
	return graphics_api.is_main_thread()
}


Windows_SetResIcon :: proc "contextless" (icon_resource_number:int) {
	when ODIN_OS == .Windows {
		hWnd := graphics_api.glfwGetHwnd()
		icon := windows.LPARAM(uintptr(windows.LoadIconW(windows_hInstance, auto_cast windows.MAKEINTRESOURCEW(icon_resource_number))))
		windows.SendMessageW(hWnd, windows.WM_SETICON, 1, icon)
		windows.SendMessageW(hWnd, windows.WM_SETICON, 0, icon)
	}
}

exit :: proc "contextless" () {
	when is_mobile {
	} else {
		graphics_api.glfwDestroy()
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