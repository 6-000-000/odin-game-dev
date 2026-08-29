package main

import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

SCREEN_W :: 480
SCREEN_H :: 640
GROUND_H :: 80
GROUND_TOP :: SCREEN_H - GROUND_H

// --- feel constants: tune these and re-run ---
GRAVITY :: 1800 // px/s^2, added to vel.y every frame
FLAP_VELOCITY :: -520 // px/s; negative is UP, because +y points DOWN
SCROLL_SPEED :: 180 // px/s; the world moves left, the bird stays put
SPAWN_INTERVAL :: 1.4 // seconds between pipes
PIPE_W :: 70
PIPE_GAP :: 150
MAX_PIPES :: 8 // fixed pool size — see spawn_pipe for why 8 is plenty

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
	gap_y:  f32, // vertical center of the gap
	gap_h:  f32,
	scored: bool, // next lesson
	active: bool,
}

// Find the first inactive slot and reuse it. If the pool is full, drop the
// spawn — with these constants at most 4 pipes are ever on screen at once.
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
	top_h := p.gap_y - p.gap_h / 2
	bottom_y := p.gap_y + p.gap_h / 2
	rl.DrawRectangleV({p.x, 0}, {PIPE_W, top_h}, rl.GREEN)
	rl.DrawRectangleV({p.x, bottom_y}, {PIPE_W, GROUND_TOP - bottom_y}, rl.GREEN)
	// darker lips at the gap mouths
	rl.DrawRectangleV({p.x - 3, top_h - 26}, {PIPE_W + 6, 26}, rl.DARKGREEN)
	rl.DrawRectangleV({p.x - 3, bottom_y}, {PIPE_W + 6, 26}, rl.DARKGREEN)
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

	pipes: [MAX_PIPES]Pipe // zero-initialized: all inactive
	spawn_timer := f32(1)

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
				state = .Dead
			}

			// --- spawner ---
			spawn_timer -= dt
			if spawn_timer <= 0 {
				spawn_pipe(&pipes)
				spawn_timer = SPAWN_INTERVAL
			}

			// --- scroll & recycle ---
			for &p in pipes {
				if !p.active do continue
				p.x -= SCROLL_SPEED * dt
				if p.x < -PIPE_W do p.active = false // off screen: back to the pool
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
		case .Dead:
			draw_centered("GAME OVER", 200, 48, rl.WHITE)
			draw_centered("R to restart", 270, 20, rl.WHITE)
		}

		rl.EndDrawing()
	}
}
