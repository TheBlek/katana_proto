package main
import "core:time"
import "core:fmt"

stats: Stats

Stats :: struct {
   physics: PhysicsStats,
   render: RenderStats,
}

StatType :: enum {
    PhysicsConversion,
    PhysicsCollision,
    PhysicsCollisionTest,
    Render,
}

RenderStats :: struct {
    draw: map[string]ProcedureStats,
}

PhysicsStats :: struct {
    conversion: map[string]ProcedureStats,
    collision: map[string]ProcedureStats,
    collision_test: map[string]ProcedureStats,
}

ProcedureStats :: struct {
    call_count: int,
    total_duration: time.Duration,
}

@(deferred_out=stop_instrument_proc)
instrument_proc :: proc(
    type: StatType,
    loc := #caller_location,
) -> (
    sw: ^time.Stopwatch,
    stat: ^ProcedureStats,
) {
    when INSTRUMENT {
        group: ^map[string]ProcedureStats
        switch type {
            case .PhysicsConversion:
                group = &stats.physics.conversion
            case .PhysicsCollision:
                group = &stats.physics.collision
            case .PhysicsCollisionTest:
                group = &stats.physics.collision_test
            case .Render:
                group = &stats.render.draw
        }
        ok: bool
        if stat, ok = &group[loc.procedure]; ok {
            stat.call_count += 1
        } else {
            group[loc.procedure] = { call_count = 1 }
            stat = &group[loc.procedure]
        }
        sw = new(time.Stopwatch)
        time.stopwatch_start(sw)
    }
    return
}

stop_instrument_proc :: proc(
    sw: ^time.Stopwatch,
    stat: ^ProcedureStats,
) {
    when INSTRUMENT {
        time.stopwatch_stop(sw)
        stat.total_duration += time.stopwatch_duration(sw^)
    }
    return
}
