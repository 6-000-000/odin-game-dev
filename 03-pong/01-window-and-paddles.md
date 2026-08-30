# 3.1 Window and paddles

**Module:** 03-pong · **Project 1 of 6**

Welcome to your first game. Pong is the "hello world" that actually teaches: input, movement, collision, scoring, and game states all fit in ~200 lines. By the end of this module you'll have a complete, juicy, AI-opponent Pong — and every pattern in it will reappear in the next five projects.

## Goals

- Set up the project skeleton (screen constants, structs, the loop)
- Draw two paddles as data-driven rectangles
- Move both paddles with input, clamped to the screen

## New concepts

| Concept | What it is |
|---|---|
| Screen constants | `SCREEN_W :: 800` — one source of truth for layout math |
| Entity struct | `Paddle` — position + speed as one value |
| Draw helper proc | `draw_paddle` — entities know *how* to be drawn via procs |
| `clamp` | Keep a value inside a range — the wall |

## Walkthrough

### Constants first

Game code is arithmetic on screen coordinates, so give the numbers names immediately:

```odin
SCREEN_W :: 800
SCREEN_H :: 450

PADDLE_W :: 15
PADDLE_H :: 90
PADDLE_SPEED :: 400    // pixels per second
```

When you later decide the game should be 1024×576, you change two lines and everything — clamping, centering, AI — follows.

### The paddle as data

```odin
Paddle :: struct {
	pos:   rl.Vector2,  // center of the paddle
	speed: f32,
}
```

A design decision worth noticing: `pos` is the paddle's **center**, not its top-left. Center-based entities make collision and clamping math symmetric (`pos.y ± PADDLE_H / 2`), and it matches how the ball works. Drawing needs the top-left, so the draw proc does the conversion in exactly one place:

```odin
draw_paddle :: proc(p: Paddle, color: rl.Color) {
	rl.DrawRectangleV(
		{p.pos.x - PADDLE_W / 2, p.pos.y - PADDLE_H / 2},
		{PADDLE_W, PADDLE_H},
		color,
	)
}
```

🌐 **Web dev callout — derived state gets one source of truth**
> This is the rule you know from frontend state management. Store one representation (center); compute the other (top-left) at render time. Never store both — they *will* desync. React re-renders from state on every commit; here `draw_paddle` re-derives the rectangle from `pos` on every frame. Same discipline, no reconciler.

### Input and clamping

```odin
if rl.IsKeyDown(.W) do player.pos.y -= player.speed * dt
if rl.IsKeyDown(.S) do player.pos.y += player.speed * dt
```

Held keys + `speed * dt` = smooth, framerate-independent movement (lesson 2.1's rule). Two-player for now: `W`/`S` vs `↑`/`↓` — an AI opponent arrives in lesson 3.4.

Then the wall, one line per paddle:

```odin
player.pos.y = clamp(player.pos.y, PADDLE_H / 2, SCREEN_H - PADDLE_H / 2)
```

Because `pos` is the center, the allowed range is "half a paddle from each edge". Center-based storage makes this line self-evident; with top-left storage it's the kind of arithmetic you get subtly wrong at 1 AM.

### Assemble the skeleton

The loop itself is lesson 2.1's, verbatim — window, frame time, draw begin/end. The only new wiring is spawning the two paddles 30 px in from each wall, centered vertically:

```odin
main :: proc() {
	rl.InitWindow(SCREEN_W, SCREEN_H, "Pong")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	player := Paddle{pos = {30, SCREEN_H / 2}, speed = PADDLE_SPEED}
	opponent := Paddle{pos = {SCREEN_W - 30, SCREEN_H / 2}, speed = PADDLE_SPEED}

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()
		// input → clamp → draw
	}
}
```

The order inside the loop is always the same — read input, clamp, draw. That discipline matters more as entities multiply: everything that mutates state happens before `BeginDrawing`, so what you draw is always *this* frame's state.

## Full listing

Runnable snapshot: [`code/01-window-and-paddles/main.odin`](code/01-window-and-paddles/main.odin)

```sh
odin run 03-pong/code/01-window-and-paddles
```

## Checkpoint

Black window, two white paddles, W/S moves the left one, arrow keys move the right one, and neither can leave the screen. It looks like nothing yet — but the skeleton under it (constants → structs → input → clamp → draw) is the skeleton of every project in this course.

## Exercises

1. **Easy:** Make the paddles different colors (`rl.SKYBLUE` vs `rl.ORANGE`) and pass the color through `draw_paddle`.
2. **Easy:** Add `A`/`D` movement for the left paddle (x-axis), clamped to the left half of the screen. Yes, that's not Pong-rules — it's your sandbox.
3. **Medium:** Add a `draw_center_line` proc: a dashed vertical line down the middle (a loop drawing 4×20 rectangles every 40px). It's in lesson 3.3's snapshot if you get stuck.
4. **Medium:** Make paddle speed *charge*: while holding SHIFT, `speed` lerps up to 800 over half a second; release and it snaps back. Feel how much "game feel" lives in tiny input-response details.
5. **Hard:** Give the paddles *weight*: replace instant velocity with acceleration — each paddle stores a `vel: f32` that eases toward ±`PADDLE_SPEED` (or 0) at 2400 px/s², then integrate `pos.y += vel * dt`. Tune the acceleration until one paddle feels like air hockey and the other like ice. Instant input is a choice, not a default — this is the experiment that proves it.

**Next:** [3.2 Ball and collisions](02-ball-and-collisions.md)
