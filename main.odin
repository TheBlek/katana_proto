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
    viewport_size: Vec2,
    transform: Transform,
    projection_matrix: linalg.Matrix3x4f32,
    camera_matrix: linalg.Matrix4f32,
}

inverse_disposition_matrix :: proc(using transform: Transform) -> Mat4 {
    using linalg
    return disposition_matrix(Transform{-position, matrix3_inverse(rotation)})
}

disposition_matrix :: proc(using transform: Transform) -> Mat4 {
    using linalg
    translation := MATRIX4F32_IDENTITY
    translation[3][0] = position.x
    translation[3][1] = position.y
    translation[3][2] = position.z

    homo_rotation := matrix4_from_matrix3(rotation)
    homo_rotation[3][3] = 1
    return homo_rotation * translation
}

calculate_projection_matrix :: proc(using camera: ^Camera) {
    projection_matrix = {}
    projection_matrix[0][0] = viewport_distance / (viewport_size.x / 2)
    projection_matrix[1][1] = viewport_distance / (viewport_size.y / 2)
    projection_matrix[2][2] = 1
}

instance_project :: proc(using camera: Camera, instance: Instance) -> (data: [dynamic]f32) {
    reserve(&data, 2*len(instance.vertices))
    for vertex in instance.vertices {
        global := Vec4{vertex.x, vertex.y, vertex.z, 1}
        viewport := cast(Vec3)(projection_matrix * camera_matrix * instance.model_matrix * global)
        projected := viewport.xy / viewport.z
        append(&data, ..projected[:])
    }
    return
}

instance_render :: proc(camera: Camera, instance: Instance) {
    data := instance_project(camera, instance)
    defer delete(data)
    verts, _ := mem.slice_to_components(data[:])
    ids, _ := mem.slice_to_components(instance.indices[:])
    gl.PolygonMode(gl.FRONT_AND_BACK, gl.LINE)
    gl.BufferData(gl.ARRAY_BUFFER, 2 * size_of(f32) * len(instance.vertices), verts, gl.DYNAMIC_DRAW)
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, size_of(u32) * len(instance.indices), ids, gl.DYNAMIC_DRAW)
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
        viewport_size = {2, 2},
        transform = Transform {
            rotation = linalg.MATRIX3F32_IDENTITY,
        },
    }
    calculate_projection_matrix(&camera)
    camera.camera_matrix = inverse_disposition_matrix(camera.transform)

    vertices := []Vec3 {
        Vec3{-0.5, 0.5, 2},
        Vec3{0.5, 0.5, 2},
        Vec3{0.5, -0.5, 2},
        Vec3{-0.5, -0.5, 2},
    }
    indices := []u32{0, 1, 3, 1, 2, 3}

    model := Model {
        vertices = vertices,
        indices = indices,
    }
    instance1 := Instance {
        model = model,
        transform = Transform {
            rotation = linalg.MATRIX3F32_IDENTITY,
        },
    }
    instance1.model_matrix = disposition_matrix(instance1.transform)
    instance2 := Instance {
        model = model,
        transform = Transform {
            position = Vec3{1, 0, 0},
            rotation = linalg.MATRIX3F32_IDENTITY,
        },
    }
    instance2.model_matrix = disposition_matrix(instance2.transform)

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

    gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, 2 * size_of(f32), 0)
    gl.EnableVertexAttribArray(0)
    gl.BindVertexArray(0) // Unbind effectively

    increment: f32 = 0.01
    angle: f32 = 0
    for !glfw.WindowShouldClose(window) { // Render
        gl.Clear(gl.COLOR_BUFFER_BIT)
        gl.BindVertexArray(vertex_array_obj)
        instance_render(camera, instance1)
        instance_render(camera, instance2)
        glfw.SwapBuffers(window)

        angle += increment
        if abs(angle) > math.PI/2 - 0.01 {
            increment *= -1
            fmt.println("Turned!")
        }
        camera.transform.rotation = linalg.matrix3_from_euler_angle_y(angle)
        camera.camera_matrix = inverse_disposition_matrix(camera.transform)
        
        glfw.PollEvents()
    }
}
