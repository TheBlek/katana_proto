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

INSTRUMENT :: true

models: [dynamic]Model

add_model :: proc(model: Model) -> (res: int) {
    res = len(models)
    append(&models, model)
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

    katana_model, ok_file := model_load_from_file("./resources/katana.gltf")
    assert(ok_file)
    switch &t in katana_model.texture_data {
        case TextureData:
            t.textures = {
                { filename="./resources/katana_diffuse.png" },
                { filename="./resources/katana_specular.png" },
            }
    }
    katana_model_id := add_model(katana_model)

    katana := Instance {
        model_id = katana_model_id,
        scale = 0.5,
        transform = Transform {
            position = Vec3{-10, 2, 0},
            rotation = linalg.MATRIX3F32_IDENTITY,
        },
    }
    instance_update(&katana)

    terrain_model_id := add_model(get_terrain(100, 100, 6, 200, 1))
    terrain := Instance {
        model_id = terrain_model_id,
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

    cube_id := add_model(UNIT_CUBE)
    obj1 := Instance {
        model_id = cube_id,
        scale = {1, 1, 1},
        transform = Transform {
            position = {2.2, 15, 0},
            rotation = linalg.MATRIX3F32_IDENTITY,
        },
        color = {1, 0, 0},
    }
    instance_update(&obj1)

    capsule_id := add_model(UNIT_CAPSULE)
    obj2 := Instance {
        model_id = capsule_id,
        scale = 1,
        transform = Transform {
            position = {2, 8, -0.8},
            rotation = linalg.MATRIX3F32_IDENTITY,//linalg.matrix3_from_euler_angle_z(f32(linalg.PI) / 4),
        },
        color = {1, 0, 0},
    }
    instance_update(&obj2)

    sphere_id := add_model(UNIT_SPHERE)
    pointer := Instance {
        model_id = sphere_id,
        scale = 0.05,
        transform = {
            rotation = linalg.MATRIX3F32_IDENTITY,
        },
        color = {0, 0, 1},
    }
    instance_update(&pointer)

    player := Instance {
        model_id = capsule_id,
        scale = 1,
        transform = camera.transform,
    }
    instance_update(&player)

    renderer.dir_light = DirectionalLight { strength = 0.1, color = 1, direction = Vec3{1, 0, 0} }
    append(&renderer.point_lights, PointLight { strength = 1, color = Vec3{1, 1, 0}, constant = 1, linear = 0.09, quadratic = 0.032 })
    light := &renderer.point_lights[0]

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
            verts := [3]Vec3 { 
                (obj2.model_matrix * Vec4 {triangle.vertices[0].x, triangle.vertices[0].y, triangle.vertices[0].z, 1}).xyz,
                (obj2.model_matrix * Vec4 {triangle.vertices[1].x, triangle.vertices[1].y, triangle.vertices[1].z, 1}).xyz,
                (obj2.model_matrix * Vec4 {triangle.vertices[2].x, triangle.vertices[2].y, triangle.vertices[2].z, 1}).xyz,
            }
            tris := Triangle{verts, linalg.cross(verts[1] - verts[0], verts[2] - verts[0])}
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

        camera_movement :: proc(
            window: glfw.WindowHandle,
            prev: ^map[i32]i32,
            key: i32,
            camera: ^Camera,
            movement: Vec3,
            player: ^Instance,
            terrain: Instance,
        ) {
            state := glfw.GetKey(window, key)
            if state == glfw.PRESS {
                using camera
                step := transform.rotation * movement
                player.transform.position += step 
                res := collide(player^, terrain)
                // fmt.println(player.transform, transform, res)
                if !res {
                    transform.position += step
                    camera_matrix = inverse(disposition_matrix(transform))
                    instance_update(player)
                } else {
                    player.transform.position -= step
                }
            }
            prev[key] = state
        }
        step:f32 = 0.05
        camera_movement(window, &prev_key_state, glfw.KEY_W, &camera, -step * VEC3_Z, &player, terrain)
        camera_movement(window, &prev_key_state, glfw.KEY_S, &camera, step * VEC3_Z, &player, terrain)
        camera_movement(window, &prev_key_state, glfw.KEY_A, &camera, -step * VEC3_X, &player, terrain)
        camera_movement(window, &prev_key_state, glfw.KEY_D, &camera, step * VEC3_X, &player, terrain)
        camera_movement(window, &prev_key_state, glfw.KEY_LEFT_SHIFT, &camera, -step * VEC3_Y, &player, terrain)
        camera_movement(window, &prev_key_state, glfw.KEY_SPACE, &camera, step * VEC3_Y, &player, terrain)

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
        renderer_draw_instance(&renderer, camera, &katana)
        renderer_draw_instance(&renderer, camera, &terrain)
        renderer_draw_instance(&renderer, camera, &obj1)
        renderer_draw_instance(&renderer, camera, &obj2)
        renderer_draw_instance(&renderer, camera, &pointer)
        glfw.SwapBuffers(window)
        
        glfw.PollEvents()
        time.stopwatch_stop(&stopwatch)
        when INSTRUMENT {
            fmt.println(time.stopwatch_duration(stopwatch), stats.physics.collision_test["collide_triangle_triangle"])
            stats = {}
        }
    }
}
