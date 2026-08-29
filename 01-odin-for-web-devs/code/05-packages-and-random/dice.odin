package game

import "core:math/rand"

// Visible to every file in this package — no export keyword needed.
roll_dice :: proc(count, sides: int) -> []int {
	rolls := make([]int, count)
	for i in 0 ..< count {
		rolls[i] = 1 + int(rand.int31_max(i32(sides)))
	}
	return rolls
}
