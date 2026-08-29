package main

import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

SCREEN_W :: 800
SCREEN_H :: 600

PADDLE_W :: 100
PADDLE_H :: 16
PADDLE_SPEED :: 520
PADDLE_Y :: SCREEN_H - 40

BALL_RADIUS :: 8
BALL_SPEED :: 420 // constant — no Pong-style speedup here
MAX_BOUNCE_ANGLE :: math.PI / 3 // 60° off straight-up

Paddle :: struct {
	pos: rl.Vector2, // center of the paddle
}

Ball :: struct {
	pos:   rl.Vector2,
	vel:   rl.Vector2,
	stuck: bool, // riding the paddle, waiting for SPACE
}

paddle_rect :: proc(p: Paddle) -> rl.Rectangle {
	return {p.pos.x - PADDLE_W / 2, p.pos.y - PADDLE_H / 2, PADDLE_W, PADDLE_H}
}

stick_ball :: proc(b: ^Ball, p: Paddle) {
	b.stuck = true
	b.pos = {p.pos.x, p.pos.y - PADDLE_H / 2 - BALL_RADIUS}
	b.vel = {}
}

serve_ball :: proc(b: ^Ball) {
	angle := rand.float32_range(-0.5, 0.5) // slight random tilt off straight-up
	b.vel = {BALL_SPEED * math.sin(angle), -BALL_SPEED * math.cos(angle)}
	b.stuck = false
}

main :: proc() {
	rl.InitWindow(SCREEN_W, SCREEN_H, "Breakout")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	paddle := Paddle{pos = {SCREEN_W / 2, PADDLE_Y}}
	ball := Ball{}
	stick_ball(&ball, paddle)

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()

		// --- input ---
		if rl.IsKeyDown(.A) || rl.IsKeyDown(.LEFT) do paddle.pos.x -= PADDLE_SPEED * dt
		if rl.IsKeyDown(.D) || rl.IsKeyDown(.RIGHT) do paddle.pos.x += PADDLE_SPEED * dt
		paddle.pos.x = clamp(paddle.pos.x, PADDLE_W / 2, SCREEN_W - PADDLE_W / 2)

		// --- ball ---
		if ball.stuck {
			ball.pos = {paddle.pos.x, paddle.pos.y - PADDLE_H / 2 - BALL_RADIUS}
			if rl.IsKeyPressed(.SPACE) do serve_ball(&ball)
		} else {
			ball.pos += ball.vel * dt

			// walls: reflect + reposition, same mantra as Pong
			if ball.pos.x < BALL_RADIUS && ball.vel.x < 0 {
				ball.vel.x = -ball.vel.x
				ball.pos.x = BALL_RADIUS
			}
			if ball.pos.x > SCREEN_W - BALL_RADIUS && ball.vel.x > 0 {
				ball.vel.x = -ball.vel.x
				ball.pos.x = SCREEN_W - BALL_RADIUS
			}
			if ball.pos.y < BALL_RADIUS && ball.vel.y < 0 {
				ball.vel.y = -ball.vel.y
				ball.pos.y = BALL_RADIUS
			}

			// paddle: Pong's offset-aim, rotated 90°
			if ball.vel.y > 0 && rl.CheckCollisionCircleRec(ball.pos, BALL_RADIUS, paddle_rect(paddle)) {
				ball.pos.y = paddle.pos.y - PADDLE_H / 2 - BALL_RADIUS
				offset := clamp((ball.pos.x - paddle.pos.x) / (PADDLE_W / 2), -1, 1)
				angle := offset * MAX_BOUNCE_ANGLE
				ball.vel = {BALL_SPEED * math.sin(angle), -BALL_SPEED * math.cos(angle)}
			}

			// lost at the bottom: respawn stuck (lives arrive in lesson 4.3)
			if ball.pos.y > SCREEN_H + BALL_RADIUS {
				stick_ball(&ball, paddle)
			}
		}

		// --- draw ---
		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)
		rl.DrawRectangleRec(paddle_rect(paddle), rl.WHITE)
		rl.DrawCircleV(ball.pos, BALL_RADIUS, rl.WHITE)
		if ball.stuck {
			w := rl.MeasureText("SPACE to serve", 20)
			rl.DrawText("SPACE to serve", (SCREEN_W - w) / 2, SCREEN_H / 2 + 80, 20, rl.GRAY)
		}
		rl.EndDrawing()
	}
}
