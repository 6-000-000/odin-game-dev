# 3.4 Polish: AI, sound, and juice

**Module:** 03-pong

## Goals

- Replace the second player with a beatable AI opponent
- Add synthesized sound effects (no asset files needed)
- Add hit particles and ball speed-up — the "juice" that makes it feel alive

## New concepts

| Concept | What it is |
|---|---|
| Puppet AI | The AI uses the same movement rules as the player, with an inferior brain |
| Deadzone | An intentional "do nothing" band that stops jitter |
| Juice | Particles, sounds, speed-up — cheap effects, huge feel |
| `unordered_remove` | O(1) removal while iterating a dynamic array backward |

## Walkthrough

### The AI: a worse player, not a smarter one

The right paddle keeps its exact player-movement mechanics; only the *decision* changes. The whole brain:

```odin
AI_MAX_SPEED :: 330   // slightly slower than the player — beatable
AI_DEADZONE  :: 8     // px; stops paddle jitter

update_ai :: proc(ai: ^Paddle, ball: Ball, dt: f32) {
	if ball.vel.x < 0 do return           // ball moving away — rest
	diff := ball.pos.y - ai.pos.y
	if abs(diff) < AI_DEADZONE do return  // close enough — don't twitch
	step: f32 = AI_MAX_SPEED * dt
	ai.pos.y += clamp(diff, -step, step)  // move toward ball, speed-capped
}
```

Three deliberate weaknesses make it fun to play against: it only tracks when the ball approaches (you can catch it resting), it moves slower than you (fast balls beat it), and the deadzone makes it look calm rather than robotic. **AI in arcade games is usually not about being smart — it's about being fun.** The two constants are your difficulty knobs; 330 vs your 400 is "normal". 400 is "impossible", 250 is "toddler".

In `main`, the opponent's `↑`/`↓` input lines disappear, replaced by one call — and the `clamp` that follows stays exactly as it was, because the AI is bound by the same movement rules as the player it replaced:

```odin
update_ai(&opponent, ball, dt)
opponent.pos.y = clamp(opponent.pos.y, PADDLE_H / 2, SCREEN_H - PADDLE_H / 2)
```

Two strings in the draw switch get reworded to match the new opponent — the title prompt becomes `"W/S to move — beat the AI to 10 — SPACE to start"` and the winner line becomes `player.score > opponent.score ? "YOU WIN!" : "AI WINS!"`. Cosmetic, but the snapshot has them, so your diff should too.

### Sounds: three synthesized beeps

Lesson 2.4's `make_beep` returns as a permanent tool — paddle hit (440 Hz), wall (220 Hz), score (660 Hz):

```odin
rl.InitAudioDevice()        // alongside InitWindow, from lesson 2.4
defer rl.CloseAudioDevice()

hit_sfx := make_beep(440, 0.08)
defer rl.UnloadSound(hit_sfx)
// ...
rl.PlaySound(hit_sfx)   // on paddle collision
```

Copy the audio machinery verbatim from the snapshot — that's **four** pieces, all under the `// --- audio ---` banner plus one constant: `SAMPLE_RATE :: 22050` (up in the constants block), the `append_u16le`/`append_u32le` byte helpers, and `make_beep` itself. Copy only the proc and you'll get compile errors for the other three. The three `rl.PlaySound` calls slot into blocks you already have: `hit_sfx` inside the paddle-collision `if`, `wall_sfx` (220 Hz, 0.06 s) inside both wall-bounce `if`s, `score_sfx` (660 Hz, 0.2 s) inside both out-of-bounds `if`s. From now on, "add a beep for X" is a two-minute task in any project — placeholder audio is a superpower because sound feedback changes how a game *feels to develop*, not just to play.

### Particles on impact

When the ball hits a paddle, burst 12 short-lived particles:

```odin
Particle :: struct {
	pos, vel: rl.Vector2,
	life:     f32,  // seconds remaining
}

spawn_particles :: proc(particles: ^[dynamic]Particle, pos, base_vel: rl.Vector2) {
	for _ in 0..<12 {
		angle := rand.float32_range(0, 2*math.PI)
		speed := rand.float32_range(60, 220)
		append(particles, Particle{
			pos  = pos,
			vel  = base_vel * 0.3 + {math.cos(angle), math.sin(angle)} * speed,
			life = rand.float32_range(0.2, 0.5),
		})
	}
}
```

Each particle inherits 30% of the ball's velocity plus a random radial burst. One honest detail: the spawn call is `spawn_particles(&particles, ball.pos, ball.vel)` placed *before* `ball.vel.x` flips, so the inherited 30% points along the incoming direction, not the rebound. It doesn't matter — the 60–220 px/s radial burst dwarfs the ~100 px/s bias, and the eye reads "impact" either way. (Swap the call to after the flip if you prefer the spray to follow the rebound.)

Declare the pool in `main`, next to the other game state — a dynamic array with the usual cleanup:

```odin
particles: [dynamic]Particle
defer delete(particles)
```

The update loop ages them and removes the dead:

```odin
for i := len(particles) - 1; i >= 0; i -= 1 {
	p := &particles[i]
	p.pos += p.vel * dt
	p.life -= dt
	if p.life <= 0 do unordered_remove(&particles, i)
}
```

**Iterate backward when removing.** Lesson 1.3 gave you `unordered_remove` — it swaps the last element into slot `i`, so a forward loop would skip that element. Iterating backward is the other half of the idiom: removal becomes safe and branch-free.

One placement detail: that update loop sits *outside* the state `switch` — particles keep drifting and fading on the title and game-over screens, so the menus never look frozen. Drawing is one loop, with alpha tied to remaining life:

```odin
for p in particles {
	rl.DrawCircleV(p.pos, 3, rl.Fade(rl.SKYBLUE, p.life * 2))
}
```

🌐 **Web dev callout — juice is your animation budget, spent differently**
> On the web, "juice" is CSS transitions and easing curves — the browser interpolates, you declare. Here, juice is *simulation*: 12 structs with velocity and a countdown, drawn as fading circles. The reason games do it this way is the same reason Flappy couldn't use `element.animate()`: the effect must interact with a world that keeps changing. Particles inherit the ball's velocity because they live in the same physics as everything else. The good news is the budget: a burst like this costs maybe 40 lines and zero assets. The CSS of game feel is just... more game.

### Speed-up: the difficulty curve

```odin
BALL_SPEEDUP :: 1.05
// on paddle hit:
ball.vel.x = -ball.vel.x * BALL_SPEEDUP
ball.vel.y = offset * rl.Vector2Length(ball.vel)  // aim scales with new speed
```

Every return is 5% faster. Rallies naturally escalate — early game is calm, late rallies are knife-fights. Note `rl.Vector2Length(ball.vel)` keeps the aiming math proportional after the speed-up. One constant, and the game now has pacing.

## Full listing

Runnable snapshot: [`code/04-polish/main.odin`](code/04-polish/main.odin) — the complete game.

```sh
odin run 03-pong/code/04-polish
```

## Checkpoint

A full Pong: title screen, a calm-but-dangerous AI, escalating rallies, impact particles, and three sound effects. Play three matches. Then tweak `AI_MAX_SPEED` and `BALL_SPEEDUP` and play again — feel how two constants redesign the experience. **That's game design.**

## Exercises

1. **Easy:** Add a serve delay — after a score, freeze the ball at center for 0.7 s (`serve_timer: f32`) before it moves. Much more readable.
2. **Easy:** Make the particles the color of the paddle that was hit (pass a `color: rl.Color` into `spawn_particles`).
3. **Medium:** Add screen shake on score: a `shake: f32` timer set to 0.3 on score; while active, offset *everything* drawn by a small random vector (`rand.float32_range(-shake, shake) * 10`). Cheap, and it lands like a punch.
4. **Medium:** Make the AI *human*: only let it update its target every 0.15 s (a timer stores `target_y`; between updates it moves toward the stale value). Reaction-time simulation beats speed-capping for believable opponents.
5. **Hard:** Predictive AI: compute where the ball's y will be when it reaches the paddle's x (account for wall bounces for the real flex). Then make it *miss* on purpose 15% of the time. Perfect prediction + occasional error = a boss fight.

**Next:** [Module 4 — Project: Breakout](../04-breakout/01-paddle-and-ball.md)
