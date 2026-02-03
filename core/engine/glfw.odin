#+private
package engine

import "base:intrinsics"
import "base:library"
import "base:runtime"
import "core:bytes"
import "core:c"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:reflect"
import "core:strings"
import "core:sync"
import "core:sys/linux"
import "core:sys/posix"
import "core:sys/windows"
import "core:thread"
import vk "vendor:vulkan"
import "vendor:glfw"
import "core:log"

when !library.is_android {

@(private="file") wnd:glfw.WindowHandle = nil
@(private="file") glfw_monitors:[dynamic]glfw.MonitorHandle

glfw_start :: proc(_screen_idx: int) {
	//?default screen idx 0
	if __window_width == nil do __window_width = int((monitors[0].rect.right - monitors[0].rect.left) / 2)
	if __window_height == nil do __window_height = int(abs(monitors[0].rect.bottom - monitors[0].rect.top) / 2)
	if __window_x == nil do __window_x = int(monitors[0].rect.left + (monitors[0].rect.right - monitors[0].rect.left) / 4)
	if __window_y == nil do __window_y = int(monitors[0].rect.top + abs(monitors[0].rect.bottom - monitors[0].rect.top) / 4)

	save_prev_window()
	__screen_idx := _screen_idx
	if len(monitors) - 1 < __screen_idx {
		__screen_idx = 0
	}

	//? change use glfw.SetWindowAttrib()
	if __screen_mode == .Fullscreen {
		when ODIN_OS == .Windows {
			glfw.WindowHint(glfw.DECORATED, glfw.FALSE)
			glfw.WindowHint(glfw.FLOATING, glfw.TRUE)//미리 속성 지정한 뒤 생성

			wnd = glfw.CreateWindow(monitors[__screen_idx].rect.right - monitors[__screen_idx].rect.left,
				abs(monitors[__screen_idx].rect.bottom - monitors[__screen_idx].rect.top),
				__window_title,
				nil,
				nil)
		} else {
			wnd = glfw.CreateWindow(monitors[__screen_idx].rect.right - monitors[__screen_idx].rect.left,
				abs(monitors[__screen_idx].rect.bottom - monitors[__screen_idx].rect.top),
				__window_title,
				glfw_monitors[__screen_idx],
				nil)
		}	

		__window_x = int(monitors[__screen_idx].rect.left)
		__window_y = int(monitors[__screen_idx].rect.top)
		__window_width = int(monitors[__screen_idx].rect.right - monitors[__screen_idx].rect.left)
		__window_height = int(abs(monitors[__screen_idx].rect.bottom - monitors[__screen_idx].rect.top))
	} else {
		wnd = glfw.CreateWindow(auto_cast __window_width.?,
			auto_cast __window_height.?,
			__window_title,
			nil,
			nil)
	}
	glfw.SetWindowPos(wnd, auto_cast __window_x.?, auto_cast __window_y.?)

	//CreateRenderFuncThread()
}

when ODIN_OS == .Windows {
	glfw_get_current_hmonitor :: proc "contextless" () -> windows.HMONITOR {
		if wnd == nil do panic_contextless("glfw_get_current_hmonitor : wnd is nil")
		h_wnd := glfw.GetWin32Window(wnd)
		if h_wnd == nil do panic_contextless("glfw_get_current_hmonitor : h_wnd is nil")

		return windows.MonitorFromWindow(h_wnd, windows.Monitor_From_Flags.MONITOR_DEFAULTTONEAREST)
	}

	glfw_get_hwnd :: proc "contextless" () -> windows.HWND {
		if wnd == nil do panic_contextless("glfw_get_hwnd : wnd is nil")
		h_wnd := glfw.GetWin32Window(wnd)
		if h_wnd == nil do panic_contextless("glfw_get_hwnd : h_wnd is nil")

		return h_wnd
	}
}

glfw_set_full_screen_mode :: proc "contextless" (monitor:^monitor_info) {
	glfw.SetWindowAttrib(wnd, glfw.DECORATED, i32(glfw.FALSE))
	when ODIN_OS == .Windows {
		glfw.SetWindowMonitor(wnd, nil, monitor.rect.left,
			monitor.rect.top,
			monitor.rect.right - monitor.rect.left,
			abs(monitor.rect.bottom - monitor.rect.top),
			glfw.DONT_CARE)
	} else {
		for monitor_handle in glfw_monitors {
			if strings.compare(glfw.GetMonitorName(monitor_handle), monitor.name) == 0 {
				glfw.SetWindowMonitor(wnd, monitor_handle, monitor.rect.left,
					monitor.rect.top,
					monitor.rect.right - monitor.rect.left,
					abs(monitor.rect.bottom - monitor.rect.top),
					glfw.DONT_CARE)
				break
			}
		}	
	}
}

glfw_set_window_icon :: #force_inline  proc "contextless" (icons:[]glfw.Image) {
	glfw.SetWindowIcon(wnd, icons)
}

glfw_set_window_mode :: proc "contextless" () {
	glfw.SetWindowAttrib(wnd, glfw.DECORATED, i32(glfw.TRUE))

	glfw.SetWindowMonitor(wnd, nil, auto_cast prev_window_x,
		auto_cast prev_window_y,
		auto_cast prev_window_width,
		auto_cast prev_window_height,
	glfw.DONT_CARE)
}

@(private="file") glfw_init_monitors :: proc() {
	glfw_monitors = mem.make_non_zeroed([dynamic]glfw.MonitorHandle)
	_monitors := glfw.GetMonitors()

	for m in _monitors {
		glfw_append_monitor(m)
	}
}

@(private="file") glfw_append_monitor :: proc(m:glfw.MonitorHandle) {
	info:monitor_info
	info.name = glfw.GetMonitorName(m)
	info.rect.left, info.rect.top, _, _ = glfw.GetMonitorWorkarea(m)
	vid := glfw.GetVideoMode(m)

	info.rect.right = vid.width
	info.rect.bottom = vid.height
	info.rect.right += info.rect.left
	info.rect.bottom += info.rect.top
	info.is_primary = m == glfw.GetPrimaryMonitor()

	vid_mode :^glfw.VidMode = glfw.GetVideoMode(m)
	info.refresh_rate = auto_cast vid_mode.refresh_rate

	log.infof(
		"SYSLOG : ADD %s monitor name: %s, x:%d, y:%d, size.x:%d, size.y:%d, refleshrate:%d\n",
		"primary" if info.is_primary else "",
		info.name,
		info.rect.left,
		info.rect.top,
		info.rect.right - info.rect.left,
		abs(info.rect.top - info.rect.bottom),
		info.refresh_rate,
	)

	non_zero_append(&monitors, info)
	non_zero_append(&glfw_monitors, m)
}

glfw_vulkan_start :: proc () {
	if vk_surface != 0 do vk.DestroySurfaceKHR(vk_instance, vk_surface, nil)

	res := glfw.CreateWindowSurface(vk_instance, wnd, nil, &vk_surface)
	if res != .SUCCESS do log.panicf("glfw_vulkan_start : %s\n", res)
}


@(private="file") __glfw_logger : log.Logger

glfw_system_init :: proc() {
	res := glfw.Init()
	if !res do log.panicf("glfw.Init : %s\n", res)

	when ODIN_OS == .Linux {
		name:linux.UTS_Name
		err := linux.uname(&name)
		if err != .NONE do log.panicf("linux.uname : %s\n", err)

		linux_platform.sys_name = strings.clone_from_ptr(&name.sysname[0], bytes.index_byte(name.sysname[:], 0))
		linux_platform.node_name = strings.clone_from_ptr(&name.nodename[0], bytes.index_byte(name.nodename[:], 0))
		linux_platform.machine = strings.clone_from_ptr(&name.machine[0], bytes.index_byte(name.machine[:], 0))
		linux_platform.release = strings.clone_from_ptr(&name.release[0], bytes.index_byte(name.release[:], 0))
		linux_platform.version = strings.clone_from_ptr(&name.version[0], bytes.index_byte(name.version[:], 0))
		log.infof("SYSLOG : ", linux_platform)
	
		processor_core_len = auto_cast os._unix_get_nprocs()
		if processor_core_len == 0 do log.panicf("processor_core_len can't zero\n")
		log.infof("SYSLOG processor_core_len : %d\n", processor_core_len)
	} else when ODIN_OS == .Windows {
		system_info:windows.SYSTEM_INFO
		windows.GetSystemInfo(&system_info)
		processor_core_len = auto_cast system_info.dwNumberOfProcessors
		if processor_core_len == 0 do log.panicf("processor_core_len can't zero\n")

		os_version_info:windows.OSVERSIONINFOEXW
		os_version_info.dwOSVersionInfoSize = size_of(os_version_info)
		_ = windows.RtlGetVersion(&os_version_info)

		windows_platform.build_number = os_version_info.dwBuildNumber
		windows_platform.service_pack = auto_cast os_version_info.wServicePackMajor
		server_os := os_version_info.wProductType != 1 // not VER_NT_WORKSTATION
		if !server_os && os_version_info.dwBuildNumber >= 22000 {
			windows_platform.version = .Windows11
		} else if server_os && os_version_info.dwBuildNumber >= 20348 {
			windows_platform.version = .WindowsServer2022
		} else if server_os && os_version_info.dwBuildNumber >= 17763 {
			windows_platform.version = .WindowsServer2019
		} else if os_version_info.dwMajorVersion == 6 && os_version_info.dwMinorVersion == 1 {
			if server_os {
				windows_platform.version = .WindowsServer2008R2
			} else {
				windows_platform.version = .Windows7
			}
		} else if os_version_info.dwMajorVersion == 6 && os_version_info.dwMinorVersion == 2 {
			if server_os {
				windows_platform.version = .WindowsServer2012
			} else {
				windows_platform.version = .Windows8
			}
		} else if os_version_info.dwMajorVersion == 6 && os_version_info.dwMinorVersion == 3 {
			if server_os {
				windows_platform.version = .WindowsServer2012R2
			} else {
				windows_platform.version = .Windows8Point1
			}
		} else if os_version_info.dwMajorVersion == 10 && os_version_info.dwMinorVersion == 0 {
			if server_os {
				windows_platform.version = .WindowsServer2016
			} else {
				windows_platform.version = .Windows10
			}
		} else {
			windows_platform.version = .Unknown
			log.warn("unknown windows version")
		}

		log.infof("SYSLOG processor_core_len : %d\n", processor_core_len)
		log.infof("SYSLOG windows_platform : %v\n", windows_platform)
	}

	__glfw_logger = context.logger
	glfw.SetErrorCallback(glfw_error_callback)
}

glfw_error_callback :: proc "c" (error: c.int, description: cstring) {
	context = runtime.default_context()
	context.logger = __glfw_logger
	log.infof("SYSLOG : glfw", error, description)
}

glfw_system_start :: proc() {
	glfw_monitor_proc :: proc "c" (monitor: glfw.MonitorHandle, event: c.int) {
		sync.mutex_lock(&monitors_mtx)
		defer sync.mutex_unlock(&monitors_mtx)
		
		context = runtime.default_context() 
		if event == glfw.CONNECTED {
			glfw_append_monitor(monitor)
		} else if event == glfw.DISCONNECTED {
			for m, i in glfw_monitors {
				if m == monitor {
					log.infof(
						"SYSLOG : DEL %s monitor name: %s, x:%d, y:%d, size.x:%d, size.y:%d, refleshrate:%d\n",
						"primary" if monitors[i].is_primary else "",
						monitors[i].name,
						monitors[i].rect.left,
						monitors[i].rect.top,
						monitors[i].rect.right - monitors[i].rect.left,
						abs(monitors[i].rect.top - monitors[i].rect.bottom),
						monitors[i].refresh_rate,
					)

					ordered_remove(&glfw_monitors, i)
					ordered_remove(&monitors, i)
					break
				}
			}
		}
	}
	if get_vulkan_version().major < 1 {
		//Unless you will be using OpenGL or OpenGL ES with the same window as Vulkan, there is no need to create a context. You can disable context creation with the GLFW_CLIENT_API hint.
		glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	}

	glfw_init_monitors()
	glfw.SetMonitorCallback(glfw_monitor_proc)

	when ODIN_OS == .Windows {
		init_gamepad()
	}
}

glfw_destroy :: proc "contextless" () {
	if wnd != nil do glfw.SetWindowShouldClose(wnd, true)
	//!glfw.DestroyWindow(wnd) 를 쓰지 않는다 왜냐하면 윈도우만 종료되고 윈도우 루프를 빠져나가지 않는다.
}

glfw_system_destroy :: proc() {
	delete(glfw_monitors)

	when ODIN_OS == .Linux {
		delete(linux_platform.sys_name)
		delete(linux_platform.node_name)
		delete(linux_platform.machine)
		delete(linux_platform.release)
		delete(linux_platform.version)
	} else when ODIN_OS == .Windows {
		cleanup_gamepad()
	}

	glfw.Terminate()
}

glfw_loop :: proc() {
	glfw_key_proc :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: c.int) {
		if key > key_size-1 || key < 0 || !reflect.is_valid_enum_value(key_code, key) {
			return
		}
		context = runtime.default_context()
		switch action {
			case glfw.PRESS:
				if !keys[key] {
					keys[key] = true
					key_down(key_code(key))
				}
			case glfw.RELEASE:
				keys[key] = false
				key_up(key_code(key))
			case glfw.REPEAT:
				key_repeat(key_code(key))
		}
	}
	glfw_mouse_button_proc :: proc "c" (window: glfw.WindowHandle, button, action, mods: c.int) {
		context = runtime.default_context()
		switch action {
			case glfw.PRESS:
				mouse_button_down(button_idx(button), __mouse_pos.x, __mouse_pos.y)
			case glfw.RELEASE:
				mouse_button_up(button_idx(button), __mouse_pos.x, __mouse_pos.y)
		}
	}
	glfw_cursor_pos_proc :: proc "c" (window: glfw.WindowHandle, xpos,  ypos: f64) {
		context = runtime.default_context()
		__mouse_pos.x = auto_cast xpos
		__mouse_pos.y = auto_cast ypos
		mouse_move(__mouse_pos.x, __mouse_pos.y)
	}
	glfw_cursor_enter_proc :: proc "c" (window: glfw.WindowHandle, entered: c.int) {
		context = runtime.default_context()
		if b32(entered) {
			__is_mouse_out = false
			mouse_in()
		} else {
			__is_mouse_out = true
			mouse_out()
		}
	}
	glfw_char_proc :: proc "c"  (window: glfw.WindowHandle, codepoint: rune) {
		//TODO (xfitgd)
	}
	glfw_joystick_proc :: proc "c" (joy, event: c.int) {
		//TODO (xfitgd)
	}
	glfw_window_size_proc :: proc "c" (window: glfw.WindowHandle, width, height: c.int) {
		__window_width = int(width)
		__window_height = int(height)

		if loop_start {
			size_updated = true
		}
	}
	glfw_window_pos_proc :: proc "c" (window: glfw.WindowHandle, xpos, ypos: c.int) {
		__window_x = int(xpos)
		__window_y = int(ypos)
	}
	glfw_window_close_proc :: proc "c" (window: glfw.WindowHandle) {
		glfw.SetWindowShouldClose(window, auto_cast closing())
	}
	glfw_window_focus_proc :: proc "c" (window: glfw.WindowHandle, focused: c.int) {
		if focused != 0 {
			sync.atomic_store_explicit(&__paused, false, .Relaxed)
			__activated = true
		} else {
			__activated = false

			for &k in keys {
				k = false
			}
		}
		activate()
	}
	glfw_window_refresh_proc :: proc "c" (window: glfw.WindowHandle) {
		//! no need
		// if !__paused() {
		//     context = runtime.default_context()
		//     vk_draw_frame()
		// }
	}
	glfw.SetKeyCallback(wnd, glfw_key_proc)
	glfw.SetMouseButtonCallback(wnd, glfw_mouse_button_proc)
	glfw.SetCharCallback(wnd, glfw_char_proc)
	glfw.SetCursorPosCallback(wnd, glfw_cursor_pos_proc)
	glfw.SetCursorEnterCallback(wnd, glfw_cursor_enter_proc)
	//glfw.SetJoystickCallback(glfw_joystick_proc)
	glfw.SetWindowCloseCallback(wnd, glfw_window_close_proc)
	glfw.SetWindowFocusCallback(wnd, glfw_window_focus_proc)
	glfw.SetFramebufferSizeCallback(wnd, glfw_window_size_proc)
	glfw.SetWindowPosCallback(wnd, glfw_window_pos_proc)
	//glfw.SetWindowRefreshCallback(wnd, glfw_window_refresh_proc)

	x, y: c.int
	x, y = glfw.GetWindowPos(wnd)
	for !glfw.WindowShouldClose(wnd) {
		glfw.PollEvents()
		render_loop()
	}
	__exiting = true
	wnd = nil
}
glfw_get_window :: proc "contextless" () -> glfw.WindowHandle {
	return wnd
}

}