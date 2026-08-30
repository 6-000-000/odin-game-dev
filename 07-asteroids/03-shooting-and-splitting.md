# 7.3 Shooting and splitting

**Module:** 07-asteroids

## Goals

- A second pool: bullets with speed, lifetime, and a fire cooldown
- Circle-vs-circle collision with `rl.CheckCollisionCircles`
- **Splitting**: big → 2 medium, medium → 2 small — spawning entity trees
- Lives, respawn invulnerability, game over, and wave progression

## New concepts

| Concept | What it is |
|---|---|
| Cooldown | A timer on the ship that gates how often an action may happen |
| Splitting | One entity dies; its children spawn from its state — an entity tree, flattened into the pool |
| Invulnerability window | A post-respawn grace period: collision is skipped while the timer runs |
| `CheckCollisionCircles` | raylib's circle-vs-circle test: center distance < r1 + r2 |

## Walkthrough

### The bullet pool

Same pattern, second time. `Bullet` gets a pool of 32 inside `World`, and the ship grows two timers (`cooldown`, `invuln`) that `update_ship` decays with `max(0, t - dt)`:

```odin
Bullet :: struct {
	pos:    rl.Vector2,
	vel:    rl.Vector2,
	life:   f32, // seconds remaining
	active: bool,
}
```

```odin
try_fire :: proc(world: ^World) {
	ship := &world.ship
	if ship.cooldown > 0 do return
	b := free_bullet(world)
	if b == nil do return // pool full: 32 live bullets is plenty — drop the shot
	facing := ship_facing(ship.angle)
	b^ = Bullet {
		pos    = ship.pos + facing * ship.radius, // fire from the nose
		vel    = facing * BULLET_SPEED,
		life   = BULLET_LIFE,
		active = true,
	}
	ship.cooldown = FIRE_COOLDOWN
}
```

`free_bullet` is the free-slot search from 7.2, promoted to a proc and returning `nil` when full — and the caller just *drops the shot*. Defensive and invisible: at 0.9 s life and 0.15 s cooldown you can keep at most 6 bullets live anyway; the 32-cap is pure headroom. Note `b^ = Bullet{...}`: `b` is a `^Bullet` pointer into the pool, so we dereference-assign. Range loops give us references (`b.active = false` writes through); an explicit pointer needs `^`.

The promotion is worth seeing, because it reshapes code you already typed. Both pools get the same three-liner:

```odin
// The free-slot search: the pool's allocator. Returns nil when the pool is full.
free_asteroid :: proc(world: ^World) -> ^Asteroid {
	for &a in world.asteroids {
		if !a.active do return &a
	}
	return nil
}
```

And 7.2's `spawn_wave` is **rewritten on top of it** — the `spawned` counter and the by-reference scan are gone; delete that version:

```odin
spawn_wave :: proc(world: ^World, n: int) {
	for _ in 0 ..< n {
		a := free_asteroid(world)
		if a == nil do return // pool full — spawn what we could (defensive)
		a^ = Asteroid{ /* same fields as 7.2 */ }
	}
}
```

One allocator idiom, three consumers already (`spawn_wave`, `try_fire`, and `split_asteroid` below).

Bullets integrate, age, die, and wrap — the full entity lifecycle in six lines:

```odin
update_bullets :: proc(world: ^World, dt: f32) {
	for &b in world.bullets {
		if !b.active do continue
		b.pos += b.vel * dt
		b.life -= dt
		if b.life <= 0 {
			b.active = false
			continue
		}
		wrap(&b.pos, BULLET_RADIUS)
	}
}
```

### Bullet meets rock

```odin
collide_bullets :: proc(world: ^World) {
	for &b in world.bullets {
		if !b.active do continue
		for &a in world.asteroids {
			if !a.active do continue
			if rl.CheckCollisionCircles(b.pos, BULLET_RADIUS, a.pos, a.radius) {
				b.active = false
				world.score += asteroid_score(a.radius)
				split_asteroid(world, &a)
				break // the bullet is spent — on to the next one
			}
		}
	}
}
```

Every bullet checks every active rock — 32 × 64 = 2,048 circle tests worst case, which is nothing. The `break` matters: the bullet is dead, so it can't also hit a second rock this frame. And `&a` is the pointer-into-the-pool promised last lesson — `split_asteroid` needs to deactivate *this slot* and hunt for free ones in the same array.

### Splitting: the entity tree, flattened

```odin
split_asteroid :: proc(world: ^World, a: ^Asteroid) {
	pos := a.pos
	radius := a.radius
	a.active = false
	if radius == ASTEROID_SMALL do return

	child_radius: f32 = radius == ASTEROID_BIG ? ASTEROID_MED : ASTEROID_SMALL
	for _ in 0 ..< 2 {
		child := free_asteroid(world)
		if child == nil do return // pool full: drop the fragment rather than fail (defensive)
		child^ = Asteroid {
			pos       = pos,
			vel       = random_drift(60, 120),
			radius    = child_radius,
			rotation  = rand.float32_range(0, 360),
			rot_speed = rand.float32_range(-90, 90),
			active    = true,
		}
	}
}
```

Read this carefully — it's the lesson. The parent dies; **two children spawn from its state** (position, smaller tier, new random velocities). That's a tree in game-design terms — one rock becoming a pair, each of which can become a pair — but there's no tree *data structure*: the pool flattens it into slots. Copy `pos`/`radius` into locals *before* `a.active = false`, because the free-slot search may hand back the very slot you just freed (the parent is inactive now — first free slot found). Score by size: big 20, medium 50, small 100 (`asteroid_score`) — the most dangerous rock pays the most.

The defensive `nil` return is worth its comment: deep into a wave, splits can genuinely exhaust 64 slots (every big rock becoming two mediums becoming two smalls…). The game drops the fragment and keeps running. No crash, no allocation spike.

### Dying, respawning, and the wave counter

Ship-vs-rock is the same circle test, guarded by the invulnerability timer:

```odin
collide_ship :: proc(world: ^World) {
	ship := &world.ship
	if ship.invuln > 0 do return // safe after respawn — no collision
	// ...
	world.lives -= 1
	if world.lives > 0 do respawn_ship(world)
	return // one death per frame is plenty
}
```

`respawn_ship` centers the ship, zeroes velocity, resets the angle to 0 (pointing up), and sets `invuln = INVULN_TIME` (2 s) — the collision guard above is what *enforces* the safety. (The ship still draws solid white this lesson; the blink arrives with the juice in 7.4.) The ship's collision radius is `ship.radius * 0.7` — smaller than the drawn triangle. Hitboxes that are kinder than the visuals are a tradition; never make the player die to a pixel that looked like empty space.

`World` grows to carry the new state — `bullets: [BULLET_MAX]Bullet`, `score: int`, `lives: int`, `wave: int` — with `lives` starting at `START_LIVES :: 3`. Drawing bullets is the same skip-inactive loop you've now written three times, one `rl.DrawCircleV` per live slot.

Wave progression lives in `main.odin` right after the collision calls:

```odin
if world.lives <= 0 {
	state = .Game_Over
} else if asteroids_remaining(&world) == 0 {
	world.wave += 1
	spawn_wave(&world, world.wave + 3)
}
```

Wave 1 spawns 4 rocks; each clear adds one more. And `start_game` shows off the pool's best trick — `world^ = World{}` zeroes the entire struct, retiring every slot of every pool in one assignment.

(One removal while you're diffing: 7.2's R-key redeal is gone. Waves arrive on their own now, so the debug key would just be a cheat for the counter.)

The HUD: score top-center, `WAVE n` top-right, and lives as a row of little ship triangles top-left — `draw_lives` reuses `ship_point` with angle 0. The `Game_State` enum is back from Pong 3.3 (`Playing` / `Game_Over`, switched in both update and draw), with one twist: `.Game_Over` keeps calling `update_asteroids`, so the field keeps drifting behind the text.

🌐 **Web dev callout — you already know state machines**
> `enum { Playing, Game_Over }` plus a `switch` in update and a `switch` in draw is a hand-rolled XState or a Redux reducer: states are a closed union, events are inputs (`SPACE`, `lives == 0`), transitions are assignments. Web devs reach for a library because UI state graphs get wide; a game loop keeps the same pattern with two cases and zero dependencies. When your switches start nesting switches, *then* you've earned a statechart.

## Full listing

Runnable snapshot: [`code/03-shooting-and-splitting/main.odin`](code/03-shooting-and-splitting/main.odin) + [`code/03-shooting-and-splitting/entities.odin`](code/03-shooting-and-splitting/entities.odin)

```sh
odin run 07-asteroids/code/03-shooting-and-splitting
```

## Checkpoint

A complete game loop, minus juice. SPACE fires from the nose (hold it: cooldown caps the rate); a big rock pops into two mediums, mediums into two smalls, smalls vanish, and the score ticks 20/50/100. Get hit and you lose one of three ships, respawning at center — during the 2-second invulnerability window rocks pass through you. Clear the field and the next wave arrives one rock heavier. Lose all three ships and it's GAME OVER; SPACE starts a fresh run. Play until you see a wave where splitting fills the screen with smalls — that's the tree exploding, and the pool absorbing it.

## Exercises

1. **Easy:** Sniper mode: `BULLET_LIFE 1.8`, `FIRE_COOLDOWN 0.5`, `BULLET_SPEED 700`. Play one wave, then revert. Two constants redesigned the weapon — write a sentence about how the feel changed.
2. **Easy:** Momentum inheritance: in `split_asteroid`, add half the parent's velocity to each child (`vel = random_drift(60, 120) + a.vel * 0.5` — copy `a.vel` into a local first). Fragments now carry the rock's motion; shooting a fast rock feels completely different.
3. **Medium:** Hyperspace on SHIFT: teleport to a random position with `ship.vel = {}` — but 10% of the time (`rl.GetRandomValue(1, 10) == 1`) treat it as a ship death. The classic panic button, priced so you only touch it when cornered.
4. **Hard:** The UFO: every 20 s, spawn a small saucer at a random edge y that crosses the screen horizontally; every 1.5 s it fires a bullet *aimed at the ship* (`math.atan2(dy, dx)`, then `{cos, sin}` — watch the −90° convention: the UFO doesn't use it); it's worth 200 points and dies to one hit. Everything it needs already exists: a pool slot, a spawn timer, `CheckCollisionCircles`.

**Next:** [7.4 Particles, audio, and juice](04-particles-audio-juice.md)
