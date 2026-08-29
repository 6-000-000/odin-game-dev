package main

import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

SCREEN_W :: 480
SCREEN_H :: 640
GROUND_H :: 80
GROUND_TOP :: SCREEN_H - GROUND_H

// --- feel constants: tune these and re-run ---
GRAVITY :: 1800
FLAP_VELOCITY :: -520
SCROLL_SPEED :: 180
SPAWN_INTERVAL :: 1.4
PIPE_W :: 70
PIPE_GAP :: 150
MAX_PIPES :: 8

BIRD_X :: 120
BIRD_RADIUS :: 14

// juice timers (seconds)
FLASH_TIME :: 0.15 // white flash on death
POP_TIME :: 0.25 // score text grows on each point
WING_TIME :: 0.2 // wing oscillates after each flap

// parallax: each layer scrolls at a fraction of SCROLL_SPEED
HILL_SPACING :: 160
CLOUD_SPACING :: 200
TICK_SPACING :: 24

SAMPLE_RATE :: 22050

DAY_SKY_TOP :: rl.Color{90, 170, 240, 255}
DAY_SKY_BOTTOM :: rl.Color{175, 225, 245, 255}
NIGHT_SKY_TOP :: rl.Color{15, 18, 55, 255}
NIGHT_SKY_BOTTOM :: rl.Color{45, 50, 100, 255}

Game_State :: enum {
	Title,
	Playing,
	Dead,
}

Bird :: struct {
	pos:    rl.Vector2,
	vel:    rl.Vector2,
	radius: f32,
}

Pipe :: struct {
	x:      f32,
	gap_y:  f32,
	gap_h:  f32,
	scored: bool,
	active: bool,
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

pipe_top_rect :: proc(p: Pipe) -> rl.Rectangle {
	return {p.x, 0, PIPE_W, p.gap_y - p.gap_h / 2}
}

pipe_bottom_rect :: proc(p: Pipe) -> rl.Rectangle {
	y := p.gap_y + p.gap_h / 2
	return {p.x, y, PIPE_W, GROUND_TOP - y}
}

spawn_pipe :: proc(pipes: ^[MAX_PIPES]Pipe) {
	for &p in pipes {
		if !p.active {
			p.x = SCREEN_W + 40
			p.gap_y = rand.float32_range(140, GROUND_TOP - 100)
			p.gap_h = PIPE_GAP
			p.scored = false
			p.active = true
			return
		}
	}
}

draw_pipe :: proc(p: Pipe) {
	top := pipe_top_rect(p)
	bottom := pipe_bottom_rect(p)
	rl.DrawRectangleRec(top, rl.GREEN)
	rl.DrawRectangleRec(bottom, rl.GREEN)
	rl.DrawRectangleV({top.x - 3, top.height - 26}, {top.width + 6, 26}, rl.DARKGREEN)
	rl.DrawRectangleV({bottom.x - 3, bottom.y}, {bottom.width + 6, 26}, rl.DARKGREEN)
}

medal :: proc(score: int) -> (color: rl.Color, name: cstring) {
	switch {
	case score >= 30:
		return {255, 215, 0, 255}, "GOLD"
	case score >= 20:
		return {192, 192, 192, 255}, "SILVER"
	case score >= 10:
		return {205, 127, 50, 255}, "BRONZE"
	}
	return {}, ""
}

reset_bird :: proc(bird: ^Bird) {
	bird.pos = {BIRD_X, SCREEN_H / 2}
	bird.vel = {0, 0}
}

flap_pressed :: proc() -> bool {
	return rl.IsKeyPressed(.SPACE) || rl.IsMouseButtonPressed(.LEFT)
}

draw_bird :: proc(bird: Bird, wing_anim: f32) {
	rotation := clamp(bird.vel.y * 0.08, -25, 90)
	// wing: fast oscillation while wing_anim runs down, still otherwise
	wing_angle: f32 = 0
	if wing_anim > 0 {
		wing_angle = math.sin(wing_anim * 50) * 30
	}
	rl.DrawRectanglePro({bird.pos.x, bird.pos.y, 16, 8}, {0, 4}, rotation + wing_angle, rl.ORANGE)
	rl.DrawPoly(bird.pos, 3, bird.radius * 1.8, rotation, rl.YELLOW)
	rad := rotation * rl.DEG2RAD
	eye := bird.pos + rl.Vector2{math.cos(rad), math.sin(rad)} * bird.radius * 0.6
	rl.DrawCircleV(eye, 3.5, rl.WHITE)
}

draw_background :: proc(time, world_x: f32) {
	// slow day/night cycle: 0 = night, 1 = day
	day := (math.sin(time * 0.15) + 1) / 2
	sky_top := rl.ColorLerp(NIGHT_SKY_TOP, DAY_SKY_TOP, day)
	sky_bottom := rl.ColorLerp(NIGHT_SKY_BOTTOM, DAY_SKY_BOTTOM, day)
	rl.DrawRectangleGradientV(0, 0, SCREEN_W, GROUND_TOP, sky_top, sky_bottom)

	// far hills: 0.2x scroll — the mod wraps the offset into one spacing
	hill_color := rl.ColorLerp({25, 40, 70, 255}, {80, 170, 100, 255}, day)
	hill_off := math.mod(world_x * 0.2, HILL_SPACING)
	for i in 0 ..< SCREEN_W / HILL_SPACING + 2 {
		rl.DrawCircle(i32(f32(i * HILL_SPACING) - hill_off), GROUND_TOP + 30, 80, hill_color)
	}

	// mid clouds: 0.5x scroll
	cloud_color := rl.ColorLerp({70, 75, 110, 255}, rl.WHITE, day)
	cloud_off := math.mod(world_x * 0.5, CLOUD_SPACING)
	for i in 0 ..< SCREEN_W / CLOUD_SPACING + 3 {
		x := i32(f32(i * CLOUD_SPACING) - cloud_off)
		rl.DrawEllipse(x, 90 + i32(i % 3) * 70, 46, 18, cloud_color)
	}
}

draw_ground :: proc(world_x: f32) {
	rl.DrawRectangle(0, GROUND_TOP, SCREEN_W, GROUND_H, {222, 216, 149, 255})
	rl.DrawRectangle(0, GROUND_TOP, SCREEN_W, 8, rl.GREEN)
	// scrolling ticks: 1x scroll, wrapped to one tick spacing
	tick_off := math.mod(world_x, TICK_SPACING)
	for x := -tick_off; x < SCREEN_W; x += TICK_SPACING {
		rl.DrawRectangle(i32(x), GROUND_TOP + 10, 4, 12, {190, 180, 120, 255})
	}
}

draw_centered :: proc(text: cstring, y, font_size: i32, color: rl.Color) {
	w := rl.MeasureText(text, font_size)
	rl.DrawText(text, (SCREEN_W - w) / 2, y, font_size, color)
}

main :: proc() {
	rl.InitWindow(SCREEN_W, SCREEN_H, "Flappy Bird")
	defer rl.CloseWindow()
	rl.InitAudioDevice()
	defer rl.CloseAudioDevice()
	rl.SetTargetFPS(60)

	flap_sfx := make_beep(600, 0.05)
	defer rl.UnloadSound(flap_sfx)
	score_sfx := make_beep(900, 0.12)
	defer rl.UnloadSound(score_sfx)
	hit_sfx := make_beep(150, 0.25)
	defer rl.UnloadSound(hit_sfx)

	state := Game_State.Title
	bird := Bird{radius = BIRD_RADIUS}
	reset_bird(&bird)
	time: f32
	world_x: f32 // total px scrolled; layers derive offsets from this

	pipes: [MAX_PIPES]Pipe
	spawn_timer := f32(1)
	score := 0
	best := 0

	flash: f32 // >0 while the death flash is fading
	score_pop: f32 // >0 while the score text is popped
	wing_anim: f32 // >0 while the wing is flapping

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()
		time += dt
		flash = max(0, flash - dt)
		score_pop = max(0, score_pop - dt)
		wing_anim = max(0, wing_anim - dt)

		// the world freezes on death — that's the drama
		if state != .Dead do world_x += SCROLL_SPEED * dt

		switch state {
		case .Title:
			bird.pos.y = SCREEN_H / 2 + math.sin(time * 3) * 10
			if flap_pressed() {
				bird.vel.y = FLAP_VELOCITY
				wing_anim = WING_TIME
				rl.PlaySound(flap_sfx)
				state = .Playing
			}

		case .Playing:
			if flap_pressed() {
				bird.vel.y = FLAP_VELOCITY
				wing_anim = WING_TIME
				rl.PlaySound(flap_sfx)
			}
			bird.vel.y += GRAVITY * dt
			bird.pos += bird.vel * dt

			if bird.pos.y < bird.radius {
				bird.pos.y = bird.radius
				bird.vel.y = 0
			}
			if bird.pos.y > GROUND_TOP - bird.radius {
				best = max(best, score)
				flash = FLASH_TIME
				rl.PlaySound(hit_sfx)
				state = .Dead
			}

			spawn_timer -= dt
			if spawn_timer <= 0 {
				spawn_pipe(&pipes)
				spawn_timer = SPAWN_INTERVAL
			}

			for &p in pipes {
				if !p.active do continue
				p.x -= SCROLL_SPEED * dt
				if p.x < -PIPE_W do p.active = false

				if rl.CheckCollisionCircleRec(bird.pos, bird.radius, pipe_top_rect(p)) ||
				   rl.CheckCollisionCircleRec(bird.pos, bird.radius, pipe_bottom_rect(p)) {
					best = max(best, score)
					flash = FLASH_TIME
					rl.PlaySound(hit_sfx)
					state = .Dead
				}

				if !p.scored && p.x + PIPE_W < bird.pos.x {
					p.scored = true
					score += 1
					score_pop = POP_TIME
					rl.PlaySound(score_sfx)
				}
			}

		case .Dead:
			bird.vel.y += GRAVITY * dt
			bird.pos += bird.vel * dt
			if bird.pos.y > GROUND_TOP - bird.radius {
				bird.pos.y = GROUND_TOP - bird.radius
				bird.vel = {0, 0}
			}
			if rl.IsKeyPressed(.R) {
				reset_bird(&bird)
				for &p in pipes do p.active = false
				spawn_timer = 1
				score = 0
				state = .Title
			}
		}

		// --- draw ---
		rl.BeginDrawing()
		draw_background(time, world_x)
		for p in pipes {
			if !p.active do continue
			draw_pipe(p)
		}
		draw_ground(world_x)
		draw_bird(bird, wing_anim)

		switch state {
		case .Title:
			draw_centered("FLAPPY", 140, 60, rl.WHITE)
			draw_centered("SPACE or click to flap", 220, 20, rl.WHITE)
		case .Playing:
			size := 48 + i32(score_pop / POP_TIME * 18)
			draw_centered(rl.TextFormat("%d", score), 30, size, rl.WHITE)
		case .Dead:
			if bird.pos.y >= GROUND_TOP - bird.radius {
				rl.DrawRectangleRounded({80, 170, 320, 240}, 0.12, 8, rl.Fade(rl.BLACK, 0.7))
				draw_centered("GAME OVER", 190, 40, rl.WHITE)
				draw_centered(rl.TextFormat("score  %d", score), 250, 24, rl.WHITE)
				draw_centered(rl.TextFormat("best  %d", best), 284, 24, rl.WHITE)
				if score >= 10 {
					color, name := medal(score)
					rl.DrawCircle(SCREEN_W / 2, 348, 18, color)
					draw_centered(name, 372, 16, color)
				}
				draw_centered("R to restart", 424, 20, rl.WHITE)
			}
		}

		// death flash covers everything, HUD included
		if flash > 0 {
			rl.DrawRectangle(0, 0, SCREEN_W, SCREEN_H, rl.Fade(rl.WHITE, flash / FLASH_TIME))
		}

		rl.EndDrawing()
	}
}
