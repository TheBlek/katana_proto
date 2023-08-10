package main

import "core:os"
import "core:strings"
import gl "vendor:OpenGL"

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

shader_set_uniform_i32 :: proc(program: u32, name: cstring, value: i32) {
    location := gl.GetUniformLocation(program, name)
    gl.Uniform1i(location, value)
}

shader_set_uniform_f32 :: proc(program: u32, name: cstring, value: f32) {
    location := gl.GetUniformLocation(program, name)
    gl.Uniform1f(location, value)
}
