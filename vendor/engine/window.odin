package engine

import "core:sync"
import "core:debug/trace"
import "core:math/linalg"
import "core:sys/windows"

@(private) __windowWidth: Maybe(int)
@(private) __windowHeight: Maybe(int)
@(private) __windowX: Maybe(int)
@(private) __windowY: Maybe(int)

@(private) prevWindowX: int
@(private) prevWindowY: int
@(private) prevWindowWidth: int
@(private) prevWindowHeight: int

@(private) __screenIdx: int = 0
@(private) __screenMode: ScreenMode
@(private) __windowTitle: cstring
@(private) __screenOrientation:ScreenOrientation = .Unknown

@(private) monitorsMtx:sync.Mutex
@(private) monitors: [dynamic]MonitorInfo
@(private) primaryMonitor: ^MonitorInfo
@(private) currentMonitor: ^MonitorInfo = nil

@(private) __isFullScreenEx := false
@(private) __vSync:VSync
@(private) monitorLocked:bool = false

@(private) paused := false
@(private) activated := false
@(private) sizeUpdated := false

@(private) fullScreenMtx : sync.Mutex

VSync :: enum {Double, Triple, None}

ScreenMode :: enum {Window, Borderless, Fullscreen}

ScreenOrientation :: enum {
	Unknown,
	Landscape90,
	Landscape270,
	Vertical180,
	Vertical360,
}

MonitorInfo :: struct {
	rect:       linalg.RectI,
	refreshRate: u32,
	name:       string,
	isPrimary:  bool,
}

Paused :: proc "contextless" () -> bool {
	return paused
}

Activated :: proc "contextless" () -> bool {
	return activated
}

@private SavePrevWindow :: proc "contextless" () {
	prevWindowX = __windowX.?
    prevWindowY = __windowY.?
    prevWindowWidth = __windowWidth.?
    prevWindowHeight = __windowHeight.?
}

SetFullScreenMode :: proc "contextless" (monitor:^MonitorInfo) {
	when !is_mobile {
		sync.mutex_lock(&fullScreenMtx)
		defer sync.mutex_unlock(&fullScreenMtx)
		SavePrevWindow()
		glfwSetFullScreenMode(monitor)
		__screenMode = .Fullscreen
	}
}
SetBorderlessScreenMode :: proc "contextless" (monitor:^MonitorInfo) {
	when !is_mobile {
		sync.mutex_lock(&fullScreenMtx)
		defer sync.mutex_unlock(&fullScreenMtx)
		SavePrevWindow()
		glfwSetBorderlessScreenMode(monitor)
		__screenMode = .Borderless
	}
}
SetWindowMode :: proc "contextless" () {
	when !is_mobile {
		sync.mutex_lock(&fullScreenMtx)
		defer sync.mutex_unlock(&fullScreenMtx)
		SavePrevWindow()
		glfwSetWindowMode()
		__screenMode = .Window
	}
}
MonitorLock :: proc "contextless" () {
	sync.mutex_lock(&monitorsMtx)
	if monitorLocked do trace.panic_log("already monitorLocked locked")
	monitorLocked = true
}
MonitorUnlock :: proc "contextless" () {
	if !monitorLocked do trace.panic_log("already monitorLocked unlocked")
	monitorLocked = false
	sync.mutex_unlock(&monitorsMtx)
}

GetMonitors :: proc "contextless" () -> []MonitorInfo {
	if !monitorLocked do trace.panic_log("call inside monitorLock")
	return monitors[:len(monitors)]
}

GetCurrentMonitor :: proc "contextless" () -> ^MonitorInfo {
	if !monitorLocked do trace.panic_log("call inside monitorLock")
	return currentMonitor
}

GetMonitorFromWindow :: proc "contextless" () -> ^MonitorInfo #no_bounds_check {
	if !monitorLocked do trace.panic_log("call inside monitorLock")
	for &value in monitors {
		if linalg.Rect_PointIn(value.rect, [2]i32{auto_cast __windowX.?, auto_cast __windowY.?}) do return &value
	}
	return primaryMonitor
}

WindowWidth :: proc "contextless" () -> int {
	return __windowWidth.?
}
WindowHeight :: proc "contextless" () -> int {
	return __windowHeight.?
}
WindowX :: proc "contextless" () -> int {
	return __windowX.?
}
WindowY :: proc "contextless" () -> int {
	return __windowY.?
}
SetVSync :: proc "contextless" (vSync:VSync) {
	__vSync = vSync
	sizeUpdated = true
}
GetVSync :: proc "contextless" () -> VSync {
	return __vSync
}

SetWindowIcon :: #force_inline proc "contextless" (icons:[]Icon_Image) {
	when !is_mobile {
	    glfwSetWindowIcon(auto_cast icons)
	}
}