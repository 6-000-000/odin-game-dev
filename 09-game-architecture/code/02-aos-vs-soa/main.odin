package main

import "core:math/rand"
import rl "vendor:raylib"

SCREEN_W :: 1280
SCREEN_H :: 720

MAX_BOIDS :: 5000
CELL_SIZE :: 75 // == default_settings().perception_radius

Layout :: enum {
	AoS,
	SoA,
}

main :: proc() {
	rl.InitWindow(SCREEN_W, SCREEN_H, "9.2 - AoS vs SoA")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	settings := default_settings()

	grid: Grid
	grid_init(&grid, SCREEN_W, SCREEN_H, CELL_SIZE, MAX_BOIDS)
	defer grid_destroy(&grid)

	// The SAME struct, two container types. AoS is what module 8 used;
	// SoA is one keyword different: #soa.
	boids_aos := make([dynamic]Boid, 0, MAX_BOIDS)
	defer delete(boids_aos)
	boids_soa := make(#soa[dynamic]Boid, 0, MAX_BOIDS)
	defer delete(boids_soa)

	// Same seed for both = identical worlds.
	rand.reset(0xB01D5)
	spawn_boids_aos(&boids_aos, 2000, settings)
	rand.reset(0xB01D5)
	spawn_boids_soa(&boids_soa, 2000, settings)

	layout := Layout.AoS
	last_ms: [Layout]f64

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()

		// TAB converts the live world between layouts and keeps simulating —
		// the conversion itself is the lesson.
		if rl.IsKeyPressed(.TAB) {
			if layout == .AoS {
				copy_aos_to_soa(&boids_soa, boids_aos[:])
				layout = .SoA
			} else {
				copy_soa_to_aos(&boids_aos, boids_soa[:])
				layout = .AoS
			}
		}

		if rl.IsKeyPressed(.ONE) || rl.IsKeyPressed(.TWO) || rl.IsKeyPressed(.THREE) {
			n := 500
			if rl.IsKeyPressed(.TWO) do n = 2000
			if rl.IsKeyPressed(.THREE) do n = 5000
			// respawn the ACTIVE layout; the other rebuilds from it on TAB
			rand.reset(0xB01D5)
			if layout == .AoS {
				spawn_boids_aos(&boids_aos, n, settings)
			} else {
				spawn_boids_soa(&boids_soa, n, settings)
			}
		}

		t0 := rl.GetTime()
		update_ms: f64
		boid_count: int
		if layout == .AoS {
			grid_rebuild_aos(&grid, boids_aos[:])
			update_boids_aos(boids_aos[:], &grid, settings, dt)
			boid_count = len(boids_aos)
		} else {
			grid_rebuild_soa(&grid, boids_soa.pos[:len(boids_soa)])
			update_boids_soa(boids_soa[:], &grid, settings, dt)
			boid_count = len(boids_soa)
		}
		update_ms = (rl.GetTime() - t0) * 1000
		last_ms[layout] = update_ms

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)

		if layout == .AoS {
			for b in boids_aos {
				draw_boid(b, rl.SKYBLUE)
			}
		} else {
			for i in 0 ..< len(boids_soa) {
				draw_boid(boids_soa[i], rl.ORANGE)
			}
		}

		ms_text := rl.TextFormat("update: %.2f ms", update_ms)
		mode_text := rl.TextFormat("layout: %s (TAB flips + converts)", layout == .AoS ? "AoS" : "SoA")
		count_text := rl.TextFormat("boids: %d", boid_count)
		aos_text := rl.TextFormat("last AoS: %.2f ms", last_ms[.AoS])
		soa_text := rl.TextFormat("last SoA: %.2f ms", last_ms[.SoA])

		rl.DrawFPS(10, 10)
		rl.DrawText(ms_text, 10, 40, 20, rl.LIME)
		rl.DrawText(mode_text, 10, 70, 20, rl.RAYWHITE)
		rl.DrawText(count_text, 10, 100, 20, rl.RAYWHITE)
		rl.DrawText(aos_text, 10, 130, 20, rl.SKYBLUE)
		rl.DrawText(soa_text, 10, 160, 20, rl.ORANGE)
		rl.DrawText("1/2/3 = 500 / 2000 / 5000 boids", 10, 190, 20, rl.GRAY)
		rl.EndDrawing()
	}
}
