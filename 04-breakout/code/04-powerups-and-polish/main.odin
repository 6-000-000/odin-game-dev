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
BALL_SPEED :: 420
MAX_BOUNCE_ANGLE :: math.PI / 3 // 60° off straight-up
MAX_BALLS :: 8
BRICK_ROWS :: 6
BRICK_COLS :: 10
BRICK_TOP :: 80
BRICK_SIDE :: 20
BRICK_PAD :: 4
BRICK_W :: f32(SCREEN_W - 2 * BRICK_SIDE - (BRICK_COLS - 1) * BRICK_PAD) / BRICK_COLS
BRICK_H :: 24
START_LIVES :: 3
SAMPLE_RATE :: 22050
POWERUP_DROP_CHANCE :: 20 // percent per brick broken
POWERUP_FALL_SPEED :: 180
MAX_POWERUPS :: 8
WIDEN_DURATION :: 10 // seconds
WIDEN_SCALE :: 1.6
SLOW_DURATION :: 8 // seconds
SLOW_SCALE :: 0.7

Game_State :: enum {
	Title,
	Playing,
	Game_Over,
	Win,
}
Power_Up_Kind :: enum {
	Widen,
	Multiball,
	Slow,
}

Power_Up :: struct {
	pos, vel: rl.Vector2,
	kind:     Power_Up_Kind,
	active:   bool,
}
Paddle :: struct {
	pos:   rl.Vector2, // center of the paddle
	width: f32, // current width — the W power-up stretches it
}
Ball :: struct {
	pos, vel: rl.Vector2,
	stuck:    bool,
	active:   bool,
}
Brick :: struct {
	rect:  rl.Rectangle,
	alive: bool,
	color: rl.Color,
}
Particle :: struct {
	pos, vel: rl.Vector2,
	life:     f32, // seconds remaining
	color:    rl.Color,
}

// Enum-indexed tables: kind → look, no switch needed.
KIND_COLORS := [Power_Up_Kind]rl.Color{.Widen = rl.GREEN, .Multiball = rl.ORANGE, .Slow = rl.SKYBLUE}
KIND_LETTERS := [Power_Up_Kind]cstring{.Widen = "W", .Multiball = "M", .Slow = "S"}

// The levels from lesson 4.3, one string per brick row ('.' = empty).
LEVELS := [3][BRICK_ROWS]string {
	{"RRRRRRRRRR", "OOOOOOOOOO", "YYYYYYYYYY", "GGGGGGGGGG", "BBBBBBBBBB", "PPPPPPPPPP"},
	{"R.R.R.R.R.", "OOOOOOOOOO", "..Y....Y..", "GG..GG..GG", "BBBBBBBBBB", ".P.P.P.P.P"},
	{"P........P", "YP......PY", "YYP....PYY", "GGYB..BYGG", "GGGYYYYGGG", "BBBBBBBBBB"},
}

// --- audio: synthesized beeps (copied from Pong 3.4) ---
append_u16le :: proc(buf: ^[dynamic]u8, v: u16) {append(buf, u8(v), u8(v >> 8))}
append_u32le :: proc(buf: ^[dynamic]u8, v: u32) {append(buf, u8(v), u8(v >> 8), u8(v >> 16), u8(v >> 24))}

make_beep :: proc(frequency, duration: f32) -> rl.Sound {
	sample_count := int(f32(SAMPLE_RATE) * duration)
	data_size := u32(sample_count * 2)
	wav: [dynamic]u8
	defer delete(wav)
	append(&wav, 'R', 'I', 'F', 'F')
	append_u32le(&wav, 36 + data_size)
	append(&wav, 'W', 'A', 'V', 'E')
	append(&wav, 'f', 'm', 't', ' ')
	append_u32le(&wav, 16)
	append_u16le(&wav, 1)
	append_u16le(&wav, 1)
	append_u32le(&wav, SAMPLE_RATE)
	append_u32le(&wav, SAMPLE_RATE * 2)
	append_u16le(&wav, 2)
	append_u16le(&wav, 16)
	append(&wav, 'd', 'a', 't', 'a')
	append_u32le(&wav, data_size)
	for i in 0 ..< sample_count {
		t := f32(i) / f32(SAMPLE_RATE)
		envelope := 1 - t / duration
		sample := i16(math.sin(2 * math.PI * frequency * t) * 12000 * envelope)
		append_u16le(&wav, transmute(u16)sample)
	}
	wave := rl.LoadWaveFromMemory(".wav", raw_data(wav), i32(len(wav)))
	sound := rl.LoadSoundFromWave(wave)
	rl.UnloadWave(wave)
	return sound
}

paddle_rect :: proc(p: Paddle) -> rl.Rectangle {
	return {p.pos.x - p.width / 2, p.pos.y - PADDLE_H / 2, p.width, PADDLE_H}
}
powerup_rect :: proc(p: Power_Up) -> rl.Rectangle {
	return {p.pos.x - 14, p.pos.y - 10, 28, 20}
}

stick_ball :: proc(b: ^Ball, p: Paddle) {
	b.stuck = true
	b.pos = {p.pos.x, p.pos.y - PADDLE_H / 2 - BALL_RADIUS}
	b.vel = {}
}
serve_ball :: proc(b: ^Ball, speed: f32) {
	angle := rand.float32_range(-0.5, 0.5)
	b.vel = {speed * math.sin(angle), -speed * math.cos(angle)}
	b.stuck = false
}

// One stuck ball in slot 0, everything else off — the fresh-serve state.
reset_balls :: proc(balls: ^[MAX_BALLS]Ball, paddle: Paddle) {
	for &b in balls do b.active = false
	balls[0].active = true
	stick_ball(&balls[0], paddle)
}

// Multiball: clone the first live ball into two free slots, velocity rotated ±30°.
spawn_extra_balls :: proc(balls: ^[MAX_BALLS]Ball) {
	src: ^Ball
	for i in 0 ..< MAX_BALLS {
		if balls[i].active && !balls[i].stuck {
			src = &balls[i]
			break
		}
	}
	if src == nil do return
	spawned := 0
	for i in 0 ..< MAX_BALLS {
		b := &balls[i]
		if b.active do continue
		sign: f32 = spawned == 0 ? 1 : -1
		a := sign * math.PI / 6 // rotate (x,y) by ±30°
		vx := src.vel.x * math.cos(a) - src.vel.y * math.sin(a)
		vy := src.vel.x * math.sin(a) + src.vel.y * math.cos(a)
		b^ = Ball{pos = src.pos, vel = {vx, vy}, active = true}
		spawned += 1
		if spawned == 2 do return
	}
}

spawn_powerup :: proc(powerups: ^[MAX_POWERUPS]Power_Up, pos: rl.Vector2) {
	for i in 0 ..< MAX_POWERUPS {
		p := &powerups[i]
		if p.active do continue
		p^ = Power_Up {
			pos    = pos,
			vel    = {0, POWERUP_FALL_SPEED},
			kind   = Power_Up_Kind(rl.GetRandomValue(0, 2)),
			active = true,
		}
		return
	}
}

// Pong 3.4's burst, now colored (its exercise 2).
spawn_particles :: proc(particles: ^[dynamic]Particle, pos: rl.Vector2, color: rl.Color) {
	for _ in 0 ..< 10 {
		angle := rand.float32_range(0, 2 * math.PI)
		speed := rand.float32_range(60, 220)
		vel := rl.Vector2{math.cos(angle), math.sin(angle)} * speed
		append(particles, Particle{pos = pos, vel = vel, life = rand.float32_range(0.2, 0.5), color = color})
	}
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
	return rl.GRAY
}

// The parser from lesson 4.3: nested loops over rows and characters.
load_level :: proc(bricks: ^[BRICK_ROWS][BRICK_COLS]Brick, level_index: int) -> int {
	level := LEVELS[level_index]
	alive := 0
	for row in 0 ..< BRICK_ROWS {
		for col in 0 ..< BRICK_COLS {
			ch := level[row][col]
			x := f32(BRICK_SIDE) + f32(col) * (BRICK_W + BRICK_PAD)
			y := f32(BRICK_TOP + row * (BRICK_H + BRICK_PAD))
			bricks[row][col] = Brick{rect = {x, y, BRICK_W, BRICK_H}, alive = ch != '.', color = brick_color(ch)}
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
	rl.InitAudioDevice()
	defer rl.CloseAudioDevice()
	rl.SetTargetFPS(60)

	paddle_sfx := make_beep(440, 0.08)
	defer rl.UnloadSound(paddle_sfx)
	brick_sfx := make_beep(440, 0.06) // pitch shifted per row at play time
	defer rl.UnloadSound(brick_sfx)
	powerup_sfx := make_beep(880, 0.1)
	defer rl.UnloadSound(powerup_sfx)
	life_sfx := make_beep(160, 0.35)
	defer rl.UnloadSound(life_sfx)

	state := Game_State.Title
	paddle := Paddle{pos = {SCREEN_W / 2, PADDLE_Y}, width = PADDLE_W}
	balls: [MAX_BALLS]Ball
	reset_balls(&balls, paddle)
	bricks: [BRICK_ROWS][BRICK_COLS]Brick
	level_index, lives := 0, START_LIVES
	bricks_left := load_level(&bricks, level_index)
	powerups: [MAX_POWERUPS]Power_Up
	particles: [dynamic]Particle
	defer delete(particles)
	ball_speed: f32 = BALL_SPEED // single source of truth — Slow bends it
	widen_timer, slow_timer, shake: f32
	camera := rl.Camera2D{zoom = 1}

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()

		switch state {
		case .Title:
			if rl.IsKeyPressed(.SPACE) {
				level_index, lives = 0, START_LIVES
				bricks_left = load_level(&bricks, level_index)
				reset_balls(&balls, paddle)
				paddle.width = PADDLE_W
				ball_speed = BALL_SPEED
				widen_timer, slow_timer = 0, 0
				for &p in powerups do p.active = false
				state = .Playing
			}

		case .Playing:
			if rl.IsKeyDown(.A) || rl.IsKeyDown(.LEFT) do paddle.pos.x -= PADDLE_SPEED * dt
			if rl.IsKeyDown(.D) || rl.IsKeyDown(.RIGHT) do paddle.pos.x += PADDLE_SPEED * dt
			paddle.pos.x = clamp(paddle.pos.x, paddle.width / 2, SCREEN_W - paddle.width / 2)

			// timers are data: tick them down, revert when they expire
			if widen_timer > 0 {
				widen_timer -= dt
				if widen_timer <= 0 do paddle.width = PADDLE_W
			}
			if slow_timer > 0 {
				slow_timer -= dt
				if slow_timer <= 0 {
					ball_speed = BALL_SPEED
					for &b in balls {
						if b.active && !b.stuck do b.vel = rl.Vector2Normalize(b.vel) * ball_speed
					}
				}
			}

			// --- balls (fixed pool, active flags) ---
			balls_active := 0
			for &b in balls {
				if !b.active do continue
				if b.stuck {
					b.pos = {paddle.pos.x, paddle.pos.y - PADDLE_H / 2 - BALL_RADIUS}
					if rl.IsKeyPressed(.SPACE) do serve_ball(&b, ball_speed)
					balls_active += 1
					continue
				}
				b.pos += b.vel * dt

				if b.pos.x < BALL_RADIUS && b.vel.x < 0 {
					b.vel.x = -b.vel.x
					b.pos.x = BALL_RADIUS
				}
				if b.pos.x > SCREEN_W - BALL_RADIUS && b.vel.x > 0 {
					b.vel.x = -b.vel.x
					b.pos.x = SCREEN_W - BALL_RADIUS
				}
				if b.pos.y < BALL_RADIUS && b.vel.y < 0 {
					b.vel.y = -b.vel.y
					b.pos.y = BALL_RADIUS
				}

				if b.vel.y > 0 && rl.CheckCollisionCircleRec(b.pos, BALL_RADIUS, paddle_rect(paddle)) {
					b.pos.y = paddle.pos.y - PADDLE_H / 2 - BALL_RADIUS
					offset := clamp((b.pos.x - paddle.pos.x) / (paddle.width / 2), -1, 1)
					angle := offset * MAX_BOUNCE_ANGLE
					b.vel = {ball_speed * math.sin(angle), -ball_speed * math.cos(angle)}
					rl.PlaySound(paddle_sfx)
				}

				// bricks: which face did we hit?
				brick_hit: for row in 0 ..< BRICK_ROWS {
					for col in 0 ..< BRICK_COLS {
						brick := &bricks[row][col]
						if !brick.alive do continue
						if rl.CheckCollisionCircleRec(b.pos, BALL_RADIUS, brick.rect) {
							brick.alive = false
							bricks_left -= 1

							cx := brick.rect.x + brick.rect.width / 2
							cy := brick.rect.y + brick.rect.height / 2
							overlap_x := BALL_RADIUS + brick.rect.width / 2 - abs(b.pos.x - cx)
							overlap_y := BALL_RADIUS + brick.rect.height / 2 - abs(b.pos.y - cy)
							if overlap_x < overlap_y {
								b.vel.x = -b.vel.x
								b.pos.x += b.pos.x < cx ? -overlap_x : overlap_x
							} else {
								b.vel.y = -b.vel.y
								b.pos.y += b.pos.y < cy ? -overlap_y : overlap_y
							}
							b.vel = rl.Vector2Normalize(b.vel) * ball_speed

							spawn_particles(&particles, {cx, cy}, brick.color)
							rl.SetSoundPitch(brick_sfx, 1 + 0.12 * f32(row)) // higher rows, higher pitch
							rl.PlaySound(brick_sfx)
							if rl.GetRandomValue(1, 100) <= POWERUP_DROP_CHANCE {
								spawn_powerup(&powerups, {cx, cy})
							}
							break brick_hit // one brick per frame
						}
					}
				}

				if b.pos.y > SCREEN_H + BALL_RADIUS do b.active = false
				if b.active do balls_active += 1
			}

			// no balls left: life lost, with a Pong-3.4-style screen shake
			if balls_active == 0 {
				lives -= 1
				shake = 0.4
				rl.PlaySound(life_sfx)
				if lives <= 0 {
					state = .Game_Over
				} else {
					reset_balls(&balls, paddle)
				}
			}

			if bricks_left == 0 {
				level_index += 1
				if level_index >= len(LEVELS) {
					state = .Win
				} else {
					bricks_left = load_level(&bricks, level_index)
					reset_balls(&balls, paddle)
				}
			}

			// --- power-ups fall; the paddle catches ---
			for &p in powerups {
				if !p.active do continue
				p.pos += p.vel * dt
				if p.pos.y > SCREEN_H + 20 {
					p.active = false
					continue
				}
				if rl.CheckCollisionRecs(powerup_rect(p), paddle_rect(paddle)) {
					p.active = false
					rl.PlaySound(powerup_sfx)
					switch p.kind {
					case .Widen:
						widen_timer = WIDEN_DURATION
						paddle.width = PADDLE_W * WIDEN_SCALE
					case .Multiball:
						spawn_extra_balls(&balls)
					case .Slow:
						slow_timer = SLOW_DURATION
						ball_speed = BALL_SPEED * SLOW_SCALE
						for &b in balls {
							if b.active && !b.stuck {
								b.vel = rl.Vector2Normalize(b.vel) * ball_speed
							}
						}
					}
				}
			}

		case .Game_Over, .Win:
			if rl.IsKeyPressed(.SPACE) do state = .Title
		}

		// particles always update (even on menus, looks alive)
		for i := len(particles) - 1; i >= 0; i -= 1 {
			p := &particles[i]
			p.pos += p.vel * dt
			p.life -= dt
			if p.life <= 0 do unordered_remove(&particles, i)
		}
		shake = max(shake - dt, 0)

		// --- draw ---
		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)

		// Pong 3.4 offset every draw call by hand; a camera does it in one line
		camera.offset = {}
		if shake > 0 {
			camera.offset = {
				rand.float32_range(-1, 1) * shake * 12,
				rand.float32_range(-1, 1) * shake * 12,
			}
		}
		rl.BeginMode2D(camera)

		for row in 0 ..< BRICK_ROWS {
			for col in 0 ..< BRICK_COLS {
				brick := bricks[row][col]
				if brick.alive do rl.DrawRectangleRec(brick.rect, brick.color)
			}
		}
		for p in particles {
			rl.DrawCircleV(p.pos, 3, rl.Fade(p.color, p.life * 2))
		}
		for p in powerups {
			if !p.active do continue
			rl.DrawRectangleRec(powerup_rect(p), KIND_COLORS[p.kind])
			letter := KIND_LETTERS[p.kind]
			x := i32(p.pos.x) - rl.MeasureText(letter, 16) / 2
			rl.DrawText(letter, x, i32(p.pos.y) - 8, 16, rl.BLACK)
		}
		rl.DrawRectangleRec(paddle_rect(paddle), rl.WHITE)
		for b in balls {
			if b.active do rl.DrawCircleV(b.pos, BALL_RADIUS, rl.WHITE)
		}

		rl.EndMode2D()

		// HUD last (on top, and unshaken)
		rl.DrawText(rl.TextFormat("LEVEL %d", level_index + 1), 20, 20, 20, rl.GRAY)
		for i in 0 ..< lives {
			rl.DrawCircleV({f32(SCREEN_W - 30 - i * 25), 26}, 7, rl.WHITE)
		}

		switch state {
		case .Title:
			draw_centered("BREAKOUT", 180, 80, rl.WHITE)
			draw_centered("catch the falling letters — SPACE to start", 300, 20, rl.GRAY)
		case .Playing:
			if balls[0].stuck do draw_centered("SPACE to serve", SCREEN_H / 2 + 80, 20, rl.GRAY)
		case .Game_Over, .Win:
			msg: cstring = state == .Win ? "YOU WIN!" : "GAME OVER"
			color := state == .Win ? rl.GREEN : rl.RED
			draw_centered(msg, 200, 70, color)
			draw_centered("SPACE for menu", 300, 20, rl.GRAY)
		}

		rl.EndDrawing()
	}
}
