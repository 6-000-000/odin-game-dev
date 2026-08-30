# 8.4 Tuning, camera, and a predator

**Module:** 08-boids

## Goals

- Fly a `rl.Camera2D` over a world 4× bigger than the window: right-drag pan, wheel zoom *toward the cursor*
- Tune the flock live with raygui sliders — the payoff for the `Settings` struct from lesson 8.1
- Add interaction the video has: a mouse **scare point** and a wandering **predator** the flock flees
- Color boids by speed, like the video's sim
- Draw world-space things inside `BeginMode2D` and UI outside it

## New concepts

| Concept | What it is |
|---|---|
| `rl.Camera2D` | `{offset, target, rotation, zoom}` — `target` is the world point shown at screen position `offset`, scaled by `zoom` |
| `rl.GetScreenToWorld2D` | Screen px → world px under a camera. The zoom-toward-cursor trick uses it twice |
| `BeginMode2D` / `EndMode2D` | Everything between them is transformed by the camera; everything after is plain screen space |
| raygui | Immediate-mode UI inside `vendor:raylib`: `GuiSlider(rect, label, value_text, &value, min, max)` — no layout, no widgets tree |
| Hazard | Our abstraction for "a place boids flee from": `{pos, radius, strength}` — scare point and predator share the flee math |

## Walkthrough

The window stays 1280×720, but the world is now **2560×1440** — you can't see it all at once. That's the excuse to build the two things every real sim needs: a camera, and a tuning UI.

### `camera.odin`: pan and zoom-toward-cursor

```odin
camera_update :: proc(cam: ^rl.Camera2D) {
	// right-drag pans: drag the world, so the target moves opposite the mouse
	if rl.IsMouseButtonDown(.RIGHT) {
		cam.target += rl.GetMouseDelta() * (-1 / cam.zoom)
	}
	// wheel zooms TOWARD the cursor
	wheel := rl.GetMouseWheelMove()
	if wheel != 0 {
		mouse := rl.GetMousePosition()
		world_before := rl.GetScreenToWorld2D(mouse, cam^)
		cam.zoom = clamp(cam.zoom * (1 + wheel * ZOOM_STEP), ZOOM_MIN, ZOOM_MAX)
		world_after := rl.GetScreenToWorld2D(mouse, cam^)
		cam.target += world_before - world_after
	}
}
```

Pan is intuitive: divide the mouse delta by `zoom` because a screen pixel is `1/zoom` world pixels. Zoom-to-cursor is the classic two-sample trick: the world point under the mouse *before* the zoom must equal the world point under the mouse *after* it; the difference of the two is exactly how much to nudge `target`. Without that correction, zooming orbits the view around the offset — try deleting the `target +=` line and feel the difference.

The zoom clamps used above are `ZOOM_MIN :: 0.3`, `ZOOM_MAX :: 3.0`, `ZOOM_STEP :: 0.1`, and the camera starts centered on the world, zoomed out so most of it is visible:

```odin
camera_init :: proc() -> rl.Camera2D {
	return {
		offset = {SCREEN_W / 2, SCREEN_H / 2}, // screen center...
		target = {WORLD_W / 2, WORLD_H / 2}, // ...shows world center
		rotation = 0,
		zoom = 0.6, // start zoomed out: most of the world visible
	}
}
```

The world (boids, world border, predator, debug circles, scare ring) draws between `rl.BeginMode2D(cam)` and `rl.EndMode2D()`; the HUD and sliders draw *after*, in untransformed screen pixels. One boundary, total clarity about which space any pixel lives in.

### raygui: sliders wired straight into `Settings`

raygui ships inside Odin's `vendor:raylib` — it's already linked, nothing to install. It's immediate-mode: no widget objects, no state, no events. A slider *is* its value pointer:

```odin
ui_slider :: proc(label: cstring, value: ^f32, min, max: f32, y: ^f32) {
	bounds := rl.Rectangle{PANEL_RECT.x + 10, y^, PANEL_RECT.width - 20, 16}
	rl.GuiSlider(bounds, label, rl.TextFormat("%.2f", value^), value, min, max)
	y^ += 27
}
```

Drag the handle and raygui writes through `value` — which points *directly* at `settings.w_sep`, `settings.perception_radius`, …. The sim reads the new numbers on the very next frame. No bindings, no change detection, no store. This is why lesson 8.1 insisted on one `Settings` struct threaded everywhere: six `ui_slider` calls later, the flock's personality is live-tunable. (Three fields deliberately get no slider: `max_speed`, `min_speed`, and `max_steer` change how flight *feels* rather than how the flock *shapes* — tune those with a recompile and a watchful eye.)

The panel around the sliders is one rect — `PANEL_RECT :: rl.Rectangle{SCREEN_W - 250, 8, 242, 200}`, drawn with `rl.GuiPanel` — and one startup line keeps raygui's tiny default text readable: `rl.GuiSetStyle(.DEFAULT, i32(rl.GuiDefaultProperty.TEXT_SIZE), 12)`.

Two sliders need a nudge beyond writing a float:

- **Boid count** is an `f32` slider over a preallocated pool (`MAX_BOIDS = 4096`). When it changes, `set_boid_count` grows the array with fresh random boids or `resize`s it smaller — never a reallocation in the loop.
- **Perception radius** is the grid's cell size. When it changes we call `grid_resize`, which recomputes `cells_x/cells_y` — no reallocation either, because the arrays were sized for the worst case up front (the slider's 20 px minimum → `MAX_CELLS :: 128 * 72`) and `grid_rebuild` only touches the active prefix. The zero-per-frame-allocation rule from lesson 8.3 survives runtime tuning. That worst-case sizing is why `grid_init`'s signature changed since 8.3: `grid_init(grid, world_w, world_h, cell_size, max_boids)` became `grid_init(grid, max_cells, max_boids)` — world size and cell size are *runtime* values now, so init no longer wants them.

One tuning footgun to know about: the avoid-radius slider tops out at 80 while the perception slider bottoms at 20 — so you *can* drag `avoid_radius` above `perception_radius`, making boids flee neighbors they can't perceive. The sim won't break, but the flock goes haunted: boids spook away from things that aren't "there". Keep avoid below perception.

### Hazards: the scare point and the predator are the same math

The interaction from Lague's video: hold the mouse to scatter boids, and loose a predator they flee from. Both are "a place boids steer hard away from", so both are one struct:

```odin
Hazard :: struct {
	pos:      rl.Vector2,
	radius:   f32,
	strength: f32, // multiplier on the flee steer
}
```

Each frame `main.odin` packs the active hazards — the left-mouse scare point (radius 150, strength 5, skipped while the cursor is over the slider panel) and the predator if toggled with P (radius 120, strength 8) — into a small array, and `update_boids` applies the flee steer to any boid inside a hazard's radius. One deliberate design choice:

```odin
// flocking obeys the turning limit...
b.vel += clamp_length(accel, s.max_steer) * dt
// ...but fear doesn't: hazard steer is added AFTER the clamp
for h in hazards {
	to_me := offset(h.pos, b.pos, WORLD_W, WORLD_H) // wrap-aware: fear works across the seam
	if rl.Vector2Length(to_me) < h.radius {
		b.vel += steer_toward(to_me, b.vel, s) * h.strength * dt
	}
}
```

Flocking acceleration is clamped to `max_steer`; fear is added *after* the clamp. Strength 5–8 genuinely out-muscles cohesion, so boids *break formation* to escape — a flock of rule-followers would politely ignore the predator. Note the `offset()` call: hazards measure distance wrap-aware, so a predator near the edge scares boids on the *other* side too — the same seam rule the flocking rules obey.

The predator itself is the video's: a red triangle at constant `PRED_SPEED :: 380.0` — deliberately a bit faster than the boids' `max_speed`, so it can actually catch up — on a random-walk heading (`heading += rand.float32_range(-PRED_TURN, PRED_TURN) * dt`, with `PRED_TURN :: 2.2` rad/s of wander), respawned at the world center each time you toggle it with P. The flock parts around it like water.

### Speed coloring

Last touch, also straight from the video: map speed to color so fast boids flash red when fleeing:

```odin
t := clamp((speed - s.min_speed) / (s.max_speed - s.min_speed), 0, 1)
color := rl.ColorLerp(rl.SKYBLUE, rl.RED, t)
```

Press D to overlay every boid's perception circle — expensive at 4,000 boids, invaluable for debugging, which is exactly what a debug toggle is for.

### Housekeeping: what moved since 8.3

- **The 1/2/3 preset keys are gone** — the count slider replaced them (and the initial spawn is 2,000 boids at startup).
- **`random_boid` lost its `w, h` parameters** — it reads the `WORLD_W`/`WORLD_H` constants directly.
- **`draw_boid` grew a `draw_agent` helper**: the triangle-from-heading math from 8.1, factored out so boids *and* the predator share one drawing routine. `draw_boid`'s signature changed with it — `draw_boid(b, color)` became `draw_boid(b, s)`, because speed coloring needs the settings' speed range.

🌐 **Web dev callout — immediate-mode GUI vs the DOM**
> raygui is the anti-React. There's no component tree, no diffing, no `useState`: each frame you call `GuiSlider(rect, label, text, &value, min, max)` and it draws itself, reads the mouse, and writes the float. State lives in *your* plain variables; the UI is a pure function of it, rebuilt from scratch 60 times a second. It sounds wasteful until you notice it costs microseconds — and that "the UI is stale" is a bug class that simply cannot exist. You already know this mindset: it's the game loop from lesson 2.1, applied to UI.

## Full listing

Runnable snapshot: [`code/04-tuning-and-interaction/`](code/04-tuning-and-interaction/) — [`main.odin`](code/04-tuning-and-interaction/main.odin), [`boids.odin`](code/04-tuning-and-interaction/boids.odin), [`grid.odin`](code/04-tuning-and-interaction/grid.odin), [`camera.odin`](code/04-tuning-and-interaction/camera.odin)

```sh
odin run 08-boids/code/04-tuning-and-interaction
odin run 08-boids/code/04-tuning-and-interaction -o:speed   # for high boid counts
```

## Checkpoint

A 2560×1440 world under a working camera: right-drag pans, the wheel zooms toward the cursor, and a dark border marks the world edge. The slider panel (top-right) reshapes the flock *live* — crank separation to 3 for a gas cloud, drop it to 0 and watch boids stack, shrink perception for small independent flocks. Hold LMB to part the flock around the cursor; press P and a red predator carves red-streaked wake through it. D shows perception circles. `update` stays in single-digit ms at 2,000 boids.

## Exercises

1. **Easy:** Flip a hazard into an *attractor*: right-mouse attracts boids toward the cursor instead of repelling. You need one sign change — but try strength 2 and watch boids orbit the point instead of landing on it. Why don't they stop? (`min_speed`.)
2. **Medium:** Circular obstacles: place 3–4 fixed hazards (strength ~3, drawn as dark circles) at interesting spots and watch streams of boids split around them and re-form downstream. This is the "flow around a rock" shot from every flocking demo.
3. **Medium:** Leader boid: add one boid that ignores the rules and eases toward the mouse (`pos = rl.Vector2Lerp(pos, mouse_world, 2*dt)`), drawn in gold. With cohesion up and separation down, the flock follows it — you've invented shepherding.
4. **Hard:** Settings save/load: F5 writes the current `Settings` to a text file with `os.write_entire_file` (you did this for Snake's high score — `fmt.tprintf` + `transmute([]u8)`, one `key=value` per line), F9 reads it back with `os.read_entire_file` + `strings.split` + `strconv.parse_f32`. Now you can version-control your favorite flock "personalities".

**Next:** [Module 9 — Game Architecture: the pattern field guide](../09-game-architecture/01-pattern-field-guide.md)
