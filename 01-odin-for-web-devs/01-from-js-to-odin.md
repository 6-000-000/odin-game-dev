# 1.1 From JavaScript to Odin

**Module:** 01-odin-for-web-devs

## Goals

- Understand the fundamental differences between the JS runtime model and Odin's compiled-native model
- Know the workflow: write → `odin run` → native binary
- Write and run your first console program in Odin

## New concepts

| Concept | What it is |
|---|---|
| AOT compilation | Your code becomes a native executable before it runs — no VM, no interpreter |
| `package` | Every `.odin` file starts with a package name; a folder = one package = one build unit |
| `main :: proc()` | The entry point — like a top-level script that runs once |
| `core:fmt` | Odin's standard formatting/printing package |

## Walkthrough

## The mental shift

JavaScript runs on a virtual machine that JIT-compiles your code while it executes, manages memory with a garbage collector, and (in the browser) gives you a giant host environment: DOM, events, fetch, timers.

Odin is **ahead-of-time compiled** to machine code — like C, because culturally it *is* C's successor. When you run `odin run .`, three things happen:

1. The compiler type-checks your whole package (fast — Odin compiles hundreds of thousands of lines in seconds).
2. It emits a native executable through LLVM.
3. It runs the executable.

Step 1 is important: **if it compiles, entire categories of bugs are already impossible.** There is no `undefined is not a function` at runtime. Misspelled field? Compile error. Wrong argument count? Compile error. Missing import? Compile error. You get TypeScript's strictness — enforced absolutely, with no escape hatches like `any`.

🌐 **Web dev callout — the toolchain comparison**
>
> | Web | Odin |
> |---|---|
> | `node script.js` / `bun run` | `odin run .` |
> | `tsc` type-check | the compiler itself — no separate step |
> | npm + package.json + node_modules | nothing — `core:` and `vendor:` ship with the compiler |
> | prettier | `odin fmt` (same binary) |
> | bundler (vite/webpack) | the compiler — output is a single native binary |
>
> The entire toolchain is one ~5 MB binary called `odin`.

## Your first program

No window this time — just text, to prove the workflow. Create `main.odin` in a fresh folder:

```odin
package main

import "core:fmt"

main :: proc() {
	name := "web developer"
	year := 2026

	fmt.println("Hello from Odin!")
	fmt.printf("%s, welcome. The year is %d.\n", name, year)
	fmt.printfln("2 + 2 = %d", 2 + 2)
}
```

```sh
odin run .
```

Output:

```
Hello from Odin!
web developer, welcome. The year is 2026.
2 + 2 = 4
```

### Reading the code

- `package main` — every file starts with its package. `main` is conventional for executables.
- `import "core:fmt"` — import from the core library. Note there's no alias: the package name (`fmt`) becomes the prefix automatically. You *can* alias (`import f "core:fmt"`), but for `core:` packages you rarely do.
- `main :: proc() { }` — `::` declares a **constant** whose value is a procedure. `main` is the entry point.
- `name := "web developer"` — `:=` declares a variable with inferred type (`string` here). Like `let`, but typed forever.
- `fmt.println`, `fmt.printf`, `fmt.printfln` — print with newline, print formatted, print formatted with newline. `%s`/`%d` are C-style verbs; Odin also has `%v` (any value) and `%t` (bool).

## Things that will feel different, honestly

**No semicolons needed... just kidding, Odin doesn't need them either.** But Odin uses `{}` blocks with mandatory braces — no single-line `if` without braces (there is `if x do y` for one-liners, which you'll see later).

**No truthiness.** `if x` requires `x` to be a `bool`. `if len(arr) > 0`, not `if arr.length`. This feels strict for a day, then it prevents a bug and you forgive it.

**No exceptions.** Procedures return errors as values. You'll see the idiom in lesson 1.2. For this course, raylib functions mostly can't fail in ways we handle — but file loading in later modules will show the pattern.

**No `null`, no `undefined`.** There's `nil` for pointers/slices/maps, but a plain `int` or `struct` is always a real value. Zero values are meaningful: an uninitialized `f32` is `0`, a `bool` is `false`, a `string` is `""`.

**No classes, no prototypes, no `this` magic.** Structs hold data; procedures operate on them. That's the whole object model, and it's enough to build everything in this course.

**Indentation is tabs** by convention (gofmt-style, enforced by `odin fmt`). The compiler doesn't care; your teammates do.

## Compile only, no run

During the course you'll sometimes want to just check that code compiles:

```sh
odin check .        # type-check only, fastest
odin build .        # produce a binary (named after the folder)
odin run . -o:speed # optimized build + run (for performance work)
```

## Full listing

Runnable snapshot: [`code/01-hello-console/main.odin`](code/01-hello-console/main.odin)

```sh
odin run 01-odin-for-web-devs/code/01-hello-console
```

## Checkpoint

Terminal output matches the example above. You can edit the strings and re-run without thinking about it.

## Exercises

1. **Easy:** Print your name and the number of years you've been programming, using `fmt.printfln` and two variables.
2. **Easy:** Try `fmt.printf("%v\n", some_struct_or_number)` — `%v` prints anything. Feed it a `bool`, an `f32`, and a string.
3. **Medium:** Intentionally break the code three ways: misspell `println`, remove the import, assign `name := 42` then print with `%s`. Read each compile error carefully. Odin's error messages are genuinely good — learning to read them now pays off for the whole course.

**Next:** [1.2 Types and procedures](02-types-and-procedures.md)
