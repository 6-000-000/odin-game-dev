package main

import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

BOID_SIZE :: 8

Boid :: struct {
	pos, vel: rl.Vector2,
}

Settings :: struct {
	max_speed:         f32,
	min_speed:         f32,
	max_steer:         f32,
	perception_radius: f32,
	avoid_radius:      f32,
	w_sep:             f32,
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

// A place boids flee from: the mouse scare point and the predator are both
// just hazards — same flee math, different position and strength.
Hazard :: struct {
	pos:      rl.Vector2,
	radius:   f32,
	strength: f32, // multiplier on the flee steer
}

// --- vector helpers (unchanged since lesson 8.1) ---

safe_normalize :: proc(v: rl.Vector2) -> rl.Vector2 {
	len := rl.Vector2Length(v)
	if len < 0.0001 do return {}
	return v / len
}

clamp_length :: proc(v: rl.Vector2, max_len: f32) -> rl.Vector2 {
	len := rl.Vector2Length(v)
	if len > max_len && len > 0 do return v * (max_len / len)
	return v
}

steer_toward :: proc(dir, vel: rl.Vector2, s: Settings) -> rl.Vector2 {
	desired := safe_normalize(dir) * s.max_speed
	return clamp_length(desired - vel, s.max_steer)
}

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

wrap :: proc(p: rl.Vector2, w, h: f32) -> rl.Vector2 {
	pos := p
	if pos.x < 0 do pos.x += w
	if pos.x >= w do pos.x -= w
	if pos.y < 0 do pos.y += h
	if pos.y >= h do pos.y -= h
	return pos
}

offset :: proc(a, b: rl.Vector2, w, h: f32) -> rl.Vector2 {
	d := b - a
	if d.x > w / 2 do d.x -= w
	if d.x < -w / 2 do d.x += w
	if d.y > h / 2 do d.y -= h
	if d.y < -h / 2 do d.y += h
	return d
}

// --- the same three rules + hazard fleeing ---

update_boids :: proc(boids: []Boid, grid: ^Grid, s: Settings, dt: f32, hazards: []Hazard) {
	for &b, i in boids {
		sep, align_sum, coh_sum: rl.Vector2
		avoid_count, perc_count := 0, 0

		// perceive: 3x3 grid cells, wrapped (identical to lesson 8.3)
		cx := clamp(int(b.pos.x / grid.cell_size), 0, grid.cells_x - 1)
		cy := clamp(int(b.pos.y / grid.cell_size), 0, grid.cells_y - 1)
		for dy in -1 ..= 1 {
			for dx in -1 ..= 1 {
				gx := (cx + dx + grid.cells_x) % grid.cells_x
				gy := (cy + dy + grid.cells_y) % grid.cells_y
				cell := gy * grid.cells_x + gx
				start := grid.cell_start[cell]
				for k in start ..< start + grid.cell_count[cell] {
					j := grid.cell_boids[k]
					if i == j do continue
					other := boids[j]
					to_other := offset(b.pos, other.pos, WORLD_W, WORLD_H)
					d := rl.Vector2Length(to_other)
					if d < s.avoid_radius {
						sep -= to_other
						avoid_count += 1
					}
					if d < s.perception_radius {
						align_sum += other.vel
						coh_sum += to_other
						perc_count += 1
					}
				}
			}
		}

		accel: rl.Vector2
		if perc_count > 0 {
			avg_vel := align_sum / f32(perc_count)
			avg_pos_off := coh_sum / f32(perc_count)
			accel += steer_toward(avg_vel, b.vel, s) * s.w_align
			accel += steer_toward(avg_pos_off, b.vel, s) * s.w_coh
		}
		if avoid_count > 0 {
			accel += steer_toward(sep / f32(avoid_count), b.vel, s) * s.w_sep
		}
		// flocking obeys the turning limit...
		b.vel += clamp_length(accel, s.max_steer) * dt

		// ...but fear doesn't: hazard flee steer is added AFTER the clamp,
		// so strength 5–8 genuinely out-muscles the flocking rules
		for h in hazards {
			to_me := offset(h.pos, b.pos, WORLD_W, WORLD_H)
			if rl.Vector2Length(to_me) < h.radius {
				b.vel += steer_toward(to_me, b.vel, s) * h.strength * dt
			}
		}

		b.vel = clamp_speed(b.vel, s)
		b.pos = wrap(b.pos + b.vel * dt, WORLD_W, WORLD_H)
	}
}

// The predator is a boid-shaped bullet: constant speed, random-walk heading.
// Lague's video does exactly this — and the flock parts around it.
Predator :: struct {
	pos:     rl.Vector2,
	heading: f32,
	active:  bool,
}

PRED_SPEED :: 380.0 // a bit faster than max_speed: it can catch up
PRED_TURN :: 2.2 // rad/s of random turning

predator_reset :: proc(p: ^Predator) {
	p.pos = {WORLD_W / 2, WORLD_H / 2}
	p.heading = rand.float32_range(0, 2 * math.PI)
	p.active = true
}

predator_update :: proc(p: ^Predator, dt: f32) {
	p.heading += rand.float32_range(-PRED_TURN, PRED_TURN) * dt
	vel := rl.Vector2{math.cos(p.heading), math.sin(p.heading)} * PRED_SPEED
	p.pos = wrap(p.pos + vel * dt, WORLD_W, WORLD_H)
}

predator_draw :: proc(p: Predator) {
	draw_agent(p.pos, p.heading, 14, rl.RED)
}

random_boid :: proc(s: Settings) -> Boid {
	angle := rand.float32_range(0, 2 * math.PI)
	speed := rand.float32_range(s.min_speed, s.max_speed)
	return {
		pos = {rand.float32_range(0, WORLD_W), rand.float32_range(0, WORLD_H)},
		vel = {math.cos(angle), math.sin(angle)} * speed,
	}
}

spawn_boids :: proc(boids: ^[dynamic]Boid, n: int, s: Settings) {
	clear(boids)
	for _ in 0 ..< n {
		append(boids, random_boid(s))
	}
}

// Grow/shrink to n: new boids spawn randomly, removals come off the end.
set_boid_count :: proc(boids: ^[dynamic]Boid, n: int, s: Settings) {
	target := clamp(n, 0, MAX_BOIDS)
	if len(boids) > target do resize(boids, target)
	for len(boids) < target {
		append(boids, random_boid(s))
	}
}

// A triangle rotated to heading, nose forward (same math since lesson 8.1).
draw_agent :: proc(pos: rl.Vector2, heading, size: f32, color: rl.Color) {
	nose := pos + {math.cos(heading), math.sin(heading)} * size
	left := pos + {math.cos(heading + 2.5), math.sin(heading + 2.5)} * size * 0.6
	right := pos + {math.cos(heading - 2.5), math.sin(heading - 2.5)} * size * 0.6
	rl.DrawTriangle(nose, left, right, color)
}

// Colored by speed, like Lague's sim: slow = sky blue, fast = red.
draw_boid :: proc(b: Boid, s: Settings) {
	speed := rl.Vector2Length(b.vel)
	t := clamp((speed - s.min_speed) / (s.max_speed - s.min_speed), 0, 1)
	draw_agent(b.pos, math.atan2(b.vel.y, b.vel.x), BOID_SIZE, rl.ColorLerp(rl.SKYBLUE, rl.RED, t))
}
