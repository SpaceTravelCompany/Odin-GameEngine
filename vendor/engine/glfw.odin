#+private
package engine

import "vendor:glfw"
import "core:reflect"
import "core:c"
import "core:mem"
import "core:sync"
import "core:debug/trace"
import "core:os"
import "core:sys/linux"
import "core:sys/posix"
import "core:sys/windows"
import "core:strings"
import "core:bytes"
import "core:thread"
import "base:runtime"
import "base:intrinsics"
import vk "vendor:vulkan"
import "core:fmt"

when !is_mobile {

@(private="file") wnd:glfw.WindowHandle = nil
@(private="file") glfwMonitors:[dynamic]glfw.MonitorHandle


glfwStart :: proc() {
    //?default screen idx 0
    if __windowWidth == nil do __windowWidth = int(monitors[0].rect.size.x / 2)
	if __windowHeight == nil do __windowHeight = int(monitors[0].rect.size.y / 2)
	if __windowX == nil do __windowX = int(monitors[0].rect.pos.x + monitors[0].rect.size.x / 4)
	if __windowY == nil do __windowY = int(monitors[0].rect.pos.y + monitors[0].rect.size.y / 4)

    SavePrevWindow()

    //? change use glfw.SetWindowAttrib()
    if __screenMode ==.Borderless {
        glfw.WindowHint (glfw.DECORATED, glfw.FALSE)
        glfw.WindowHint(glfw.FLOATING, glfw.TRUE)

        wnd = glfw.CreateWindow(monitors[__screenIdx].rect.size.x,
            monitors[__screenIdx].rect.size.y,
            __windowTitle,
            nil,
            nil)

        glfw.SetWindowPos(wnd, monitors[__screenIdx].rect.pos.x, monitors[__screenIdx].rect.pos.y)
        glfw.SetWindowSize(wnd, monitors[__screenIdx].rect.size.x, monitors[__screenIdx].rect.size.y)
    } else if __screenMode == .Fullscreen {
        wnd = glfw.CreateWindow(monitors[__screenIdx].rect.size.x,
            monitors[__screenIdx].rect.size.y,
            __windowTitle,
            glfwMonitors[__screenIdx],
            nil)
    } else {
        wnd = glfw.CreateWindow(auto_cast __windowWidth.?,
            auto_cast __windowHeight.?,
            __windowTitle,
            nil,
            nil)

        glfw.SetWindowPos(wnd, auto_cast __windowX.?, auto_cast __windowY.?)
    }

    //CreateRenderFuncThread()
}

when ODIN_OS == .Windows {
glfwGetCurrentHMONITOR :: proc "contextless" () -> windows.HMONITOR {
    if wnd == nil do trace.panic_log("glfwGetCurrentHMONITOR : wnd is nil")
    hWnd := glfw.GetWin32Window(wnd)
    if hWnd == nil do trace.panic_log("glfwGetCurrentHMONITOR : hWnd is nil")

    return windows.MonitorFromWindow(hWnd, windows.Monitor_From_Flags.MONITOR_DEFAULTTONEAREST)
}   
}

glfwSetFullScreenMode :: proc "contextless" (monitor:^MonitorInfo) {
    for &m, i in monitors {
        if raw_data(m.name) == raw_data(monitor.name) {
            glfw.SetWindowMonitor(wnd, glfwMonitors[i], monitor.rect.pos.x,
                 monitor.rect.pos.y,
                monitor.rect.size.x,
                monitor.rect.size.y,
                glfw.DONT_CARE)
            return
        }
    }
}

glfwSetWindowIcon :: #force_inline  proc "contextless" (icons:[]Icon_Image) {
    glfw.SetWindowIcon(wnd, auto_cast icons)
}

glfwSetBorderlessScreenMode :: proc "contextless" (monitor:^MonitorInfo) {
    glfw.SetWindowMonitor(wnd, nil, monitor.rect.pos.x,
        monitor.rect.pos.y,
       monitor.rect.size.x,
       monitor.rect.size.y,
       glfw.DONT_CARE)
}

glfwSetWindowMode :: proc "contextless" () {
    glfw.SetWindowMonitor(wnd, nil, auto_cast prevWindowX,
        auto_cast prevWindowY,
        auto_cast prevWindowWidth,
        auto_cast prevWindowHeight,
       glfw.DONT_CARE)
}

glfwVulkanStart :: proc "contextless" () {
    if vkSurface != 0 do vk.DestroySurfaceKHR(vkInstance, vkSurface, nil)

    res := glfw.CreateWindowSurface(vkInstance, wnd, nil, &vkSurface)
    if (res != .SUCCESS) do trace.panic_log("glfwVulkanStart : ", res)
}

@(private="file") glfwInitMonitors :: proc() {
    glfwMonitors = mem.make_non_zeroed([dynamic]glfw.MonitorHandle)
    _monitors := glfw.GetMonitors()

    for m in _monitors {
        glfwAppendMonitor(m)
    }
}

@(private="file") glfwAppendMonitor :: proc(m:glfw.MonitorHandle) {
    info:MonitorInfo
    info.name = glfw.GetMonitorName(m)
    info.rect.pos.x, info.rect.pos.y, info.rect.size.x, info.rect.size.y = glfw.GetMonitorWorkarea(m)
    info.isPrimary = m == glfw.GetPrimaryMonitor()

    vidMode :^glfw.VidMode = glfw.GetVideoMode(m)
    info.refreshRate = auto_cast vidMode.refresh_rate

    when is_log {
        printf(
            "XFIT SYSLOG : ADD %s monitor name: %s, x:%d, y:%d, size.x:%d, size.y:%d, refleshrate%d\n",
            "primary" if info.isPrimary else "",
            info.name,
            info.rect.pos.x,
            info.rect.pos.y,
            info.rect.size.x,
            info.rect.size.y,
            info.refreshRate,
        )
    }

    non_zero_append(&monitors, info)
    non_zero_append(&glfwMonitors, m)
}

glfwSystemInit :: proc() {
    res := glfw.Init()
    if !res do trace.panic_log("glfw.Init : ", res)

    when ODIN_OS == .Linux {
        name:linux.UTS_Name
		err := linux.uname(&name)
        if err != .NONE do trace.panic_log("linux.uname : ", err)

        linuxPlatform.sysName = strings.clone_from_ptr(&name.sysname[0], bytes.index_byte(name.sysname[:], 0))
        linuxPlatform.nodeName = strings.clone_from_ptr(&name.nodename[0], bytes.index_byte(name.nodename[:], 0))
        linuxPlatform.machine = strings.clone_from_ptr(&name.machine[0], bytes.index_byte(name.machine[:], 0))
        linuxPlatform.release = strings.clone_from_ptr(&name.release[0], bytes.index_byte(name.release[:], 0))
        linuxPlatform.version = strings.clone_from_ptr(&name.version[0], bytes.index_byte(name.version[:], 0))
        when is_log {
            println("XFIT SYSLOG : ", linuxPlatform)
        }
       
        processorCoreLen = auto_cast os._unix_get_nprocs()
        when is_log {
            println("XFIT SYSLOG processorCoreLen : ", processorCoreLen)
        }
        if processorCoreLen == 0 do trace.panic_log("processorCoreLen can't zero")
	} else when ODIN_OS == .Windows {
		//TODO (xfitgd)
	}

    

    when is_log do glfw.SetErrorCallback(glfwErrorCallback)
}

glfwErrorCallback :: proc "c" (error: c.int, description: cstring) {
    when is_log {
        context = runtime.default_context()
        println("XFIT SYSLOG : glfw", error, description)
    }
}

glfwSystemStart :: proc() {
    glfwMonitorProc :: proc "c" (monitor: glfw.MonitorHandle, event: c.int) {
        sync.mutex_lock(&monitorsMtx)
        defer sync.mutex_unlock(&monitorsMtx)
        
        context = runtime.default_context() 
        if event == glfw.CONNECTED {
            glfwAppendMonitor(monitor)
        } else if event == glfw.DISCONNECTED {
            for m, i in glfwMonitors {
                if m == monitor {
                    when is_log {
                        printf(
                            "XFIT SYSLOG : DEL %s monitor name: %s, x:%d, y:%d, size.x:%d, size.y:%d, refleshrate%d\n",
                            "primary" if monitors[i].isPrimary else "",
                            monitors[i].name,
                            monitors[i].rect.pos.x,
                            monitors[i].rect.pos.y,
                            monitors[i].rect.size.x,
                            monitors[i].rect.size.y,
                            monitors[i].refreshRate,
                        )
                    }
                    ordered_remove(&glfwMonitors, i)
                    ordered_remove(&monitors, i)
                    break
                }
            }
        }
    }
    //Unless you will be using OpenGL or OpenGL ES with the same window as Vulkan, there is no need to create a context. You can disable context creation with the GLFW_CLIENT_API hint.
    glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)

    glfwInitMonitors()
    glfw.SetMonitorCallback(glfwMonitorProc)
}

glfwDestroy :: proc() {
    if wnd != nil do glfw.DestroyWindow(wnd)
    wnd = nil
}


glfwSystemDestroy :: proc() {
    delete(glfwMonitors)

    when ODIN_OS == .Linux {
        delete(linuxPlatform.sysName)
        delete(linuxPlatform.nodeName)
        delete(linuxPlatform.machine)
        delete(linuxPlatform.release)
        delete(linuxPlatform.version)
	} else when ODIN_OS == .Windows {
		//TODO (xfitgd)
	}
  
    glfw.Terminate()
}

glfwLoop :: proc() {
    glfwKeyProc :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: c.int) {
        //glfw.KEY_SPACE
        if key > KEY_SIZE-1 || key < 0 || !reflect.is_valid_enum_value(KeyCode, key) {
            return
        }
        switch action {
            case glfw.PRESS:
                if !keys[key] {
                    keys[key] = true
                    KeyDown(KeyCode(key))
                }
            case glfw.RELEASE:
                keys[key] = false
                KeyUp(KeyCode(key))
            case glfw.REPEAT:
                KeyRepeat(KeyCode(key))
        }
    }
    glfwMouseButtonProc :: proc "c" (window: glfw.WindowHandle, button, action, mods: c.int) {
        switch action {
            case glfw.PRESS:
                MouseButtonDown(auto_cast button)
            case glfw.RELEASE:
                MouseButtonUp(auto_cast button)
        }
    }
    glfwCursorPosProc :: proc "c" (window: glfw.WindowHandle, xpos,  ypos: f64) {
        MouseMove(xpos, ypos)
    }
    glfwCursorEnterProc :: proc "c" (window: glfw.WindowHandle, entered: c.int) {
        if b32(entered) {
            isMouseOut = false
            MouseIn()
        } else {
            isMouseOut = true
            MouseOut()
        }
    }
    glfwCharProc :: proc "c"  (window: glfw.WindowHandle, codepoint: rune) {
        //TODO (xfitgd)
    }
    glfwJoystickProc :: proc "c" (joy, event: c.int) {
        //TODO (xfitgd)
    }
    glfwWindowSizeProc :: proc "c" (window: glfw.WindowHandle, width, height: c.int) {
        __windowWidth = int(width)
        __windowHeight = int(height)

        if loopStart {
            sizeUpdated = true
        }
    }
    glfwWindowPosProc :: proc "c" (window: glfw.WindowHandle, xpos, ypos: c.int) {
        __windowX = int(xpos)
        __windowY = int(ypos)
    }
    glfwWindowCloseProc :: proc "c" (window: glfw.WindowHandle) {
        glfw.SetWindowShouldClose(window, auto_cast Close())
    }
    glfwWindowFocusProc :: proc "c" (window: glfw.WindowHandle, focused: c.int) {
        if focused != 0 {
            sync.atomic_store_explicit(&paused, false, .Relaxed)
            activated = true
        } else {
            activated = false

            for &k in keys {
                k = false
            }
        }
        Activate()
    }
    glfwWindowRefreshProc :: proc "c" (window: glfw.WindowHandle) {
        //! no need
        // if !Paused() {
        //     context = runtime.default_context()
        //     vkDrawFrame()
        // }
    }
    glfw.SetKeyCallback(wnd, glfwKeyProc)
    glfw.SetMouseButtonCallback(wnd, glfwMouseButtonProc)
    glfw.SetCharCallback(wnd, glfwCharProc)
    glfw.SetCursorPosCallback(wnd, glfwCursorPosProc)
    glfw.SetCursorEnterCallback(wnd, glfwCursorEnterProc)
    glfw.SetJoystickCallback(glfwJoystickProc)
    glfw.SetWindowCloseCallback(wnd, glfwWindowCloseProc)
    glfw.SetWindowFocusCallback(wnd, glfwWindowFocusProc)
    glfw.SetFramebufferSizeCallback(wnd, glfwWindowSizeProc)
    glfw.SetWindowPosCallback(wnd, glfwWindowPosProc)
    glfw.SetWindowRefreshCallback(wnd, glfwWindowRefreshProc)

    x, y: c.int
    x, y = glfw.GetWindowPos(wnd)
    for !glfw.WindowShouldClose(wnd) {
        glfw.PollEvents()
        RenderLoop()
    }
    exiting = true
   // thread.join(render_th)
}

}