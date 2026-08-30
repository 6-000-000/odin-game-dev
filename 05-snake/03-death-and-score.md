# 5.3 Death, score, and saving

**Module:** 05-snake

## Goals

- Kill the snake: wall collision and self collision → `.Game_Over`
- Persist the high score across runs in a plain-text save file
- Restart with R: a complete reset of every run-scoped variable
- Reuse Pong's synthesized beeps for eating and dying

## New concepts

| Concept | What it is |
|---|---|
| `os.read_entire_file` / `os.write_entire_file` | Whole-file I/O in one call — returns `([]u8, Error)` / `Error` |
| `strconv.parse_int` | `string` → `(int, ok)` — parsing without exceptions |
| `fmt.tprintf` | sprintf into the *temp allocator* — an arena, no per-string cleanup |
| `transmute([]u8)` | Reinterpret a `string`'s bytes for a byte-slice API |
| Tail-tip rule | The cell the tail vacates this tick is **not** a collision |

## Walkthrough

### The state machine returns (and swallows the loop)

Death means the game can be over, so Pong's architecture comes back — this time with just two states (no title screen; Snake starts mid-run):

```odin
Game_State :: enum {
	Playing,
	Game_Over,
}
```

This is a restructure before it's a feature: **everything** from lessons 5.1–5.2 — the input buffering *and* the accumulator loop — moves under `case .Playing:`, and the new `case .Game_Over:` holds the R-restart you'll see below. The skeleton:

```odin
state := Game_State.Playing
for !rl.WindowShouldClose() {
	switch state {
	case .Playing:
		// ... input buffering + accumulator loop from lessons 5.1/5.2 ...
	case .Game_Over:
		// R restarts (shown below)
	}
	// drawing runs in every state — the world stays visible behind the overlay
}
```

Two smaller refactors ride along. First, startup now calls `reset_snake(&snake)` — the same proc R uses — instead of the three inline `append`s from 5.1 (write the starting body once, use it twice). Second, the eat test no longer computes the next cell inline: `new_head` is hoisted to the top of the tick and shared by the wall check, the eat test, and the self-collision — one computation, three consumers, as the death code below shows.

### Two ways to die

Death is decided on the tick, on the cell the head is *about to* enter — before `step` runs:

```odin
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
```

The wall test is a bounds check — integer grid coordinates make it trivial. The self test holds the one subtle rule in all of Snake: the cell the tail currently occupies is legal to move into, because the tail leaves it *on this same tick*. Drop the `limit` math and you'll hand out false deaths whenever a player chases their tail one cell behind. When growing (`eating`), the tail stays, so the whole body counts. `snake[:limit]` is a slice of the dynamic array — a view, not a copy.

Both deaths converge on a single transition:

```odin
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
```

Side effects live at the transition, same discipline as Pong's state machine: the save fires exactly once, on the tick the run ends — never in a per-frame HUD path. The `break` abandons whatever time is still banked in the accumulator; leftover ticks must not move a dead snake.

### The save file: one integer, zero ceremony

The filename is a constant — `HIGHSCORE_FILE :: "highscore.txt"` — and the whole persistence layer is two procs:

```odin
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
```

Reading: the whole file lands in memory, allocated from `context.allocator` (hence `defer delete(data)`), and parsed with `strconv.parse_int`, which returns `(value, ok)`. If *anything* goes wrong — file missing, permissions, someone wrote "banana" in it — the game shrugs and starts at 0. Writing: `fmt.tprintf` formats the int onto the temp allocator (an arena — no per-string cleanup needed), and `transmute([]u8)` reinterprets the string's bytes for the byte-slice API: same pointer, same length, no copy. `write_entire_file` returns an `Error`; we assign it to `_` because a failed save is not worth crashing a game over — but the `_ =` is a deliberate choice, made visible.

The path is relative: the file lands wherever you launch the game from (`odin run 05-snake/code/03-death-and-score` puts it in the repo root). Find it, open it, edit it — it's plain text. Set it to 99999, re-run, and watch the game-over screen believe you. That's not a bug; it's a reminder that client-side saves are a convenience, not a security boundary.

One gotcha before you try: `parse_int` is strict — it rejects anything that isn't *exactly* a number, including the trailing newline most editors append on save. If your hand-edit silently resets to 0, that's why (remember: "garbage contents: we just start at 0"). Hardening it is one line — `strconv.parse_int(strings.trim_space(string(data)))` — worth adding if you plan to hand-edit often.

🌐 **Web dev callout — it's localStorage, minus the ceremony**
> Synchronous string I/O, a schema of your own invention, zero validation you didn't write yourself, fully user-editable: this is `localStorage.setItem("best", score)` with the browser swapped for a filesystem. The discipline transfers directly: treat reads as untrusted (`parse_int` returns `ok` for a reason — one corrupt file must never crash the game), write only at meaningful moments, and never store anything client-side you wouldn't want the user to modify. When you later meet grown-up save systems — versioned, checksummed, binary — they're this same file with more paranoia.

### Restart

R on the game-over screen resets everything the run mutated:

```odin
if rl.IsKeyPressed(.R) {
	reset_snake(&snake) // clear + re-append the starting three cells
	dir = DIR_RIGHT
	next_dir = DIR_RIGHT
	acc = 0
	tick = START_TICK
	score = 0
	new_best = false
	food = spawn_food(snake)
	state = .Playing
}
```

`reset_snake` is `clear(snake)` — length back to 0, capacity kept, no reallocation — plus the three starting `append`s. Note `acc = 0`: time banked by the dead run must not leak into the new one. The full list *is* the lesson: a restart is only correct when every run-scoped variable is in it. If a bug ever appears "only on the second run," something is missing from this list.

The beeps are Pong's `make_beep` (lesson 3.4) copied verbatim — all four pieces (`SAMPLE_RATE`, the two append helpers, the proc) — with `rl.InitAudioDevice()` / `defer rl.CloseAudioDevice()` joining `InitWindow` in `main`. Two sounds cover the module: `eat_sfx := make_beep(660, 0.07)` and `death_sfx := make_beep(140, 0.3)`, each with its `defer rl.UnloadSound`. The death beep fires in the transition you already saw; the eat beep is one line inside the `if eating` block — `rl.PlaySound(eat_sfx)`. Audio reuse is like code reuse, but louder.

### The game-over screen

The draw side switches on `state` too — same discipline as update, same as Pong. The world (grid, food, snake, HUD) draws unconditionally; the overlay stacks on top in `.Game_Over`:

```odin
switch state {
case .Playing:
case .Game_Over:
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
```

The fullscreen `rl.Fade(rl.BLACK, 0.65)` rectangle dims everything drawn so far — HUD included, which is why the panel re-displays score and best rather than leaving them readable under the dimmer. Centering is `draw_centered`, Pong 3.3's helper ported verbatim (`MeasureText`, then draw at `(SCREEN_W - w) / 2`).

One HUD detail worth stealing: the best score is right-aligned with `best_text := rl.TextFormat("BEST %d", best)` assigned to a variable *once*, then fed to both `rl.MeasureText` and `rl.DrawText`. Never call `rl.TextFormat` twice in one expression — it uses a single static buffer, so the second call would clobber the first. Binding to a variable is the safe idiom, and it's what makes measuring-then-drawing the same string possible.

## Full listing

Runnable snapshot: [`code/03-death-and-score/main.odin`](code/03-death-and-score/main.odin)

```sh
odin run 05-snake/code/03-death-and-score
```

## Checkpoint

Walls and your own body are lethal: hit either and the screen dims to **GAME OVER** with your score and best. Beat the best and it flashes **NEW BEST!** R restarts instantly. Quit and re-run — your best survives, sitting in `highscore.txt` wherever you launched from. **Snake: complete.**

## Exercises

1. **Easy:** Wrap-around mode: add `wrap: bool`, toggled with T. When on, out-of-bounds heads wrap (`(new_head.x + COLS) %% COLS`, same for `y`) instead of killing, and the HUD shows the mode. Which mode is harder is a genuine design question — play both.
2. **Medium:** Pause with P: skip the entire `acc += dt; for acc >= tick { ... }` block while paused and draw a dim overlay. Do *not* just stop calling `step` — if `acc` keeps banking, unpausing fires a burst of catch-up ticks and the snake teleports (probably into a wall). Freezing the accumulator is the fix; this exact bug ships in real games.
3. **Medium:** Mines: every 5 foods, spawn a permanent obstacle on a free cell — free now means "not on the snake, the food, or another mine," so generalize `spawn_food` to take extra forbidden cells. Hitting a mine is death. Watch rejection sampling earn its keep as the forbidden set grows.
4. **Hard:** Two-player: a second `[dynamic]Cell` snake steered with WASD (arrows for player 1), its own score, both bodies lethal to both snakes. Heads entering the same cell on the same tick: both die. Notice how the state machine, spawner, and HUD survive almost untouched — evidence the architecture was right.

**Next:** [6.1 Gravity and flap](../06-flappy-bird/01-gravity-and-flap.md)
