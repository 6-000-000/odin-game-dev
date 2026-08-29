# 9.3 Components and systems

**Module:** 09-game-architecture

## Goals

- Build a mini-ECS in ~150 lines: entities as handles, components as columns, systems as sweeps
- Keep 9.1's promise: generation counters make references into a pool *safe*
- Compose entity "kinds" out of component mixes — no types, no inheritance
- Settle on one `bit_set` idiom for multi-component tests and use it everywhere

## New concepts

| Concept | What it is |
|---|---|
| Entity (handle) | `{index, gen}` — a ticket into the world's arrays, not a pointer |
| Component | One column in the World + one bit in each entity's mask |
| `bit_set[Enum]` | Odin's built-in set type: `in` tests membership, `+=` adds bits, `>=` is a subset test |
| Generation counter | Per-slot counter bumped on despawn; makes stale handles detectable |
| System | A proc that sweeps the columns every frame, acting on entities whose mask matches |
| Composition over inheritance | Entity kinds are component *mixes*, not entries in a type hierarchy |

## Walkthrough

### The idea: rows, columns, and queries

9.2 asked how one array of entities should be *shaped in memory*. This lesson asks the organization question from 9.1: what happens when entity *kinds* multiply past what pools handle gracefully? Asteroids had three kinds (ship, rocks, bullets) and needed a struct + a pool + update/draw/collide procs *per kind*. A game with forty kinds can't afford forty of everything.

The ECS answer: stop giving kinds their own types. Instead, every entity is just an integer-sized **handle**, every property lives in a **column** (one array per property, indexed by the handle), and a per-entity **mask** records which columns that entity actually uses:

```odin
// A handle to an entity. Copying it is cheap and safe: if the entity dies and
// its slot is recycled, the copy goes STALE instead of corrupting the new
// occupant — because the generations no longer match (see is_alive). This is
// the fix for 7.2's pooled-pointer hazard, promised back in 9.1.
Entity :: struct {
	index: int,
	gen:   u32,
}

// The schema: one case per component. Growing the framework = adding a case
// here, one column to World, and one add_* proc. Nothing else changes.
Component :: enum {
	Position,
	Velocity,
	Spin,
	Lifetime,
	Pulse,
}
```

The World is the columns plus bookkeeping — 9.2's SoA, but sparse: most entities use only a few columns, and `masks[i]` says which:

```odin
World :: struct {
	// --- component columns: slot i holds the data for entity index i ---
	positions:   [MAX_ENTITIES]rl.Vector2,
	velocities:  [MAX_ENTITIES]rl.Vector2,
	angles:      [MAX_ENTITIES]f32, // Spin: current angle, degrees
	spins:       [MAX_ENTITIES]f32, // Spin: angular velocity, deg/s
	lifetimes:   [MAX_ENTITIES]f32, // Lifetime: seconds remaining
	pulses:      [MAX_ENTITIES]f32, // Pulse: phase offset for the wave
	scales:      [MAX_ENTITIES]f32, // NOT a component: scratch data the pulse
	//                                 system writes and the draw code reads

	// --- bookkeeping ---
	masks:       [MAX_ENTITIES]bit_set[Component], // which components slot i has
	alive:       [MAX_ENTITIES]bool,
	generations: [MAX_ENTITIES]u32, // bumped on every despawn
	free_list:   [dynamic]int, // recycled slot indices
	count:       int, // high-water mark: slots [0, count) may be in use
}
```

Note `Spin` owns *two* columns (`angles` and `spins`): a component is a semantic role — "has an angle that rotates" — not a single field. And `scales` has no mask bit at all: it's scratch space a system writes and the draw code reads, not something entities *have*.

> **🌐 Web dev callout — an ECS is an in-memory relational database**
> You've seen this architecture, just with different names. Entities are **row ids**. Component arrays are **table columns** — `positions` is `TABLE position (entity_id, x, y)`. The mask is the **schema per row** (ECS rows are schemaless-per-entity, like a document store with a field index). And a system is a **query** that runs every frame: `system_move` is literally `SELECT i WHERE mask HAS (Position, Velocity) UPDATE positions …`. If you've used LINQ or an ORM, `world.masks[i] >= {.Position, .Velocity}` is the `WHERE` clause. The honest differences: a real DB builds indexes to *avoid* scanning; our mini-ECS just scans all 1024 rows per query per frame — cheap at this scale, and when it stops being cheap, the fix is 8.3's spatial hash or 9.2's layout, not a fancier ECS.

### Spawn, despawn, and the generation trick

Here is where 9.1's promise gets kept. 7.2's pool had a hazard: hold a pointer to a pooled entity, the entity dies, the slot gets recycled — and your pointer now silently *corrupts a different entity*. The fix is to never hand out pointers. Hand out a ticket, and stamp the slot:

```odin
// Take a slot: recycle from the free list when possible, else bump the
// high-water mark. Returns an invalid handle (index -1) when full.
spawn_entity :: proc(world: ^World) -> Entity {
	idx: int
	if len(world.free_list) > 0 {
		idx = pop(&world.free_list)
	} else if world.count < MAX_ENTITIES {
		idx = world.count
		world.count += 1
	} else {
		return {index = -1} // pool exhausted — callers check is_alive
	}
	world.alive[idx] = true
	world.masks[idx] = nil // fresh slot: no components yet
	return {index = idx, gen = world.generations[idx]}
}

// Retire a slot. The generation bump is the whole safety story: any handle
// still holding the old gen fails is_alive from here on, even after the slot
// is reused. EVERY death route must end here — the lifetime system included.
despawn_entity :: proc(world: ^World, e: Entity) {
	if !is_alive(world, e) do return
	world.alive[e.index] = false
	world.generations[e.index] += 1
	append(&world.free_list, e.index)
}

// A handle is valid only if its slot is in range, alive, and the generation
// still matches — i.e. the slot hasn't been recycled since the handle was made.
is_alive :: proc(world: ^World, e: Entity) -> bool {
	return(
		e.index >= 0 &&
		e.index < world.count &&
		world.alive[e.index] &&
		world.generations[e.index] == e.gen
	)
}
```

Walk the scenario: a bullet despawns, `generations[7]` goes 0→1, slot 7 lands on the free list. A comet spawns, pops slot 7, and gets handle `{7, 1}`. Some system still holds the bullet's old `{7, 0}` — `is_alive` compares 0 against the slot's current 1 and *rejects it*. The stale handle fails loudly (returns `false`) instead of silently moving the comet. That's the entire trick: **recycling is safe because the ticket expires.**

### Components: a column write plus a bit

Every component gets one adder, and they all have the same shape:

```odin
add_position :: proc(world: ^World, e: Entity, pos: rl.Vector2) {
	world.positions[e.index] = pos
	world.masks[e.index] += {.Position}
}
```

`world.masks[e.index] += {.Position}` sets the bit — `bit_set` literal syntax is `{.A, .B}`, membership is `.A in mask`, and removal (9.4 uses it) is `mask -= {.A}`.

For multi-component tests, pick one idiom and never deviate. Ours, with the comment that lives in the snapshot:

```odin
// IDIOM: `mask >= {.A, .B}` is a SUBSET test. bit_set comparison operators
// compare by set inclusion, so this reads "the entity has at least A and B".
// One idiom, used everywhere below — write it once, read it forever.
```

(If `>=` ever reads strangely, the equivalent `(mask & {.A, .B}) == {.A, .B}` is the portable fallback — but the superset operator compiles and is shorter.)

### Systems: queries that run every frame

A system is a proc that sweeps the high-water range and acts on mask matches. That's the whole pattern:

```odin
system_move :: proc(world: ^World, dt: f32) {
	for i in 0 ..< world.count {
		if !world.alive[i] do continue
		if world.masks[i] >= {.Position, .Velocity} {
			world.positions[i] += world.velocities[i] * dt
		}
	}
}
```

And here is where the generation safety *pays rent* — the lifetime system despawns by index, routing through `despawn_entity` like every other death:

```odin
system_lifetime :: proc(world: ^World, dt: f32) {
	for i in 0 ..< world.count {
		if !world.alive[i] do continue
		if .Lifetime in world.masks[i] {
			world.lifetimes[i] -= dt
			if world.lifetimes[i] <= 0 {
				// Route through despawn_entity so the generation bumps.
				despawn_entity(world, handle_at(world, i))
			}
		}
	}
}
```

`handle_at(world, i)` builds the *currently valid* handle for slot `i` — systems hold indices, so this is how they despawn. The remaining systems are the same shape: `system_spin` advances `angles` by `spins`, and `system_pulse` writes `scales[i] = 1 + 0.3 * math.sin(time * 6 + world.pulses[i])` — a breathing value in [0.7, 1.3].

### The playground: kinds are mixes

Now the payoff. Four "kinds" of entity, and not one type declaration among them — each recipe is just a combination of columns:

```odin
// Comet: drifts and tumbles forever.  Position + Velocity + Spin
spawn_comet :: proc(world: ^World, pos: rl.Vector2) -> Entity {
	e := spawn_entity(world)
	if !is_alive(world, e) do return e // pool full
	add_position(world, e, pos)
	add_velocity(world, e, random_vel(40, 140))
	add_spin(world, e, rand.float32_range(0, 360), rand.float32_range(-180, 180))
	return e
}
```

Blinkers are Position+Pulse+Lifetime, drifters are Position+Velocity+Lifetime, spinners are Position+Spin. SPACE spawns 100 entities with every component rolled independently — and every system picks off exactly the entities carrying its bits, no matter how strange the mix. **A new kind is a new combination of existing columns.** If you've ever mix-and-matched React hooks or middleware, you know the feeling: behavior assembled from orthogonal pieces.

Drawing is also mask-driven — the first combo an entity's mask satisfies decides its shape (comets = rotated triangles, blinkers = breathing circles, drifters = squares, spinners = rotating plus signs). The systems never see this; a random mix drawn as a blinker still *moves* if it has Velocity, because `system_move` only reads the mask.

The playground also makes the generation lesson concrete. T stores a comet's handle; K kills it *through the lifetime system* (a zero-second Lifetime), the frame's systems retire it, and a replacement comet spawns into the freed slot:

```odin
if rl.IsKeyPressed(.K) && has_tracked && is_alive(&world, tracked) {
	// Kill it THROUGH the lifetime system: every death route ends in
	// despawn_entity, which is what bumps the generation.
	add_lifetime(&world, tracked, 0)
	want_probe = true
}
```

The HUD then shows the stored handle — `{index 7, gen 0}` — failing `is_alive` in red, with the slot's new generation alongside it. Stale ticket, rejected at the door.

## Full listing

Runnable snapshot: [`code/03-mini-ecs/`](code/03-mini-ecs/) — `main.odin`, `ecs.odin`, `playground.odin`

```sh
odin run 09-game-architecture/code/03-mini-ecs
```

## Checkpoint

- Keys 1–4 spawn bursts at the mouse; each kind behaves per its components (comets tumble, blinkers pulse and die, drifters drift and die, spinners spin in place)
- SPACE's random mixes behave *per bit*: an entity with Velocity+Lifetime moves and dies regardless of how it's drawn
- The HUD reacts to C: `alive` drops to 0, `free list` jumps, `slots used` stays put (it's the high-water mark)
- T then K: the tracked handle flips from green `is_alive: true` to red `is_alive: false`, and the slot shows its bumped generation

## Exercises

1. **Easy:** Add a `Gravity` component: enum case, `gravities: [MAX_ENTITIES]f32` column, `add_gravity`, and `system_gravity` (`velocities[i].y += g * dt` for entities with `{.Velocity, .Gravity}`). Give it to any spawn recipe — gravity comets raining from the top of the screen are a good time. Notice what you *didn't* touch: every existing system.
2. **Medium:** Prove both allocation paths in `spawn_entity`. Spam SPACE until `slots used` (high-water) is a few hundred, press C, then spawn more. Explain — in a comment — why `slots used` doesn't shrink, why the free list feeds new spawns first, and why a recycled slot's generation is 1 while a never-used slot's is 0. (Print `generations` of a fresh spawn and a recycled one via the HUD if you're not sure.)
3. **Medium:** Add a `Homing` component and `system_homing`: each frame, entities with `{.Position, .Velocity, .Homing}` steer their velocity toward the mouse (`rl.Vector2Normalize(mouse - pos) * speed`, or lerp toward it for lazier tracking). Homing drifters become heat-seeking squares; homing spinners become turrets that refuse to aim. No new entity *types* were harmed.
4. **Hard:** Implement `query :: proc(world: ^World, required: bit_set[Component], out: ^[dynamic]int)` — clear `out`, fill it with every alive index whose mask passes, and rewrite all four systems to iterate `out` instead of scanning. Keep one scratch array in `main` and reuse it (no per-frame allocation). Then decide honestly: is `system_move` more readable this way, or did you just add a layer?

**Next:** [9.4 Rebuilding Asteroids on the mini-ECS](04-asteroids-as-ecs.md)
