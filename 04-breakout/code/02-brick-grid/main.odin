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

BRICK_ROWS :: 6
BRICK_COLS :: 10
BRICK_TOP :: 80 // px from the top of the screen
BRICK_SIDE :: 20 // px margin on left/right
BRICK_PAD :: 4 // px gap between bricks
BRICK_W :: f32(SCREEN_W - 2 * BRICK_SIDE - (BRICK_COLS - 1) * BRICK_PAD) / BRICK_COLS
BRICK_H :: 24

row_color :: proc(row: int) -> rl.Color {
	colors := [BRICK_ROWS]rl.Color{rl.RED, rl.ORANGE, rl.YELLOW, rl.GREEN, rl.SKYBLUE, rl.PURPLE}
	return colors[row]
}

Paddle :: struct {
	pos: rl.Vector2, // center of the paddle
}

Ball :: struct {
	pos:   rl.Vector2,
	vel:   rl.Vector2,
	stuck: bool, // riding the paddle, waiting for SPACE
}

Brick :: struct {
	rect:  rl.Rectangle,
	alive: bool, // dead bricks stop colliding and drawing
	color: rl.Color,
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

init_bricks :: proc(bricks: ^[BRICK_ROWS][BRICK_COLS]Brick) {
	for row in 0 ..< BRICK_ROWS {
		for col in 0 ..< BRICK_COLS {
			x := f32(BRICK_SIDE) + f32(col) * (BRICK_W + BRICK_PAD)
			y := f32(BRICK_TOP + row * (BRICK_H + BRICK_PAD))
			bricks[row][col] = Brick {
				rect  = {x, y, BRICK_W, BRICK_H},
				alive = true,
				color = row_color(row),
			}
		}
	}
}

main :: proc() {
	rl.InitWindow(SCREEN_W, SCREEN_H, "Breakout")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	paddle := Paddle{pos = {SCREEN_W / 2, PADDLE_Y}}
	ball := Ball{}
	stick_ball(&ball, paddle)

	bricks: [BRICK_ROWS][BRICK_COLS]Brick
	init_bricks(&bricks)
	bricks_left := BRICK_ROWS * BRICK_COLS

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

			// bricks: which face did we hit?
			brick_hit: for row in 0 ..< BRICK_ROWS {
				for col in 0 ..< BRICK_COLS {
					b := &bricks[row][col]
					if !b.alive do continue
					if rl.CheckCollisionCircleRec(ball.pos, BALL_RADIUS, b.rect) {
						b.alive = false
						bricks_left -= 1

						// penetration on each axis — the SMALLER overlap is the face
						cx := b.rect.x + b.rect.width / 2
						cy := b.rect.y + b.rect.height / 2
						overlap_x := BALL_RADIUS + b.rect.width / 2 - abs(ball.pos.x - cx)
						overlap_y := BALL_RADIUS + b.rect.height / 2 - abs(ball.pos.y - cy)
						if overlap_x < overlap_y {
							ball.vel.x = -ball.vel.x
							ball.pos.x += ball.pos.x < cx ? -overlap_x : overlap_x
						} else {
							ball.vel.y = -ball.vel.y
							ball.pos.y += ball.pos.y < cy ? -overlap_y : overlap_y
						}
						// flips preserve speed in exact math; floats aren't exact — pin it
						ball.vel = rl.Vector2Normalize(ball.vel) * BALL_SPEED
						break brick_hit // one brick per frame is enough
					}
				}
			}

			// lost at the bottom: respawn stuck (lives arrive in lesson 4.3)
			if ball.pos.y > SCREEN_H + BALL_RADIUS {
				stick_ball(&ball, paddle)
			}
		}

		// --- draw ---
		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)

		for row in 0 ..< BRICK_ROWS {
			for col in 0 ..< BRICK_COLS {
				b := bricks[row][col]
				if b.alive do rl.DrawRectangleRec(b.rect, b.color)
			}
		}

		rl.DrawRectangleRec(paddle_rect(paddle), rl.WHITE)
		rl.DrawCircleV(ball.pos, BALL_RADIUS, rl.WHITE)

		// HUD last (on top)
		rl.DrawText(rl.TextFormat("bricks: %d", bricks_left), 20, 20, 20, rl.GRAY)
		if ball.stuck {
			w := rl.MeasureText("SPACE to serve", 20)
			rl.DrawText("SPACE to serve", (SCREEN_W - w) / 2, SCREEN_H / 2 + 80, 20, rl.GRAY)
		}
		rl.EndDrawing()
	}
}
