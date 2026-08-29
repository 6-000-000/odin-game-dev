package main

import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

SCREEN_W :: 800
SCREEN_H :: 450

PADDLE_W :: 15
PADDLE_H :: 90
PADDLE_SPEED :: 400

BALL_RADIUS :: 8
BALL_SPEED :: 350

Paddle :: struct {
	pos:   rl.Vector2, // center of the paddle
	speed: f32,
}

Ball :: struct {
	pos: rl.Vector2,
	vel: rl.Vector2,
}

paddle_rect :: proc(p: Paddle) -> rl.Rectangle {
	return {p.pos.x - PADDLE_W / 2, p.pos.y - PADDLE_H / 2, PADDLE_W, PADDLE_H}
}

draw_paddle :: proc(p: Paddle, color: rl.Color) {
	rl.DrawRectangleRec(paddle_rect(p), color)
}

// Serve at a shallow random angle toward a random side.
ball_serve_vel :: proc() -> rl.Vector2 {
	angle := rand.float32_range(-0.4, 0.4) // radians off horizontal
	dir: f32 = rl.GetRandomValue(0, 1) == 0 ? -1 : 1
	return {dir * BALL_SPEED * math.cos(angle), BALL_SPEED * math.sin(angle)}
}

main :: proc() {
	rl.InitWindow(SCREEN_W, SCREEN_H, "Pong")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	player := Paddle{pos = {30, SCREEN_H / 2}, speed = PADDLE_SPEED}
	opponent := Paddle{pos = {SCREEN_W - 30, SCREEN_H / 2}, speed = PADDLE_SPEED}
	ball := Ball{pos = {SCREEN_W / 2, SCREEN_H / 2}, vel = ball_serve_vel()}

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()

		// --- input (2 players: W/S vs UP/DOWN) ---
		if rl.IsKeyDown(.W) do player.pos.y -= player.speed * dt
		if rl.IsKeyDown(.S) do player.pos.y += player.speed * dt
		if rl.IsKeyDown(.UP) do opponent.pos.y -= opponent.speed * dt
		if rl.IsKeyDown(.DOWN) do opponent.pos.y += opponent.speed * dt
		player.pos.y = clamp(player.pos.y, PADDLE_H / 2, SCREEN_H - PADDLE_H / 2)
		opponent.pos.y = clamp(opponent.pos.y, PADDLE_H / 2, SCREEN_H - PADDLE_H / 2)

		// --- ball movement ---
		ball.pos += ball.vel * dt

		// bounce off top/bottom walls
		if ball.pos.y < BALL_RADIUS && ball.vel.y < 0 {
			ball.vel.y = -ball.vel.y
			ball.pos.y = BALL_RADIUS
		}
		if ball.pos.y > SCREEN_H - BALL_RADIUS && ball.vel.y > 0 {
			ball.vel.y = -ball.vel.y
			ball.pos.y = SCREEN_H - BALL_RADIUS
		}

		// --- paddle collisions (AABB vs circle) ---
		paddles := [2]Paddle{player, opponent}
		for p in paddles {
			if rl.CheckCollisionCircleRec(ball.pos, BALL_RADIUS, paddle_rect(p)) {
				// reflect horizontally, push clear so it can't double-hit
				ball.vel.x = -ball.vel.x
				ball.pos.x = p.pos.x + (ball.pos.x > p.pos.x ? 1 : -1) * (PADDLE_W / 2 + BALL_RADIUS)

				// aim: where on the paddle it hit (-1 top .. +1 bottom) steers vel.y
				offset := clamp((ball.pos.y - p.pos.y) / (PADDLE_H / 2), -1, 1)
				ball.vel.y = offset * BALL_SPEED
			}
		}

		// --- out of bounds: reset to center (scoring arrives next lesson) ---
		if ball.pos.x < -BALL_RADIUS || ball.pos.x > SCREEN_W + BALL_RADIUS {
			ball.pos = {SCREEN_W / 2, SCREEN_H / 2}
			ball.vel = ball_serve_vel()
		}

		// --- draw ---
		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)
		draw_paddle(player, rl.WHITE)
		draw_paddle(opponent, rl.WHITE)
		rl.DrawCircleV(ball.pos, BALL_RADIUS, rl.WHITE)
		rl.EndDrawing()
	}
}
