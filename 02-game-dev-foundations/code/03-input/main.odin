package main

import rl "vendor:raylib"

SCREEN_W :: 800
SCREEN_H :: 450

SPEED :: 300

main :: proc() {
	rl.InitWindow(SCREEN_W, SCREEN_H, "2.3 - input inspector")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	pos := rl.Vector2{SCREEN_W / 2, SCREEN_H / 2}
	size: f32 = 30
	pulse: f32 = 0 // counts down after SPACE tap

	markers: [dynamic]rl.Vector2
	defer delete(markers)

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()

		// --- held keys: continuous movement ---
		if rl.IsKeyDown(.D) do pos.x += SPEED * dt
		if rl.IsKeyDown(.A) do pos.x -= SPEED * dt
		if rl.IsKeyDown(.S) do pos.y += SPEED * dt
		if rl.IsKeyDown(.W) do pos.y -= SPEED * dt

		// --- pressed-this-frame: discrete actions ---
		if rl.IsKeyPressed(.SPACE) do pulse = 1.0
		if pulse > 0 do pulse -= dt * 3

		// --- mouse ---
		mouse := rl.GetMousePosition()
		if rl.IsMouseButtonPressed(.LEFT) {
			append(&markers, mouse)
		}
		size += rl.GetMouseWheelMove() * 5
		size = clamp(size, 5, 100)

		// --- draw ---
		rl.BeginDrawing()
		rl.ClearBackground(rl.RAYWHITE)

		// click markers
		for m in markers {
			rl.DrawCircleV(m, 6, rl.Fade(rl.SKYBLUE, 0.8))
		}

		// player square (pulses after SPACE)
		scale := 1 + pulse
		rl.DrawRectangleV(
		{pos.x - size * scale / 2, pos.y - size * scale / 2},
		{size * scale, size * scale},
		rl.MAROON,
		)

		// readouts
		rl.DrawText("WASD move | SPACE pulse | CLICK mark | WHEEL resize", 10, 10, 20, rl.DARKGRAY)
		rl.DrawText(rl.TextFormat("mouse: %d, %d", i32(mouse.x), i32(mouse.y)), 10, 40, 20, rl.GRAY)
		rl.DrawText(rl.TextFormat("D held: %t   SPACE pressed: %t", rl.IsKeyDown(.D), rl.IsKeyPressed(.SPACE)), 10, 70, 20, rl.GRAY)

		rl.EndDrawing()
	}
}
