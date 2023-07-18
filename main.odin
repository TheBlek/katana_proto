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
    viewport_distance: f32,
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
    aspect_ratio: f32 = 16 / 9

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
    model_matrix: Mat4,
}

main :: proc() {
    if glfw.Init() == 0 {
        fmt.println("Failed to initialize glfw")
        return
    }
    defer glfw.Terminate()

    window := glfw.CreateWindow(640, 480, "Hello world", nil, nil) 
    defer glfw.DestroyWindow(window)

    if window == nil {
        fmt.println("Failed to create window")
        return
    }
    
    glfw.MakeContextCurrent(window)
    glfw.SwapInterval(1)

    gl.load_up_to(4, 6, glfw.gl_set_proc_address)

    camera := Camera {
        viewport_distance = 1,
        fov = 100,
        transform = Transform {
            rotation = linalg.MATRIX3F32_IDENTITY,
        },
        near = 0.1,
        far = 5,
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
        model = model,
        transform = Transform {
            position = Vec3{0, 0, -2},
            rotation = linalg.MATRIX3F32_IDENTITY,
        },
    }
    instance1.model_matrix = disposition_matrix(instance1.transform)
    // instance2 := Instance {
    //     model = model,
    //     transform = Transform {
    //         position = Vec3{1, 0, 0},
    //         rotation = linalg.MATRIX3F32_IDENTITY,
    //     },
    // }
    // instance2.model_matrix = disposition_matrix(instance2.transform)

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
        // instance_render(camera, instance2, program)
        glfw.SwapBuffers(window)

        angle += increment
        if abs(angle) > math.PI/2 - 0.01 {
            increment *= -1
            fmt.println("Turned!")
        }
        {
            using camera
            transform.rotation = linalg.matrix3_from_euler_angle_y(angle)
            camera_matrix = linalg.matrix4_inverse(disposition_matrix(transform))
        }
        {
            using instance1
            transform.rotation = linalg.matrix3_from_euler_angle_y(angle)
            model_matrix = disposition_matrix(transform)
        }
        
        glfw.PollEvents()
    }
}
