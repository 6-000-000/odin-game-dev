package main

import rl "vendor:raylib"

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
		nose := ship_point(c, 0, 10)
		wing_l := ship_point(c, 140, 8)
		wing_r := ship_point(c, -140, 8)
		rl.DrawTriangleLines(nose, wing_l, wing_r, rl.WHITE)
	}
}

main :: proc() {
	rl.InitWindow(SCREEN_W, SCREEN_H, "Asteroids — as an ECS")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	world: World
	defer delete(world.free_list)
	start_game(&world)
	state := Game_State.Playing

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()

		// The whole game is a fixed pipeline of system sweeps. Read this list
		// top to bottom and you know every rule that runs, in order.
		switch state {
		case .Playing:
			system_input(&world, dt)
			system_move(&world, dt)
			system_wrap(&world)
			system_spin(&world, dt)
			system_lifetime(&world, dt)
			system_invuln(&world, dt)
			system_collide_bullets(&world)
			system_collide_ship(&world)

			if world.game.lives <= 0 {
				state = .Game_Over
			} else if rocks_remaining(&world) == 0 {
				world.game.wave += 1
				spawn_wave(&world, world.game.wave + 3)
			}
		case .Game_Over:
			system_move(&world, dt) // the field keeps drifting behind the text
			system_wrap(&world)
			system_spin(&world, dt)
			if rl.IsKeyPressed(.SPACE) {
				start_game(&world)
				state = .Playing
			}
		}

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)
		draw_world(&world)

		switch state {
		case .Playing:
		case .Game_Over:
			draw_centered("GAME OVER", 200, 64, rl.WHITE)
			draw_centered(rl.TextFormat("FINAL SCORE %d", world.game.score), 290, 24, rl.GRAY)
			draw_centered("SPACE to play again", 330, 20, rl.GRAY)
		}

		// HUD
		draw_lives(world.game.lives)
		draw_centered(rl.TextFormat("%d", world.game.score), 12, 28, rl.WHITE)
		rl.DrawText(rl.TextFormat("WAVE %d", world.game.wave), SCREEN_W - 110, 16, 20, rl.GRAY)

		rl.EndDrawing()
	}
}
