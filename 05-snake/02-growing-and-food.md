# 5.2 Growing and food

**Module:** 05-snake

## Goals

- Add food that spawns on a random *free* cell — rejection sampling
- Grow the snake by skipping the tail removal: growth is a `pop` you don't do
- Score, and a speed ramp: the tick interval shrinks every time you eat
- HUD score, and food rendered with a pulse

## New concepts

| Concept | What it is |
|---|---|
| Rejection sampling | Pick a random cell; if it's invalid, pick again. Probabilistic, dead simple |
| `rand.int31_max` | `int(rand.int31_max(COLS))` → a random column in `[0, COLS)` |
| Growth as a skipped `pop` | `if !grow do pop(snake)` — the tail stays, the snake is one longer |
| Speed ramp | `tick = max(MIN_TICK, START_TICK - SPEEDUP * f32(score))` |
| Wall-clock animation | `math.sin(f32(rl.GetTime()))` — a pulse that ignores the tick entirely |

## Walkthrough

### Food, and where to put it

Food is just a `Cell`. The one constraint: it must not overlap the snake. The straightforward algorithm is **rejection sampling** — roll a random cell, check it, retry on collision:

```odin
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
```

How often does this actually retry? Expected attempts are `1 / free_fraction` — barely above 1 early on, pathological only when the board is nearly full (at which point you've essentially won Snake). The exact alternative: collect every free cell into a list and pick one entry — O(cells) work and memory per spawn, zero luck involved. Rejection sampling trades a theoretical worst case for three lines of code. Take the trade.

(`rand.int31_max(n)` returns an `i32` in `[0, n)`; the `int(...)` converts it to `Cell`'s field type. `rl.GetRandomValue(0, COLS - 1)` would do the job too — both are already in your toolbox.)

### Eating: growth is a pop you skip

`step` gains one flag:

```odin
step :: proc(snake: ^[dynamic]Cell, dir: Cell, grow: bool) {
	new_head := Cell{snake[0].x + dir.x, snake[0].y + dir.y}
	inject_at(snake, 0, new_head)
	if !grow do pop(snake)
}
```

That is the entire growth mechanism: the head still advances, the tail stays put, the snake is one cell longer. The eat test runs *before* stepping — comparing the cell the head is about to enter against the food, struct equality again:

```odin
eating := Cell{snake[0].x + dir.x, snake[0].y + dir.y} == food
step(&snake, dir, eating)
if eating {
	score += 1
	tick = max(MIN_TICK, START_TICK - SPEEDUP * f32(score))
	food = spawn_food(snake)
}
```

Notice the respawn happens *after* the step: `spawn_food` rejects cells occupied by the body, and the body just changed. Order matters whenever a function reads state you're mid-way through mutating.

### The speed ramp

`tick` stops being a constant — it's recomputed every time the score changes:

```odin
START_TICK :: 0.15
MIN_TICK :: 0.06
SPEEDUP :: 0.004

tick = max(MIN_TICK, START_TICK - SPEEDUP * f32(score))
```

0.15s per hop at the start, 4ms shaved per food, floored at 0.06s — around score 22 you hit the floor and the game is pure reflexes. (`max` is a built-in, like `min`, `clamp`, `abs`.) Three constants and Snake's whole difficulty curve falls out. And remember exercise 1 from last lesson: as the tick shrinks, input *latency* shrinks with it — the game grows more responsive exactly as it demands more precision. The ramp isn't just difficulty, it's feel.

### Pulsing food: a second clock

```odin
pulse := 1 + 0.15 * math.sin(f32(rl.GetTime()) * 6)
food_center := rl.Vector2{f32(food.x * CELL + CELL / 2), f32(food.y * CELL + CELL / 2)}
rl.DrawCircleV(food_center, (CELL / 2 - 4) * pulse, rl.RED)
```

`rl.GetTime()` is seconds since `InitWindow` (an `f64`, hence the cast). The sine swings the radius ±15%, and the food is drawn as a circle centered in its cell (`cell * CELL + CELL/2`, in pixel space). Here's the payoff of the accumulator split: the simulation hops a few times per second, but this animation runs at full frame rate, because it's *render state*, not *game state* — nothing in the sim reads the pulse. Once you start asking "which clock does this belong on?", every effect in every game gets easier to place.

The HUD is one line, borrowed straight from Pong:

```odin
rl.DrawText(rl.TextFormat("SCORE %d", score), 10, 10, 20, rl.WHITE)
```

🌐 **Web dev callout — rejection sampling is "retry on collision"**
> You've written this pattern every time you generated a random slug, invite code, or username and looped on a uniqueness check: roll, validate, retry. The analysis transfers too — expected attempts blow up only as the space saturates, so it's fine until it isn't. The alternative (materialize all valid options, pick one) is the `SELECT ... WHERE id NOT IN (taken)` version: exact, heavier, usually unnecessary. In games the same trade shows up for spawn points, loot drops, and map generation — anywhere you need "random, but not *there*."

## Full listing

Runnable snapshot: [`code/02-growing-and-food/main.odin`](code/02-growing-and-food/main.odin)

```sh
odin run 05-snake/code/02-growing-and-food
```

## Checkpoint

A red, gently pulsing morsel sits on the grid. Eat it: the snake grows by one cell, the score ticks up, a new morsel appears somewhere free, and the rhythm quickens perceptibly. By score 15 the game demands real attention. Walls and your own body still don't kill you — drive straight through yourself with pride. That ends next lesson.

## Exercises

1. **Easy:** Show the speed on the HUD: `rl.DrawText(rl.TextFormat("tick %.2f", tick), 10, 34, 20, rl.GRAY)`. Watch it shrink as you eat — and pin at 0.06. (One `TextFormat` call per expression, always.)
2. **Easy:** Tune the pulse: change the `6` (rate) and `0.15` (amplitude), or pulse the alpha instead of the radius with `rl.Fade(rl.RED, ...)`. Nothing about gameplay changes — it's a render clock.
3. **Medium:** Implement the collect-free-cells spawner: build a `[dynamic]Cell` of every cell not on the body (nested `for y in 0 ..< ROWS` / `for x in 0 ..< COLS` loops), return `free[int(rand.int31_max(i32(len(free))))]`, `delete` the list. Run both versions, then keep the one you'd rather maintain.
4. **Medium:** Add a bonus cherry: every 5th food also spawns a golden morsel worth 3 points that despawns after 5 seconds (`cherry: Cell`, `cherry_timer: f32`, `cherry_active: bool`). The despawn counts down per frame on `dt` — a third clock, neither the tick nor wall-clock.

**Next:** [5.3 Death, score, and saving](03-death-and-score.md)
