package game

import "core:fmt"
import "core:math/rand"
import rl "vendor:raylib"

main :: proc() {
	// raylib's integer dice — no seeding needed
	fmt.printfln("d20 roll: %d", rl.GetRandomValue(1, 20))

	// core:math/rand — seed for reproducible runs
	rand.reset(12345)
	fmt.printfln("float in [200, 400): %v", rand.float32_range(200, 400))

	// uses roll_dice from dice.odin — same package, no import
	rolls := roll_dice(3, 6)
	fmt.printfln("3d6: %v", rolls)
}
