package main

import rl "vendor:raylib"

// The uniform spatial-hash grid from lesson 8.3, unchanged.
// Buckets store boid INDICES — the grid doesn't care how boids are laid out.
// Only the position LOOKUP differs between the two rebuild procs.

Grid :: struct {
	cells_x, cells_y: int,
	cell_size:      f32,
	cell_count:     [dynamic]int,
	cell_start:     [dynamic]int,
	cell_boids:     [dynamic]int,
	cursor:         [dynamic]int,
}

grid_init :: proc(grid: ^Grid, world_w, world_h, cell_size, max_boids: int) {
	grid.cells_x = (world_w + cell_size - 1) / cell_size
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

// AoS rebuild: positions live INSIDE each Boid, interleaved with velocity.
grid_rebuild_aos :: proc(grid: ^Grid, boids: []Boid) {
	for &c in grid.cell_count {
		c = 0
	}
	for b in boids {
		grid.cell_count[grid_cell(grid, b.pos)] += 1
	}
	total := 0
	for count, i in grid.cell_count {
		grid.cell_start[i] = total
		total += count
	}
	copy(grid.cursor[:], grid.cell_start[:])
	for _, i in boids {
		cell := grid_cell(grid, boids[i].pos)
		grid.cell_boids[grid.cursor[cell]] = i
		grid.cursor[cell] += 1
	}
}

// SoA rebuild: positions are a single contiguous column we can pass directly —
// boids.pos[:len(boids)] IS a []rl.Vector2. No struct hopping, one clean stream.
grid_rebuild_soa :: proc(grid: ^Grid, positions: []rl.Vector2) {
	for &c in grid.cell_count {
		c = 0
	}
	for p in positions {
		grid.cell_count[grid_cell(grid, p)] += 1
	}
	total := 0
	for count, i in grid.cell_count {
		grid.cell_start[i] = total
		total += count
	}
	copy(grid.cursor[:], grid.cell_start[:])
	for p, i in positions {
		cell := grid_cell(grid, p)
		grid.cell_boids[grid.cursor[cell]] = i
		grid.cursor[cell] += 1
	}
}
