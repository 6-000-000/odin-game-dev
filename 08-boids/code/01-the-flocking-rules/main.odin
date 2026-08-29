package main

import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

SCREEN_W :: 1280
SCREEN_H :: 720

BOID_COUNT :: 20
BOID_SIZE :: 9 // px from center to nose
WANDER :: 0.05 // fraction of max_steer applied as random jitter

Boid :: struct {
	pos, vel: rl.Vector2,
}

// Every tuning constant of the simulation lives in ONE struct, threaded
// through every proc. Today only a few fields are used; lessons 8.2–8.4
// grow into the rest (and lesson 8.4 tweaks them live with sliders).
Settings :: struct {
	max_speed:         f32, // px/s — hard speed ceiling
	min_speed:         f32, // px/s — boids never stop, they always fly
	max_steer:         f32, // px/s² — max turning acceleration
	perception_radius: f32, // px — how far a boid sees flockmates
	avoid_radius:      f32, // px — "too close" distance for separation
	w_sep:             f32, // rule weights (8.2)
	w_align:           f32,
	w_coh:             f32,
}

default_settings :: proc() -> Settings {
	return {
		max_speed = 320,
		min_speed = 180,
		max_steer = 900,
		perception_radius = 75,
		avoid_radius = 35,
		w_sep = 1.4,
		w_align = 1.0,
		w_coh = 1.0,
	}
}

// --- vector helpers ---

// rl.Vector2Normalize({0, 0}) divides by length 0 and yields NaN — and one
// NaN velocity poisons every sum it touches. ALWAYS normalize through this.
safe_normalize :: proc(v: rl.Vector2) -> rl.Vector2 {
	len := rl.Vector2Length(v)
	if len < 0.0001 do return {}
	return v / len
}

// Cap a vector's length without changing its direction.
clamp_length :: proc(v: rl.Vector2, max_len: f32) -> rl.Vector2 {
	len := rl.Vector2Length(v)
	if len > max_len && len > 0 do return v * (max_len / len)
	return v
}

// Lague's steering: aim for a full-speed velocity in `dir`, then let the boid
// turn toward it by at most max_steer. "I want to go THERE" − "I'm going here".
steer_toward :: proc(dir, vel: rl.Vector2, s: Settings) -> rl.Vector2 {
	desired := safe_normalize(dir) * s.max_speed
	return clamp_length(desired - vel, s.max_steer)
}

// Keep speed inside [min_speed, max_speed]. Boids are like sharks: they
// can't hover, so a near-zero velocity gets a random kick instead.
clamp_speed :: proc(vel: rl.Vector2, s: Settings) -> rl.Vector2 {
	speed := rl.Vector2Length(vel)
	if speed > s.max_speed do return vel * (s.max_speed / speed)
	if speed < 0.001 {
		angle := rand.float32_range(0, 2 * math.PI)
		return {math.cos(angle), math.sin(angle)} * s.min_speed
	}
	if speed < s.min_speed do return vel * (s.min_speed / speed)
	return vel
}

// --- toroidal world ---

// Positions wrap around the edges: fly off the right, reappear on the left.
wrap :: proc(p: rl.Vector2, w, h: f32) -> rl.Vector2 {
	pos := p
	if pos.x < 0 do pos.x += w
	if pos.x >= w do pos.x -= w
	if pos.y < 0 do pos.y += h
	if pos.y >= h do pos.y -= h
	return pos
}

// Shortest vector from a to b on the wrap-around world ("wrap-aware b − a").
// Without this, two boids on opposite sides of an edge look 1200px apart
// when they're really 6px apart across the seam.
offset :: proc(a, b: rl.Vector2, w, h: f32) -> rl.Vector2 {
	d := b - a
	if d.x > w / 2 do d.x -= w
	if d.x < -w / 2 do d.x += w
	if d.y > h / 2 do d.y -= h
	if d.y < -h / 2 do d.y += h
	return d
}

// --- boids ---

random_boid :: proc(s: Settings, w, h: f32) -> Boid {
	angle := rand.float32_range(0, 2 * math.PI)
	speed := rand.float32_range(s.min_speed, s.max_speed)
	return {
		pos = {rand.float32_range(0, w), rand.float32_range(0, h)},
		vel = {math.cos(angle), math.sin(angle)} * speed,
	}
}

// Only COHESION is implemented today, plus a tiny wander so isolated boids
// drift instead of flying in straight lines forever.
update_boids :: proc(boids: []Boid, s: Settings, dt: f32) {
	for &b, i in boids {
		// perceive: where is the average flockmate, relative to me?
		coh_sum: rl.Vector2
		count := 0
		for other, j in boids {
			if i == j do continue
			to_other := offset(b.pos, other.pos, SCREEN_W, SCREEN_H)
			if rl.Vector2Length(to_other) < s.perception_radius {
				coh_sum += to_other
				count += 1
			}
		}

		accel: rl.Vector2
		if count > 0 {
			// b.pos + avg(to_other) is the perceived center of the flock
			accel += steer_toward(coh_sum / f32(count), b.vel, s) * s.w_coh
		}
		// tiny random jitter — keeps lonely boids (and the math) alive
		accel += {rand.float32_range(-1, 1), rand.float32_range(-1, 1)} * s.max_steer * WANDER

		b.vel += clamp_length(accel, s.max_steer) * dt
		b.vel = clamp_speed(b.vel, s)
		b.pos = wrap(b.pos + b.vel * dt, SCREEN_W, SCREEN_H)
	}
}

// A boid is a small triangle rotated to its heading, nose forward.
draw_boid :: proc(b: Boid, color: rl.Color) {
	heading := math.atan2(b.vel.y, b.vel.x)
	nose := b.pos + {math.cos(heading), math.sin(heading)} * BOID_SIZE
	left := b.pos + {math.cos(heading + 2.5), math.sin(heading + 2.5)} * BOID_SIZE * 0.6
	right := b.pos + {math.cos(heading - 2.5), math.sin(heading - 2.5)} * BOID_SIZE * 0.6
	rl.DrawTriangle(nose, left, right, color)
}

main :: proc() {
	rl.InitWindow(SCREEN_W, SCREEN_H, "Boids 1/4 — the flocking rules")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	rand.reset(0xB01D5) // fixed seed = reproducible flock (change it!)

	settings := default_settings()

	boids: [dynamic]Boid
	defer delete(boids)
	for _ in 0 ..< BOID_COUNT {
		append(&boids, random_boid(settings, SCREEN_W, SCREEN_H))
	}

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()

		update_boids(boids[:], settings, dt)

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)
		for b in boids {
			draw_boid(b, rl.SKYBLUE)
		}
		rl.DrawFPS(10, 10)
		rl.DrawText(rl.TextFormat("boids: %d", len(boids)), 10, 40, 20, rl.RAYWHITE)
		rl.EndDrawing()
	}
}
