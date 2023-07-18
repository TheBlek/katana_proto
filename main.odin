package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:mem"
import "core:math/linalg"
import "core:math"
import "vendor:glfw"
import gl "vendor:OpenGL"

Vec2 :: linalg.Vector2f32
Vec3 :: linalg.Vector3f32
Vec4 :: linalg.Vector4f32
Mat3 :: linalg.Matrix3f32
Mat3x4 :: linalg.Matrix3x4f32
Mat4 :: linalg.Matrix4f32

load_shaders :: proc(filepath: string) -> (program: u32, ok := true) {
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

instance_project :: proc(using camera: Camera, instance: Instance) -> (data: [dynamic]f32) {
    reserve(&data, 3*len(instance.vertices))
    for vertex in instance.vertices {
        global := []f32{vertex.x, vertex.y, vertex.z}
        // global := Vec4{vertex.x, vertex.y, vertex.z, 1}
        // viewport := cast(Vec3)(projection_matrix * camera_matrix * instance.model_matrix * global)
        // projected := viewport.xy / viewport.z
        append(&data, ..global)
    }
    return
}

instance_render :: proc(camera: Camera, instance: Instance, shader: u32) {
    data := instance_project(camera, instance)
    defer delete(data)

    gl.PolygonMode(gl.FRONT_AND_BACK, gl.LINE)

    model_location := gl.GetUniformLocation(shader, "model")
    model_flat := matrix_flatten(instance.model_matrix)
    gl.UniformMatrix4fv(
        model_location,
        1,
        gl.FALSE,
        raw_data(model_flat[:]),
    )

    view_location := gl.GetUniformLocation(shader, "view")
    view_flat := matrix_flatten(camera.camera_matrix)
    gl.UniformMatrix4fv(
        view_location,
        1,
        gl.FALSE,
        raw_data(view_flat[:]),
    )

    projection_location := gl.GetUniformLocation(shader, "projection")
    projection_flat := matrix_flatten(camera.projection_matrix)
    gl.UniformMatrix4fv(
        projection_location,
        1,
        gl.FALSE,
        raw_data(projection_flat[:]),
    )

    gl.BufferData(gl.ARRAY_BUFFER, size_of(f32) * len(data), raw_data(data[:]), gl.DYNAMIC_DRAW)
    gl.BufferData(
        gl.ELEMENT_ARRAY_BUFFER,
        size_of(u32) * len(instance.indices),
        raw_data(instance.indices[:]),
        gl.DYNAMIC_DRAW,
    )
    gl.DrawElements(gl.TRIANGLES, cast(i32) len(instance.indices), gl.UNSIGNED_INT, nil)
}

Model :: struct {
    vertices: []Vec3,
    indices: []u32,
}

Instance :: struct {
    using model: Model,
    transform: Transform,
    scale: Vec3,
    model_matrix: Mat4,
}

UNIT_CUBE :: Model {
    vertices = { 
        Vec3{-0.5, -0.5, -0.5},
        Vec3{0.5, -0.5, -0.5},
        Vec3{0.5, -0.5, 0.5},
        Vec3{-0.5, -0.5, 0.5},

        Vec3{-0.5, 0.5, -0.5},
        Vec3{0.5, 0.5, -0.5},
        Vec3{0.5, 0.5, 0.5},
        Vec3{-0.5, 0.5, 0.5},
    },
    indices = {
        // Bottom
        0, 1, 2,
        0, 3, 2,

        // Top
        4, 5, 6,
        4, 7, 6,

        // Back
        0, 1, 5,
        0, 5, 4,

        // Front
        3, 2, 6,
        3, 6, 7,

        // Left
        0, 3, 7,
        0, 4, 7,

        // Right
        1, 2, 6,
        1, 5, 6,
    },
}

UNIT_SPHERE :: Model{vertices = {{0.000, 0.000, -1.000}, {1.000, 0.000, 0.000}, {0.000, 0.000, 1.000}, {-1.000, 0.000, 0.000}, {0.000, -1.000, 0.000}, {0.000, 1.000, 0.000}, {0.707, 0.000, -0.707}, {0.000, 0.707, -0.707}, {0.707, 0.707, 0.000}, {-0.707, 0.000, -0.707}, {-0.707, 0.707, 0.000}, {0.000, -0.707, -0.707}, {0.707, -0.707, 0.000}, {-0.707, -0.707, 0.000}, {0.707, 0.000, 0.707}, {0.000, 0.707, 0.707}, {-0.707, 0.000, 0.707}, {0.000, -0.707, 0.707}, {0.383, 0.000, -0.924}, {0.000, 0.383, -0.924}, {0.408, 0.408, -0.816}, {0.924, 0.000, -0.383}, {0.924, 0.383, 0.000}, {0.816, 0.408, -0.408}, {0.383, 0.924, 0.000}, {0.000, 0.924, -0.383}, {0.408, 0.816, -0.408}, {-0.383, 0.000, -0.924}, {-0.408, 0.408, -0.816}, {-0.924, 0.000, -0.383}, {-0.924, 0.383, 0.000}, {-0.816, 0.408, -0.408}, {-0.383, 0.924, 0.000}, {-0.408, 0.816, -0.408}, {0.000, -0.383, -0.924}, {0.408, -0.408, -0.816}, {0.924, -0.383, 0.000}, {0.816, -0.408, -0.408}, {0.383, -0.924, 0.000}, {0.000, -0.924, -0.383}, {0.408, -0.816, -0.408}, {-0.408, -0.408, -0.816}, {-0.924, -0.383, 0.000}, {-0.816, -0.408, -0.408}, {-0.383, -0.924, 0.000}, {-0.408, -0.816, -0.408}, {0.383, 0.000, 0.924}, {0.000, 0.383, 0.924}, {0.408, 0.408, 0.816}, {0.924, 0.000, 0.383}, {0.816, 0.408, 0.408}, {0.000, 0.924, 0.383}, {0.408, 0.816, 0.408}, {-0.383, 0.000, 0.924}, {-0.408, 0.408, 0.816}, {-0.924, 0.000, 0.383}, {-0.816, 0.408, 0.408}, {-0.408, 0.816, 0.408}, {0.000, -0.383, 0.924}, {0.408, -0.408, 0.816}, {0.816, -0.408, 0.408}, {0.000, -0.924, 0.383}, {0.408, -0.816, 0.408}, {-0.408, -0.408, 0.816}, {-0.816, -0.408, 0.408}, {-0.408, -0.816, 0.408}}, indices = {0, 18, 19, 6, 18, 20, 7, 20, 19, 20, 18, 19, 1, 21, 22, 6, 21, 23, 8, 23, 22, 23, 21, 22, 5, 24, 25, 8, 24, 26, 7, 26, 25, 26, 24, 25, 8, 23, 26, 6, 23, 20, 7, 20, 26, 20, 23, 26, 0, 27, 19, 9, 27, 28, 7, 28, 19, 28, 27, 19, 3, 29, 30, 9, 29, 31, 10, 31, 30, 31, 29, 30, 5, 32, 25, 10, 32, 33, 7, 33, 25, 33, 32, 25, 10, 31, 33, 9, 31, 28, 7, 28, 33, 28, 31, 33, 0, 18, 34, 6, 18, 35, 11, 35, 34, 35, 18, 34, 1, 21, 36, 6, 21, 37, 12, 37, 36, 37, 21, 36, 4, 38, 39, 12, 38, 40, 11, 40, 39, 40, 38, 39, 12, 37, 40, 6, 37, 35, 11, 35, 40, 35, 37, 40, 0, 27, 34, 9, 27, 41, 11, 41, 34, 41, 27, 34, 3, 29, 42, 9, 29, 43, 13, 43, 42, 43, 29, 42, 4, 44, 39, 13, 44, 45, 11, 45, 39, 45, 44, 39, 13, 43, 45, 9, 43, 41, 11, 41, 45, 41, 43, 45, 2, 46, 47, 14, 46, 48, 15, 48, 47, 48, 46, 47, 1, 49, 22, 14, 49, 50, 8, 50, 22, 50, 49, 22, 5, 24, 51, 8, 24, 52, 15, 52, 51, 52, 24, 51, 8, 50, 52, 14, 50, 48, 15, 48, 52, 48, 50, 52, 2, 53, 47, 16, 53, 54, 15, 54, 47, 54, 53, 47, 3, 55, 30, 16, 55, 56, 10, 56, 30, 56, 55, 30, 5, 32, 51, 10, 32, 57, 15, 57, 51, 57, 32, 51, 10, 56, 57, 16, 56, 54, 15, 54, 57, 54, 56, 57, 2, 46, 58, 14, 46, 59, 17, 59, 58, 59, 46, 58, 1, 49, 36, 14, 49, 60, 12, 60, 36, 60, 49, 36, 4, 38, 61, 12, 38, 62, 17, 62, 61, 62, 38, 61, 12, 60, 62, 14, 60, 59, 17, 59, 62, 59, 60, 62, 2, 53, 58, 16, 53, 63, 17, 63, 58, 63, 53, 58, 3, 55, 42, 16, 55, 64, 13, 64, 42, 64, 55, 42, 4, 44, 61, 13, 44, 65, 17, 65, 61, 65, 44, 61, 13, 64, 65, 16, 64, 63, 17, 63, 65, 63, 64, 65}}
UNIT_CAPSULE :: Model{vertices = {{0.000, 0.000, -1.000}, {1.000, 0.000, 0.000}, {0.000, 0.000, 1.000}, {-1.000, 0.000, 0.000}, {0.000, -1.000, 0.000}, {0.000, 2.000, 0.000}, {0.707, 0.000, -0.707}, {0.000, 1.707, -0.707}, {0.707, 1.707, 0.000}, {-0.707, 0.000, -0.707}, {-0.707, 1.707, 0.000}, {0.000, -0.707, -0.707}, {0.707, -0.707, 0.000}, {-0.707, -0.707, 0.000}, {0.707, 0.000, 0.707}, {0.000, 1.707, 0.707}, {-0.707, 0.000, 0.707}, {0.000, -0.707, 0.707}, {0.383, 0.000, -0.924}, {0.000, 1.383, -0.924}, {0.408, 1.408, -0.816}, {0.924, 0.000, -0.383}, {0.924, 1.383, 0.000}, {0.816, 1.408, -0.408}, {0.383, 1.924, 0.000}, {0.000, 1.924, -0.383}, {0.408, 1.816, -0.408}, {-0.383, 0.000, -0.924}, {-0.408, 1.408, -0.816}, {-0.924, 0.000, -0.383}, {-0.924, 1.383, 0.000}, {-0.816, 1.408, -0.408}, {-0.383, 1.924, 0.000}, {-0.408, 1.816, -0.408}, {0.000, -0.383, -0.924}, {0.408, -0.408, -0.816}, {0.924, -0.383, 0.000}, {0.816, -0.408, -0.408}, {0.383, -0.924, 0.000}, {0.000, -0.924, -0.383}, {0.408, -0.816, -0.408}, {-0.408, -0.408, -0.816}, {-0.924, -0.383, 0.000}, {-0.816, -0.408, -0.408}, {-0.383, -0.924, 0.000}, {-0.408, -0.816, -0.408}, {0.383, 0.000, 0.924}, {0.000, 1.383, 0.924}, {0.408, 1.408, 0.816}, {0.924, 0.000, 0.383}, {0.816, 1.408, 0.408}, {0.000, 1.924, 0.383}, {0.408, 1.816, 0.408}, {-0.383, 0.000, 0.924}, {-0.408, 1.408, 0.816}, {-0.924, 0.000, 0.383}, {-0.816, 1.408, 0.408}, {-0.408, 1.816, 0.408}, {0.000, -0.383, 0.924}, {0.408, -0.408, 0.816}, {0.816, -0.408, 0.408}, {0.000, -0.924, 0.383}, {0.408, -0.816, 0.408}, {-0.408, -0.408, 0.816}, {-0.816, -0.408, 0.408}, {-0.408, -0.816, 0.408}, {0.000, 1.000, -1.000}, {1.000, 1.000, 0.000}, {0.000, 1.000, 1.000}, {-1.000, 1.000, 0.000}, {0.707, 1.000, -0.707}, {-0.707, 1.000, -0.707}, {0.707, 1.000, 0.707}, {-0.707, 1.000, 0.707}, {0.383, 1.000, -0.924}, {0.924, 1.000, -0.383}, {-0.383, 1.000, -0.924}, {-0.924, 1.000, -0.383}, {0.383, 1.000, 0.924}, {0.924, 1.000, 0.383}, {-0.383, 1.000, 0.924}, {-0.924, 1.000, 0.383}}, indices = {66, 74, 19, 70, 74, 20, 7, 20, 19, 20, 74, 19, 67, 75, 22, 70, 75, 23, 8, 23, 22, 23, 75, 22, 5, 24, 25, 8, 24, 26, 7, 26, 25, 26, 24, 25, 8, 23, 26, 70, 23, 20, 7, 20, 26, 20, 23, 26, 66, 76, 19, 71, 76, 28, 7, 28, 19, 28, 76, 19, 69, 77, 30, 71, 77, 31, 10, 31, 30, 31, 77, 30, 5, 32, 25, 10, 32, 33, 7, 33, 25, 33, 32, 25, 10, 31, 33, 71, 31, 28, 7, 28, 33, 28, 31, 33, 0, 18, 34, 6, 18, 35, 11, 35, 34, 35, 18, 34, 1, 21, 36, 6, 21, 37, 12, 37, 36, 37, 21, 36, 4, 38, 39, 12, 38, 40, 11, 40, 39, 40, 38, 39, 12, 37, 40, 6, 37, 35, 11, 35, 40, 35, 37, 40, 0, 27, 34, 9, 27, 41, 11, 41, 34, 41, 27, 34, 3, 29, 42, 9, 29, 43, 13, 43, 42, 43, 29, 42, 4, 44, 39, 13, 44, 45, 11, 45, 39, 45, 44, 39, 13, 43, 45, 9, 43, 41, 11, 41, 45, 41, 43, 45, 68, 78, 47, 72, 78, 48, 15, 48, 47, 48, 78, 47, 67, 79, 22, 72, 79, 50, 8, 50, 22, 50, 79, 22, 5, 24, 51, 8, 24, 52, 15, 52, 51, 52, 24, 51, 8, 50, 52, 72, 50, 48, 15, 48, 52, 48, 50, 52, 68, 80, 47, 73, 80, 54, 15, 54, 47, 54, 80, 47, 69, 81, 30, 73, 81, 56, 10, 56, 30, 56, 81, 30, 5, 32, 51, 10, 32, 57, 15, 57, 51, 57, 32, 51, 10, 56, 57, 73, 56, 54, 15, 54, 57, 54, 56, 57, 2, 46, 58, 14, 46, 59, 17, 59, 58, 59, 46, 58, 1, 49, 36, 14, 49, 60, 12, 60, 36, 60, 49, 36, 4, 38, 61, 12, 38, 62, 17, 62, 61, 62, 38, 61, 12, 60, 62, 14, 60, 59, 17, 59, 62, 59, 60, 62, 2, 53, 58, 16, 53, 63, 17, 63, 58, 63, 53, 58, 3, 55, 42, 16, 55, 64, 13, 64, 42, 64, 55, 42, 4, 44, 61, 13, 44, 65, 17, 65, 61, 65, 44, 61, 13, 64, 65, 16, 64, 63, 17, 63, 65, 63, 64, 65, 0, 66, 18, 66, 18, 74, 6, 70, 18, 70, 18, 74, 1, 67, 21, 67, 21, 75, 6, 70, 21, 70, 21, 75, 0, 66, 27, 66, 27, 76, 9, 71, 27, 71, 27, 76, 3, 69, 29, 69, 29, 77, 9, 71, 29, 71, 29, 77, 2, 68, 46, 68, 46, 78, 14, 72, 46, 72, 46, 78, 1, 67, 49, 67, 49, 79, 14, 72, 49, 72, 49, 79, 2, 68, 53, 68, 53, 80, 16, 73, 53, 73, 53, 80, 3, 69, 55, 69, 55, 81, 16, 73, 55, 73, 55, 81}}

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

    camera := Camera {
        fov = 70,
        transform = Transform {
            rotation = linalg.MATRIX3F32_IDENTITY,
        },
        near = 0.1,
        far = 100,
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

    model := Model {
        vertices = vertices,
        indices = indices,
    }
    instance1 := Instance {
        model = UNIT_CAPSULE,
        scale = 1,
        transform = Transform {
            position = Vec3{0, -0.5, -5},
            rotation = linalg.MATRIX3F32_IDENTITY,
        },
    }
    fmt.println(get_capsule(2))
    instance1.model_matrix = disposition_matrix(instance1.transform)

    program, ok := load_shaders("plain.shader")
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

    gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, 3 * size_of(f32), 0)
    gl.EnableVertexAttribArray(0)
    gl.BindVertexArray(0) // Unbind effectively

    increment: f32 = 0.01
    angle: f32 = 0
    for !glfw.WindowShouldClose(window) { // Render
        gl.Clear(gl.COLOR_BUFFER_BIT)
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
        {
            using instance1
            transform.rotation = linalg.matrix3_from_euler_angle_y(angle)
            // transform.position.z = -abs(angle) - 1
            model_matrix = disposition_matrix(transform) * scale_matrix(scale)
        }
        
        glfw.PollEvents()
    }
}
