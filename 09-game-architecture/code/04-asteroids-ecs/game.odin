package main

import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

// =============================================================================
// Asteroids on the mini-ECS: the game-specific half. Constants, the singleton
// Game struct, spawn recipes, and the systems that know the rules.
// =============================================================================

// --- game feel: every tuning number lives here (same values as 7.3) ---
SCREEN_W :: 900
SCREEN_H :: 600

// --- ship tuning ---
ROT_SPEED   :: 220 // deg/s
THRUST      :: 300 // px/s² gained while thrusting
DAMPING     :: 0.8 // fraction of velocity bled off per second
INVULN_TIME :: 2   // seconds of safety after respawn
SHIP_RADIUS :: 16

// --- bullets ---
BULLET_SPEED  :: 500
BULLET_LIFE   :: 0.9 // seconds; range = speed × life
BULLET_RADIUS :: 2
FIRE_COOLDOWN :: 0.15 // seconds between shots

// --- asteroids ---
ASTEROID_SIDES :: 9
SHIP_CLEARANCE :: 150 // px; asteroids never spawn closer than this to the ship
START_LIVES    :: 3

Rock_Tier :: enum {
	Big,
	Medium,
	Small,
}

// Tier drives radius and score — indexed BY THE ENUM, no switch required.
// (Package-level variables, not constants: a constant array can't be indexed
// with a runtime value.)
TIER_RADIUS := [Rock_Tier]f32{.Big = 40, .Medium = 22, .Small = 12}
TIER_SCORE  := [Rock_Tier]int{.Big = 20, .Medium = 50, .Small = 100}

// The masks that mean "is a bullet" / "is a rock" in the sweeps below.
BULLET_MASK :: bit_set[Component]{.Position, .Velocity, .Lifetime}
ROCK_MASK   :: bit_set[Component]{.Position, .Radius, .Tier}

// Singleton state. One score, one lives counter, one ship — so this stays a
// plain struct inside the World, NOT an entity. The ship is kept by handle.
Game :: struct {
	score:    int,
	lives:    int,
	wave:     int,
	cooldown: f32, // seconds until the next shot is allowed
	ship:     Entity,
}

start_game :: proc(world: ^World) {
	reset_world(world)
	world.game = Game{lives = START_LIVES, wave = 1}
	world.game.ship = spawn_ship(world)
	spawn_wave(world, world.game.wave + 3)
}

// --- spawn recipes: kinds are compositions, not types ---------------------------

spawn_ship :: proc(world: ^World) -> Entity {
	e := spawn_entity(world)
	add_position(world, e, {SCREEN_W / 2, SCREEN_H / 2})
	add_velocity(world, e, {})
	add_angle(world, e, 0)
	add_radius(world, e, SHIP_RADIUS)
	add_tag(world, e, .PlayerControlled)
	return e
}

spawn_rock :: proc(world: ^World, pos: rl.Vector2, tier: Rock_Tier, min_speed, max_speed: f32) -> Entity {
	e := spawn_entity(world)
	if !is_alive(world, e) do return e // pool full: drop the spawn (defensive)
	add_position(world, e, pos)
	add_velocity(world, e, random_drift(min_speed, max_speed))
	add_radius(world, e, TIER_RADIUS[tier])
	add_tier(world, e, tier)
	add_spin(world, e, rand.float32_range(0, 360), rand.float32_range(-90, 90))
	return e
}

spawn_bullet :: proc(world: ^World, pos, vel: rl.Vector2) -> Entity {
	e := spawn_entity(world)
	if !is_alive(world, e) do return e
	add_position(world, e, pos)
	add_velocity(world, e, vel)
	add_lifetime(world, e, BULLET_LIFE)
	return e
}

spawn_wave :: proc(world: ^World, n: int) {
	ship_pos := world.positions[world.game.ship.index]
	for _ in 0 ..< n {
		spawn_rock(world, random_edge_pos(ship_pos), .Big, 30, 90)
	}
}

// big -> 2 medium, medium -> 2 small, small -> gone. Children fly off randomly.
split_rock :: proc(world: ^World, i: int) {
	pos := world.positions[i]
	tier := world.tiers[i]
	despawn_entity(world, handle_at(world, i))
	switch tier {
	case .Big:
		spawn_rock(world, pos, .Medium, 60, 120)
		spawn_rock(world, pos, .Medium, 60, 120)
	case .Medium:
		spawn_rock(world, pos, .Small, 60, 120)
		spawn_rock(world, pos, .Small, 60, 120)
	case .Small:
	}
}

// --- game systems: these know the rules -----------------------------------------

// Input acts on ANY entity with the PlayerControlled tag (today: one ship).
// One ship = one cooldown, so the cooldown stays in the Game struct.
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

// Screen wrap for everything with a Position. Entities without a Radius
// (bullets) wrap on BULLET_RADIUS.
system_wrap :: proc(world: ^World) {
	for i in 0 ..< world.count {
		if !world.alive[i] do continue
		if .Position not_in world.masks[i] do continue
		radius := f32(BULLET_RADIUS)
		if .Radius in world.masks[i] do radius = world.radii[i]
		wrap(&world.positions[i], radius)
	}
}

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

// bullets × rocks. O(n²) with mask-test early-outs — fine at this scale
// (module 8 is where this pattern breaks and 8.3 shows the fix).
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

// ship × rocks, gated by the Invuln component.
system_collide_ship :: proc(world: ^World) {
	game := &world.game
	if !is_alive(world, game.ship) do return
	i := game.ship.index
	if .Invuln in world.masks[i] do return // safe after respawn — no collision
	for r in 0 ..< world.count {
		if !world.alive[r] do continue
		if !(world.masks[r] >= ROCK_MASK) do continue
		if rl.CheckCollisionCircles(world.positions[i], world.radii[i] * 0.7, world.positions[r], world.radii[r]) {
			game.lives -= 1
			if game.lives > 0 {
				respawn_ship(world, game.ship)
			} else {
				despawn_entity(world, game.ship) // the ship is GONE
			}
			return // one death per frame is plenty
		}
	}
}

respawn_ship :: proc(world: ^World, ship: Entity) {
	i := ship.index
	world.positions[i] = {SCREEN_W / 2, SCREEN_H / 2}
	world.velocities[i] = {}
	world.facings[i] = 0
	add_invuln(world, ship, INVULN_TIME)
}

rocks_remaining :: proc(world: ^World) -> int {
	n := 0
	for i in 0 ..< world.count {
		if world.alive[i] && .Tier in world.masks[i] do n += 1
	}
	return n
}

// --- drawing ----------------------------------------------------------------------

draw_world :: proc(world: ^World) {
	for i in 0 ..< world.count {
		if !world.alive[i] do continue
		m := world.masks[i]
		switch {
		case m >= ROCK_MASK:
			rl.DrawPolyLines(world.positions[i], ASTEROID_SIDES, world.radii[i], world.angles[i], rl.LIGHTGRAY)
		case m >= BULLET_MASK:
			rl.DrawCircleV(world.positions[i], BULLET_RADIUS, rl.WHITE)
		case .PlayerControlled in m:
			draw_ship(world, i)
		}
	}
}

draw_ship :: proc(world: ^World, i: int) {
	pos := world.positions[i]
	angle := world.facings[i]
	radius := world.radii[i]
	color := rl.WHITE
	if .Invuln in world.masks[i] {
		// blink while safe: dim half of each 0.2 s cycle
		if int(world.invuln_timers[i] * 10) % 2 == 0 do color = rl.Fade(rl.WHITE, 0.25)
	}
	nose := ship_point(pos, angle, radius)
	wing_l := ship_point(pos, angle + 140, radius * 0.8)
	wing_r := ship_point(pos, angle - 140, radius * 0.8)
	rl.DrawTriangleLines(nose, wing_l, wing_r, color)

	if rl.IsKeyDown(.UP) {
		tip := ship_point(pos, angle + 180, rand.float32_range(radius * 0.9, radius * 1.7))
		base_l := ship_point(pos, angle + 160, radius * 0.5)
		base_r := ship_point(pos, angle - 160, radius * 0.5)
		rl.DrawTriangle(base_l, tip, base_r, rl.ORANGE)
	}
}

// --- helpers (same math as 7.3) -----------------------------------------------------

ship_facing :: proc(angle: f32) -> rl.Vector2 {
	rad := (angle - 90) * rl.DEG2RAD
	return {math.cos(rad), math.sin(rad)}
}

ship_point :: proc(pos: rl.Vector2, deg, dist: f32) -> rl.Vector2 {
	rad := (deg - 90) * rl.DEG2RAD
	return pos + {math.cos(rad), math.sin(rad)} * dist
}

wrap :: proc(pos: ^rl.Vector2, radius: f32) {
	if pos.x < -radius do pos.x += SCREEN_W + radius * 2
	if pos.x > SCREEN_W + radius do pos.x -= SCREEN_W + radius * 2
	if pos.y < -radius do pos.y += SCREEN_H + radius * 2
	if pos.y > SCREEN_H + radius do pos.y -= SCREEN_H + radius * 2
}

// A random spot in an 80 px band along the edges, far from the ship.
random_edge_pos :: proc(ship_pos: rl.Vector2) -> rl.Vector2 {
	for _ in 0 ..< 32 {
		pos := rl.Vector2{rand.float32_range(0, SCREEN_W), rand.float32_range(0, SCREEN_H)}
		near_edge := min(min(pos.x, SCREEN_W - pos.x), min(pos.y, SCREEN_H - pos.y)) < 80
		if near_edge && rl.Vector2Distance(pos, ship_pos) >= SHIP_CLEARANCE {
			return pos
		}
	}
	return {0, 0} // gave up; a corner is far enough
}

random_drift :: proc(min_speed, max_speed: f32) -> rl.Vector2 {
	angle := rand.float32_range(0, 2 * math.PI)
	speed := rand.float32_range(min_speed, max_speed)
	return {math.cos(angle), math.sin(angle)} * speed
}
