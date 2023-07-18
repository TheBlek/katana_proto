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
    return Model{ vertices[:], indices[:] }
}
