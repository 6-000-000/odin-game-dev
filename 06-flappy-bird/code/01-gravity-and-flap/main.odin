package main

import "core:math"
import rl "vendor:raylib"

SCREEN_W :: 480
SCREEN_H :: 640
GROUND_H :: 80
GROUND_TOP :: SCREEN_H - GROUND_H

// --- feel constants: tune these and re-run ---
GRAVITY :: 1800 // px/s^2, added to vel.y every frame
FLAP_VELOCITY :: -520 // px/s; negative is UP, because +y points DOWN

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

reset_bird :: proc(bird: ^Bird) {
	bird.pos = {BIRD_X, SCREEN_H / 2}
	bird.vel = {0, 0}
}

flap_pressed :: proc() -> bool {
	return rl.IsKeyPressed(.SPACE) || rl.IsMouseButtonPressed(.LEFT)
}

draw_bird :: proc(bird: Bird) {
	// nose follows velocity: up to -25 deg climbing, 90 deg (straight down) falling
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

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()
		time += dt

		switch state {
		case .Title:
			// idle bob: a pure sine wave, no physics at all
			bird.pos.y = SCREEN_H / 2 + math.sin(time * 3) * 10
			if flap_pressed() {
				bird.vel.y = FLAP_VELOCITY
				state = .Playing
			}

		case .Playing:
			if flap_pressed() {
				bird.vel.y = FLAP_VELOCITY // impulse: SET the velocity, never add to it
			}
			bird.vel.y += GRAVITY * dt
			bird.pos += bird.vel * dt

			// ceiling: clamp, don't die
			if bird.pos.y < bird.radius {
				bird.pos.y = bird.radius
				bird.vel.y = 0
			}
			// ground: death trigger
			if bird.pos.y > GROUND_TOP - bird.radius {
				state = .Dead
			}

		case .Dead:
			// physics keeps running so the bird tumbles to rest — but no flap
			bird.vel.y += GRAVITY * dt
			bird.pos += bird.vel * dt
			if bird.pos.y > GROUND_TOP - bird.radius {
				bird.pos.y = GROUND_TOP - bird.radius
				bird.vel = {0, 0}
			}
			if rl.IsKeyPressed(.R) {
				reset_bird(&bird)
				state = .Title
			}
		}

		// --- draw ---
		rl.BeginDrawing()
		rl.ClearBackground(rl.SKYBLUE)
		rl.DrawRectangle(0, GROUND_TOP, SCREEN_W, GROUND_H, {222, 216, 149, 255})
		rl.DrawRectangle(0, GROUND_TOP, SCREEN_W, 8, rl.GREEN)
		draw_bird(bird)

		// HUD last
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
