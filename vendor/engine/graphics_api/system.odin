package graphics_api

import "base:library"
import "../"

import "core:sync"

when library.is_android {
	androidPlatform:engine.AndroidPlatformVersion
} else when ODIN_OS == .Linux {
	linuxPlatform:engine.LinuxPlatformVersion
} else when ODIN_OS == .Windows {
	windowsPlatform:engine.WindowsPlatformVersion
}

@private main_thread_id:int

is_main_thread :: #force_inline proc "contextless" () -> bool {
	return sync.current_thread_id() == main_thread_id
}