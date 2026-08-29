package main

import "core:math"
import rl "vendor:raylib"

SCREEN_W :: 800
SCREEN_H :: 450

main :: proc() {
	rl.InitWindow(SCREEN_W, SCREEN_H, "2.2 - drawing gallery")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	for !rl.WindowShouldClose() {
		t := f32(rl.GetTime())

		rl.BeginDrawing()
		rl.ClearBackground(rl.RAYWHITE)

		// --- shapes ---
		rl.DrawCircle(100, 100, 40, rl.SKYBLUE)
		rl.DrawText("DrawCircle", 45, 150, 14, rl.GRAY)

		rl.DrawCircleLines(250, 100, 40, rl.DARKBLUE)
		rl.DrawText("DrawCircleLines", 185, 150, 14, rl.GRAY)

		rl.DrawRectangle(350, 60, 100, 80, rl.GREEN)
		rl.DrawText("DrawRectangle", 350, 150, 14, rl.GRAY)

		rl.DrawRectangleLinesEx({500, 60, 100, 80}, 3, rl.DARKGREEN)
		rl.DrawText("DrawRectangleLinesEx", 490, 150, 14, rl.GRAY)

		rl.DrawTriangle({650, 140}, {700, 60}, {750, 140}, rl.ORANGE)
		rl.DrawText("DrawTriangle", 650, 150, 14, rl.GRAY)

		rl.DrawLineEx({50, 220}, {150, 280}, 5, rl.MAROON)
		rl.DrawText("DrawLineEx", 55, 290, 14, rl.GRAY)

		rl.DrawRing({280, 250}, 30, 40, 0, 270, 32, rl.GOLD)
		rl.DrawText("DrawRing", 245, 300, 14, rl.GRAY)

		rl.DrawRectangleGradientV(400, 200, 120, 100, rl.YELLOW, rl.RED)
		rl.DrawText("DrawRectangleGradientV", 385, 310, 14, rl.GRAY)

		// --- alpha pulse ---
		alpha := 0.5 + 0.5*math.sin(t*4)
		rl.DrawCircleV({650, 250}, 40, rl.ColorAlpha(rl.PURPLE, alpha))
		rl.DrawText("ColorAlpha pulse", 590, 300, 14, rl.GRAY)

		// --- centered text ---
		title :: "2.2 - Drawing Gallery"
		w := rl.MeasureText(title, 30)
		rl.DrawText(title, (SCREEN_W - w)/2, 400, 30, rl.DARKGRAY)

		rl.EndDrawing()
	}
}
