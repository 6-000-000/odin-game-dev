package main

import rl "vendor:raylib"

// =============================================================================
// The 9.3 mini-ECS, EXTENDED for Asteroids. The machinery (spawn / despawn /
// is_alive / handle_at / the systems sweep) is byte-for-byte the same idea —
// what changed is the schema: new enum cases, new columns, new adders.
// Growing the framework IS the point of ECS.
// =============================================================================

MAX_ENTITIES :: 1024

// A handle: index + generation. See 9.3 — the generation makes stale handles
// detectable after a slot is recycled.
Entity :: struct {
	index: int,
	gen:   u32,
}

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

World :: struct {
	// --- component columns: slot i holds the data for entity index i ---
	positions:     [MAX_ENTITIES]rl.Vector2,
	velocities:    [MAX_ENTITIES]rl.Vector2,
	angles:        [MAX_ENTITIES]f32, // Spin: tumble angle, degrees
	spins:         [MAX_ENTITIES]f32, // Spin: tumble speed, deg/s
	lifetimes:     [MAX_ENTITIES]f32,
	facings:       [MAX_ENTITIES]f32, // Angle: heading, degrees; 0 = up the screen
	radii:         [MAX_ENTITIES]f32,
	tiers:         [MAX_ENTITIES]Rock_Tier,
	invuln_timers: [MAX_ENTITIES]f32,
	// PlayerControlled: tag only — no column.

	// --- bookkeeping ---
	masks:       [MAX_ENTITIES]bit_set[Component],
	alive:       [MAX_ENTITIES]bool,
	generations: [MAX_ENTITIES]u32,
	free_list:   [dynamic]int,
	count:       int, // high-water mark

	// --- singleton state ---
	// Score, lives, wave, the ship handle: exactly ONE of these exists, so it
	// stays a plain struct (defined in game.odin). NOT everything is an entity.
	game: Game,
}

// --- lifetime ---------------------------------------------------------------

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
	world.masks[idx] = nil
	return {index = idx, gen = world.generations[idx]}
}

// Every death route ends here — the generation bump is what retires stale handles.
despawn_entity :: proc(world: ^World, e: Entity) {
	if !is_alive(world, e) do return
	world.alive[e.index] = false
	world.generations[e.index] += 1
	append(&world.free_list, e.index)
}

is_alive :: proc(world: ^World, e: Entity) -> bool {
	return(
		e.index >= 0 &&
		e.index < world.count &&
		world.alive[e.index] &&
		world.generations[e.index] == e.gen
	)
}

// The currently-valid handle for slot i — used by systems that despawn by index.
handle_at :: proc(world: ^World, i: int) -> Entity {
	return {index = i, gen = world.generations[i]}
}

// Zero everything but keep the free list's allocation across restarts.
reset_world :: proc(world: ^World) {
	free := world.free_list
	clear(&free)
	world^ = World{}
	world.free_list = free
}

// --- components: one adder each ----------------------------------------------
// Setting a component = writing its column + setting its bit in the mask.

add_position :: proc(world: ^World, e: Entity, pos: rl.Vector2) {
	world.positions[e.index] = pos
	world.masks[e.index] += {.Position}
}

add_velocity :: proc(world: ^World, e: Entity, vel: rl.Vector2) {
	world.velocities[e.index] = vel
	world.masks[e.index] += {.Velocity}
}

add_spin :: proc(world: ^World, e: Entity, angle, spin: f32) {
	world.angles[e.index] = angle
	world.spins[e.index] = spin
	world.masks[e.index] += {.Spin}
}

add_lifetime :: proc(world: ^World, e: Entity, seconds: f32) {
	world.lifetimes[e.index] = seconds
	world.masks[e.index] += {.Lifetime}
}

add_angle :: proc(world: ^World, e: Entity, degrees: f32) {
	world.facings[e.index] = degrees
	world.masks[e.index] += {.Angle}
}

add_radius :: proc(world: ^World, e: Entity, radius: f32) {
	world.radii[e.index] = radius
	world.masks[e.index] += {.Radius}
}

add_tier :: proc(world: ^World, e: Entity, tier: Rock_Tier) {
	world.tiers[e.index] = tier
	world.masks[e.index] += {.Tier}
}

add_invuln :: proc(world: ^World, e: Entity, seconds: f32) {
	world.invuln_timers[e.index] = seconds
	world.masks[e.index] += {.Invuln}
}

// Tags have no data, so a tag adder is just the bit.
add_tag :: proc(world: ^World, e: Entity, tag: Component) {
	world.masks[e.index] += {tag}
}

// --- generic systems -----------------------------------------------------------
// IDIOM (from 9.3): `mask >= {.A, .B}` is a subset test — "has at least A and B".
// These systems know nothing about Asteroids; the game-specific ones live in
// game.odin.

system_move :: proc(world: ^World, dt: f32) {
	for i in 0 ..< world.count {
		if !world.alive[i] do continue
		if world.masks[i] >= {.Position, .Velocity} {
			world.positions[i] += world.velocities[i] * dt
		}
	}
}

system_spin :: proc(world: ^World, dt: f32) {
	for i in 0 ..< world.count {
		if !world.alive[i] do continue
		if .Spin in world.masks[i] {
			world.angles[i] += world.spins[i] * dt
		}
	}
}

system_lifetime :: proc(world: ^World, dt: f32) {
	for i in 0 ..< world.count {
		if !world.alive[i] do continue
		if .Lifetime in world.masks[i] {
			world.lifetimes[i] -= dt
			if world.lifetimes[i] <= 0 {
				despawn_entity(world, handle_at(world, i))
			}
		}
	}
}
