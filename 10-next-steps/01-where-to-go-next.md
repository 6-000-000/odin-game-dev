# 10.1 Where to go next

**Module:** 10-next-steps

You've built six games. You have the loop, the math, the pools, the state machines, the juice — and a flocking simulation with a spatial hash. This final lesson is a map of the territory beyond the course, ordered by how much leverage your existing knowledge gives you.

## Ship your games to the web (you knew this was coming)

raylib compiles to WebAssembly, and Odin's `vendor:raylib` ships a `wasm` folder for exactly this. Your games can run in a browser at full speed — canvas + WebGL, no engine, no runtime. The rough shape:

```sh
# needs the Emscripten SDK (emsdk) installed and activated
odin build . -target:freestanding_wasm32 -build-mode:obj \
    -out:build/game.o
# then link with emcc against Odin's vendored raylib wasm lib + a shell html
```

The moving parts: Emscripten provides the C runtime + browser glue, Odin compiles your code to a wasm object, and a small HTML shell hosts the canvas. The main loop gets restructured slightly (the browser owns the frame callback — `emscripten_set_main_loop` — instead of your `for` loop).

> **🌐 Web dev callout — finally, home turf**
> Everything the browser *doesn't* give you on the web (consistent frame timing, immediate-mode pixels, zero layout engine) is what made native gamedev feel strange in week one. Going back, you'll watch a 2,000-boid sim run in a tab at 60 fps with a devtools profiler you already know how to read. The full guide lives in the [Odin raylib wasm docs](https://github.com/odin-lang/Odin/tree/master/vendor/raylib#wasm) and community templates — search "odin raylib wasm template".

## Shaders: the GPU is right there

Everything you drew was CPU-issued draw calls batched by raylib. The next lever is fragment shaders — tiny programs that run per-pixel on the GPU:

```odin
shader := rl.LoadShader(nil, "crt.fs")   // vertex default, custom fragment
defer rl.UnloadShader(shader)

rl.BeginShaderMode(shader)
	// everything drawn here passes through crt.fs
rl.EndShaderMode()
```

With ~20 lines of GLSL you get: CRT/scanline filters, palette swaps, glow, screen distortion, flash-on-hit. The classic first exercise: render your game to a `rl.RenderTexture2D` (`BeginTextureMode`), then draw that texture to screen through a shader. Instant post-processing pipeline — this is how "game feel" goes pro.

## Tilemaps and bigger worlds

Snake taught you grids; Breakout taught you levels-as-strings. The combination is a tilemap: a 2D array of tile indices + a texture atlas of tiles + a camera. That's the foundation of platformers, top-down RPGs, and roguelikes. The [Tiled](https://www.mapeditor.org) editor exports JSON you can parse with `core:encoding/json` — yes, Odin has JSON in the standard library, and yes, it feels like coming home.

## Architecture: what you actually used

Module 9 made this explicit: you built six games with structs, free procs, and pools — then measured *why* that works (cache lines and memory layout in 9.2) and built the alternative yourself (a mini-ECS with generation-safe entity handles in 9.3, with Asteroids ported onto it in 9.4, honest tradeoffs included). The vocabulary is yours now: AoS vs SoA, components vs hierarchies, and — most valuable of all — *when the simple thing is the right thing*. If you want to go further down this road, look at [flecs](https://github.com/SanderMertens/flecs), Unity DOTS, or Bevy — you'll recognize every concept as a variation on what you built in module 9.

## Your asset pipeline

- **[kenney.nl](https://kenney.nl)** — thousands of free CC0 sprites, sounds, and music. This is where placeholder art stops being an excuse.
- **[sfxr](https://www.drpetter.se/project_sfxr.html)** / jsfxr — procedural sound-effect generators; the spiritual ancestor of your `make_beep`.
- **[raylib cheatsheet](https://www.raylib.com/cheatsheet/cheatsheet.html)** — the whole API on one page; you'll now read it fluently.
- **[raylib examples](https://www.raylib.com/examples.html)** — 140+ C examples; every one translates to Odin nearly line-for-line. When you wonder "how do I do X in raylib", the answer is here.
- **[Odin Discord + forums](https://odin-lang.org/community/)** — active and genuinely helpful.
- **[pkg.odin-lang.org](https://pkg.odin-lang.org)** — the API reference for `core:` and `vendor:` you used all course.

## The capstone of the capstone: your own game

The course projects were chosen so that *almost any 2D game idea* decomposes into pieces you now own:

| Your idea | The pieces you already built |
|---|---|
| Tower defense | Grid (Snake), entity pools + waves (Asteroids), placement UI (Boids' raygui) |
| Vampire-survivors-like | Spatial hash for hundreds of enemies (Boids L3!), pools, XP gems as power-ups (Breakout) |
| Platformer | Gravity/impulse (Flappy), AABB face collision (Breakout), tilemaps (above) |
| Puzzle game | Levels-as-data (Breakout), state machines (everything), fixed timestep (Snake) |
| Bullet hell | Pools + spatial hash + particles — honestly, Asteroids with the numbers turned up |

Pick the smallest version of the idea that could possibly be fun. Build that first — one mechanic, one screen, placeholder shapes. Polish it with particles and beeps until it feels good. *Then* expand. Every project in this course was built in exactly that order, and now you've felt why.

Go build something. Show it to people. 🐦

**Back to:** [Course overview](../README.md)
