package main

import "core:math/rand"
import rl "vendor:raylib"

SCREEN_W :: 1280
SCREEN_H :: 720
WORLD_W :: 2560
WORLD_H :: 1440 // 4x the window: camera territory

MAX_BOIDS :: 4096
MAX_CELLS :: 128 * 72 // worst case: perception slider at 20 px

SCARE_RADIUS :: 150.0
SCARE_STRENGTH :: 5.0
PRED_RADIUS :: 120.0
PRED_STRENGTH :: 8.0

// raygui tuning panel, top-right (screen space)
PANEL_RECT :: rl.Rectangle{SCREEN_W - 250, 8, 242, 200}

main :: proc() {
	rl.InitWindow(SCREEN_W, SCREEN_H, "Boids 4/4 — tuning & interaction")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)
	rl.GuiSetStyle(.DEFAULT, i32(rl.GuiDefaultProperty.TEXT_SIZE), 12)

	rand.reset(0xB01D5)

	settings := default_settings()

	grid: Grid
	grid_init(&grid, MAX_CELLS, MAX_BOIDS)
	defer grid_destroy(&grid)
	grid_resize(&grid, WORLD_W, WORLD_H, settings.perception_radius)

	boids := make([dynamic]Boid, 0, MAX_BOIDS)
	defer delete(boids)
	spawn_boids(&boids, 2000, settings)

	cam := camera_init()
	predator := Predator{}
	debug_circles := false
	count_f := f32(len(boids)) // boid-count slider value

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()

		camera_update(&cam)

		if rl.IsKeyPressed(.D) do debug_circles = !debug_circles
		if rl.IsKeyPressed(.P) {
			predator.active = !predator.active
			if predator.active do predator_reset(&predator)
		}
		if predator.active do predator_update(&predator, dt)

		// hold left mouse = scare point (unless dragging a slider)
		mouse := rl.GetMousePosition()
		scaring := rl.IsMouseButtonDown(.LEFT) && !rl.CheckCollisionPointRec(mouse, PANEL_RECT)
		scare_world := rl.GetScreenToWorld2D(mouse, cam)

		hazards: [2]Hazard
		hazard_count := 0
		if scaring {
			hazards[hazard_count] = {scare_world, SCARE_RADIUS, SCARE_STRENGTH}
			hazard_count += 1
		}
		if predator.active {
			hazards[hazard_count] = {predator.pos, PRED_RADIUS, PRED_STRENGTH}
			hazard_count += 1
		}

		// apply slider-driven changes
		if int(count_f) != len(boids) do set_boid_count(&boids, int(count_f), settings)
		if grid.cell_size != settings.perception_radius {
			grid_resize(&grid, WORLD_W, WORLD_H, settings.perception_radius)
		}

		t0 := rl.GetTime()
		grid_rebuild(&grid, boids[:])
		update_boids(boids[:], &grid, settings, dt, hazards[:hazard_count])
		update_ms := (rl.GetTime() - t0) * 1000

		// --- draw: world first, inside the camera ---
		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)

		rl.BeginMode2D(cam)
		rl.DrawRectangleLinesEx({0, 0, WORLD_W, WORLD_H}, 4, rl.DARKGRAY)
		for b in boids {
			draw_boid(b, settings)
		}
		if predator.active do predator_draw(predator)
		if scaring {
			rl.DrawCircleLines(i32(scare_world.x), i32(scare_world.y), SCARE_RADIUS, rl.Fade(rl.RED, 0.4))
		}
		if debug_circles {
			for b in boids {
				rl.DrawCircleLines(i32(b.pos.x), i32(b.pos.y), settings.perception_radius, rl.Fade(rl.GREEN, 0.15))
			}
		}
		rl.EndMode2D()

		// --- HUD: screen space, AFTER EndMode2D ---
		rl.DrawFPS(10, 10)
		rl.DrawText(rl.TextFormat("update: %.2f ms", update_ms), 10, 40, 20, rl.LIME)
		rl.DrawText(rl.TextFormat("boids: %d", len(boids)), 10, 70, 20, rl.RAYWHITE)
		rl.DrawText("LMB: scare  |  P: predator  |  D: perception  |  RMB+wheel: camera", 10, SCREEN_H - 30, 20, rl.GRAY)
		draw_ui(&settings, &count_f)

		rl.EndDrawing()
	}
}

draw_ui :: proc(s: ^Settings, count: ^f32) {
	rl.GuiPanel(PANEL_RECT, "tuning")
	y := PANEL_RECT.y + 28
	ui_slider("separation", &s.w_sep, 0, 3, &y)
	ui_slider("alignment", &s.w_align, 0, 3, &y)
	ui_slider("cohesion", &s.w_coh, 0, 3, &y)
	ui_slider("perception", &s.perception_radius, 20, 150, &y)
	ui_slider("avoid", &s.avoid_radius, 10, 80, &y)
	ui_slider("boids", count, 100, 4000, &y)
}

ui_slider :: proc(label: cstring, value: ^f32, min, max: f32, y: ^f32) {
	bounds := rl.Rectangle{PANEL_RECT.x + 10, y^, PANEL_RECT.width - 20, 16}
	rl.GuiSlider(bounds, label, rl.TextFormat("%.2f", value^), value, min, max)
	y^ += 27
}
