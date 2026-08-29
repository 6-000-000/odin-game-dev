# 2.2 Drawing and the coordinate system

**Module:** 02-game-dev-foundations

## Goals

- Think in raylib's coordinate system: y points **down**, origin top-left
- Draw every primitive shape and know the `V`/`Ex`/`Pro` suffix conventions
- Build colors from channels, use alpha, and fade
- Center text with `MeasureText` — the 80% case of game UI

## New concepts

| Concept | What it is |
|---|---|
| Immediate-mode rendering | Nothing persists on screen; you redraw everything every frame |
| `rl.Color` | `{r, g, b, a: u8}` — 0–255 per channel |
| `Vector2` | `{x, y: f32}` — the universal 2D currency; literal `{100, 200}` |
| `rl.Rectangle` | `{x, y, width, height: f32}` |

## Walkthrough

## The coordinate system (y is down!)

```
(0,0) ──────────────── x increases →
  │
  │        (400, 225) is the center of an 800×450 window
  │
  y increases ↓
```

Y grows **downward**. `(0, 0)` is the top-left corner; `(800, 450)` is bottom-right. This is screen-space tradition (and matches CSS, happily) — but it will betray you when you do math from school: positive rotation is *clockwise*, and "up" on screen is *negative* y. Thrust "upward" is `vel.y -= speed * dt`. You'll make this sign error once, fix it, and be immune forever.

## Immediate mode: there is no scene graph

Nothing you draw persists. Every frame begins with `rl.ClearBackground`, wiping to a solid color, and everything visible must be drawn again. This feels wasteful if you're used to retained-mode UIs — it's actually liberating:

- To move something, change its variables. The next frame draws it there. Done.
- To hide something, stop drawing it. There's nothing to remove or destroy.
- Draw order = painter's algorithm: later draws appear on top. Background first, UI last.

> **🌐 Web dev callout — canvas2d, not the DOM**
> This is `<canvas>`'s 2D context model: `clearRect` then redraw. It is *not* the DOM — there's no element tree, no layout engine, no reflow, no CSS. "Layout" is arithmetic you do yourself: `center_x := SCREEN_W/2 - width/2`. The upside: no mystery. The screen shows exactly what your code drew, in the order it drew it, at the coordinates you computed.

## The shape toolkit

```odin
rl.DrawPixel(10, 10, rl.RED)
rl.DrawLine(0, 0, 100, 100, rl.GRAY)                          // x1,y1 → x2,y2 (ints)
rl.DrawLineV({0, 0}, {100, 100}, rl.GRAY)                     // Vector2 version
rl.DrawLineEx({0, 0}, {100, 100}, 4, rl.DARKGRAY)             // thick
rl.DrawCircle(400, 225, 30, rl.SKYBLUE)                       // x, y, radius (ints)
rl.DrawCircleV({400, 225}, 30, rl.SKYBLUE)                    // Vector2 + f32 radius
rl.DrawCircleLines(400, 225, 30, rl.DARKBLUE)                 // outline
rl.DrawRectangle(50, 50, 120, 80, rl.GREEN)                   // x, y, w, h (ints)
rl.DrawRectangleRec({50, 50, 120, 80}, rl.GREEN)              // Rectangle version
rl.DrawRectangleLinesEx({50, 50, 120, 80}, 2, rl.DARKGREEN)   // outline w/ thickness
rl.DrawTriangle({0,0}, {50,100}, {100,0}, rl.ORANGE)
rl.DrawRing({400, 225}, 40, 50, 0, 360, 32, rl.GOLD)          // donut/pie
rl.DrawRectangleGradientV(0, 0, 800, 450, rl.DARKBLUE, rl.PURPLE)
```

Naming conventions, learnable in one minute:
- **`...V`** — takes `Vector2`s instead of separate x/y ints
- **`...Ex` / `...Pro`** — extended parameters (thickness, rotation, origin)
- **`...Lines`** — outline instead of fill

## Colors

```odin
rl.RED, rl.RAYWHITE, rl.SKYBLUE ...        // named constants
my_teal := rl.Color{0, 128, 128, 255}      // {r, g, b, a} each 0–255
ghost := rl.Fade(rl.WHITE, 0.5)            // 50% alpha version
pulse := rl.ColorAlpha(rl.RED, 0.5 + 0.5*math.sin(t*4))
```

Alpha (`a`) is opacity: 255 solid, 0 invisible. For per-frame pulsing effects, `rl.Fade`/`rl.ColorAlpha` are your friends — you'll use them for invulnerability blinks in Asteroids.

## Text that lands where you want it

`rl.DrawText` draws from the **top-left** of the text block. To center, measure first:

```odin
text :: "GAME OVER"
font_size :: 40
w := rl.MeasureText(text, font_size)   // width in pixels (i32)
rl.DrawText(text, (SCREEN_W - w)/2, 200, font_size, rl.WHITE)
```

`MeasureText` uses the default font's metrics. Every menu, score, and title in this course centers this way.

## Full listing

Runnable snapshot: [`code/02-drawing/main.odin`](code/02-drawing/main.odin) — a labeled gallery of every shape above, plus a pulsing circle and centered text. Keep it open in a tab; it's your drawing reference for the whole course.

```sh
odin run 02-game-dev-foundations/code/02-drawing
```

## Checkpoint

A gallery screen with shapes at predictable positions. You can place a rectangle's *center* at the screen's center (hint: `x = SCREEN_W/2 - w/2`) without trial and error.

## Exercises

1. **Easy:** Draw a bullseye: three concentric circles, alternating red/white, centered on the screen.
2. **Easy:** Draw a plus sign (crosshair) centered on the mouse position with `rl.GetMousePosition()`. Two `DrawLineEx` calls.
3. **Medium:** Draw an 8×8 checkerboard of 40px squares using two nested loops and `DrawRectangle` — color by `(x + y) % 2`. (Odin: `%` on ints, `if (x+y) %% 2 == 0` — note Odin's modulo for ints is `%%` when the divisor could be negative; plain `%` works for positives.)
4. **Medium:** Make a "sunrise" background: `DrawRectangleGradientV` whose top color lerps from dark blue to orange over 5 seconds, looping. Hint: `rl.ColorLerp(a, b, t)` with `t = 0.5 + 0.5*math.sin(time)` and `time := f32(rl.GetTime())`.

**Next:** [2.3 Input: polling, not events](03-input.md)
