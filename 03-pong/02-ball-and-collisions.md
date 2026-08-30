# 3.2 Ball and collisions

**Module:** 03-pong

## Goals

- Add a ball with velocity, served at a random angle
- Bounce off the top/bottom walls
- Collide with paddles using circle-vs-rectangle (AABB) collision
- Steer the ball by *where* it hits the paddle — Pong's actual gameplay
- Reset the rally when the ball leaves the screen (scoring arrives next lesson)

## New concepts

| Concept | What it is |
|---|---|
| Velocity | `vel: rl.Vector2` — direction × speed, integrated with `pos += vel * dt` |
| AABB | Axis-Aligned Bounding Box — an unrotated rectangle, the workhorse of 2D collision |
| `CheckCollisionCircleRec` | raylib's circle-vs-rectangle test |
| Reflection | `vel.x = -vel.x` — the bounce |

## Walkthrough

### Velocity: position's rate of change

```odin
Ball :: struct {
	pos: rl.Vector2,
	vel: rl.Vector2,
}
```

Two constants join the block at the top of the file:

```odin
BALL_RADIUS :: 8
BALL_SPEED :: 350
```

This lesson also needs two new imports at the top of the file, next to `import rl "vendor:raylib"`:

```odin
import "core:math"       // cos, sin, PI
import "core:math/rand"  // float32_range
```

Movement is one line: `ball.pos += ball.vel * dt`. Everything else in this lesson is about deciding what `vel` *is*. Drawing is one call — `rl.DrawCircleV(ball.pos, BALL_RADIUS, rl.WHITE)` next to the two `draw_paddle` calls.

The serve picks a shallow random angle and a random side — you never want the same serve twice:

```odin
ball_serve_vel :: proc() -> rl.Vector2 {
	angle := rand.float32_range(-0.4, 0.4)  // radians off horizontal
	dir: f32 = rl.GetRandomValue(0, 1) == 0 ? -1 : 1
	return {dir * BALL_SPEED * math.cos(angle), BALL_SPEED * math.sin(angle)}
}
```

`{cos θ, sin θ}` is the unit vector at angle θ — multiplying by speed turns "a direction" into "a velocity". This polar→cartesian conversion shows up in every game with angled movement; Asteroids is made of it. (`rl.GetRandomValue(0, 1)` is raylib's integer roll, inclusive of both ends — here a coin flip for which side serves.)

### Wall bounces: reflect and reposition

```odin
if ball.pos.y < BALL_RADIUS && ball.vel.y < 0 {
	ball.vel.y = -ball.vel.y
	ball.pos.y = BALL_RADIUS
}
```

Two details here, both load-bearing:

1. **Check the velocity's sign too** (`vel.y < 0`). Without it, a ball that's already moving downward but still overlapping the edge gets flipped *upward* every frame and sticks to the wall. Only bounce balls that are actually heading out.
2. **Snap the position back inside** (`pos.y = BALL_RADIUS`). The ball moved *past* the boundary this frame; if you only flip velocity it can sit outside for a frame — visible, and it can re-trigger the condition. Reflect velocity, correct position. This pair is the collision mantra for the whole course.

The bottom wall is the same test mirrored — `ball.pos.y > SCREEN_H - BALL_RADIUS && ball.vel.y > 0`, snapping to `SCREEN_H - BALL_RADIUS`. It's in the snapshot; don't forget it, or every rally ends at the floor.

### `paddle_rect`: one conversion, two consumers

Collision needs the paddle as an `rl.Rectangle`, and drawing needs the same top-left corner — so the conversion from lesson 3.1's `draw_paddle` gets promoted into its own proc, and `draw_paddle` becomes a one-liner over it:

```odin
paddle_rect :: proc(p: Paddle) -> rl.Rectangle {
	return {p.pos.x - PADDLE_W / 2, p.pos.y - PADDLE_H / 2, PADDLE_W, PADDLE_H}
}

draw_paddle :: proc(p: Paddle, color: rl.Color) {
	rl.DrawRectangleRec(paddle_rect(p), color)
}
```

One conversion, two consumers (render + collision). If the paddle's shape ever changes, you edit one proc and the picture and the physics stay in sync.

### Paddle collision: circle vs AABB

raylib does the hard geometry; we do the consequences:

```odin
paddles := [2]Paddle{player, opponent}
for p in paddles {
	if rl.CheckCollisionCircleRec(ball.pos, BALL_RADIUS, paddle_rect(p)) {
		ball.vel.x = -ball.vel.x
		ball.pos.x = p.pos.x + (ball.pos.x > p.pos.x ? 1 : -1) * (PADDLE_W / 2 + BALL_RADIUS)

		offset := clamp((ball.pos.y - p.pos.y) / (PADDLE_H / 2), -1, 1)
		ball.vel.y = offset * BALL_SPEED
	}
}
```

Bundling both paddles into a `[2]Paddle` array lets one loop handle left and right identically — no duplicated collision block to drift out of sync. (The loop iterates *copies*; that's fine, we only read the paddle and mutate the ball.)

The push-out line uses the ternary to place the ball on the correct *side* of the paddle (right side of the left paddle, left side of the right paddle) so it can't get trapped inside and double-bounce.

The `offset` math is the game design: `(ball.y - paddle.y) / half_height` is −1 at the paddle's top edge, 0 dead center, +1 at the bottom. Mapping that to `vel.y` means **center hits go straight, edge hits go steep** — the player aims by positioning the paddle. Pong with `vel.y = -vel.y` bouncing is unplayable chaos; Pong with offset aiming is a skill game. One line of math is the difference.

### Out of bounds: reset the rally

The last piece has no scoring yet — that's next lesson — so for now a missed ball just re-serves:

```odin
if ball.pos.x < -BALL_RADIUS || ball.pos.x > SCREEN_W + BALL_RADIUS {
	ball.pos = {SCREEN_W / 2, SCREEN_H / 2}
	ball.vel = ball_serve_vel()
}
```

The boundary test is `< -BALL_RADIUS`, not `< 0`: the ball must be *fully* off-screen before the reset, so it visibly leaves play instead of teleporting while half-visible. Same reset on both sides; next lesson replaces it with score-keeping.

🌐 **Web dev callout — collision as intersection tests**
> If you've ever written `rect1.left < rect2.right && ...` for drag-and-drop or scroll-into-view, you've written AABB collision. Games just do it every frame for every moving pair. raylib's `CheckCollision*` family covers the common pairs (rec/rec, circle/circle, circle/rec, point/*) — the [cheatsheet](https://www.raylib.com/cheatsheet/cheatsheet.html) lists them all. For 2D arcade games, these primitives are genuinely all you need.

## Full listing

Runnable snapshot: [`code/02-ball-and-collisions/main.odin`](code/02-ball-and-collisions/main.odin)

```sh
odin run 03-pong/code/02-ball-and-collisions
```

## Checkpoint

The ball serves at a random angle, bounces off top/bottom walls, reflects off paddles with aimable angles, and resets to center when it exits left or right. Play a few rallies two-player: hit with the paddle's edge and watch the ball take a steep path.

## Exercises

1. **Easy:** Change the serve so it always goes toward the player who was just scored on (pass a `toward_left: bool`). The next lesson's snapshot does this — try it yourself first.
2. **Easy:** Draw the ball as a square instead of a circle (`DrawRectangleV` centered on `ball.pos`). The collision still uses the circle radius — notice that gameplay barely changes. Collision shape ≠ render shape, and that's normal.
3. **Medium:** Add spin: while the ball is in flight, holding W or S adds ±200 to `vel.y` per second (clamped). This breaks "real" Pong rules and is extremely fun.
4. **Medium:** Cap the bounce angle: after computing `offset`, reconstruct `vel` so its angle never exceeds 60° from horizontal (hint: `math.atan2`, clamp the angle, `cos`/`sin` back). This prevents degenerate near-vertical rallies.
5. **Hard:** Face detection for the paddle: when the ball overlaps a paddle's *top or bottom edge* instead of its face, reflect `vel.y` instead of `vel.x` (hint: compare x- and y-penetration depths, like Breakout 4.2 will formalize). Edge catches become sharp angled returns — and the "ball trapped inside the paddle" double-bounce dies for good.

**Next:** [3.3 Scoring and game states](03-scoring-and-game-states.md)
