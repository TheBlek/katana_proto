package main

import "vendor:glfw"

MovementKeyBind :: struct {
    key: i32,
    vec: Vec3,
}

input_gather :: proc(state: ^InputState, window: glfw.WindowHandle) {
    for key in state.keys {
        state.prev_key_state[key] = state.key_state[key]
        state.key_state[key] = glfw.GetKey(window, key)
    }

    state.prev_mouse_pos = state.mouse_pos
    x, y := glfw.GetCursorPos(window)
    state.mouse_pos = Vec2{f32(x), f32(y)}
}

input_pressed :: proc(state: InputState, key: i32) -> bool {
    assert(key in state.key_state)
    return state.key_state[key] == glfw.PRESS
}

input_clicked :: proc(state: InputState, key: i32) -> bool {
    assert(key in state.key_state)
    assert(key in state.prev_key_state)
    return state.key_state[key] == glfw.PRESS && state.prev_key_state[key] == glfw.RELEASE
}

input_mouse_diff :: proc(state: InputState) -> Vec2 {
    return state.mouse_pos - state.prev_mouse_pos
}
