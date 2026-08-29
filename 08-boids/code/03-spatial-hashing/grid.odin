package main

import rl "vendor:raylib"

// A uniform spatial-hash grid: the world is cut into cell_size squares and
// every boid lands in exactly one bucket. Neighbor queries then scan the 3x3
// cells around a boid instead of the entire flock — cell_size equals the
// perception radius, so 3x3 cells always cover everything a boid can see.
//
// Bucketing is a COUNTING SORT over flat arrays, refilled every frame with
// ZERO per-frame allocation: all four arrays are allocated once in
// grid_init and reused forever.

Grid :: struct {
	cells_x, cells_y: int, // grid dimensions in cells
	cell_size:      f32, // MUST equal Settings.perception_radius
	cell_count:     [dynamic]int, // boids per cell            (len cells_x*cells_y)
	cell_start:     [dynamic]int, // where each cell's run begins (len cells_x*cells_y)
	cell_boids:     [dynamic]int, // boid indices, sorted by cell  (len max_boids)
	cursor:         [dynamic]int, // fill-pass scratch         (len cells_x*cells_y)
}

grid_init :: proc(grid: ^Grid, world_w, world_h, cell_size, max_boids: int) {
	grid.cells_x = (world_w + cell_size - 1) / cell_size // round up
	grid.cells_y = (world_h + cell_size - 1) / cell_size
	grid.cell_size = f32(cell_size)
	cells := grid.cells_x * grid.cells_y
	grid.cell_count = make([dynamic]int, cells)
	grid.cell_start = make([dynamic]int, cells)
	grid.cell_boids = make([dynamic]int, max_boids)
	grid.cursor = make([dynamic]int, cells)
}

grid_destroy :: proc(grid: ^Grid) {
	delete(grid.cell_count)
	delete(grid.cell_start)
	delete(grid.cell_boids)
	delete(grid.cursor)
}

grid_cell :: proc(grid: ^Grid, pos: rl.Vector2) -> int {
	cx := clamp(int(pos.x / grid.cell_size), 0, grid.cells_x - 1)
	cy := clamp(int(pos.y / grid.cell_size), 0, grid.cells_y - 1)
	return cy * grid.cells_x + cx
}

// Counting-sort bucketing, rebuilt from scratch each frame:
//
//	boid indices before:  [0 1 2 3 4]        cell_of[boid]: [1 0 1 2 1]
//	cell_count:           [1 3 1]            (how many boids per cell)
//	cell_start:           [0 1 4]            (prefix sum of counts)
//	cell_boids after:     [1 | 0 2 4 | 3]    (boids grouped by cell)
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
	// 4. fill: scatter boid indices into their cell's run, using a copy of
	//    cell_start as per-cell write cursors
	copy(grid.cursor[:], grid.cell_start[:])
	for _, i in boids {
		cell := grid_cell(grid, boids[i].pos)
		grid.cell_boids[grid.cursor[cell]] = i
		grid.cursor[cell] += 1
	}
}
