package main

import rl "vendor:raylib"

SCREEN_W :: 900
SCREEN_H :: 600

main :: proc() {
	rl.InitWindow(SCREEN_W, SCREEN_H, "Asteroids — the entity pool")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	world: World
	world.ship = Ship{pos = {SCREEN_W / 2, SCREEN_H / 2}, radius = 16}
	spawn_wave(&world, 4)

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()

		thrusting := rl.IsKeyDown(.UP)
		update_ship(&world.ship, dt)
		update_asteroids(&world, dt)

		if rl.IsKeyPressed(.R) {
			for &a in world.asteroids do a.active = false // retire every slot
			spawn_wave(&world, 4)
		}

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)
		draw_ship(world.ship, thrusting)
		draw_asteroids(&world)
		rl.DrawText("LEFT/RIGHT rotate — UP thrusts — R redeals the wave", 10, 10, 20, rl.GRAY)
		rl.EndDrawing()
	}
}
