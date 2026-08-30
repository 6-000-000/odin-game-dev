# 6.2 The pipe spawner

**Module:** 06-flappy-bird

## Goals

- An endless obstacle stream with **zero runtime allocation** — a fixed pool, not a growing array
- The world moves, the bird doesn't: everything scrolls left at `SCROLL_SPEED`
- A spawn timer as a metronome, gap heights randomized inside a safe band
- Slot recycling: pipes that leave the screen go straight back into the pool

## New concepts

| Concept | What it is |
|---|---|
| Object pool | A fixed `pipes: [MAX_PIPES]Pipe` array plus an `active` flag per slot — nothing is allocated or freed while playing |
| Slot recycling | Spawn = find the first inactive slot and flip it on. Despawn = flip it off. The memory never moves |
| Spawn timer | `spawn_timer -= dt`, and when it hits 0: spawn and reset to `SPAWN_INTERVAL` — a metronome in three lines |
| World scrolling | The bird's x is pinned at `BIRD_X` forever; pipes move left at 180 px/s. The *world* flies past the bird |
| Safe band | `rand.float32_range(140, GROUND_TOP - 100)` — randomness with guardrails, so every dealt gap is reachable |

## Walkthrough

### The world moves, not the bird

In Pong and Breakout the ball moved and the paddles mostly didn't. Flappy inverts the feeling: the bird's x **never changes** — it hangs at `BIRD_X :: 120` for the entire run. Forward motion is an illusion produced by moving everything else leftward:

```odin
SCROLL_SPEED :: 180 // px/s; the world moves left, the bird stays put
```

Every active pipe runs `p.x -= SCROLL_SPEED * dt` each frame. The bird isn't flying through the world; the world is being dragged past the bird. Don't think of this as a trick — it's simpler physics (one less thing to integrate), and it's why the collision math next lesson gets to assume the bird is always at the same x.

### A fixed pool, zero allocation

```odin
MAX_PIPES :: 8 // fixed pool size — see spawn_pipe for why 8 is plenty
```

```odin
Pipe :: struct {
	x:      f32,
	gap_y:  f32, // vertical center of the gap
	gap_h:  f32,
	scored: bool, // next lesson
	active: bool,
}
```

```odin
pipes: [MAX_PIPES]Pipe // zero-initialized: all inactive
```

Eight structs on the stack, declared once before the loop. Odin zero-initializes the array, so every `active` starts `false` — the pool begins empty. No `make`, no `append`, no `delete`: the game allocates nothing while it runs. The `scored` field sits unused this lesson; it's the latch the scoring system needs in 6.3, and the comment says so.

### spawn_pipe: find a dead slot

```odin
// Find the first inactive slot and reuse it. If the pool is full, drop the
// spawn — with these constants at most 3 pipes are ever on screen at once.
spawn_pipe :: proc(pipes: ^[MAX_PIPES]Pipe) {
	for &p in pipes {
		if !p.active {
			p.x = SCREEN_W + 40
			p.gap_y = rand.float32_range(140, GROUND_TOP - 100)
			p.gap_h = PIPE_GAP
			p.scored = false
			p.active = true
			return
		}
	}
}
```

Spawning is a linear scan for the first inactive slot, a field-by-field reset, and an early `return`. If no slot is free, the spawn is silently dropped — and that can't happen here: a pipe lives `(520 + 70) px ÷ 180 px/s ≈ 3.3 s` (spawn at `SCREEN_W + 40`, retire at `-PIPE_W`), spawns arrive 1.4 s apart, so at most **3** pipes are ever live, and 8 slots can't fill. The new pipe appears at `SCREEN_W + 40`: fully off the right edge, so it slides into view instead of popping in. Note the parameter type `^[MAX_PIPES]Pipe` — a pointer to the whole array, so `spawn_pipe(&pipes)` mutates the caller's pool, and `for &p in pipes` iterates by reference so the writes land in the slots themselves.

### Random, but safe

```odin
p.gap_y = rand.float32_range(140, GROUND_TOP - 100)
```

The gap's vertical center is random — courtesy of the new `import "core:math/rand"` — but only inside a band: never closer than 140 px to the ceiling, never closer than 100 px to the ground. With `PIPE_GAP :: 150`, that guarantees every gap is fully on screen and threadable with the flap arc from 6.1. Unbounded randomness eventually deals an impossible pipe; the band is what makes the game fair *and* endless. Difficulty tuning lives here: squeeze the band and the game gets meaner without touching a single physics constant.

### The metronome and the recycling loop

```odin
// --- spawner ---
spawn_timer -= dt
if spawn_timer <= 0 {
	spawn_pipe(&pipes)
	spawn_timer = SPAWN_INTERVAL
}

// --- scroll & recycle ---
for &p in pipes {
	if !p.active do continue
	p.x -= SCROLL_SPEED * dt
	if p.x < -PIPE_W do p.active = false // off screen: back to the pool
}
```

Two small machines run every Playing frame. The timer counts down from `SPAWN_INTERVAL` (1.4 s) and fires `spawn_pipe` each time it laps. Below it, the loop scrolls every live pipe left and retires any pipe whose right edge has cleared the left edge of the screen (`x < -PIPE_W`) — that slot is immediately available for the next spawn. The pool breathes: pipes activate at the right edge, retire at the left, and the same eight slots serve the whole run. Restart is the same trick in bulk: `for &p in pipes do p.active = false` clears the world in one line.

One detail on the timer's starting value: it's declared as `spawn_timer := f32(1)`, not `SPAWN_INTERVAL` — the first pipe arrives 1.0 s after the run starts (and the restart sets `spawn_timer = 1` too), so the player gets a beat to find the rhythm before the first obstacle. Waiting the full 1.4 s makes the opening feel broken; starting at 0 spawns a pipe on frame one.

### Two rects and a lip

```odin
draw_pipe :: proc(p: Pipe) {
	top_h := p.gap_y - p.gap_h / 2
	bottom_y := p.gap_y + p.gap_h / 2
	rl.DrawRectangleV({p.x, 0}, {PIPE_W, top_h}, rl.GREEN)
	rl.DrawRectangleV({p.x, bottom_y}, {PIPE_W, GROUND_TOP - bottom_y}, rl.GREEN)
	// darker lips at the gap mouths
	rl.DrawRectangleV({p.x - 3, top_h - 26}, {PIPE_W + 6, 26}, rl.DARKGREEN)
	rl.DrawRectangleV({p.x - 3, bottom_y}, {PIPE_W + 6, 26}, rl.DARKGREEN)
}
```

A pipe is two rectangles meeting at the gap: the top one hangs from y = 0 down to the gap's top edge, the bottom one stands from the gap's bottom edge to `GROUND_TOP`. The darker "lip" rectangles are 6 px wider than the pipe (3 px of overhang per side) and cap the mouths of the gap — pure decoration, but it's what makes a green rectangle read as a *pipe*. The bottom rect stops exactly at `GROUND_TOP` and the ground strip is drawn right after, so the junction is seamless.

The draw loop that calls this iterates **by value** — `for p in pipes` — because drawing only reads. Contrast with the update loop's `for &p`, which mutates. Pick per loop: `&` when you write, plain when you read.

(Heads-up for your diff: from this snapshot on, each lesson's listing trims the previous lesson's now-redundant teaching comments — 6.1's `// impulse: SET the velocity…` and friends are gone here. The code they described is unchanged.)

🌐 **Web dev callout — pooling is how you never feed the GC**
> You've hit this on the web: a particle effect or a canvas animation stutters, and the profiler shows GC pauses from thousands of short-lived objects. The fix there is the fix here — keep a fixed set of objects alive forever and recycle them (three.js devs pool their `Vector3`s for exactly this reason). In JS, pooling is an optimization you reach for *after* the garbage collector embarrasses you, because the language will happily collect whatever you drop. Odin has no GC at all: without a pool you'd be calling `make`/`delete` by hand and leaking when you forgot. The pool isn't a performance hack — it's just what "manage your own memory" looks like when entities are born and die every second. The `active` flag is the whole lifecycle — constructor, destructor, and collector in one boolean.

## Full listing

Runnable snapshot: [`code/02-pipe-spawner/main.odin`](code/02-pipe-spawner/main.odin)

```sh
odin run 06-flappy-bird/code/02-pipe-spawner
```

## Checkpoint

Flap to start: a pipe slides in from the right every 1.4 seconds, gap heights vary but are always threadable, and pipes vanish the moment they're fully off the left edge. The bird still only dies on the ground — pipes are harmless for now. Now set `SPAWN_INTERVAL :: 0.7` and re-run: pipes arrive twice as often and the game is instantly chaotic. Restore it, then set `SCROLL_SPEED :: 300` — everything rushes at you. Pipe spacing in pixels is `SCROLL_SPEED * SPAWN_INTERVAL` — 252 px by default: **that one product is the real difficulty knob;** the interval in seconds is just how you got there.

## Exercises

1. **Easy:** Set `MAX_PIPES :: 2` and re-run. The obstacle stream develops holes — the spawner drops spawns when the pool is full, *silently*. A pool that's too small doesn't crash, it fails quietly, which is worse. Restore the 8.
2. **Easy:** Paint the corridor you're aiming for: in `draw_pipe`, add `rl.DrawRectangleV({p.x, p.gap_y - p.gap_h / 2}, {PIPE_W, p.gap_h}, rl.Fade(rl.RED, 0.3))`. Play a round with the gap filled in, then delete it.
3. **Medium:** Break the metronome. After each spawn, set `spawn_timer = SPAWN_INTERVAL * rand.float32_range(0.85, 1.15)` instead of the flat constant. Same average spacing, unpredictable rhythm — Flappy's rhythm-game feel comes precisely from the flat interval.
4. **Medium:** Watch the pool breathe. Each frame, count the active pipes into an `active_count` and draw it with `draw_centered(rl.TextFormat("pipes %d", active_count), 8, 20, rl.WHITE)`. Confirm it never exceeds 3 — then set `SPAWN_INTERVAL :: 0.5` and watch the cap get tested.
5. **Hard:** Ramp the difficulty without new constants: make the interval a variable that shrinks from 1.4 s to 0.9 s over the first minute (`interval = max(0.9, interval - 0.01 * dt)`… per frame). Then redo the lifetime math from this lesson (590 px ÷ 180 px/s ≈ 3.3 s) against the 0.9 s floor and *prove* the 8-slot pool still can't fill. Difficulty curves that outrun their pools fail silently — exercise 1 showed you how.

**Next:** [6.3 Collisions and score](03-collisions-and-score.md)
