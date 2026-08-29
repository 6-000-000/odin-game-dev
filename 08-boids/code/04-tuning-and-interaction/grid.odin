package main

import "core:math"
import rl "vendor:raylib"

// The same uniform spatial-hash grid as lesson 8.3, with one upgrade: the
// perception radius is slider-driven, so cell_size is set at runtime
// (grid_resize). All four arrays are still allocated ONCE, sized for the
// worst case (smallest slider value) — zero per-frame allocation.

Grid :: struct {
	cells_x, cells_y: int,
	cell_size:      f32,
	cell_count:     [dynamic]int,
	cell_start:     [dynamic]int,
	cell_boids:     [dynamic]int,
	cursor:         [dynamic]int,
}

grid_init :: proc(grid: ^Grid, max_cells, max_boids: int) {
	grid.cell_count = make([dynamic]int, max_cells)
	grid.cell_start = make([dynamic]int, max_cells)
	grid.cell_boids = make([dynamic]int, max_boids)
	grid.cursor = make([dynamic]int, max_cells)
}

grid_destroy :: proc(grid: ^Grid) {
	delete(grid.cell_count)
	delete(grid.cell_start)
	delete(grid.cell_boids)
	delete(grid.cursor)
}

// Cell size tracks the (tunable) perception radius: 3x3 cells must always
// cover everything a boid can see. No reallocation — arrays were sized for
// the smallest possible cell size.
grid_resize :: proc(grid: ^Grid, world_w, world_h, cell_size: f32) {
	grid.cell_size = cell_size
	grid.cells_x = int(math.ceil(world_w / cell_size))
	grid.cells_y = int(math.ceil(world_h / cell_size))
}

grid_cell :: proc(grid: ^Grid, pos: rl.Vector2) -> int {
	cx := clamp(int(pos.x / grid.cell_size), 0, grid.cells_x - 1)
	cy := clamp(int(pos.y / grid.cell_size), 0, grid.cells_y - 1)
	return cy * grid.cells_x + cx
}

// Counting-sort bucketing, same four steps as lesson 8.3.
grid_rebuild :: proc(grid: ^Grid, boids: []Boid) {
	cells := grid.cells_x * grid.cells_y
	// 1. zero the buckets (only the active prefix — arrays are worst-case size)
	for &c in grid.cell_count[:cells] {
		c = 0
	}
	// 2. count boids per cell
	for b in boids {
		grid.cell_count[grid_cell(grid, b.pos)] += 1
	}
	// 3. prefix sum
	total := 0
	for i in 0 ..< cells {
		grid.cell_start[i] = total
		total += grid.cell_count[i]
	}
	// 4. fill via cursor pass
	copy(grid.cursor[:cells], grid.cell_start[:cells])
	for _, i in boids {
		cell := grid_cell(grid, boids[i].pos)
		grid.cell_boids[grid.cursor[cell]] = i
		grid.cursor[cell] += 1
	}
}
