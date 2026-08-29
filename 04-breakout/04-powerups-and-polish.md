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

Multiball means the single `ball` variable has to become a collection. Instead of a dynamic array, both balls and power-ups use the same pattern as the brick grid — a fixed array where every slot always exists:

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

The brick-break site rolls the dice: `if rl.GetRandomValue(1, 100) <= POWERUP_DROP_CHANCE`. Update and draw loops skip inactive slots (`if !p.active do continue`), the ball-lost check becomes `b.active = false`, and "you're out of balls" is a count of active slots hitting zero. `reset_balls` restores the fresh-serve state: one stuck ball in slot 0, everything else off.

### Catching: rectangle vs rectangle

Power-ups fall at constant speed and die off-screen. The catch is `CheckCollisionRecs` against the paddle — the same test as Pong's paddle, now on a 28×20 capsule:

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

### The three effects

**Widen** is a timer plus a wider rect. `Paddle` gains a `width` field that `paddle_rect`, the clamp, and the bounce offset all read — one source of truth:

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

**Slow** bends a single `ball_speed` variable that serves, paddle bounces, and brick-bounce renormalization all use — change it once and the whole game obeys. Catch rescales every live ball instantly; expiry rescales back:

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

**Multiball** clones the first live ball into two free slots, rotating its velocity ±30°. Rotating a vector `(x, y)` by angle `a` is `(x·cos a − y·sin a, x·sin a + y·cos a)` — the one formula to remember:

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

- **Particles:** the same `[dynamic]Particle` burst, iterated backward with `unordered_remove` — now colored per brick (Pong 3.4's exercise 2), so red bricks shower red sparks.
- **Beeps:** `make_beep` copied verbatim: paddle 440 Hz, catch 880 Hz, life-lost 160 Hz. The brick beep gets per-row pitch with one new call instead of six sounds: `rl.SetSoundPitch(brick_sfx, 1 + 0.12 * f32(row))` — higher rows ring higher.
- **Screen shake** on life lost: Pong 3.4's exercise 3 offset every draw call by hand; here a `Camera2D` with a random decaying `offset` does it in one line, and the HUD stays outside `BeginMode2D` so it doesn't shake:

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
