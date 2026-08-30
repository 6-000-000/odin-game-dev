# 8.2 The naïve implementation

**Module:** 08-boids

## Goals

- Implement all three rules — separation, alignment, cohesion — with the accumulator pattern
- Turn the rule weights into a single clamped acceleration, then integrate
- Instrument the update with millisecond timing and *see* O(n²)
- Understand why 150 boids is fine and 2,000 is a slideshow — setting up lesson 8.3

## New concepts

| Concept | What it is |
|---|---|
| Accumulator pattern | Per boid, sum neighbor contributions (`align_sum`, `coh_sum`, `sep`) + counts, divide afterwards |
| Weighted rules | `accel = w_sep*sep + w_align*align + w_coh*coh`, clamped to `max_steer` |
| O(n²) | Every boid checks every boid: 150 × 149 ≈ 22,000 pair checks *per frame* |
| `rl.GetTime()` | f64 seconds since `InitWindow` — diff two calls for millisecond timing |

## Walkthrough

### First, a deletion: the wander is gone

Lesson 8.1's `WANDER` jitter — the random kick that kept isolated boids drifting — is **removed** in this snapshot, and your diff should delete it too (the constant and the `accel += {...} * WANDER` line). It was a stand-in force for a simulation that only had cohesion: without it, lone boids flew in straight lines forever. With all three rules active, every boid is perpetually steered by *someone* — and on the off chance one truly sees nobody, `clamp_speed`'s near-zero kick from 8.1 still covers the degenerate case. Keep the jitter and the flock works, but the streams look fuzzy; the real rules deserve a clean stage.

### Perceive: accumulate what the neighbors are doing

All three rules run off a single neighbor scan. Per boid, walk the whole flock, bucket each other boid by distance, and *accumulate* — don't act yet:

```odin
for &b, i in boids {
	sep, align_sum, coh_sum: rl.Vector2
	avoid_count, perc_count := 0, 0

	for other, j in boids { // ← O(n²): the full flock scan
		if i == j do continue
		to_other := offset(b.pos, other.pos, SCREEN_W, SCREEN_H)
		d := rl.Vector2Length(to_other)
		if d < s.avoid_radius {
			sep -= to_other // push away from the too-close neighbor
			avoid_count += 1
		}
		if d < s.perception_radius {
			align_sum += other.vel // average heading
			coh_sum += to_other // average position (relative to me)
			perc_count += 1
		}
	}
	// ... steer, below
}
```

The three buckets map exactly to the three rules from last lesson's diagram:

- `sep` — sum of vectors pointing *away* from everyone inside the **avoid radius**. `to_other` points from me to them, so `-= ` accumulates "away".
- `align_sum` — sum of velocities of everyone inside the **perception radius**. Their average is the flock's heading.
- `coh_sum` — sum of *relative* positions inside the perception radius. The average is the direction to the group center.

### Steer: each rule becomes a clamped desired-minus-current

After the scan, each rule gets the same `steer_toward` treatment from lesson 8.1 — desired velocity at `max_speed` in the rule's direction, minus current velocity, clamped to `max_steer`:

```odin
accel: rl.Vector2
if perc_count > 0 {
	avg_vel := align_sum / f32(perc_count)
	avg_pos_off := coh_sum / f32(perc_count)
	accel += steer_toward(avg_vel, b.vel, s) * s.w_align
	accel += steer_toward(avg_pos_off, b.vel, s) * s.w_coh
}
if avoid_count > 0 {
	accel += steer_toward(sep / f32(avoid_count), b.vel, s) * s.w_sep
}

b.vel += clamp_length(accel, s.max_steer) * dt
b.vel = clamp_speed(b.vel, s)
b.pos = wrap(b.pos + b.vel * dt, SCREEN_W, SCREEN_H)
```

Two details worth staring at:

1. **Separation's weight is highest** (`w_sep = 1.4`). When a boid is crowded, "get off me" should beat "stay with the group" — otherwise flocks collapse into a single point. The defaults in `default_settings()` (`max_speed 320, min_speed 180, max_steer 900, perception 75, avoid 35`) are a known-good starting point, not sacred numbers — *you* will tune them with sliders in lesson 8.4.
2. **The counts guard division.** A boid that sees nobody contributes nothing but keeps flying — no division by zero, and (thanks to `safe_normalize` inside `steer_toward`) no NaN either.

That's the whole algorithm. It is genuinely ~40 lines of math — the magic is what emerges from it.

### Instrumentation: put a number on the cost

Before we call this "slow", let's measure it. `rl.GetTime()` returns f64 seconds; bracket the update and convert to milliseconds:

```odin
t0 := rl.GetTime()
update_boids(boids[:], settings, dt)
update_ms := (rl.GetTime() - t0) * 1000
```

Drawn next to the FPS counter, `update` is the number this module is about. The draw calls, the OS, the GPU — none of that is in it. Just the flock math.

### The cost: O(n²) is real math, not a vibe

At 150 boids, the inner scan runs 150 × 149 ≈ **22,000 pair checks per frame** — about 0.4 ms in a debug build on a typical machine. Nothing. But pair checks grow with the *square* of the boid count:

| boids | pair checks / frame | update (debug build, typical) |
|---|---|---|
| 150 | 22,000 | ~0.4 ms |
| 400 | 160,000 | ~2.5 ms |
| 2,000 | 4,000,000 | ~60 ms — 16 fps, unplayable |

Double the boids, quadruple the work. At 60 fps your entire frame budget is 16.7 ms; the naïve update eats all of it somewhere past 1,000 boids, and you'll feel the chug well before that — try 400+ and watch the `update` number climb *quadratically* even while FPS still looks fine. This wall is the whole reason lesson 8.3 exists: we don't make the checks faster, we make there be **fewer checks**.

🌐 **Web dev callout — the N+1 of gamedev**
> You've seen this shape: a list endpoint that runs one query per row. It demos fine with 20 rows, melts at 2,000, and the fix is never "query faster" — it's *stop issuing queries you don't need*. The naïve boid scan is an unindexed self-JOIN executed 60 times a second: every boid probes the whole table for "who's near me?". Lesson 8.3 is literally adding an index.

## Full listing

Runnable snapshot: [`code/02-naive-boids/main.odin`](code/02-naive-boids/main.odin)

```sh
odin run 08-boids/code/02-naive-boids
```

## Checkpoint

150 boids flock *properly* for the first time: they keep personal space, align into streams, and clump into swirling groups that split and merge across the wrap-around edges. The HUD shows FPS, `update` (well under 1 ms at 150), and the boid count. If it looks like brownian motion or collapses into one blob, check the rule weights and the `-=` on the separation accumulator.

## Exercises

1. **Easy:** Add a `pair_checks` counter incremented in the inner loop, draw it with the HUD. Confirm it reads 150 × 149 = 22,350 regardless of where the boids are. (Lesson 8.3's whole job is making this number small and *position-dependent*.)
2. **Medium:** Bump `BOID_COUNT` to 400, then 1,000. Record `update_ms` at each size on your machine and verify the ×4-per-×2 pattern. How many boids before your debug build drops below 60 fps? Re-run with `odin run . -o:speed` and find the new wall.
3. **Medium:** Replace wrap-around with **edge-margin avoidance**: delete the `wrap` call, and when a boid comes within ~80 px of an edge, steer it back toward the center (`steer_toward(center - b.pos, ...)`, stronger as it gets closer). Lague's sim bounds its world too — compare how the flock behaves at the borders.
4. **Hard:** Distance-weighted separation: scale each `sep` contribution by `1 - d/s.avoid_radius`, so near-collisions push harder than distant ones. Does it change the flock's "texture"? Keep or discard — that's tuning.

**Next:** [8.3 Spatial hashing: from 150 to 2,000+](03-spatial-hashing.md)
