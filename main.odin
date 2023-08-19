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

EPS :: 0.001

COLOR_RED :: VEC3_X
COLOR_GREEN :: VEC3_Y
COLOR_BLUE :: VEC3_Z

INSTRUMENT :: true

MovementKeyBind :: struct {
    key: i32,
    vec: Vec3,
}

MOVEMENT_BINDS :: []MovementKeyBind {
    { glfw.KEY_W, VEC3_Z_NEG },
    { glfw.KEY_S, VEC3_Z },
    { glfw.KEY_A, VEC3_X_NEG },
    { glfw.KEY_D, VEC3_X },
    { glfw.KEY_LEFT_SHIFT, VEC3_Y_NEG },
    { glfw.KEY_SPACE, VEC3_Y },
}

GameState :: struct {
    models: [dynamic]Model,
    instance_count: int,
    renderer: Renderer,
    physics: PhysicsData, 
}

register_model :: proc(state: ^GameState, m: Model) -> (res: int) {
    res = len(state.models)
    append(&state.models, m)
    return
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
            rotation = linalg.MATRIX3F32_IDENTITY, position = Vec3{0, 10, 25}, },
        near = 0.1,
        far = 1000,
    }
    {
        using camera
        projection_matrix = calculate_projection_matrix(fov, near, far)
        camera_matrix = inverse(disposition_matrix(transform))
    }
    state := GameState {
        renderer = renderer
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
    katana_model_id := register_model(&state, katana_model)

    katana := instance_create(&state, katana_model_id, scale = 0.5, position = Vec3{-10, 2, 0})
    instance_update(state, &katana)

    terrain_model_id := register_model(&state, get_terrain(100, 100, 6, 200, 1))
    terrain := instance_create(&state, terrain_model_id, color = Vec3{0.659, 0.392, 0.196})
    instance_update(state, &terrain)
    terrain_partition := partition_grid_from_instance(state.physics, 1, 101, terrain)

    cube_id := register_model(&state, UNIT_CUBE)
    obj1 := instance_create(&state, cube_id, position = {2.2, 15, 0}, color = COLOR_RED)
    instance_update(state, &obj1)

    capsule_id := register_model(&state, UNIT_CAPSULE)
    obj2 := instance_create(&state, capsule_id, position = {2, 8, -0.8}, color = COLOR_RED)
    instance_update(state, &obj2)

    sphere_id := register_model(&state, UNIT_SPHERE)
    pointer := instance_create(&state, sphere_id, scale = 0.05, color = VEC3_Z)
    instance_update(state, &pointer)

    player := instance_create(&state, capsule_id, camera.transform)
    instance_update(state, &player)

    state.renderer.dir_light = DirectionalLight { strength = 0.1, color = 1, direction = Vec3{1, 0, 0} }
    append(&state.renderer.point_lights, PointLight { strength = 1, color = Vec3{1, 1, 0}, constant = 1, linear = 0.09, quadratic = 0.032 })
    light := &state.renderer.point_lights[0]

    prev_key_state: map[i32]i32
    prev_mouse_pos: Vec2
    pitch, yaw: f32
    mouse_sensitivity:f32 = 0.01
    gravity_step: f32 = 0.02
    stopwatch: time.Stopwatch
    pause := false
    angle: f32 = 0
    for !glfw.WindowShouldClose(window) { // Render
        time.stopwatch_reset(&stopwatch)
        time.stopwatch_start(&stopwatch)
        // Game logic
        if !pause {
            // result := collide(obj1, obj2)
            // if !result {
            //     obj1.transform.position.y -= gravity_step
            //     instance_update(&obj1)
            // }

            // point1 := (disposition_matrix(camera.transform) * Vec4{0, 0, 0, 1}).xyz
            // point2 := (disposition_matrix(camera.transform) * Vec4{0, 0, -1, 1}).xyz
            // ray := ray_from_points(Vec3(point1), Vec3(point2))
            // if collision, ok := collision(ray, tris).(Vec3); ok {
            //     pointer.transform.position = collision
            //     instance_update(&pointer)
            // }
            angle += gravity_step 
            direction := linalg.matrix3_from_euler_angle_z(angle) * Vec3{1, 0, 0}
            // renderer.dir_light.direction = direction
        }
        light.position.y += gravity_step

        // Input
        e_state := glfw.GetKey(window, glfw.KEY_E)
        if e_state == glfw.PRESS && prev_key_state[glfw.KEY_E] == glfw.RELEASE {
            pause = !pause
            fmt.println("Pressed e")
        }
        prev_key_state[glfw.KEY_E] = e_state

        dt: f32 = 0.05
        for bind in MOVEMENT_BINDS {
            key := glfw.GetKey(window, bind.key)
            if key == glfw.PRESS {
                step := camera.transform.rotation * (dt * bind.vec)
                player.transform.position += step 
                // instance_update(state, &player)
                res := collide(state.physics, player, terrain, terrain_partition)
                if !res {
                    camera.transform.position += step
                    camera.camera_matrix = inverse(disposition_matrix(camera.transform))
                } else {
                    player.transform.position -= step
                }
            }
            prev_key_state[bind.key] = key
        }

        x, y := glfw.GetCursorPos(window)
        diff := Vec2{f32(x), f32(y)}  - prev_mouse_pos
        if linalg.length(diff) > 0.1 {
            offset := diff * mouse_sensitivity
            pitch -= offset.y
            yaw -= offset.x

            pitch = clamp(pitch, -math.PI/2 - 0.1, math.PI/2 - 0.1)

            camera.transform.rotation = linalg.matrix3_from_yaw_pitch_roll(yaw, pitch, 0)
            camera.camera_matrix = inverse(disposition_matrix(camera.transform))
            prev_mouse_pos = Vec2{f32(x), f32(y)}
        }

        // Rendering
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
        renderer_draw_instance(&state.renderer, camera, &katana)
        renderer_draw_instance(&state.renderer, camera, &terrain)
        renderer_draw_instance(&state.renderer, camera, &obj1)
        renderer_draw_instance(&state.renderer, camera, &obj2)
        renderer_draw_instance(&state.renderer, camera, &pointer)
        glfw.SwapBuffers(window)
        
        glfw.PollEvents()
        time.stopwatch_stop(&stopwatch)
        fmt.println(time.stopwatch_duration(stopwatch))
        when INSTRUMENT {
            fmt.println(stats.render.draw, stats.physics.collision_test)
            stats = {}
        }
        fmt.println("End of frame")
    }
}
