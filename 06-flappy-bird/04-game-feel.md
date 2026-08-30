# 6.4 Game feel

**Module:** 06-flappy-bird

## Goals

- Parallax from one number: `world_x` drives hills at 0.2x, clouds at 0.5x, ground ticks at 1x
- `math.mod(offset, spacing)` — the wrap that makes each layer loop seamlessly
- A day/night cycle from `rl.ColorLerp` + `sin(time)` that tints the entire scene in lockstep
- Juice timers: `flash`, `score_pop`, `wing_anim` — set on an event, decay to zero, drive a visual while > 0
- Sound effects synthesized at startup with 2.4's `make_beep`

## New concepts

| Concept | What it is |
|---|---|
| Parallax | Distant layers scroll slower: `world_x * 0.2` for hills, `* 0.5` for clouds, `* 1.0` for the ground. Depth is a multiplier |
| Seamless wrap | `math.mod(world_x * 0.2, HILL_SPACING)` folds any offset into one tile width, so a short row of shapes loops forever |
| `rl.ColorLerp` | Interpolates between two colors; one `day` factor (0 = night, 1 = day) tints sky, hills, and clouds together |
| Juice timer | A float set on an event (`flash = FLASH_TIME`), decayed with `max(0, flash - dt)`, read as `flash / FLASH_TIME` for a 1→0 envelope |
| Score pop | Font size `48 + i32(score_pop / POP_TIME * 18)` — the number swells for a quarter-second on each point |

## Walkthrough

### Juice is a policy, not a feature

Nothing in this lesson changes how the game plays. Physics, spawner, collision, scoring — all untouched from 6.3. What changes is that every event the game already had (flap, score, death) now *leaves a mark*: a sound, a flash, a swell, a wing beat. The whole system is three timers and three constants:

```odin
// juice timers (seconds)
FLASH_TIME :: 0.15 // white flash on death
POP_TIME :: 0.25 // score text grows on each point
WING_TIME :: 0.2 // wing oscillates after each flap
```

The pattern is always the same four steps: an event sets the timer to its constant, the top of the loop decays every timer toward zero, something reads `timer / TIME` as a normalized 1→0 envelope, and at zero the effect is simply gone. No tweens, no animation library, no state to clean up.

```odin
flash = max(0, flash - dt)
score_pop = max(0, score_pop - dt)
wing_anim = max(0, wing_anim - dt)
```

### One number drives the world

```odin
world_x: f32 // total px scrolled; layers derive offsets from this
```

`world_x` accumulates `SCROLL_SPEED * dt` — the same speed the pipes move — and every background layer derives its offset from it by multiplication. One guard does all the directing:

```odin
// the world freezes on death — that's the drama
if state != .Dead do world_x += SCROLL_SPEED * dt
```

The instant you die, the scrolling world stops dead while the bird keeps falling. That freeze — the world holding its breath while you tumble — costs one `if` and does more for the drama of death than any particle system.

Note the guard's flip side: `world_x` accumulates in *every* state except `.Dead` — so the title screen scrolls now. In 6.1–6.3 the backdrop sat still behind the menu; from here on the menu is alive. Free, and it makes the game feel started before it starts.

### The mod wrap

```odin
// far hills: 0.2x scroll — the mod wraps the offset into one spacing
hill_color := rl.ColorLerp({25, 40, 70, 255}, {80, 170, 100, 255}, day)
hill_off := math.mod(world_x * 0.2, HILL_SPACING)
for i in 0 ..< SCREEN_W / HILL_SPACING + 2 {
	rl.DrawCircle(i32(f32(i * HILL_SPACING) - hill_off), GROUND_TOP + 30, 80, hill_color)
}
```

Hills are circles parked on the horizon, spaced `HILL_SPACING :: 160` apart, shifted left by `hill_off`. The `math.mod` is the loop: as `world_x * 0.2` grows without bound, `hill_off` folds back into `[0, HILL_SPACING)` — when the offset reaches one full spacing, it wraps and every hill silently takes its neighbor's place. The `+ 2` extra hills cover the seam at the edges. Since `world_x` only ever grows, the mod never sees a negative.

The clouds repeat the trick at `0.5x` — faster, therefore nearer — with `CLOUD_SPACING :: 200` and two small variations of their own: they're ellipses (`rl.DrawEllipse`, new here) at staggered heights (`i % 3` picks one of three altitudes), and the loop draws `+ 3` extra because the wider spacing needs one more to cover the seam:

```odin
// mid clouds: 0.5x scroll
cloud_color := rl.ColorLerp({70, 75, 110, 255}, rl.WHITE, day)
cloud_off := math.mod(world_x * 0.5, CLOUD_SPACING)
for i in 0 ..< SCREEN_W / CLOUD_SPACING + 3 {
	x := i32(f32(i * CLOUD_SPACING) - cloud_off)
	rl.DrawEllipse(x, 90 + i32(i % 3) * 70, 46, 18, cloud_color)
}
```

The ground ticks run at full 1x scroll, `TICK_SPACING :: 24` px apart:

```odin
// scrolling ticks: 1x scroll, wrapped to one tick spacing
tick_off := math.mod(world_x, TICK_SPACING)
for x := -tick_off; x < SCREEN_W; x += TICK_SPACING {
	rl.DrawRectangle(i32(x), GROUND_TOP + 10, 4, 12, {190, 180, 120, 255})
}
```

Three layers, three speeds, one scrolling variable. Your eyes do the depth math for free: the faster a layer moves, the closer it reads.

### Day and night from one sine

```odin
// slow day/night cycle: 0 = night, 1 = day
day := (math.sin(time * 0.15) + 1) / 2
sky_top := rl.ColorLerp(NIGHT_SKY_TOP, DAY_SKY_TOP, day)
sky_bottom := rl.ColorLerp(NIGHT_SKY_BOTTOM, DAY_SKY_BOTTOM, day)
rl.DrawRectangleGradientV(0, 0, SCREEN_W, GROUND_TOP, sky_top, sky_bottom)
```

`sin` oscillates in [−1, 1]; the `+ 1) / 2` remaps that to [0, 1] — a breathing blend factor. At 0.15 rad/s a full day takes about 42 seconds. `rl.ColorLerp(a, b, t)` mixes two colors, and because the hills and clouds also lerp on the same `day`, the *entire* scene — sky gradient, hills, clouds — swings between its night and day palettes in lockstep. One sine, four colors (sky top, sky bottom, hills, clouds), a living world.

### The three timers at work

Death fires the flash and the thud, on both paths into `.Dead`:

```odin
best = max(best, score)
flash = FLASH_TIME
rl.PlaySound(hit_sfx)
state = .Dead
```

...and the flash draws **last**, after the HUD, so the white-out covers everything:

```odin
// death flash covers everything, HUD included
if flash > 0 {
	rl.DrawRectangle(0, 0, SCREEN_W, SCREEN_H, rl.Fade(rl.WHITE, flash / FLASH_TIME))
}
```

`flash / FLASH_TIME` runs 1→0 over 0.15 s; `rl.Fade` maps that to alpha. One fullscreen rectangle. Scoring pops the HUD number:

```odin
size := 48 + i32(score_pop / POP_TIME * 18)
draw_centered(rl.TextFormat("%d", score), 30, size, rl.WHITE)
```

The font jumps to 66 on the point and settles back to 48 in a quarter-second. And the flap gets a wing — while `wing_anim` runs down, its raw value feeds a sine, so the wing sweeps about a cycle and a half and stops:

```odin
// wing: fast oscillation while wing_anim runs down, still otherwise
wing_angle: f32 = 0
if wing_anim > 0 {
	wing_angle = math.sin(wing_anim * 50) * 30
}
rl.DrawRectanglePro({bird.pos.x, bird.pos.y, 16, 8}, {0, 4}, rotation + wing_angle, rl.ORANGE)
```

The wing is a 16×8 rectangle rotating around its left edge (`{0, 4}` is the pivot), its angle added to the body's rotation. It's armed on every flap, right next to the impulse: `wing_anim = WING_TIME`. (It's drawn *before* the body triangle, so the body covers its root and it reads as attached.)

The wing also changes `draw_bird`'s signature — the timer has to come from somewhere, so the call site becomes `draw_bird(bird, wing_anim)`:

```odin
draw_bird :: proc(bird: Bird, wing_anim: f32) {
	rotation := clamp(bird.vel.y * 0.08, -25, 90)
	// ... wing, body, eye ...
}
```

### Beeps you already own

`make_beep` is the WAV synthesizer from lesson 2.4, copied in unchanged — it builds a sine wave with a decay envelope in memory and loads it as a sound. Three voices at startup:

```odin
flap_sfx := make_beep(600, 0.05)
defer rl.UnloadSound(flap_sfx)
score_sfx := make_beep(900, 0.12)
defer rl.UnloadSound(score_sfx)
hit_sfx := make_beep(150, 0.25)
defer rl.UnloadSound(hit_sfx)
```

Pitch is meaning: 600 Hz for 50 ms is a tick, 900 Hz is a reward chime, 150 Hz for a quarter-second is a thud. You could tune these three numbers for an hour — many have. The only other audio work is `rl.InitAudioDevice()` / `defer rl.CloseAudioDevice()` at startup and an `rl.PlaySound(...)` at each event, right where the timers get set.

### Housekeeping: the scenery becomes procs

The drawing grew enough that the snapshot reorganizes it — your diff will show three moves, all mechanical:

- **`draw_background(time, world_x)`** now owns the sky gradient, hills, and clouds; **`draw_ground(world_x)`** owns the ground strip and ticks. The two base ground rectangles lived inline in `main` since 6.1 — they've moved in.
- **`rl.ClearBackground(rl.SKYBLUE)` is gone.** Not because clearing is optional — because `draw_background`'s gradient plus `draw_ground`'s strip now paint every pixel of the window, so there's nothing left to clear. (The habit stays: if you can see the clear color, something isn't painting.)
- The juice timers aren't reset on R — a flash mid-death simply finishes during the next title screen. Harmless, and one less line in the reset.

🌐 **Web dev callout — you've shipped parallax; the browser did the wrapping**
> Parallax is a web native: `background-attachment: fixed`, scroll-jacked layers with `translateY(scrollY * 0.5)`, a `repeat-x` background with an animated `background-position` for a marquee. That last one *is* this lesson's trick — animating `background-position-x` from 0 to −spacing on a loop is `math.mod(world_x, spacing)` with a compositor. The differences are ownership and authority: on the web the user owns the scroll variable and the browser wraps tiles for you; here *you* own `world_x` — which is why a single `if state != .Dead` can freeze the entire world mid-frame, something no CSS animation will politely let you do. And the juice timers are CSS transitions re-implemented as three lines: set, decay, divide. The browser gives you transitions for free and charges you a main thread; games give you nothing and charge you three floats.

## Full listing

Runnable snapshot: [`code/04-game-feel/main.odin`](code/04-game-feel/main.odin)

```sh
odin run 06-flappy-bird/code/04-game-feel
```

## Checkpoint

The sky drifts between night and day (a full cycle is ~42 s — wait for dusk), hills and clouds slide at visibly different speeds, and the ground ticks race beneath everything. Flap and the wing beats; score and the number swells with a chime; die and the world freezes, the screen flashes white, and a low thud lands while the bird tumbles. Now set `FLASH_TIME :: 0` and re-run — death suddenly feels like a software crash instead of an event. One rectangle, 0.15 seconds, the whole difference between "oh no" and "oh well." **Juice is cheap. Feel is everything.**

## Exercises

1. **Easy:** Golden hour. Retint the night palette to a sunset — `NIGHT_SKY_TOP :: rl.Color{60, 30, 80, 255}` and `NIGHT_SKY_BOTTOM :: rl.Color{230, 120, 70, 255}` — and speed the cycle to `math.sin(time * 0.4)`. Hills and clouds follow automatically: they all read the same `day`.
2. **Medium:** Ceiling bonk. Give the ceiling clamp a sound, but only on arrival, not while pinned: build a `bonk_sfx := make_beep(250, 0.08)` at startup alongside the other three sounds, and inside `if bird.pos.y < bird.radius`, `rl.PlaySound(bonk_sfx)` only when `bird.vel.y < -200` (i.e. the bird actually *arrived* fast this frame). Without that velocity condition the sound retriggers every frame you're pinned — you're hand-building the same edge detection as 6.3's scoring trigger.
3. **Medium:** Stars. At the top of `draw_background`, draw 40 stars that fade in at night: `for i in 0 ..< 40 { rl.DrawCircle(i32((i * 137) % SCREEN_W), i32((i * 89) % 250), 1.5, rl.Fade(rl.WHITE, 1 - day)) }`. The index-multiplied constants are a poor man's hash — deterministic positions with nothing stored and nothing randomized.
4. **Hard:** Combo pitch. Build an array of five flap beeps at startup (`make_beep(f32(550 + 60 * i), 0.05)` for `i in 0 ..< 5`), keep a `combo` int that increments per flap and resets to 0 after a second without flapping, and play `flap_sfx[min(combo, 4)]`. Rhythmic flapping now plays a rising arpeggio — the game grades your timing without a single new mechanic.

**Next:** [7.1 Ship and thrust](../07-asteroids/01-ship-and-thrust.md)
