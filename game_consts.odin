package main

import "core:math/linalg"
import "vendor:glfw"

WIDTH :: 1280
HEIGHT :: 720

GRAVITY :: Vec3 {0, -9.81, 0}
PLAYER_HEIGHT :: 1.9
PLAYER_RUN_MULTIPLIER :: 1.5

MOVEMENT_BINDS :: []MovementKeyBind {
    { glfw.KEY_W, Vec3{0, 0, -10} },
    { glfw.KEY_S, Vec3{0, 0, 5} },
    { glfw.KEY_A, Vec3{-3, 0, 0} },
    { glfw.KEY_D, Vec3{3, 0, 0} },
}

KATANA_MOVEMENT_BIND :: glfw.KEY_LEFT_ALT

MOUSE_SENSITIVITY :: 0.001
KATANA_SENSITIVITY :: 0.001
KATANA_ANGLES :: [2][2]f32 {
    {-linalg.PI/2, linalg.PI/2},
    {linalg.PI/2, -linalg.PI/2},
}
KATANA_SPREAD :: [2][2]f32 {
    {-2, 2},
    {-1, 2},
}
KATANA_BASE_POSITION :: Vec3{0, -2, -4}
KATANA_BASE_ROTATION :: matrix[3, 3]f32{
    -0.000, 1.000, 0.000,
    1.000, 0.000, 0.000,
    0.000, 0.000, -1.000,
}
