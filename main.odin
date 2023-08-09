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

VEC3_X :: linalg.VECTOR3F32_X_AXIS
VEC3_Y :: linalg.VECTOR3F32_Y_AXIS
VEC3_Z :: linalg.VECTOR3F32_Z_AXIS

EPS :: 0.001

vec4_from_vec3 :: proc(vec: Vec3, w: f32) -> Vec4 {
    return {vec.x, vec.y, vec.z, w}
}

Transform :: struct {
    position: Vec3,
    rotation: Mat3,
}

Camera :: struct {
    fov: f32,
    near: f32,
    far: f32,
    transform: Transform,
    projection_matrix: linalg.Matrix4f32,
    camera_matrix: linalg.Matrix4f32,
}

// left, right, bottom, top, near, far
calculate_projection_matrix_full :: proc(l, r, b, t, n, f: f32) -> (projection_matrix: Mat4) {
    projection_matrix = {
        2 * n / (r - l),    0,                  (r + l) / (r - l),  0,
        0,                  2 * n / (t - b),    (t + b) / (t - b),  0,
        0,                  0,                  -(f + n) / (f - n), -2 * f * n / (f - n),
        0,                  0,                  -1,                 0,
    }
    return
}

calculate_projection_matrix :: proc(fov, near, far: f32) -> (projection_matrix: Mat4) {
    fov := math.to_radians(fov)
    aspect_ratio: f32 = f32(WIDTH) / HEIGHT

    width := 2 * near * math.tan(fov/2)
    height := width / aspect_ratio
    projection_matrix = {
        2 * near / width,   0,                  0,                              0,
        0,                  2 * near / height,  0,                              0,
        0,                  0,                  -(far + near) / (far - near),   -2 * far * near / (far - near),
        0,                  0,                  -1,                             0,
    }
    return
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
            rotation = linalg.MATRIX3F32_IDENTITY,
            position = Vec3{0, 10, 25},
        },
        near = 0.1,
        far = 1000,
    }
    {
        using camera
        projection_matrix = calculate_projection_matrix(fov, near, far)
        camera_matrix = inverse(disposition_matrix(transform))
    }

    m, ok_file := model_load_from_file("./resources/katana.gltf")
    assert(ok_file)
    switch &t in m.texture_data {
        case TextureData:
            t.textures = {
                { filename="./resources/katana_texture.png" },
                { filename="./resources/katana_diffuse.png" },
                { filename="./resources/katana_specular.png" },
            }
    }

    instance1 := Instance {
        model = m,
        scale = 0.5,
        transform = Transform {
            position = Vec3{-10, 2, 0},
            rotation = linalg.MATRIX3F32_IDENTITY,
        },
    }
    instance_update(&instance1)
    terrain := Instance {
        model = get_terrain(100, 100, 6, 200, 1),
        scale = 1,
        transform = Transform {
            position = Vec3{0, 0, 0},
            rotation = linalg.MATRIX3F32_IDENTITY,
        },
        color = {0.659, 0.392, 0.196},
    }
    instance_update(&terrain)

    triangle := Model {
        vertices = {{0.5, 0, 0}, {0, 0.5, 0}, {0, 0, 0.5}},
        normals = {
            linalg.sqrt(f32(3)), linalg.sqrt(f32(3)), linalg.sqrt(f32(3)),
        },
        indices = {0, 1, 2},
    }

    obj1 := Instance {
        model = UNIT_CUBE,
        scale = {1, 1, 1},
        transform = Transform {
            position = {2.2, 15, 0},
            rotation = linalg.MATRIX3F32_IDENTITY,
        },
        color = {1, 0, 0},
    }
    instance_update(&obj1)
    obj2 := Instance {
        model = UNIT_CAPSULE,
        scale = 1,
        transform = Transform {
            position = {2, 8, -0.8},
            rotation = linalg.MATRIX3F32_IDENTITY,//linalg.matrix3_from_euler_angle_z(f32(linalg.PI) / 4),
        },
        color = {1, 0, 0},
    }
    instance_update(&obj2)

    pointer := Instance {
        model = UNIT_SPHERE,
        scale = 0.05,
        transform = {
            rotation = linalg.MATRIX3F32_IDENTITY,
        },
        color = {0, 0, 1},
    }
    instance_update(&pointer)

    prev_key_state: map[i32]i32
    prev_mouse_pos: Vec2
    pitch, yaw: f32
    mouse_sensitivity:f32 = 0.01
    gravity_step: f32 = 0.02
    stopwatch: time.Stopwatch
    pause := false
    for !glfw.WindowShouldClose(window) { // Render
        time.stopwatch_reset(&stopwatch)
        time.stopwatch_start(&stopwatch)
        // Game logic
        if !pause {
            verts := [3]Vec3 { 
                (obj2.model_matrix * Vec4 {triangle.vertices[0].x, triangle.vertices[0].y, triangle.vertices[0].z, 1}).xyz,
                (obj2.model_matrix * Vec4 {triangle.vertices[1].x, triangle.vertices[1].y, triangle.vertices[1].z, 1}).xyz,
                (obj2.model_matrix * Vec4 {triangle.vertices[2].x, triangle.vertices[2].y, triangle.vertices[2].z, 1}).xyz,
            }
            tris := Triangle{verts, linalg.cross(verts[1] - verts[0], verts[2] - verts[0])}
            result := collide(obj1, obj2)
            if !result {
                obj1.transform.position.y -= gravity_step
                instance_update(&obj1)
            }

            // point1 := (disposition_matrix(camera.transform) * Vec4{0, 0, 0, 1}).xyz
            // point2 := (disposition_matrix(camera.transform) * Vec4{0, 0, -1, 1}).xyz
            // ray := ray_from_points(Vec3(point1), Vec3(point2))
            // if collision, ok := collision(ray, tris).(Vec3); ok {
            //     pointer.transform.position = collision
            //     instance_update(&pointer)
            // }
        }

        // Input
        e_state := glfw.GetKey(window, glfw.KEY_E)
        if e_state == glfw.PRESS && prev_key_state[glfw.KEY_E] == glfw.RELEASE {
            pause = !pause
            fmt.println("Pressed e")
        }
        prev_key_state[glfw.KEY_E] = e_state

        camera_movement :: proc(
            window: glfw.WindowHandle,
            prev: ^map[i32]i32,
            key: i32,
            camera: ^Camera,
            movement: Vec3,
        ) {
            state := glfw.GetKey(window, key)
            if state == glfw.PRESS {
                using camera
                transform.position += transform.rotation * movement
                camera_matrix = inverse(disposition_matrix(transform))
            }
            prev[key] = state
        }
        step:f32 = 0.05
        camera_movement(window, &prev_key_state, glfw.KEY_W, &camera, -step * VEC3_Z)
        camera_movement(window, &prev_key_state, glfw.KEY_S, &camera, step * VEC3_Z)
        camera_movement(window, &prev_key_state, glfw.KEY_A, &camera, -step * VEC3_X)
        camera_movement(window, &prev_key_state, glfw.KEY_D, &camera, step * VEC3_X)
        camera_movement(window, &prev_key_state, glfw.KEY_LEFT_SHIFT, &camera, -step * VEC3_Y)
        camera_movement(window, &prev_key_state, glfw.KEY_SPACE, &camera, step * VEC3_Y)

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
        renderer_draw_instance(renderer, camera, &instance1)
        renderer_draw_instance(renderer, camera, &terrain)
        renderer_draw_instance(renderer, camera, &obj1)
        renderer_draw_instance(renderer, camera, &obj2)
        renderer_draw_instance(renderer, camera, &pointer)
        glfw.SwapBuffers(window)
        
        glfw.PollEvents()
        time.stopwatch_stop(&stopwatch)
        // fmt.println(time.stopwatch_duration(stopwatch))
    }
}
