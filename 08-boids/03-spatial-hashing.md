# 8.3 Spatial hashing: from 150 to 2,000+

**Module:** 08-boids

## Goals

- Replace the full flock scan with a **uniform spatial-hash grid**
- Bucket boids with a **counting sort** over flat arrays — zero per-frame allocation
- Query neighbors by scanning the 3×3 cells around a boid (wrapped, toroidal)
- Verify the flocking math is *unchanged* — only the neighbor source changed
- Run 2,000–5,000 boids and read the difference in `update_ms`

## New concepts

| Concept | What it is |
|---|---|
| Spatial hash grid | World cut into `cell_size` squares; each boid lives in exactly one bucket |
| `cell_size = perception_radius` | Guarantees the 3×3 cells around a boid cover everything it can possibly see |
| Counting sort | Count → prefix-sum → scatter: sorts boids by cell in O(n), no comparisons |
| Prefix sum | `cell_start[i]` = index where cell *i*'s boids begin in the flat array |
| Multi-file package | `main.odin` / `boids.odin` / `grid.odin` share `package main` — no imports between them |
| `-o:speed` | Release build: debug builds of this sim are ~10× slower |

## Walkthrough

### The idea: stop checking boids you can't see

A boid's world is 75 px wide. The other 1,950 boids on a 1280×720 screen are *irrelevant* to it — yet the naïve loop measures the distance to every one of them. The fix is the classic CPU-side acceleration structure (the same win Lague gets from his GPU compute shader, achieved the standard CPU way): **bucket boids by position once per frame, then only look inside nearby buckets.**

```
cell size = perception radius (75 px)
┌─────┬─────┬─────┬─────┐
│     │     │     │     │
├─────┼─────┼─────┼─────┤
│     │ ·   │  ·  │     │   boid ● lives in one cell
├─────┼──●──┼─────┼─────┤   neighbors can only be in the
│     │ · · │  ·  │     │   3×3 cells around it (shaded)
├─────┼─────┼─────┼─────┤   → scan ~30 candidates, not 2,000
└─────┴─────┴─────┴─────┘
```

Why must `cell_size` equal the perception radius? A boid can see up to 75 px in any direction. If cells are 75 px wide, then *anything* within 75 px is guaranteed to be in the boid's cell or an adjacent one — the 3×3 block is a superset of the vision circle. Smaller cells would miss neighbors; larger cells would scan more dead space. Exact fit.

This is also the moment the project outgrows one file. Odin multi-file packages need zero ceremony: all files in the folder share `package main` and see each other's declarations directly — `main.odin` calls `grid_rebuild` from `grid.odin` with no import. (You learned this in lesson 1.5; this is the first project that actually splits.)

### `grid.odin`: counting-sort bucketing

We need, per frame: boid indices grouped by cell. The naïve tool is a map from cell to a list of boids — and it's a trap: per-frame map churn means per-frame allocation. The standard trick is a **counting sort** over four flat arrays, allocated *once* and refilled every frame:

```odin
grid_rebuild :: proc(grid: ^Grid, boids: []Boid) {
	// 1. zero the buckets
	for &c in grid.cell_count {
		c = 0
	}
	// 2. count boids per cell
	for b in boids {
		grid.cell_count[grid_cell(grid, b.pos)] += 1
	}
	// 3. prefix sum: cell_start[i] = index where cell i's boids begin
	total := 0
	for count, i in grid.cell_count {
		grid.cell_start[i] = total
		total += count
	}
	// 4. fill: scatter boid indices into their cell's run (cursor pass)
	copy(grid.cursor[:], grid.cell_start[:])
	for _, i in boids {
		cell := grid_cell(grid, boids[i].pos)
		grid.cell_boids[grid.cursor[cell]] = i
		grid.cursor[cell] += 1
	}
}
```

Walk the tiny example in the code comment: boids `[0 1 2 3 4]` live in cells `[1 0 1 2 1]`. Counts are `[1 3 1]`; prefix sums give starts `[0 1 4]`; the fill pass scatters indices into runs — cell 1 owns `cell_boids[1..<4]` = boids `{0, 2, 4}`. After the rebuild, *"the boids in cell c"* is the slice `cell_boids[start[c] ..< start[c]+count[c]]`. No map, no pointers, no allocation — three linear passes.

The arrays come from `grid_init` with `make([dynamic]int, ...)` + `defer grid_destroy(&grid)`: `cell_count`, `cell_start`, `cursor` sized `cells_x * cells_y` (18×10 = 180 on our screen), `cell_boids` sized `MAX_BOIDS`. Allocation happens at startup, never in the loop.

### `boids.odin`: same flock, new neighbor source

Here's the teaching moment of the whole module — the update loop is **visually identical to lesson 8.2 except for how `j` is found**. The inner scan went from `for other, j in boids` to:

```odin
// perceive: scan the 3×3 cells around my cell — indices wrap modulo
// the grid so edge boids see across the seam (toroidal world).
cx := clamp(int(b.pos.x / grid.cell_size), 0, grid.cells_x - 1)
cy := clamp(int(b.pos.y / grid.cell_size), 0, grid.cells_y - 1)
for dy in -1 ..= 1 {
	for dx in -1 ..= 1 {
		gx := (cx + dx + grid.cells_x) % grid.cells_x
		gy := (cy + dy + grid.cells_y) % grid.cells_y
		cell := gy * grid.cells_x + gx
		start := grid.cell_start[cell]
		for k in start ..< start + grid.cell_count[cell] {
			j := grid.cell_boids[k]
			if i == j do continue
			other := boids[j]
			// ... IDENTICAL accumulate/steer/integrate math from 8.2
		}
	}
}
```

The `(x + cells_x) % cells_x` wrap makes the 3×3 scan toroidal: a boid in the rightmost column scans the leftmost column, where — thanks to our wrap-aware `offset()` helper — it genuinely finds the boids sitting just across the seam. Everything below the scan (the `sep`/`align_sum`/`coh_sum` accumulators, the three `steer_toward` calls, the clamp-integrate-wrap tail) is byte-for-byte lesson 8.2. **The optimization changed the data structure, not the algorithm** — same rules, same weights, same flock behavior, radically fewer pair checks.

### `main.odin`: presets and honesty about build modes

Preallocate the boid array once at max capacity, then let keys switch presets. Note the container: `[dynamic]Boid` — every boid's fields sit adjacent in memory, one boid after another. That's an *Array of Structs*, and it's quietly been the layout of every entity array in the course. Lesson 9.2 converts this very sim to the dual layout (Struct of Arrays, one keyword in Odin) and measures the difference:

```odin
boids := make([dynamic]Boid, 0, MAX_BOIDS) // capacity once, never reallocates
defer delete(boids)
spawn_boids(&boids, 2000, settings)
...
if rl.IsKeyPressed(.ONE) do spawn_boids(&boids, 500, settings)
if rl.IsKeyPressed(.TWO) do spawn_boids(&boids, 2000, settings)
if rl.IsKeyPressed(.THREE) do spawn_boids(&boids, 5000, settings)
```

`spawn_boids` `clear`s and re-appends — the backing memory never moves, so keys 1/2/3 cost nothing but the spawn itself.

Measured on one machine (update only, `update_ms` is rebuild + flock step — *measure on yours*):

| sim | boids | debug build | `-o:speed` |
|---|---|---|---|
| naïve (8.2) | 150 | ~0.4 ms | ~0.1 ms |
| naïve (8.2) | 400 | ~2.5 ms | ~0.4 ms |
| naïve (8.2) | 2,000 | ~62 ms (16 fps) | ~11 ms |
| **grid (8.3)** | 500 | ~0.7 ms | ~0.2 ms |
| **grid (8.3)** | 2,000 | ~8 ms | ~3 ms |
| **grid (8.3)** | 5,000 | ~46 ms | ~15 ms |

Two lessons in that table. First, the algorithmic win: the grid does 2,000 boids cheaper than the naïve loop does 400 — and at 5,000 boids it's still ~13× fewer pair checks than naïve-at-2,000 would need (naïve 5,000 would be ~25M checks/frame; it doesn't fit in the table because it doesn't fit in a frame). Second: **debug builds are slow**. Odin's default build keeps bounds checks and no inlining; for this sim it's ~6–10× slower. Whenever you're measuring or showing off, ship `-o:speed`:

```sh
odin run 08-boids/code/03-spatial-hashing -o:speed
```

🌐 **Web dev callout — you just hand-wrote a database index**
> The naïve loop is a full table scan: `SELECT * FROM boids WHERE distance < 75`, per boid, per frame. The grid is a hash index on a partition key: bucket by `cell`, and the same query touches one bucketful of rows. Postgres's `PARTITION BY`, Cassandra's partition keys, Elasticsearch shards — all the same move: pay a small O(n) bucketing cost up front so every query is O(bucket) instead of O(table). You even did it allocation-free with a counting sort, which is more than most databases can claim.

## Full listing

Runnable snapshot: [`code/03-spatial-hashing/`](code/03-spatial-hashing/) — [`main.odin`](code/03-spatial-hashing/main.odin), [`boids.odin`](code/03-spatial-hashing/boids.odin), [`grid.odin`](code/03-spatial-hashing/grid.odin)

```sh
odin run 08-boids/code/03-spatial-hashing
odin run 08-boids/code/03-spatial-hashing -o:speed   # for real measurements
```

## Checkpoint

2,000 boids flock smoothly — rivers of triangles that braid, split at the seams, and rejoin. Keys 1/2/3 respawn 500 / 2,000 / 5,000 boids, and `update` stays in single-digit milliseconds where lesson 8.2's naïve loop needed ~62 ms for 2,000. Behavior should look *identical* to 8.2 — if the flock acts differently, the bug is in the query, not the rules.

## Exercises

1. **Easy:** Count candidates scanned per frame (increment a counter in the innermost loop) and print `candidates / boids` — the average neighborhood size. Compare with the naïve loop's fixed `n − 1`. At 2,000 boids you should see ~100× fewer checks.
2. **Medium:** Debug view: draw the grid lines (`DrawLine` every `cell_size`) and highlight the 3×3 cells around the boid nearest the mouse. Watching the shaded block follow the boid makes the query click.
3. **Medium:** Cell-size experiment: rebuild the grid with `CELL_SIZE` = 37 (half perception) and 150 (double). One misses neighbors (broken flocking — why?), the other scans more dead space (slower — measure it). This is why cell = perception radius.
4. **Hard:** Remove the square roots: compare `Vector2LengthSqr(to_other)` against `d*d` precomputed from the radii, and compare `sep`/`coh` math accordingly (careful: `coh_sum/count` still needs real vectors — only the *distance tests* change). Measure the difference at 5,000 boids. Then look at `update_boids` and decide if the readability cost was worth it.

**Next:** [8.4 Tuning, camera, and a predator](04-tuning-and-interaction.md)
