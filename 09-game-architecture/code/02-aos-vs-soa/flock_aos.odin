package main

import rl "vendor:raylib"

// Array of Structs: each boid's pos and vel sit next to each other in memory.
// Byte-for-byte the update from lesson 8.3 — this is the control group.
update_boids_aos :: proc(boids: []Boid, grid: ^Grid, s: Settings, dt: f32) {
	for &b, i in boids {
		sep, align_sum, coh_sum: rl.Vector2
		avoid_count, perc_count := 0, 0

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
