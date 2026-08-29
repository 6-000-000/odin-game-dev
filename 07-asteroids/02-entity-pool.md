# 7.2 The entity pool

**Module:** 07-asteroids

## Goals

- Split the game into a multi-file package: `main.odin` + `entities.odin`
- Replace dynamic arrays with **fixed entity pools**: arrays + `active` flags
- Own every entity in one `World` struct, passed around by pointer
- Spawn waves of spinning asteroids near the edges, clear of the ship

## New concepts

| Concept | What it is |
|---|---|
| Multi-file package | One folder, one `package` name, shared scope — no imports between files (module 1.5) |
| Entity pool | A fixed array with an `active` flag per slot; spawning = finding a free slot |
| Free-slot search | Scanning for `!active` — that scan *is* the allocator |
| `World` struct | Ship + pools in one struct; `update`/`draw` procs take `^World` |
| `rl.DrawPolyLines` | Polygon outline with a rotation parameter — an instant asteroid |

## Walkthrough

### The split

Lesson 7.1's single file becomes two:

```
02-entity-pool/
├── main.odin      // package main — SCREEN constants + main() + the loop
└── entities.odin  // package main — Ship, Asteroid, World, and every proc that touches them
```

Both files say `package main`, so they share one scope exactly as if concatenated: `main.odin` calls `spawn_wave` and `update_ship` with **no import statement** (module 1.5's rule). Even `SCREEN_W`, declared in `main.odin`, is used inside `entities.odin`'s `wrap`. `odin run` compiles the whole folder — the folder *is* the build. From now on, `main.odin` stays small: the loop, the states, the HUD. Everything with a `pos` lives in `entities.odin`.

### Why pools beat dynamic arrays here

Flappy pooled 8 pipes. Asteroids wants 64 rocks — and next lesson adds bullets that live for 0.9 seconds and die constantly. A `[dynamic]` array forces you into `unordered_remove` while iterating backward (Pong 3.4's trick), with memory that grows and shrinks behind your back. A pool deletes all of that:

- **Fixed memory**: `[64]Asteroid` sits inside `World` from frame one. Zero per-frame allocation, ever.
- **Killing is free**: `a.active = false`. Spawning is finding `!active` and overwriting the slot. No remove, no swap, no allocator.
- **Iteration is a flat scan**: `if !a.active do continue`. 64 checks per frame is nothing; it's still nothing at 256 particles in lesson 7.4.

That third bullet has a hardware reason behind it — a flat array scans in address order, which is exactly what the CPU cache wants. Lesson 9.2 puts numbers on *why* flat arrays win, by converting the boids sim's memory layout and measuring the difference on screen.

One syntax note: `for &a in world.asteroids` iterates by **reference** — `a` is not a copy, so `a = Asteroid{...}` writes straight into the slot. (And `&a` yields a real pointer into the pool, which lesson 7.3 will use to split asteroids in place.)

### The asteroid and the world

```odin
Asteroid :: struct {
	pos:       rl.Vector2,
	vel:       rl.Vector2,
	radius:    f32,
	rotation:  f32, // degrees; spins via rot_speed
	rot_speed: f32, // deg/s
	active:    bool,
}

// Everything in the game lives in one struct, passed around by pointer.
World :: struct {
	ship:      Ship,
	asteroids: [ASTEROID_MAX]Asteroid,
}
```

Three radius tiers are defined now — `ASTEROID_BIG 40`, `ASTEROID_MED 22`, `ASTEROID_SMALL 12` — but waves only spawn BIG. The other two exist for lesson 7.3's splitting.

### Spawning a wave

```odin
spawn_wave :: proc(world: ^World, n: int) {
	spawned := 0
	for &a in world.asteroids {
		if spawned >= n do return
		if a.active do continue // slot in use — keep scanning
		a = Asteroid {
			pos       = random_edge_pos(world.ship.pos),
			vel       = random_drift(30, 90),
			radius    = ASTEROID_BIG,
			rotation  = rand.float32_range(0, 360),
			rot_speed = rand.float32_range(-60, 60),
			active    = true,
		}
		spawned += 1
	}
}
```

The free-slot search *is* the spawn logic — no append, no index bookkeeping. Positions come from `random_edge_pos`, which rejection-samples random points until one lands in an 80 px band along the edges **and** at least 150 px from the ship (`SHIP_CLEARANCE` — spawning a rock on top of the player is a rage-quit). Velocities come from `random_drift(30, 90)`: a random direction at 30–90 px/s.

### Update and draw

```odin
update_asteroids :: proc(world: ^World, dt: f32) {
	for &a in world.asteroids {
		if !a.active do continue
		a.pos += a.vel * dt
		a.rotation += a.rot_speed * dt
		wrap(&a.pos, a.radius)
	}
}

draw_asteroids :: proc(world: ^World) {
	for a in world.asteroids {
		if !a.active do continue
		rl.DrawPolyLines(a.pos, ASTEROID_SIDES, a.radius, a.rotation, rl.LIGHTGRAY)
	}
}
```

`DrawPolyLines` takes its rotation in **degrees** — the same convention as the ship, so no conversion anywhere. `rotation += rot_speed * dt` gives each rock its own lazy spin. And `wrap` is the ship's proc from 7.1, unchanged: one wrapper, every entity. That's the payoff of giving it a `radius` parameter.

🌐 **Web dev callout — pools are slab allocation**
> You've met this pattern: database connection pools, worker thread pools, V8's object arenas. The motivation is identical — allocation is expensive and unpredictable, so pay it once up front and recycle forever. In JS, an array you `push`/`splice` every frame eventually triggers the GC; in a game loop, a GC-style pause *is* a dropped frame. Odin has no GC, but the habit is the point: per-frame allocation is a code smell in any language that has to hit a frame deadline.

## Full listing

Runnable snapshot: [`code/02-entity-pool/main.odin`](code/02-entity-pool/main.odin) + [`code/02-entity-pool/entities.odin`](code/02-entity-pool/entities.odin)

```sh
odin run 07-asteroids/code/02-entity-pool
```

## Checkpoint

The ship flies exactly as in 7.1, now sharing the screen with 4 fat wireframe asteroids that drift, spin at their own rates, and wrap around the edges. Nothing collides yet — fly straight through a rock; it doesn't care. Press **R** to wipe the field (`for &a in world.asteroids do a.active = false`) and redeal a fresh wave. Then open `main.odin`: it's 36 lines of loop and nothing else. That's the split working.

## Exercises

1. **Easy:** Give each asteroid its own vertex count: add `sides: i32` to `Asteroid`, set it from `rl.GetRandomValue(7, 11)` at spawn, and pass it to `DrawPolyLines`. Same rocks, instant variety.
2. **Easy:** Bias spawn velocities toward the screen center so rocks cross the playfield instead of skimming along the edges. (Hint: direction from `pos` toward `{SCREEN_W/2, SCREEN_H/2}`, plus ±0.6 rad of random spread.)
3. **Medium:** Asteroid-asteroid collision: for every active pair (`i < j`), if the circles overlap, swap their velocities. It's O(n²) — 64²/2 ≈ 2,000 checks a frame, which is fine *here*. Remember this number in module 8, where 2,000 boids make the same loop cost two million checks.
4. **Medium:** Wrap ghosting: when an asteroid is within `radius` of an edge, draw it a second time offset by ±`SCREEN_W`/`SCREEN_H` on the opposite side. Classic Asteroids does this so rocks never pop at the boundary. Do it entirely inside `draw_asteroids` — don't touch `update`.

**Next:** [7.3 Shooting and splitting](03-shooting-and-splitting.md)
