package main

import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

// --- ship tuning ---
ROT_SPEED :: 220 // deg/s
THRUST :: 300 // px/s² gained while thrusting
DAMPING :: 0.8 // fraction of velocity bled off per second
INVULN_TIME :: 2 // seconds of safety after respawn

// --- bullets ---
BULLET_MAX :: 32
BULLET_SPEED :: 500
BULLET_LIFE :: 0.9 // seconds; range = speed × life
BULLET_RADIUS :: 2
FIRE_COOLDOWN :: 0.15 // seconds between shots

// --- asteroids ---
ASTEROID_MAX :: 64
ASTEROID_BIG :: 40
ASTEROID_MED :: 22
ASTEROID_SMALL :: 12
ASTEROID_SIDES :: 9

SHIP_CLEARANCE :: 150 // px; asteroids never spawn closer than this to the ship
START_LIVES :: 3

Ship :: struct {
	pos:      rl.Vector2,
	vel:      rl.Vector2,
	angle:    f32, // degrees; 0 points up the screen
	radius:   f32,
	cooldown: f32, // seconds until the next shot is allowed
	invuln:   f32, // seconds of post-respawn safety remaining
}

Bullet :: struct {
	pos:    rl.Vector2,
	vel:    rl.Vector2,
	life:   f32, // seconds remaining
	active: bool,
}

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
	bullets:   [BULLET_MAX]Bullet,
	score:     int,
	lives:     int,
	wave:      int,
}

// Zero the whole world, then set up a fresh run. world^ = World{} retires every pool slot at once.
start_game :: proc(world: ^World) {
	world^ = World{}
	world.ship = Ship{pos = {SCREEN_W / 2, SCREEN_H / 2}, radius = 16}
	world.lives = START_LIVES
	world.wave = 1
	spawn_wave(world, world.wave + 3)
}

// --- ship ---

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

update_ship :: proc(ship: ^Ship, dt: f32) {
	if rl.IsKeyDown(.LEFT) do ship.angle -= ROT_SPEED * dt
	if rl.IsKeyDown(.RIGHT) do ship.angle += ROT_SPEED * dt
	if rl.IsKeyDown(.UP) {
		ship.vel += ship_facing(ship.angle) * THRUST * dt
	}
	ship.vel *= 1 - DAMPING * dt
	ship.pos += ship.vel * dt
	wrap(&ship.pos, ship.radius)

	ship.cooldown = max(0, ship.cooldown - dt)
	ship.invuln = max(0, ship.invuln - dt)
}

respawn_ship :: proc(world: ^World) {
	ship := &world.ship
	ship.pos = {SCREEN_W / 2, SCREEN_H / 2}
	ship.vel = {}
	ship.angle = 0
	ship.invuln = INVULN_TIME
}

draw_ship :: proc(ship: Ship, thrusting: bool) {
	nose := ship_point(ship.pos, ship.angle, ship.radius)
	wing_l := ship_point(ship.pos, ship.angle + 140, ship.radius * 0.8)
	wing_r := ship_point(ship.pos, ship.angle - 140, ship.radius * 0.8)
	rl.DrawTriangleLines(nose, wing_l, wing_r, rl.WHITE)

	if thrusting {
		tip := ship_point(ship.pos, ship.angle + 180, rand.float32_range(ship.radius * 0.9, ship.radius * 1.7))
		base_l := ship_point(ship.pos, ship.angle + 160, ship.radius * 0.5)
		base_r := ship_point(ship.pos, ship.angle - 160, ship.radius * 0.5)
		rl.DrawTriangle(base_l, tip, base_r, rl.ORANGE)
	}
}

// --- wave spawning ---

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

// The free-slot search: the pool's allocator. Returns nil when the pool is full.
free_asteroid :: proc(world: ^World) -> ^Asteroid {
	for &a in world.asteroids {
		if !a.active do return &a
	}
	return nil
}

free_bullet :: proc(world: ^World) -> ^Bullet {
	for &b in world.bullets {
		if !b.active do return &b
	}
	return nil
}

// Fill n free pool slots with fresh big asteroids.
spawn_wave :: proc(world: ^World, n: int) {
	for _ in 0 ..< n {
		a := free_asteroid(world)
		if a == nil do return // pool full — spawn what we could (defensive)
		a^ = Asteroid {
			pos       = random_edge_pos(world.ship.pos),
			vel       = random_drift(30, 90),
			radius    = ASTEROID_BIG,
			rotation  = rand.float32_range(0, 360),
			rot_speed = rand.float32_range(-60, 60),
			active    = true,
		}
	}
}

// --- asteroids ---

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

asteroids_remaining :: proc(world: ^World) -> int {
	n := 0
	for a in world.asteroids {
		if a.active do n += 1
	}
	return n
}

asteroid_score :: proc(radius: f32) -> int {
	if radius == ASTEROID_BIG do return 20
	if radius == ASTEROID_MED do return 50
	return 100
}

// big -> 2 medium, medium -> 2 small, small -> gone. Children fly off in random directions.
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

// --- bullets ---

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

draw_bullets :: proc(world: ^World) {
	for b in world.bullets {
		if !b.active do continue
		rl.DrawCircleV(b.pos, BULLET_RADIUS, rl.WHITE)
	}
}

// --- collisions ---

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

collide_ship :: proc(world: ^World) {
	ship := &world.ship
	if ship.invuln > 0 do return // safe after respawn — no collision
	for &a in world.asteroids {
		if !a.active do continue
		if rl.CheckCollisionCircles(ship.pos, ship.radius * 0.7, a.pos, a.radius) {
			world.lives -= 1
			if world.lives > 0 do respawn_ship(world)
			return // one death per frame is plenty
		}
	}
}
