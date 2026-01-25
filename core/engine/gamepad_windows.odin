#+build windows
package engine

import "core:math/linalg"
import "core:mem"
import "base:runtime"
import "vendor:windows/GameInput"

@(private = "file") game_input: ^GameInput.IGameInput
@(private = "file") callback_token: GameInput.CallbackToken

@(private = "file")
reading_callback :: proc "stdcall" (token: GameInput.CallbackToken, ctx: rawptr, reading: ^GameInput.IGameInputReading, hasOverrunOccured: bool) {
	if general_input_callback == nil do return
	if reading == nil do return

	context = runtime.default_context()

	device: ^GameInput.IGameInputDevice
	reading->GetDevice(&device)
	if device == nil do return

	gamepad_state: GameInput.GamepadState
	success := reading->GetGamepadState(&gamepad_state)
	if !success do return

	// Convert to general_input_state
	state := general_input_state {
		handle = rawptr(device),
		left_trigger = gamepad_state.leftTrigger,
		right_trigger = gamepad_state.rightTrigger,
		left_thumb = linalg.point{gamepad_state.leftThumbstickX, gamepad_state.leftThumbstickY},
		right_thumb = linalg.point{gamepad_state.rightThumbstickX, gamepad_state.rightThumbstickY},
		buttons = general_input_buttons {
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
		},
	}

	general_input_callback(state)
}


@private init_gamepad :: proc() -> bool {
	result := GameInput.Create(&game_input)
	if result != 0 {
		return false
	}

	kind := GameInput.Kind{.Gamepad}
	result = game_input->RegisterReadingCallback(nil, kind, 0.0, nil, reading_callback, &callback_token)
	if result != 0 {
		return false
	}
	return true
}


@private cleanup_gamepad :: proc() {
	if game_input != nil && callback_token != GameInput.INVALID_CALLBACK_TOKEN_VALUE {
		game_input->UnregisterCallback(callback_token, 0)
	}

	game_input = nil
}
