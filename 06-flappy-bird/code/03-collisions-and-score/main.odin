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
	scored: bool, // has this pipe already given its point?
	active: bool,
}

// The collision rects ARE the draw rects — one source of truth.
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

draw_bird :: proc(bird: Bird) {
	rotation := clamp(bird.vel.y * 0.08, -25, 90)
	rl.DrawPoly(bird.pos, 3, bird.radius * 1.8, rotation, rl.YELLOW)
	rad := rotation * rl.DEG2RAD
	eye := bird.pos + rl.Vector2{math.cos(rad), math.sin(rad)} * bird.radius * 0.6
	rl.DrawCircleV(eye, 3.5, rl.WHITE)
}

draw_centered :: proc(text: cstring, y, font_size: i32, color: rl.Color) {
	w := rl.MeasureText(text, font_size)
	rl.DrawText(text, (SCREEN_W - w) / 2, y, font_size, color)
}

main :: proc() {
	rl.InitWindow(SCREEN_W, SCREEN_H, "Flappy Bird")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	state := Game_State.Title
	bird := Bird{radius = BIRD_RADIUS}
	reset_bird(&bird)
	time: f32

	pipes: [MAX_PIPES]Pipe
	spawn_timer := f32(1)
	score := 0
	best := 0 // in-memory only: dies with the process, and that's fine

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()
		time += dt

		switch state {
		case .Title:
			bird.pos.y = SCREEN_H / 2 + math.sin(time * 3) * 10
			if flap_pressed() {
				bird.vel.y = FLAP_VELOCITY
				state = .Playing
			}

		case .Playing:
			if flap_pressed() {
				bird.vel.y = FLAP_VELOCITY
			}
			bird.vel.y += GRAVITY * dt
			bird.pos += bird.vel * dt

			if bird.pos.y < bird.radius {
				bird.pos.y = bird.radius
				bird.vel.y = 0
			}
			if bird.pos.y > GROUND_TOP - bird.radius {
				best = max(best, score)
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
					state = .Dead
				}

				// scoring trigger: fires once, the frame the pipe's right edge
				// crosses behind the bird — edge detection, not overlap counting
				if !p.scored && p.x + PIPE_W < bird.pos.x {
					p.scored = true
					score += 1
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
		rl.ClearBackground(rl.SKYBLUE)

		for p in pipes {
			if !p.active do continue
			draw_pipe(p)
		}
		rl.DrawRectangle(0, GROUND_TOP, SCREEN_W, GROUND_H, {222, 216, 149, 255})
		rl.DrawRectangle(0, GROUND_TOP, SCREEN_W, 8, rl.GREEN)
		draw_bird(bird)

		switch state {
		case .Title:
			draw_centered("FLAPPY", 140, 60, rl.WHITE)
			draw_centered("SPACE or click to flap", 220, 20, rl.WHITE)
		case .Playing:
			draw_centered(rl.TextFormat("%d", score), 30, 48, rl.WHITE)
		case .Dead:
			// panel appears once the bird has finished its tumble
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

		rl.EndDrawing()
	}
}
