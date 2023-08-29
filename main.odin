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

GameState :: struct {
    models: [dynamic]Model,
    instance_count: int,
    renderer: Renderer,
    physics: PhysicsData, 
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

main :: proc() {
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
    }
    state.renderer.models = &state.models
    state.physics.models = &state.models

    katana_model, ok_file := model_load_from_file("./resources/katana.gltf")
    assert(ok_file)
    switch &t in katana_model.texture_data {
        case TextureData:
            t.textures = {
                { filename="./resources/katana_diffuse.png" },
                { filename="./resources/katana_specular.png" },
            }
    }
    katana_model_id := model_register(&state, katana_model)

    katana := instance_create(
        &state,
        katana_model_id,
        scale = 0.1,
        position = {0, -2, -5},
        rotation = linalg.matrix3_from_euler_angles_zx_f32(-linalg.PI / 2, linalg.PI),
    )
    instance_update(state, &katana)

    terrain_model_id := model_register(&state, get_terrain(100, 100, 6, 200, 1))
    terrain := instance_create(&state, terrain_model_id, color = Vec3{0.659, 0.392, 0.196})
    instance_update(state, &terrain)
    // terrain_partition := partition_grid_from_instance(state.physics, 1, 101, terrain)

    cube_id := model_register(&state, UNIT_CUBE)
    obj1 := instance_create(&state, cube_id, position = {2.2, 15, 0}, color = COLOR_RED)
    instance_update(state, &obj1)

    capsule_id := model_register(&state, UNIT_CAPSULE)
    obj2 := instance_create(&state, capsule_id, position = {2, 8, -0.8}, color = COLOR_RED)
    instance_update(state, &obj2)

    sphere_id := model_register(&state, UNIT_SPHERE)
    pointer := instance_create(&state, sphere_id, scale = 0.05, color = COLOR_BLUE)
    instance_update(state, &pointer)

    state.renderer.dir_light = DirectionalLight { strength = 0.1, color = 1, direction = Vec3{1, 0, 0} }
    append(&state.renderer.point_lights, PointLight { strength = 1, color = Vec3{1, 1, 0}, constant = 1, linear = 0.09, quadratic = 0.032 })
    // light := &state.renderer.point_lights[0]

    player := instance_create(&state, capsule_id, position = {0, 10, 25})
    append(&player.children, &katana)

    enemies: [dynamic]^Instance
    append(&enemies, &obj2)

    prev_key_state: map[i32]i32
    prev_mouse_pos: Vec2
    pitch, yaw: f32
    mouse_sensitivity:f32 = 0.001
    katana_sensitivity:f32 = 0.001

    player_velocity := Vec3(0)
    grounded := false
    ground_normal: Vec3
 
    stopwatch: time.Stopwatch
    pause := true
    dt: f32 = 0.05
    for !glfw.WindowShouldClose(window) { // Render
        time.stopwatch_reset(&stopwatch)
        time.stopwatch_start(&stopwatch)
        // Game logic
        downwards := Ray { player.position, VEC3_Y_NEG }

        if !pause {
            grounded = false
            if data, ok := collision_full(state.physics, downwards, terrain).(CollisionData); ok {
                if linalg.length(player.position - data.point) < PLAYER_HEIGHT {
                    grounded = true
                    ground_normal = data.normal
                    player_velocity.y = 0
                }
            }

            if !grounded {
                player_velocity += GRAVITY * dt
            }

            player.position += player_velocity * dt

            sight := Ray { camera.transform.position, camera.transform.rotation * VEC3_Z_NEG }
            if point, ok := collision(state.physics, sight, obj2).(Vec3); ok {
                pointer.position = point
                instance_update(state, &pointer)
            }

            if grounded {
                shift := glfw.GetKey(window, glfw.KEY_LEFT_SHIFT)
                prev_key_state[glfw.KEY_LEFT_SHIFT] = shift
                multiplier: f32 = 1.0
                if shift == glfw.PRESS {
                    multiplier = PLAYER_RUN_MULTIPLIER
                }

                for move in MOVEMENT_BINDS {
                    key_state := glfw.GetKey(window, move.key)
                    if key_state == glfw.PRESS { 
                        ground := plane_from_normal_n_point(ground_normal, player.position)
                        shifted := player.position + camera.transform.rotation * move.vec * multiplier * dt
                        to := plane_project_point(ground, shifted)
                        player.position = to 
                    }
                    prev_key_state[move.key] = key_state
                }
            }

            x, y := glfw.GetCursorPos(window)
            diff := Vec2{f32(x), f32(y)}  - prev_mouse_pos
            if glfw.GetKey(window, KATANA_MOVEMENT_BIND) != glfw.PRESS {
                offset := diff * mouse_sensitivity

                pitch -= offset.y
                yaw -= offset.x
                pitch = clamp(pitch, -math.PI/2 - 0.1, math.PI/2 - 0.1)

                camera.transform.rotation = linalg.matrix3_from_yaw_pitch_roll(yaw, pitch, 0)
            } else {
                katana.position.x += diff.x * katana_sensitivity
                katana.position.x = clamp(katana.position.x, -2, 2)
                katana.position.y -= diff.y * katana_sensitivity
                katana.position.y = clamp(katana.position.y, -3, 0)
            }
            prev_mouse_pos = Vec2{f32(x), f32(y)}
            camera.transform.position = player.position
            player.rotation = camera.transform.rotation
            camera_update(&camera)
            instance_update(state, &player)

            for enemy, i in enemies {
                if collide(state.physics, katana, enemy^) {
                    unordered_remove(&enemies, i)
                    fmt.println("Removed!")
                }
            }
        }


        e_state := glfw.GetKey(window, glfw.KEY_E)
        if e_state == glfw.PRESS && prev_key_state[glfw.KEY_E] == glfw.RELEASE {
            pause = !pause
            fmt.println("Pressed e")
        }
        prev_key_state[glfw.KEY_E] = e_state

        // Rendering
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
        renderer_draw_instance(&state.renderer, camera, &katana)
        renderer_draw_instance(&state.renderer, camera, &terrain)
        renderer_draw_instance(&state.renderer, camera, &obj1)
        renderer_draw_instance(&state.renderer, camera, &pointer)
        for enemy in enemies {
            renderer_draw_instance(&state.renderer, camera, enemy)
        }
        glfw.SwapBuffers(window)
        
        glfw.PollEvents()
        time.stopwatch_stop(&stopwatch)
        dt = cast(f32)time.duration_seconds(time.stopwatch_duration(stopwatch))
        fmt.println(dt * 1000)
        when INSTRUMENT {
            fmt.printf("%#v", stats)
            stats = {}
        }
        fmt.println("End of frame")
    }
}
