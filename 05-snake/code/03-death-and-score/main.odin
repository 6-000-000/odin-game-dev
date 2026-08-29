package main

import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:os"
import "core:strconv"
import rl "vendor:raylib"

CELL :: 24
COLS :: 30
ROWS :: 30
SCREEN_W :: CELL * COLS
SCREEN_H :: CELL * ROWS

START_TICK :: 0.15
MIN_TICK :: 0.06
SPEEDUP :: 0.004

SAMPLE_RATE :: 22050

HIGHSCORE_FILE :: "highscore.txt"

Game_State :: enum {
	Playing,
	Game_Over,
}

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

// --- save file: one integer in a text file, tolerated, never trusted ---
load_highscore :: proc() -> int {
	best := 0 // missing file, garbage contents: we just start at 0
	data, err := os.read_entire_file(HIGHSCORE_FILE, context.allocator)
	if err == nil {
		defer delete(data)
		if v, ok := strconv.parse_int(string(data)); ok {
			best = v
		}
	}
	return best
}

save_highscore :: proc(best: int) {
	buf := fmt.tprintf("%d", best)
	_ = os.write_entire_file(HIGHSCORE_FILE, transmute([]u8)buf)
}

// --- audio: synthesized beeps (same make_beep as Pong, lesson 3.4) ---
append_u16le :: proc(buf: ^[dynamic]u8, v: u16) {append(buf, u8(v), u8(v >> 8))}
append_u32le :: proc(buf: ^[dynamic]u8, v: u32) {append(buf, u8(v), u8(v >> 8), u8(v >> 16), u8(v >> 24))}

make_beep :: proc(frequency, duration: f32) -> rl.Sound {
	sample_count := int(f32(SAMPLE_RATE) * duration)
	data_size := u32(sample_count * 2)
	wav: [dynamic]u8
	defer delete(wav)
	append(&wav, 'R', 'I', 'F', 'F')
	append_u32le(&wav, 36 + data_size)
	append(&wav, 'W', 'A', 'V', 'E')
	append(&wav, 'f', 'm', 't', ' ')
	append_u32le(&wav, 16)
	append_u16le(&wav, 1)
	append_u16le(&wav, 1)
	append_u32le(&wav, SAMPLE_RATE)
	append_u32le(&wav, SAMPLE_RATE * 2)
	append_u16le(&wav, 2)
	append_u16le(&wav, 16)
	append(&wav, 'd', 'a', 't', 'a')
	append_u32le(&wav, data_size)
	for i in 0 ..< sample_count {
		t := f32(i) / f32(SAMPLE_RATE)
		envelope := 1 - t / duration
		sample := i16(math.sin(2 * math.PI * frequency * t) * 12000 * envelope)
		append_u16le(&wav, transmute(u16)sample)
	}
	wave := rl.LoadWaveFromMemory(".wav", raw_data(wav), i32(len(wav)))
	sound := rl.LoadSoundFromWave(wave)
	rl.UnloadWave(wave)
	return sound
}

step :: proc(snake: ^[dynamic]Cell, dir: Cell, grow: bool) {
	new_head := Cell{snake[0].x + dir.x, snake[0].y + dir.y}
	inject_at(snake, 0, new_head)
	if !grow do pop(snake)
}

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

reset_snake :: proc(snake: ^[dynamic]Cell) {
	clear(snake)
	append(snake, Cell{COLS / 2, ROWS / 2})
	append(snake, Cell{COLS / 2 - 1, ROWS / 2})
	append(snake, Cell{COLS / 2 - 2, ROWS / 2})
}

draw_grid :: proc() {
	for x in 0 ..= COLS do rl.DrawLine(i32(x * CELL), 0, i32(x * CELL), SCREEN_H, GRID_LINE)
	for y in 0 ..= ROWS do rl.DrawLine(0, i32(y * CELL), SCREEN_W, i32(y * CELL), GRID_LINE)
}

draw_centered :: proc(text: cstring, y, font_size: i32, color: rl.Color) {
	w := rl.MeasureText(text, font_size)
	rl.DrawText(text, (SCREEN_W - w) / 2, y, font_size, color)
}

main :: proc() {
	rl.InitWindow(SCREEN_W, SCREEN_H, "Snake")
	defer rl.CloseWindow()
	rl.InitAudioDevice()
	defer rl.CloseAudioDevice()
	rl.SetTargetFPS(60)

	eat_sfx := make_beep(660, 0.07)
	defer rl.UnloadSound(eat_sfx)
	death_sfx := make_beep(140, 0.3)
	defer rl.UnloadSound(death_sfx)

	snake: [dynamic]Cell
	defer delete(snake)
	reset_snake(&snake)

	dir := DIR_RIGHT
	next_dir := DIR_RIGHT
	acc: f32
	tick: f32 = START_TICK
	score := 0
	food := spawn_food(snake)
	best := load_highscore()
	new_best := false

	state := Game_State.Playing

	for !rl.WindowShouldClose() {
		switch state {
		case .Playing:
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

				new_head := Cell{snake[0].x + dir.x, snake[0].y + dir.y}
				hit_wall := new_head.x < 0 || new_head.x >= COLS || new_head.y < 0 || new_head.y >= ROWS
				eating := new_head == food

				// The tail tip VACATES this tick (unless growing), so chasing
				// your tail is legal: check the body minus its last cell.
				limit := eating ? len(snake) : len(snake) - 1
				hit_self := false
				for c in snake[:limit] {
					if c == new_head {
						hit_self = true
						break
					}
				}

				if hit_wall || hit_self {
					state = .Game_Over
					rl.PlaySound(death_sfx)
					if score > best {
						best = score
						new_best = true
						save_highscore(best)
					}
					break // stop consuming accumulated time — the run is over
				}

				step(&snake, dir, eating)
				if eating {
					score += 1
					tick = max(MIN_TICK, START_TICK - SPEEDUP * f32(score))
					food = spawn_food(snake)
					rl.PlaySound(eat_sfx)
				}
			}

		case .Game_Over:
			if rl.IsKeyPressed(.R) {
				reset_snake(&snake)
				dir = DIR_RIGHT
				next_dir = DIR_RIGHT
				acc = 0
				tick = START_TICK
				score = 0
				new_best = false
				food = spawn_food(snake)
				state = .Playing
			}
		}

		// --- draw ---
		rl.BeginDrawing()
		rl.ClearBackground(BACKGROUND)
		draw_grid()

		pulse := 1 + 0.15 * math.sin(f32(rl.GetTime()) * 6)
		food_center := rl.Vector2{f32(food.x * CELL + CELL / 2), f32(food.y * CELL + CELL / 2)}
		rl.DrawCircleV(food_center, (CELL / 2 - 4) * pulse, rl.RED)

		for c, i in snake {
			color := i == 0 ? HEAD_COLOR : BODY_COLOR
			rl.DrawRectangle(i32(c.x * CELL + 1), i32(c.y * CELL + 1), CELL - 2, CELL - 2, color)
		}

		// HUD
		rl.DrawText(rl.TextFormat("SCORE %d", score), 10, 10, 20, rl.WHITE)
		best_text := rl.TextFormat("BEST %d", best)
		rl.DrawText(best_text, SCREEN_W - rl.MeasureText(best_text, 20) - 10, 10, 20, rl.GRAY)

		if state == .Game_Over {
			rl.DrawRectangle(0, 0, SCREEN_W, SCREEN_H, rl.Fade(rl.BLACK, 0.65))
			draw_centered("GAME OVER", 250, 60, rl.RED)
			draw_centered(rl.TextFormat("score %d", score), 340, 24, rl.WHITE)
			if new_best {
				draw_centered("NEW BEST!", 374, 24, rl.GOLD)
			} else {
				draw_centered(rl.TextFormat("best %d", best), 374, 24, rl.GRAY)
			}
			draw_centered("R to restart", 424, 20, rl.GRAY)
		}

		rl.EndDrawing()
	}
}
