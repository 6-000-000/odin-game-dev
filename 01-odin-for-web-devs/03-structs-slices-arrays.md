# 1.3 Structs, arrays, and slices

**Module:** 01-odin-for-web-devs

## Goals

- Model game entities with structs — Odin's only "object"
- Know the three array types and when to use each: fixed `[N]T`, slice `[]T`, dynamic `[dynamic]T`
- Iterate and mutate collections confidently
- Touch `map` for the cases where you need a dictionary

## New concepts

| Concept | What it is |
|---|---|
| `struct` | A product of named fields. No methods, no inheritance, no constructors |
| Fixed array `[N]T` | Length baked into the type, lives inline (stack) |
| Slice `[]T` | A view (pointer + length) over contiguous memory |
| Dynamic array `[dynamic]T` | A growable array you manage — JS's `Array` with manual cleanup |
| `make` / `delete` | Allocate / free dynamic arrays, slices, maps |

## Walkthrough

## Structs: your entities

A game entity is data. In Odin:

```odin
import rl "vendor:raylib"

Paddle :: struct {
	pos:    rl.Vector2,   // rl.Vector2 is a struct: { x, y: f32 }
	size:   rl.Vector2,
	speed:  f32,
}

paddle := Paddle{
	pos   = {40, 200},
	size  = {20, 100},
	speed = 400,
}
```

Field access is `paddle.pos.x`. Initialization uses field names — order doesn't matter, omitted fields zero-initialize. There is **no constructor and no `new`**; a struct literal is just data.

🌐 **Web dev callout — struct vs class**
> A struct is a TypeScript `interface` that actually *is* the memory layout, not a shape erased at runtime. No methods — you write procs that take the struct:
>
> ```ts
> // TS
> class Paddle { update(dt: number) { ... } }
> paddle.update(dt)
> ```
> ```odin
> // Odin
> update_paddle :: proc(p: ^Paddle, dt: f32) { ... }
> update_paddle(&paddle, dt)
> ```
>
> The `^Paddle` is a pointer (next lesson covers these deeply). `&paddle` takes the address. Inside the proc, `p.pos.x` auto-dereferences — no `(*p).pos` noise. This "data + free procedures" split is how the entire course is written, and after two projects you'll stop missing classes.

## The three array types

```odin
// 1. FIXED ARRAY — length is part of the type. Lives inline.
lives: [3]bool = {true, true, true}
grid: [4][8]int   // 2D: four rows of eight — used for Breakout bricks

// 2. SLICE — a view over existing memory. Doesn't own anything.
row: []int = grid[2][:]   // slice of row 2

// 3. DYNAMIC ARRAY — growable, heap-allocated, YOU free it.
bullets: [dynamic]Bullet
append(&bullets, Bullet{pos = {100, 200}})
delete(bullets)  // when done (usually via defer)
```

**Which one when?**

| Situation | Type |
|---|---|
| Count known at compile time, small (lives, grid, key bindings) | `[N]T` fixed |
| Passing a read window over an array to a proc | `[]T` slice |
| Entities that spawn/despawn (bullets, particles, boids) | `[dynamic]T` |

Procs accept slices for maximum flexibility — both fixed arrays and dynamic arrays convert implicitly:

```odin
count_active :: proc(items: []Bullet) -> int { ... }

count_active(bullets[:])     // dynamic array → slice
count_active(fixed_arr[:])   // fixed array → slice
```

## Iteration

```odin
for bullet, i in bullets {              // bullet is a COPY
	fmt.printfln("bullet %d at %v", i, bullet.pos)
}

for &bullet in bullets {                // & makes it a reference — mutates in place
	bullet.pos += bullet.vel * dt
}

for i in 0 ..< len(bullets) {           // index-based; 0..<n is "up to, excluding"
	// bullets[i] ...
}

for row, y in grid {                    // 2D
	for cell, x in row {
		_ = cell; _ = x; _ = y
	}
}
```

`for x, i in arr` is `arr.forEach((x, i) => ...)`. The `&` variant has no JS equivalent — it's how you mutate the actual element instead of a copy, like iterating with indices and writing `arr[i].pos = ...`. The `0 ..< n` range is Rust-style; there's also inclusive `0 ..= n`.

## Removing elements (the swap-remove trick)

Games constantly delete dead entities. The O(1) idiom used throughout this course:

```odin
// unordered_remove: swaps the last element into slot i, shrinks by one
unordered_remove(&bullets, i)
```

Order isn't preserved, but for bullets/particles nobody cares, and it's vastly cheaper than shifting elements. (`ordered_remove` exists when order matters.)

## Maps, briefly

```odin
high_scores: map[string]int
high_scores["alice"] = 4200
score, ok := high_scores["alice"]   // ok = key existed
defer delete(high_scores)
```

Maps are good to recognize, but this course never needs one — even the boids spatial hash (lesson 8.3) turns out to be faster as flat arrays. Everything here is arrays.

## Where this leads: layout matters

Everything in this lesson stores entities the same way: an array where each struct sits next to its neighbors — `[pos, vel, hp][pos, vel, hp]…`. That's called **Array of Structs (AoS)**, and it's the layout of every entity collection in the first eight modules.

There's a dual: **Struct of Arrays (SoA)** — one array per field (`pos pos pos…`, `vel vel vel…`). Same data, different memory shape, and the difference matters to the CPU cache once you're sweeping thousands of entities per frame. Most languages make you choose by rewriting all your code; Odin has SoA built into the type system (`#soa[dynamic]Bullet`), so switching layouts barely changes your syntax. You'll convert your own 5,000-boid simulation between the two and measure it in [lesson 9.2](../09-game-architecture/02-aos-vs-soa.md). For now: arrays of structs are the right default, and you'll know exactly when they aren't.

## Full listing

Runnable snapshot: [`code/03-collections/main.odin`](code/03-collections/main.odin)

```sh
odin run 01-odin-for-web-devs/code/03-collections
```

## Checkpoint

You can explain the difference between `[8]int`, `[]int`, and `[dynamic]int` in one sentence each, and you know why `for &b in bullets` exists.

## Exercises

1. **Easy:** Create a `Particle` struct (`pos`, `vel: rl.Vector2`, `life: f32`) and a dynamic array of 5 particles. Iterate with `&` and decrease each `life` by `dt` in a loop of 10 fake frames; print lives before and after.
2. **Easy:** Sum a `[10]int` fixed array via a proc taking `[]int`. Pass it with `arr[:]`.
3. **Medium:** Write `remove_dead :: proc(particles: ^[dynamic]Particle)` that swap-removes every particle with `life <= 0`. Careful: when you remove at index `i`, the swapped-in element also needs checking — the classic fix is to *not* increment `i` after a removal.
4. **Medium:** Make a `[3][3]int` tic-tac-toe board, fill it with 0/1/2 values, and write `winner :: proc(board: [3][3]int) -> int` returning the winning player or 0. You just wrote the rules engine of a board game with zero graphics.

**Next:** [1.4 Memory and allocators](04-memory-and-allocators.md)
