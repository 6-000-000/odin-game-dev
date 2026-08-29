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

START_LIVES :: 3

Game_State :: enum {
	Title,
	Playing,
	Game_Over,
	Win,
}

// Levels as data: one string per brick row, one character per brick.
// '.' is empty space; every other character picks a color.
// (A variable, not a constant: constants can't be indexed at runtime.)
LEVELS := [3][BRICK_ROWS]string {
	{
		"RRRRRRRRRR",
		"OOOOOOOOOO",
		"YYYYYYYYYY",
		"GGGGGGGGGG",
		"BBBBBBBBBB",
		"PPPPPPPPPP",
	},
	{
		"R.R.R.R.R.",
		"OOOOOOOOOO",
		"..Y....Y..",
		"GG..GG..GG",
		"BBBBBBBBBB",
		".P.P.P.P.P",
	},
	{
		"P........P",
		"YP......PY",
		"YYP....PYY",
		"GGYB..BYGG",
		"GGGYYYYGGG",
		"BBBBBBBBBB",
	},
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

brick_color :: proc(ch: u8) -> rl.Color {
	switch ch {
	case 'R': return rl.RED
	case 'O': return rl.ORANGE
	case 'Y': return rl.YELLOW
	case 'G': return rl.GREEN
	case 'B': return rl.SKYBLUE
	case 'P': return rl.PURPLE
	}
	return rl.GRAY // unreachable for well-formed levels
}

// The parser: nested loops over rows and characters. Returns the live count.
load_level :: proc(bricks: ^[BRICK_ROWS][BRICK_COLS]Brick, level_index: int) -> int {
	level := LEVELS[level_index]
	alive := 0
	for row in 0 ..< BRICK_ROWS {
		for col in 0 ..< BRICK_COLS {
			ch := level[row][col]
			x := f32(BRICK_SIDE) + f32(col) * (BRICK_W + BRICK_PAD)
			y := f32(BRICK_TOP + row * (BRICK_H + BRICK_PAD))
			bricks[row][col] = Brick {
				rect  = {x, y, BRICK_W, BRICK_H},
				alive = ch != '.',
				color = brick_color(ch),
			}
			if ch != '.' do alive += 1
		}
	}
	return alive
}

draw_centered :: proc(text: cstring, y, font_size: i32, color: rl.Color) {
	w := rl.MeasureText(text, font_size)
	rl.DrawText(text, (SCREEN_W - w) / 2, y, font_size, color)
}

main :: proc() {
	rl.InitWindow(SCREEN_W, SCREEN_H, "Breakout")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	state := Game_State.Title
	paddle := Paddle{pos = {SCREEN_W / 2, PADDLE_Y}}
	ball := Ball{}
	stick_ball(&ball, paddle)

	bricks: [BRICK_ROWS][BRICK_COLS]Brick
	level_index := 0
	lives := START_LIVES
	bricks_left := load_level(&bricks, level_index)

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()

		switch state {
		case .Title:
			if rl.IsKeyPressed(.SPACE) {
				level_index = 0
				lives = START_LIVES
				bricks_left = load_level(&bricks, level_index)
				stick_ball(&ball, paddle)
				state = .Playing
			}

		case .Playing:
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
				if ball.vel.y > 0 &&
				   rl.CheckCollisionCircleRec(ball.pos, BALL_RADIUS, paddle_rect(paddle)) {
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
							ball.vel = rl.Vector2Normalize(ball.vel) * BALL_SPEED
							break brick_hit // one brick per frame is enough
						}
					}
				}

				// ball lost: costs a life, respawn stuck on the paddle
				if ball.pos.y > SCREEN_H + BALL_RADIUS {
					lives -= 1
					if lives <= 0 {
						state = .Game_Over
					} else {
						stick_ball(&ball, paddle)
					}
				}
			}

			// level cleared: next level, or win after the last
			if bricks_left == 0 {
				level_index += 1
				if level_index >= len(LEVELS) {
					state = .Win
				} else {
					bricks_left = load_level(&bricks, level_index)
					stick_ball(&ball, paddle)
				}
			}

		case .Game_Over:
			if rl.IsKeyPressed(.SPACE) do state = .Title
		case .Win:
			if rl.IsKeyPressed(.SPACE) do state = .Title
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

		switch state {
		case .Title:
			draw_centered("BREAKOUT", 200, 80, rl.WHITE)
			draw_centered("A/D or arrows to move — SPACE to start", 320, 20, rl.GRAY)
		case .Playing:
			rl.DrawCircleV(ball.pos, BALL_RADIUS, rl.WHITE)
			if ball.stuck do draw_centered("SPACE to serve", SCREEN_H / 2 + 80, 20, rl.GRAY)
		case .Game_Over:
			draw_centered("GAME OVER", 200, 70, rl.RED)
			draw_centered("SPACE for menu", 300, 20, rl.GRAY)
		case .Win:
			draw_centered("YOU WIN!", 200, 70, rl.GREEN)
			draw_centered("SPACE for menu", 300, 20, rl.GRAY)
		}

		// HUD last (on top)
		rl.DrawText(rl.TextFormat("LEVEL %d", level_index + 1), 20, 20, 20, rl.GRAY)
		for i in 0 ..< lives {
			rl.DrawCircleV({f32(SCREEN_W - 30 - i * 25), 26}, 7, rl.WHITE)
		}
		rl.EndDrawing()
	}
}
