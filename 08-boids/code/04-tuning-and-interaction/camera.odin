package main

import rl "vendor:raylib"

// The world (2560x1440) is 4x the window (1280x720), so we need a camera.
// rl.Camera2D is just {offset, target, zoom}: target = the world point the
// camera looks at, offset = where that point lands on screen, zoom = scale.
ZOOM_MIN :: 0.3
ZOOM_MAX :: 3.0
ZOOM_STEP :: 0.1

camera_init :: proc() -> rl.Camera2D {
	return {
		offset = {SCREEN_W / 2, SCREEN_H / 2}, // screen center...
		target = {WORLD_W / 2, WORLD_H / 2}, // ...shows world center
		rotation = 0,
		zoom = 0.6, // start zoomed out: most of the world visible
	}
}

camera_update :: proc(cam: ^rl.Camera2D) {
	// Right-drag pans: grab the world and drag it, so the camera target moves
	// opposite the mouse — divided by zoom (screen px → world px).
	if rl.IsMouseButtonDown(.RIGHT) {
		cam.target += rl.GetMouseDelta() * (-1 / cam.zoom)
	}
	// Wheel zooms TOWARD the cursor: keep the world point under the mouse
	// fixed by correcting the target after changing zoom.
	wheel := rl.GetMouseWheelMove()
	if wheel != 0 {
		mouse := rl.GetMousePosition()
		world_before := rl.GetScreenToWorld2D(mouse, cam^)
		cam.zoom = clamp(cam.zoom * (1 + wheel * ZOOM_STEP), ZOOM_MIN, ZOOM_MAX)
		world_after := rl.GetScreenToWorld2D(mouse, cam^)
		cam.target += world_before - world_after
	}
}
