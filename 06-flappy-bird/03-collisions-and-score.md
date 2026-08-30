# 6.3 Collisions and score

**Module:** 06-flappy-bird

## Goals

- Circle-vs-rect collision: the bird against both pipe rects with `rl.CheckCollisionCircleRec`
- One source of truth: the rects you draw are the rects you collide with
- Scoring as **edge detection** — a trigger that fires exactly once per pipe, not overlap counting
- Medals, a best score, and a game-over panel that waits for the body to land

## New concepts

| Concept | What it is |
|---|---|
| `pipe_top_rect` / `pipe_bottom_rect` | Procs that return a pipe's two `rl.Rectangle`s — called by both drawing and collision, so the two can never disagree |
| `rl.CheckCollisionCircleRec` | Circle vs. rectangle overlap — the bird is a circle, each pipe half is a rect, two calls cover the whole obstacle |
| Edge detection | `!p.scored && p.x + PIPE_W < bird.pos.x` — true for exactly one frame per pipe, then latched off forever |
| Death bookkeeping | `best = max(best, score)` runs on *every* path into `.Dead` — ground and pipe alike |
| Deferred UI | The panel draws only once `bird.pos.y >= GROUND_TOP - bird.radius` — the interface waits for the tumble to finish |

## Walkthrough

### One source of truth

In 6.2 the pipe rects were computed inline inside `draw_pipe`. Collision needs the same two rectangles, so they graduate to procs:

```odin
// The collision rects ARE the draw rects — one source of truth.
pipe_top_rect :: proc(p: Pipe) -> rl.Rectangle {
	return {p.x, 0, PIPE_W, p.gap_y - p.gap_h / 2}
}

pipe_bottom_rect :: proc(p: Pipe) -> rl.Rectangle {
	y := p.gap_y + p.gap_h / 2
	return {p.x, y, PIPE_W, GROUND_TOP - y}
}
```

`draw_pipe` now calls these too, so the pixels on screen and the hitboxes are the same numbers by construction. This is the cheapest insurance policy in gamedev: if visuals and collision are computed separately, they *will* drift apart, and players will die to pipes they visibly cleared — the most rage-inducing bug a game can ship. One proc, two consumers, zero drift.

(One deliberate exception, so you're not confused when you spot it: the darker lip rectangles overhang the pipe by 3 px per side and are decoration only — no hitbox. Exercise 2 goes further and shrinks the hitbox *inside* the sprite on purpose. Shared rects are the safe default, not a law of physics.)

### Circle vs. rect

The bird is a circle (that's why `radius` exists) and each pipe half is a rect. raylib has the exact test:

```odin
if rl.CheckCollisionCircleRec(bird.pos, bird.radius, pipe_top_rect(p)) ||
   rl.CheckCollisionCircleRec(bird.pos, bird.radius, pipe_bottom_rect(p)) {
	best = max(best, score)
	state = .Dead
}
```

Two calls, one per rect, `||`'d — touching either half is death. The check lives inside the same loop that scrolls and recycles the pool, so every live pipe is tested once per frame. Note `best = max(best, score)` here *and* on the ground-death path: both roads into `.Dead` update the record. The tumble itself needed no new code — 6.1's `.Dead` state already keeps integrating gravity, so the bird arcs out of the sky on its own.

### Scoring is a trigger, not a state

The field that sat dormant in 6.2 earns its keep:

```odin
// scoring trigger: fires once, the frame the pipe's right edge
// crosses behind the bird — edge detection, not overlap counting
if !p.scored && p.x + PIPE_W < bird.pos.x {
	p.scored = true
	score += 1
}
```

Read the condition without the latch: `p.x + PIPE_W < bird.pos.x` becomes true the frame the pipe's right edge crosses behind the bird's center — and then *stays* true for the rest of the pipe's life. Score on the raw condition and a cleared pipe awards a point every frame until it recycles: hundreds per pipe. The `scored` bool converts a *level* (a condition that holds) into an *edge* (an event that happens): the latch starts false, the crossing sets it, and `!p.scored` never passes again for that pipe. `spawn_pipe` resets it to `false` precisely because slots get recycled — a reused slot must be allowed to score again. During play, the running total is a single HUD line: `draw_centered(rl.TextFormat("%d", score), 30, 48, rl.WHITE)`.

### Medals and the panel

```odin
medal :: proc(score: int) -> (color: rl.Color, name: cstring) {
	switch {
	case score >= 30:
		return {255, 215, 0, 255}, "GOLD"
	case score >= 20:
		return {192, 192, 192, 255}, "SILVER"
	case score >= 10:
		return {205, 127, 50, 255}, "BRONZE"
	}
	return {}, ""
}
```

Two Odin notes in seven lines: a bare `switch` (no value) evaluates its cases top-down like an if-else chain — so the highest tier must come first — and the proc returns **multiple values**, destructured at the call site as `color, name := medal(score)`. Below bronze it returns a zero color and an empty string, and the caller never asks, because the panel gates on `score >= 10`:

```odin
// panel appears once the bird has finished its tumble
if bird.pos.y >= GROUND_TOP - bird.radius {
	rl.DrawRectangleRounded({80, 170, 320, 240}, 0.12, 8, rl.Fade(rl.BLACK, 0.7))
	draw_centered("GAME OVER", 190, 40, rl.WHITE)
	draw_centered(rl.TextFormat("score  %d", score), 250, 24, rl.WHITE)
	draw_centered(rl.TextFormat("best  %d", best), 284, 24, rl.WHITE)
	if score >= 10 {
		color, name := medal(score)
		rl.DrawCircle(SCREEN_W / 2, 348, 18, color)
		draw_centered(name, 372, 16, color)
	}
	draw_centered("R to restart", 424, 20, rl.WHITE)
}
```

The outer `if` is direction, not logic: it waits until the tumbling bird has landed before the UI appears. You watch your failure come to rest, *then* get the verdict. The medal itself is a filled circle and a label — bronze, silver, gold at 10, 20, 30.

### R resets everything now

```odin
score := 0
best := 0 // in-memory only: dies with the process, and that's fine
```

```odin
if rl.IsKeyPressed(.R) {
	reset_bird(&bird)
	for &p in pipes do p.active = false
	spawn_timer = 1
	score = 0
	state = .Title
}
```

Bird, pool, timer — and now `score`. `best` is deliberately *not* on the list: it survives restarts and lives only in memory, dying with the process. For an arcade toy that's a feature, not a bug (Snake's save files showed you the alternative if you want permanence).

🌐 **Web dev callout — you already know edge detection as "enter" events**
> The DOM never makes you build this: `mouseenter` fires once when the cursor crosses in, `IntersectionObserver` invokes your callback at the moment a threshold is crossed, and both then stay quiet until the crossing reverses. Under the hood the browser is doing exactly what `p.scored` does — every frame it re-evaluates "is it inside?" and diffs against the *previous* answer, firing your handler only on a change. In a game loop nobody diffs for you: the only question you can ask is "is it true *now*?", so you carry the previous answer yourself as a latched bool. Every "trigger once when X starts being true" in gamedev is this pattern. `mouseenter`, an IntersectionObserver threshold, a `useEffect` that should run once per value — same idea, with someone else holding the latch.

## Full listing

Runnable snapshot: [`code/03-collisions-and-score/main.odin`](code/03-collisions-and-score/main.odin)

```sh
odin run 06-flappy-bird/code/03-collisions-and-score
```

## Checkpoint

Pipes are lethal now: clip one and the bird tumbles to the ground, then the panel appears with score, best, and — at 10 or better — a medal. Each pipe you clear ticks the score exactly once; watch it and confirm it's never two. R wipes the run but keeps `best`; closing the window forgets everything. Now the honesty test: delete the `!p.scored &&` half of the trigger and re-run — the score spins into the hundreds as a cleared pipe drifts behind you. **A point is an event; in a loop, events are latched booleans.**

## Exercises

1. **Easy:** Show the record on the title screen: in the `.Title` draw case, add `if best > 0 { draw_centered(rl.TextFormat("best  %d", best), 260, 20, rl.WHITE) }`. Small thing — but it gives the first flap of every run a stake.
2. **Easy:** Forgive the player. Change both collision calls to use `bird.radius - 4` as the radius. The hitbox shrinks inside the sprite, near-misses start going your way, and the game feels instantly fairer — with zero physics changes. Real Flappy's hitbox is famously smaller than its bird.
3. **Medium:** Add a PLATINUM tier at 50: `return {220, 245, 255, 255}, "PLATINUM"`. Placement matters — the bare `switch` evaluates top-down, so the new case must sit *above* `score >= 30` or gold swallows it. Get it wrong on purpose first and watch platinum never appear.
4. **Medium:** Make `best` survive the window. Snake (5.3) already wrote save files: on every death, write `best` to a text file; at startup, read it back if the file exists. Ten lines, and the record book becomes permanent.
5. **Hard:** Flight recorder: keep a 120-entry ring buffer (`[120]f32`, written at `idx %% 120`) of the last two seconds of `bird.pos.y`, and dump it to the console on death. Post-mortem data beats replaying your deaths in your head — and a ring of recent history is the seed of every replay/ghost system.

**Next:** [6.4 Game feel](04-game-feel.md)
