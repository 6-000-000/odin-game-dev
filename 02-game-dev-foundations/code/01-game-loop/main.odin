package main

import rl "vendor:raylib"

SCREEN_W :: 800
SCREEN_H :: 450

SPEED :: 200 // pixels per second

main :: proc() {
	rl.InitWindow(SCREEN_W, SCREEN_H, "2.1 - delta time")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	capped := true

	// The BAD circle: moves a fixed amount per frame — speed depends on FPS
	bad_x: f32 = 0
	// The GOOD circle: moves SPEED * dt — same wall-clock speed at any FPS
	good_x: f32 = 0

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()

		// --- input ---
		if rl.IsKeyPressed(.SPACE) {
			capped = !capped
			rl.SetTargetFPS(capped ? 60 : 0) // 0 = uncapped
		}

		// --- update ---
		bad_x += 3.0 // px per FRAME — wrong on purpose
		good_x += SPEED * dt // px per SECOND — correct

		if bad_x > SCREEN_W + 20 do bad_x = -20
		if good_x > SCREEN_W + 20 do good_x = -20

		// --- draw ---
		rl.BeginDrawing()
		rl.ClearBackground(rl.RAYWHITE)

		rl.DrawText("per-frame (bad): speed depends on FPS", 20, 130, 20, rl.MAROON)
		rl.DrawCircleV({bad_x, 180}, 20, rl.MAROON)

		rl.DrawText("dt-based (good): constant px/second", 20, 250, 20, rl.DARKGREEN)
		rl.DrawCircleV({good_x, 300}, 20, rl.DARKGREEN)

		rl.DrawText("SPACE: toggle FPS cap", 20, 10, 20, rl.DARKGRAY)
		rl.DrawText(rl.TextFormat("dt: %.5f s", dt), 620, 40, 20, rl.GRAY)
		rl.DrawFPS(660, 10)
		rl.EndDrawing()
	}
}
