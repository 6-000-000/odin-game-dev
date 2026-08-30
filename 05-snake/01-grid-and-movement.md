# 5.1 Grid and movement

**Module:** 05-snake

## Goals

- Model the world as a grid: `Cell` coordinates as the truth, pixels derived — never the other way around
- Drive movement with a **fixed timestep**: an accumulator that spends frame time in discrete ticks
- Buffer direction input and apply it on the tick, with 180° turns rejected
- Move the snake with two dynamic-array operations: `inject_at` at the head, `pop` at the tail

## New concepts

| Concept | What it is |
|---|---|
| `Cell` | `struct { x, y: int }` — a grid coordinate, the unit of everything in Snake |
| Fixed timestep | The simulation advances in fixed `TICK` chunks regardless of frame rate |
| Accumulator | `acc += dt; for acc >= TICK { ... }` — banks real time, spends it in ticks |
| Input buffering | Keys write `next_dir`; the tick reads it. Input is data, not immediate action |
| `inject_at` / `pop` | Insert at index 0 / remove the last element of a `[dynamic]` array |

## Walkthrough

### Two coordinate systems

Pong and Breakout lived entirely in pixels. Snake lives on a **grid**: the world is 30×30 cells and a position is two ints. The window size is *computed from* the grid, not the other way around:

```odin
CELL :: 24
COLS :: 30
ROWS :: 30
SCREEN_W :: CELL * COLS
SCREEN_H :: CELL * ROWS

Cell :: struct {
	x, y: int,
}
```

Grid coordinates are the truth; pixels (`cell.x * CELL`) are a view computed at draw time. All game logic — movement, collision, food — happens in integer cell space. That's why Snake collision is `==` instead of raylib's `CheckCollision*` family: two cells either overlap exactly or not at all.

Directions are cell offsets, so "move" is just integer addition:

```odin
DIR_UP :: Cell{0, -1}
DIR_DOWN :: Cell{0, 1}
DIR_LEFT :: Cell{-1, 0}
DIR_RIGHT :: Cell{1, 0}
```

(Remember: +y is down, so "up" is −1. Same convention as every screen coordinate system you've used.)

### The snake is an array, head first

```odin
snake: [dynamic]Cell
defer delete(snake)
append(&snake, Cell{COLS / 2, ROWS / 2})     // head
append(&snake, Cell{COLS / 2 - 1, ROWS / 2})
append(&snake, Cell{COLS / 2 - 2, ROWS / 2}) // tail
```

Head at index 0, tail at the end. With that layout, one grid step is exactly two operations — push a new head on the front, drop the last cell:

```odin
step :: proc(snake: ^[dynamic]Cell, dir: Cell) {
	new_head := Cell{snake[0].x + dir.x, snake[0].y + dir.y}
	inject_at(snake, 0, new_head)
	pop(snake)
}
```

Every body cell ends up in the cell its front-neighbor just vacated, so the whole body "follows" with zero per-segment logic. There is no per-segment state — the array *is* the snake. If this feels like cheating, it is. The best game code usually is.

### Fixed timestep: the accumulator

Pong moved every frame by `vel * dt`. Snake must move in **discrete hops** — one cell at a time, on a strict rhythm — while the window still renders at 60+ fps. The accumulator pattern splits those two clocks:

```odin
TICK :: 0.15 // seconds per grid step

acc: f32
// each frame:
acc += rl.GetFrameTime()
for acc >= TICK {
	acc -= TICK
	step(&snake, dir)
}
```

Each frame banks its real elapsed time into `acc`; the `for` loop spends that bank in `TICK`-sized chunks. At 60 fps a tick fires about every 9 frames; at 30 fps about every 4–5 — and on a hitching frame, several ticks fire back-to-back to catch up. Either way the *simulation* advances at exactly 1/`TICK` steps per second, and rendering just draws whatever state it's in. The snake hops; the frame loop spins; neither cares about the other's rate. This is why the game looks smooth (grid lines, HUD, later the food pulse) while the snake itself moves in discrete jumps.

🌐 **Web dev callout — this is a server tick, client-side**
> If you've ever built a realtime multiplayer game or a collab app: the accumulator is the authoritative server tick running inside your render loop. The sim advances at a fixed rate — deterministic, frame-rate independent — while the renderer samples it at whatever rate `requestAnimationFrame` gives you. Real multiplayer games make exactly this split so a 144Hz monitor doesn't run the game 2.4× faster than a 60Hz one. Pong got away with `pos += vel * dt` because smooth movement is frame-rate tolerant; Snake's grid logic isn't — a hop must be a hop.

### Buffered input: the 180° bug

Naive Snake applies key presses immediately (`if pressed do dir = ...`). That hides a classic bug: moving right, press **up then left** within the same tick — both apply instantly, and the snake reverses into its own neck. Instant input plus discrete movement equals death by double-tap.

The fix is buffering: keys only write `next_dir`, and the *tick* is the sole place that reads it:

```odin
if rl.IsKeyPressed(.UP) || rl.IsKeyPressed(.W) do next_dir = DIR_UP
if rl.IsKeyPressed(.DOWN) || rl.IsKeyPressed(.S) do next_dir = DIR_DOWN
if rl.IsKeyPressed(.LEFT) || rl.IsKeyPressed(.A) do next_dir = DIR_LEFT
if rl.IsKeyPressed(.RIGHT) || rl.IsKeyPressed(.D) do next_dir = DIR_RIGHT
```

```odin
// inside the tick, before stepping:
opposite := Cell{-dir.x, -dir.y}
if next_dir != opposite do dir = next_dir
```

The rejection test compares against `dir` — the direction the snake is *actually moving* — not against `next_dir`. Replay the bug: moving right, up-then-left lands `next_dir = LEFT`; at the tick, LEFT is the opposite of RIGHT, so it's refused and the snake survives (the earlier UP is discarded — one buffer slot holds one intent; a queue is exercise 3). Structs compare with `==`/`!=` field-by-field in Odin, so "is this a reversal?" is one expression.

### Drawing: cells to pixels

The grid→pixel conversion happens exactly once per cell per frame, at the rectangle call:

```odin
for c, i in snake {
	color := i == 0 ? HEAD_COLOR : BODY_COLOR
	rl.DrawRectangle(i32(c.x * CELL + 1), i32(c.y * CELL + 1), CELL - 2, CELL - 2, color)
}
```

The 1px inset (`+1`, `CELL - 2`) leaves a seam between cells so individual segments stay readable at speed. Index 0 gets the brighter shade: the head is the only cell the player must track, so make it free to find.

The backdrop is two constants and one tiny proc. `BACKGROUND :: rl.Color{15, 15, 18, 255}` (near-black) fills the window, and `draw_grid` paints faint lines over it (`GRID_LINE` is `{255, 255, 255, 8}` — nearly transparent white) so the grid is visible without shouting:

```odin
draw_grid :: proc() {
	for x in 0 ..= COLS do rl.DrawLine(i32(x * CELL), 0, i32(x * CELL), SCREEN_H, GRID_LINE)
	for y in 0 ..= ROWS do rl.DrawLine(0, i32(y * CELL), SCREEN_W, i32(y * CELL), GRID_LINE)
}
```

Note the **inclusive** ranges: `0 ..= COLS` draws COLS+1 lines — 30 cells need 31 fence posts, including the right and bottom edges of the window.

## Full listing

Runnable snapshot: [`code/01-grid-and-movement/main.odin`](code/01-grid-and-movement/main.odin)

```sh
odin run 05-snake/code/01-grid-and-movement
```

## Checkpoint

A three-cell snake glides right in crisp hops, about seven times a second. Arrows or WASD turn it — but only on tick boundaries, never mid-hop. Drive it off any edge: it just keeps going (walls become lethal in 5.3). Now try the double-tap: while moving right, quickly tap up then left — the snake ignores the reversal instead of eating its own neck.

## Exercises

1. **Easy:** Set `TICK :: 0.06`, then `TICK :: 0.4`. One constant is the entire difficulty curve. Notice 0.4 is awful not because it's slow but because input feels *latent* — your keypress waits up to 400ms to matter. That latency is the real reason Snake speeds up as it grows (next lesson).
2. **Easy:** Wrap-around walls: in `step`, add `new_head.x = (new_head.x + COLS) %% COLS` and the same for `y` with `ROWS`. (The `+ COLS` keeps the value non-negative; `%%` is Odin's floored modulo.) Drive off the right edge, appear on the left.
3. **Medium:** Upgrade the buffer to a two-slot queue: a `[dynamic]Cell` capped at 2 entries, the tick shifts the front entry off. Now up-then-left within one tick turns up on this tick and left on the next — both intents survive. This is what modern Snake-likes ship.
4. **Medium:** Shade the body by distance from the head: in the draw loop, `rl.ColorLerp(HEAD_COLOR, BODY_COLOR, f32(i) / f32(len(snake)))`. Purely a render change — the simulation doesn't know or care, which is exactly the point.
5. **Hard:** Replay mode: record `dir` into a `[dynamic]Cell` on every tick, and on R play the last run back at 2× speed (a `replaying: bool`, a playback index, the accumulator driving both). Recording *decisions per tick* — not positions per frame — is what makes the replay tiny; it's the command pattern (lesson 9.1) in embryo.

**Next:** [5.2 Growing and food](02-growing-and-food.md)
