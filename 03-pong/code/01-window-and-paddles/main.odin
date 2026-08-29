package main

import rl "vendor:raylib"

SCREEN_W :: 800
SCREEN_H :: 450

PADDLE_W :: 15
PADDLE_H :: 90
PADDLE_SPEED :: 400

Paddle :: struct {
	pos:   rl.Vector2, // center of the paddle
	speed: f32,
}

draw_paddle :: proc(p: Paddle, color: rl.Color) {
	rl.DrawRectangleV(
	{p.pos.x - PADDLE_W / 2, p.pos.y - PADDLE_H / 2},
	{PADDLE_W, PADDLE_H},
	color,
	)
}

main :: proc() {
	rl.InitWindow(SCREEN_W, SCREEN_H, "Pong")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	player := Paddle{pos = {30, SCREEN_H / 2}, speed = PADDLE_SPEED}
	opponent := Paddle{pos = {SCREEN_W - 30, SCREEN_H / 2}, speed = PADDLE_SPEED}

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()

		// --- input (2 players for now: W/S vs UP/DOWN) ---
		if rl.IsKeyDown(.W) do player.pos.y -= player.speed * dt
		if rl.IsKeyDown(.S) do player.pos.y += player.speed * dt
		if rl.IsKeyDown(.UP) do opponent.pos.y -= opponent.speed * dt
		if rl.IsKeyDown(.DOWN) do opponent.pos.y += opponent.speed * dt

		// --- keep paddles on screen ---
		player.pos.y = clamp(player.pos.y, PADDLE_H / 2, SCREEN_H - PADDLE_H / 2)
		opponent.pos.y = clamp(opponent.pos.y, PADDLE_H / 2, SCREEN_H - PADDLE_H / 2)

		// --- draw ---
		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)
		draw_paddle(player, rl.WHITE)
		draw_paddle(opponent, rl.WHITE)
		rl.EndDrawing()
	}
}
