package main

import rl "vendor:raylib"

// The window is DERIVED from the grid: cells are the truth, pixels are a view.
CELL :: 24
COLS :: 30
ROWS :: 30
SCREEN_W :: CELL * COLS
SCREEN_H :: CELL * ROWS

TICK :: 0.15 // seconds per grid step — the snake's heartbeat

Cell :: struct {
	x, y: int,
}

// Directions are cell offsets, not velocities.
DIR_UP :: Cell{0, -1}
DIR_DOWN :: Cell{0, 1}
DIR_LEFT :: Cell{-1, 0}
DIR_RIGHT :: Cell{1, 0}

BACKGROUND :: rl.Color{15, 15, 18, 255}
GRID_LINE :: rl.Color{255, 255, 255, 8}
BODY_COLOR :: rl.Color{70, 170, 70, 255}
HEAD_COLOR :: rl.Color{140, 230, 140, 255}

// One grid step: new head goes in at the front, tail comes off the back.
// inject_at + pop on a dynamic array is the entire movement engine.
step :: proc(snake: ^[dynamic]Cell, dir: Cell) {
	new_head := Cell{snake[0].x + dir.x, snake[0].y + dir.y}
	inject_at(snake, 0, new_head)
	pop(snake)
}

draw_grid :: proc() {
	for x in 0 ..= COLS do rl.DrawLine(i32(x * CELL), 0, i32(x * CELL), SCREEN_H, GRID_LINE)
	for y in 0 ..= ROWS do rl.DrawLine(0, i32(y * CELL), SCREEN_W, i32(y * CELL), GRID_LINE)
}

main :: proc() {
	rl.InitWindow(SCREEN_W, SCREEN_H, "Snake")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	// The snake is a dynamic array of cells, head at index 0.
	snake: [dynamic]Cell
	defer delete(snake)
	append(&snake, Cell{COLS / 2, ROWS / 2})
	append(&snake, Cell{COLS / 2 - 1, ROWS / 2})
	append(&snake, Cell{COLS / 2 - 2, ROWS / 2})

	dir := DIR_RIGHT // the direction the snake is actually moving
	next_dir := DIR_RIGHT // the direction it will move on the next tick
	acc: f32 // accumulator: real seconds banked toward the next tick

	for !rl.WindowShouldClose() {
		// --- input: buffered, not applied yet ---
		if rl.IsKeyPressed(.UP) || rl.IsKeyPressed(.W) do next_dir = DIR_UP
		if rl.IsKeyPressed(.DOWN) || rl.IsKeyPressed(.S) do next_dir = DIR_DOWN
		if rl.IsKeyPressed(.LEFT) || rl.IsKeyPressed(.A) do next_dir = DIR_LEFT
		if rl.IsKeyPressed(.RIGHT) || rl.IsKeyPressed(.D) do next_dir = DIR_RIGHT

		// --- fixed timestep: bank frame time, spend it in TICK-sized chunks ---
		acc += rl.GetFrameTime()
		for acc >= TICK {
			acc -= TICK
			// Reject 180° turns against the CURRENT direction — this check is
			// what makes "up then left within one tick" survivable (see lesson).
			opposite := Cell{-dir.x, -dir.y}
			if next_dir != opposite do dir = next_dir
			step(&snake, dir)
		}

		// --- draw ---
		rl.BeginDrawing()
		rl.ClearBackground(BACKGROUND)
		draw_grid()
		for c, i in snake {
			color := i == 0 ? HEAD_COLOR : BODY_COLOR
			rl.DrawRectangle(i32(c.x * CELL + 1), i32(c.y * CELL + 1), CELL - 2, CELL - 2, color)
		}
		rl.EndDrawing()
	}
}
