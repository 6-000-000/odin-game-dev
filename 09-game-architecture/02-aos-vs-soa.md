# 9.2 AoS vs SoA: memory layout is a design decision

**Module:** 09-game-architecture

## Goals

- Understand what a CPU cache line is and why it decides whether your loop is fast
- Know the three canonical layouts — AoS, SoA, AoSoA — and when each wins
- Convert your 5,000-boid simulation from AoS to SoA using Odin's first-class `#soa` types
- Measure the difference on screen — and learn the honest rule for when layout matters

## New concepts

| Concept | What it is |
|---|---|
| Cache line | The 64-byte block CPUs actually fetch; touching 1 byte drags in its 63 neighbors |
| AoS | Array of Structs: `[pos, vel][pos, vel][pos, vel]…` — what you've used all course |
| SoA | Struct of Arrays: `pos pos pos…` over here, `vel vel vel…` over there |
| `#soa` | Odin's built-in SoA container type — same struct, same syntax, different layout |
| Hot/cold fields | Fields a hot loop touches (hot) vs. fields it skips (cold) — drive layout choice |

## Walkthrough

### The real bottleneck

Your 8.3 boids sim runs 5,000 boids by checking ~9 grid cells per boid. (8.3, deliberately not 8.4: the camera, predator, and sliders are interaction chrome — what we're measuring is the flock step, so the snapshot rewinds to the clean 8.3 sim as the control group.) The flocking math is a few dozen FLOPs per neighbor — trivial for a CPU that does billions per second. So where does the time go? **Memory.** Every `boids[j]` fetch is a pointer chase into RAM, and RAM is *slow* relative to the CPU: a cache miss costs as much as a few hundred arithmetic ops.

Here's the part nobody tells web devs: the CPU never fetches one byte. It fetches a **cache line — 64 bytes** — the byte you asked for plus its 63 neighbors, on the bet that you'll need them next. If your data is arranged so neighbors *are* what you need next, every fetch is free. If not, you pay a miss per element.

🌐 **Web dev callout — row store vs column store**
> You've met this exact tradeoff in databases. PostgreSQL is a **row store**: a row's columns sit together, so `SELECT *` by id is one page read — but `AVG(price)` over a million rows drags every *entire row* through memory just to read one column. ClickHouse/Parquet are **column stores**: each column is contiguous, so aggregate scans read only the columns they need and absolutely fly — while "give me whole row 42" becomes a scattered mess. Same data, different layout, different queries win. AoS is the row store (great when you touch all of an entity's fields at once); SoA is the column store (great when you sweep one field across many entities). And just like databases: **the access pattern decides, not fashion.**

### The three layouts, concretely

For `Boid :: struct { pos, vel: rl.Vector2 }` (16 bytes per boid):

```
AoS  [pos.x pos.y vel.x vel.y] [pos.x pos.y vel.x vel.y] …   ← one boid per 16B block
SoA  [pos.x pos.y] [pos.x pos.y] … | [vel.x vel.y] [vel.x vel.y] …   ← one column per array
AoSoA  blocks of 4 AoS boids, columns inside each block (SIMD-shaped; beyond our scope)
```

Every boid in this sim gets *both* fields touched every frame — so which layout wins here? Honest answer: **it might be a wash, and measuring that is the point.** Keep reading.

### Odin's superpower: `#soa`

In C, converting AoS→SoA means rewriting every access site by hand. In Odin, the container type does it:

```odin
boids_aos := make([dynamic]Boid, 0, MAX_BOIDS)        // what module 8 used
boids_soa := make(#soa[dynamic]Boid, 0, MAX_BOIDS)    // ONE keyword different
```

The `Boid` struct is **unchanged**. Element syntax is **unchanged**: `boids_soa[i]` yields a `Boid` value, `boids_soa[i].pos` reads the field. But SoA also gives you the *columns* directly:

```odin
boids_soa.pos[i] = new_pos            // write straight into the pos column
positions: []rl.Vector2 = boids_soa.pos[:len(boids_soa)]  // the column as a slice!
```

That second one is a genuine superpower: the grid rebuild from 8.3 only needs positions, and with SoA you hand it `boids_soa.pos[:len(boids_soa)]` — a ready-made contiguous `[]rl.Vector2` streaming through cache with zero velocity bytes dragged along. (One gotcha: the field of a `#soa[dynamic]` is a multipointer, so slicing needs the explicit `[:len(boids_soa)]` — the compiler will tell you if you forget.)

The full conversion touched only four things:

| What | AoS | SoA |
|---|---|---|
| Container | `[dynamic]Boid` | `#soa[dynamic]Boid` |
| Append | `append(&boids, b)` | `append_soa(&boids, b)` |
| Reset length | `clear(boids)` | `resize_soa(&boids, 0)` |
| Update loop | `for &b, i in boids` (mutate through ref) | index loop with locals, write back `boids.vel[i] = vel` |

The flocking math, the `Boid` struct, the grid (it buckets *indices*, agnostic to layout) — byte-for-byte identical. There's also `soa_zip`/`soa_unzip` for treating existing separate slices as one SoA view, and fixed-size `#soa[N]T` / slice `#soa[]T` forms; see the [overview docs](https://odin-lang.org/docs/overview/#soa-data-types).

### Run the experiment

The snapshot runs both layouts of the *same world* (same fixed seed). **TAB converts the live world between layouts mid-flight** — watch the flock continue seamlessly, because the conversion preserves state exactly:

```odin
copy_aos_to_soa :: proc(dst: ^#soa[dynamic]Boid, src: []Boid) {
	resize_soa(dst, len(src))
	for b, i in src {
		dst[i] = b
	}
}
```

(Its mirror `copy_soa_to_aos` is the same loop in the other direction — resize `boids_aos` to `len(src)`, assign element by element. TAB calls whichever matches the direction, so the flock never loses a beat.)

The HUD shows the current layout, its `update` ms, and the last-measured ms of *both* layouts. Know exactly what that `update` number is before you trust it: a **single-frame** sample — `rl.GetTime()` bracketing the grid rebuild *and* the flock step — with no averaging and no warmup. It will jitter frame to frame (OS scheduling, cache state), so read the *typical* value over a few seconds, not any one frame. And the 1/2/3 keys respawn **only the active layout**; the other rebuilds from it on TAB. That's what keeps both worlds identical for comparison (the seed resets on every respawn for the same reason). Run it:

```sh
odin run 09-game-architecture/code/02-aos-vs-soa -o:speed
```

Press 3 (5,000 boids), let it settle, and TAB back and forth. On most machines the difference here is **modest** — sometimes within noise. That's not a failed experiment; that's the honest result, and understanding *why* is the real lesson:

- Each boid is 16 bytes — **four boids per cache line**. Even AoS, a neighbor fetch usually grabs useful neighbors.
- This sim touches *every field of every boid* every frame. There are no cold fields to skip. SoA's whole advantage — not dragging cold data through cache — has nothing to bite on.

So when does layout actually matter? **When structs get fat or loops get selective.** If `Boid` also carried `color`, `spin`, `health`, a name string (say 64 bytes/boid), the AoS flock step would drag 4× the memory for the same two hot fields, while SoA streams exactly `pos` and `vel`. Same math, 4× the memory traffic — that's when SoA pulls away hard. Layout follows access patterns: profile first, lay out second.

This is also why 8.3's *grid* was the bigger win: it cut the *number* of fetches (algorithmic, ~18×), while layout optimizes the *cost* per fetch (constant factor, ~2–5×). **Algorithm first, layout second, micro-optimizations last** — in that order, always.

## Full listing

Runnable snapshot: [`code/02-aos-vs-soa/`](code/02-aos-vs-soa/) — `main.odin`, `boids.odin`, `grid.odin`, `flock_aos.odin`, `flock_soa.odin`

```sh
odin run 09-game-architecture/code/02-aos-vs-soa -o:speed
```

## Checkpoint

- TAB flips the running world between AoS (sky blue) and SoA (orange) with no visible behavior change — the flock is identical because the *code* is identical
- You can explain why the measured difference is modest for a 16-byte, all-hot boid
- You can state the two conditions under which SoA wins big: fat structs, field-selective loops

## Exercises

1. **Easy:** Note `update` ms at 500/2000/5000 in both layouts. Is SoA ever *slower*? Why might it be? (Hint: the neighbor loop now chases two streams — `pos[j]` and `vel[j]` — instead of one interleaved block.)
2. **Medium:** Add `padding: [6]rl.Vector2` (48 cold bytes) to `Boid` — don't touch it anywhere. Re-measure both layouts at 5,000. Watch AoS fall off a cliff while SoA barely moves. You just manufactured the conditions where layout is *the* optimization.
3. **Medium:** The grid rebuild only reads positions. Time `grid_rebuild_aos` vs `grid_rebuild_soa` separately at 5,000 with the fat struct from exercise 2 — the column-stream version should now win clearly. This is the "hot loop touches one cold-struct field" case in its purest form.
4. **Hard:** Convert Asteroids' particle pool to `#soa` (particles are updated every frame but drawn from only `pos`+`life`). Measure with 10,000 particles. Decide, with numbers, whether the conversion was worth keeping.

**Next:** [9.3 Components and systems](03-components-and-systems.md)
