# 7.1 Ship and thrust

**Module:** 07-asteroids

## Goals

- Rotate a ship and thrust along its facing — vector physics with real inertia
- Store angles in degrees, convert to radians only for the math (`rl.DEG2RAD`)
- Damping: velocity that persists after you let go, slowly bleeding off
- Screen wrapping: exit one edge fully, re-enter on the opposite side

## New concepts

| Concept | What it is |
|---|---|
| Facing vector | `{cos θ, sin θ}` — the ship's nose direction as a unit vector |
| Thrust | Acceleration along the facing: `vel += facing * THRUST * dt` |
| Damping | `vel *= 1 - DAMPING * dt` — friction, applied every frame |
| Screen wrapping | Teleport to the opposite edge once *fully* off-screen |

## Walkthrough

### The ship, and the −90° convention

```odin
Ship :: struct {
	pos:    rl.Vector2,
	vel:    rl.Vector2,
	angle:  f32, // degrees; 0 points UP the screen
	radius: f32,
}
```

We keep `angle` in **degrees** because humans (and raylib's polygon drawing) think in degrees. The trig in `core:math` thinks in radians. The conversion lives in exactly one place:

```odin
ship_facing :: proc(angle: f32) -> rl.Vector2 {
	rad := (angle - 90) * rl.DEG2RAD
	return {math.cos(rad), math.sin(rad)}
}
```

Why the `- 90`? `{cos 0, sin 0}` is `{1, 0}` — pointing **right**. And because screen y points *down* (lesson 2.2), angle 90° in screen space is straight *down*. Shifting the circle by −90° puts angle 0 where the player expects it: up the screen. Every point on the ship's body goes through the same helper (`ship_point`), so there is one place to get this right and zero places to get it wrong.

### Rotate, thrust, damp, integrate

```odin
if rl.IsKeyDown(.LEFT) do ship.angle -= ROT_SPEED * dt
if rl.IsKeyDown(.RIGHT) do ship.angle += ROT_SPEED * dt

thrusting := rl.IsKeyDown(.UP)
if thrusting {
	ship.vel += ship_facing(ship.angle) * THRUST * dt
}

ship.vel *= 1 - DAMPING * dt // inertia: speed bleeds off slowly
ship.pos += ship.vel * dt
wrap(&ship.pos, ship.radius)
```

Notice what's *not* here: nothing sets position directly. Thrust **adds** velocity along the nose; damping removes a fraction of velocity every frame; integration turns velocity into position. The ship keeps drifting after you release UP, and rotating doesn't change your velocity — only the direction of *future* thrust. That disconnect between where you point and where you're going is the entire Asteroids feel, in three lines.

### Screen wrapping

```odin
wrap :: proc(pos: ^rl.Vector2, radius: f32) {
	if pos.x < -radius do pos.x += SCREEN_W + radius * 2
	if pos.x > SCREEN_W + radius do pos.x -= SCREEN_W + radius * 2
	if pos.y < -radius do pos.y += SCREEN_H + radius * 2
	if pos.y > SCREEN_H + radius do pos.y -= SCREEN_H + radius * 2
}
```

Two details, both deliberate:

1. **Wait until fully past the edge** (`-radius`, not `0`). The ship exits completely before teleporting, so it never visibly pops mid-screen.
2. **Preserve the overshoot** (`+= SCREEN_W + radius * 2` rather than `= SCREEN_W`). A ship 3 px past the left edge reappears 3 px past the right, keeping speed and trajectory exact.

The proc takes a pointer and a radius — every entity in this project (ship, asteroids, bullets) reuses it.

### Drawing a triangle from an angle

The ship is a dart: a nose at the ship's angle, two wings swept back at ±140°:

```odin
nose := ship_point(ship.pos, ship.angle, ship.radius)
wing_l := ship_point(ship.pos, ship.angle + 140, ship.radius * 0.8)
wing_r := ship_point(ship.pos, ship.angle - 140, ship.radius * 0.8)
rl.DrawTriangleLines(nose, wing_l, wing_r, rl.WHITE)
```

And the thruster flame, drawn only while UP is held:

```odin
tip := ship_point(ship.pos, ship.angle + 180, rand.float32_range(ship.radius * 0.9, ship.radius * 1.7))
base_l := ship_point(ship.pos, ship.angle + 160, ship.radius * 0.5)
base_r := ship_point(ship.pos, ship.angle - 160, ship.radius * 0.5)
rl.DrawTriangle(base_l, tip, base_r, rl.ORANGE)
```

The flame tip's length is re-randomized **every frame** — 60 random lengths a second reads as flicker. It's the cheapest animation technique that exists, and you'll keep using it (the boids capstone uses it for a predator's pulse).

🌐 **Web dev callout — velocity + damping is inertia scrolling**
> If you've ever built momentum scrolling or a springy drag in a `requestAnimationFrame` loop — track velocity on pointermove, keep integrating after release, multiply by 0.95 each frame until it dies — you have written this exact integrator. Games just never stop the loop. The discipline that differs: never assume 60 fps. `vel *= 0.95` means "keep 95% per *frame*", which is a different friction at 144 Hz than at 30 Hz. `vel *= 1 - DAMPING * dt` is the linear fix; the exercises make it exact with `math.pow`.

## Full listing

Runnable snapshot: [`code/01-ship-and-thrust/main.odin`](code/01-ship-and-thrust/main.odin)

```sh
odin run 07-asteroids/code/01-ship-and-thrust
```

## Checkpoint

A white wireframe dart sits center-screen. LEFT/RIGHT spin it in place at 220°/s; holding UP fires the flickering orange flame and accelerates along the nose; releasing UP leaves it drifting, slowing gently. Fly off any edge: the ship vanishes completely, then re-enters on the far side, still moving. Spin 180° while drifting and thrust to brake with the engine. That little dance is the whole game — the next three lessons just give you things to dance *with*.

## Exercises

1. **Easy:** Draw the velocity vector: `rl.DrawLineV(ship.pos, ship.pos + ship.vel * 0.25, rl.GREEN)`. Rotate without thrusting and watch the green line refuse to follow the nose. Facing ≠ velocity — seeing it makes it click.
2. **Easy:** Find a feel. Try `THRUST 600 / DAMPING 0.2` (ice rink) and `THRUST 300 / DAMPING 3.0` (molasses). Keep your favorite and write one comment line defending the choice.
3. **Medium:** Make damping exactly frame-rate independent: replace `vel *= 1 - DAMPING * dt` with `vel *= math.pow(1 - DAMPING, dt)` ("keep (1−D) of velocity *per second*, raised to the dt power"). Run both versions at `rl.SetTargetFPS(30)` and `rl.SetTargetFPS(144)` and compare how far the ship drifts after a fixed thrust burst.
4. **Medium:** Brakes: while DOWN is held, apply `ship.vel *= 1 - 4 * dt`. Explain (in a comment) why this feels better than `ship.vel = {}` — and which of the two can leave a tiny, never-quite-zero residual velocity.

**Next:** [7.2 The entity pool](02-entity-pool.md)
