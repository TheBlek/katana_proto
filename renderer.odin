package main

import "vendor:glfw"
import gl "vendor:OpenGL"
import "core:image/png"
import "core:image"
import "core:bytes"
import "core:fmt"
import "core:strings"
import "core:math"

Camera :: struct {
    fov: f32,
    near: f32,
    far: f32,
    transform: Transform,
    projection_matrix: Mat4,
    camera_matrix: Mat4,
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

PointLight :: struct {
    position: Vec3,
    strength: f32,
    color: Vec3,

    constant: f32,
    linear: f32,
    quadratic: f32,
}

DirectionalLight :: struct {
    direction: Vec3,
    strength: f32,
    color: Vec3,
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
    dir_light: DirectionalLight,
    point_lights: [dynamic]PointLight,
    models: [dynamic]Model,
}

renderer_destroy :: proc(window: glfw.WindowHandle, _: Renderer(2)) {
    glfw.Terminate()
    glfw.DestroyWindow(window)
}

instance_data :: proc(renderer: ^$T/Renderer, using camera: Camera, instance: Instance) -> (data: [dynamic]f32) {
    instrument_proc(.Render)
    model := &models[instance.model_id]
    reserve(&data, 3*len(model.vertices))

    assert(
        len(model.vertices) == len(model.normals),
        "Normals do not correspond with vertices correctly",
    )

    if texs, exists := model.texture_data.(TextureData); exists {
        assert(
            len(model.vertices) == len(texs.uvs),
            "UVs do not correspond with vertices correctly",
        )
    }

    for i in 0..<len(model.vertices) {
        using model
        append(&data, vertices[i].x, vertices[i].y, vertices[i].z)
        append(&data, normals[i].x, normals[i].y, normals[i].z)
        if t, ok := texture_data.(TextureData); ok {
            append(&data, t.uvs[i].x, t.uvs[i].y)
        }
    }
    return
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
    shader_set_uniform_i32(textured_shader, "u_diffuse", 0)
    shader_set_uniform_i32(textured_shader, "u_specular", 1)

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
        modes = {
            { vao=plain_vao, vbo=plain_vbo, shader=plain_shader },
            { vao=textured_vao, vbo=textured_vbo, shader=textured_shader },
        },
    }
    return window, renderer
}

renderer_draw_instance :: proc(renderer: ^$T/Renderer, camera: Camera, instance: ^Instance) {
    instrument_proc(.Render) 
    data := instance_data(renderer, camera, instance^)
    defer delete(data)

    shader: u32
    vao: u32
    vbo: u32
    switch &tex_data in models[instance.model_id].texture_data {
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

    shader_set_uniform_matrix4(shader, "model", instance.model_matrix)
    shader_set_uniform_matrix3(shader, "normal_matrix", instance.normal_matrix)
    shader_set_uniform_matrix4(shader, "view", camera.camera_matrix)
    shader_set_uniform_matrix4(shader, "projection", camera.projection_matrix)

    shader_set_uniform_vec3(shader, "dir_light.direction", renderer.dir_light.direction)
    shader_set_uniform_vec3(shader, "dir_light.ambient", renderer.dir_light.color * renderer.dir_light.strength)
    shader_set_uniform_vec3(shader, "dir_light.diffuse", renderer.dir_light.color * renderer.dir_light.strength)
    shader_set_uniform_vec3(shader, "dir_light.specular", renderer.dir_light.color * renderer.dir_light.strength)

    shader_set_uniform_i32(shader, "point_light_count", cast(i32)len(renderer.point_lights))
    for source, i in renderer.point_lights {
        name :: proc(i: int, field: string) -> cstring {
            return strings.unsafe_string_to_cstring(fmt.aprintf("point_lights[%d].%s\x00", i, field))
        }
        source := renderer.point_lights[i]
        
        shader_set_uniform_vec3(shader, name(i, "position"), source.position)
        shader_set_uniform_vec3(shader, name(i, "ambient"), source.color * source.strength)
        shader_set_uniform_vec3(shader, name(i, "diffuse"), source.color * source.strength)
        shader_set_uniform_vec3(shader, name(i, "specular"), source.color * source.strength)

        shader_set_uniform_f32(shader, name(i, "constant"), source.constant)
        shader_set_uniform_f32(shader, name(i, "linear"), source.linear)
        shader_set_uniform_f32(shader, name(i, "quadratic"), source.quadratic)
    }

    shader_set_uniform_vec3(shader, "viewer_position", camera.transform.position)
    if _, textured := models[instance.model_id].texture_data.(TextureData); !textured { // this sample is not needed
        shader_set_uniform_vec3(shader, "object_color", instance.color)
    }
    
    model := &models[instance.model_id]
    gl.BindVertexArray(vao)
    gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
    gl.BufferData(gl.ARRAY_BUFFER, size_of(f32) * len(data), raw_data(data[:]), gl.DYNAMIC_DRAW)
    gl.BufferData(
        gl.ELEMENT_ARRAY_BUFFER,
        size_of(u32) * len(model.indices),
        raw_data(model.indices[:]),
        gl.DYNAMIC_DRAW,
    )
    gl.DrawElements(gl.TRIANGLES, cast(i32) len(model.indices), gl.UNSIGNED_INT, nil)
}
