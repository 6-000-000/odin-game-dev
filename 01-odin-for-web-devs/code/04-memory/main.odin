package main

import "core:fmt"
import "core:mem"
import rl "vendor:raylib"

Player :: struct {
	pos: rl.Vector2,
	hp:  int,
}

heal :: proc(p: ^Player) {
	p.hp = min(p.hp + 25, 100) // auto-deref through the pointer
}

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

	// value semantics: b is a copy of a
	a := rl.Vector2{10, 20}
	b := a
	b.x = 999
	fmt.printfln("a.x = %v (unchanged), b.x = %v", a.x, b.x)

	// pointers: heal mutates the caller's player
	player := Player{pos = {100, 100}, hp = 50}
	heal(&player)
	fmt.printfln("player.hp after heal: %d", player.hp)

	// pattern 1: own it, defer the cleanup
	velocities := make([dynamic]rl.Vector2, 0, 64)
	defer delete(velocities)
	append(&velocities, rl.Vector2{1, 0}, rl.Vector2{0, 1})
	fmt.printfln("velocities: %v", velocities[:])
}
