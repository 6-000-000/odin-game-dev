# 1.5 Packages, the core library, and randomness

**Module:** 01-odin-for-web-devs

## Goals

- Know the `core:` packages you'll actually use in games
- Generate randomness two ways (raylib's helper and `core:math/rand`)
- Understand how a multi-file Odin package works, for when your games outgrow one file

## New concepts

| Concept | What it is |
|---|---|
| `core:` library | Odin's stdlib: `fmt`, `math`, `math/rand`, `strings`, `os`, `mem`, `slice`… |
| `core:math` | `sqrt`, `sin`, `cos`, `clamp`, `lerp`, `PI` — the game math toolkit |
| `core:math/rand` | Seeded PRNG with range helpers |
| Multi-file package | Folder of `.odin` files sharing one `package` name; no imports between them |

## Walkthrough

## Your everyday `core:` toolkit

```odin
import "core:fmt"        // println, printf, printfln, eprintfln (stderr)
import "core:math"       // sqrt, sin, cos, atan2, clamp, lerp, abs, PI, min, max
import "core:math/rand"  // proper randomness
import "core:strings"    // builder/concat when you need it (rarely, thanks to rl.TextFormat)
import "core:os"         // file I/O — used once in Snake for the high score
import "core:slice"      // sort, reverse, contains helpers on slices
```

`core:math` highlights you'll use in nearly every project:

```odin
math.sqrt(x)          // vector lengths
math.sin(t), math.cos(t)
math.clamp(v, lo, hi) // keep paddle on screen
math.lerp(a, b, t)    // smooth movement toward a target
math.PI               // radians; raylib also has rl.PI and DEG2RAD/RAD2DEG
```

Note that `min`/`max`/`abs`/`clamp` are actually built-ins in modern Odin (no import needed) for many type combinations; `core:math` covers the float-generic cases. If the compiler ever says "undefined: min", import `core:math`… but usually it just works.

## Randomness

Games need dice constantly. Two good options:

**raylib's helper** — dead simple, inclusive integer range, no seeding required for play:

```odin
rl.GetRandomValue(1, 6)      // i32 in [1, 6], like a die
```

**`core:math/rand`** — for floats, ranges, and reproducibility:

```odin
import "core:math/rand"

rand.reset(12345)                    // optional: seed for reproducible runs (great for debugging!)
speed := rand.float32_range(200, 400) // f32 in [200, 400)
angle := rand.float32() * 2 * math.PI // [0, 1) * 2π
x := rand.int_max(100)                // int in [0, 100)
```

If you don't seed, you get different results each run — fine for games. During development, **seeding to a fixed value is a superpower**: the "random" world becomes reproducible, so bugs can be replayed. The boids capstone uses this.

## Multi-file packages

Until now, everything lived in one `main.odin`. Real games split up. Odin's model couldn't be simpler:

```
mygame/
├── main.odin      // package game  (has main :: proc)
├── player.odin    // package game
└── bullets.odin   // package game
```

- Every file in the folder shares **one** `package` name.
- Files see each other's declarations directly — **no imports between files of the same package**. `player.odin` can use `Bullet` declared in `bullets.odin` as if it were in the same file.
- `odin run .` compiles the whole folder. There's no build config; the folder *is* the build.
- Visibility rule: everything at file scope is visible to importers of the package. `@(private)` hides a declaration from other packages. Within one package, everything is shared.

```odin
// bullets.odin
package game

import rl "vendor:raylib"

Bullet :: struct {
	pos, vel: rl.Vector2,
	active:   bool,
}

spawn_bullet :: proc(bullets: ^[dynamic]Bullet, pos, vel: rl.Vector2) {
	append(bullets, Bullet{pos = pos, vel = vel, active = true})
}
```

```odin
// main.odin
package game

import rl "vendor:raylib"

main :: proc() {
	bullets: [dynamic]Bullet
	spawn_bullet(&bullets, {100, 100}, {0, -300})   // from bullets.odin — no import
	// ...
}
```

🌐 **Web dev callout:** this is the opposite of ES modules. There's no `import { Bullet } from "./bullets"` — imagine every file in a folder being automatically concatenated into one scope, and the folder being the importable unit. It feels too loose for about a day, and then you notice you stopped thinking about import graphs entirely. Circular imports between packages are forbidden, which keeps architecture honest.

**Course convention:** projects start as one `main.odin` (Pong, Snake, Flappy) and split into files when the entity count grows (Asteroids, Boids). Each lesson tells you when to split.

## Full listing

Runnable snapshot: [`code/05-packages-and-random/`](code/05-packages-and-random/) — a two-file package demonstrating shared scope plus both RNG styles.

```sh
odin run 01-odin-for-web-devs/code/05-packages-and-random
```

## Checkpoint

You know where `sqrt`, `clamp`, `printf`, and `float32_range` come from, and you can split a program across two files without any import ceremony.

## Exercises

1. **Easy:** Roll two dice (`rl.GetRandomValue(1, 6)`) 10 times and print the sums. Then seed `rand` with a fixed value and use `rand.int31_max(6) + 1` instead; run twice and confirm identical output.
2. **Easy:** Use `math.lerp` to print 5 steps from 0 to 100 (`t` = 0, 0.25, 0.5, 0.75, 1).
3. **Medium:** Split exercise 1.3.3 (`remove_dead` for particles) into a two-file package: `particle.odin` holds the struct and procs, `main.odin` runs a small simulation. No new logic — just the split.
4. **Medium:** Write `random_point_in_circle :: proc(radius: f32) -> rl.Vector2` using `rand.float32` (hint: random angle + random distance; for uniform distribution use `radius * math.sqrt(rand.float32())` for the distance — the sqrt compensates for area growing with r²). This is the helper to reach for whenever you scatter points inside a circle instead of a rectangle.

**Next:** [Module 2 — Game Dev Foundations](../02-game-dev-foundations/01-the-game-loop.md)
