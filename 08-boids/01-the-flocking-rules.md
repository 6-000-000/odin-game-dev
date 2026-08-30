# 8.1 The flocking rules

> 📺 **Watch first:** [Sebastian Lague's boids video](https://www.youtube.com/watch?v=bqtqltqcQhw) — this module builds exactly what he builds, in Odin.

**Module:** 08-boids

## Goals

- Know what a "boid" is and where the three flocking rules come from (Reynolds, 1986)
- Model the video's perception: one radius to *see* flockmates, a smaller one to *avoid* them
- Implement steer-toward-desired: `desired − current` velocity, clamped
- Draw a boid as a triangle rotated to its heading
- Run 20 boids with only cohesion + a wander jitter, in a wrap-around world

## New concepts

| Concept | What it is |
|---|---|
| Boid | An agent with `pos, vel: rl.Vector2` — nothing else. Flocking is emergent, not scripted |
| Perception vs avoid radius | A boid *sees* neighbors within `perception_radius`; it *flees* neighbors within the smaller `avoid_radius` |
| Steering | `steer = clamp(normalize(dir) * max_speed − vel, max_steer)` — "where I want to go" minus "where I'm going" |
| Toroidal world | Positions wrap at the edges: exit right, re-enter left. Distances must wrap too |
| `math.atan2(vel.y, vel.x)` | Velocity → heading angle, for drawing the nose forward |
| `rand.reset(seed)` | Fixed seed = a reproducible flock, invaluable for debugging |

## Walkthrough

### The idea: three local rules, global order

In 1986 Craig Reynolds published *"Flocks, Herds, and Schools: A Distributed Behavioral Model"* and showed something shocking: realistic bird flocking needs no leader, no plan, no choreography. Each bird follows **three rules about its immediate neighbors**, and flock-shaped order *emerges* on its own:

```
SEPARATION                     ALIGNMENT                     COHESION
"don't crowd me"               "fly with my neighbors"       "stay with the group"
(avoid radius)                 (perception radius)           (perception radius)

   a  b→  c                    a: →                          a ·
    ↕ too close!               b: ↗    avg: ↗                    · ✕ ·  ← center
 steer: away from              c: →    steer to match          b ·  · c
 a and c                                                    steer: toward ✕
```

Lague's video (and this module) uses his version of the perception model: each boid sees flockmates within a **perception radius**, but separation only triggers within a smaller **avoid radius** inside it:

```odin
Settings :: struct {
	max_speed:         f32, // px/s — hard speed ceiling
	min_speed:         f32, // px/s — boids never stop, they always fly
	max_steer:         f32, // px/s² — max turning acceleration
	perception_radius: f32, // px — how far a boid sees flockmates
	avoid_radius:      f32, // px — "too close" distance for separation
	w_sep:             f32, // rule weights (next lesson)
	w_align:           f32,
	w_coh:             f32,
}
```

**Every tuning constant of the simulation lives in this one struct** and is passed to every proc that needs it. It looks like overkill for 20 boids — but in lesson 8.4 we'll wire these fields to on-screen sliders and tune a living flock in real time, without touching the update code. Design the plumbing now, enjoy it later.

The snapshot fills the struct with the values that carry the whole module, and names today's three top-level constants alongside:

```odin
BOID_COUNT :: 20
BOID_SIZE :: 8 // px from center to nose
WANDER :: 0.05 // fraction of max_steer applied as random jitter

default_settings :: proc() -> Settings {
	return {
		max_speed = 320,
		min_speed = 180,
		max_steer = 900,
		perception_radius = 75,
		avoid_radius = 35,
		w_sep = 1.4,
		w_align = 1.0,
		w_coh = 1.0,
	}
}
```

Only cohesion and `WANDER` do anything today; the rest is plumbing for 8.2–8.4.

### Steering: desired minus current

A boid doesn't teleport toward its goal; it *steers*, like a plane banking. Given a direction it wants to go, the math is always the same three steps:

```odin
steer_toward :: proc(dir, vel: rl.Vector2, s: Settings) -> rl.Vector2 {
	desired := safe_normalize(dir) * s.max_speed
	return clamp_length(desired - vel, s.max_steer)
}
```

1. `desired` — full speed in the wanted direction.
2. `desired - vel` — the velocity *change* that would get us there instantly.
3. `clamp_length(..., max_steer)` — but a boid has limited turning power, so cap the change. `max_steer` is the difference between a hummingbird and an oil tanker.

`clamp_length` is the magnitude cap you'd expect — scale down proportionally when over the limit, pass through otherwise:

```odin
clamp_length :: proc(v: rl.Vector2, max_len: f32) -> rl.Vector2 {
	len := rl.Vector2Length(v)
	if len > max_len && len > 0 do return v * (max_len / len)
	return v
}
```

Why `safe_normalize` and not `rl.Vector2Normalize`? Because `rl.Vector2Normalize({0, 0})` divides by length 0 and yields **NaN** — and one NaN velocity poisons every sum it touches (NaN + anything = NaN; soon half your flock is at coordinates `nan, nan` and the screen is empty). Guard it once, use it everywhere:

```odin
safe_normalize :: proc(v: rl.Vector2) -> rl.Vector2 {
	len := rl.Vector2Length(v)
	if len < 0.0001 do return {}
	return v / len
}
```

This is a real bug you *will* hit if you normalize raw: two boids at the exact same position produce a zero offset, and one frame later the simulation is silently dead.

### A wrap-around world (and its ruler)

Hard walls make flocks pile up in corners, so our world is **toroidal**: fly off the right edge, reappear on the left. Positions are easy — add or subtract the world size:

```odin
wrap :: proc(p: rl.Vector2, w, h: f32) -> rl.Vector2 {
	pos := p
	if pos.x < 0 do pos.x += w
	if pos.x >= w do pos.x -= w
	if pos.y < 0 do pos.y += h
	if pos.y >= h do pos.y -= h
	return pos
}
```

But wrapping positions breaks naive distance math: a boid at `x = 5` and one at `x = 1275` are 1,270 px apart on paper, yet only **6 px apart across the seam**. Every perception check needs the shortest vector between two points *on the torus*:

```odin
offset :: proc(a, b: rl.Vector2, w, h: f32) -> rl.Vector2 {
	d := b - a
	if d.x > w / 2 do d.x -= w
	if d.x < -w / 2 do d.x += w
	if d.y > h / 2 do d.y -= h
	if d.y < -h / 2 do d.y += h
	return d
}
```

Keep this helper in your head as "wrap-aware `b - a`". Every rule — separation, alignment, cohesion — measures neighbors through it, in every lesson of this module.

### Cohesion only, plus a little chaos

Today's update implements just one rule — cohesion — plus a tiny random **wander** so isolated boids drift instead of flying in straight lines forever:

```odin
for &b, i in boids {
	coh_sum: rl.Vector2
	count := 0
	for other, j in boids {
		if i == j do continue
		to_other := offset(b.pos, other.pos, SCREEN_W, SCREEN_H)
		if rl.Vector2Length(to_other) < s.perception_radius {
			coh_sum += to_other // relative positions of everyone I see
			count += 1
		}
	}

	accel: rl.Vector2
	if count > 0 {
		// b.pos + avg(to_other) is the perceived center of the flock
		accel += steer_toward(coh_sum / f32(count), b.vel, s) * s.w_coh
	}
	accel += {rand.float32_range(-1, 1), rand.float32_range(-1, 1)} * s.max_steer * WANDER

	b.vel += clamp_length(accel, s.max_steer) * dt
	b.vel = clamp_speed(b.vel, s)
	b.pos = wrap(b.pos + b.vel * dt, SCREEN_W, SCREEN_H)
}
```

Note the trick in the accumulator: instead of summing absolute positions (which breaks across the seam), we sum the *relative* offsets `to_other`. `b.pos + coh_sum/count` is the perceived center, so the direction to it is just `coh_sum/count` — already relative, seam-safe.

The integration order matters and never changes for the rest of the module: **clamp the steering, apply it to velocity, clamp the speed, move, wrap.** `clamp_speed` keeps speed inside `[min_speed, max_speed]` — boids are like sharks, they can't hover. It has one surprise clause: besides capping at `max_speed` and boosting to `min_speed`, a *near-zero* velocity is replaced outright with a random direction at `min_speed` — rather than let a boid degenerate to a standstill, the sim kicks it awake. (That branch consumes RNG state, which would perturb the deterministic-seed story below — in practice it almost never fires.)

### Drawing: a triangle that faces its velocity

```odin
heading := math.atan2(b.vel.y, b.vel.x)
nose  := b.pos + {math.cos(heading), math.sin(heading)} * BOID_SIZE
left  := b.pos + {math.cos(heading + 2.5), math.sin(heading + 2.5)} * BOID_SIZE * 0.6
right := b.pos + {math.cos(heading - 2.5), math.sin(heading - 2.5)} * BOID_SIZE * 0.6
rl.DrawTriangle(nose, left, right, color)
```

`atan2(y, x)` turns the velocity vector into an angle. The nose sits one `BOID_SIZE` along that angle (`{cos θ, sin θ}` is the unit vector at θ — the polar→cartesian conversion from Pong), and the two rear points sit at ±2.5 radians behind it, slightly shorter. Three points, one `DrawTriangle`, instant "bird".

One last setup detail — we seed the RNG:

```odin
rand.reset(0xB01D5) // fixed seed = reproducible flock (change it!)
```

Same seed, same flock, every run. When something looks wrong you can debug a *deterministic* simulation; change the seed when you want a new flock. The seed feeds `random_boid(s, w, h)`, called once per boid at startup: a random position, and a random direction at a random speed inside `[min_speed, max_speed]` — so the same seed deals the same opening frame, boid for boid.

🌐 **Web dev callout — emergence is just `reduce` over local state**
> Each boid is a pure function of its neighborhood: take the boids within 75 px, reduce them to an average, steer toward it. No coordinator, no events, no subscriptions — the flock-shaped "global state" you see on screen *doesn't exist anywhere in memory*. If you've ever derived UI from `items.reduce(...)` instead of storing derived state, you know the pattern: compute what you can, store only what you must. The eerie part of boids is how much you can compute with so little stored: two `Vector2`s per bird.

## Full listing

Runnable snapshot: [`code/01-the-flocking-rules/main.odin`](code/01-the-flocking-rules/main.odin)

```sh
odin run 08-boids/code/01-the-flocking-rules
```

## Checkpoint

20 triangles drift, notice each other, and pull into loose, wandering clumps that orbit and merge across the screen edges. Nothing avoids collisions yet (boids happily overlap — separation is next lesson), and there's no coordinated direction (that's alignment). The FPS counter sits in the corner, pinned at 60.

## Exercises

1. **Easy:** Draw the perception circle of the boid nearest the mouse. Find the nearest boid each frame (`offset` + `Vector2Length`), then `rl.DrawCircleLines` with `s.perception_radius`. Watch which flockmates fall inside it.
2. **Medium:** Build an *alignment-only* variant: replace the cohesion accumulator with `align_sum += other.vel` and steer toward `align_sum / f32(count)`. No cohesion, no separation. You'll get synchronized lanes of boids that never group up — a great intuition for what each rule contributes.
3. **Medium:** Color boids by speed: compute `t := clamp((speed - s.min_speed) / (s.max_speed - s.min_speed), 0, 1)` and draw with `rl.ColorLerp(rl.SKYBLUE, rl.RED, t)`. (Lesson 8.4 does this for real — Lague's sim does it too.)
4. **Hard:** Separation as personality: pick the boid nearest the mouse and give *it alone* a separation rule — steer it away from every neighbor within 35 px at 3× the cohesion weight, drawn red. The flock should eject it like an immune system. One boid with different weights is the entire idea of 8.4's predator, seen from the inside.

**Next:** [8.2 The naïve implementation](02-naive-boids.md)
