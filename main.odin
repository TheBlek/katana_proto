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

Vec2 :: linalg.Vector2f32
Vec3 :: linalg.Vector3f32
Vec4 :: linalg.Vector4f32
Mat3 :: linalg.Matrix3f32
Mat3x4 :: linalg.Matrix3x4f32
Mat4 :: linalg.Matrix4f32

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

disposition_matrix :: proc(using transform: Transform) -> Mat4 {
    using linalg
    translation := MATRIX4F32_IDENTITY
    translation[3][0] = position.x
    translation[3][1] = position.y
    translation[3][2] = position.z

    homo_rotation := linalg.matrix4_from_matrix3(rotation)
    homo_rotation[3][3] = 1
    return translation * homo_rotation
}

scale_matrix :: proc(scale: Vec3) -> (result: Mat4) {
    result[0][0] = scale.x
    result[1][1] = scale.y
    result[2][2] = scale.z
    result[3][3] = 1
    return 
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

WIDTH :: 720
HEIGHT :: 480

main :: proc() {
    if glfw.Init() == 0 {
        fmt.println("Failed to initialize glfw")
        return
    }
    defer glfw.Terminate()

    window := glfw.CreateWindow(WIDTH, HEIGHT, "Hello world", nil, nil) 
    defer glfw.DestroyWindow(window)

    if window == nil {
        fmt.println("Failed to create window")
        return
    }
    
    glfw.MakeContextCurrent(window)
    glfw.SwapInterval(1)

    gl.load_up_to(4, 6, glfw.gl_set_proc_address)
    gl.Enable(gl.DEPTH_TEST)

    camera := Camera {
        fov = 100,
        transform = Transform {
            rotation = linalg.MATRIX3F32_IDENTITY,
            position = Vec3{0, 0, 10},
        },
        near = 0.1,
        far = 1000,
    }
    {
        using camera
        projection_matrix = calculate_projection_matrix(fov, near, far)
        camera_matrix = linalg.matrix4_inverse(disposition_matrix(transform))
    }

    vertices := []Vec3 {
        Vec3{-0.5, 0.5, 0},
        Vec3{0.5, 0.5, 0},
        Vec3{0.5, -0.5, 0},
        Vec3{-0.5, -0.5, 0},
    }
    indices := []u32{0, 1, 3, 1, 2, 3}

    m, ok_file := model_load_from_file("./resources/katana.gltf")
    assert(ok_file)
    model := Model {
        vertices = vertices,
        indices = indices,
    }
    instance1 := Instance {
        model = m,
        scale = 1,
        transform = Transform {
            position = Vec3{0, 0, -7},
            rotation = linalg.MATRIX3F32_IDENTITY,
        },
        color = Vec4{1, 1, 0, 1},
    }
    instance_update(&instance1)

    program, ok := shader_load_from_combined_file("plain.shader")
    assert(ok, "Shader error. Aborting") 
    gl.UseProgram(program)

    vertex_array_obj: u32
    gl.GenVertexArrays(1, &vertex_array_obj)
    gl.BindVertexArray(vertex_array_obj)
    vertex_buffer_obj: u32
    gl.GenBuffers(1, &vertex_buffer_obj)
    gl.BindBuffer(gl.ARRAY_BUFFER, vertex_buffer_obj)

    element_buffer_obj: u32
    gl.GenBuffers(1, &element_buffer_obj)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, element_buffer_obj)

    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, 6 * size_of(f32), 0)
    gl.EnableVertexAttribArray(1)
    gl.VertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, 6 * size_of(f32), 3 * size_of(f32))
    gl.BindVertexArray(0) // Unbind effectively

    increment: f32 = 0.01
    angle: f32 = 0
    for !glfw.WindowShouldClose(window) { // Render
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
        gl.BindVertexArray(vertex_array_obj)
        instance_render(camera, instance1, program)
        glfw.SwapBuffers(window)

        angle += increment
        if abs(angle) > math.PI/2 - 0.01 {
            increment *= -1
            // fmt.println("Turned!")
        }
        // {
        //     using camera
        //     transform.rotation = linalg.matrix3_from_euler_angle_y(angle)
        //     camera_matrix = linalg.matrix4_inverse(disposition_matrix(transform))
        // }
        instance1.transform.rotation = linalg.matrix3_from_euler_angle_y(angle)
        instance_update(&instance1)
        
        glfw.PollEvents()
    }
}
