package main

import "core:fmt"
import rl "vendor:raylib"

Bullet :: struct {
	pos:    rl.Vector2,
	vel:    rl.Vector2,
	active: bool,
}

count_active :: proc(items: []Bullet) -> int {
	n := 0
	for b in items {
		if b.active do n += 1
	}
	return n
}

main :: proc() {
	// fixed array
	lives := [3]bool{true, true, false}
	fmt.printfln("lives: %v", lives)

	// dynamic array of structs
	bullets: [dynamic]Bullet
	defer delete(bullets)

	append(&bullets, Bullet{pos = {0, 0}, vel = {100, 0}, active = true})
	append(&bullets, Bullet{pos = {50, 20}, vel = {0, 100}, active = true})
	append(&bullets, Bullet{pos = {9, 9}, vel = {0, 0}, active = false})

	fmt.printfln("active before: %d", count_active(bullets[:]))

	// mutate in place with &
	dt: f32 = 1.0 / 60.0
	for &b in bullets {
		b.pos += b.vel * dt
	}
	fmt.printfln("bullet 0 after 1 frame: %v", bullets[0].pos)

	// swap-remove element 0
	unordered_remove(&bullets, 0)
	fmt.printfln("len after unordered_remove: %d (first is now %v)", len(bullets), bullets[0].pos)

	// map
	scores: map[string]int
	defer delete(scores)
	scores["alice"] = 4200
	score, ok := scores["alice"]
	fmt.printfln("alice: %d (found: %t)", score, ok)
	_, ok = scores["bob"]
	fmt.printfln("bob found: %t", ok)
}
