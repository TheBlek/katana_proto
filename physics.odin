package main

import "core:math/linalg"
import "core:math"
import "core:fmt"

PhysicsData :: struct {
    models: ^[dynamic]Model,
    aabbs: [dynamic]AABB,
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
    normal: Vec3,
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
    instrument_proc(.PhysicsConversion)
    return { from, linalg.normalize(to - from) }
}

plane_from_triangle :: proc(using t: Triangle) -> (p: Plane) {
    instrument_proc(.PhysicsConversion)
    p.normal = normal
    p.d = -linalg.dot(p.normal, points[0])
    return
}

plane_normalized_from_triangle :: proc(using t: Triangle) -> (p: Plane) {
    instrument_proc(.PhysicsConversion)
    p.normal = linalg.normalize(normal)
    p.d = -linalg.dot(p.normal, points[0])
    return
}

aabb_from_instance :: proc(cache: PhysicsData, using instance: Instance) -> AABB {
    instrument_proc(.PhysicsConversion)
    minimal: Vec3 = math.F32_MAX 
    maximal: Vec3
    
    for vertex in cache.models[model_id].vertices {
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
    instrument_proc(.PhysicsCollisionTest)
    center := (b.maximal + b.minimal) / 2;
    length := (b.maximal - b.minimal) / 2;

    r := length.x * abs(a.normal.x) + length.y * abs(a.normal.y) + length.z * abs(a.normal.z)
    dist := linalg.dot(a.normal, center) + a.d
    return abs(dist) <= r
}

collide_triangle_aabb :: proc(a: Triangle, b: AABB) -> bool {
    instrument_proc(.PhysicsCollisionTest)
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
    instrument_proc(.PhysicsCollisionTest)
    return aabb_closest_point_dist2(b, a.center) <= a.radius * a.radius
}

collide_sphere_sphere :: proc(a, b: Sphere) -> bool {
    instrument_proc(.PhysicsCollisionTest)
    return linalg.length2(a.center - b.center) <= (a.radius + b.radius) * (a.radius + b.radius)
}

collide_aabb_aabb :: proc(a, b: AABB) -> bool {
    instrument_proc(.PhysicsCollisionTest)
    a_min := a.minimal 
    a_max := a.maximal
    
    b_min := b.minimal 
    b_max := b.maximal
    return a_max.x >= b_min.x && b_max.x >= a_min.x &&
        a_max.y >= b_min.y && b_max.y >= a_min.y &&
        a_max.z >= b_min.z && b_max.z >= a_min.z
}

exists_triangle :: proc { exists_triangle_cache, exists_triangle_no_cache }

exists_triangle_cache :: proc(
    cache: PhysicsData,
    a: Instance,
    condition: proc(PhysicsData, Triangle, $T) -> bool,
    data: T,
) -> bool {
    model := &cache.models[a.model_id]
    triangle_count := len(model.indices) / 3
    for i in 0..<triangle_count {
        triangle := Triangle {
            {
                (a.model_matrix * vec4_from_vec3(model.vertices[model.indices[3 * i]], 1)).xyz,
                (a.model_matrix * vec4_from_vec3(model.vertices[model.indices[3 * i + 1]], 1)).xyz,
                (a.model_matrix * vec4_from_vec3(model.vertices[model.indices[3 * i + 2]], 1)).xyz,
            },
            a.normal_matrix * model.normals[model.indices[3 * i]],
        }
        if condition(cache, triangle, data) {
            return true
        }
    }
    return false
}

exists_triangle_no_cache :: proc(
    cache: PhysicsData,
    a: Instance,
    condition: proc(Triangle, $T) -> bool,
    data: T,
) -> bool {
    model := &cache.models[a.model_id]
    triangle_count := len(model.indices) / 3
    for i in 0..<triangle_count {
        triangle := Triangle {
            {
                (a.model_matrix * vec4_from_vec3(model.vertices[model.indices[3 * i]], 1)).xyz,
                (a.model_matrix * vec4_from_vec3(model.vertices[model.indices[3 * i + 1]], 1)).xyz,
                (a.model_matrix * vec4_from_vec3(model.vertices[model.indices[3 * i + 2]], 1)).xyz,
            },
            a.normal_matrix * model.normals[model.indices[3 * i]],
        }
        if condition(triangle, data) {
            return true
        }
    }
    return false
}

collide_instance_aabb :: proc(cache: PhysicsData, a: Instance, b: AABB) -> bool {
    instrument_proc(.PhysicsCollisionTest)
    if !collide_aabb_aabb(b, cache.aabbs[a.instance_id]) {
        return false
    }
    return exists_triangle(cache, a, collide_triangle_aabb, b)
}

collide_triangle_triangle :: proc(a, b: Triangle) -> bool {
    instrument_proc(.PhysicsCollisionTest)
    // Small normals can cause robustness problems
    a_plane := plane_normalized_from_triangle(a)
    sdistb := [3]f32 {
        linalg.dot(a_plane.normal, b.points[0]) + a_plane.d,
        linalg.dot(a_plane.normal, b.points[1]) + a_plane.d,
        linalg.dot(a_plane.normal, b.points[2]) + a_plane.d,
    }
    // Precision problems. Floating point arithmetic
    if abs(sdistb[0]) < EPS && abs(sdistb[1]) < EPS && abs(sdistb[2]) < EPS {
        panic("Coplanar case is not handled")
    }
    if sdistb[0] * sdistb[1] > 0 && sdistb[1] * sdistb[2] > 0 { 
        return false
    }
    // Small normals can cause robustness problems
    b_plane := plane_normalized_from_triangle(b)
    sdist := [3]f32 {
        linalg.dot(b_plane.normal, a.points[0]) + b_plane.d,
        linalg.dot(b_plane.normal, a.points[1]) + b_plane.d,
        linalg.dot(b_plane.normal, a.points[2]) + b_plane.d,
    }
    // Precision problems. Floating point arithmetic
    if abs(sdist[0]) < EPS && abs(sdist[1]) < EPS && abs(sdist[2]) < EPS {
        panic("Coplanar case is not handled")
    }
    if sdist[0] * sdist[1] > 0 && sdist[1] * sdist[2] > 0 { 
        return false
    }

    intersection_dir := linalg.cross(a_plane.normal, b_plane.normal)
    projection_index: int
    max_axis := max(abs(intersection_dir.x), abs(intersection_dir.y), abs(intersection_dir.z))
    if max_axis == abs(intersection_dir.x) {
        projection_index = 0
    } else if max_axis == abs(intersection_dir.y) {
        projection_index = 1
    } else {
        projection_index = 2
    }
    
    find_interval :: proc(sdist: [3]f32, points: [3]Vec3, projection_index: int) -> (t1, t2: f32) {
        other_side_vertex: int = 1
        one_side_vertices: [2]int = {0, 2}
        if sdist[0] * sdist[1] > 0 {
            other_side_vertex = 2
            one_side_vertices[1] = 1
        } else if sdist[1] * sdist[2] > 0 {
            other_side_vertex = 0
            one_side_vertices[0] = 1
        }

        proj := [3]f32{ 
            points[0][projection_index],
            points[1][projection_index],
            points[2][projection_index],
        }
        v := one_side_vertices[0]
        t1 = proj[v] + (proj[other_side_vertex] - proj[v]) * sdist[v] / (sdist[v] - sdist[other_side_vertex])
        v = one_side_vertices[1]
        t2 = proj[v] + (proj[other_side_vertex] - proj[v]) * sdist[v] / (sdist[v] - sdist[other_side_vertex])
        return
    }
    t1, t2 := find_interval(sdist, a.points, projection_index)
    t3, t4 := find_interval(sdistb, b.points, projection_index)

    return (max(t1, t2) > t3 && t3 > min(t1, t2)) || (max(t1, t2) > t4 && t4 > min(t1, t2))
}

collide_instance_triangle :: proc(cache: PhysicsData, a: Instance, b: Triangle) -> bool {
    instrument_proc(.PhysicsCollisionTest)
    if !collide_triangle_aabb(b, cache.aabbs[a.instance_id]) {
        return false
    }

    return exists_triangle(cache, a, collide_triangle_triangle, b)
}

collide_triangle_instance :: proc(cache: PhysicsData, a: Triangle, b: Instance) -> bool {
    return collide_instance_triangle(cache, b, a)
}

collide_instance_instance :: proc(cache: PhysicsData, a, b: Instance) -> bool {
    instrument_proc(.PhysicsCollisionTest)
    if !collide_aabb_aabb(cache.aabbs[a.instance_id], cache.aabbs[b.instance_id]) {
        return false
    }

    return exists_triangle(cache, a, collide_triangle_instance, b)
}

collide_instance_instance_partitioned :: proc(
    cache: PhysicsData,
    a, b: Instance,
    b_grid: PartitionGrid,
) -> bool {
    instrument_proc(.PhysicsCollisionTest)
    if !collide_aabb_aabb(cache.aabbs[a.instance_id], cache.aabbs[b.instance_id]) {
        return false
    }

    low_corner := Vec3 {
        -f32(b_grid.grid_size.x) * b_grid.cell_size / 2, 
        -f32(b_grid.grid_size.y) * b_grid.cell_size / 2, 
        -f32(b_grid.grid_size.z) * b_grid.cell_size / 2,
    }
    for x in 0..<b_grid.grid_size.x {
        for y in 0..<b_grid.grid_size.y {
            aabb := AABB { 
                maximal=low_corner + Vec3{f32(x+1), f32(y+1), f32(math.F32_MAX)} * b_grid.cell_size,
                minimal=low_corner + Vec3{f32(x), f32(y), f32(math.F32_MIN)} * b_grid.cell_size,
            }
            if collide_instance_aabb(cache, a, aabb) {
                model := &cache.models[b.model_id]
                for i in b_grid.triangle_ids[x][y] {
                    triangle := Triangle {
                        {
                            (b.model_matrix * vec4_from_vec3(model.vertices[model.indices[3 * i]], 1)).xyz,
                            (b.model_matrix * vec4_from_vec3(model.vertices[model.indices[3 * i + 1]], 1)).xyz,
                            (b.model_matrix * vec4_from_vec3(model.vertices[model.indices[3 * i + 2]], 1)).xyz,
                        },
                        b.normal_matrix * model.normals[model.indices[3 * i]],
                    }
                    if collide_instance_triangle(cache, a, triangle) {
                        return true
                    }
                }
            }
        }
    }
    return false
}

collide_ray_sphere :: proc(ray: Ray, sphere: Sphere) -> bool {
    instrument_proc(.PhysicsCollisionTest)
    centered_origin := ray.origin - sphere.center 
    // Coeffs of quadratic equation
    b := linalg.dot(ray.direction, centered_origin)
    c := linalg.dot(centered_origin, centered_origin) - sphere.radius * sphere.radius
    // If origin is outside sphere and ray pointing away
    if c > 0 && b > 0 {
        return false
    }
    
    discr := b*b - c
    return discr >= 0
}

collide_ray_aabb :: proc(ray: Ray, aabb: AABB) -> bool {
    instrument_proc(.PhysicsCollisionTest)
    tmin:f32 = 0
    tmax:f32 = math.F32_MAX
    for i in 0..<3 {
        if abs(ray.direction[i]) < EPS {
            if ray.origin[i] < aabb.minimal[i] || ray.origin[i] > aabb.maximal[i] {
                return false
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
            return false
        }
    }

    return true
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
    collide_instance_instance,
    collide_instance_instance_partitioned,
    collide_ray_sphere,
    collide_ray_aabb,
}

collision :: proc{ 
    collision_ray_aabb,
    collision_ray_sphere,
    collision_ray_triangle,
    collision_ray_instance,
}

collision_ray_sphere :: proc(ray: Ray, sphere: Sphere) -> Maybe(Vec3) {
    instrument_proc(.PhysicsCollision)
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
    instrument_proc(.PhysicsCollision)
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

collision_ray_triangle :: proc(using ray: Ray, using t: Triangle) -> Maybe(Vec3) {
    instrument_proc(.PhysicsCollision)
    d := linalg.dot(-direction, normal)

    if d <= 0 {
        return nil
    }

    ap := origin - points[0]
    t := linalg.dot(ap, normal)
    if t < 0 {
        return nil
    }

    ac := points[2] - points[0]
    ed := linalg.cross(-direction, ap)
    v := linalg.dot(ac, ed)
    if v < 0 || v > d {
        return nil
    }
    ab := points[1] - points[0]
    w := -linalg.dot(ab, ed)
    if w < 0 || v + w > d {
        return nil
    }
    // This may cause some problems
    // assert(linalg.dot(linalg.cross(ab, ac), normal) < 0)
    return origin + (t / d) * direction
}

collision_ray_instance :: proc(data: PhysicsData, a: Ray, b: Instance) -> Maybe(Vec3) {
    if !collide(a, data.aabbs[b.instance_id]) {
       return nil 
    }
    model := data.models[b.model_id]
    triangle_count := len(model.indices) / 3
    for i in 0..<triangle_count {
        m_mat := b.model_matrix
        n_mat := b.normal_matrix
        triangle := Triangle {
            {
                (m_mat * vec4_from_vec3(model.vertices[model.indices[3 * i + 1]], 1)).xyz,
                (m_mat * vec4_from_vec3(model.vertices[model.indices[3 * i + 2]], 1)).xyz,
                (m_mat * vec4_from_vec3(model.vertices[model.indices[3 * i + 3]], 1)).xyz,
            },
            n_mat * model.normals[model.indices[3 * i]],
        }
        if point, ok := collision(a, triangle).(Vec3); ok {
            return point
        }
    }
    return nil
}

PartitionGrid :: struct {
    cell_size: f32,
    grid_size: [3]int,
    triangle_ids: [][][dynamic]int,
}

partition_grid_from_instance :: proc(
    cache: PhysicsData,
    cell_size: f32,
    grid_size: [3]int,
    instance: Instance,
) -> (grid: PartitionGrid) {
    grid.cell_size = cell_size
    grid.grid_size = grid_size

    grid.triangle_ids = make([][][dynamic]int, grid_size.x)
    for i in 0..<grid_size.x {
        grid.triangle_ids[i] = make([][dynamic]int, grid_size.y)
    }
    // get grid cell by coordinates, test it and all surrounding

    test_grid_cell :: proc(i: int, t: Triangle, grid: PartitionGrid, x, y: int, depth: int) {
        if x < 0 || x >= grid.grid_size.x || y < 0 || y >= grid.grid_size.y {
            return
        }

        low_corner := Vec3 {
            -f32(grid.grid_size.x) * grid.cell_size / 2, 
            -f32(grid.grid_size.y) * grid.cell_size / 2, 
            -f32(grid.grid_size.z) * grid.cell_size / 2,
        }
     
        aabb := AABB { 
            maximal=low_corner + Vec3{f32(x+1), f32(y+1), f32(math.F32_MAX)} * grid.cell_size,
            minimal=low_corner + Vec3{f32(x), f32(y), f32(math.F32_MIN)} * grid.cell_size,
        }

        if collide(t, aabb) {
            append(&grid.triangle_ids[x][y], i)
        }

        if depth == 1 {
            return
        }

        moves := [][2]int{
            {1, 0},
            {-1, 0},
            {0, 1},
            {0, -1},
            {1, 1},
            {-1, 1},
            {1, -1},
            {-1, -1},
        }
        for move in moves {
            test_grid_cell(i, t, grid, x + move.x, y + move.y, depth - 1)
        }
    }

    model := &cache.models[instance.model_id]
    triangle_count := len(model.indices) / 3
    low_corner := Vec3 {
        -f32(grid.grid_size.x) * grid.cell_size / 2, 
        -f32(grid.grid_size.y) * grid.cell_size / 2, 
        -f32(grid.grid_size.z) * grid.cell_size / 2,
    }
    for i in 0..<triangle_count {
        mat := instance.model_matrix
        triangle := Triangle {
            {
                (mat * vec4_from_vec3(model.vertices[model.indices[3 * i]], 1)).xyz,
                (mat * vec4_from_vec3(model.vertices[model.indices[3 * i + 1]], 1)).xyz,
                (mat * vec4_from_vec3(model.vertices[model.indices[3 * i + 2]], 1)).xyz,
            },
            instance.normal_matrix * model.normals[model.indices[3 * i]],
        }
        cell := (triangle.points[0].xy - low_corner.xy) / cell_size
        test_grid_cell(i, triangle, grid, cast(int)cell.x, cast(int)cell.y, 1)
        fmt.println("Done {}/{}")
    }
    return
}
