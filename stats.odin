package main

stats: Stats

Stats :: struct {
   physics: PhysicsStats,
}

PhysicsStats :: struct {
    conversion: PhysicsConversionStats,
    collision: PhysicsCollisionStats,
}

PhysicsConversionStats :: struct {
    plane_from_triangle: int,
    plane_from_triangle_normalized: int,
    aabb_from_instance: int,
    ray_from_points: int,
}

PhysicsCollisionStats :: struct {
    plane_aabb_test: int,
    triangle_aabb_test: int,
    sphere_aabb_test: int,
    sphere_sphere_test: int,
    aabb_aabb_test: int,
    instance_aabb_test: int,
    triangle_triangle_test: int,
    instance_triangle_test: int,
    instance_instance_test: int,
    ray_sphere_test: int,
    ray_aabb_test: int,
    ray_aabb: int,
    ray_sphere: int,
    ray_triangle: int,
}
