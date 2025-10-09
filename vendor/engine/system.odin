package engine

import "base:intrinsics"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:os"
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

//@(private) render_th: ^thread.Thread

@(private) exiting := false
@(private) programStart := true
@(private) loopStart := false
@(private) maxFrame : f64
@(private) deltaTime : u64
@(private) processorCoreLen : int
@(private) gClearColor : [4]f32 = {0.0, 0.0, 0.0, 1.0}

Exiting :: #force_inline proc  "contextless"() -> bool {return exiting}
dt :: #force_inline proc "contextless" () -> f64 { return f64(deltaTime) / 1000000000.0 }
dt_u64 :: #force_inline proc "contextless" () -> u64 { return deltaTime }
GetProcessorCoreLen :: #force_inline proc "contextless" () -> int { return processorCoreLen }

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
	@(private) androidPlatform:AndroidPlatformVersion
	GetPlatformVersion :: #force_inline proc "contextless" () -> AndroidPlatformVersion {
		return androidPlatform
	}
} else when ODIN_OS == .Linux {
	@(private) linuxPlatform:LinuxPlatformVersion
	GetPlatformVersion :: #force_inline proc "contextless" () -> LinuxPlatformVersion {
		return linuxPlatform
	}
} else when ODIN_OS == .Windows {
	@(private) windowsPlatform:WindowsPlatformVersion
	GetPlatformVersion :: #force_inline proc "contextless" () -> WindowsPlatformVersion {
		return windowsPlatform
	}
}



is_android :: ODIN_PLATFORM_SUBTARGET == .Android
is_mobile :: is_android
is_log :: #config(__log__, false)
is_console :: #config(__console__, false)

Icon_Image :: glfw.Image

@(private="file") inited := false

@(private = "file") __arena: virtual.Arena
@(private) engineDefAllocator : runtime.Allocator

@(private) windows_hInstance:windows.HINSTANCE

defAllocator :: proc "contextless" () -> runtime.Allocator {
	return engineDefAllocator
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

	assert(!(windowWidth != nil && windowWidth.? <= 0))
	assert(!(windowHeight != nil && windowHeight.? <= 0))

	_ = virtual.arena_init_growing(&__arena)
	engineDefAllocator =  virtual.arena_allocator(&__arena)
	
	systemInit()
	systemStart()
	inited = true

	__windowTitle = windowTitle
	when is_android {
		when is_console {
			trace.panic_log("Console mode is not supported on Android.")
		}
		__windowX = 0
		__windowY = 0

		__android_SetApp(auto_cast android.get_android_app())
	} else {
		when !is_console {
			__windowX = windowX
			__windowY = windowY
			__windowWidth = windowWidth
			__windowHeight = windowHeight
		}
	}
	__vSync = vSync

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

			vkStart()

			Init()

			for !exiting {
				systemLoop()
			}

			vkWaitDeviceIdle()

			Destroy()

			vkDestory()

			systemDestroy()

			systemAfterDestroy()
		}	
	}
}

@(private) systemLoop :: proc() {
	when is_android {
	} else {
		glfwLoop()
	}
}

@(private) systemInit :: proc() {
	monitors = mem.make_non_zeroed([dynamic]MonitorInfo)
	when is_android {
	} else {
		glfwSystemInit()
	}
}

@(private) systemStart :: proc() {
	when is_android {
	} else {
		glfwSystemStart()
	}
}

@(private) windowStart :: proc() {
	when is_android {
	} else {
		glfwStart()
	}
}

@(private) systemDestroy :: proc() {
	when is_android {
	} else {
		glfwDestroy()
		glfwSystemDestroy()
	}
}
@(private) systemAfterDestroy :: proc() {
	delete(monitors)

	virtual.arena_destroy(&__arena)
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


when is_android {
	print :: proc(args: ..any, sep := " ", flush := true) -> int {
		_ = flush
		cstr := fmt.caprint(..args, sep=sep)
		defer delete(cstr)
		return auto_cast android.__android_log_write(android.LogPriority.INFO, ODIN_BUILD_PROJECT_NAME, cstr)
	}
	println  :: print
	printf   :: proc(_fmt: string, args: ..any, flush := true) -> int {
		_ = flush
		cstr := fmt.caprintf(_fmt, ..args)
		defer delete(cstr)
		return auto_cast android.__android_log_write(android.LogPriority.INFO, ODIN_BUILD_PROJECT_NAME, cstr)
	}
	printfln :: printf
	printCustomAndroid :: proc(args: ..any, logPriority: android.LogPriority = .INFO, sep := " ") -> int {
		cstr := fmt.caprint(..args, sep=sep)
		defer delete(cstr)
		return auto_cast android.__android_log_write(logPriority, ODIN_BUILD_PROJECT_NAME, cstr)
	}
} else {
	println :: fmt.println
	printfln :: fmt.printfln
	printf :: fmt.printf
	print :: fmt.print

	/**
	* Android log priority values, in increasing order of priority.
	*/
	LogPriority :: enum i32 {
	/** For internal use only.  */
	UNKNOWN = 0,
	/** The default priority, for internal use only.  */
	DEFAULT, /* only for SetMinPriority() */
	/** Verbose logging. Should typically be disabled for a release apk. */
	VERBOSE,
	/** Debug logging. Should typically be disabled for a release apk. */
	DEBUG,
	/** Informational logging. Should typically be disabled for a release apk. */
	INFO,
	/** Warning logging. For use with recoverable failures. */
	WARN,
	/** Error logging. For use with unrecoverable failures. */
	ERROR,
	/** Fatal logging. For use when aborting. */
	FATAL,
	/** For internal use only.  */
	SILENT, /* only for SetMinPriority(); must be last */
	}

	printCustomAndroid :: proc(args: ..any, logPriority:LogPriority = .INFO, sep := " ") -> int {
		_ = logPriority
		return print(..args, sep = sep)
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

@private CalcFrameTime :: proc(Paused_: bool) {
	@static start:time.Time
	@static now:time.Time

	if !loopStart {
		loopStart = true
		start = time.now()
		now = start
	} else {
		maxFrame_ := GetMaxFrame()
		if Paused_ && maxFrame_ == 0 {
			maxFrame_ = 60
		}
		n := time.now()
		delta := n._nsec - now._nsec

		if maxFrame_ > 0 {
			maxF := u64(1 * (1 / maxFrame_)) * 1000000000
			if maxF > auto_cast delta {
				time.sleep(auto_cast (i64(maxF) - delta))
				n = time.now()
				delta = n._nsec - now._nsec
			}
		}
		now = n
		deltaTime = auto_cast delta
	}
}

@(private) RenderLoop :: proc() {
	Paused_ := Paused()

	CalcFrameTime(Paused_)
	
	Update()
	if gMainRenderCmdIdx >= 0 {
		for obj in gRenderCmd[gMainRenderCmdIdx].scene {
			IObject_Update(obj)
		}
	}

	if !Paused_ {
		vkDrawFrame()
	}
}

GetMaxFrame :: #force_inline proc "contextless" () -> f64 {
	return intrinsics.atomic_load_explicit(&maxFrame,.Relaxed)
}


GetFPS :: #force_inline proc "contextless" () -> f64 {
	if deltaTime == 0 do return 0
	return 1.0 / dt()
}

SetMaxFrame :: #force_inline proc "contextless" (_maxframe: f64) {
	intrinsics.atomic_store_explicit(&maxFrame, _maxframe, .Relaxed)
}

//_int * 1000000000 + _dec
SecondToNanoSecond :: #force_inline proc "contextless" (_int: $T, _dec: T) -> T where intrinsics.type_is_integer(T) {
    return _int * 1000000000 + _dec
}

SecondToNanoSecond2 :: #force_inline proc "contextless" (_sec: $T, _milisec: T, _usec: T, _nsec: T) -> T where intrinsics.type_is_integer(T) {
    return _sec * 1000000000 + _milisec * 1000000 + _usec * 1000 + _nsec
}

IsInMainThread :: #force_inline proc "contextless" () -> bool {
	return sync.current_thread_id() == vkThreadId
}


Windows_SetResIcon :: proc "contextless" (icon_resource_number:int) {
	when ODIN_OS == .Windows {
		hWnd := glfwGetHwnd()
		icon := windows.LPARAM(uintptr(windows.LoadIconW(windows_hInstance, auto_cast windows.MAKEINTRESOURCEW(icon_resource_number))))
		windows.SendMessageW(hWnd, windows.WM_SETICON, 1, icon)
		windows.SendMessageW(hWnd, windows.WM_SETICON, 0, icon)
	}
}

exit :: proc "contextless" () {
	when is_mobile {
	} else {
		glfwDestroy()
	}
}