# 4.3 Lives, levels, and level data

**Module:** 04-breakout

## Goals

- Give the player three lives, drawn as ball icons; a lost ball respawns stuck on the paddle
- Bring back Pong's enum + switch state machine, extended with a `Win` state
- Define levels as **data** — arrays of strings — and parse them into the brick grid
- Chain levels: clear one, load the next, win after the last

## New concepts

| Concept | What it is |
|---|---|
| `Game_State` (encore) | The same enum + switch as Pong 3.3, in update *and* draw, now with `.Win` |
| Lives | A counter, icons top-right; zero means game over |
| Level as data | A level is `[BRICK_ROWS]string` — one character per brick, `.` for empty |
| Parser | Nested loops over rows and characters, mapping chars to bricks |
| Data-driven design | Game content edited as data; the code never changes per level |

## Walkthrough

### The state machine returns

Same shape as Pong 3.3 — an enum, one switch in update, one in draw:

```odin
Game_State :: enum {
	Title,
	Playing,
	Game_Over,
	Win,
}
```

`.Title` resets everything and starts; `.Game_Over` and `.Win` wait for SPACE and go back to the title. All the gameplay from lesson 4.2 moves under `case .Playing:` untouched.

The draw switch is new in this module, so here it is in full. It leans on `draw_centered` — Pong 3.3's `MeasureText` helper, ported verbatim — which also takes over the "SPACE to serve" hint from lesson 4.1:

```odin
switch state {
case .Title:
	draw_centered("BREAKOUT", 200, 80, rl.WHITE)
	draw_centered("A/D or arrows to move — SPACE to start", 320, 20, rl.GRAY)
case .Playing:
	rl.DrawCircleV(ball.pos, BALL_RADIUS, rl.WHITE)
	if ball.stuck do draw_centered("SPACE to serve", SCREEN_H / 2 + 80, 20, rl.GRAY)
case .Game_Over:
	draw_centered("GAME OVER", 200, 70, rl.RED)
	draw_centered("SPACE for menu", 300, 20, rl.GRAY)
case .Win:
	draw_centered("YOU WIN!", 200, 70, rl.GREEN)
	draw_centered("SPACE for menu", 300, 20, rl.GRAY)
}
```

Note the ball is drawn only in `.Playing` now (in 4.2 it was unconditional) — the title and end screens show the brick wall and paddle but no ball.

### Lives: make the kill zone cost something

The bottom edge already respawns the ball; now it decrements a counter first:

```odin
// ball lost: costs a life, respawn stuck on the paddle
if ball.pos.y > SCREEN_H + BALL_RADIUS {
	lives -= 1
	if lives <= 0 {
		state = .Game_Over
	} else {
		stick_ball(&ball, paddle)
	}
}
```

The HUD shows lives as little ball icons top-right — draw the state, don't print the number:

```odin
for i in 0 ..< lives {
	rl.DrawCircleV({f32(SCREEN_W - 30 - i * 25), 26}, 7, rl.WHITE)
}
```

Meanwhile 4.2's brick counter (`"bricks: %d"`) retires — the player cares about the campaign now, so the HUD's left slot becomes `rl.TextFormat("LEVEL %d", level_index + 1)`.

### Levels as data

Here's the star of the lesson. Three levels, each one string per brick row, one character per brick — `.` is empty, every other character picks a color:

```odin
LEVELS := [3][BRICK_ROWS]string {
	{
		"RRRRRRRRRR",
		"OOOOOOOOOO",
		"YYYYYYYYYY",
		"GGGGGGGGGG",
		"BBBBBBBBBB",
		"PPPPPPPPPP",
	},
	{
		"R.R.R.R.R.",
		"OOOOOOOOOO",
		"..Y....Y..",
		"GG..GG..GG",
		"BBBBBBBBBB",
		".P.P.P.P.P",
	},
	{
		"P........P",
		"YP......PY",
		"YYP....PYY",
		"GGYB..BYGG",
		"GGGYYYYGGG",
		"BBBBBBBBBB",
	},
}
```

Look at level 3: you can *see* the fortress in the source. That's the point. Designing a level is now editing text in your editor — with syntax highlighting, `git diff`, and undo. No level editor, no file format, no tooling. (It's a package-level variable rather than a constant because constants can't be indexed at runtime.)

### The parser is the nested loop you already know

`load_level` walks rows and characters, writes every grid slot (alive or not), and returns the live count so the game knows when the level is cleared:

```odin
load_level :: proc(bricks: ^[BRICK_ROWS][BRICK_COLS]Brick, level_index: int) -> int {
	level := LEVELS[level_index]
	alive := 0
	for row in 0 ..< BRICK_ROWS {
		for col in 0 ..< BRICK_COLS {
			ch := level[row][col]
			x := f32(BRICK_SIDE) + f32(col) * (BRICK_W + BRICK_PAD)
			y := f32(BRICK_TOP + row * (BRICK_H + BRICK_PAD))
			bricks[row][col] = Brick {
				rect  = {x, y, BRICK_W, BRICK_H},
				alive = ch != '.',
				color = brick_color(ch),
			}
			if ch != '.' do alive += 1
		}
	}
	return alive
}
```

`brick_color` is a `switch` from character to `rl.Color` — the whole "grammar" of our tiny level language is six letters and a dot. Indexing a string gives you bytes (`u8`), which compare directly against rune literals like `'R'`.

**Housekeeping:** `load_level` and `brick_color` *replace* last lesson's `init_bricks` and `row_color` — delete both, they're dead code now. Initialization in `main` changes to match: `bricks_left := load_level(&bricks, level_index)` takes over from `BRICK_ROWS * BRICK_COLS`, and `lives := START_LIVES` (`START_LIVES :: 3`) joins it. The initial `load_level` call at startup is what puts bricks behind the title screen; `.Title`'s transition to `.Playing` then reloads level 1 to guarantee a fresh start.

This is **data-driven design**: the grid, the parser, and the collision code are written once and never touched again. New content arrives as new data. When you later want two-hit bricks, you add a *character*, not a feature branch.

### Progression

`bricks_left` hit zero in lesson 4.2 and nothing happened. Now it drives the campaign:

```odin
// level cleared: next level, or win after the last
if bricks_left == 0 {
	level_index += 1
	if level_index >= len(LEVELS) {
		state = .Win
	} else {
		bricks_left = load_level(&bricks, level_index)
		stick_ball(&ball, paddle)
	}
}
```

Re-sticking the ball between levels gives the player a beat to breathe — pacing for free, courtesy of the `stuck` flag from lesson 4.1.

🌐 **Web dev callout — you already love data-driven design**
> You put routes in a table, copy in i18n catalogs, and form fields in JSON schemas for exactly this reason: changing content shouldn't mean changing logic. `LEVELS` is the same move — a declarative mini-language (six letters and a dot) plus a tiny interpreter (`load_level`). The difference is that your "config file" lives inside the binary and your level editor is just your text editor. When a web team says "make it configurable," a game dev says "make it data" — same instinct, same payoff.

## Full listing

Runnable snapshot: [`code/03-lives-and-levels/main.odin`](code/03-lives-and-levels/main.odin)

```sh
odin run 04-breakout/code/03-lives-and-levels
```

## Checkpoint

A title screen leads into level 1's rainbow wall. Losing the ball costs a life (watch the icons top-right empty out) and respawns it on the paddle; three losses ends the game. Clearing a level loads the next layout — checkerboard, then the fortress — and clearing the last one shows the win screen. SPACE returns to the title from either ending.

## Exercises

1. **Easy:** Design a fourth level — your initials in bricks, a smiley, whatever — and append it to `LEVELS`. Notice the parser, collision, and progression code needed **zero** changes. That's the lesson.
2. **Easy:** Add a new character `'S'` for silver (`rl.LIGHTGRAY`) bricks to `brick_color` and use it in a level.
3. **Medium:** Two-hit bricks via case: uppercase letters get `hp = 2`, lowercase get `hp = 1` (add the field; see lesson 4.2's exercise 4). `'R'` vs `'r'` in a level now means something — for free.
4. **Hard:** Validate levels at load: `assert` every row has exactly `BRICK_COLS` characters and every character is known, with `fmt.eprintln` telling the designer which level and row is broken. Data-driven design only works if bad data fails loudly.

**Next:** [4.4 Power-ups and polish](04-powerups-and-polish.md)
