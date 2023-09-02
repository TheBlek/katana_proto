package main

import "core:fmt"
import "core:math/linalg"
import "core:math"
import "core:time"
import "vendor:glfw"
import gl "vendor:OpenGL"
Vec2 :: linalg.Vector2f32
Vec3 :: linalg.Vector3f32
Vec4 :: linalg.Vector4f32
Mat3 :: linalg.Matrix3f32
Mat4 :: linalg.Matrix4f32

VEC3_ZERO :: Vec3(0)
VEC3_ONE :: Vec3(1)
VEC3_X :: Vec3 {1, 0, 0} 
VEC3_Y :: Vec3 {0, 1, 0}
VEC3_Z :: Vec3 {0, 0, 1}

VEC3_X_NEG :: Vec3 {-1, 0, 0} 
VEC3_Y_NEG :: Vec3 {0, -1, 0}
VEC3_Z_NEG :: Vec3 {0, 0, -1}

MAT3_IDENTITY :: linalg.MATRIX3F32_IDENTITY
MAT4_IDENTITY :: linalg.MATRIX4F32_IDENTITY

EPS :: linalg.F32_EPSILON

COLOR_RED :: VEC3_X
COLOR_GREEN :: VEC3_Y
COLOR_BLUE :: VEC3_Z

INSTRUMENT :: false

GRAVITY :: Vec3 {0, -9.81, 0}
PLAYER_HEIGHT :: 1.9
PLAYER_RUN_MULTIPLIER :: 1.5

MovementKeyBind :: struct {
    key: i32,
    vec: Vec3,
}

MOVEMENT_BINDS :: []MovementKeyBind {
    { glfw.KEY_W, Vec3{0, 0, -10} },
    { glfw.KEY_S, Vec3{0, 0, 5} },
    { glfw.KEY_A, Vec3{-3, 0, 0} },
    { glfw.KEY_D, Vec3{3, 0, 0} },
}

KATANA_MOVEMENT_BIND :: glfw.KEY_LEFT_ALT

MOUSE_SENSITIVITY :: 0.001
KATANA_SENSITIVITY :: 0.001
KATANA_ANGLES :: [2][2]f32 {
    {-linalg.PI/2, linalg.PI/2},
    {linalg.PI/2, -linalg.PI/2},
}
KATANA_SPREAD :: [2][2]f32 {
    {-2, 2},
    {-1, 2},
}
KATANA_BASE_POSITION :: Vec3{0, -2, -4}
KATANA_BASE_ROTATION :: matrix[3, 3]f32{
    -0.000, 1.000, 0.000,
    1.000, 0.000, 0.000,
    0.000, 0.000, -1.000,
}

GameState :: struct {
    instance_count: int,
    renderer: Renderer,
    physics: PhysicsData,
    window: glfw.WindowHandle,
    
    instances: [dynamic]Instance,
    player: Instance_Id,
    katana: Instance_Id,
    camera: Camera,
    terrain: Instance_Id,
    enemies: [dynamic]Instance_Id,
    pointer: Instance_Id,

    prev_key_state: map[i32]i32,
    prev_mouse_pos: Vec2,
    pitch, yaw: f32,

    player_velocity: Vec3,
    grounded: bool,
    ground_normal: Vec3,
 
    pause: bool,
    last_xt: f32,
}

vec4_from_vec3 :: proc(vec: Vec3, w: f32) -> Vec4 {
    return {vec.x, vec.y, vec.z, w}
}

Transform :: struct {
    position: Vec3,
    rotation: Mat3,
}

WIDTH :: 1280
HEIGHT :: 720

render :: proc(state: ^GameState) {
    gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
    renderer_draw_instance(&state.renderer, state.camera, &state.instances[state.katana])
    renderer_draw_instance(&state.renderer, state.camera, &state.instances[state.terrain])
    renderer_draw_instance(&state.renderer, state.camera, &state.instances[state.pointer])
    for &enemy in state.enemies {
        renderer_draw_instance(&state.renderer, state.camera, &state.instances[enemy])
    }
    glfw.SwapBuffers(state.window)
}

destroy :: proc(state: GameState) {
    glfw.Terminate()
    glfw.DestroyWindow(state.window)
}

@(deferred_out=destroy)
init :: proc() -> GameState  {
    window, renderer := renderer_init()
    glfw.SetInputMode(window, glfw.CURSOR, glfw.CURSOR_DISABLED) 
    gl.Enable(gl.DEPTH_TEST)

    camera := Camera {
        fov = 70,
        transform = Transform {
            rotation = MAT3_IDENTITY,
            position = Vec3{0, 100, 25},
        },
        near = 0.1,
        far = 1000,
    }
    camera.projection_matrix = calculate_projection_matrix(
        camera.fov,
        camera.near,
        camera.far,
    )
    state := GameState {
        renderer = renderer,
        camera = camera,
        window = window,
        last_xt = 0.5,
    }

    katana_model, ok_file := model_load_from_file("./resources/katana.gltf")
    assert(ok_file)
    switch &t in katana_model.texture_data {
        case TextureData:
            t.textures = make([]Texture, 2)
            t.textures[0] = { filename="./resources/katana_diffuse.png" }
            t.textures[1] = { filename="./resources/katana_specular.png" }
    }
    katana_model_id := model_register(&state, katana_model)

    state.katana = instance_create(
        &state,
        katana_model_id,
        scale = 0.1,
        position = KATANA_BASE_POSITION,
        rotation = KATANA_BASE_ROTATION,
    )
    instance_update(state, state.katana)

    terrain_model_id := model_register(&state, get_terrain(100, 100, 6, 200, 1))
    state.terrain = instance_create(&state, terrain_model_id, color = Vec3{0.659, 0.392, 0.196})
    instance_update(state, state.terrain)
    // terrain_partition := partition_grid_from_instance(state.physics, 1, 101, terrain)
    
    capsule_id := model_register(&state, get_capsule(2))
    obj2 := instance_create(&state, capsule_id, position = {2, 8, -0.8}, color = COLOR_RED)
    instance_update(state, obj2)

    sphere_id := model_register(&state, get_sphere(2))
    state.pointer = instance_create(&state, sphere_id, scale = 0.05, color = COLOR_BLUE)
    instance_update(state, state.pointer)

    state.renderer.dir_light = DirectionalLight { strength = 0.1, color = 1, direction = Vec3{1, 0, 0} }
    append(&state.renderer.point_lights, PointLight { strength = 1, color = Vec3{1, 1, 0}, constant = 1, linear = 0.09, quadratic = 0.032 })
    // light := &state.renderer.point_lights[0]

    state.player = instance_create(&state, capsule_id, position = {0, 10, 25})
    append(&state.instances[state.player].children, state.katana)

    append(&state.enemies, obj2)
    return state
}

handle_input :: proc(state: ^GameState, dt: f32) {
    player := &state.instances[state.player]
    if state.grounded {
        shift := glfw.GetKey(state.window, glfw.KEY_LEFT_SHIFT)
        state.prev_key_state[glfw.KEY_LEFT_SHIFT] = shift
        multiplier: f32 = 1.0
        if shift == glfw.PRESS {
            multiplier = PLAYER_RUN_MULTIPLIER
        }

        for move in MOVEMENT_BINDS {
            key_state := glfw.GetKey(state.window, move.key)
            if key_state == glfw.PRESS { 
                ground := plane_from_normal_n_point(state.ground_normal, player.position)
                shifted := player.position + state.camera.transform.rotation * move.vec * multiplier * dt
                to := plane_project_point(ground, shifted)
                player.position = to 
            }
            state.prev_key_state[move.key] = key_state
        }
    }

    x, y := glfw.GetCursorPos(state.window)
    diff := Vec2{f32(x), f32(y)}  - state.prev_mouse_pos
    katana := &state.instances[state.katana]
    if glfw.GetKey(state.window, KATANA_MOVEMENT_BIND) != glfw.PRESS {
        offset := diff * MOUSE_SENSITIVITY

        state.pitch -= offset.y
        state.yaw -= offset.x
        state.pitch = clamp(state.pitch, -math.PI/2 - 0.1, math.PI/2 - 0.1)

        state.camera.transform.rotation = linalg.matrix3_from_yaw_pitch_roll(state.yaw, state.pitch, 0)
    } else {
        katana.position.x += diff.x * KATANA_SENSITIVITY
        katana.position.x = clamp(
            katana.position.x,
            KATANA_BASE_POSITION.x + KATANA_SPREAD.x[0],
            KATANA_BASE_POSITION.x + KATANA_SPREAD.x[1],
        )
        katana.position.y -= diff.y * KATANA_SENSITIVITY
        katana.position.y = clamp(
            katana.position.y,
            KATANA_BASE_POSITION.y + KATANA_SPREAD.y[0],
            KATANA_BASE_POSITION.y + KATANA_SPREAD.y[1],
        )

        xt: f32 = state.last_xt
        if linalg.length(diff) < 100 {
            xt = 0.5 * clamp(
                (katana.position.x - KATANA_BASE_POSITION.x) / abs(KATANA_SPREAD.x[1]),
                0, 1,
            ) + 0.5 * clamp(
                1 - (KATANA_BASE_POSITION.x - katana.position.x) / abs(KATANA_SPREAD.x[0]),
                0, 1,
            )
        }

        yt := 0.5 * clamp(
            (katana.position.y - KATANA_BASE_POSITION.y) / abs(KATANA_SPREAD.y[1]),
            0, 1,
        ) + 0.5 * clamp(
            1 - (KATANA_BASE_POSITION.y - katana.position.y) / abs(KATANA_SPREAD.y[0]),
            0, 1,
        )
        
        katana.rotation = linalg.matrix3_from_euler_angles_zx(
            math.lerp(KATANA_ANGLES.x[0], KATANA_ANGLES.x[1], xt),
            math.lerp(KATANA_ANGLES.y[0], KATANA_ANGLES.y[1], yt),
        ) * KATANA_BASE_ROTATION
        state.last_xt = xt
    }
    state.prev_mouse_pos = Vec2{f32(x), f32(y)}
    state.camera.transform.position = player.position
    player.rotation = state.camera.transform.rotation
    camera_update(&state.camera)
    instance_update(state^, state.player)
}

update :: proc(state: ^GameState, dt: f32) {
    player := &state.instances[state.player]
    katana := &state.instances[state.katana]
    terrain := state.instances[state.terrain]
    downwards := Ray { player.position, VEC3_Y_NEG }
    state.grounded = false
    if data, ok := collision_full(state.physics, downwards, terrain).(CollisionData); ok {
        if linalg.length(player.position - data.point) < PLAYER_HEIGHT {
            state.grounded = true
            state.ground_normal = data.normal
            state.player_velocity.y = 0
        }
    }

    if !state.grounded {
        state.player_velocity += GRAVITY * dt
    }

    player.position += state.player_velocity * dt

    sight := Ray { state.camera.transform.position, state.camera.transform.rotation * VEC3_Z_NEG }
    if point, ok := collision(state.physics, sight, terrain).(Vec3); ok {
        pointer := &state.instances[state.pointer]
        pointer.position = point
        instance_update(state^, state.pointer)
    }

    for enemy, i in state.enemies {
        if collide(state.physics, katana^, state.instances[enemy]) {
            unordered_remove(&state.enemies, i)
            fmt.println("Removed!")
        }
    }
}

main :: proc() {
    state := init()

    dt: f32 = 0.05
    stopwatch: time.Stopwatch
    for !glfw.WindowShouldClose(state.window) {
        time.stopwatch_reset(&stopwatch)
        time.stopwatch_start(&stopwatch)
        // Game logic

        if !state.pause {
            update(&state, dt)
            handle_input(&state, dt)
        }

        e_state := glfw.GetKey(state.window, glfw.KEY_E)
        if e_state == glfw.PRESS && state.prev_key_state[glfw.KEY_E] == glfw.RELEASE {
            state.pause = !state.pause
            fmt.println("Pressed e")
        }
        state.prev_key_state[glfw.KEY_E] = e_state

        render(&state)
        
        glfw.PollEvents()
        time.stopwatch_stop(&stopwatch)
        dt = cast(f32)time.duration_seconds(time.stopwatch_duration(stopwatch))
        when INSTRUMENT {
            fmt.println("Total: ", dt * 1000, "ms")
            fmt.printf("%#v\n", stats)
            stats = {}
            fmt.println("End of frame")
        }
    }
}
