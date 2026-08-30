# 2.5 The architecture roadmap

**Module:** 02-game-dev-foundations

## Goals

- Have a map of every architectural pattern this course teaches — before you build anything
- Know the *problem* each pattern solves, so you recognize the moment it becomes relevant
- Understand the course's one teaching rule: **patterns arrive when their problems do**

## New concepts

This lesson introduces no code. It introduces *vocabulary* — names you'll hear constantly in gamedev circles — each pinned to the exact lesson where you'll build it with your own hands.

## Walkthrough

### Why you're reading a map instead of code right now

You're a senior developer. You have pattern intuition from years of web work, and learning without knowing the destination probably feels wrong. Fair. This page is the destination: every pattern you'll meet, in the order you'll meet it, with the problem that makes it necessary.

One promise the course makes, stated now so you can hold us to it: **no pattern is taught before the problem it solves has hurt you — briefly, on purpose.** You'll write the object pool by hand three times (Breakout, Flappy, Asteroids) before module 9 formalizes why it works. That's not repetition, it's load-bearing: a pattern learned as *relief from felt pain* sticks; a pattern learned as *preparation for imagined pain* evaporates.

🌐 **Web dev callout — this is the RFC before the sprint**
> You already work this way: before a big build, you write the design doc — not the implementation, just the shape of the problem space and the names of the moving parts. This lesson is that doc. Skim it now, forget the details, and let each name ring a bell when it shows up in a project later. Recognition is the goal, not memorization.

### The map

| Pattern | The problem it solves | Where you'll build it |
|---|---|---|
| Game loop + delta time | Movement speed must not depend on the machine's frame rate | [2.1](01-the-game-loop.md), every project after |
| Fixed timestep (accumulator) | Simulation must be stable/deterministic even when rendering isn't | [2.1](01-the-game-loop.md), Snake [5.1](../05-snake/01-grid-and-movement.md) |
| Immediate-mode rendering | No scene graph, no diffing — screen is a pure function of state, redrawn every frame | [2.2](02-drawing-and-coordinates.md) |
| Polling input (vs events) | The world needs current state every frame, not a queue of past events | [2.3](03-input.md) |
| Reflect + reposition | Collisions must resolve *out of* overlap or objects stick | Pong [3.2](../03-pong/02-ball-and-collisions.md) |
| State machine (enum + switch) | Menus/playing/game-over need different rules *and* different screens | Pong [3.3](../03-pong/03-scoring-and-game-states.md), then everywhere |
| Puppet AI | Computer opponents should use the player's mechanics with a worse brain, not cheat | Pong [3.4](../03-pong/04-polish.md) |
| Timer envelopes | "Juice" (flash, shake, pop) needs fire-and-forget timed effects | Pong 3.4, Flappy [6.4](../06-flappy-bird/04-game-feel.md) |
| Data-driven design | Levels should be *data you edit*, not code you rewrite | Breakout [4.3](../04-breakout/03-lives-and-levels.md) |
| Rejection sampling | "Random, but not *there*" — spawn points, loot, map gen | Snake [5.2](../05-snake/02-growing-and-food.md) |
| Input buffering | Fast taps must not be lost between slow simulation steps | Snake [5.1](../05-snake/01-grid-and-movement.md) |
| Object pool | Spawning/despawning every frame without allocation or GC-style pauses | Flappy [6.2](../06-flappy-bird/02-pipe-spawner.md), Breakout [4.4](../04-breakout/04-powerups-and-polish.md), Asteroids [7.2](../07-asteroids/02-entity-pool.md) |
| Edge-trigger latch | "Do X *once* when Y becomes true" in a world that only knows "is Y true now" | Flappy [6.3](../06-flappy-bird/03-collisions-and-score.md) |
| Entity tree → flat pool | One thing splits into many (asteroids) without tree data structures | Asteroids [7.3](../07-asteroids/03-shooting-and-splitting.md) |
| Spatial hash grid | Neighbor queries must not be O(n²) — thousands of agents at 60 fps | Boids [8.3](../08-boids/03-spatial-hashing.md) |
| Steering behaviors | Lifelike motion from summed simple rules, no scripting | Boids [8.1](../08-boids/01-the-flocking-rules.md)–[8.2](../08-boids/02-naive-boids.md) |
| AoS vs SoA (memory layout) | How entities are *laid out* in memory changes cache behavior and speed | Architecture [9.2](../09-game-architecture/02-aos-vs-soa.md) |
| ECS (Entity Component System) | Entity *variety* explodes: composition of data beats hierarchies of types | Architecture [9.3](../09-game-architecture/03-components-and-systems.md)–[9.4](../09-game-architecture/04-asteroids-as-ecs.md) |

### The endgame, so you know where this goes

Module 8 gives you a 5,000-boid flocking simulation. Module 9 then does two things to your own code:

1. **Rewrites its memory layout** from Array-of-Structs to Struct-of-Arrays — Odin has first-class `#soa` types, so the *code barely changes* while the layout completely changes — and measures the difference on screen.
2. **Ports Asteroids onto a mini-ECS you build yourself** (~180 lines), then honestly compares the two versions: what improved, what got worse, and when each architecture is the right call. Spoiler: for every game in this course, the simple thing was the right call. Knowing *why* is the actual skill.

Patterns you will *not* need in this course (and when you would): event/message queues (decoupling many unrelated systems), the command pattern (undo, replays, netcode), scene managers (games with more than a handful of screens). Module 9.1 covers them briefly so you know they exist.

## Full listing

This lesson's "code" is the course itself — the runnable snapshot for every pattern above is linked in its table row.

## Checkpoint

You can read the table's middle column and nod: "right, that would be a problem." You can't yet solve most of them — that's the next seven modules.

## Exercises

1. **Easy:** Pick your favorite 2D game. From the table, guess which three patterns it definitely uses and why. (A roguelike? Data-driven levels, spatial hashing, state machines. Tower defense? Object pools, waves, edge triggers.)
2. **Medium:** Take the game from exercise 1 and guess where it needs a pattern *not* in the table — is that an event queue, a command pattern, or a scene manager? What feature forces it?
3. **Medium:** Revisit this page after each project module and cross off the rows you now own. If any row doesn't feel earned by the time you reach module 9, that's the lesson to redo.

**Next:** [Module 3 — Project: Pong](../03-pong/01-window-and-paddles.md)
