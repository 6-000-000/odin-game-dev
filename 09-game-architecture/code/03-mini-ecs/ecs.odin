package main

import "core:math"
import rl "vendor:raylib"

// =============================================================================
// A mini Entity-Component-System in ~150 lines.
//
//   Entity    = a handle (index + generation), not a pointer.
//   Component = a column in the World + a bit in each entity's mask.
//   System    = a proc that sweeps the columns and acts on every entity whose
//               mask has the bits it needs.
// =============================================================================

MAX_ENTITIES :: 1024

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

// --- lifetime ---------------------------------------------------------------

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

// The currently-valid handle for slot i — used by systems that despawn by index.
handle_at :: proc(world: ^World, i: int) -> Entity {
	return {index = i, gen = world.generations[i]}
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

add_pulse :: proc(world: ^World, e: Entity, phase: f32) {
	world.pulses[e.index] = phase
	world.masks[e.index] += {.Pulse}
}

// --- systems: one sweep each, run every frame ---------------------------------
//
// IDIOM: `mask >= {.A, .B}` is a SUBSET test. bit_set comparison operators
// compare by set inclusion, so this reads "the entity has at least A and B".
// One idiom, used everywhere below — write it once, read it forever.

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
				// Route through despawn_entity so the generation bumps.
				despawn_entity(world, handle_at(world, i))
			}
		}
	}
}

// scale = 1 + 0.3·sin(time·6 + phase): a breathing value in [0.7, 1.3].
system_pulse :: proc(world: ^World, time: f32) {
	for i in 0 ..< world.count {
		if !world.alive[i] do continue
		if .Pulse in world.masks[i] {
			world.scales[i] = 1 + 0.3 * math.sin(time * 6 + world.pulses[i])
		}
	}
}

// Despawn everything (the C key in the playground).
clear_world :: proc(world: ^World) {
	for i in 0 ..< world.count {
		if world.alive[i] {
			despawn_entity(world, handle_at(world, i))
		}
	}
}
