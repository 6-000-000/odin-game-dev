package main

import "core:math/rand"
import rl "vendor:raylib"

SCREEN_W :: 1280
SCREEN_H :: 720

MAX_BOIDS :: 5000
CELL_SIZE :: 75 // == default_settings().perception_radius; 3x3 cells cover it

main :: proc() {
	rl.InitWindow(SCREEN_W, SCREEN_H, "Boids 3/4 — spatial hashing")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	rand.reset(0xB01D5)

	settings := default_settings()

	grid: Grid
	grid_init(&grid, SCREEN_W, SCREEN_H, CELL_SIZE, MAX_BOIDS)
	defer grid_destroy(&grid)

	boids := make([dynamic]Boid, 0, MAX_BOIDS) // capacity once, never reallocates
	defer delete(boids)
	spawn_boids(&boids, 2000, settings)

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()

		// boid-count presets
		if rl.IsKeyPressed(.ONE) do spawn_boids(&boids, 500, settings)
		if rl.IsKeyPressed(.TWO) do spawn_boids(&boids, 2000, settings)
		if rl.IsKeyPressed(.THREE) do spawn_boids(&boids, 5000, settings)

		// rebuild the buckets, then run the flock — time the pair
		t0 := rl.GetTime()
		grid_rebuild(&grid, boids[:])
		update_boids(boids[:], &grid, settings, dt)
		update_ms := (rl.GetTime() - t0) * 1000

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)
		for b in boids {
			draw_boid(b, rl.SKYBLUE)
		}
		rl.DrawFPS(10, 10)
		rl.DrawText(rl.TextFormat("update: %.2f ms", update_ms), 10, 40, 20, rl.LIME)
		rl.DrawText(rl.TextFormat("boids: %d", len(boids)), 10, 70, 20, rl.RAYWHITE)
		rl.DrawText("1/2/3 = 500 / 2000 / 5000 boids", 10, 100, 20, rl.GRAY)
		rl.EndDrawing()
	}
}
