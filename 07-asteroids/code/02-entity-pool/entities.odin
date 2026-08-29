package main

import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

// --- ship tuning (moved over from lesson 1) ---
ROT_SPEED :: 220 // deg/s
THRUST :: 300 // px/s² gained while thrusting
DAMPING :: 0.8 // fraction of velocity bled off per second

// --- the asteroid pool: a fixed array with active flags ---
ASTEROID_MAX :: 64

// radius tiers; MED/SMALL only appear once splitting exists (lesson 3)
ASTEROID_BIG :: 40
ASTEROID_MED :: 22
ASTEROID_SMALL :: 12
ASTEROID_SIDES :: 9

SHIP_CLEARANCE :: 150 // px; asteroids never spawn closer than this to the ship

Ship :: struct {
	pos:    rl.Vector2,
	vel:    rl.Vector2,
	angle:  f32, // degrees; 0 points up the screen
	radius: f32,
}

Asteroid :: struct {
	pos:       rl.Vector2,
	vel:       rl.Vector2,
	radius:    f32,
	rotation:  f32, // degrees; spins via rot_speed
	rot_speed: f32, // deg/s
	active:    bool,
}

// Everything in the game lives in one struct, passed around by pointer.
World :: struct {
	ship:      Ship,
	asteroids: [ASTEROID_MAX]Asteroid,
}

// --- ship (from lesson 1, unchanged) ---

ship_facing :: proc(angle: f32) -> rl.Vector2 {
	rad := (angle - 90) * rl.DEG2RAD
	return {math.cos(rad), math.sin(rad)}
}

ship_point :: proc(pos: rl.Vector2, deg, dist: f32) -> rl.Vector2 {
	rad := (deg - 90) * rl.DEG2RAD
	return pos + {math.cos(rad), math.sin(rad)} * dist
}

wrap :: proc(pos: ^rl.Vector2, radius: f32) {
	if pos.x < -radius do pos.x += SCREEN_W + radius * 2
	if pos.x > SCREEN_W + radius do pos.x -= SCREEN_W + radius * 2
	if pos.y < -radius do pos.y += SCREEN_H + radius * 2
	if pos.y > SCREEN_H + radius do pos.y -= SCREEN_H + radius * 2
}

update_ship :: proc(ship: ^Ship, dt: f32) {
	if rl.IsKeyDown(.LEFT) do ship.angle -= ROT_SPEED * dt
	if rl.IsKeyDown(.RIGHT) do ship.angle += ROT_SPEED * dt
	if rl.IsKeyDown(.UP) {
		ship.vel += ship_facing(ship.angle) * THRUST * dt
	}
	ship.vel *= 1 - DAMPING * dt
	ship.pos += ship.vel * dt
	wrap(&ship.pos, ship.radius)
}

draw_ship :: proc(ship: Ship, thrusting: bool) {
	nose := ship_point(ship.pos, ship.angle, ship.radius)
	wing_l := ship_point(ship.pos, ship.angle + 140, ship.radius * 0.8)
	wing_r := ship_point(ship.pos, ship.angle - 140, ship.radius * 0.8)
	rl.DrawTriangleLines(nose, wing_l, wing_r, rl.WHITE)

	if thrusting {
		tip := ship_point(ship.pos, ship.angle + 180, rand.float32_range(ship.radius * 0.9, ship.radius * 1.7))
		base_l := ship_point(ship.pos, ship.angle + 160, ship.radius * 0.5)
		base_r := ship_point(ship.pos, ship.angle - 160, ship.radius * 0.5)
		rl.DrawTriangle(base_l, tip, base_r, rl.ORANGE)
	}
}

// --- wave spawning ---

// A random spot in an 80 px band along the edges, far from the ship.
random_edge_pos :: proc(ship_pos: rl.Vector2) -> rl.Vector2 {
	for _ in 0 ..< 32 {
		pos := rl.Vector2{rand.float32_range(0, SCREEN_W), rand.float32_range(0, SCREEN_H)}
		near_edge := min(min(pos.x, SCREEN_W - pos.x), min(pos.y, SCREEN_H - pos.y)) < 80
		if near_edge && rl.Vector2Distance(pos, ship_pos) >= SHIP_CLEARANCE {
			return pos
		}
	}
	return {0, 0} // gave up; a corner is far enough
}

random_drift :: proc(min_speed, max_speed: f32) -> rl.Vector2 {
	angle := rand.float32_range(0, 2 * math.PI)
	speed := rand.float32_range(min_speed, max_speed)
	return {math.cos(angle), math.sin(angle)} * speed
}

// Fill n free pool slots with fresh big asteroids. The free-slot search IS the allocator.
spawn_wave :: proc(world: ^World, n: int) {
	spawned := 0
	for &a in world.asteroids {
		if spawned >= n do return
		if a.active do continue // slot in use — keep scanning
		a = Asteroid {
			pos       = random_edge_pos(world.ship.pos),
			vel       = random_drift(30, 90),
			radius    = ASTEROID_BIG,
			rotation  = rand.float32_range(0, 360),
			rot_speed = rand.float32_range(-60, 60),
			active    = true,
		}
		spawned += 1
	}
}

// --- asteroids ---

update_asteroids :: proc(world: ^World, dt: f32) {
	for &a in world.asteroids {
		if !a.active do continue
		a.pos += a.vel * dt
		a.rotation += a.rot_speed * dt
		wrap(&a.pos, a.radius)
	}
}

draw_asteroids :: proc(world: ^World) {
	for a in world.asteroids {
		if !a.active do continue
		rl.DrawPolyLines(a.pos, ASTEROID_SIDES, a.radius, a.rotation, rl.LIGHTGRAY)
	}
}
