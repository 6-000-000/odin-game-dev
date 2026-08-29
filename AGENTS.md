# AGENTS.md

Markdown course teaching 2D gamedev with Odin + raylib to a senior web dev. Content = lesson `.md` files in module folders (`NN-name/`) + runnable Odin snapshots under each module's `code/`. There is no app, build system, or package manifest — the "build" is compiling the snapshots.

## Verification (do this after ANY change to `.odin` or lesson links)

```sh
odin check <snapshot-dir>        # type-check one snapshot; MUST be zero errors
odin build <snapshot-dir> -o:speed -out:/tmp/x   # also LINK; required for snapshots using raygui (08-boids/04, 09-game-architecture/04) — check alone misses link errors
odin run <dir> -o:speed          # run; perf snapshots (08-boids/03+, 09-game-architecture/02) need -o:speed
```

- Every snapshot is a standalone `package main` dir. All 36 must pass: `for d in */code/*/; do odin check "$d"; done`
- First `odin check` in a fresh dir can stall ~2 min (package cache build); afterwards ~1s. Don't kill it prematurely.
- This is a desktop (Hyprland) machine: do NOT `odin run` windowed snapshots to "test" them — it pops windows on the user's screen. Compile-verify only.
- Link check after editing markdown: every relative link must resolve (README's curriculum map links every lesson; adding/renaming a lesson means updating README + the previous lesson's `**Next:**` line).

## Odin API landmines (verified against odin dev-2026-08 at ~/tools/Odin)

- `import rl "vendor:raylib"` — vendored, no system raylib install. raygui is INSIDE package raylib (`rl.GuiSlider(...)`), not a separate package.
- `for &x in [2]T{a, b}` does NOT compile (can't reference a composite literal) — bind to a named local first, then iterate.
- Seed RNG with `rand.reset(seed)`. `rand.set_global_seed` does not exist.
- `rl.TextFormat` uses a static buffer: never two calls in one expression. Assign to a variable first if reused.
- Constant arrays can't be indexed at runtime (`Cannot index a constant`) — lookup tables (levels, tier radii) must be variables (`:=` not `::`).
- `#soa[dynamic]T` field access yields a multipointer — a slice needs explicit length: `boids.pos[:len(boids)]`.
- `for &x in arr` yields a reference, not a pointer; `&x` gives the real pointer.
- `os.write_entire_file` returns `Error` with `@(require_results)` — must `_ =` or handle it.

## Content conventions (enforced by QA checks; new lessons must match)

- Every teaching lesson has ALL of: `## Goals`, `## New concepts` (table), `## Walkthrough`, `## Full listing` (links its snapshot + `odin run` command), `## Checkpoint`, `## Exercises` (graded Easy/Medium/Hard), final `**Next:**` line — and exactly one `🌐 **Web dev callout**` blockquote (JS/TS analogy for the lesson's key idea). `10-next-steps` is exempt (resources page).
- Snapshots are COMPLETE runnable programs, never diffs; each builds on the previous lesson's snapshot.
- No binary assets anywhere: shapes/procedural textures only; sound = the `make_beep` WAV synthesizer copied from `03-pong/code/04-polish/main.odin`.
- Code style: tabs, `import rl "vendor:raylib"` (raylib is PascalCase; `core:` is snake_case), screen/layout values as `::` constants, HUD drawn last, state machines as `enum` + `switch` in update AND draw.
- Voice: senior-dev-to-senior-dev, no intro-to-programming explanations.
