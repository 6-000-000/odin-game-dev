# 2.1 The game loop and delta time

**Module:** 02-game-dev-foundations

## Goals

- Understand the anatomy of a game loop: input → update → draw → repeat
- Use delta time so movement is framerate-independent
- Know what a fixed timestep is and when you need one
- Read FPS and frame time like a profiler

## New concepts

| Concept | What it is |
|---|---|
| Game loop | An infinite `for` that polls input, updates state, redraws everything |
| Delta time (`dt`) | Seconds since last frame — the multiplier that makes speed real |
| `rl.GetFrameTime()` | raylib's dt for the current frame |
| Fixed timestep | Updating simulation in constant-size chunks (Snake uses this fully) |

## Walkthrough

## The loop is the program

A web app waits: the browser calls you when something happens (a click, a response, a timer). A game does the opposite — **it never waits**. 60 times per second, every second, it runs the entire world forward one step and redraws it from scratch:

```odin
for !rl.WindowShouldClose() {
	dt := rl.GetFrameTime()

	// 1. INPUT  — what's the player doing right now?
	// 2. UPDATE — advance the world by dt seconds
	// 3. DRAW   — render the entire scene from current state
}
```

Everything is in that loop. Menus, physics, AI, animations — all just code that runs every frame. There is no "when the ball hits the wall, do X" event. There is: every frame, check if ball overlaps wall; if so, bounce.

> **🌐 Web dev callout — `requestAnimationFrame`, but you own it**
> You've seen this shape: `function frame() { update(); render(); requestAnimationFrame(frame) }`. The game loop is that, minus the browser scheduler — *your* `for` loop drives time itself. The psychological difference is bigger than the technical one: on the web, state lives in the DOM and frameworks reconcile it; here, state lives in plain variables and you re-render the world from scratch each frame. No diffing, no virtual DOM, no stale state. The screen is a pure function of your structs.

## Delta time: why `pos += 5` is a bug

Consider moving a paddle right:

```odin
pos.x += 5   // BAD: 5 pixels PER FRAME
```

On a 60 fps machine that's 300 px/s. On a 144 Hz monitor, 720 px/s. During a frame-rate dip, the game literally slows down. Your game's physics become hardware-dependent — the classic beginner bug.

The fix is to define speeds in **pixels per second** and multiply by the frame's duration:

```odin
PADDLE_SPEED :: 400  // pixels per second

dt := rl.GetFrameTime()           // seconds since last frame (~0.0167 at 60fps)
pos.x += PADDLE_SPEED * dt        // 400 px/s on ANY machine
```

`rl.GetFrameTime()` returns an `f32` of the last frame's duration. At 60 fps it's ≈ 0.0167; at 144 fps ≈ 0.0069. The speed stays 400 px/s either way. **Rule of the course: every velocity multiplication includes `dt`.**

## Reading performance

```odin
rl.DrawFPS(10, 10)                          // green FPS counter
rl.DrawText(rl.TextFormat("dt: %.4f", dt), 10, 40, 20, rl.GRAY)
```

`rl.GetFPS()` gives the averaged frame rate; `GetFrameTime` the instantaneous dt. `rl.SetTargetFPS(60)` paces the loop (raylib sleeps the remainder of each frame). Without it, the loop spins as fast as possible — thousands of FPS and a cooked CPU core.

## Fixed timestep (a preview)

Variable dt has a subtle failure: if a frame hitches (say dt = 0.2s during a GC-free disk stall), fast objects teleport through walls — the ball moves 80px in one step and never overlaps the paddle it should have hit.

The cure is updating in fixed-size chunks regardless of render rate:

```odin
TICK :: 1.0 / 120.0
acc: f32 = 0

for !rl.WindowShouldClose() {
	acc += rl.GetFrameTime()
	for acc >= TICK {       // run as many 1/120s sim steps as fit
		simulate(TICK)      // ALWAYS the same dt — deterministic, stable
		acc -= TICK
	}
	render()                // draw once, at whatever rate
}
```

Snake builds its entire movement system on this pattern (it's perfect for grid games), and the boids capstone revisits it for simulation stability. For most arcade games (Pong, Breakout, Flappy), plain variable dt with sensible speeds is completely fine — you'll know when you need more.

## Full listing

Runnable snapshot: [`code/01-game-loop/main.odin`](code/01-game-loop/main.odin) — two circles race across the screen: one moves per-frame (bad), one moves per-second with dt (good). Toggle the FPS cap with SPACE and watch the per-frame circle speed up while the dt circle holds steady.

```sh
odin run 02-game-dev-foundations/code/01-game-loop
```

## Checkpoint

- The dt-driven circle crosses the screen at the same wall-clock speed capped or uncapped
- The per-frame circle becomes a blur when uncapped (hundreds of fps)
- You can explain why, in one sentence: "speed × dt = constant pixels per second regardless of frame rate"

## Exercises

1. **Easy:** Add a third circle moving vertically with dt at 250 px/s, bouncing off the top and bottom edges (flip the sign of its velocity at the boundary).
2. **Easy:** Display `rl.GetFrameTime() * 1000` as milliseconds per frame. At 60 fps it should read ≈ 16.7 ms.
3. **Medium:** Make the dt circle accelerate: add a `speed: f32` that increases by 50 px/s every second the RIGHT key is held, and decays back toward 200 when released (use `math.lerp` or a simple clamp).
4. **Medium:** Implement the accumulator pattern above around the dt circle's update. Set `TICK` to `1.0/30.0` (a 30 Hz simulation) — you'll see the circle move in visible steps while FPS stays high. This stutter is exactly why Snake renders every frame but steps its grid at 10 Hz.

**Next:** [2.2 Drawing and the coordinate system](02-drawing-and-coordinates.md)
