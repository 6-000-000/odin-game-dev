# 6.1 Gravity and flap

**Module:** 06-flappy-bird

## Goals

- A bird with real physics: constant gravity, one-button flap
- Learn the sign lesson: **+y is down**, so up is a *negative* velocity
- Impulse vs. force: flap *sets* velocity, it never adds
- Three states — Title (bobbing, no physics), Playing, Dead (physics, no input)

## New concepts

| Concept | What it is |
|---|---|
| Gravity | Constant acceleration: `vel.y += GRAVITY * dt` every frame |
| Impulse | An instant velocity change — `vel.y = FLAP_VELOCITY`, an assignment, not an accumulation |
| Euler integration | `vel += acc * dt` then `pos += vel * dt` — the two-line engine of every platformer |
| Sign convention | Y grows downward, so gravity is positive and the flap velocity is negative |
| Idle bob | `pos.y = base + sin(t * 3) * 10` — life on the title screen with zero physics |

## Walkthrough

### The sign lesson

Every force in this game is vertical, and the vertical axis is upside-down compared to math class: **y grows toward the bottom of the screen.** So:

```odin
GRAVITY :: 1800 // px/s^2, added to vel.y every frame
FLAP_VELOCITY :: -520 // px/s; negative is UP, because +y points DOWN

BIRD_X :: 120      // the bird hangs here, 120px from the left, forever
BIRD_RADIUS :: 14
```

Gravity is a *positive* number (it pulls the bird toward larger y, i.e. the floor). The flap is a *negative* number (it pushes the bird toward smaller y, i.e. the sky). If you ever find a bird that falls upward, a sign is flipped somewhere — this is the single most common bug in 2D games, and it always comes from forgetting which way y points.

### Integration: two lines

```odin
bird.vel.y += GRAVITY * dt
bird.pos += bird.vel * dt
```

The first line says "falling speeds up, forever." The second is the movement you already know from Pong. Together they're **Euler integration**: acceleration changes velocity, velocity changes position, in that order, every frame. That ordering matters — integrating velocity first means a flap this frame moves the bird this frame, which is exactly the responsiveness Flappy lives or dies on.

### Impulse: set, don't add

```odin
if flap_pressed() {
	bird.vel.y = FLAP_VELOCITY // impulse: SET the velocity, never add to it
}
```

The tempting mistake is `vel.y += FLAP_VELOCITY`. With `+=`, two quick flaps stack into a super-jump and the game becomes a helicopter. With `=`, every flap is identical: whatever your current velocity — falling fast, hovering, just flapped — it's *replaced* by −520. The bird's trajectory after a flap is always the same arc. That determinism is the entire game feel; Flappy is a rhythm game wearing a physics costume.

### Rotation from velocity

The bird pitches with its velocity, which sells the physics for free:

```odin
rotation := clamp(bird.vel.y * 0.08, -25, 90)
rl.DrawPoly(bird.pos, 3, bird.radius * 1.8, rotation, rl.YELLOW)
```

Just after a flap, `vel.y` is −520 → rotation clamps to −25° (nose up). At full fall, `vel.y` approaches 1125 → 90° (nose straight down). `DrawPoly` with 3 sides draws a triangle whose first vertex points along +x when rotation is 0, so a plain triangle reads as a bird facing right. One `clamp` maps "how fast am I falling" to "how panicked do I look."

The snapshot's `draw_bird` adds one more detail: an eye, placed at the nose so rotation reads instantly:

```odin
rad := rotation * rl.DEG2RAD
eye := bird.pos + rl.Vector2{math.cos(rad), math.sin(rad)} * bird.radius * 0.6
rl.DrawCircleV(eye, 3.5, rl.WHITE)
```

Watch the units on those adjacent lines — this is *the* gamedev unit trap: **raylib takes degrees** (`DrawPoly`'s rotation, hence the `clamp(..., -25, 90)`), while **Odin's `core:math` takes radians** (`math.cos`, `math.sin`). `rl.DEG2RAD` is the bridge between them; forgetting it puts the eye 57× further around the circle than intended. Degrees at the raylib boundary, radians at the math boundary, convert at the seam.

### Three states, three physics policies

```odin
case .Title:
	// idle bob: a pure sine wave, no physics at all
	bird.pos.y = SCREEN_H / 2 + math.sin(time * 3) * 10
case .Playing:
	// flap + gravity + integrate
case .Dead:
	// gravity + integrate, no flap — the bird tumbles to the ground
```

The same `switch` drives update and draw, as always. The interesting design: **Dead keeps integrating.** On death the bird arcs and tumbles to the ground under gravity — you watch your mistake land. Only the input is taken away. The ceiling (`pos.y < radius`) clamps position and zeroes velocity — reaching the sky is embarrassing, not fatal. The ground is the death trigger.

Two small helpers round out the file: `reset_bird` centers the bird at `{BIRD_X, SCREEN_H / 2}` and zeroes its velocity (called at startup and again on R), and `draw_centered` is Pong 3.3's `MeasureText` helper, back for the title and death prompts.

🌐 **Web dev callout — this is an integrator, not an animation**
> On the web you'd reach for a CSS transition or `element.animate()` — declare a start and end, let the browser interpolate. Games can't do that: the flap's *end state* depends on inputs that haven't happened yet. So instead of describing trajectories, you describe *rates of change* and step them forward every frame: `v += a·dt; p += v·dt`. If you've ever hand-rolled inertia scrolling or a springy drag in a `requestAnimationFrame` loop (`x += vx; vx *= 0.95`), you've written Euler integration — gravity just adds the `vx += g·dt` line. The browser interpolates; games accumulate.

## Full listing

Runnable snapshot: [`code/01-gravity-and-flap/main.odin`](code/01-gravity-and-flap/main.odin)

```sh
odin run 06-flappy-bird/code/01-gravity-and-flap
```

## Checkpoint

The bird bobs gently on the title screen. SPACE (or click) starts the game: the bird kicks upward, arcs, and falls nose-first into the ground. Spamming flap pins it against the ceiling without dying. On death it tumbles, rests on the ground, and R returns to the title. Now change `GRAVITY` to `900` and re-run — the whole game turns to molasses. **Two constants are the entire difficulty curve.**

## Exercises

1. **Easy:** Moon mode: set `GRAVITY :: 1200` and `FLAP_VELOCITY :: -400`. Play it, then restore the originals. Feel how the *ratio* between the two constants — not either one alone — defines the game.
2. **Easy:** Draw the bird as a plain circle (`rl.DrawCircleV(bird.pos, bird.radius, rl.YELLOW)`) instead of a triangle. The rotation cue disappears and the game instantly feels worse — but the physics are untouched. Render shape ≠ simulation.
3. **Medium:** Add terminal velocity: after gravity, `bird.vel.y = min(bird.vel.y, 900)`. The fall stops accelerating and the late game gets floatier. Real Flappy does this.
4. **Medium:** Smooth the rotation: add a `rotation: f32` field to `Bird`, and each frame ease it toward the clamped target — `bird.rotation += (target - bird.rotation) * 12 * dt`. The nose now *chases* the fall instead of snapping to it.
5. **Hard:** Verify the physics against physics: from rest, one flap should peak at `v²/2g` ≈ 75 px and land back after `2v/g` ≈ 0.58 s. Instrument the sim (print max height and airtime over one flap), compare with the closed-form answers, and explain the small discrepancy (hint: Euler integration *overshoots* — which direction?). Sims you can check against math are sims you can trust.

**Next:** [6.2 The pipe spawner](02-pipe-spawner.md)
