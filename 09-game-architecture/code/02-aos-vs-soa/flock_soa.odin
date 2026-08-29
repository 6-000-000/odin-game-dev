package main

import rl "vendor:raylib"

// Struct of Arrays: all pos values in one array, all vel values in another.
// The flocking math is IDENTICAL — only the memory layout (and how we spell
// the accesses) changed. `#soa[]Boid` still indexes like a normal array:
// boids.pos[j] reaches into the pos column directly.
update_boids_soa :: proc(boids: #soa[]Boid, grid: ^Grid, s: Settings, dt: f32) {
	for i in 0 ..< len(boids) {
		// Work on locals; write back once at the end.
		pos := boids.pos[i]
		vel := boids.vel[i]

		sep, align_sum, coh_sum: rl.Vector2
		avoid_count, perc_count := 0, 0

		cx := clamp(int(pos.x / grid.cell_size), 0, grid.cells_x - 1)
		cy := clamp(int(pos.y / grid.cell_size), 0, grid.cells_y - 1)
		for dy in -1 ..= 1 {
			for dx in -1 ..= 1 {
				gx := (cx + dx + grid.cells_x) % grid.cells_x
				gy := (cy + dy + grid.cells_y) % grid.cells_y
				cell := gy * grid.cells_x + gx
				start := grid.cell_start[cell]
				for k in start ..< start + grid.cell_count[cell] {
					j := grid.cell_boids[k]
					if i == j do continue
					to_other := offset(pos, boids.pos[j], SCREEN_W, SCREEN_H)
					d := rl.Vector2Length(to_other)
					if d < s.avoid_radius {
						sep -= to_other
						avoid_count += 1
					}
					if d < s.perception_radius {
						align_sum += boids.vel[j]
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
			accel += steer_toward(avg_vel, vel, s) * s.w_align
			accel += steer_toward(avg_pos_off, vel, s) * s.w_coh
		}
		if avoid_count > 0 {
			accel += steer_toward(sep / f32(avoid_count), vel, s) * s.w_sep
		}

		vel += clamp_length(accel, s.max_steer) * dt
		vel = clamp_speed(vel, s)
		pos = wrap(pos + vel * dt, SCREEN_W, SCREEN_H)

		boids.vel[i] = vel
		boids.pos[i] = pos
	}
}
