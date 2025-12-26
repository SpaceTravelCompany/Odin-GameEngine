#+private
package engine 

import "core:sys/android"
import "core:thread"
import "core:sync"
import "core:c"
import "core:sys/posix"
import "core:strings"
import "core:debug/trace"
import "base:intrinsics"
import "base:runtime"
import "core:math/linalg"
import vk "vendor:vulkan"
import graphics_api "./graphics_api"

when is_android {
    @(private="file") app : ^android.android_app
    @(private="file") appInited := false

    //must call start
    __android_SetApp :: proc "contextless" (_app : ^android.android_app) {
        app = _app
    }
 
    android_GetAssetManager :: proc "contextless" () -> ^android.AAssetManager {
        return app.activity.assetManager
    }
    android_GetDeviceWidth :: proc "contextless" () -> u32 {
        return auto_cast max(0, android.ANativeWindow_getWidth(app.window))
    }
    android_GetDeviceHeight :: proc "contextless" () -> u32 {
        return auto_cast max(0, android.ANativeWindow_getHeight(app.window))
    }
    // android_GetCacheDir :: proc "contextless" () -> string {
    //     return app.cacheDir
    // }
    android_GetInternalDataPath :: proc "contextless" () -> string {
        return string(app.activity.internalDataPath)
    }
    android_PrintCurrentConfig :: proc () {
        lang:[2]u8
        country:[2]u8

        android.AConfiguration_getLanguage(app.config, &lang[0])
        android.AConfiguration_getCountry(app.config, &country[0])

        printf("Config: mcc=%d mnc=%d lang=%c%c cnt=%c%c orien=%d touch=%d dens=%d keys=%d nav=%d keysHid=%d navHid=%d sdk=%d size=%d long=%d modetype=%d modenight=%d", 
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
    }

    vulkanAndroidStart :: proc "contextless" () {
        if vkSurface != 0 {
            vk.DestroySurfaceKHR(vkInstance, vkSurface, nil)
        }
        androidSurfaceCreateInfo : vk.AndroidSurfaceCreateInfoKHR = {
            sType = vk.StructureType.ANDROID_SURFACE_CREATE_INFO_KHR,
            window = app.window,
        }
        res := vk.CreateAndroidSurfaceKHR(vkInstance, &androidSurfaceCreateInfo, nil, &vkSurface)
        if res != .SUCCESS {
            trace.panic_log(res)
        }
    }
    @(private="file") inputState:GENERAL_INPUT_STATE

    @(private="file") freeSavedState :: proc "contextless" () {
        //TODO (xfitgd)
    }
    @(private="file") handleInputButtons :: proc (evt : ^android.AInputEvent, keyCode:android.Keycode, upDown:bool) -> bool {
        #partial switch keyCode {
            case .BUTTON_A:
                if upDown && inputState.buttons.a do return false //already set
                inputState.buttons.a = upDown
            case .BUTTON_B:
                if upDown && inputState.buttons.b do return false
                inputState.buttons.b = upDown
            case .BUTTON_X:
                if upDown && inputState.buttons.x do return false
                inputState.buttons.x = upDown
            case .BUTTON_Y:
                if upDown && inputState.buttons.y do return false
                inputState.buttons.y = upDown
            case .BUTTON_START:
                if upDown && inputState.buttons.start do return false
                inputState.buttons.start = upDown
            case .BUTTON_SELECT:
                if upDown && inputState.buttons.back do return false
                inputState.buttons.back = upDown
            case .BUTTON_L1:
                if upDown && inputState.buttons.leftShoulder do return false
                inputState.buttons.leftShoulder = upDown
            case .BUTTON_R1:
                if upDown && inputState.buttons.rightShoulder do return false
                inputState.buttons.rightShoulder = upDown
            case .BUTTON_THUMBL:
                if upDown && inputState.buttons.leftThumb do return false
                inputState.buttons.leftThumb = upDown
            case .BUTTON_THUMBR:
                if upDown && inputState.buttons.rightThumb do return false
                inputState.buttons.rightThumb = upDown
            case .VOLUME_UP:
                if upDown && inputState.buttons.volumeUp do return false
                inputState.buttons.volumeUp = upDown
            case .VOLUME_DOWN:
                if upDown && inputState.buttons.volumeDown do return false
                inputState.buttons.volumeDown = upDown
            case:
                return false
        }

        inputState.handle = transmute(rawptr)(int(android.AInputEvent_getDeviceId(evt)))
        GeneralInputCallBack(inputState)
        return true
    }
    @(private="file") handleInput :: proc "c" (app:^android.android_app, evt : ^android.AInputEvent) -> c.int {
        MAX_POINTERS :: 20
        @static pointer_poses:[MAX_POINTERS]linalg.PointF

        context = runtime.default_context()

        type := android.AInputEvent_getType(evt)
        src := android.AInputEvent_getSource(evt)

        if type == .MOTION {
            toolType := android.AMotionEvent_getToolType(evt, 0)
            //https://github.com/gameplay3d/GamePlay/blob/master/gameplay/src/PlatformAndroid.cpp
            if android.InputSourceDevice.JOYSTICK in transmute(android.InputSourceDevice)(src.device) {
                xAxis := android.AMotionEvent_getAxisValue(evt, android.MotionEventAxis.HAT_X, 0)
                yAxis := android.AMotionEvent_getAxisValue(evt, android.MotionEventAxis.HAT_Y, 0)

                leftTrigger := android.AMotionEvent_getAxisValue(evt, android.MotionEventAxis.BRAKE, 0)
                rightTrigger := android.AMotionEvent_getAxisValue(evt, android.MotionEventAxis.GAS, 0)

                x := android.AMotionEvent_getAxisValue(evt, android.MotionEventAxis.X, 0)
                y := android.AMotionEvent_getAxisValue(evt, android.MotionEventAxis.Y, 0)
                z := android.AMotionEvent_getAxisValue(evt, android.MotionEventAxis.Z, 0)
                rz := android.AMotionEvent_getAxisValue(evt, android.MotionEventAxis.RZ, 0)

                if xAxis == -1.0 {
                    inputState.buttons.dpadLeft = true
                    inputState.buttons.dpadRight = false
                } else if xAxis == 1.0 {
                    inputState.buttons.dpadLeft = false
                    inputState.buttons.dpadRight = true
                } else {
                    inputState.buttons.dpadLeft = false
                    inputState.buttons.dpadRight = false
                }
                if yAxis == -1.0 {
                    inputState.buttons.dpadUp = true
                    inputState.buttons.dpadDown = false
                } else if yAxis == 1.0 {
                    inputState.buttons.dpadUp = false
                    inputState.buttons.dpadDown = true
                } else {
                    inputState.buttons.dpadUp = false
                    inputState.buttons.dpadDown = false
                }

                inputState.leftTrigger = leftTrigger
                inputState.rightTrigger = rightTrigger
                inputState.leftThumb = linalg.PointF{x, y}
                inputState.rightThumb = linalg.PointF{z, rz}

                inputState.handle = transmute(rawptr)(int(android.AInputEvent_getDeviceId(evt)))
                GeneralInputCallBack(inputState)
            } else {
                count:uint
                act := android.AMotionEvent_getAction(evt)

                if toolType == .MOUSE {
                    count = 1
                    mm := linalg.PointF{android.AMotionEvent_getX(evt, 0), android.AMotionEvent_getY(evt, 0)}
                    mm = ConvertMousePos(mm)
                    mouse_pos = mm

                    #partial switch act.action {
                        case .DOWN:
                            isPrimary := android.AMotionEvent_getAxisValue(evt, android.MotionEventAxis.PRESSURE, 0) == 1.0
                            MouseButtonDown(isPrimary ? 0 : 1, mm.x, mm.y)
                        case .UP:
                            isPrimary := android.AMotionEvent_getAxisValue(evt, android.MotionEventAxis.PRESSURE, 0) == 1.0
                            MouseButtonUp(isPrimary ? 0 : 1, mm.x, mm.y)
                        case .SCROLL:
                            //TODO (xfitgd) HSCROLL
                            dt := int(android.AMotionEvent_getAxisValue(evt, android.MotionEventAxis.VSCROLL, 0) * 100.0)
                            MouseScroll(dt)
                        case .MOVE:
                            if mm.x != pointer_poses[0].x || mm.y != pointer_poses[0].y {
                                pointer_poses[0] = mm
                                MouseMove(mm.x, mm.y)
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
                        pt := linalg.PointF{android.AMotionEvent_getX(evt, i), android.AMotionEvent_getY(evt, i)}
                        pt = ConvertMousePos(pt)

                        if pt.x != pointer_poses[i].x || pt.y != pointer_poses[i].y {
                            pointer_poses[i] = pt
                            if i == 0 {
                                mouse_pos = pt
                            }
                            PointerMove(int(i), pt.x, pt.y)
                        }
                    }
                } else {
                    for i in 0 ..< count {
                        pointer_poses[i] = linalg.PointF{android.AMotionEvent_getX(evt, i), android.AMotionEvent_getY(evt, i)}
                        pointer_poses[i] = ConvertMousePos(pointer_poses[i])
                    }
                    mouse_pos = pointer_poses[0]
                }

                #partial switch act.action {
                    case .DOWN:
                        PointerDown(0, pointer_poses[0].x, pointer_poses[0].y)
                    case .UP:
                        PointerUp(0, pointer_poses[0].x, pointer_poses[0].y)
                    case .POINTER_DOWN:
                        idx := act.pointer_index
                        if auto_cast idx < count {
                            PointerDown(auto_cast idx, pointer_poses[idx].x, pointer_poses[idx].y)
                        } else {
                            printCustomAndroid("WARN OUT OF RANGE PointerDown:", idx, count, "\n", logPriority=.WARN)
                        }
                    case .POINTER_UP:
                        idx := act.pointer_index
                        if auto_cast idx < count {
                            PointerUp(auto_cast idx, pointer_poses[idx].x, pointer_poses[idx].y)
                        } else {
                            printCustomAndroid("WARN OUT OF RANGE PointerUp:", idx, count, "\n", logPriority=.WARN)
                        }
                }
                return 1
            }
        } else if type == .KEY {
            keyCode := android.AKeyEvent_getKeyCode(evt)
            act := android.AKeyEvent_getAction(evt)

            switch act {
                case .DOWN:
                    if .JOYSTICK in transmute(android.InputSourceDevice)(src.device) || .GAMEPAD in transmute(android.InputSourceDevice)(src.device) {
                        if handleInputButtons(evt, keyCode, true) do return 1
                    }
                    if int(keyCode) < KEY_SIZE {
                        if !keys[int(keyCode)] {
                            keys[int(keyCode)] = true
                            KeyDown(transmute(KeyCode)(keyCode))
                        }
                    } else {
                        printCustomAndroid("WARN OUT OF RANGE KeyDown: ", int(keyCode), "\n", logPriority=.WARN, sep = "")
                        return 0
                    }
                case .UP:
                    if .JOYSTICK in transmute(android.InputSourceDevice)(src.device) || .GAMEPAD in transmute(android.InputSourceDevice)(src.device) {
                        if handleInputButtons(evt, keyCode, false) do return 1
                    }
                    if int(keyCode) < KEY_SIZE {
                        keys[int(keyCode)] = false
                        KeyUp(transmute(KeyCode)(keyCode))
                    } else {
                        printCustomAndroid("WARN OUT OF RANGE KeyUp: ", int(keyCode), "\n", logPriority=.WARN, sep = "")
                        return 0
                    }
                case .MULTIPLE:
                    if int(keyCode) < KEY_SIZE {
                        cnt := android.AKeyEvent_getRepeatCount(evt)
                        for i in 0 ..< cnt {
                            KeyDown(transmute(KeyCode)(keyCode))
                            KeyUp(transmute(KeyCode)(keyCode))
                        }
                    } else {
                        printCustomAndroid("WARN OUT OF RANGE Key Multiple: ", int(keyCode), "\n", logPriority=.WARN, sep = "")
                        return 0
                    }
            }
        } else {
            //TODO (xfitgd)
        }
        return 0
    }
    @(private="file") handleCmd :: proc "c" (app:^android.android_app, cmd : android.AppCmd) {
        #partial switch cmd {
            case .SAVE_STATE:
                //TODO (xfitgd)
            case .INIT_WINDOW:
                if app.window != nil {
                    if !appInited {
                        context = runtime.default_context()
                        graphics_api.graphics_init()

                        __windowWidth = int(vkExtent.width)
		                __windowHeight = int(vkExtent.height)

		                Init()
                        appInited = true
                    } else {
                        sizeUpdated = true
                    }
                }
            case .TERM_WINDOW:
                //EMPTY
            case .GAINED_FOCUS:
                paused = false
                activated = false
                Activate()
            case .LOST_FOCUS:
                paused = true
                activated = true
                Activate()
            case .WINDOW_RESIZED:
                sync.mutex_lock(&fullScreenMtx)
                defer sync.mutex_unlock(&fullScreenMtx)

                prop : vk.SurfaceCapabilitiesKHR
                res := vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(vkPhysicalDevice, vkSurface, &prop)
                if res != .SUCCESS do trace.panic_log(res)
                if prop.currentExtent.width != vkExtent.width || prop.currentExtent.height != vkExtent.height {
                    sizeUpdated = true
                }
        }
    }

    androidStart :: proc () {
        app.userData = nil
        app.onAppCmd = handleCmd
        app.onInputEvent = handleInput

        for {
            events: i32
            source: ^android.android_poll_source

            ident := android.ALooper_pollAll(!paused ? 0 : -1, nil, &events, cast(^rawptr)&source)
            for ident >= 0 {
                if source != nil {
                    source.process(app, source)
                }

                if app.destroyRequested != 0 {
                    graphics_api.graphics_wait_device_idle()
                    Destroy()
                    graphics_api.graphics_destroy()
                    systemDestroy()
                    systemAfterDestroy()
                    return
                }

                ident = android.ALooper_pollAll(!paused ? 0 : -1, nil, &events, cast(^rawptr)&source)
            }

            if (!paused && appInited) {
                RenderLoop()
            }
        }
    }
}