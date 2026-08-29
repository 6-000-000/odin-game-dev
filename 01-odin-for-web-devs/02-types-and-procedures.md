# 1.2 Types and procedures

**Module:** 01-odin-for-web-devs

## Goals

- Know Odin's core types and when games use each
- Write procedures with parameters, return values, and multiple return values
- Understand `::` vs `:=` vs `=`
- Recognize Odin's error-handling idiom (you'll meet it when loading files)

## New concepts

| Concept | What it is |
|---|---|
| Sized number types | `i32`, `f32`, `u8`… — you pick the size, no `number` abstraction |
| `proc` | The only kind of function. No arrow functions, no `function` keyword |
| Multiple return values | `proc(...) -> (f32, bool)` — used instead of throwing |
| Constants with `::` | Compile-time bindings — also how procs are declared |

## Walkthrough

## The declaration trio

Odin has exactly three ways to bind a name, and you'll internalize them fast:

```odin
SPEED :: 300          // constant: fixed at compile time, never changes
score := 0            // variable: type inferred from the value (int here)
health: f32 = 100     // variable: explicit type, initialized
score = 10            // assignment to an existing variable
```

🌐 **Web dev callout:** `::` ≈ `const` for values the compiler inlines; `:=` ≈ `let` with inference; the explicit `name: Type = value` form is exactly TypeScript's `let name: Type = value`. Odin's `:=` does NOT allow reassignment-declaration like `var` hoisting tricks — one name, one declaration per scope.

## Number types (the ones games actually use)

| Type | Meaning | Typical game use |
|---|---|---|
| `int` | Pointer-sized signed int (64-bit on your machine) | scores, counts, loop indices |
| `i32` | 32-bit signed | raylib API params (`DrawText` x/y/fontSize) |
| `f32` | 32-bit float | **positions, velocities, sizes — the default game number** |
| `f64` | 64-bit float | rarely needed |
| `u8` | 0–255 | color channels |
| `bool` | `true`/`false` — and nothing else | flags, state |

Two conversion rules matter daily:

1. **Untyped constants adapt.** `pos.x += 10` works because `10` becomes `f32` to match `pos.x`.
2. **Variables don't implicitly convert.** Mixing an `int` and an `f32` requires an explicit cast: `f32(score)`, `int(pos.x)`. This is the #1 compile error you'll hit in week one, and the fix is always a cast.

```odin
score := 100
ratio: f32 = 0.5
// bonus := score * ratio        // ERROR: mismatched types
bonus := f32(score) * ratio      // OK
```

## Procedures

```odin
add :: proc(a: int, b: int) -> int {
	return a + b
}

// same types can be grouped:
clamp_speed :: proc(value, min, max: f32) -> f32 {
	if value < min do return min
	if value > max do return max
	return value
}
```

- Parameters are `name: Type`, return type after `->`.
- `if cond do statement` is the one-liner form (no braces needed).
- No function expressions or closures-as-values in the JS sense. Procs are declared at package scope and that's 95% of what this course uses. (Odin does have proc values for advanced use; we won't need them until the boids capstone, if at all.)

## Multiple return values — the error idiom

Instead of exceptions, Odin procs return results plus an `ok` flag:

```odin
import "core:strconv"

parse_score :: proc(text: string) -> (int, bool) {
	value, ok := strconv.parse_int(text)
	if !ok {
		return 0, false
	}
	return value, true
}

main :: proc() {
	score, ok := parse_score("1500")
	if ok {
		// use score
	}
}
```

You'll see this constantly in the standard library: `value, ok := thing(...)`. There's no try/catch, no stack unwinding — the error is a value and you handle it right there. In this course, file loading (save files in Snake, textures later) is where you'll use it.

## Strings, briefly

`string` in Odin is an immutable read-only slice of bytes (UTF-8 by convention). Comparisons (`==`) work as you'd expect. Concatenation allocates — fine in menus, avoid per-frame in hot loops. For per-frame UI text like scores, we use raylib's `rl.TextFormat`, which formats into a reused static buffer — no allocation:

```odin
rl.DrawText(rl.TextFormat("Score: %d", score), 10, 10, 20, rl.WHITE)
```

One quirk to know: raylib is a C library and takes `cstring` (null-terminated). **String literals coerce automatically**, so `rl.DrawText("Hello", ...)` just works. Built-up dynamic strings need conversion (`strings.clone_to_cstring`) — you won't need it in this course thanks to `rl.TextFormat`.

## Full listing

Runnable snapshot: [`code/02-types-and-procs/main.odin`](code/02-types-and-procs/main.odin) — exercises every concept above.

```sh
odin run 01-odin-for-web-devs/code/02-types-and-procs
```

Expected output:

```
add(2, 3) = 5
clamp_speed(500, 0, 300) = 300
bonus = 50
parsed = 1500 (ok = true)
parsed bad input ok = false
```

## Checkpoint

You can read `paddle_speed: f32 = 400` and `clamp :: proc(v, lo, hi: f32) -> f32` fluently, and you know why `f32(score)` exists.

## Exercises

1. **Easy:** Write `lerp :: proc(a, b, t: f32) -> f32` returning `a + (b - a) * t`. This is the single most-used formula in game feel work; verify `lerp(0, 100, 0.25) == 25`.
2. **Easy:** Write `vec_len :: proc(x, y: f32) -> f32` returning the vector length (you'll need `math.sqrt` from `core:math` — import it).
3. **Medium:** Write `rects_overlap :: proc(ax, ay, aw, ah, bx, by, bw, bh: f32) -> bool` implementing AABB overlap: true when `ax < bx+bw && ax+aw > bx && ay < by+bh && ay+ah > by`. You just wrote Pong's collision detection before learning what AABB means.
4. **Medium:** Extend `parse_score`-style thinking: write `safe_div :: proc(a, b: f32) -> (f32, bool)` that refuses division by near-zero (`abs(b) < 0.0001`; `abs` is in `core:math`). Callers must handle the `false` case.

**Next:** [1.3 Structs, arrays, and slices](03-structs-slices-arrays.md)
