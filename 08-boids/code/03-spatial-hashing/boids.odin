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

// --- vector helpers (identical to lessons 8.1 and 8.2) ---

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

// --- the same three rules; ONLY the neighbor source changed ---

update_boids :: proc(boids: []Boid, grid: ^Grid, s: Settings, dt: f32) {
	for &b, i in boids {
		sep, align_sum, coh_sum: rl.Vector2
		avoid_count, perc_count := 0, 0

		// perceive: scan the 3x3 cells around my cell — indices wrap modulo
		// the grid so edge boids see across the seam (toroidal world).
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
					to_other := offset(b.pos, other.pos, SCREEN_W, SCREEN_H)
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

		// ↓↓↓ byte-for-byte the same flocking math as lesson 8.2 ↓↓↓
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

		b.vel += clamp_length(accel, s.max_steer) * dt
		b.vel = clamp_speed(b.vel, s)
		b.pos = wrap(b.pos + b.vel * dt, SCREEN_W, SCREEN_H)
	}
}

random_boid :: proc(s: Settings, w, h: f32) -> Boid {
	angle := rand.float32_range(0, 2 * math.PI)
	speed := rand.float32_range(s.min_speed, s.max_speed)
	return {
		pos = {rand.float32_range(0, w), rand.float32_range(0, h)},
		vel = {math.cos(angle), math.sin(angle)} * speed,
	}
}

spawn_boids :: proc(boids: ^[dynamic]Boid, n: int, s: Settings) {
	clear(boids)
	for _ in 0 ..< n {
		append(boids, random_boid(s, SCREEN_W, SCREEN_H))
	}
}

draw_boid :: proc(b: Boid, color: rl.Color) {
	heading := math.atan2(b.vel.y, b.vel.x)
	nose := b.pos + {math.cos(heading), math.sin(heading)} * BOID_SIZE
	left := b.pos + {math.cos(heading + 2.5), math.sin(heading + 2.5)} * BOID_SIZE * 0.6
	right := b.pos + {math.cos(heading - 2.5), math.sin(heading - 2.5)} * BOID_SIZE * 0.6
	rl.DrawTriangle(nose, left, right, color)
}
