package main

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
		nose := ship_point(c, 0, 10)
		wing_l := ship_point(c, 140, 8)
		wing_r := ship_point(c, -140, 8)
		rl.DrawTriangleLines(nose, wing_l, wing_r, rl.WHITE)
	}
}

main :: proc() {
	rl.InitWindow(SCREEN_W, SCREEN_H, "Asteroids — shooting and splitting")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	world: World
	start_game(&world)
	state := Game_State.Playing

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()

		switch state {
		case .Playing:
			if rl.IsKeyDown(.SPACE) do try_fire(&world)
			update_ship(&world.ship, dt)
			update_asteroids(&world, dt)
			update_bullets(&world, dt)
			collide_bullets(&world)
			collide_ship(&world)

			if world.lives <= 0 {
				state = .Game_Over
			} else if asteroids_remaining(&world) == 0 {
				world.wave += 1
				spawn_wave(&world, world.wave + 3)
			}
		case .Game_Over:
			update_asteroids(&world, dt) // the field keeps drifting behind the text
			if rl.IsKeyPressed(.SPACE) {
				start_game(&world)
				state = .Playing
			}
		}

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)
		draw_asteroids(&world)
		draw_bullets(&world)

		switch state {
		case .Playing:
			draw_ship(world.ship, rl.IsKeyDown(.UP))
		case .Game_Over:
			draw_centered("GAME OVER", 200, 64, rl.WHITE)
			draw_centered(rl.TextFormat("FINAL SCORE %d", world.score), 290, 24, rl.GRAY)
			draw_centered("SPACE to play again", 330, 20, rl.GRAY)
		}

		// HUD
		draw_lives(world.lives)
		draw_centered(rl.TextFormat("%d", world.score), 12, 28, rl.WHITE)
		rl.DrawText(rl.TextFormat("WAVE %d", world.wave), SCREEN_W - 110, 16, 20, rl.GRAY)

		rl.EndDrawing()
	}
}
