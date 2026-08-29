package main

import "core:fmt"

main :: proc() {
	name := "web developer"
	year := 2026

	fmt.println("Hello from Odin!")
	fmt.printf("%s, welcome. The year is %d.\n", name, year)
	fmt.printfln("2 + 2 = %d", 2 + 2)
}
