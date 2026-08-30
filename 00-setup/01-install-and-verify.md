# 0.1 Install, verify, and open your first window

**Module:** 00-setup

## Goals

- Have a working Odin toolchain you can build and run from the terminal
- Have editor support (the `ols` language server) — optional but recommended
- Open a real raylib window rendered at 60 fps

## New concepts

| Concept | What it is |
|---|---|
| `odin run` | Compile + execute a package in one command |
| `vendor:raylib` | raylib bindings shipped inside the Odin distribution — nothing to install |
| Odin package | A folder of `.odin` files sharing a `package` declaration; the unit of compilation |

## Walkthrough

## Step 1 — Verify Odin is installed

```sh
odin version
```

You should see something like `odin version dev-2026-08:965970af7`. Any recent build works.

If you get `command not found`, install Odin:

```sh
git clone https://github.com/odin-lang/Odin
cd Odin
make release
# add to your shell config (~/.zshrc, ~/.bashrc, ...):
export PATH="$HOME/path/to/Odin:$PATH"
```

Full instructions for every platform live at [odin-lang.org/docs/install](https://odin-lang.org/docs/install/).

🌐 **Web dev callout — where's the package manager?**
> There isn't one, and you won't miss it. Odin ships with a `core:` library (fmt, math, strings, containers…) and a `vendor:` library (raylib, SDL, box2d, stb…). You import them with no install step, no lockfile, no `node_modules`. The compiler is the whole toolchain: compiler, linker driver, and formatter (`odin fmt`) in one binary.

## Step 2 — Editor setup (optional but recommended)

The Odin language server is [ols](https://github.com/DanielGavin/ols). It gives you autocomplete, hover docs, and go-to-definition in VS Code, Neovim, Helix, Zed, and others. If your editor supports LSP, point it at `ols`. If you'd rather skip this for now, everything in this course works fine from the terminal with any text editor.

## Step 3 — Your first window

Create a new folder anywhere, and put this in `main.odin`:

```odin
package main

import rl "vendor:raylib"

main :: proc() {
	rl.InitWindow(800, 450, "My first raylib window")
	defer rl.CloseWindow()

	rl.SetTargetFPS(60)

	for !rl.WindowShouldClose() {
		rl.BeginDrawing()
		rl.ClearBackground(rl.RAYWHITE)
		rl.DrawText("It works!", 350, 210, 20, rl.DARKGRAY)
		rl.EndDrawing()
	}
}
```

Run it:

```sh
odin run .
```

A window opens. It renders text. Press ESC or close the window to exit. **You are now a game developer.**

### Reading the code

Five things happened, and you'll use this exact skeleton in every project:

1. `rl.InitWindow(800, 450, "...")` — opens an 800×450 window with an OpenGL context.
2. `defer rl.CloseWindow()` — `defer` runs when the enclosing proc returns, however it returns. Odin's answer to cleanup; you'll use it constantly.
3. `rl.SetTargetFPS(60)` — raylib paces the loop to 60 iterations per second.
4. `for !rl.WindowShouldClose() { ... }` — the **game loop**. It runs until the user presses ESC or clicks the window's close button.
5. `BeginDrawing` / `ClearBackground` / `DrawText` / `EndDrawing` — every frame: wipe the screen, draw things, present.

> `import rl "vendor:raylib"` is exactly `import * as rl from "vendor:raylib"`. Odin always requires an explicit name for imports, so you always know where a symbol comes from. Also note: raylib's API is `PascalCase` in Odin (`rl.DrawText`, `rl.GetFrameTime`), matching the C library. Odin's own `core:` packages are `snake_case` (`fmt.println`). You'll develop an eye for it within an hour.

## Troubleshooting

- **`undefined: rl.InitWindow` or import errors** — your Odin is very old or the `vendor` collection is missing. Reinstall/update Odin.
- **Linker errors about X11/Wayland on Linux** — install your distro's X11 dev packages (e.g. `sudo pacman -S libx11 libxrandr libxi libxcursor libxinerama` on Arch).
- **A window opens and immediately closes** — check the terminal output; raylib logs warnings there.

## Full listing

Runnable snapshot: [`code/01-hello-window/main.odin`](code/01-hello-window/main.odin)

```sh
odin run 00-setup/code/01-hello-window
```

## Checkpoint

A white-ish window titled "My first raylib window" with centered text, staying open until you close it. The terminal shows only raylib's `INFO` log lines and the CPU stays near idle — raylib is pacing the loop for you.

## Exercises

1. **Easy:** Change the window size and title. Re-run. Notice there's no config file — the window is *code*.
2. **Easy:** Replace `rl.RAYWHITE` with `rl.SKYBLUE`, and draw a second line of text at a different size.
3. **Medium:** Delete `rl.SetTargetFPS(60)` and add `rl.DrawFPS(10, 10)` inside the loop (after `ClearBackground`). Run again and look at the number. That's your machine rendering as fast as it can. Put the line back — uncapped FPS wastes a full CPU core for nothing.

**Next:** [Module 1 — Odin for Web Developers](../01-odin-for-web-devs/01-from-js-to-odin.md)
