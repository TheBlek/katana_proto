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
Mat3 :: linalg.Matrix3f32

load_shaders :: proc(filepath: string) -> (program: u32, ok := true) {
    data, ok_file := os.read_entire_file(filepath, context.allocator)
    if !ok_file {
        ok = false
        return
    }
    defer delete(data, context.allocator)

    shader := -1 // 0 - vertex shader, 1 - fragment shader

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

Camera :: struct {
    viewport_distance: f32,
    viewport_size: [2]f32,
    position: Vec3,
    rotation: Mat3,
}

project_point :: proc(camera: Camera, global: Vec3) -> Vec2 {
    coeff := camera.viewport_distance / global.z  
    translated := global - camera.position
    local := linalg.matrix3_inverse(camera.rotation) * translated
    viewport := local.xy * coeff 
    viewport /= camera.viewport_size / 2
    return Vec2(viewport)
}

project_points :: proc(camera: Camera, points: []Vec3) -> (data: [dynamic]f32) {
    reserve(&data, len(points) * 2)
    for point in points {
        projected := project_point(camera, point)
        append(&data, ..projected[:])
    }
    return
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

    camera := Camera{
        viewport_distance=1,
        viewport_size={2, 2},
        position=Vec3{},
        rotation=linalg.MATRIX3F32_IDENTITY,
    }

    vertices := []Vec3{
        Vec3{0, 0.5, 2},
        Vec3{0.5, -0.5, 2},
        Vec3{-0.5, -0.5, 3},
    }

    program, ok := load_shaders("plain.shader")
    assert(ok, "Shader error. Aborting") 
    gl.UseProgram(program)

    vertex_buffer: u32
    gl.GenBuffers(1, &vertex_buffer)
    gl.BindBuffer(gl.ARRAY_BUFFER, vertex_buffer)

    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, 2 * size_of(f32), 0)

    increment: f32 = 0.01
    angle: f32 = 0
    for !glfw.WindowShouldClose(window) { // Render
        gl.Clear(gl.COLOR_BUFFER_BIT)

        data := project_points(camera, vertices)
        ptr, _ := mem.slice_to_components(data[:])
        gl.BufferData(gl.ARRAY_BUFFER, 2 * size_of(f32) * len(vertices), ptr, gl.DYNAMIC_DRAW)
        gl.DrawArrays(gl.TRIANGLES, 0, 6)
        glfw.SwapBuffers(window)

        angle += increment
        if abs(angle) > math.PI/2 {
            increment *= -1
            fmt.println("Turned!")
        }
        camera.rotation = linalg.matrix3_from_euler_angle_y(angle)
        /*
        camera.position.y += increment
        if abs(camera.position.y) > 1 {
            increment *= -1
        }
        */
        
        glfw.PollEvents()
        delete(data)
    }
}
