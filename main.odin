package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:mem"
import "core:math/linalg"
import "core:math"
import "vendor:glfw"
import gl "vendor:OpenGL"
import "core:encoding/json"
import "core:image/png"
import "core:image"
import "core:bytes"

Vec2 :: linalg.Vector2f32
Vec3 :: linalg.Vector3f32
Vec4 :: linalg.Vector4f32
Mat3 :: linalg.Matrix3f32
Mat4 :: linalg.Matrix4f32

VEC3_X :: linalg.VECTOR3F32_X_AXIS
VEC3_Y :: linalg.VECTOR3F32_Y_AXIS
VEC3_Z :: linalg.VECTOR3F32_Z_AXIS

shader_load_from_combined_file :: proc(filepath: string) -> (program: u32, ok := true) {
    data, ok_file := os.read_entire_file(filepath, context.allocator)
    if !ok_file {
        ok = false
        return
    }
    defer delete(data, context.allocator)

    text := string(data)
    blobs := strings.split(text, "#shader ")
    if len(blobs) != 3 {
        ok = false
        return
    }

    vs_source, fs_source: string
    for blob in blobs {
        if strings.has_prefix(blob, "vertex") {
            vs_source = strings.trim_prefix(blob, "vertex")
        }
        if strings.has_prefix(blob, "fragment") {
            fs_source = strings.trim_prefix(blob, "fragment")
        }
    }

    return gl.load_shaders_source(vs_source, fs_source)
}

shader_set_uniform_matrix3 :: proc(program: u32, name: cstring, mat: Mat3) {
    location := gl.GetUniformLocation(program, name)
    flat := matrix_flatten(mat)
    gl.UniformMatrix3fv(
        location,
        1,
        gl.FALSE,
        raw_data(flat[:]),
    )
}

shader_set_uniform_matrix4 :: proc(program: u32, name: cstring, mat: Mat4) {
    location := gl.GetUniformLocation(program, name)
    flat := matrix_flatten(mat)
    gl.UniformMatrix4fv(
        location,
        1,
        gl.FALSE,
        raw_data(flat[:]),
    )
}

shader_set_uniform_vec4 :: proc(program: u32, name: cstring, vec: Vec4) {
    location := gl.GetUniformLocation(program, name)
    gl.Uniform4f(location, vec.x, vec.y, vec.z, vec.w)
}

shader_set_uniform_vec3 :: proc(program: u32, name: cstring, vec: Vec3) {
    location := gl.GetUniformLocation(program, name)
    gl.Uniform3f(location, vec.x, vec.y, vec.z)
}

shader_set_uniform_1i :: proc(program: u32, name: cstring, value: i32) {
    location := gl.GetUniformLocation(program, name)
    gl.Uniform1i(location, value)
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

RenderMode :: enum {
    Plain = 0,
    Textured = 1,
}

RenderModeData :: struct {
    vao: u32,
    vbo: u32,
    shader: u32,
}

Renderer :: struct($n: int) {
    modes: [n]RenderModeData,
}

renderer_destroy :: proc(window: glfw.WindowHandle, _: Renderer(2)) {
    glfw.Terminate()
    glfw.DestroyWindow(window)
}

@(deferred_out=renderer_destroy)
renderer_init :: proc() -> (glfw.WindowHandle, Renderer(2)) {
    assert(glfw.Init() != 0, "Failed to initialize glfw")

    window := glfw.CreateWindow(WIDTH, HEIGHT, "Hello world", nil, nil) 
    assert(window != nil, "Failed to create window")
    
    glfw.MakeContextCurrent(window)
    glfw.SwapInterval(1)

    gl.load_up_to(4, 6, glfw.gl_set_proc_address)
    gl.Enable(gl.DEPTH_TEST)

    textured_shader, ok := shader_load_from_combined_file("textured.shader")
    assert(ok, "Shader error. Aborting") 

    plain_shader, ok_plain := shader_load_from_combined_file("plain.shader")
    assert(ok_plain, "Shader error. Aborting") 

    gl.UseProgram(textured_shader)
    shader_set_uniform_1i(textured_shader, "u_texture", 0)
    shader_set_uniform_1i(textured_shader, "u_diffuse", 1)
    shader_set_uniform_1i(textured_shader, "u_specular", 2)

    textured_vao: u32
    gl.GenVertexArrays(1, &textured_vao)
    gl.BindVertexArray(textured_vao)
    textured_vbo: u32
    gl.GenBuffers(1, &textured_vbo)
    gl.BindBuffer(gl.ARRAY_BUFFER, textured_vbo)

    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, 8 * size_of(f32), 0)
    gl.EnableVertexAttribArray(1)
    gl.VertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, 8 * size_of(f32), 3 * size_of(f32))
    gl.EnableVertexAttribArray(2)
    gl.VertexAttribPointer(2, 2, gl.FLOAT, gl.FALSE, 8 * size_of(f32), 6 * size_of(f32))

    textured_ebo: u32
    gl.GenBuffers(1, &textured_ebo)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, textured_ebo)

    gl.BindVertexArray(0) // Unbind effectively

    gl.UseProgram(plain_shader)
    plain_vao: u32
    gl.GenVertexArrays(1, &plain_vao)
    gl.BindVertexArray(plain_vao)
    plain_vbo: u32
    gl.GenBuffers(1, &plain_vbo)
    gl.BindBuffer(gl.ARRAY_BUFFER, plain_vbo)

    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, 6 * size_of(f32), 0)
    gl.EnableVertexAttribArray(1)
    gl.VertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, 6 * size_of(f32), 3 * size_of(f32))

    plain_ebo: u32
    gl.GenBuffers(1, &plain_ebo)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, plain_ebo)

    gl.BindVertexArray(0) // Unbind effectively

    renderer := Renderer(2) {
        {
            { vao=plain_vao, vbo=plain_vbo, shader=plain_shader },
            { vao=textured_vao, vbo=textured_vbo, shader=textured_shader },
        },
    }
    return window, renderer
}

renderer_draw_instance :: proc(renderer: $T/Renderer, camera: Camera, instance: ^Instance) {
    data := instance_data(camera, instance^)
    defer delete(data)

    shader: u32
    vao: u32
    vbo: u32
    switch &tex_data in instance.texture_data {
        case TextureData:
            shader = renderer.modes[RenderMode.Textured].shader
            vao = renderer.modes[RenderMode.Textured].vao
            vbo = renderer.modes[RenderMode.Textured].vbo
            gl.UseProgram(shader)
            for &tex, i in tex_data.textures {
                if tex_id, ok := tex.id.(u32); !ok {
                    img, err := png.load_from_file(tex.filename)
                    assert(err == nil)
                    assert(image.alpha_drop_if_present(img))

                    tex.id = 0
                    gl.GenTextures(1, &tex.id.(u32))
                    gl.BindTexture(gl.TEXTURE_2D, tex.id.(u32))
                    gl.TexImage2D(
                        gl.TEXTURE_2D, 0, gl.RGB, 
                        i32(img.width), i32(img.height), 0,
                        gl.RGB, gl.UNSIGNED_BYTE, raw_data(bytes.buffer_to_bytes(&img.pixels)),
                    )
                    gl.GenerateMipmap(gl.TEXTURE_2D);
                } 
                gl.ActiveTexture(gl.TEXTURE0 + u32(i))
                gl.BindTexture(gl.TEXTURE_2D, tex.id.(u32)) 
            }
        case:
            shader = renderer.modes[RenderMode.Plain].shader
            vao = renderer.modes[RenderMode.Plain].vao
            vbo = renderer.modes[RenderMode.Plain].vbo
            gl.UseProgram(shader)
    }

    // gl.EnableVertexAttribArray(0)
    // gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, 8 * size_of(f32), 0)
    // gl.EnableVertexAttribArray(1)
    // gl.VertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, 8 * size_of(f32), 3 * size_of(f32))
    // gl.EnableVertexAttribArray(2)
    // gl.VertexAttribPointer(2, 2, gl.FLOAT, gl.FALSE, 8 * size_of(f32), 6 * size_of(f32))
    shader_set_uniform_matrix4(shader, "model", instance.model_matrix)
    shader_set_uniform_matrix3(shader, "normal_matrix", instance.normal_matrix)
    shader_set_uniform_matrix4(shader, "view", camera.camera_matrix)
    shader_set_uniform_matrix4(shader, "projection", camera.projection_matrix)
    shader_set_uniform_vec4(shader, "light_color", 1) 
    shader_set_uniform_vec3(shader, "light_position", Vec3{0, 2, 0})
    shader_set_uniform_vec3(shader, "viewer_position", camera.transform.position)
    if _, textured := instance.texture_data.(TextureData); !textured {
        shader_set_uniform_vec3(shader, "object_color", instance.color)
    }
    
    gl.BindVertexArray(vao)
    gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
    gl.BufferData(gl.ARRAY_BUFFER, size_of(f32) * len(data), raw_data(data[:]), gl.DYNAMIC_DRAW)
    gl.BufferData(
        gl.ELEMENT_ARRAY_BUFFER,
        size_of(u32) * len(instance.indices),
        raw_data(instance.indices[:]),
        gl.DYNAMIC_DRAW,
    )
    gl.DrawElements(gl.TRIANGLES, cast(i32) len(instance.indices), gl.UNSIGNED_INT, nil)
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
            position = Vec3{0, 5, 25},
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
            position = Vec3{-10, 0, 0},
            rotation = linalg.MATRIX3F32_IDENTITY,
        },
    }
    instance2 := Instance {
        model = UNIT_CUBE,
        scale = 1,
        transform = Transform {
            position = Vec3{0, 1, 0},
            rotation = linalg.MATRIX3F32_IDENTITY,
        },
        color = Vec3{1, 0, 0},
    }
    instance_update(&instance1)
    instance_update(&instance2)

    increment: f32 = 0
    angle: f32 = 0
    prev_key_state: map[i32]i32
    prev_mouse_pos: Vec2
    pitch, yaw: f32
    mouse_sensitivity:f32 = 0.01
    for !glfw.WindowShouldClose(window) { // Render
        // Game logic
        angle += increment
        instance1.transform.rotation = linalg.matrix3_from_euler_angle_x(angle)
        instance_update(&instance1)

        // Input
        e_state := glfw.GetKey(window, glfw.KEY_E)
        if e_state == glfw.PRESS && prev_key_state[glfw.KEY_E] == glfw.RELEASE {
            increment *= -1
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
        renderer_draw_instance(renderer, camera, &instance2)
        glfw.SwapBuffers(window)
        
        glfw.PollEvents()
    }
}
