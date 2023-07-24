package main

import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:slice"
import "core:fmt"

expand_triangles :: proc(vertices: ^[dynamic]Vec3, indices: ^[dynamic]u32) {
    triangle_count := len(indices) / 3

    reserve(indices, len(indices) + triangle_count * 4)
    
    for i in 0..<triangle_count {
        a_i := indices[3 * i]
        b_i := indices[3 * i + 1]
        c_i := indices[3 * i + 2]
        a := vertices[a_i]
        b := vertices[b_i]
        c := vertices[c_i]

        ab := linalg.vector_normalize((a + b) / 2)
        ac := linalg.vector_normalize((a + c) / 2)
        bc := linalg.vector_normalize((b + c) / 2)
        
        ab_i: int
        ac_i: int
        bc_i: int
        ok: bool
        if ab_i, ok = slice.linear_search(vertices[:], ab); !ok {
            ab_i = len(vertices)

            append(vertices, ab)
        }

        if ac_i, ok = slice.linear_search(vertices[:], ac); !ok {
            ac_i = len(vertices)
            append(vertices, ac)
        }

        if bc_i, ok = slice.linear_search(vertices[:], bc); !ok {
            bc_i = len(vertices)
            append(vertices, bc)
        }
        append(indices, u32(a_i), u32(ab_i), u32(ac_i))
        append(indices, u32(b_i), u32(ab_i), u32(bc_i))
        append(indices, u32(c_i), u32(bc_i), u32(ac_i))
        append(indices, u32(bc_i), u32(ab_i), u32(ac_i))
    }

    for i in 0..<triangle_count {
        // We can do unordered bc # of ids is divisible by 3
        ordered_remove(indices, 0)
        ordered_remove(indices, 0)
        ordered_remove(indices, 0)
    }
}

get_sphere :: proc(n: int) -> Model {
    vertices := [dynamic]Vec3{
        Vec3{0, 0, -1},
        Vec3{1, 0, 0},
        Vec3{0, 0, 1},

        Vec3{-1, 0, 0},
        Vec3{0, -1, 0},
        Vec3{0, 1, 0},
    }

    indices := [dynamic]u32{
        0, 1, 5,
        0, 3, 5,
        0, 1, 4,
        0, 3, 4,

        2, 1, 5,
        2, 3, 5,
        2, 1, 4,
        2, 3, 4,
    }

    for i in 0..<n {
        expand_triangles(&vertices, &indices)
    }

    new_vertices, normals, new_indices := generate_normals(vertices[:], indices[:])    
    delete(indices)
    delete(vertices)

    return Model { new_vertices, normals, new_indices, nil }
}

get_capsule :: proc(n: int) -> Model {
    vertices := [dynamic]Vec3{
        Vec3{0, 0, -1},
        Vec3{1, 0, 0},
        Vec3{0, 0, 1},

        Vec3{-1, 0, 0},
        Vec3{0, -1, 0},
        Vec3{0, 1, 0},
    }

    indices := [dynamic]u32{
        0, 1, 5,
        0, 3, 5,
        0, 1, 4,
        0, 3, 4,

        2, 1, 5,
        2, 3, 5,
        2, 1, 4,
        2, 3, 4,
    }

    for i in 0..<n {
        expand_triangles(&vertices, &indices)
    }
    // I couldn't call get_sphere as it returns []T and not [dynamic]T

    equator: [dynamic]u32
    replacement: [dynamic]u32
    vertex_count := len(vertices)
    for i in 0..<vertex_count {
        if vertices[i].y == 0 {
            append(&equator, u32(i))
            append(&replacement, cast(u32) len(vertices))
            append(&vertices, vertices[i])
        }
    }

    triangle_count := len(indices) / 3
    next := 0
    for i in 0..<triangle_count {
        a_i := indices[3 * i]
        b_i := indices[3 * i + 1]
        c_i := indices[3 * i + 2]
        a := vertices[a_i]
        b := vertices[b_i]
        c := vertices[c_i]

        up := a.y > 0 || b.y > 0 || c.y > 0 
        if !up {
            continue
        }

        a_equator: bool
        b_equator: bool
        c_equator: bool
        if j, ok := slice.linear_search(equator[:], a_i); ok {
            indices[3 * i] = replacement[j]
            a_equator = true
        }

        if j, ok := slice.linear_search(equator[:], b_i); ok {
            indices[3 * i + 1] = replacement[j]
            b_equator = true
        }

        if j, ok := slice.linear_search(equator[:], c_i); ok {
            indices[3 * i + 2] = replacement[j]
            c_equator = true
        }

        if u32(a_equator) + u32(b_equator) + u32(c_equator) != 2 {
            continue 
        }

        rect: [dynamic]u32
        reserve(&rect, 4)

        if a_equator {
            append(&rect, a_i, indices[3 * i])
        }

        if b_equator {
            append(&rect, b_i, indices[3 * i + 1])
        }

        if c_equator {
            append(&rect, c_i, indices[3 * i + 2])
        }

        assert(len(rect) == 4)
        append(&indices, rect[0], rect[1], rect[2])
        append(&indices, rect[1], rect[2], rect[3])
    }

    for &v, i in vertices {
        if v.y > 0 || slice.contains(replacement[:], u32(i)) {
            v.y += 1
        }
    }

    new_vertices, normals, new_indices := generate_normals(vertices[:], indices[:])    
    delete(indices)
    delete(vertices)

    return Model { new_vertices, normals, new_indices, nil }
}

generate_normals :: proc(vertices: []Vec3, indices: []u32, sphere := true) -> ([]Vec3, []Vec3, []u32) {
    triangle_count := len(indices) / 3
    new_vertices: [dynamic]Vec3
    normals: [dynamic]Vec3
    new_indices: [dynamic]u32
    for i in 0..<triangle_count {
        a := vertices[indices[3 * i]]
        b := vertices[indices[3 * i + 1]]
        c := vertices[indices[3 * i + 2]]

        raw_normal := linalg.cross(a - b, b - c)
        normal := linalg.normalize(raw_normal * math.sign(linalg.dot(raw_normal, a)))
        if !sphere && normal.y < 0 {
            normal = -normal
        }

        first := cast(u32)len(new_vertices)
        append(&new_indices, first, first + 1, first + 2)
        append(&new_vertices, a, b, c)
        append(&normals, normal, normal, normal)
    }
    return new_vertices[:], normals[:], new_indices[:]
}

@private
grid_vectors: [256]Vec2
@private
grid_step: Vec2

perlin_noise_init :: proc(seed: u64, plain_size: Vec2) {
    grid_step = plain_size / 15
    gen := rand.create(seed)
    for &vec in grid_vectors {
        vec.x = rand.float32(&gen)
        vec.y = rand.float32(&gen)
        vec = linalg.normalize(vec)
    }
}

perlin_noise_get :: proc(point: Vec2) -> f32 {
    grid_pos := linalg.floor(point / grid_step)
    grid_x := int(grid_pos.x) % 15
    grid_y := int(grid_pos.y) % 15

    inner_pos := point / grid_step - grid_pos

    a_vec := grid_vectors[grid_x + grid_y * 16]
    b_vec := grid_vectors[grid_x + 1 + grid_y * 16]
    c_vec := grid_vectors[grid_x + 1 + (grid_y + 1) * 16]
    d_vec := grid_vectors[grid_x + (grid_y + 1) * 16]
     
    a_weight := linalg.dot(a_vec, inner_pos)
    b_weight := linalg.dot(b_vec, inner_pos - Vec2{1, 0})
    c_weight := linalg.dot(c_vec, inner_pos - Vec2{1, 1})
    d_weight := linalg.dot(d_vec, inner_pos - Vec2{0, 1})

    fade :: proc(x: f32) -> f32 {
        return (6*x*x - 15*x + 10)*x*x*x
    }

    u := fade(inner_pos.x)
    v := fade(inner_pos.y)
    value := linalg.lerp(
        linalg.lerp(a_weight, d_weight, v),
        linalg.lerp(b_weight, c_weight, v),
        u,
    )
    return value
}

get_terrain :: proc(width, height, amplitude: f32, segment_count: int, seed: u64) -> Model {
    corner := Vec3{-width/2, 0, -height/2}
    step := Vec3{width, 0, height} / f32(segment_count)
    vertices: [dynamic]Vec3
    vertex_count := segment_count + 1
    reserve(&vertices, vertex_count * vertex_count)

    perlin_noise_init(seed, {4*width, 4*height})
    for i in 0..<vertex_count {
        for j in 0..<vertex_count {
            projection := step * {f32(i), 0, f32(j)}

            octave_count := 4
            frequency: f32 = 2
            persistence: f32 = 0.6
            value: f32
            for k in 0..<octave_count {
                freq := math.pow(frequency, f32(k))
                amp := amplitude *  math.pow(persistence, f32(k))
                value += (perlin_noise_get(projection.xz * freq) + 1) * amp / 2 // bc value is [-1; 1]
            }
            projection.y = value

            append(&vertices, corner + projection)
        }
    }
    
    indices: [dynamic]u32
    reserve(&indices, 6 * segment_count * segment_count)
    for row in 0..<segment_count {
        for column in 0..<segment_count {
            append(
                &indices,
                u32(row * vertex_count + column),
                u32(row * vertex_count + (column + 1)),
                u32((row + 1) * vertex_count + (column + 1)),
            )
            append(
                &indices,
                u32(row * vertex_count + column),
                u32((row + 1) * vertex_count + column),
                u32((row + 1) * vertex_count + (column + 1)),
            )
        }
    }


    new_vertices, normals, new_indices := generate_normals(vertices[:], indices[:], false)    
    delete(indices)
    delete(vertices)

    return Model{ new_vertices, normals, new_indices, nil}
}
