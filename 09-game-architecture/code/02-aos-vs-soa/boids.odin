package main

import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

BOID_SIZE :: 8

// The struct is UNCHANGED between layouts — only the container type differs.
// 16 bytes per boid: two rl.Vector2 ({x, y: f32} each).
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

// --- vector helpers (identical to module 8) ---

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

random_boid :: proc(s: Settings, w, h: f32) -> Boid {
	angle := rand.float32_range(0, 2 * math.PI)
	speed := rand.float32_range(s.min_speed, s.max_speed)
	return {
		pos = {rand.float32_range(0, w), rand.float32_range(0, h)},
		vel = {math.cos(angle), math.sin(angle)} * speed,
	}
}

// --- spawning, identical worlds in both layouts (same seed = same boids) ---

spawn_boids_aos :: proc(boids: ^[dynamic]Boid, n: int, s: Settings) {
	clear(boids)
	for _ in 0 ..< n {
		append(boids, random_boid(s, SCREEN_W, SCREEN_H))
	}
}

spawn_boids_soa :: proc(boids: ^#soa[dynamic]Boid, n: int, s: Settings) {
	resize_soa(boids, 0) // keep capacity, drop length (SoA's `clear`)
	for _ in 0 ..< n {
		append_soa(boids, random_boid(s, SCREEN_W, SCREEN_H)) // note: append_soa
	}
}

// --- live conversion between layouts (what TAB does) ---

copy_aos_to_soa :: proc(dst: ^#soa[dynamic]Boid, src: []Boid) {
	resize_soa(dst, len(src))
	for b, i in src {
		dst[i] = b // same indexing syntax as a normal array
	}
}

copy_soa_to_aos :: proc(dst: ^[dynamic]Boid, src: #soa[]Boid) {
	resize(dst, len(src))
	for i in 0 ..< len(src) {
		dst[i] = src[i] // reading one element yields a plain Boid value
	}
}

draw_boid :: proc(b: Boid, color: rl.Color) {
	heading := math.atan2(b.vel.y, b.vel.x)
	nose := b.pos + {math.cos(heading), math.sin(heading)} * BOID_SIZE
	left := b.pos + {math.cos(heading + 2.5), math.sin(heading + 2.5)} * BOID_SIZE * 0.6
	right := b.pos + {math.cos(heading - 2.5), math.sin(heading - 2.5)} * BOID_SIZE * 0.6
	rl.DrawTriangle(nose, left, right, color)
}
