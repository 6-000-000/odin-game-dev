package main

import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

// =============================================================================
// The playground. Entity "kinds" are COMPOSED by mixing components — there is
// no Comet type, no Blinker type, no inheritance. A kind is just a combination
// of columns. A new kind = a new combination of existing parts.
// =============================================================================

// --- spawn recipes: one per "kind" --------------------------------------------

// Comet: drifts and tumbles forever.  Position + Velocity + Spin
spawn_comet :: proc(world: ^World, pos: rl.Vector2) -> Entity {
	e := spawn_entity(world)
	if !is_alive(world, e) do return e // pool full
	add_position(world, e, pos)
	add_velocity(world, e, random_vel(40, 140))
	add_spin(world, e, rand.float32_range(0, 360), rand.float32_range(-180, 180))
	return e
}

// Blinker: sits still, pulses, dies.  Position + Pulse + Lifetime
spawn_blinker :: proc(world: ^World, pos: rl.Vector2) -> Entity {
	e := spawn_entity(world)
	if !is_alive(world, e) do return e
	add_position(world, e, pos)
	add_pulse(world, e, rand.float32_range(0, 2 * math.PI))
	add_lifetime(world, e, rand.float32_range(2, 5))
	return e
}

// Drifter: drifts, dies.  Position + Velocity + Lifetime
spawn_drifter :: proc(world: ^World, pos: rl.Vector2) -> Entity {
	e := spawn_entity(world)
	if !is_alive(world, e) do return e
	add_position(world, e, pos)
	add_velocity(world, e, random_vel(60, 180))
	add_lifetime(world, e, rand.float32_range(1.5, 4))
	return e
}

// Spinner: sits still, spins forever.  Position + Spin
spawn_spinner :: proc(world: ^World, pos: rl.Vector2) -> Entity {
	e := spawn_entity(world)
	if !is_alive(world, e) do return e
	add_position(world, e, pos)
	add_spin(world, e, 0, rand.float32_range(90, 360))
	return e
}

// A random mix (SPACE): every component rolled independently. The systems don't
// care that no "type" describes these — each system picks off the entities
// carrying the bits it needs.
spawn_random :: proc(world: ^World, pos: rl.Vector2) -> Entity {
	e := spawn_entity(world)
	if !is_alive(world, e) do return e
	add_position(world, e, pos)
	if rand.float32_range(0, 1) < 0.7 do add_velocity(world, e, random_vel(20, 200))
	if rand.float32_range(0, 1) < 0.5 {
		add_spin(world, e, rand.float32_range(0, 360), rand.float32_range(-270, 270))
	}
	if rand.float32_range(0, 1) < 0.4 do add_lifetime(world, e, rand.float32_range(1, 6))
	if rand.float32_range(0, 1) < 0.4 do add_pulse(world, e, rand.float32_range(0, 2 * math.PI))
	return e
}

random_vel :: proc(min_speed, max_speed: f32) -> rl.Vector2 {
	angle := rand.float32_range(0, 2 * math.PI)
	speed := rand.float32_range(min_speed, max_speed)
	return {math.cos(angle), math.sin(angle)} * speed
}

// --- drawing --------------------------------------------------------------------
// What an entity LOOKS LIKE is decided from its mask, not from a type tag:
// the first combo its mask satisfies wins. The systems never see this — a
// moving, pulsing, dying entity is drawn as a blinker and STILL moves, because
// system_move only cares about Position+Velocity.

draw_entities :: proc(world: ^World) {
	for i in 0 ..< world.count {
		if !world.alive[i] do continue
		m := world.masks[i]
		if .Position not_in m do continue // nothing to draw without a position
		pos := world.positions[i]

		switch {
		case m >= {.Position, .Velocity, .Spin}:
			// comet: a triangle, nose pointing along its angle
			a := world.angles[i]
			nose := point_at(pos, a, 14)
			wing_l := point_at(pos, a + 140, 11)
			wing_r := point_at(pos, a - 140, 11)
			rl.DrawTriangleLines(nose, wing_l, wing_r, rl.ORANGE)
		case m >= {.Position, .Pulse, .Lifetime}:
			// blinker: a circle breathing with the pulse scale (range [0.7, 1.3])
			s := world.scales[i]
			rl.DrawCircleV(pos, 12 * s, rl.Fade(rl.SKYBLUE, (s - 0.7) / 0.6))
		case m >= {.Position, .Velocity, .Lifetime}:
			// drifter: a small square
			rl.DrawRectanglePro({pos.x, pos.y, 10, 10}, {5, 5}, 0, rl.LIGHTGRAY)
		case m >= {.Position, .Spin}:
			// spinner: a plus sign rotating on the spot
			d1 := direction_at(world.angles[i])
			d2 := direction_at(world.angles[i] + 90)
			rl.DrawLineEx(pos - d1 * 12, pos + d1 * 12, 2, rl.GREEN)
			rl.DrawLineEx(pos - d2 * 12, pos + d2 * 12, 2, rl.GREEN)
		case:
			// anything else (e.g. a bare Position): a dot
			rl.DrawCircleV(pos, 3, rl.GRAY)
		}
	}
}

// Unit vector at `deg` degrees — 0 points up the screen, same convention as
// the Asteroids ship (module 7).
direction_at :: proc(deg: f32) -> rl.Vector2 {
	rad := (deg - 90) * rl.DEG2RAD
	return {math.cos(rad), math.sin(rad)}
}

point_at :: proc(pos: rl.Vector2, deg, dist: f32) -> rl.Vector2 {
	return pos + direction_at(deg) * dist
}

draw_hud :: proc(world: ^World, tracked: Entity, has_tracked, probed: bool) {
	alive := 0
	for i in 0 ..< world.count {
		if world.alive[i] do alive += 1
	}
	rl.DrawText(
		rl.TextFormat("alive %d   slots used %d   free list %d", alive, world.count, len(world.free_list)),
		10, 10, 20, rl.WHITE,
	)
	rl.DrawText("1 comets   2 blinkers   3 drifters   4 spinners   SPACE x100 random mix   C clear", 10, 36, 16, rl.GRAY)
	rl.DrawText("T track a comet at the mouse, then K to kill it and probe the stale handle", 10, 56, 16, rl.GRAY)

	if has_tracked {
		ok := is_alive(world, tracked)
		rl.DrawText(
			rl.TextFormat("tracked handle {index %d, gen %d}   is_alive: %s", tracked.index, int(tracked.gen), ok ? "true" : "false"),
			10, SCREEN_H - 30, 20, ok ? rl.GREEN : rl.RED,
		)
		if probed {
			rl.DrawText(
				rl.TextFormat("slot %d now holds gen %d — the stale gen %d handle was rejected", tracked.index, int(world.generations[tracked.index]), int(tracked.gen)),
				10, SCREEN_H - 55, 16, rl.YELLOW,
			)
		}
	}
}
