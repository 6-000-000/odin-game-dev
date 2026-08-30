# 9.1 The pattern field guide

**Module:** 09-game-architecture

## Goals

- Consolidate: every pattern you built across six games, with its name, its tradeoffs, and its breaking point
- Meet three patterns you deliberately *didn't* need — and learn the features that would force them
- Frame the rest of this module: memory layout (9.2) and ECS (9.3–9.4) as the *system-level* layer beneath everything above

## New concepts

| Concept | What it is |
|---|---|
| Event/message queue | Decouple systems by posting events instead of calling directly |
| Command pattern | Input/actions as data objects — enables undo, replays, netcode |
| Scene manager | A stack of screens with enter/exit, for games with more than a few states |
| System-level architecture | Layout and organization of *all* your data — the layer this module covers |

## Walkthrough

### The field guide: patterns you own

Back in [lesson 2.5](../02-game-dev-foundations/05-architecture-roadmap.md) this was a map of unknown territory. Now every row is a place you've been. Read this as a review — each entry names when to reach for the pattern and, just as important, **when it breaks**.

**Time and flow**

- **Game loop + delta time** — *Reach for:* always. *Breaks:* when a frame hitch lets fast objects tunnel through walls → then add…
- **Fixed timestep accumulator** — *Reach for:* grid games (Snake), deterministic sims, replays, netcode. *Breaks:* render-sim rate mismatch causes visible stutter without interpolation (you saw this in 2.1's exercise).
- **State machine (enum + switch)** — *Reach for:* any game with distinguishable "modes." *Breaks:* when switches nest switches (boss phases inside playing inside paused…) → that's a statechart/scene manager's job, below.
- **Input buffering** — *Reach for:* discrete-step games where instant input breaks invariants (Snake's 180° reversal), combo windows, jump buffering in platformers. *Breaks:* never, but depth is a feel decision — one slot holds one intent; a queue holds a combo (5.1's exercise 3).

**Entities and lifetime**

- **Object pool** — *Reach for:* anything spawned/despawned per-frame (bullets, particles, pipes). *Breaks:* when slots must be *referenced* long after death (a slot gets recycled and your stale pointer hits a new entity) → add generation counters, 9.3 shows how. Also breaks when entity *variety* explodes → that's 9.3's whole lesson.
- **Entity tree → flat pool** — *Reach for:* splitting/spawning hierarchies (asteroids, adds in boss fights). *Breaks:* when parent-child *relationships* must persist (a squad that regroups) — then you need real hierarchy or entity references, not flattened spawns.
- **Data-driven design** — *Reach for:* anything content-heavy: levels, waves, item stats, dialogue. *Breaks:* never, really — the failure mode is not going far enough (magic numbers in code) or way too far (a Turing-complete level format for a jam game).

**Feel and feedback**

- **Reflect + reposition** — *Reach for:* every collision response. *Breaks:* stacked overlaps (three objects in one spot) need iterative solvers — but that's physics-engine territory, not arcade games.
- **Timer envelopes** — *Reach for:* any fire-and-forget effect (flash, shake, pop). *Breaks:* effects that must *interrupt and blend* (animation canceling in a fighting game) need a real animation state machine.
- **Edge-trigger latch** — *Reach for:* "once when X becomes true": scoring, triggers, achievements. *Breaks:* never; the failure is forgetting it (counting overlaps instead of crossings — the classic double-score bug).
- **Puppet AI** — *Reach for:* opponents the player must outplay. *Breaks:* when the AI must *plan* (pathfinding, strategy) — steering is reactive by nature.
- **Steering behaviors** — *Reach for:* agents with inertia that seek, flee, or flock (boids, the 8.4 predator, homing missiles): desired velocity minus current, clamped, weighted. *Breaks:* when the hard part is *choosing* the goal (pathfinding, planning) — steering only answers "how do I get there smoothly."

**Scale**

- **Rejection sampling** — *Reach for:* "random, but not *there*" in sparse spaces. *Breaks:* as the space fills (a 90%-full board → infinite retries) — switch to collect-and-choose.
- **Spatial hash grid** — *Reach for:* pairwise local queries over hundreds+ of agents (neighbors, collisions). *Breaks:* hugely varying entity sizes (a battleship and a bullet in one grid) → quadtrees; and non-uniform distributions (everything in one cell → back to O(n²)).

🌐 **Web dev callout — patterns are vocabulary, not ceremony**
> If "design patterns" makes you think of `AbstractFactoryFactory` Java jokes, recalibrate: on the web you already say "debounce that handler," "pool those connections," "make it a controlled component" — pattern names as *compression for shared experience*. This guide is the same move for gamedev. The value isn't the code (you wrote all of it already); it's that "spatial hash" now means something to you in a design discussion, a library's docs, or an interview. Nobody should ever implement a pattern from a book — you extract it from a problem you have, then learn its name.

### Three you didn't need (and what would change that)

**Event/message queue.** In every project, systems talked by direct calls: the collision code *directly* incremented `score`. That coupling is fine at six-entities scale. When it hurts: an achievement system, a sound system, and an analytics system all want to know "player scored" — and you don't want collision code importing all three. The fix is posting `Scored{points: 100}` to a queue that interested systems drain each frame. Web analogue: pub/sub, the observer pattern, Redux actions. You felt the edges of this in Asteroids (explosion sound + particles + score + screenshake all triggered from one death site) — it was still manageable with four direct calls. At forty, it isn't.

**Command pattern.** Your games read input and *immediately* moved state: `if IsKeyDown(.W) do pos.y -= speed * dt`. When input must become *data* — a `Move{dx, dy}` value you can store, replay, undo, or send over a network — you wrap it as a command and execute it against the world. You'd need this for: replays, undo systems (a level editor), lockstep multiplayer, and tool-assisted speedruns. None of the six games needed any of those. Now you know the name for when they do.

**Scene manager.** Each game had 2–4 states, so one enum + two switches was the perfect amount of structure. When screens multiply (title → settings → save slots → overworld → battle → inventory → game over), a flat switch becomes spaghetti, and each screen wants its own enter/exit/update/draw plus a stack ("pause pushes settings, pop back"). That's a scene manager: an array/stack of screen structs with lifecycle procs. Web analogue: a router with nested routes. Reach for it when your `Game_State` enum hits double digits — not before.

### The layer beneath: what the rest of this module covers

Everything above is *code-level* architecture — how procs and loops are shaped. The next three lessons go one level down, to **system-level architecture**: how *all* of your game's data is laid out and organized.

- **9.2** asks a deceptively simple question: your boids live in an array — but is an array of structs actually the right *shape* in memory? (Spoiler: it depends, and Odin lets you switch with one keyword.)
- **9.3–9.4** ask the organization question: when entity *kinds* multiply past what pools handle gracefully, how do engines compose entities out of data instead of types — and is it worth it for games like yours?

## Full listing

No new code today — the runnable artifacts are the six projects you already built. If any entry in the field guide felt unearned, its snapshot is linked from [the roadmap](../02-game-dev-foundations/05-architecture-roadmap.md): go rerun it.

## Checkpoint

- You can name the pattern behind any system in your six games without checking the table
- For each of the three new patterns, you can name one concrete game feature that would force you to adopt it
- You can state the difference between code-level and system-level architecture in one sentence

## Exercises

1. **Easy:** Open your Asteroids code. Find five patterns from the guide and annotate them with comments (`// PATTERN: edge-trigger latch — wave clear`). If you can't find five, reread 7.2–7.4.
2. **Medium:** Sketch (in comments or on paper) how Snake would change if you added replays. Which pattern appears, and what stops being a direct call?
3. **Medium:** Your Pong needs per-hit sound, particles, screenshake, a combo counter, and an announcer. List the direct calls in the collision site today, then design the event struct that replaces them.
4. **Hard:** Pick the project where a scene manager is *closest* to worth it. Count the states, sketch the stack for one interaction (pause → settings → back), and decide honestly: pull the trigger or not? Defend the answer in two sentences.

**Next:** [9.2 AoS vs SoA: memory layout is a design decision](02-aos-vs-soa.md)
