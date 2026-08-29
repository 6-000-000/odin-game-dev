package main

import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

SCREEN_W :: 900
SCREEN_H :: 600

ROT_SPEED :: 220 // degrees per second
THRUST :: 300 // px/s² added while thrusting
DAMPING :: 0.8 // fraction of velocity bled off per second

Ship :: struct {
	pos:    rl.Vector2,
	vel:    rl.Vector2,
	angle:  f32, // degrees; 0 points UP the screen
	radius: f32,
}

// The ship's nose direction as a unit vector.
// angle 0 must mean "up the screen", but screen y points DOWN (lesson 2.2),
// so the usual {cos, sin} circle is rotated by -90°.
ship_facing :: proc(angle: f32) -> rl.Vector2 {
	rad := (angle - 90) * rl.DEG2RAD
	return {math.cos(rad), math.sin(rad)}
}

// A point on the ship's body: `deg` degrees around, `dist` px out from center.
ship_point :: proc(pos: rl.Vector2, deg, dist: f32) -> rl.Vector2 {
	rad := (deg - 90) * rl.DEG2RAD
	return pos + {math.cos(rad), math.sin(rad)} * dist
}

// Teleport to the opposite side once fully past an edge.
wrap :: proc(pos: ^rl.Vector2, radius: f32) {
	if pos.x < -radius do pos.x += SCREEN_W + radius * 2
	if pos.x > SCREEN_W + radius do pos.x -= SCREEN_W + radius * 2
	if pos.y < -radius do pos.y += SCREEN_H + radius * 2
	if pos.y > SCREEN_H + radius do pos.y -= SCREEN_H + radius * 2
}

draw_ship :: proc(ship: Ship, thrusting: bool) {
	nose := ship_point(ship.pos, ship.angle, ship.radius)
	wing_l := ship_point(ship.pos, ship.angle + 140, ship.radius * 0.8)
	wing_r := ship_point(ship.pos, ship.angle - 140, ship.radius * 0.8)
	rl.DrawTriangleLines(nose, wing_l, wing_r, rl.WHITE)

	if thrusting {
		// the flame flickers: a new random length every frame
		tip := ship_point(ship.pos, ship.angle + 180, rand.float32_range(ship.radius * 0.9, ship.radius * 1.7))
		base_l := ship_point(ship.pos, ship.angle + 160, ship.radius * 0.5)
		base_r := ship_point(ship.pos, ship.angle - 160, ship.radius * 0.5)
		rl.DrawTriangle(base_l, tip, base_r, rl.ORANGE)
	}
}

main :: proc() {
	rl.InitWindow(SCREEN_W, SCREEN_H, "Asteroids — ship and thrust")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	ship := Ship{pos = {SCREEN_W / 2, SCREEN_H / 2}, radius = 16}

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()

		if rl.IsKeyDown(.LEFT) do ship.angle -= ROT_SPEED * dt
		if rl.IsKeyDown(.RIGHT) do ship.angle += ROT_SPEED * dt

		thrusting := rl.IsKeyDown(.UP)
		if thrusting {
			ship.vel += ship_facing(ship.angle) * THRUST * dt
		}

		ship.vel *= 1 - DAMPING * dt // inertia: speed bleeds off slowly
		ship.pos += ship.vel * dt
		wrap(&ship.pos, ship.radius)

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)
		draw_ship(ship, thrusting)
		rl.DrawText("LEFT/RIGHT rotate — UP thrusts", 10, 10, 20, rl.GRAY)
		rl.EndDrawing()
	}
}
