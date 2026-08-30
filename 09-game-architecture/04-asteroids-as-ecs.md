# 9.4 Rebuilding Asteroids on the mini-ECS

**Module:** 09-game-architecture

## Goals

- Port 7.3's Asteroids — ship, rocks, bullets, splitting, waves, score, lives, invulnerability — onto the 9.3 framework
- Extend the framework with game components: a tag, an enum-indexed tier table, timers — and feel how cheap that is
- Learn what does *not* become an entity: singleton state stays a plain struct
- Compare ECS vs the 7.2 pool **honestly**, and leave with a decision framework for your own games

## New concepts

| Concept | What it is |
|---|---|
| Tag component | A bit with no column and no data — "is player-controlled" is a yes/no property |
| Component removal | `mask -= {.Invuln}` — clearing a bit retires a component |
| Enum-indexed table | `[Rock_Tier]f32{.Big = 40, …}` — lookup by enum, no switch |
| Singleton state | Score/lives/wave as one plain struct in the World, *not* an entity |
| Framework vs bespoke | The tradeoff this lesson exists to measure |

## Walkthrough

### The port: what maps to what

Same game, same constants (thrust 300, rotation 220 deg/s, bullet speed 500 / life 0.9 / cooldown 0.15, tiers 40/22/12, waves of `wave + 3`, 3 lives, 2 s invulnerability), same `wrap` and `ship_point` math — re-organized:

| 7.3 (pools) | 9.4 (ECS) |
|---|---|
| `Ship` struct | Entity with Position + Velocity + Angle + Radius + **PlayerControlled** |
| `[64]Asteroid` pool | Entities with Position + Velocity + Radius + Tier + Spin |
| `[32]Bullet` pool | Entities with Position + Velocity + Lifetime |
| `active` flags | `alive` + `generations` (stale-handle safety, free) |
| `world.score/lives/wave` | A plain `Game` struct — still not entities |
| `update_asteroids`, `update_bullets`… | Systems named by *capability*: move, spin, lifetime, input, collide |

Particles from 7.4 port as entities (an exhaust puff is Position+Velocity+Lifetime) — that's exercise 3. Audio ports as *itself*: `load_sounds` plus an `rl.PlaySound` at each event site, since systems are plain procs and there's no ECS lesson in it. Both are left out of the snapshot to keep the comparison readable.

One deliberate simplification to flag against 7.3's constants: rocks here tumble at `rand.float32_range(-90, 90)` for *all* spawns — 7.3 used ±60 for wave rocks and ±90 for splits, but 9.4's single shared `spawn_rock` serves both, so the livelier range won. Everything else matches 7.3 exactly.

### Growing the framework is the point

The 9.3 machinery — `spawn_entity`, `despawn_entity`, `is_alive`, `handle_at`, the system sweep shape — is unchanged. What changed is the schema:

```odin
// The schema, Asteroids edition.
//
// PlayerControlled is a TAG: it has no column and no data — just a bit in the
// mask. "Reads player input" is a yes/no property, so a bit is all it takes.
Component :: enum {
	Position,
	Velocity,
	Spin,     // visual tumble (rocks): angles[i] += spins[i] * dt
	Lifetime, // bullets: despawn at 0
	Angle,    // ship heading (facings[i]), degrees — input-steered
	Radius,   // collision circle + draw size
	Tier,     // rock class (Big/Medium/Small): drives split + score
	Invuln,   // invuln_timers[i]: seconds of post-respawn safety left
	PlayerControlled,
}
```

The five new components cost five enum cases, four columns (`facings`, `radii`, `tiers`, `invuln_timers`), and five adders — the tag needs no column. That *is* the ECS sales pitch, and it's *mostly* true. The honest footnotes, so your 9.3→9.4 diff holds no surprises: the playground-only pieces were **removed** (`Pulse` with its `pulses`/`scales` columns, `add_pulse`, `system_pulse`, and `clear_world`), one framework proc was **added** — `reset_world`, which zeroes the World but preserves the `free_list`'s allocation across restarts (grab the slice, `world^ = World{}`, put it back) — and `World` gained the `game` field you'll meet below. `Angle` gets its own column (`facings`) rather than sharing Spin's `angles`: same data shape, different role — a rock tumbles for looks, a ship's heading is gameplay. `PlayerControlled` is a **tag**: no array at all, because there's nothing to store. (If tags feel familiar — they're marker interfaces, or boolean flag columns on a row.)

Tier data lives in tables indexed *by the enum*:

```odin
// Tier drives radius and score — indexed BY THE ENUM, no switch required.
// (Package-level variables, not constants: a constant array can't be indexed
// with a runtime value.)
TIER_RADIUS := [Rock_Tier]f32{.Big = 40, .Medium = 22, .Small = 12}
TIER_SCORE  := [Rock_Tier]int{.Big = 20, .Medium = 50, .Small = 100}
```

🌐 **Web dev callout — hand-rolled tables vs one generic engine**
> This port is a refactoring you've done a dozen times. 7.3 is the "bespoke table per domain" era: the rocks table, the bullets table, each with its own allocator (`free_asteroid`, `free_bullet`), its own validity convention (`active`), its own query procs. 9.4 is the "one generic table engine" era: one allocator, one validity check, one query mechanism — you pay in indirection (`world.positions[e.index]` instead of `rock.pos`) and buy back uniformity. You know this tradeoff from the other side too: it's exactly why teams adopt a framework over hand-rolled per-feature code, and exactly why they sometimes regret it when the app only ever had three features. Hold both feelings; the comparison below needs them.

### The game systems

The spawn recipes are compositions. The ship is the interesting one — five components, one of them a tag:

```odin
spawn_ship :: proc(world: ^World) -> Entity {
	e := spawn_entity(world)
	add_position(world, e, {SCREEN_W / 2, SCREEN_H / 2})
	add_velocity(world, e, {})
	add_angle(world, e, 0)
	add_radius(world, e, SHIP_RADIUS)
	add_tag(world, e, .PlayerControlled)
	return e
}
```

And the input system acts on *anything* carrying that tag — today one ship, but nothing in the code knows that:

```odin
system_input :: proc(world: ^World, dt: f32) {
	game := &world.game
	game.cooldown = max(0, game.cooldown - dt)
	for i in 0 ..< world.count {
		if !world.alive[i] do continue
		if world.masks[i] >= {.PlayerControlled, .Angle, .Velocity} {
			if rl.IsKeyDown(.LEFT) do world.facings[i] -= ROT_SPEED * dt
			if rl.IsKeyDown(.RIGHT) do world.facings[i] += ROT_SPEED * dt
			if rl.IsKeyDown(.UP) {
				world.velocities[i] += ship_facing(world.facings[i]) * THRUST * dt
			}
			world.velocities[i] *= 1 - DAMPING * dt
			if rl.IsKeyDown(.SPACE) && game.cooldown <= 0 {
				facing := ship_facing(world.facings[i])
				spawn_bullet(world, world.positions[i] + facing * world.radii[i], facing * BULLET_SPEED)
				game.cooldown = FIRE_COOLDOWN
			}
		}
	}
}
```

Collisions become queries over named masks — `BULLET_MASK :: bit_set[Component]{.Position, .Velocity, .Lifetime}` and `ROCK_MASK :: bit_set[Component]{.Position, .Radius, .Tier}` — swept with the same `>=` idiom:

```odin
system_collide_bullets :: proc(world: ^World) {
	for b in 0 ..< world.count {
		if !world.alive[b] do continue
		if !(world.masks[b] >= BULLET_MASK) do continue // not a bullet
		for r in 0 ..< world.count {
			if !world.alive[r] do continue
			if !(world.masks[r] >= ROCK_MASK) do continue // not a rock
			if rl.CheckCollisionCircles(world.positions[b], BULLET_RADIUS, world.positions[r], world.radii[r]) {
				despawn_entity(world, handle_at(world, b))
				world.game.score += TIER_SCORE[world.tiers[r]]
				split_rock(world, r) // despawns the rock, spawns the children
				break // the bullet is spent — on to the next one
			}
		}
	}
}
```

Splitting, waves, scoring: same rules as 7.3, re-spelled — `split_rock` despawns the parent and spawns two children one tier down; the wave check counts `.Tier` entities; score comes from `TIER_SCORE`. The invulnerability system shows off something pools can't do gracefully — **component removal**:

```odin
// Tick invulnerability down and REMOVE the component at zero — `-=` clears the
// bit. Component removal is as cheap as addition.
system_invuln :: proc(world: ^World, dt: f32) {
	for i in 0 ..< world.count {
		if !world.alive[i] do continue
		if .Invuln in world.masks[i] {
			world.invuln_timers[i] -= dt
			if world.invuln_timers[i] <= 0 {
				world.masks[i] -= {.Invuln}
			}
		}
	}
}
```

The ship's collision system just checks `.Invuln in world.masks[i]` — while the bit is set, rocks pass through; when the timer retires the component, the ship becomes mortal again. The ship even blinks while invulnerable, because the draw code reads the same bit.

### What stays a struct

Not everything is an entity, and pretending otherwise is where ECS goes cult-y. There is exactly one score, one lives counter, one current wave, one ship — so they live in a plain struct inside the World:

```odin
// Singleton state. One score, one lives counter, one ship — so this stays a
// plain struct inside the World, NOT an entity. The ship is kept by handle.
Game :: struct {
	score:    int,
	lives:    int,
	wave:     int,
	cooldown: f32, // seconds until the next shot is allowed
	ship:     Entity,
}
```

The ship field is a *handle*, so when the final death despawns the ship entity, `is_alive(world, game.ship)` simply goes false — no dangling pointer, no null check convention. The main loop is now a table of contents for the whole game:

```odin
case .Playing:
	system_input(&world, dt)
	system_move(&world, dt)
	system_wrap(&world)
	system_spin(&world, dt)
	system_lifetime(&world, dt)
	system_invuln(&world, dt)
	system_collide_bullets(&world)
	system_collide_ship(&world)
```

`system_wrap` is the one system not shown above, and it's the nicest demonstration of the column model: it sweeps every entity with `.Position`, using `world.radii[i]` as the wrap margin when the entity has `.Radius` — and falling back to `BULLET_RADIUS` when it doesn't. One proc wraps ships, rocks, and bullets without knowing any of those kinds exist.

Two behavior notes against 7.3, both deliberate. In `.Game_Over` the loop runs move/wrap/spin but **not** `system_lifetime`, so in-flight bullets now drift forever (7.3 froze them); rocks and ship-death behave the same either way. And `draw_ship` reads `rl.IsKeyDown(.UP)` directly to draw the flame — input inside draw code, a small impurity kept so drawing needs no game state; the purist fix is a `Thrusting` tag written by `system_input`, and you're equipped to write it.

### The honest comparison

This lesson's reason to exist. Same game, both ways, no religion:

| | 7.3 pools + structs | 9.4 mini-ECS |
|---|---|---|
| New entity kind | New struct + pool + update/draw/collide procs | New component columns + a spawn recipe (exercise 1: a UFO in ~15 lines) |
| Spawn/despawn/validity | Re-implemented per pool (`free_asteroid`, `free_bullet`, `active`) | One allocator, one `is_alive`, one despawn — for every kind, forever |
| Stale references | Raw pointers into pools — recycle hazard | Handles + generations — safe for free |
| Reading an entity | `rock.pos` — typed, direct | `world.positions[e.index]` — a hop, no type at the end |
| Collision loops | Typed nested loops over known pools | Scan the whole store with mask tests, early-out per entity |
| Capacity | Hard caps per kind: 64 rocks, 32 bullets | One shared 1024-slot store — any mix of kinds, until it isn't |
| System boundaries | "The asteroid code" is a place | Capabilities, listed explicitly in the main loop |
| Top-to-bottom read | `update_bullets` shows you *bullets* | `system_lifetime` shows you *anything with a Lifetime* — you grep to find who |
| Debugging | A rock is a struct in the debugger | An entity is a number; you inspect columns by index |
| Ceremony | ~0 for 3 kinds | 9 adders, masks, handles — for 3 kinds |

### Choosing: the decision framework

Three axes decide it: **entity count** × **entity variety** × **how much iteration the design needs**.

- **Dozens-to-hundreds of entities, few kinds** — every project in this course: pools + plain structs win on simplicity, and it isn't close. Pong, Breakout, Snake, Flappy: trivially. Asteroids (~100 entities, 3 kinds): the pool was fine; you ported it for the *lesson*, not because it hurt.
- **Thousands of entities, one kind** — Boids: organization is irrelevant (an ECS with one component set is a pool with extra steps). *Layout* is everything — that's 9.2. Layout and organization are orthogonal choices; either half of this module applies without the other.
- **High variety, heavy design iteration** — dozens of enemy/pickup/buff kinds, designers mixing capabilities weekly: ECS pays for itself. Adding "a rock that also homes and also pulses" being a mask edit instead of a refactor is the whole ballgame.
- Real engines land everywhere on this: Unity DOTS, Bevy, and flecs are full ECS (with archetype storage and parallel scheduling our 180 lines skip); plenty of shipped games run hybrid — ECS for gameplay organization, hand-tuned SoA for the physics inner loop. You now have the vocabulary for all of it, and — more valuable — a working sense of when *not* to reach for it.

## Full listing

Runnable snapshot: [`code/04-asteroids-ecs/`](code/04-asteroids-ecs/) — `main.odin`, `ecs.odin`, `game.odin`

```sh
odin run 09-game-architecture/code/04-asteroids-ecs
```

## Checkpoint

- Plays identically to 7.3: thrust, damping, wrap, splitting, waves of `wave + 3`, score by tier, 3 lives, blinking invulnerability
- Final death *despawns the ship entity* — it vanishes; the rocks keep drifting behind GAME OVER
- Open `main.odin`: the Playing branch is eight system calls in a fixed order. Then open 7.3's `main.odin` and compare what each tells you

## Exercises

1. **Easy:** Add the UFO: Position + Velocity + Radius + Lifetime, spawned every ~8 s crossing the screen, drawn as a squashed ellipse (`rl.DrawEllipse` — or a flat triangle). Count your lines; ~15 is the ECS dividend. Then extend `system_collide_ship` so it can kill you — hint: it tests `ROCK_MASK`, and a UFO isn't a rock. One clean option: a `Hazard` tag both carry.
2. **Medium:** Add a `Shield` component: the ship spawns with one; the first rock hit consumes the shield (remove the component) instead of a life, and grants brief invulnerability so the same rock doesn't instantly re-hit. Draw a ring while the bit is set.
3. **Medium:** Port 7.4's exhaust particles: while thrusting, spawn entities with Position + Velocity + Lifetime at the tail of the ship, short lifetimes, drawn as fading dots. Notice the lifetime system already despawns them — you wrote no cleanup code. (Want them to shimmer like 9.3's blinkers? Pulse was removed in the port — re-adding it *is* the exercise's hard mode: enum case, `pulses` column, `add_pulse`, and a `system_pulse`. Four pieces, by now familiar.)
4. **Hard:** Swap the component columns for a single `#soa` mega-store (one `#soa[MAX_ENTITIES]Component_Data` struct of all fields) and measure against the current plain arrays at a few thousand entities — 9.2's exercise playbook applies. Decide, with numbers, whether the layout change bought anything at this scale, and write your verdict in a comment.

**Next:** [10.1 Where to go next](../10-next-steps/01-where-to-go-next.md)
