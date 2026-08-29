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

WIN_SCORE :: 10

Game_State :: enum {
	Title,
	Playing,
	Game_Over,
}

Paddle :: struct {
	pos:   rl.Vector2, // center of the paddle
	speed: f32,
	score: int,
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

ball_serve_vel :: proc(toward_left: bool) -> rl.Vector2 {
	angle := rand.float32_range(-0.4, 0.4)
	dir: f32 = toward_left ? -1 : 1
	return {dir * BALL_SPEED * math.cos(angle), BALL_SPEED * math.sin(angle)}
}

draw_center_line :: proc() {
	y: i32 = 0
	for y < SCREEN_H {
		rl.DrawRectangle(SCREEN_W / 2 - 2, y, 4, 20, rl.DARKGRAY)
		y += 40
	}
}

draw_centered :: proc(text: cstring, y, font_size: i32, color: rl.Color) {
	w := rl.MeasureText(text, font_size)
	rl.DrawText(text, (SCREEN_W - w) / 2, y, font_size, color)
}

main :: proc() {
	rl.InitWindow(SCREEN_W, SCREEN_H, "Pong")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	state := Game_State.Title
	player := Paddle{pos = {30, SCREEN_H / 2}, speed = PADDLE_SPEED}
	opponent := Paddle{pos = {SCREEN_W - 30, SCREEN_H / 2}, speed = PADDLE_SPEED}
	ball := Ball{pos = {SCREEN_W / 2, SCREEN_H / 2}, vel = ball_serve_vel(true)}

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()

		switch state {
		case .Title:
			if rl.IsKeyPressed(.SPACE) {
				player.score = 0
				opponent.score = 0
				state = .Playing
			}

		case .Playing:
			// --- input (2 players: W/S vs UP/DOWN) ---
			if rl.IsKeyDown(.W) do player.pos.y -= player.speed * dt
			if rl.IsKeyDown(.S) do player.pos.y += player.speed * dt
			if rl.IsKeyDown(.UP) do opponent.pos.y -= opponent.speed * dt
			if rl.IsKeyDown(.DOWN) do opponent.pos.y += opponent.speed * dt
			player.pos.y = clamp(player.pos.y, PADDLE_H / 2, SCREEN_H - PADDLE_H / 2)
			opponent.pos.y = clamp(opponent.pos.y, PADDLE_H / 2, SCREEN_H - PADDLE_H / 2)

			// --- ball ---
			ball.pos += ball.vel * dt

			if ball.pos.y < BALL_RADIUS && ball.vel.y < 0 {
				ball.vel.y = -ball.vel.y
				ball.pos.y = BALL_RADIUS
			}
			if ball.pos.y > SCREEN_H - BALL_RADIUS && ball.vel.y > 0 {
				ball.vel.y = -ball.vel.y
				ball.pos.y = SCREEN_H - BALL_RADIUS
			}

			paddles := [2]Paddle{player, opponent}
			for p in paddles {
				if rl.CheckCollisionCircleRec(ball.pos, BALL_RADIUS, paddle_rect(p)) {
					ball.vel.x = -ball.vel.x
					ball.pos.x = p.pos.x + (ball.pos.x > p.pos.x ? 1 : -1) * (PADDLE_W / 2 + BALL_RADIUS)
					offset := clamp((ball.pos.y - p.pos.y) / (PADDLE_H / 2), -1, 1)
					ball.vel.y = offset * BALL_SPEED
				}
			}

			// --- scoring ---
			if ball.pos.x < -BALL_RADIUS {
				opponent.score += 1
				ball.pos = {SCREEN_W / 2, SCREEN_H / 2}
				ball.vel = ball_serve_vel(true) // serve to the player who was scored on
			}
			if ball.pos.x > SCREEN_W + BALL_RADIUS {
				player.score += 1
				ball.pos = {SCREEN_W / 2, SCREEN_H / 2}
				ball.vel = ball_serve_vel(false)
			}
			if player.score >= WIN_SCORE || opponent.score >= WIN_SCORE {
				state = .Game_Over
			}

		case .Game_Over:
			if rl.IsKeyPressed(.SPACE) do state = .Title
		}

		// --- draw ---
		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)
		draw_center_line()
		draw_paddle(player, rl.WHITE)
		draw_paddle(opponent, rl.WHITE)

		// scores
		rl.DrawText(rl.TextFormat("%d", player.score), SCREEN_W / 2 - 80, 20, 60, rl.WHITE)
		rl.DrawText(rl.TextFormat("%d", opponent.score), SCREEN_W / 2 + 50, 20, 60, rl.WHITE)

		switch state {
		case .Title:
			draw_centered("PONG", 150, 80, rl.WHITE)
			draw_centered("first to 10 — SPACE to start", 260, 20, rl.GRAY)
		case .Playing:
			rl.DrawCircleV(ball.pos, BALL_RADIUS, rl.WHITE)
		case .Game_Over:
			winner: cstring = player.score > opponent.score ? "LEFT WINS!" : "RIGHT WINS!"
			draw_centered(winner, 150, 60, rl.WHITE)
			draw_centered("SPACE for menu", 240, 20, rl.GRAY)
		}

		rl.EndDrawing()
	}
}
