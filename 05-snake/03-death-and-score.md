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

The beeps are Pong's `make_beep` (lesson 3.4) copied verbatim — 660Hz for eating, 140Hz for death. Audio reuse is like code reuse, but louder.

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
