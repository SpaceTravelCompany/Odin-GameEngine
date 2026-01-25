#+build windows
package engine

import "core:math/linalg"
import "core:mem"
import "base:runtime"
import "core:sync"
import "vendor:windows/GameInput"

@(private = "file") game_input: ^GameInput.IGameInput
@(private = "file") reading_callback_token: GameInput.CallbackToken
@(private = "file") device_callback_token: GameInput.CallbackToken
@(private = "file") connected_devices: [dynamic]^GameInput.IGameInputDevice
@(private = "file") devices_mtx:sync.Mutex

// Device callback function
@(private = "file")
device_callback :: proc "stdcall" (token: GameInput.CallbackToken, ctx: rawptr, device: ^GameInput.IGameInputDevice, timestamp: u64, currentStatus: GameInput.DeviceStatus, previousStatus: GameInput.DeviceStatus) {
	context = runtime.default_context()

	if device == nil do return

	//was_connected := .Connected in previousStatus
	is_connected := .Connected in currentStatus

	if is_connected {
		sync.mutex_lock(&devices_mtx)
		append(&connected_devices, device)
		sync.mutex_unlock(&devices_mtx)
		
		if general_input_change_callback != nil {
			general_input_change_callback(rawptr(device), true)
		}
	} else if !is_connected {
		for d, i in connected_devices {
			if d == device {
				sync.mutex_lock(&devices_mtx)
				unordered_remove(&connected_devices, i)
				sync.mutex_unlock(&devices_mtx)
				
				if general_input_change_callback != nil {
					general_input_change_callback(rawptr(device), false)
				}
				break
			}
		}
	}
}


@(private = "file")
reading_callback :: proc "stdcall" (token: GameInput.CallbackToken, ctx: rawptr, reading: ^GameInput.IGameInputReading, hasOverrunOccured: bool) {
	if reading == nil do return
	if general_input_callback == nil do return

	context = runtime.default_context()

	device: ^GameInput.IGameInputDevice
	reading->GetDevice(&device)
	if device == nil do return

	gamepad_state: GameInput.GamepadState
	success := reading->GetGamepadState(&gamepad_state)
	if !success do return

	// Convert to general_input_state
	current_buttons := general_input_buttons {
		a = .A in gamepad_state.buttons,
		b = .B in gamepad_state.buttons,
		x = .X in gamepad_state.buttons,
		y = .Y in gamepad_state.buttons,
		dpad_up = .DPadUp in gamepad_state.buttons,
		dpad_down = .DPadDown in gamepad_state.buttons,
		dpad_left = .DPadLeft in gamepad_state.buttons,
		dpad_right = .DPadRight in gamepad_state.buttons,
		start = .Menu in gamepad_state.buttons,
		back = .View in gamepad_state.buttons,
		left_thumb = .LeftThumbstick in gamepad_state.buttons,
		right_thumb = .RightThumbstick in gamepad_state.buttons,
		left_shoulder = .LeftShoulder in gamepad_state.buttons,
		right_shoulder = .RightShoulder in gamepad_state.buttons,
	}

	state := general_input_state {
		handle = rawptr(device),
		left_trigger = gamepad_state.leftTrigger,
		right_trigger = gamepad_state.rightTrigger,
		left_thumb = linalg.point{gamepad_state.leftThumbstickX, gamepad_state.leftThumbstickY},
		right_thumb = linalg.point{gamepad_state.rightThumbstickX, gamepad_state.rightThumbstickY},
		buttons = current_buttons,
	}

	general_input_callback(state)
}


@private init_gamepad :: proc() -> bool {
	result := GameInput.Create(&game_input)
	if result != 0 {
		return false
	}

	kind := GameInput.Kind{.Gamepad}
	status_filter := GameInput.DeviceStatus{.Connected}
	result = game_input->RegisterDeviceCallback(nil, kind, status_filter, .AsyncEnumeration, nil, device_callback, &device_callback_token)
	if result != 0 {
		return false
	}

	result = game_input->RegisterReadingCallback(nil, kind, 0.0, nil, reading_callback, &reading_callback_token)
	if result != 0 {
		return false
	}

	connected_devices = make([dynamic]^GameInput.IGameInputDevice)

	return true
}

/*
Gets all connected gamepad devices

Returns:
- Array of connected gamepad device handles
*/
get_connected_gamepad_devices :: proc(allocator := context.allocator) -> []^GameInput.IGameInputDevice {
	sync.mutex_lock(&devices_mtx)
	defer sync.mutex_unlock(&devices_mtx)

	result := make([]^GameInput.IGameInputDevice, len(connected_devices), allocator)

	for device, i in connected_devices {
		result[i] = device
	}
	return result
}

/*
Gets the number of connected gamepad devices

Returns:
- Number of connected gamepad devices
*/
get_connected_gamepad_count :: proc() -> int {
	sync.mutex_lock(&devices_mtx)
	defer sync.mutex_unlock(&devices_mtx)
	return len(connected_devices)
}

@private cleanup_gamepad :: proc() {
	if game_input != nil {
		if reading_callback_token != GameInput.INVALID_CALLBACK_TOKEN_VALUE {
			game_input->UnregisterCallback(reading_callback_token, 0)
		}
		if device_callback_token != GameInput.INVALID_CALLBACK_TOKEN_VALUE {
			game_input->UnregisterCallback(device_callback_token, 0)
		}
	}

	delete(connected_devices)
	game_input = nil
}
