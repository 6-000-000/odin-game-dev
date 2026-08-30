# 1.4 Memory and allocators

**Module:** 01-odin-for-web-devs

## Goals

- Understand stack vs heap at a working level
- Use pointers without fear: `^T`, `&`, auto-deref
- Know Odin's value semantics: assignment copies
- Manage dynamic memory with `make`/`delete` — and *prove* there are no leaks with the tracking allocator
- Stop worrying: 90% of this course needs none of the fancy parts

## New concepts

| Concept | What it is |
|---|---|
| Value semantics | Assignment copies data. `b := a` gives `b` its own copy |
| Pointer `^T` | An address of a value. Explicit, and you rarely need one |
| Allocator | The thing `make` asks for memory — explicit, swappable |
| Tracking allocator | A debug wrapper that reports leaks at exit |

## Walkthrough

## Value semantics: the default that changes how you write code

```odin
a := rl.Vector2{10, 20}
b := a          // b is a COPY
b.x = 999
fmt.println(a.x)  // still 10
```

Everything in Odin behaves this way: structs, fixed arrays, numbers. Assignment and proc arguments copy. (Slices, dynamic arrays, and maps are the exception: copying them copies the *header* — pointer+len — so the underlying data is shared. Same as JS arrays, conveniently.)

🌐 **Web dev callout — this is backwards from JS**
> In JS, primitives copy and objects share (by reference). In Odin, *everything* copies — including structs — unless you explicitly share via a pointer or slice header. This kills the whole class of "spooky mutation at a distance" bugs: when you pass an entity to a proc, the proc gets its own copy and can't hurt yours. When you *want* shared mutation, the `^` in the signature advertises it.

## Pointers, the friendly version

```odin
heal :: proc(p: ^Player) {
	p.hp = min(p.hp + 25, 100)   // auto-deref: no (*p) syntax
}

heal(&player)   // & takes the address
```

Three rules cover everything this course needs:

1. `^T` in a proc signature means "I will mutate your value" (like TS `function heal(p: Player)` *with* the mutation actually visible to the caller).
2. `&x` takes the address of `x`.
3. Accessing fields through a pointer is just `p.field` — Odin auto-dereferences.

You'll also see `&` in `for &b in bullets` (mutate in place) and in `append(&bullets, x)` (append must be able to grow/reallocate your array).

## Stack vs heap, in two sentences

Local variables live on the **stack**: freed automatically when the proc returns, zero cost. `make`/`new` allocate on the **heap**: they survive until you `delete`/`free` them. Odin has **no garbage collector** — heap memory you allocate is yours to release.

## The whole game, in three patterns

That's it for the scary part. Every project in this course uses one of these three patterns:

**Pattern 1 — own it, defer the cleanup:**

```odin
bullets := make([dynamic]Bullet, 0, 64)   // capacity 64
defer delete(bullets)                      // freed when main returns
```

**Pattern 2 — structs on the stack, no allocation at all:**

```odin
player := Player{pos = {100, 100}, hp = 100}   // nothing to free. Most entities.
```

**Pattern 3 — raylib resources have their own Load/Unload pairs:**

```odin
texture := rl.LoadTexture("ship.png")
defer rl.UnloadTexture(texture)   // GPU memory, freed with raylib's own call — not delete
```

## Prove you didn't leak: the tracking allocator

For peace of mind (and to impress your future self), Odin's core library ships a debug allocator that records every allocation and reports what wasn't freed. Standard boilerplate at the top of `main`:

```odin
import "core:mem"

main :: proc() {
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)
		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintfln("=== %v allocations not freed: ===", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintfln("- %v bytes at %v", entry.size, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	// ... your game ...
}
```

Run with `odin run . -debug` (debug is the default for `odin run`), and if your program exits with unfreed allocations, you get a list with exact source locations. `when ODIN_DEBUG { ... }` is a compile-time conditional — release builds skip this entirely, zero cost.

> Closest analogue: a `fetch` interceptor, but for memory. Every `make` in Odin goes through `context.allocator` — an implicit "context" value threaded through your program (Odin's answer to dependency injection). Swapping it for the tracking allocator is like wrapping `fetch` to log requests. Games exploit this hard: per-frame temporary allocations go to a `temp_allocator` that resets each frame — but you won't need that until you're optimizing, and maybe not even then.

## What about use-after-free and all the C horror stories?

Odin prevents the worst by design: no implicit pointer arithmetic, bounds-checked array/slice indexing (a wrong index panics with a message instead of corrupting memory), and a culture of value semantics. You can still shoot your foot with raw pointers — but this course simply doesn't go there.

## Full listing

Runnable snapshot: [`code/04-memory/main.odin`](code/04-memory/main.odin) — includes the tracking allocator; try deleting a `delete` and watch it catch you.

```sh
odin run 01-odin-for-web-devs/code/04-memory
```

## Checkpoint

You can state what copies and what shares (structs copy; slices/dynamic arrays/maps share the backing data). You know `^T` = "I mutate", `&x` = address, and you have leak-detection boilerplate you can paste into any project.

## Exercises

1. **Easy:** Predict, then verify: pass a `Player` struct (not a pointer) to a proc that sets `hp = 0`. Print `hp` after the call. Then change the signature to `^Player` and pass `&player`. Print again.
2. **Easy:** Allocate a dynamic array with `make([dynamic]f32, 0, 10)`, *forget* the `delete`, run with the tracking allocator active, and read the leak report. Then fix it.
3. **Medium:** Write `split_even_odd :: proc(nums: []int) -> (evens, odds: [dynamic]int)` that appends into two new dynamic arrays. The *caller* owns them — document that in a comment and `defer delete` both at the call site. Returning allocated collections is the one case where "who frees what?" needs a convention; "caller frees" is the usual one.

**Next:** [1.5 Packages, the core library, and randomness](05-packages-and-random.md)
