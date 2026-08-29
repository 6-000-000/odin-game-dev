package main

import "core:fmt"
import "core:strconv"

add :: proc(a: int, b: int) -> int {
	return a + b
}

clamp_speed :: proc(value, min, max: f32) -> f32 {
	if value < min do return min
	if value > max do return max
	return value
}

parse_score :: proc(text: string) -> (int, bool) {
	value, ok := strconv.parse_int(text)
	if !ok {
		return 0, false
	}
	return value, true
}

main :: proc() {
	fmt.printfln("add(2, 3) = %d", add(2, 3))
	fmt.printfln("clamp_speed(500, 0, 300) = %v", clamp_speed(500, 0, 300))

	// explicit conversion between int and f32
	score := 100
	ratio: f32 = 0.5
	bonus := f32(score) * ratio
	fmt.printfln("bonus = %v", bonus)

	// multiple return values
	parsed, ok := parse_score("1500")
	fmt.printfln("parsed = %d (ok = %t)", parsed, ok)

	_, ok2 := parse_score("not a number")
	fmt.printfln("parsed bad input ok = %t", ok2)
}
