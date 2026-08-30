# 4.1 Paddle and ball, revisited

**Module:** 04-breakout

## Goals

- Rebuild Pong's paddle-and-ball along the other axis: a horizontal paddle on a tall field
- Keep the ball *stuck* to the paddle until the player serves
- Turn Pong's offset-aim into a capped bounce angle at a constant ball speed
- Treat the bottom edge as a hazard instead of a wall

## New concepts

| Concept | What it is |
|---|---|
| Attachment flag | `stuck: bool` on the ball — while set, it rides the paddle every frame |
| Serve | Clearing `stuck` and giving the ball a fresh velocity at a slight random angle |
| Angle-capped bounce | Map where the ball hits the paddle to an angle, rebuild `vel` with `sin`/`cos` |
| Constant speed | `vel` is reconstructed at exactly `BALL_SPEED` on every paddle hit — no speedup |

## Walkthrough

### Same game, rotated 90°

Everything from Pong 3.2 is here, transposed. The screen is 800×600 now — Breakout wants a tall field — and the paddle is wide, short, and moves along **x**, clamped to the screen. The constants block sets the shape of the whole game:

```odin
PADDLE_W :: 100
PADDLE_H :: 16
PADDLE_SPEED :: 520
PADDLE_Y :: SCREEN_H - 40 // the paddle's resting height, fixed

BALL_RADIUS :: 8
BALL_SPEED :: 420 // constant — no Pong-style speedup here
```

```odin
if rl.IsKeyDown(.A) || rl.IsKeyDown(.LEFT) do paddle.pos.x -= PADDLE_SPEED * dt
if rl.IsKeyDown(.D) || rl.IsKeyDown(.RIGHT) do paddle.pos.x += PADDLE_SPEED * dt
paddle.pos.x = clamp(paddle.pos.x, PADDLE_W / 2, SCREEN_W - PADDLE_W / 2)
```

`paddle_rect` makes the trip too — Pong 3.2's proc, unchanged (`{p.pos.x - PADDLE_W / 2, p.pos.y - PADDLE_H / 2, PADDLE_W, PADDLE_H}`) — and drawing the paddle is one `rl.DrawRectangleRec(paddle_rect(paddle), rl.WHITE)`.

### The stuck ball

Breakout doesn't auto-serve. The ball sits on the paddle until SPACE:

```odin
Ball :: struct {
	pos:   rl.Vector2,
	vel:   rl.Vector2,
	stuck: bool, // riding the paddle, waiting for SPACE
}

stick_ball :: proc(b: ^Ball, p: Paddle) {
	b.stuck = true
	b.pos = {p.pos.x, p.pos.y - PADDLE_H / 2 - BALL_RADIUS}
	b.vel = {}
}
```

While `stuck` is set, every frame copies the paddle's x into the ball — the ball follows the paddle for free, and that one flag decides whether the whole movement/collision block runs:

```odin
if ball.stuck {
	ball.pos = {paddle.pos.x, paddle.pos.y - PADDLE_H / 2 - BALL_RADIUS}
	if rl.IsKeyPressed(.SPACE) do serve_ball(&ball)
} else {
	// movement, walls, paddle collision ...
}
```

The serve is a slight random tilt off straight-up — the same polar→cartesian conversion as Pong's serve:

```odin
serve_ball :: proc(b: ^Ball) {
	angle := rand.float32_range(-0.5, 0.5) // slight random tilt off straight-up
	b.vel = {BALL_SPEED * math.sin(angle), -BALL_SPEED * math.cos(angle)}
	b.stuck = false
}
```

Straight-up is `{0, -BALL_SPEED}`; rotating by `angle` turns that into `{sin, -cos} × speed`. You'll write this pattern every time something launches at an angle.

While the ball sits stuck, the snapshot also draws a small centered hint — `MeasureText` (lesson 2.2) doing the centering math, drawn only in the stuck state:

```odin
if ball.stuck {
	w := rl.MeasureText("SPACE to serve", 20)
	rl.DrawText("SPACE to serve", (SCREEN_W - w) / 2, SCREEN_H / 2 + 80, 20, rl.GRAY)
}
```

### Walls: three of them

Left, right, top — same reflect-and-reposition mantra as Pong, velocity-sign check included:

```odin
if ball.pos.x < BALL_RADIUS && ball.vel.x < 0 {
	ball.vel.x = -ball.vel.x
	ball.pos.x = BALL_RADIUS
}
```

The fourth wall is missing on purpose: the bottom edge is the *kill zone*. Falling past it just respawns the ball on the paddle for now — lesson 4.3 makes it cost a life:

```odin
// lost at the bottom: respawn stuck (lives arrive in lesson 4.3)
if ball.pos.y > SCREEN_H + BALL_RADIUS {
	stick_ball(&ball, paddle)
}
```

### The paddle bounce: offset-aim, rotated

Pong mapped `(ball.y - paddle.y)` to `vel.y`. Breakout maps `(ball.x - paddle.x)` to a **bounce angle**, then rebuilds the whole velocity at constant speed:

```odin
if ball.vel.y > 0 && rl.CheckCollisionCircleRec(ball.pos, BALL_RADIUS, paddle_rect(paddle)) {
	ball.pos.y = paddle.pos.y - PADDLE_H / 2 - BALL_RADIUS
	offset := clamp((ball.pos.x - paddle.pos.x) / (PADDLE_W / 2), -1, 1)
	angle := offset * MAX_BOUNCE_ANGLE
	ball.vel = {BALL_SPEED * math.sin(angle), -BALL_SPEED * math.cos(angle)}
}
```

- `offset` is −1 at the paddle's left tip, 0 dead center, +1 at the right tip — same math as Pong, other axis.
- `MAX_BOUNCE_ANGLE :: math.PI / 3` caps the exit at 60° off vertical: edge hits go steep but never degenerate-horizontal. (This is Pong 3.2's exercise 4, built in.)
- Rebuilding `vel` from scratch means **speed never drifts** — there is no `BALL_SPEEDUP` this time. Breakout's difficulty comes from level design, not rally escalation.
- The `ball.vel.y > 0` guard is the velocity-sign check again: only catch balls actually moving down, so a ball can't be grabbed from underneath.

🌐 **Web dev callout — `stuck` is drag-and-drop**
> You've built this flag before: `dragging = true` on mousedown, copy pointer coordinates into the element on every mousemove, `dragging = false` on mouseup. Here the "pointer" is the paddle, "mousemove" is the per-frame update, and "mouseup" is SPACE. UI frameworks hide the loop; the game loop *is* the loop — but the state machine is identical.

## Full listing

Runnable snapshot: [`code/01-paddle-and-ball/main.odin`](code/01-paddle-and-ball/main.odin)

```sh
odin run 04-breakout/code/01-paddle-and-ball
```

## Checkpoint

A wide paddle slides along the bottom (A/D or arrow keys) with the ball riding on top. SPACE serves at a slight random angle; the ball bounces off the side walls, the ceiling, and the paddle — shallow off the center, steep off the edges — at a perfectly constant speed. Falling off the bottom respawns the ball on the paddle.

## Exercises

1. **Easy:** Steer with the mouse instead of the keyboard: `paddle.pos.x = f32(rl.GetMouseX())`, keeping the clamp. Most Breakout clones play better with a mouse — feel why.
2. **Easy:** While the ball is stuck, draw an aim hint: a thin line from the ball upward at a fixed angle (`rl.DrawLineV`, endpoint = ball pos + `{sin, -cos} * 80`).
3. **Medium:** Paddle momentum: track the paddle's velocity (`(pos.x - prev_x) / dt`, stored each frame) and add 20% of it to the ball's `vel.x` on paddle hits, then renormalize to `BALL_SPEED`. "Flicking" the paddle puts english on the ball.
4. **Medium:** Enforce a minimum horizontal speed: after every paddle bounce, if `abs(ball.vel.x) < 60`, set it to ±60 (preserving sign) and renormalize. No more interminable near-vertical rallies.
5. **Hard:** Aimed serves: while the ball is stuck, LEFT/RIGHT adjusts a `serve_angle` clamped to ±`MAX_BOUNCE_ANGLE`, an arrow shows the aim (exercise 2's hint, made live), and SPACE serves at exactly that angle instead of a random one. Deterministic serves turn the opening into a skill shot — pinball's plunger, basically.

**Next:** [4.2 The brick grid](02-brick-grid.md)
