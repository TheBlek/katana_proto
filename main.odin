package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:mem"
import "vendor:glfw"
import gl "vendor:OpenGL"

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

    vertices := []f32{
        0.0, 0.5,
        0.5, -0.5,
        -0.5, -0.5,
    }
    ptr, _ := mem.slice_to_components(vertices)

    program, ok := load_shaders("plain.shader")
    assert(ok, "Shader error. Aborting") 
    gl.UseProgram(program)

    vertex_buffer: u32
    gl.GenBuffers(1, &vertex_buffer)
    gl.BindBuffer(gl.ARRAY_BUFFER, vertex_buffer)
    gl.BufferData(gl.ARRAY_BUFFER, size_of(f32) * len(vertices), ptr, gl.STATIC_DRAW)

    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, 2 * size_of(f32), 0)

    for !glfw.WindowShouldClose(window) { // Render
        gl.Clear(gl.COLOR_BUFFER_BIT)
        gl.DrawArrays(gl.TRIANGLES, 0, 6)

        glfw.SwapBuffers(window)
        glfw.PollEvents()
    }
}
