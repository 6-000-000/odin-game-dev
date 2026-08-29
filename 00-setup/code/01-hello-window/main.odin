package main

import rl "vendor:raylib"

main :: proc() {
	rl.InitWindow(800, 450, "My first raylib window")
	defer rl.CloseWindow()

	rl.SetTargetFPS(60)

	for !rl.WindowShouldClose() {
		rl.BeginDrawing()
		rl.ClearBackground(rl.RAYWHITE)
		rl.DrawText("It works!", 350, 210, 20, rl.DARKGRAY)
		rl.EndDrawing()
	}
}
