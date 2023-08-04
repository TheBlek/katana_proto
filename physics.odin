package main

import "core:math/linalg"
import "core:math"

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

Ray :: struct {
    origin: Vec3,
    direction: Vec3,
}

ray_from_points :: proc(from, to: Vec3) -> Ray {
    return { from, linalg.normalize(to - from) }
}

plane_from_triangle :: proc(using t: Triangle) -> (p: Plane) {
    using linalg
    p.normal = cross(points[1] - points[0], points[2] - points[1])
    p.d = dot(p.normal, points[0])
    return
}

plane_normalized_from_triangle :: proc(using t: Triangle) -> (p: Plane) {
    using linalg
    p.normal = normalize(cross(points[1] - points[0], points[2] - points[1]))
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
    // Small normals can cause robustness problems
    a_plane := plane_normalized_from_triangle(a)
    sdist: [3]f32
    sdist[0] = dot(a_plane.normal, b.points[0]) - a_plane.d
    sdist[1] = dot(a_plane.normal, b.points[1]) - a_plane.d
    sdist[2] = dot(a_plane.normal, b.points[2]) - a_plane.d 
    // Precision problems. Floating point arithmetic
    if abs(sdist[0]) < EPS && abs(sdist[1]) < EPS && abs(sdist[2]) < EPS {
        panic("Coplanar case is not handled")
    }
    if sdist[0] * sdist[1] > 0 && sdist[1] * sdist[2] > 0 { 
        return false
    }
    // Small normals can cause robustness problems
    b_plane := plane_normalized_from_triangle(b)

    sdistb: [3]f32
    sdistb[0] = dot(b_plane.normal, a.points[0]) - b_plane.d
    sdistb[1] = dot(b_plane.normal, a.points[1]) - b_plane.d
    sdistb[2] = dot(b_plane.normal, a.points[2]) - b_plane.d 
    // Precision problems. Floating point arithmetic
    if abs(sdistb[0]) < EPS && abs(sdistb[1]) < EPS && abs(sdistb[2]) < EPS {
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

collision_ray_sphere :: proc(ray: Ray, sphere: Sphere) -> Maybe(Vec3) {
    centered_origin := ray.origin - sphere.center 
    // Coeffs of quadratic equation
    b := linalg.dot(ray.direction, centered_origin)
    c := linalg.dot(centered_origin, centered_origin) - sphere.radius * sphere.radius
    // If origin is outside sphere and ray pointing away
    if c > 0 && b > 0 {
        return nil
    }
    
    discr := b*b - c
    if discr < 0 {
        return nil
    }

    t := -b - math.sqrt(discr)
    if t < 0 {
        t = 0
    }
    return ray.origin + t * ray.direction
}

collision_ray_aabb :: proc(ray: Ray, aabb: AABB) -> Maybe(Vec3) {
    tmin:f32 = 0
    tmax:f32 = math.F32_MAX
    for i in 0..<3 {
        if abs(ray.direction[i]) < EPS {
            if ray.origin[i] < aabb.minimal[i] || ray.origin[i] > aabb.maximal[i] {
                return nil
            }
            continue
        }
        t0 := (aabb.minimal[i] - ray.origin[i]) / ray.direction[i]
        t1 := (aabb.maximal[i] - ray.origin[i]) / ray.direction[i]
        if t0 > t1 {
            t0, t1 = t1, t0
        }
        tmin = max(tmin, t0)
        tmax = min(tmax, t1)
        if tmax < tmin {
            return nil
        }
    }

    return ray.origin + tmin * ray.direction
}

collision :: proc{ collision_ray_aabb, collision_ray_sphere }
