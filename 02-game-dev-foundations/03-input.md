# 2.3 Input: polling, not events

**Module:** 02-game-dev-foundations

## Goals

- Poll keyboard, mouse, and (briefly) gamepad state each frame
- Know the crucial difference between `IsKeyDown` and `IsKeyPressed`
- Get mouse position, deltas, wheel, and clicks
- Buffer input so presses aren't lost between simulation steps

## New concepts

| Concept | What it is |
|---|---|
| Input polling | Every frame you *ask* about the current state — nothing calls you |
| `IsKeyDown` / `IsKeyPressed` | Held (every frame) vs. pressed-this-frame (once) |
| `rl.KeyboardKey` | Enum of keys: `.SPACE`, `.RIGHT`, `.W`, … |
| Mouse state | `GetMousePosition`, `IsMouseButtonPressed`, `GetMouseWheelMove` |

## Walkthrough

## The polling model

There are no event listeners. Each frame, you interrogate the hardware state:

```odin
if rl.IsKeyDown(.RIGHT)  do pos.x += SPEED * dt   // held: smooth movement
if rl.IsKeyPressed(.SPACE) do jump()              // once: discrete actions
if rl.IsKeyReleased(.SPACE) do cut_jump_short()   // the frame it goes up
```

- **`IsKeyDown`** is true *every frame* the key is held → continuous things: movement, aiming, charging.
- **`IsKeyPressed`** is true *only on the frame* the key goes down → discrete things: jump, pause, confirm, shoot-once.
- **`IsKeyReleased`** — the frame it goes up: charged-shot release, variable jump height.

Using the wrong one is a classic bug: `IsKeyDown` for jumping gives 60 jumps per second; `IsKeyPressed` for movement gives a 1-frame nudge per press.

🌐 **Web dev callout — goodbye, `addEventListener`**
> Web input is push-based: the browser queues events and calls your handlers whenever they fire. Game input is pull-based: the OS updates a state table, and your loop reads it once per frame. The model is simpler than it sounds — `keysDown` is a set you query, not a stream you consume. The tradeoff: if your frame rate stutters, a quick tap could be missed *between* polls... except raylib polls input at the start of every frame and tracks pressed-this-frame, so taps are never lost at 60 fps. For simulation steps slower than frame rate (Snake's 10 Hz grid), you *do* need input buffering — lesson 5.1 covers exactly that.

## Keys you'll use constantly

```odin
.W .A .S .D .UP .DOWN .LEFT .RIGHT .SPACE .ENTER .ESCAPE .P .R .ONE .TWO
```

Full list: `rl.KeyboardKey` in the [raylib package docs](https://pkg.odin-lang.org/vendor/raylib/#KeyboardKey). The enum shorthand (`.SPACE` instead of `rl.KeyboardKey.SPACE`) works anywhere the type is known — you'll write it a thousand times.

## Mouse

```odin
mouse := rl.GetMousePosition()                    // Vector2 in screen coords
if rl.IsMouseButtonPressed(.LEFT)  do spawn(mouse)
if rl.IsMouseButtonDown(.RIGHT)    do drag()
wheel := rl.GetMouseWheelMove()                   // +1/-1 per notch
delta := rl.GetMouseDelta()                       // movement since last frame
```

Buttons: `.LEFT`, `.RIGHT`, `.MIDDLE`, `.SIDE`, `.EXTRA`. The boids capstone uses all of this: wheel zooms the camera, right-drag pans, left-click scares the flock.

## Gamepad (30 seconds)

```odin
if rl.IsGamepadAvailable(0) {
	if rl.IsGamepadButtonDown(0, .RIGHT_FACE_DOWN) { /* "A"/"cross" */ }
	axis_x := rl.GetGamepadAxisMovement(0, .LEFT_X)  // -1..1
}
```

Same poll model, plus an availability check. The projects in this course are keyboard/mouse-first; adding gamepad support is an exercise in Asteroids.

## A note on `SetExitKey`

By default ESC closes the window (`WindowShouldClose` becomes true). If your game uses ESC for pause menus, steal it: `rl.SetExitKey(.KEY_NULL)` — then ESC is yours to poll like any key, and the window only closes via its X button or an explicit quit path you build.

## Full listing

Runnable snapshot: [`code/03-input/main.odin`](code/03-input/main.odin) — an input inspector: move a square with WASD (held), tap SPACE to pulse it (pressed), click to drop markers, wheel to resize the square, and watch live state readouts.

```sh
odin run 02-game-dev-foundations/code/03-input
```

## Checkpoint

- WASD moves smoothly; tapping SPACE pulses exactly once per tap
- The on-screen readout matches your fingers: held keys listed, mouse position updating live
- You can articulate when `IsKeyPressed` is correct and when `IsKeyDown` is correct

## Exercises

1. **Easy:** Add SHIFT-as-sprint: while held, movement speed doubles.
2. **Easy:** Show a "CLICK!" label for 0.3 seconds after each left click (store a `timer: f32`, decrement with dt, draw when `> 0`).
3. **Medium:** Implement pause: P toggles a `paused` bool; when paused, skip the update section and dim the screen (`DrawRectangle` fullscreen with `Fade(rl.BLACK, 0.5)`), drawing "PAUSED" centered. Every project from here on will include this.
4. **Medium:** Arrow keys rotate an arrow drawn with `DrawTriangle` (store an `angle: f32`, compute the three points with `math.sin`/`math.cos`). Pressing SPACE resets rotation to 0. You just built the aiming half of Asteroids' ship.

**Next:** [2.4 Textures, sprites, and audio](04-textures-sprites-audio.md)
