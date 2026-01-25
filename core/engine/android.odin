package engine

import "base:intrinsics"
import "base:library"
import "base:runtime"
import "core:c"
import "core:mem"
import "core:c/libc"
import "core:debug/trace"
import "core:fmt"
import "core:math/linalg"
import "core:strings"
import "core:sync"
import "core:sys/android"
import "core:sys/posix"
import "core:thread"
import vk "vendor:vulkan"
import "vendor:android_cpu_features"

when library.is_android {
    @(private="file") app : ^android.android_app
    @(private="file") app_inited := false
    @(private="file") input_state:general_input_state
}
    
/*
Gets the Android asset manager

Returns:
- Pointer to the Android asset manager
*/
android_get_asset_manager :: proc "contextless" () -> ^android.AAssetManager {
	when library.is_android {
		return app.activity.assetManager
	} else {
		trace.panic_log("android_get_asset_manager is not available on this platform")
	}
}

/*
Gets the device width in pixels

Returns:
- Device width in pixels
*/
android_get_device_width :: proc "contextless" () -> u32 {
	when library.is_android {
		return auto_cast max(0, android.ANativeWindow_getWidth(app.window))
	} else {
		trace.panic_log("android_get_device_width is not available on this platform")
	}
}

/*
Gets the device height in pixels

Returns:
- Device height in pixels
*/
android_get_device_height :: proc "contextless" () -> u32 {
	when library.is_android {
		return auto_cast max(0, android.ANativeWindow_getHeight(app.window))
	} else {
		trace.panic_log("android_get_device_height is not available on this platform")
	}
}

// android_get_cache_dir :: proc "contextless" () -> string {
//     return app.cacheDir
// }

/*
Gets the internal data path for the Android app

Returns:
- Internal data path as a string
*/
android_get_internal_data_path :: proc "contextless" () -> string {
	when library.is_android {
		return string(app.activity.internalDataPath)
	} else {
		trace.panic_log("android_get_internal_data_path is not available on this platform")
	}
}

android_print_current_config :: proc () {
	when library.is_android {
		lang:[2]u8
		country:[2]u8

		android.AConfiguration_getLanguage(app.config, &lang[0])
		android.AConfiguration_getCountry(app.config, &country[0])

		fmt.printf("Config: mcc=%d mnc=%d lang=%c%c cnt=%c%c orien=%d touch=%d dens=%d keys=%d nav=%d keysHid=%d navHid=%d sdk=%d size=%d long=%d modetype=%d modenight=%d", 
			android.AConfiguration_getMcc(app.config),
			android.AConfiguration_getMnc(app.config),
			lang[0],
			lang[1],
			country[0],
			country[1],
			android.AConfiguration_getOrientation(app.config),
			android.AConfiguration_getTouchscreen(app.config),
			android.AConfiguration_getDensity(app.config),
			android.AConfiguration_getKeyboard(app.config),
			android.AConfiguration_getNavigation(app.config),
			android.AConfiguration_getKeysHidden(app.config),
			android.AConfiguration_getNavHidden(app.config),
			android.AConfiguration_getSdkVersion(app.config),
			android.AConfiguration_getScreenSize(app.config),
			android.AConfiguration_getScreenLong(app.config),
			android.AConfiguration_getUiModeType(app.config),
			android.AConfiguration_getUiModeNight(app.config),
		)
	} else {
		trace.panic_log("android_print_current_config is not available on this platform")
	}
}

when library.is_android {
	@private print_android :: proc "contextless" (args: ..any, sep := " ", flush := true) -> i32 {
		_ = flush
		context = runtime.Context {
			allocator = runtime.heap_allocator(),
		}
		cstr := fmt.caprint(..args, sep=sep)
		defer delete(cstr)
		
		return android.__android_log_write(android.LogPriority.INFO, ODIN_BUILD_PROJECT_NAME, cstr)
	}
	@private android_close :: #force_inline proc "contextless" () {
		app.destroyRequested = 1
	}

	@private vulkan_android_start :: proc "contextless" () {
		if vk_surface != 0 {
			vk.DestroySurfaceKHR(vk_instance, vk_surface, nil)
		}
		android_surface_create_info : vk.AndroidSurfaceCreateInfoKHR = {
			sType = vk.StructureType.ANDROID_SURFACE_CREATE_INFO_KHR,
			window = app.window,
		}
		res := vk.CreateAndroidSurfaceKHR(vk_instance, &android_surface_create_info, nil, &vk_surface)
		if res != .SUCCESS {
			trace.panic_log(res)
		}
	}

	@(private="file") free_saved_state :: proc "contextless" () {
		//TODO (xfitgd)
	}
	@(private="file") handle_input_buttons :: proc (evt : ^android.AInputEvent, key_code_:android.Keycode, up_down:bool) -> bool {
		#partial switch key_code_ {
			case .BUTTON_A:
				if up_down && input_state.buttons.a do return false //already set
				input_state.buttons.a = up_down
			case .BUTTON_B:
				if up_down && input_state.buttons.b do return false
				input_state.buttons.b = up_down
			case .BUTTON_X:
				if up_down && input_state.buttons.x do return false
				input_state.buttons.x = up_down
			case .BUTTON_Y:
				if up_down && input_state.buttons.y do return false
				input_state.buttons.y = up_down
			case .BUTTON_START:
				if up_down && input_state.buttons.start do return false
				input_state.buttons.start = up_down
			case .BUTTON_SELECT:
				if up_down && input_state.buttons.back do return false
				input_state.buttons.back = up_down
			case .BUTTON_L1:
				if up_down && input_state.buttons.left_shoulder do return false
				input_state.buttons.left_shoulder = up_down
			case .BUTTON_R1:
				if up_down && input_state.buttons.right_shoulder do return false
				input_state.buttons.right_shoulder = up_down
			case .BUTTON_THUMBL:
				if up_down && input_state.buttons.left_thumb do return false
				input_state.buttons.left_thumb = up_down
			case .BUTTON_THUMBR:
				if up_down && input_state.buttons.right_thumb do return false
				input_state.buttons.right_thumb = up_down
			case .VOLUME_UP:
				if up_down && input_state.buttons.volume_up do return false
				input_state.buttons.volume_up = up_down
			case .VOLUME_DOWN:
				if up_down && input_state.buttons.volume_down do return false
				input_state.buttons.volume_down = up_down
			case:
				return false
		}

		input_state.handle = transmute(rawptr)(int(android.AInputEvent_getDeviceId(evt)))
		if general_input_callback != nil do general_input_callback(input_state)
		return true
	}

	@(private="file") handle_input :: proc "c" (app:^android.android_app, evt : ^android.AInputEvent) -> c.int {
		context = runtime.default_context()

		MAX_POINTERS :: 20
		@static pointer_poses:[MAX_POINTERS]linalg.point

		type := android.AInputEvent_getType(evt)
		src := android.AInputEvent_getSource(evt)

		if type == .MOTION {
			toolType := android.AMotionEvent_getToolType(evt, 0)
			//https://github.com/gameplay3d/GamePlay/blob/master/gameplay/src/PlatformAndroid.cpp
			if android.InputSourceDevice.JOYSTICK in transmute(android.InputSourceDevice)(src.device) {
				if general_input_callback != nil {
					xAxis := android.AMotionEvent_getAxisValue(evt, android.MotionEventAxis.HAT_X, 0)
					yAxis := android.AMotionEvent_getAxisValue(evt, android.MotionEventAxis.HAT_Y, 0)

					leftTrigger := android.AMotionEvent_getAxisValue(evt, android.MotionEventAxis.BRAKE, 0)
					rightTrigger := android.AMotionEvent_getAxisValue(evt, android.MotionEventAxis.GAS, 0)

					x := android.AMotionEvent_getAxisValue(evt, android.MotionEventAxis.X, 0)
					y := android.AMotionEvent_getAxisValue(evt, android.MotionEventAxis.Y, 0)
					z := android.AMotionEvent_getAxisValue(evt, android.MotionEventAxis.Z, 0)
					rz := android.AMotionEvent_getAxisValue(evt, android.MotionEventAxis.RZ, 0)

					if xAxis == -1.0 {
						input_state.buttons.dpad_left = true
						input_state.buttons.dpad_right = false
					} else if xAxis == 1.0 {
						input_state.buttons.dpad_left = false
						input_state.buttons.dpad_right = true
					} else {
						input_state.buttons.dpad_left = false
						input_state.buttons.dpad_right = false
					}
					if yAxis == -1.0 {
						input_state.buttons.dpad_up = true
						input_state.buttons.dpad_down = false
					} else if yAxis == 1.0 {
						input_state.buttons.dpad_up = false
						input_state.buttons.dpad_down = true
					} else {
						input_state.buttons.dpad_up = false
						input_state.buttons.dpad_down = false
					}

					input_state.left_trigger = leftTrigger
					input_state.right_trigger = rightTrigger
					input_state.left_thumb = linalg.point{x, y}
					input_state.right_thumb = linalg.point{z, rz}

					input_state.handle = transmute(rawptr)(int(android.AInputEvent_getDeviceId(evt)))
					general_input_callback(input_state)
				}
			} else {
				count:uint
				act := android.AMotionEvent_getAction(evt)

				if toolType == .MOUSE {
					count = 1
					mm := linalg.point{android.AMotionEvent_getX(evt, 0), android.AMotionEvent_getY(evt, 0)}
					//mm = convert_mouse_pos(mm) //no need to convert anymore
					__mouse_pos = mm

					#partial switch act.action {
						case .DOWN:
							is_primary := android.AMotionEvent_getAxisValue(evt, android.MotionEventAxis.PRESSURE, 0) == 1.0
							mouse_button_down(is_primary ? .LEFT : .RIGHT, mm.x, mm.y)
						case .UP:
							is_primary := android.AMotionEvent_getAxisValue(evt, android.MotionEventAxis.PRESSURE, 0) == 1.0
							mouse_button_up(is_primary ? .LEFT : .RIGHT, mm.x, mm.y)
						case .SCROLL:
							//TODO (xfitgd) HSCROLL
							dt := int(android.AMotionEvent_getAxisValue(evt, android.MotionEventAxis.VSCROLL, 0) * 100.0)
							mouse_scroll(dt)
						case .MOVE:
							if mm.x != pointer_poses[0].x || mm.y != pointer_poses[0].y {
								pointer_poses[0] = mm
								mouse_move(mm.x, mm.y)
							}
					}
					return 1
				} else if toolType == .FINGER {
					count = min(uint(MAX_POINTERS), android.AMotionEvent_getPointerCount(evt))
				} else {
					return 0
				}

				if act.action == .MOVE {
					for i in 0 ..< count {
						pt := linalg.point{android.AMotionEvent_getX(evt, i), android.AMotionEvent_getY(evt, i)}
						//pt = convert_mouse_pos(pt) //no need to convert anymore

						if pt.x != pointer_poses[i].x || pt.y != pointer_poses[i].y {
							pointer_poses[i] = pt
							if i == 0 {
								__mouse_pos = pt
							}
							pointer_move(u8(i), pt.x, pt.y)
						}
					}
				} else {
					for i in 0 ..< count {
						pointer_poses[i] = linalg.point{android.AMotionEvent_getX(evt, i), android.AMotionEvent_getY(evt, i)}
						//pointer_poses[i] = convert_mouse_pos(pointer_poses[i]) //no need to convert anymore
					}
					__mouse_pos = pointer_poses[0]
				}

				#partial switch act.action {
					case .DOWN:
						pointer_down(0, pointer_poses[0].x, pointer_poses[0].y)
					case .UP:
						pointer_up(0, pointer_poses[0].x, pointer_poses[0].y)
					case .POINTER_DOWN:
						idx := act.pointer_index
						if auto_cast idx < count {
							pointer_down(u8(idx), pointer_poses[idx].x, pointer_poses[idx].y)
						} else {
							print_android("WARN OUT OF RANGE PointerDown:", idx, count, "\n", sep = "")
						}
					case .POINTER_UP:
						idx := act.pointer_index
						if auto_cast idx < count {
							pointer_up(u8(idx), pointer_poses[idx].x, pointer_poses[idx].y)
						} else {
							print_android("WARN OUT OF RANGE PointerUp:", idx, count, "\n", sep = "")
						}
				}
				return 1
			}
		} else if type == .KEY {
			key_code_ := android.AKeyEvent_getKeyCode(evt)
			act := android.AKeyEvent_getAction(evt)

			switch act {
				case .DOWN:
					if .JOYSTICK in transmute(android.InputSourceDevice)(src.device) || .GAMEPAD in transmute(android.InputSourceDevice)(src.device) {
						if handle_input_buttons(evt, key_code_, true) do return 1
					}
					if int(key_code_) < key_size {
						if !keys[int(key_code_)] {
							keys[int(key_code_)] = true
							key_down(transmute(key_code)(key_code_))
						}
					} else {
						print_android("WARN OUT OF RANGE KeyDown: ", int(key_code_), "\n", sep = "")
						return 0
					}
					if key_code_ == .BACK do return 1 // 뒤로가기 버튼 비활성화
				case .UP:
					if .JOYSTICK in transmute(android.InputSourceDevice)(src.device) || .GAMEPAD in transmute(android.InputSourceDevice)(src.device) {
						if handle_input_buttons(evt, key_code_, false) do return 1
					}
					if int(key_code_) < key_size {
						keys[int(key_code_)] = false
						key_up(transmute(key_code)(key_code_))
					} else {
						print_android("WARN OUT OF RANGE KeyUp: ", int(key_code_), "\n", sep = "")
						return 0
					}
					if key_code_ == .BACK do return 1 // 뒤로가기 버튼 비활성화
				case .MULTIPLE:
					if int(key_code_) < key_size {
						cnt := android.AKeyEvent_getRepeatCount(evt)
						for i in 0 ..< cnt {
							key_down(transmute(key_code)(key_code_))
							key_up(transmute(key_code)(key_code_))
						}
					} else {
						print_android("WARN OUT OF RANGE Key Multiple: ", int(key_code_), "\n", sep = "")
						return 0
					}
					if key_code_ == .BACK do return 1 // 뒤로가기 버튼 비활성화
			}
		} else {
			//TODO (xfitgd)
		}
		return 0
	}


	@(private="file") handle_cmd :: proc "c" (app:^android.android_app, cmd : android.AppCmd) {
		#partial switch cmd {
			case .SAVE_STATE:
				//TODO (xfitgd)
			case .INIT_WINDOW:
				if app.window != nil {
					if !app_inited {
						context = runtime.default_context()
						graphics_init()

						__window_width = int(vk_extent.width)
						__window_height = int(vk_extent.height)

						init()
						app_inited = true
					} else {
						size_updated = true
					}
				}
			case .TERM_WINDOW:
				//EMPTY
			case .GAINED_FOCUS:
				__paused = false
				__activated = false
				activate()
			case .LOST_FOCUS:
				__paused = true
				__activated = true
				activate()
			case .WINDOW_RESIZED:
				sync.mutex_lock(&full_screen_mtx)
				defer sync.mutex_unlock(&full_screen_mtx)

				prop : vk.SurfaceCapabilitiesKHR
				res := vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(vk_physical_device, vk_surface, &prop)
				if res != .SUCCESS do trace.panic_log(res)
				if prop.currentExtent.width != vk_extent.width || prop.currentExtent.height != vk_extent.height {
					size_updated = true
				}
		}
	}

	@private android_start :: proc () {
		// Set CPU core count for Android
		core_count := android_cpu_features.android_getCpuCount()
		processor_core_len = auto_cast core_count
		if processor_core_len == 0 do trace.panic_log("processor_core_len can't zero")
		
		app = auto_cast android.get_android_app()
		app.userData = nil
		app.onAppCmd = handle_cmd
		app.onInputEvent = handle_input

		for {
			events: i32
			source: ^android.android_poll_source

			ident := android.ALooper_pollAll(!__paused ? 0 : -1, nil, &events, cast(^rawptr)&source)
			for ident >= 0 {
				if source != nil {
					source.process(app, source)
				}

				if app.destroyRequested != 0 {
					if !closing() {
						app.destroyRequested = 0
					} else {
						graphics_wait_device_idle()
						destroy()
						graphics_destroy()
						system_destroy()
						system_after_destroy()

						libc.exit(0)
						//return
					}
				}

				ident = android.ALooper_pollAll(!__paused ? 0 : -1, nil, &events, cast(^rawptr)&source)
			}

			if (!__paused && app_inited) {
				render_loop()
			}
		}
	}
}