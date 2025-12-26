package engine

import "core:sync"
import "core:debug/trace"
import "core:math/linalg"
import "core:sys/windows"

import graphics_api "./graphics_api"


VSync :: graphics_api.VSync
ScreenMode :: graphics_api.ScreenMode
ScreenOrientation :: graphics_api.ScreenOrientation
MonitorInfo :: graphics_api.MonitorInfo

Paused :: proc "contextless" () -> bool {
	return graphics_api.paused
}

Activated :: proc "contextless" () -> bool {
	return graphics_api.activated
}


SetFullScreenMode :: proc "contextless" (monitor:^MonitorInfo) {
	when !is_mobile {
		sync.mutex_lock(&graphics_api.fullScreenMtx)
		defer sync.mutex_unlock(&graphics_api.fullScreenMtx)
		graphics_api.SavePrevWindow()
		graphics_api.glfwSetFullScreenMode(monitor)
		graphics_api.__screenMode = .Fullscreen
	}
}
SetBorderlessScreenMode :: proc "contextless" (monitor:^MonitorInfo) {
	when !is_mobile {
		sync.mutex_lock(&graphics_api.fullScreenMtx)
		defer sync.mutex_unlock(&graphics_api.fullScreenMtx)
		graphics_api.SavePrevWindow()
		graphics_api.glfwSetBorderlessScreenMode(monitor)
		graphics_api.__screenMode = .Borderless
	}
}
SetWindowMode :: proc "contextless" () {
	when !is_mobile {
		sync.mutex_lock(&graphics_api.fullScreenMtx)
		defer sync.mutex_unlock(&graphics_api.fullScreenMtx)
		graphics_api.SavePrevWindow()
		graphics_api.glfwSetWindowMode()
		graphics_api.__screenMode = .Window
	}
}
MonitorLock :: proc "contextless" () {
	sync.mutex_lock(&graphics_api.monitorsMtx)
	if graphics_api.monitorLocked do trace.panic_log("already monitorLocked locked")
	graphics_api.monitorLocked = true
}
MonitorUnlock :: proc "contextless" () {
	if !graphics_api.monitorLocked do trace.panic_log("already monitorLocked unlocked")
	graphics_api.monitorLocked = false
	sync.mutex_unlock(&graphics_api.monitorsMtx)
}

GetMonitors :: proc "contextless" () -> []MonitorInfo {
	if !graphics_api.monitorLocked do trace.panic_log("call inside monitorLock")
	return graphics_api.monitors[:len(graphics_api.monitors)]
}

GetCurrentMonitor :: proc "contextless" () -> ^MonitorInfo {
	if !graphics_api.monitorLocked do trace.panic_log("call inside monitorLock")
	return graphics_api.currentMonitor
}

GetMonitorFromWindow :: proc "contextless" () -> ^MonitorInfo #no_bounds_check {
	if !graphics_api.monitorLocked do trace.panic_log("call inside monitorLock")
	for &value in graphics_api.monitors {
		if linalg.Rect_PointIn(value.rect, [2]i32{auto_cast graphics_api.__windowX.?, auto_cast graphics_api.__windowY.?}) do return &value
	}
	return graphics_api.primaryMonitor
}

WindowWidth :: proc "contextless" () -> int {
	return graphics_api.__windowWidth.?
}
WindowHeight :: proc "contextless" () -> int {
	return graphics_api.__windowHeight.?
}
WindowX :: proc "contextless" () -> int {
	return graphics_api.__windowX.?
}
WindowY :: proc "contextless" () -> int {
	return graphics_api.__windowY.?
}
SetVSync :: proc "contextless" (vSync:VSync) {
	graphics_api.__vSync = vSync
	graphics_api.sizeUpdated = true
}
GetVSync :: proc "contextless" () -> VSync {
	return graphics_api.__vSync
}

SetWindowIcon :: #force_inline proc "contextless" (icons:[]Icon_Image) {
	when !is_mobile {
	    graphics_api.glfwSetWindowIcon(auto_cast icons)
	}
}