# 4.4 Power-ups and polish

**Module:** 04-breakout

## Goals

- Make bricks drop falling power-ups (20% chance) that the paddle can catch
- Manage balls and power-ups with **fixed pools + active flags** instead of single values
- Implement three power-ups: widen paddle (timer), multiball (vector rotation), slow ball (shared speed)
- Reuse every Pong 3.4 polish pattern: particles, synth beeps, screen shake

## New concepts

| Concept | What it is |
|---|---|
| Object pool | Fixed array + `active: bool`; spawning = finding an inactive slot, despawning = clearing a flag |
| Timer as data | `timer -= dt` every frame; revert the effect at zero. There is no `setTimeout` here |
| Vector rotation | Rotate `vel` by ±θ: `{x·cosθ − y·sinθ, x·sinθ + y·cosθ}` |
| Drop chance | `rl.GetRandomValue(1, 100) <= 20` |
| Enum-indexed table | `[Power_Up_Kind]rl.Color` — lookup by enum value, no `switch` needed |

## Walkthrough

### Pools: many balls, many power-ups, zero allocations

Multiball means the single `ball` variable has to become a collection. Instead of a dynamic array, both balls and power-ups use the same pattern as the brick grid — a fixed array where every slot always exists (`MAX_BALLS :: 8` and `MAX_POWERUPS :: 8`: generous ceilings that never need to grow):

```odin
balls: [MAX_BALLS]Ball       // Ball gains an `active` field
powerups: [MAX_POWERUPS]Power_Up
```

Spawning is "find an inactive slot and overwrite it" — `p^ = Power_Up{...}` assigns a whole fresh struct through the pointer:

```odin
spawn_powerup :: proc(powerups: ^[MAX_POWERUPS]Power_Up, pos: rl.Vector2) {
	for i in 0 ..< MAX_POWERUPS {
		p := &powerups[i]
		if p.active do continue
		p^ = Power_Up {
			pos    = pos,
			vel    = {0, POWERUP_FALL_SPEED},
			kind   = Power_Up_Kind(rl.GetRandomValue(0, 2)),
			active = true,
		}
		return
	}
}
```

`POWERUP_FALL_SPEED :: 180` keeps drops catchable, and `Power_Up_Kind(rl.GetRandomValue(0, 2))` is a plain int→enum cast — `GetRandomValue` returns `i32`, the enum's ordinals run 0–2, and the cast says "trust me, it's in range." The brick-break site rolls the dice: `if rl.GetRandomValue(1, 100) <= POWERUP_DROP_CHANCE`. Update and draw loops skip inactive slots (`if !p.active do continue`), and the ball-lost check becomes `b.active = false`.

"You're out of balls" is a count of active slots hitting zero — and that count has one subtlety. It's accumulated inside the update loop in *two* places:

```odin
balls_active := 0
for &b in balls {
	if !b.active do continue
	if b.stuck {
		// ... ride the paddle, serve on SPACE ...
		balls_active += 1 // a stuck ball still counts!
		continue
	}
	// ... move, collide ...
	if b.pos.y > SCREEN_H + BALL_RADIUS do b.active = false
	if b.active do balls_active += 1
}
```

The stuck-branch increment is load-bearing: without it, a fresh serve (one stuck ball, nothing moving) reads as "no balls left" and costs a life instantly. When the count does hit zero, `reset_balls` restores the fresh-serve state: one stuck ball in slot 0, everything else off.

### Catching: rectangle vs rectangle

Power-ups fall at constant speed and die off-screen. The catch is `CheckCollisionRecs` against the paddle — the same test as Pong's paddle, now on a 28×20 pickup:

```odin
if rl.CheckCollisionRecs(powerup_rect(p), paddle_rect(paddle)) {
	p.active = false
	rl.PlaySound(powerup_sfx)
	switch p.kind {
	// ...
	}
}
```

Each kind draws its color and letter from an **enum-indexed table** — Odin arrays can be indexed by enum types, so lookup needs no switch:

```odin
KIND_COLORS := [Power_Up_Kind]rl.Color{.Widen = rl.GREEN, .Multiball = rl.ORANGE, .Slow = rl.SKYBLUE}
KIND_LETTERS := [Power_Up_Kind]cstring{.Widen = "W", .Multiball = "M", .Slow = "S"}
```

Drawing consumes both tables, with `MeasureText` centering the letter on the pickup (and particles fading exactly the way Pong's did — `rl.Fade(p.color, p.life * 2)`):

```odin
for p in powerups {
	if !p.active do continue
	rl.DrawRectangleRec(powerup_rect(p), KIND_COLORS[p.kind])
	letter := KIND_LETTERS[p.kind]
	x := i32(p.pos.x) - rl.MeasureText(letter, 16) / 2
	rl.DrawText(letter, x, i32(p.pos.y) - 8, 16, rl.BLACK)
}
```

### The three effects

**Widen** is a timer (`WIDEN_DURATION :: 10` seconds) plus a wider rect (`WIDEN_SCALE :: 1.6`). `Paddle` gains a `width` field that `paddle_rect`, the clamp, and the bounce offset all read — one source of truth:

```odin
case .Widen:
	widen_timer = WIDEN_DURATION
	paddle.width = PADDLE_W * WIDEN_SCALE
```

```odin
// timers are data: tick them down, revert when they expire
if widen_timer > 0 {
	widen_timer -= dt
	if widen_timer <= 0 do paddle.width = PADDLE_W
}
```

**Slow** (`SLOW_DURATION :: 8` seconds, `SLOW_SCALE :: 0.7`) bends a single `ball_speed` variable that serves, paddle bounces, and brick-bounce renormalization all use — change it once and the whole game obeys. That plumbing is why `serve_ball` gains a parameter this lesson — `serve_ball :: proc(b: ^Ball, speed: f32)`, body and call site updated to match. Catch rescales every live ball instantly; expiry rescales back:

```odin
case .Slow:
	slow_timer = SLOW_DURATION
	ball_speed = BALL_SPEED * SLOW_SCALE
	for &b in balls {
		if b.active && !b.stuck {
			b.vel = rl.Vector2Normalize(b.vel) * ball_speed
		}
	}
```

**Multiball** clones the first **active, non-stuck** ball into two free slots, rotating its velocity ±30°. The source search has an early-out — catching **M** while your only ball still rides the paddle (pre-serve) finds no source and does nothing, rather than cloning a parked ball:

```odin
src: ^Ball
for i in 0 ..< MAX_BALLS {
	if balls[i].active && !balls[i].stuck {
		src = &balls[i]
		break
	}
}
if src == nil do return
```

Rotating a vector `(x, y)` by angle `a` is `(x·cos a − y·sin a, x·sin a + y·cos a)` — the one formula to remember:

```odin
sign: f32 = spawned == 0 ? 1 : -1
a := sign * math.PI / 6 // rotate (x,y) by ±30°
vx := src.vel.x * math.cos(a) - src.vel.y * math.sin(a)
vy := src.vel.x * math.sin(a) + src.vel.y * math.cos(a)
b^ = Ball{pos = src.pos, vel = {vx, vy}, active = true}
```

Three balls bouncing through a dense grid is pure Breakout joy — and it cost one pool and one trig formula.

### Polish: all Pong 3.4 patterns, transplanted

Every effect in this section is a pattern you already own from Pong 3.4, adapted in minutes:

- **Particles:** the same `[dynamic]Particle` burst, iterated backward with `unordered_remove` — now colored per brick (Pong 3.4's exercise 2), so red bricks shower red sparks. Two quiet recipe changes: 10 sparks per brick instead of 12, and no 30% velocity inheritance — brick debris is a pure radial burst, since there's no single impact direction to inherit from.
- **Beeps:** `rl.InitAudioDevice()` / `defer rl.CloseAudioDevice()` join `InitWindow` in `main`, and `make_beep` is copied verbatim (all four pieces from lesson 3.4: `SAMPLE_RATE`, both helpers, the proc): paddle 440 Hz, catch 880 Hz, life-lost 160 Hz. The brick beep gets per-row pitch with one new call instead of six sounds: `rl.SetSoundPitch(brick_sfx, 1 + 0.12 * f32(row))` — higher rows ring higher.
- **Screen shake** on life lost: `shake = 0.4` fires where the last ball dies, and every frame the timer decays — `shake = max(shake - dt, 0)`, placed outside the state switch next to the particles so it runs on every screen. Pong 3.4's exercise 3 offset every draw call by hand; here a `Camera2D` with a random decaying `offset` does it in one line, and the HUD stays outside `BeginMode2D` so it doesn't shake:

```odin
camera.offset = {}
if shake > 0 {
	camera.offset = {
		rand.float32_range(-1, 1) * shake * 12,
		rand.float32_range(-1, 1) * shake * 12,
	}
}
rl.BeginMode2D(camera)
// ... world ...
rl.EndMode2D()
```

### Housekeeping: what else changed since 4.3

The new machinery forced a few renames and reshuffles in code you already typed. The snapshot has them all — here's the diff in words, so nothing surprises you:

- **`.Game_Over` and `.Win` merged** into `case .Game_Over, .Win:` in *both* switches — identical behavior (SPACE → title), so the draw side picks its message with two ternaries: `msg: cstring = state == .Win ? "YOU WIN!" : "GAME OVER"` and a matching color.
- **The brick-loop variable is now `brick`, not `b`** — `for &b in balls` claimed the letter first. Both the collision loop and the draw loop were renamed.
- **All active balls draw in every state.** Ball drawing moved out of the state switch up next to the paddle, so a leftover ball is visible behind the title screen. The serve hint now keys off `balls[0].stuck`.
- **The title screen advertises the new feature:** "catch the falling letters — SPACE to start" (nudged to y=180/300).
- **Draw order shuffled:** world (through the camera) → HUD → state screens. State screens must sit on top of everything, so "HUD last" now means "last *unshaken* element" — the snapshot's comment says as much.
- **Cosmetic:** `LEVELS` reflowed to one line per level, struct fields regrouped (`pos, vel:`), a few 4.3 comments dropped. No behavior changed.

One deliberate behavior note: falling power-ups and the widen/slow timers are *not* cleared on a level transition — leftover letters keep falling into the next level and a wide paddle stays wide. That's a design choice (momentum carries); if it bothers you, clearing both in the `bricks_left == 0` block is three lines.

🌐 **Web dev callout — there is no `setTimeout` in a game loop**
> "Widen the paddle for 10 seconds" is not a scheduler callback — it's a float you decrement by `dt` every frame and a check that reverts the effect at zero. You're effectively implementing `setTimeout` on top of `requestAnimationFrame`, because that's what the game loop *is*. The payoff over browser timers: timers are plain data, so they pause when the game pauses, they're inspectable in the debugger, and they serialize straight into a save file. Handles and closures give you none of that.

## Full listing

Runnable snapshot: [`code/04-powerups-and-polish/main.odin`](code/04-powerups-and-polish/main.odin) — the complete game.

```sh
odin run 04-breakout/code/04-powerups-and-polish
```

## Checkpoint

A full Breakout: three levels, three lives, and falling letters. Green **W** stretches the paddle for 10 s, orange **M** splits the ball into three, blue **S** slows everything for 8 s. Bricks burst into colored particles with a pitch that climbs by row, losing the last ball punches the screen with a shake and a low buzz, and the win screen waits after the fortress. Play it twice — once chasing every power-up, once ignoring them. Different games.

## Exercises

1. **Easy:** Give particles gravity: `p.vel.y += 400 * dt` in the update loop. Debris that *falls* reads as rubble; debris that drifts reads as sparks.
2. **Easy:** Draw countdown bars for the widen/slow timers under the HUD: width `= 100 * timer / DURATION`. Players should never guess how long an effect lasts.
3. **Medium:** Add a fourth kind, **Catch** (`'C'`): for 6 s, balls that touch the paddle go `stuck` instead of bouncing (SPACE re-serves). You already own the flag — this power-up is mostly table entries and one `if`. Add it to the enum, both tables, and the catch switch.
4. **Hard:** Tame multiball chains: balls spawned by multiball get `is_extra = true` and can't trigger power-up drops, and no power-ups spawn while more than 3 balls are live. Playtest before and after — which version is more *fun*, and why?

**Next:** [Module 5 — Project: Snake](../05-snake/01-grid-and-movement.md)
