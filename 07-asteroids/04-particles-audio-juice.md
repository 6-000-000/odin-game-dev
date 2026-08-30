# 7.4 Particles, audio, and juice

**Module:** 07-asteroids

## Goals

- A third pool: 256 particles — exhaust trails, explosion bursts, ship-death nova
- All sounds synthesized once at startup (`audio.odin`); wave-clear as a two-tone jingle
- Invulnerability blink with `rl.Fade` + `math.sin`
- Screen shake via a `Camera2D` offset — the world shakes, the HUD doesn't
- Feel the payoff: pools made all of this *trivial*

## New concepts

| Concept | What it is |
|---|---|
| Particle | The smallest entity: `pos, vel, life, color` — zero gameplay, all feel |
| Burst vs. trail | Explosions spawn a batch at once; the exhaust spawns continuously while thrusting |
| `rl.Fade` | A color with scaled alpha — particle fade-out and the invuln blink |
| `Camera2D` offset | Shifts everything drawn inside `BeginMode2D` — shake without touching the HUD |

## Walkthrough

### The particle pool — third time's the pattern

```odin
Particle :: struct {
	pos:    rl.Vector2,
	vel:    rl.Vector2,
	life:   f32,
	color:  rl.Color,
	active: bool,
}

// Claim one free slot; if the pool is full the effect just doesn't spawn. Juice is optional.
spawn_particle :: proc(world: ^World, p: Particle) {
	for &slot in world.particles {
		if !slot.active {
			slot = p
			slot.active = true
			return
		}
	}
}
```

This is the *same* free-slot search you wrote for asteroids and bullets — the third pool, zero new ideas. That's the point of this module: the loop code that runs 2 entities runs 200. Update ages and retires; draw fades alpha with remaining life (`rl.Fade(p.color, p.life * 2)` — Pong 3.4's trick). One difference from gameplay pools: when the particle pool is full, the effect is silently skipped. Dropping a spark is always better than dropping a frame.

### Explosions that scale with the rock

```odin
// in collide_bullets, right where the rock dies:
explode(world, a.pos, rl.ORANGE, int(a.radius * 0.6), 40, 180) // burst scales with size
```

`explode` fires `count` sparks in random directions at 40–180 px/s, each living 0.3–0.7 s. `int(a.radius * 0.6)` turns the tiers into 24 / 13 / 7 sparks — the player's eye learns "bigger kill, bigger bang" in one wave, no tutorial needed. Ship death goes bigger: 40 sky-blue sparks at up to 240 px/s, plus `world.shake = 0.4`.

### Exhaust: a trail, not a flame

Delete the flame triangle from `draw_ship` (its `thrusting` parameter goes too) — a real particle trail replaces the fake one. One puff per frame while UP is held:

```odin
spawn_exhaust :: proc(world: ^World) {
	ship := &world.ship
	facing := ship_facing(ship.angle)
	jitter := rl.Vector2{rand.float32_range(-25, 25), rand.float32_range(-25, 25)}
	spawn_particle(world, Particle{pos = ship.pos - facing * ship.radius, vel = facing * -80 + jitter, life = 0.4, color = rl.YELLOW})
}
```

Spawned at the tail, thrown *against* the facing at 80 px/s with a little random jitter: the trail streams behind you even as you drift sideways — inertia you can see. 60 spawns/s × 0.4 s life ≈ 24 live particles. The 256 budget is luxurious, and that's fine: headroom is the whole point of sizing pools.

### audio.odin: make_beep graduates to its own file

Lesson 2.4's `make_beep` (with `append_u16le`/`append_u32le`) moves to `audio.odin` verbatim, and every sound in the game is synthesized **once at startup** into a struct:

```odin
load_sounds :: proc() -> Sounds {
	return {
		shoot = make_beep(900, 0.05),
		hit = make_beep(330, 0.08),
		explosion = make_beep(110, 0.25),
		wave_low = make_beep(440, 0.3),
		wave_high = make_beep(660, 0.3),
		game_over = make_beep(80, 0.5),
	}
}
```

High and short for shooting, low and long for disaster — pitch reads as severity. The wave-clear "two-tone" is just `wave_low` and `wave_high` played in the same frame: raylib mixes simultaneous `PlaySound` calls, so a jingle is two lines. In `main`: `rl.InitAudioDevice()` + `defer rl.CloseAudioDevice()`, `sfx := load_sounds()` + `defer unload_sounds(sfx)`, and the gameplay procs (`try_fire`, `collide_bullets`, `collide_ship`) take `sfx: Sounds` to play their cues. `main` plays the wave jingle and the game-over drone at the state transitions.

### Blink and shake

While `invuln` runs, the ship's alpha pulses — the universal "you can't die right now, move!" signal:

```odin
alpha: f32 = 1
if ship.invuln > 0 {
	alpha = 0.35 + 0.65 * abs(math.sin(ship.invuln * 12))
}
rl.DrawTriangleLines(nose, wing_l, wing_r, rl.Fade(rl.WHITE, alpha))
```

And the shake: instead of offsetting every draw call by hand, offset the *camera*. Everything between `BeginMode2D` and `EndMode2D` shifts; the HUD, drawn outside, stays rock-steady:

```odin
camera := rl.Camera2D{zoom = 1}
if world.shake > 0 {
	camera.offset = {rand.float32_range(-1, 1), rand.float32_range(-1, 1)} * world.shake * 24
}
```

`world.shake` decays in the loop (`max(0, world.shake - dt)`), so the jitter dies out over 0.4 s. Random offset scaled by remaining time = a punch that fades.

The camera moves the state machine's draw side around, but it still *switches*: the ship draws inside `BeginMode2D` under `case .Playing` (so it shakes with the world), the GAME OVER text draws under `case .Game_Over` outside it (so it doesn't) — and since that text comes after the HUD lines, "HUD last" strictly holds only in `.Playing`. On the game-over screen the verdict is what sits on top, which is what you want.

(Housekeeping for your diff — 7.3's code shifted in a few places that the features above don't mention:

- `respawn_ship` was also used exactly once, so it's inlined into `collide_ship` next to the death effects (same four assignments: center, zero velocity, angle 0, `invuln`). One-use procs earn their inline — same verdict as `asteroids_remaining`, which became the count loop at the wave check in `main.odin`.
- `update_bullets` collapsed the death block to a one-liner (`if b.life <= 0 do b.active = false` without the `continue`), so a bullet that dies this frame still gets wrapped once. Harmless — it's inactive, so it never draws — and one branch fewer.
- `update_particles` runs in `.Game_Over` too, so the nova and the drifting field die out naturally instead of freezing mid-burst.
- Particles draw **first**, behind rocks, bullets, and ship (sparks read as underlay, not confetti-on-top), and they're hard-coded at radius 2.
- A batch of 7.3's now-redundant teaching comments was stripped; the code they described is unchanged.)

🌐 **Web dev callout — juice is micro-interactions**
> Skeleton screens, button press states, hover eases, confetti on the success page: the last 10% that makes software feel *shipped*. Games are nothing but that 10%. And particles are oddly close to CSS animations — fire-and-forget: you spawn them, never reference them again, and they clean themselves up. The discipline difference is ownership: here there's no compositor watching out for you, just a 256-slot array and a loop. If a web page had 350 animated nodes you'd reach for the GPU; here 350 pool slots update in microseconds, because a flat array scan is the fastest "framework" there is.

## Full listing

Runnable snapshot: [`code/04-particles-audio-juice/main.odin`](code/04-particles-audio-juice/main.odin) + [`code/04-particles-audio-juice/entities.odin`](code/04-particles-audio-juice/entities.odin) + [`code/04-particles-audio-juice/audio.odin`](code/04-particles-audio-juice/audio.odin)

```sh
odin run 07-asteroids/code/04-particles-audio-juice
```

## Checkpoint

The complete game. Thrusting streams a golden trail; rocks burst into orange sparks sized by tier; dying flashes a sky-blue nova and kicks the screen; the respawned ship blinks for two seconds; every action has a sound, and clearing a wave plays a little two-tone jingle. Then count the entities: 1 ship + 64 rocks + 32 bullets + 256 particles ≈ 350 slots — all updated by the same three loop shapes (`if !active do continue`, integrate, draw) you've now written four times. That's not a coincidence. That's the architecture.

## Exercises

1. **Easy:** Pitch variety: build three shoot beeps (880, 900, 920 Hz) into a `[3]rl.Sound` and rotate which one plays per shot. Ten minutes of work; the pew-pew stops feeling like a printer.
2. **Easy:** Tint explosions by tier — BIG `rl.ORANGE`, MED `rl.GOLD`, SMALL `rl.SKYBLUE` — via a `asteroid_color(radius)` sibling to `asteroid_score`. The field becomes readable at a glance.
3. **Medium:** A high score that survives restarts: on game over, if `score > best`, write it to a file; load it at startup and show `BEST n` on the game-over screen. This is Snake 5.3's exact technique, transplanted.
4. **Hard:** Engine hum: a 60 Hz, 0.2 s beep looped while UP is held — guard with `if !rl.IsSoundPlaying(hum)` before `rl.PlaySound(hum)` so it never stacks. Then synthesize a second hum 20% higher and switch to it above 200 px/s (`rl.Vector2Length(ship.vel)`). Congratulations, you've invented the rev limiter.
5. **Easy:** Gamepad support (lesson 2.3's promise): with `rl.IsGamepadAvailable(0)`, rotate with the left stick (`rl.GetGamepadAxisMovement(0, .LEFT_X)`) and thrust with the bottom face button (`.RIGHT_FACE_DOWN`). Asteroids on a controller is a different, better game.

**Next:** [Module 8 — Capstone: Boids 🐦](../08-boids/01-the-flocking-rules.md)
