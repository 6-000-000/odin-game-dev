package main

import "core:math/rand"
import rl "vendor:raylib"

SCREEN_W :: 900
SCREEN_H :: 600

Game_State :: enum {
	Playing,
	Game_Over,
}

draw_centered :: proc(text: cstring, y, font_size: i32, color: rl.Color) {
	w := rl.MeasureText(text, font_size)
	rl.DrawText(text, (SCREEN_W - w) / 2, y, font_size, color)
}

// Lives as a row of little ships, pointing up (angle 0).
draw_lives :: proc(lives: int) {
	for i in 0 ..< lives {
		c := rl.Vector2{28 + f32(i) * 26, 32}
		rl.DrawTriangleLines(ship_point(c, 0, 10), ship_point(c, 140, 8), ship_point(c, -140, 8), rl.WHITE)
	}
}

main :: proc() {
	rl.InitWindow(SCREEN_W, SCREEN_H, "Asteroids")
	defer rl.CloseWindow()
	rl.InitAudioDevice()
	defer rl.CloseAudioDevice()
	rl.SetTargetFPS(60)

	sfx := load_sounds()
	defer unload_sounds(sfx)

	world: World
	start_game(&world)
	state := Game_State.Playing

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()
		world.shake = max(0, world.shake - dt)

		switch state {
		case .Playing:
			if rl.IsKeyDown(.SPACE) do try_fire(&world, sfx)
			update_ship(&world.ship, dt)
			if rl.IsKeyDown(.UP) do spawn_exhaust(&world)
			update_asteroids(&world, dt)
			update_bullets(&world, dt)
			update_particles(&world, dt)
			collide_bullets(&world, sfx)
			collide_ship(&world, sfx)

			// wave cleared when no active slots remain
			remaining := 0
			for a in world.asteroids {
				if a.active do remaining += 1
			}

			if world.lives <= 0 {
				state = .Game_Over
				rl.PlaySound(sfx.game_over)
			} else if remaining == 0 {
				world.wave += 1
				spawn_wave(&world, world.wave + 3)
				rl.PlaySound(sfx.wave_low) // two tones at once = a jingle; raylib mixes them
				rl.PlaySound(sfx.wave_high)
			}
		case .Game_Over:
			update_asteroids(&world, dt)
			update_particles(&world, dt)
			if rl.IsKeyPressed(.SPACE) {
				start_game(&world)
				state = .Playing
			}
		}

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)

		// the world shakes, the HUD doesn't: camera offset = random jitter while shake > 0
		camera := rl.Camera2D{zoom = 1}
		if world.shake > 0 {
			camera.offset = {rand.float32_range(-1, 1), rand.float32_range(-1, 1)} * world.shake * 24
		}

		rl.BeginMode2D(camera)
		draw_particles(&world)
		draw_asteroids(&world)
		draw_bullets(&world)
		if state == .Playing {
			draw_ship(world.ship)
		}
		rl.EndMode2D()

		// HUD
		draw_lives(world.lives)
		draw_centered(rl.TextFormat("%d", world.score), 12, 28, rl.WHITE)
		rl.DrawText(rl.TextFormat("WAVE %d", world.wave), SCREEN_W - 110, 16, 20, rl.GRAY)

		if state == .Game_Over {
			draw_centered("GAME OVER", 200, 64, rl.WHITE)
			draw_centered(rl.TextFormat("FINAL SCORE %d", world.score), 290, 24, rl.GRAY)
			draw_centered("SPACE to play again", 330, 20, rl.GRAY)
		}

		rl.EndDrawing()
	}
}
