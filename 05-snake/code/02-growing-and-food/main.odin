package main

import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

CELL :: 24
COLS :: 30
ROWS :: 30
SCREEN_W :: CELL * COLS
SCREEN_H :: CELL * ROWS

// The speed ramp: every food shaves SPEEDUP seconds off the tick, floored at MIN_TICK.
START_TICK :: 0.15
MIN_TICK :: 0.06
SPEEDUP :: 0.004

Cell :: struct {
	x, y: int,
}

DIR_UP :: Cell{0, -1}
DIR_DOWN :: Cell{0, 1}
DIR_LEFT :: Cell{-1, 0}
DIR_RIGHT :: Cell{1, 0}

BACKGROUND :: rl.Color{15, 15, 18, 255}
GRID_LINE :: rl.Color{255, 255, 255, 8}
BODY_COLOR :: rl.Color{70, 170, 70, 255}
HEAD_COLOR :: rl.Color{140, 230, 140, 255}

// grow=true keeps the tail this tick — that's the whole growth mechanism.
step :: proc(snake: ^[dynamic]Cell, dir: Cell, grow: bool) {
	new_head := Cell{snake[0].x + dir.x, snake[0].y + dir.y}
	inject_at(snake, 0, new_head)
	if !grow do pop(snake)
}

// Rejection sampling: pick a random cell, retry while it overlaps the body.
// Fine until the board is nearly full — and "nearly full" means you already won.
spawn_food :: proc(snake: [dynamic]Cell) -> Cell {
	for {
		cell := Cell{int(rand.int31_max(COLS)), int(rand.int31_max(ROWS))}
		occupied := false
		for c in snake {
			if c == cell {
				occupied = true
				break
			}
		}
		if !occupied do return cell
	}
}

draw_grid :: proc() {
	for x in 0 ..= COLS do rl.DrawLine(i32(x * CELL), 0, i32(x * CELL), SCREEN_H, GRID_LINE)
	for y in 0 ..= ROWS do rl.DrawLine(0, i32(y * CELL), SCREEN_W, i32(y * CELL), GRID_LINE)
}

main :: proc() {
	rl.InitWindow(SCREEN_W, SCREEN_H, "Snake")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	snake: [dynamic]Cell
	defer delete(snake)
	append(&snake, Cell{COLS / 2, ROWS / 2})
	append(&snake, Cell{COLS / 2 - 1, ROWS / 2})
	append(&snake, Cell{COLS / 2 - 2, ROWS / 2})

	dir := DIR_RIGHT
	next_dir := DIR_RIGHT
	acc: f32
	tick: f32 = START_TICK
	score := 0
	food := spawn_food(snake)

	for !rl.WindowShouldClose() {
		// --- input: buffered ---
		if rl.IsKeyPressed(.UP) || rl.IsKeyPressed(.W) do next_dir = DIR_UP
		if rl.IsKeyPressed(.DOWN) || rl.IsKeyPressed(.S) do next_dir = DIR_DOWN
		if rl.IsKeyPressed(.LEFT) || rl.IsKeyPressed(.A) do next_dir = DIR_LEFT
		if rl.IsKeyPressed(.RIGHT) || rl.IsKeyPressed(.D) do next_dir = DIR_RIGHT

		// --- fixed timestep ---
		acc += rl.GetFrameTime()
		for acc >= tick {
			acc -= tick
			opposite := Cell{-dir.x, -dir.y}
			if next_dir != opposite do dir = next_dir

			eating := Cell{snake[0].x + dir.x, snake[0].y + dir.y} == food
			step(&snake, dir, eating)
			if eating {
				score += 1
				tick = max(MIN_TICK, START_TICK - SPEEDUP * f32(score))
				food = spawn_food(snake)
			}
		}

		// --- draw ---
		rl.BeginDrawing()
		rl.ClearBackground(BACKGROUND)
		draw_grid()

		// food: a circle pulsing on a sine wave, computed from wall-clock time
		pulse := 1 + 0.15 * math.sin(f32(rl.GetTime()) * 6)
		food_center := rl.Vector2{f32(food.x * CELL + CELL / 2), f32(food.y * CELL + CELL / 2)}
		rl.DrawCircleV(food_center, (CELL / 2 - 4) * pulse, rl.RED)

		for c, i in snake {
			color := i == 0 ? HEAD_COLOR : BODY_COLOR
			rl.DrawRectangle(i32(c.x * CELL + 1), i32(c.y * CELL + 1), CELL - 2, CELL - 2, color)
		}

		rl.DrawText(rl.TextFormat("SCORE %d", score), 10, 10, 20, rl.WHITE)
		rl.EndDrawing()
	}
}
