package main

import "core:fmt"
import "core:mem"
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

vec4_from_vec3 :: proc(vec: Vec3, w: f32) -> Vec4 {
    return {vec.x, vec.y, vec.z, w}
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

Sphere :: struct {
    center: Vec3,
    radius: f32,
}

AABB :: struct {
    maximal: Vec3,
    minimal: Vec3,
}

Triangle :: struct {
    points: [3]Vec3,
}

Plane :: struct {
    normal: Vec3,
    d: f32,
}

plane_from_triangle :: proc(using t: Triangle) -> (p: Plane) {
    using linalg
    p.normal = cross(points[1] - points[0], points[2] - points[1])
    p.d = dot(p.normal, points[0])
    return
}

aabb_from_instance :: proc(using instance: Instance) -> AABB {
    minimal: Vec3 = math.F32_MAX 
    maximal: Vec3
    
    for vertex in model.vertices {
        global := model_matrix * Vec4{vertex.x, vertex.y, vertex.z, 1}
        for i in 0..<3 {
            minimal[i] = min(minimal[i], global[i])
            maximal[i] = max(maximal[i], global[i])
        }
    }
    return AABB { maximal, minimal } 
}

aabb_closest_point :: proc(aabb: AABB, point: Vec3) -> Vec3 {
    result := point
    for i in 0..<3 {
        result[i] = clamp(result[i], aabb.minimal[i], aabb.maximal[i])
    }
    return result
}

aabb_closest_point_dist2 :: proc(aabb: AABB, point: Vec3) -> f32 {
    result: f32 = 0
    for i in 0..<3 {
        if point[i] < aabb.minimal[i] {
            result += (point[i] - aabb.minimal[i]) * (point[i] - aabb.minimal[i])
        }
        if point[i] > aabb.maximal[i] {
            result += (aabb.maximal[i] - point[i]) * (aabb.maximal[i] - point[i])
        }
    }
    return result
}

collide_plane_aabb :: proc(a: Plane, b: AABB) -> bool {
    center := (b.maximal + b.minimal) / 2;
    length := (b.maximal - b.minimal) / 2;

    r := length.x * abs(a.normal.x) + length.y * abs(a.normal.y) + length.z * abs(a.normal.z)
    dist := linalg.dot(a.normal, center) - a.d
    return abs(dist) <= r
}

collide_triangle_aabb :: proc(a: Triangle, b: AABB) -> bool {
    center := (b.maximal + b.minimal) / 2;
    length := (b.maximal - b.minimal) / 2;

    points := [3]Vec3{a.points[0] - center, a.points[1] - center, a.points[2] - center}
    edges := [3]Vec3{points[1] - points[0], points[2] - points[1], points[0] - points[2]}

    // a00 - a02
    for i in 0..<3 {
        r := length.y * abs(edges[i].z) + length.z * abs(edges[i].y)
        p1 := -points[(2 + i) % 3].y * edges[i].z + points[(2 + i) % 3].z * edges[i].y
        p2 := -points[(3 + i) % 3].y * edges[i].z + points[(3 + i) % 3].z * edges[i].y
        if max(p1, p2) < -r || min(p1, p2) > r { // Separating axis found
            return false
        }
    }
    
    // a10 - a12
    for i in 0..<3 {
        r := length.x * abs(edges[i].z) + length.z * abs(edges[i].x)
        p1 := points[(2 + i) % 3].x * edges[i].z - points[(2 + i) % 3].z * edges[i].x
        p2 := points[(3 + i) % 3].x * edges[i].z - points[(3 + i) % 3].z * edges[i].x
        if max(p1, p2) < -r || min(p1, p2) > r { // Separating axis found
            return false
        }
    }

    // a20 - a22
    for i in 0..<3 {
        r := length.x * abs(edges[i].y) + length.y * abs(edges[i].x)
        p1 := -points[(2 + i) % 3].x * edges[i].y + points[(2 + i) % 3].y * edges[i].x
        p2 := -points[(3 + i) % 3].x * edges[i].y + points[(3 + i) % 3].y * edges[i].x
        if max(p1, p2) < -r || min(p1, p2) > r { // Separating axis found
            return false
        }
    }

    // AABB of a triangle test
    for i in 0..<3 {
        if max(points[0][i], points[1][i], points[2][i]) < -length[i] ||
            min(points[0][i], points[1][i], points[2][i]) > length[i] {
            return false
        }
    }

    return collide_plane_aabb(plane_from_triangle(a), b)
}

collide_sphere_aabb :: proc(a: Sphere, b: AABB) -> bool {
    return aabb_closest_point_dist2(b, a.center) <= a.radius * a.radius
}

collide_sphere_sphere :: proc(a, b: Sphere) -> bool {
    return linalg.length2(a.center - b.center) <= (a.radius + b.radius) * (a.radius + b.radius)
}

collide_aabb_aabb :: proc(a, b: AABB) -> bool {
    a_min := a.minimal 
    a_max := a.maximal
    
    b_min := b.minimal 
    b_max := b.maximal
    return a_max.x >= b_min.x && b_max.x >= a_min.x &&
        a_max.y >= b_min.y && b_max.y >= a_min.y &&
        a_max.z >= b_min.z && b_max.z >= a_min.z
}

collide_instance_aabb :: proc(a: Instance, b: AABB) -> bool {
    if !collide(b, aabb_from_instance(a)) {
        return false
    }

    triangle_count := len(a.indices) / 3
    for i in 0..<triangle_count {
        triangle := Triangle {
            {
                (a.model_matrix * vec4_from_vec3(a.vertices[a.indices[3 * i]], 1)).xyz,
                (a.model_matrix * vec4_from_vec3(a.vertices[a.indices[3 * i + 1]], 1)).xyz,
                (a.model_matrix * vec4_from_vec3(a.vertices[a.indices[3 * i + 2]], 1)).xyz,
            }
        }
        if collide(triangle, b) {
            return true
        }
    }
    return false
}

collide_triangle_triangle :: proc(a, b: Triangle) -> bool {
    using linalg
    eps: f32 = 0.001
    a_plane := plane_from_triangle(a)
    // Small normals can cause robustness problems
    a_plane.normal = normalize(a_plane.normal)
    sdist: [3]f32
    sdist[0] = dot(a_plane.normal, b.points[0]) - a_plane.d
    sdist[1] = dot(a_plane.normal, b.points[1]) - a_plane.d
    sdist[2] = dot(a_plane.normal, b.points[2]) - a_plane.d 
    // Precision problems. Floating point arithmetic
    if abs(sdist[0]) < eps && abs(sdist[1]) < eps && abs(sdist[2]) < eps {
        panic("Coplanar case is not handled")
    }
    if sdist[0] * sdist[1] > 0 && sdist[1] * sdist[2] > 0 { 
        return false
    }
    b_plane := plane_from_triangle(b)
    // Small normals can cause robustness problems
    b_plane.normal = normalize(b_plane.normal)

    sdistb: [3]f32
    sdistb[0] = dot(b_plane.normal, a.points[0]) - b_plane.d
    sdistb[1] = dot(b_plane.normal, a.points[1]) - b_plane.d
    sdistb[2] = dot(b_plane.normal, a.points[2]) - b_plane.d 
    // Precision problems. Floating point arithmetic
    if abs(sdistb[0]) < eps && abs(sdistb[1]) < eps && abs(sdistb[2]) < eps {
        panic("Coplanar case is not handled")
    }
    if sdistb[0] * sdistb[1] > 0 && sdistb[1] * sdistb[2] > 0 { 
        return false
    }

    intersection_dir := cross(a_plane.normal, b_plane.normal)
    projection_index: int
    max_axis := max(abs(intersection_dir.x), abs(intersection_dir.y), abs(intersection_dir.z))
    if max_axis == abs(intersection_dir.x) {
        projection_index = 0
    } else if max_axis == abs(intersection_dir.y) {
        projection_index = 1
    } else {
        projection_index = 2
    }
    t1, t2: f32
    {
        other_side_vertex: int
        one_side_vertices: [2]int 
        if sdist[0] * sdist[1] > 0 {
            other_side_vertex = 2  
            one_side_vertices = {0, 1}
        } else if sdist[1] * sdist[2] > 0 {
            other_side_vertex = 0
            one_side_vertices = {1, 2}
        } else {
            other_side_vertex = 1
            one_side_vertices = {0, 2}
        }

        proj := [3]f32{ 
            a.points[0][projection_index],
            a.points[1][projection_index],
            a.points[2][projection_index],
        }
        v := one_side_vertices[0]
        t1 = proj[v] + (proj[other_side_vertex] - proj[v]) * sdist[v] * (sdist[v] - sdist[other_side_vertex])
        v = one_side_vertices[1]
        t2 = proj[v] + (proj[other_side_vertex] - proj[v]) * sdist[v] * (sdist[v] - sdist[other_side_vertex])
    }

    t3, t4: f32
    {
        other_side_vertex: int
        one_side_vertices: [2]int
        if sdistb[0] * sdistb[1] > 0 {
            other_side_vertex = 2  
            one_side_vertices = {0, 1}
        } else if sdistb[1] * sdistb[2] > 0 {
            other_side_vertex = 0
            one_side_vertices = {1, 2}
        } else {
            other_side_vertex = 1
            one_side_vertices = {0, 2}
        }

        proj := [3]f32{ 
            b.points[0][projection_index],
            b.points[1][projection_index],
            b.points[2][projection_index],
        }
        v := one_side_vertices[0]
        t3 = proj[v] + (proj[other_side_vertex] - proj[v]) * sdistb[v] * (sdistb[v] - sdistb[other_side_vertex])
        v = one_side_vertices[1]
        t4 = proj[v] + (proj[other_side_vertex] - proj[v]) * sdistb[v] * (sdistb[v] - sdistb[other_side_vertex])
    }
    return (max(t1, t2) > t3 && t3 > min(t1, t2)) || (max(t1, t2) > t4 && t4 > min(t1, t2))
}

collide_instance_triangle :: proc(a: Instance, b: Triangle) -> bool {
    if !collide(b, aabb_from_instance(a)) {
        return false
    }

    triangle_count := len(a.indices) / 3
    for i in 0..<triangle_count {
        triangle := Triangle {
            {
                (a.model_matrix * vec4_from_vec3(a.vertices[a.indices[3 * i]], 1)).xyz,
                (a.model_matrix * vec4_from_vec3(a.vertices[a.indices[3 * i + 1]], 1)).xyz,
                (a.model_matrix * vec4_from_vec3(a.vertices[a.indices[3 * i + 2]], 1)).xyz,
            }
        }
        if collide(triangle, b) {
            return true
        }
    }
    return false

}

collide :: proc{ 
    collide_aabb_aabb,
    collide_sphere_sphere,
    collide_sphere_aabb,
    collide_plane_aabb,
    collide_triangle_aabb,
    collide_triangle_triangle,
    collide_instance_aabb,
    collide_instance_triangle,
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
            position = Vec3{0, 10, 25},
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
            position = Vec3{-10, 2, 0},
            rotation = linalg.MATRIX3F32_IDENTITY,
        },
    }
    instance_update(&instance1)
    terrain := Instance {
        model = get_terrain(100, 100, 6, 200, 1),
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

    obj1 := Instance {
        model = UNIT_CAPSULE,
        scale = {1, 1, 1},
        transform = Transform {
            position = {2.2, 15, 0},
            rotation = linalg.MATRIX3F32_IDENTITY,
        },
        color = {1, 0, 0},
    }
    instance_update(&obj1)
    obj2 := Instance {
        model = triangle,
        scale = 1,
        transform = Transform {
            position = {2, 8, -0.8},
            rotation = linalg.MATRIX3F32_IDENTITY,//linalg.matrix3_from_euler_angle_z(f32(linalg.PI) / 4),
        },
        color = {1, 0, 0},
    }
    instance_update(&obj2)

    prev_key_state: map[i32]i32
    prev_mouse_pos: Vec2
    pitch, yaw: f32
    mouse_sensitivity:f32 = 0.01
    gravity_step: f32 = 0.02
    stopwatch: time.Stopwatch
    pause := false
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
            result := collide(obj1, Triangle{verts})
            if !result {
                obj1.transform.position.y -= gravity_step
                instance_update(&obj1)
            }
        }

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
        renderer_draw_instance(renderer, camera, &terrain)
        renderer_draw_instance(renderer, camera, &obj1)
        renderer_draw_instance(renderer, camera, &obj2)
        glfw.SwapBuffers(window)
        
        glfw.PollEvents()
        time.stopwatch_stop(&stopwatch)
        // fmt.println(time.stopwatch_duration(stopwatch))
    }
}
