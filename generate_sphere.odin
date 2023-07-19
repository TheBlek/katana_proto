package main

import "core:math"
import "core:math/linalg"
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
    
    // LEAK
    return Model{ vertices=vertices[:], indices=indices[:] }
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

    return Model { vertices=vertices[:], indices=indices[:] }
}
