# 4.2 The brick grid

**Module:** 04-breakout

## Goals

- Fill the top of the screen with bricks stored in a fixed 2D array
- Compute brick size and position from layout constants
- Answer Breakout's key question — *which face of the brick did we hit?* — with penetration depths
- Kill bricks permanently: dead bricks stop colliding and drawing

## New concepts

| Concept | What it is |
|---|---|
| Fixed 2D array | `[BRICK_ROWS][BRICK_COLS]Brick` — every brick exists always; no allocation, no growth |
| Grid from constants | brick x/y computed from row/col, padding, and margins — re-flow the grid by editing one constant |
| Penetration depth | how far the ball overlaps the brick on each axis; the *smaller* overlap reveals the hit face |
| Labeled break | `break brick_hit` exits a nested loop from the inside |
| Dead flag | `alive: bool` — skip dead bricks in collision *and* draw |

## Walkthrough

### The grid is data laid out by math

```odin
BRICK_ROWS :: 6
BRICK_COLS :: 10
BRICK_TOP :: 80 // px from the top of the screen
BRICK_SIDE :: 20 // px margin on left/right
BRICK_PAD :: 4 // px gap between bricks
BRICK_W :: f32(SCREEN_W - 2 * BRICK_SIDE - (BRICK_COLS - 1) * BRICK_PAD) / BRICK_COLS
BRICK_H :: 24
```

`BRICK_W` is whatever width remains after margins and gaps, divided evenly. Change any constant and the whole grid re-flows — nothing else knows the numbers.

```odin
Brick :: struct {
	rect:  rl.Rectangle,
	alive: bool, // dead bricks stop colliding and drawing
	color: rl.Color,
}
```

Sixty bricks, one fixed array. The count is known at compile time, so there's nothing to allocate and nothing to free — the array just sits inside `main`'s stack frame:

```odin
bricks: [BRICK_ROWS][BRICK_COLS]Brick
```

Initialization is the nested loop you'll write for every grid in your career. Row picks the color from `row_color` (RED/ORANGE/YELLOW/GREEN/SKYBLUE/PURPLE — a tiny proc, because Odin won't let you index a constant array at runtime):

```odin
init_bricks :: proc(bricks: ^[BRICK_ROWS][BRICK_COLS]Brick) {
	for row in 0 ..< BRICK_ROWS {
		for col in 0 ..< BRICK_COLS {
			x := f32(BRICK_SIDE) + f32(col) * (BRICK_W + BRICK_PAD)
			y := f32(BRICK_TOP + row * (BRICK_H + BRICK_PAD))
			bricks[row][col] = Brick {
				rect  = {x, y, BRICK_W, BRICK_H},
				alive = true,
				color = row_color(row),
			}
		}
	}
}
```

Drawing is the same loop with one guard: `if b.alive do rl.DrawRectangleRec(b.rect, b.color)`.

### Which face did we hit?

In Pong every bounce flipped `vel.x`, because a paddle only ever presents one face. A brick presents **four** — and flipping the wrong component looks broken. A ball grazing a brick's side must flip `vel.x`; a ball arriving from below must flip `vel.y`.

The trick: when the ball overlaps a brick, measure how deeply it penetrates on **each axis**, from the brick's center:

```odin
cx := b.rect.x + b.rect.width / 2
cy := b.rect.y + b.rect.height / 2
overlap_x := BALL_RADIUS + b.rect.width / 2 - abs(ball.pos.x - cx)
overlap_y := BALL_RADIUS + b.rect.height / 2 - abs(ball.pos.y - cy)
```

`BALL_RADIUS + half_width` is the center distance at which ball and brick would *just* touch along x; subtracting the actual distance leaves the overlap. The **smaller** overlap is the face we came through — on that axis the ball has barely entered, while on the other it's already deep inside. Flip that axis and push the ball out by exactly the overlap, toward the side it came from. Reflect-and-reposition, promoted to two dimensions:

```odin
if overlap_x < overlap_y {
	ball.vel.x = -ball.vel.x
	ball.pos.x += ball.pos.x < cx ? -overlap_x : overlap_x
} else {
	ball.vel.y = -ball.vel.y
	ball.pos.y += ball.pos.y < cy ? -overlap_y : overlap_y
}
```

Wrapped in the collision loop, with the kill and one new piece of Odin:

```odin
brick_hit: for row in 0 ..< BRICK_ROWS {
	for col in 0 ..< BRICK_COLS {
		b := &bricks[row][col]
		if !b.alive do continue
		if rl.CheckCollisionCircleRec(ball.pos, BALL_RADIUS, b.rect) {
			b.alive = false
			bricks_left -= 1
			// ... face detection from above ...
			ball.vel = rl.Vector2Normalize(ball.vel) * BALL_SPEED
			break brick_hit // one brick per frame is enough
		}
	}
}
```

- `brick_hit:` labels the outer loop and `break brick_hit` exits **both**. A plain `break` exits only the inner loop, and the ball keeps eating bricks in the same frame.
- Axis flips preserve speed in exact math — but floats aren't exact, and corner grazes compound tiny errors. `Vector2Normalize(vel) * BALL_SPEED` pins the speed after every brick bounce: cheap insurance for the constant-speed physics from lesson 4.1.
- `b := &bricks[row][col]` takes a pointer so `b.alive = false` writes into the grid, not a copy.

The HUD is one line — drawn last, so it sits on top:

```odin
rl.DrawText(rl.TextFormat("bricks: %d", bricks_left), 20, 20, 20, rl.GRAY)
```

🌐 **Web dev callout — smallest overlap = scroll-axis locking**
> Trackpads and touchscreens solve the inverse problem: given a diagonal gesture, decide whether the user meant to scroll horizontally or vertically by comparing `|deltaX|` to `|deltaY|` and locking to the dominant axis. Face detection is the same comparison with the opposite winner — the dominant axis is where the ball was *traveling*, the smallest overlap is the face it *entered through*. One `abs` comparison, two classic behaviors.

## Full listing

Runnable snapshot: [`code/02-brick-grid/main.odin`](code/02-brick-grid/main.odin)

```sh
odin run 04-breakout/code/02-brick-grid
```

## Checkpoint

Six colored rows of bricks across the top and a brick counter in the corner. The ball destroys one brick per hit and bounces correctly: side hits send it back horizontally, top/bottom hits vertically. Thread the ball into a gap and watch it ricochet along a column, face flips alternating. Clearing the field just leaves it empty — lesson 4.3 decides what happens next.

## Exercises

1. **Easy:** Move the grid down 40 px and widen the gaps to 8 px. Notice you edited two constants and zero loops — that's why layout lives in constants.
2. **Easy:** Give each row a point value (top row 50, down to 10 for the bottom) and show a score next to the brick count.
3. **Medium:** Comment out the `break brick_hit` and play. Explain the tunnels the ball digs: why does resolving two bricks in one frame look like passing through solid ones?
4. **Medium:** Multi-hit bricks: add `hp: int` to `Brick` (2 for the top two rows, 1 otherwise), decrement instead of killing, and draw damaged bricks with `rl.Fade(b.color, 0.5)`. Lesson 4.3's level format will want this.

**Next:** [4.3 Lives, levels, and level data](03-lives-and-levels.md)
