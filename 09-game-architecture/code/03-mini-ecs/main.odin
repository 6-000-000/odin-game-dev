package main

import "core:math/rand"
import rl "vendor:raylib"

SCREEN_W :: 1280
SCREEN_H :: 720

main :: proc() {
	rl.InitWindow(SCREEN_W, SCREEN_H, "Mini-ECS playground")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	world: World
	defer delete(world.free_list)
	time: f32

	// --- stale-handle demo state ---
	tracked: Entity
	has_tracked := false
	want_probe := false // K was pressed: probe after this frame's systems have run
	probed := false

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()
		time += dt
		mouse := rl.GetMousePosition()

		// --- input: spawning ---
		if rl.IsKeyPressed(.ONE) {
			for _ in 0 ..< 8 do spawn_comet(&world, mouse + random_vel(0, 40))
		}
		if rl.IsKeyPressed(.TWO) {
			for _ in 0 ..< 8 do spawn_blinker(&world, mouse + random_vel(0, 40))
		}
		if rl.IsKeyPressed(.THREE) {
			for _ in 0 ..< 8 do spawn_drifter(&world, mouse + random_vel(0, 40))
		}
		if rl.IsKeyPressed(.FOUR) {
			for _ in 0 ..< 8 do spawn_spinner(&world, mouse + random_vel(0, 40))
		}
		if rl.IsKeyPressed(.SPACE) {
			for _ in 0 ..< 100 {
				spawn_random(&world, {rand.float32_range(0, SCREEN_W), rand.float32_range(0, SCREEN_H)})
			}
		}
		if rl.IsKeyPressed(.C) do clear_world(&world)

		// --- the stale-handle demo ---
		if rl.IsKeyPressed(.T) {
			tracked = spawn_comet(&world, mouse)
			has_tracked = true
			probed = false
		}
		if rl.IsKeyPressed(.K) && has_tracked && is_alive(&world, tracked) {
			// Kill it THROUGH the lifetime system: every death route ends in
			// despawn_entity, which is what bumps the generation.
			add_lifetime(&world, tracked, 0)
			want_probe = true
		}

		// --- systems, every frame, in a fixed order ---
		system_move(&world, dt)
		system_spin(&world, dt)
		system_lifetime(&world, dt)
		system_pulse(&world, time)

		// The lifetime system has now retired the tracked comet. Spawn a
		// replacement (likely reusing the just-freed slot) and let the HUD
		// show the old handle failing is_alive.
		if want_probe {
			want_probe = false
			probed = true
			spawn_comet(&world, {SCREEN_W / 2, 120})
		}

		// --- draw ---
		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)
		draw_entities(&world)
		draw_hud(&world, tracked, has_tracked, probed)
		rl.EndDrawing()
	}
}
