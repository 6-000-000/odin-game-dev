# 2D Game Development with Odin & raylib

**A project-based course for senior web developers who have never built a game.**

You will go from `odin run` to a 2,000-agent flocking simulation by building six complete games. Every concept is taught through code you write, run, and modify — never through abstract theory alone.

- **Language:** [Odin](https://odin-lang.org) — a modern, C-like systems language with no hidden allocations, no GC pauses, and a refreshingly small spec.
- **Library:** [raylib](https://github.com/odin-lang/Odin/tree/master/vendor/raylib) (ships with Odin as `vendor:raylib`) — the friendliest game programming library in existence. No engine, no editor, no scene graph. Just functions.
- **Approach:** immediate mode. If you want something on screen, you draw it. Every frame. You'll understand every pixel.

---

## Who this is for

You are a senior web developer. You know JavaScript/TypeScript inside out, you've shipped real products, and you understand event loops, the DOM, requestAnimationFrame, and npm-driven workflows. You have **zero** game development experience.

This course translates what you know into gamedev terms at every step. Each lesson has a **🌐 Web dev callout** that maps the current concept to its closest web analogue — and, just as often, explains why the analogue breaks down.

## What you'll build

| # | Project | You'll learn |
|---|---------|--------------|
| 1 | **Pong** | The game loop, delta time, input, AABB collision, game states |
| 2 | **Breakout** | Entity arrays, collision faces, level data, dynamic arrays |
| 3 | **Snake** | Grid logic, fixed timestep, input buffering, save files |
| 4 | **Flappy Bird** | Gravity & impulse physics, object pools, procedural spawning, parallax |
| 5 | **Asteroids** | Rotation & thrust, entity pooling at scale, particles, audio juice |
| 6 | **Boids** 🐦 | Flocking (separation/alignment/cohesion), spatial hashing, cameras, live tuning — the capstone, based on [Sebastian Lague's boids video](https://www.youtube.com/watch?v=bqtqltqcQhw) |
| 7 | **No game — architecture** | Pattern consolidation, AoS vs SoA with Odin's `#soa` (measured on your own boids sim), building a mini-ECS, and how to choose an architecture |

Each game is a folder of numbered lessons. Each lesson ends with a **runnable snapshot** of the game exactly as it should exist at that point, so you can always diff your code against a known-good state.

## How the course works

Every lesson follows the same shape:

1. **Goals** — what you'll be able to do afterwards
2. **New concepts** — the Odin feature + the gamedev concept being introduced
3. **Walkthrough** — incremental explanation with code
4. **Full listing** — a link to the lesson's snapshot under `code/`, plus the command to run it
5. **Checkpoint** — what you should see on screen
6. **🌐 Web dev callout** — the JS/TS translation of the lesson's key idea
7. **Exercises** — 2–4 challenges, graded easy → hard. *Do them.* They're where the learning actually happens.

> **The one rule:** type the code yourself. Don't copy-paste the snapshots. The snapshots exist to unblock you and to diff against — not to be read instead of written. Muscle memory is half of learning a language.

## Running the code

Every code snapshot is a self-contained Odin package (a folder with a `main.odin`). From the repository root:

```sh
odin run 03-pong/code/01-window-and-paddles
```

or from inside a snapshot folder:

```sh
odin run .
```

Release build (for performance testing, e.g. the boids capstone):

```sh
odin run . -o:speed
```

No `package.json`, no bundler, no install step. `vendor:raylib` is part of the Odin distribution — the import just works.

## Curriculum map

### Module 0 — Setup
- [0.1 Install, verify, and open your first window](00-setup/01-install-and-verify.md)

### Module 1 — Odin for Web Developers
A JS/TS → Odin translation course. Not intro-to-programming — a remap of what you already know.
- [1.1 From JavaScript to Odin](01-odin-for-web-devs/01-from-js-to-odin.md)
- [1.2 Types and procedures](01-odin-for-web-devs/02-types-and-procedures.md)
- [1.3 Structs, arrays, and slices](01-odin-for-web-devs/03-structs-slices-arrays.md)
- [1.4 Memory and allocators](01-odin-for-web-devs/04-memory-and-allocators.md)
- [1.5 Packages, the core library, and randomness](01-odin-for-web-devs/05-packages-and-random.md)

### Module 2 — Game Dev Foundations
The mental models that differ from the web: the loop, the coordinate system, the renderer, the input model.
- [2.1 The game loop and delta time](02-game-dev-foundations/01-the-game-loop.md)
- [2.2 Drawing and the coordinate system](02-game-dev-foundations/02-drawing-and-coordinates.md)
- [2.3 Input: polling, not events](02-game-dev-foundations/03-input.md)
- [2.4 Textures, sprites, and audio](02-game-dev-foundations/04-textures-sprites-audio.md)
- [2.5 The architecture roadmap](02-game-dev-foundations/05-architecture-roadmap.md) — *a map of every pattern the course teaches, and when it arrives*

### Module 3 — Project: Pong
- [3.1 Window and paddles](03-pong/01-window-and-paddles.md)
- [3.2 Ball and collisions](03-pong/02-ball-and-collisions.md)
- [3.3 Scoring and game states](03-pong/03-scoring-and-game-states.md)
- [3.4 Polish: AI, sound, and juice](03-pong/04-polish.md)

### Module 4 — Project: Breakout
- [4.1 Paddle and ball, revisited](04-breakout/01-paddle-and-ball.md)
- [4.2 The brick grid](04-breakout/02-brick-grid.md)
- [4.3 Lives, levels, and level data](04-breakout/03-lives-and-levels.md)
- [4.4 Power-ups and polish](04-breakout/04-powerups-and-polish.md)

### Module 5 — Project: Snake
- [5.1 Grid and movement](05-snake/01-grid-and-movement.md)
- [5.2 Growing and food](05-snake/02-growing-and-food.md)
- [5.3 Death, score, and saving](05-snake/03-death-and-score.md)

### Module 6 — Project: Flappy Bird
- [6.1 Gravity and flap](06-flappy-bird/01-gravity-and-flap.md)
- [6.2 The pipe spawner](06-flappy-bird/02-pipe-spawner.md)
- [6.3 Collisions and score](06-flappy-bird/03-collisions-and-score.md)
- [6.4 Game feel](06-flappy-bird/04-game-feel.md)

### Module 7 — Project: Asteroids
- [7.1 Ship and thrust](07-asteroids/01-ship-and-thrust.md)
- [7.2 The entity pool](07-asteroids/02-entity-pool.md)
- [7.3 Shooting and splitting](07-asteroids/03-shooting-and-splitting.md)
- [7.4 Particles, audio, and juice](07-asteroids/04-particles-audio-juice.md)

### Module 8 — Capstone: Boids 🐦
Faithful to [Sebastian Lague's boids simulation](https://www.youtube.com/watch?v=bqtqltqcQhw): the same three rules, the same perceived-radius model, and the same spatial-optimization leap that takes you from ~150 to thousands of boids.
- [8.1 The three flocking rules](08-boids/01-the-flocking-rules.md)
- [8.2 The naïve implementation](08-boids/02-naive-boids.md)
- [8.3 Spatial hashing: from 150 to 2,000+](08-boids/03-spatial-hashing.md)
- [8.4 Tuning, camera, and a predator](08-boids/04-tuning-and-interaction.md)

### Module 9 — Game Architecture
The system-level layer: consolidate the patterns, then go under the hood of how game data is organized and laid out in memory.
- [9.1 The pattern field guide](09-game-architecture/01-pattern-field-guide.md)
- [9.2 AoS vs SoA: memory layout is a design decision](09-game-architecture/02-aos-vs-soa.md) — *convert your own boids sim with Odin's `#soa` and measure it*
- [9.3 Components and systems](09-game-architecture/03-components-and-systems.md) — *build a mini-ECS with generation-safe entity handles*
- [9.4 Rebuilding Asteroids on the mini-ECS](09-game-architecture/04-asteroids-as-ecs.md) — *an honest comparison, and how to choose*

### Module 10 — Next Steps
- [10.1 Where to go next (web export, shaders, tilemaps)](10-next-steps/01-where-to-go-next.md)

## Suggested pacing

Modules 0–2 in one sitting (they're short — you already know how to program). Then one project per sitting. Each project lesson is designed to take 30–60 minutes including exercises.

## Reference material

- [Odin docs](https://odin-lang.org/docs/) and [pkg.odin-lang.org](https://pkg.odin-lang.org) (core/vendor API reference)
- [raylib cheatsheet](https://www.raylib.com/cheatsheet/cheatsheet.html) — the entire API on one page; bookmark it
- `vendor:raylib` API reference: [pkg.odin-lang.org/vendor/raylib](https://pkg.odin-lang.org/vendor/raylib/)
- [raylib examples](https://www.raylib.com/examples.html) — C examples; every one translates to Odin almost line-for-line
- [Sebastian Lague — Boids simulation video](https://www.youtube.com/watch?v=bqtqltqcQhw) (watch before Module 8)
