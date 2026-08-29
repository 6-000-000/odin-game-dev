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
BALL_SPEEDUP :: 1.05 // each paddle hit makes the ball 5% faster

WIN_SCORE :: 10
SAMPLE_RATE :: 22050

AI_MAX_SPEED :: 330 // slightly slower than the player — beatable
AI_DEADZONE :: 8 // px; stops paddle jitter

Game_State :: enum {
	Title,
	Playing,
	Game_Over,
}

Paddle :: struct {
	pos:   rl.Vector2,
	speed: f32,
	score: int,
}

Ball :: struct {
	pos: rl.Vector2,
	vel: rl.Vector2,
}

Particle :: struct {
	pos, vel: rl.Vector2,
	life:     f32, // seconds remaining
}

// --- audio: synthesized beeps (from lesson 2.4) ---
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
		envelope := 1 - t/duration
		sample := i16(math.sin(2 * math.PI * frequency * t) * 12000 * envelope)
		append_u16le(&wav, transmute(u16)sample)
	}
	wave := rl.LoadWaveFromMemory(".wav", raw_data(wav), i32(len(wav)))
	sound := rl.LoadSoundFromWave(wave)
	rl.UnloadWave(wave)
	return sound
}

paddle_rect :: proc(p: Paddle) -> rl.Rectangle {
	return {p.pos.x - PADDLE_W / 2, p.pos.y - PADDLE_H / 2, PADDLE_W, PADDLE_H}
}

ball_serve_vel :: proc(toward_left: bool) -> rl.Vector2 {
	angle := rand.float32_range(-0.4, 0.4)
	dir: f32 = toward_left ? -1 : 1
	return {dir * BALL_SPEED * math.cos(angle), BALL_SPEED * math.sin(angle)}
}

// The entire AI: drift toward the ball's y, capped speed, only when the ball approaches.
update_ai :: proc(ai: ^Paddle, ball: Ball, dt: f32) {
	if ball.vel.x < 0 do return // ball moving away — rest
	diff := ball.pos.y - ai.pos.y
	if abs(diff) < AI_DEADZONE do return
	step: f32 = AI_MAX_SPEED * dt
	ai.pos.y += clamp(diff, -step, step)
}

spawn_particles :: proc(particles: ^[dynamic]Particle, pos, base_vel: rl.Vector2) {
	for _ in 0 ..< 12 {
		angle := rand.float32_range(0, 2 * math.PI)
		speed := rand.float32_range(60, 220)
		append(
			particles,
			Particle{
				pos = pos,
				vel = base_vel * 0.3 + {math.cos(angle), math.sin(angle)} * speed,
				life = rand.float32_range(0.2, 0.5),
			},
		)
	}
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
	rl.InitAudioDevice()
	defer rl.CloseAudioDevice()
	rl.SetTargetFPS(60)

	hit_sfx := make_beep(440, 0.08)
	defer rl.UnloadSound(hit_sfx)
	wall_sfx := make_beep(220, 0.06)
	defer rl.UnloadSound(wall_sfx)
	score_sfx := make_beep(660, 0.2)
	defer rl.UnloadSound(score_sfx)

	state := Game_State.Title
	player := Paddle{pos = {30, SCREEN_H / 2}, speed = PADDLE_SPEED}
	opponent := Paddle{pos = {SCREEN_W - 30, SCREEN_H / 2}, speed = PADDLE_SPEED}
	ball := Ball{pos = {SCREEN_W / 2, SCREEN_H / 2}, vel = ball_serve_vel(true)}

	particles: [dynamic]Particle
	defer delete(particles)

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
			if rl.IsKeyDown(.W) do player.pos.y -= player.speed * dt
			if rl.IsKeyDown(.S) do player.pos.y += player.speed * dt
			player.pos.y = clamp(player.pos.y, PADDLE_H / 2, SCREEN_H - PADDLE_H / 2)

			update_ai(&opponent, ball, dt)
			opponent.pos.y = clamp(opponent.pos.y, PADDLE_H / 2, SCREEN_H - PADDLE_H / 2)

			ball.pos += ball.vel * dt

			if ball.pos.y < BALL_RADIUS && ball.vel.y < 0 {
				ball.vel.y = -ball.vel.y
				ball.pos.y = BALL_RADIUS
				rl.PlaySound(wall_sfx)
			}
			if ball.pos.y > SCREEN_H - BALL_RADIUS && ball.vel.y > 0 {
				ball.vel.y = -ball.vel.y
				ball.pos.y = SCREEN_H - BALL_RADIUS
				rl.PlaySound(wall_sfx)
			}

			paddles := [2]Paddle{player, opponent}
			for p in paddles {
				if rl.CheckCollisionCircleRec(ball.pos, BALL_RADIUS, paddle_rect(p)) {
					spawn_particles(&particles, ball.pos, ball.vel)

					ball.vel.x = -ball.vel.x * BALL_SPEEDUP
					ball.pos.x = p.pos.x + (ball.pos.x > p.pos.x ? 1 : -1) * (PADDLE_W / 2 + BALL_RADIUS)
					offset := clamp((ball.pos.y - p.pos.y) / (PADDLE_H / 2), -1, 1)
					ball.vel.y = offset * rl.Vector2Length(ball.vel)

					rl.PlaySound(hit_sfx)
				}
			}

			if ball.pos.x < -BALL_RADIUS {
				opponent.score += 1
				rl.PlaySound(score_sfx)
				ball.pos = {SCREEN_W / 2, SCREEN_H / 2}
				ball.vel = ball_serve_vel(true)
			}
			if ball.pos.x > SCREEN_W + BALL_RADIUS {
				player.score += 1
				rl.PlaySound(score_sfx)
				ball.pos = {SCREEN_W / 2, SCREEN_H / 2}
				ball.vel = ball_serve_vel(false)
			}
			if player.score >= WIN_SCORE || opponent.score >= WIN_SCORE {
				state = .Game_Over
			}

		case .Game_Over:
			if rl.IsKeyPressed(.SPACE) do state = .Title
		}

		// particles always update (even on menus, looks alive)
		for i := len(particles) - 1; i >= 0; i -= 1 {
			p := &particles[i]
			p.pos += p.vel * dt
			p.life -= dt
			if p.life <= 0 do unordered_remove(&particles, i)
		}

		// --- draw ---
		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)
		draw_center_line()

		for p in particles {
			rl.DrawCircleV(p.pos, 3, rl.Fade(rl.SKYBLUE, p.life * 2))
		}

		rl.DrawRectangleRec(paddle_rect(player), rl.WHITE)
		rl.DrawRectangleRec(paddle_rect(opponent), rl.WHITE)
		rl.DrawText(rl.TextFormat("%d", player.score), SCREEN_W / 2 - 80, 20, 60, rl.WHITE)
		rl.DrawText(rl.TextFormat("%d", opponent.score), SCREEN_W / 2 + 50, 20, 60, rl.WHITE)

		switch state {
		case .Title:
			draw_centered("PONG", 150, 80, rl.WHITE)
			draw_centered("W/S to move — beat the AI to 10 — SPACE to start", 260, 20, rl.GRAY)
		case .Playing:
			rl.DrawCircleV(ball.pos, BALL_RADIUS, rl.WHITE)
		case .Game_Over:
			winner: cstring = player.score > opponent.score ? "YOU WIN!" : "AI WINS!"
			draw_centered(winner, 150, 60, rl.WHITE)
			draw_centered("SPACE for menu", 240, 20, rl.GRAY)
		}

		rl.EndDrawing()
	}
}
