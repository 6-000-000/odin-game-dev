# 3.3 Scoring and game states

**Module:** 03-pong

## Goals

- Track scores and a win condition
- Structure the game as a state machine: Title → Playing → Game_Over
- Draw a HUD: big scores, center line, state-dependent screens

## New concepts

| Concept | What it is |
|---|---|
| Game state enum | `Game_State :: enum { Title, Playing, Game_Over }` |
| State machine | `switch state` in both update and draw — each state has its own logic and screen |
| HUD | Scores and prompts drawn *after* (on top of) the world |

## Walkthrough

### The state machine

Right now the game starts mid-rally and never ends. Real games are always in exactly one *state*, and each state has its own rules for input, update, and drawing. An enum + two `switch`es is the entire architecture:

```odin
Game_State :: enum {
	Title,
	Playing,
	Game_Over,
}

state := Game_State.Title
```

```odin
switch state {
case .Title:
	if rl.IsKeyPressed(.SPACE) {
		player.score = 0
		opponent.score = 0
		state = .Playing
	}
case .Playing:
	// ... all the gameplay from lesson 3.2 ...
	if player.score >= WIN_SCORE || opponent.score >= WIN_SCORE {
		state = .Game_Over
	}
case .Game_Over:
	if rl.IsKeyPressed(.SPACE) do state = .Title
}
```

Notice what each state transition *does*: entering `.Playing` resets scores (initialization belongs at transitions, not scattered around). The draw switch mirrors it — Title draws the big title + prompt, Playing draws the ball, Game_Over draws the winner.

🌐 **Web dev callout — it's a reducer with a render function**
> This is the `useReducer` pattern you already know: a finite set of states, explicit transitions triggered by events (key presses, scores), and UI as a pure function of state. The difference: no library, no dispatch — just a `switch` that runs 60 times a second. Games lean on this pattern *constantly*: menus, pause, cutscenes, boss phases. When a game dev says "state machine", they mean exactly this enum+switch, not a framework.

### Scoring

The ball crossing the left edge scores for the opponent (and vice versa). The serve-after-score goes toward the player who was scored on — a small kindness built into real Pong:

```odin
if ball.pos.x < -BALL_RADIUS {
	opponent.score += 1
	ball.pos = {SCREEN_W/2, SCREEN_H/2}
	ball.vel = ball_serve_vel(true)   // serve left, toward the player
}
```

Note the out-of-bounds test is `< -BALL_RADIUS`: the ball fully leaves the screen before the point registers. Using `< 0` would trigger while half the ball is still visible — feels wrong, looks wrong.

### The HUD

Scores draw on top of everything, flanking the center line:

```odin
rl.DrawText(rl.TextFormat("%d", player.score), SCREEN_W/2 - 80, 20, 60, rl.WHITE)
rl.DrawText(rl.TextFormat("%d", opponent.score), SCREEN_W/2 + 50, 20, 60, rl.WHITE)
```

And two small helpers carry the whole UI — a dashed center line, and centered text using `MeasureText` (lesson 2.2):

```odin
draw_centered :: proc(text: cstring, y, font_size: i32, color: rl.Color) {
	w := rl.MeasureText(text, font_size)
	rl.DrawText(text, (SCREEN_W - w)/2, y, font_size, color)
}
```

Keep helpers like these at the bottom of the file and reuse them forever — `draw_centered` will serve every title screen you ever make.

## Full listing

Runnable snapshot: [`code/03-scoring-and-game-states/main.odin`](code/03-scoring-and-game-states/main.odin)

```sh
odin run 03-pong/code/03-scoring-and-game-states
```

## Checkpoint

Title screen ("PONG — first to 10 — SPACE to start"), a playable rallying game with live scores, a winner announcement at 10, and SPACE returns to title. You can play a full match start to finish. **It is now, officially, a game.**

## Exercises

1. **Easy:** Change `WIN_SCORE` to 3 for faster testing. Feel how one constant changes the whole rhythm.
2. **Easy:** Add a pause state (`.Paused`) entered with P from `.Playing`, showing a dimmed overlay (fullscreen rect with `rl.Fade(rl.BLACK, 0.5)`) and "PAUSED". P resumes. (Steal `rl.SetExitKey(.KEY_NULL)` from lesson 2.3 if you want ESC instead.)
3. **Medium:** Add a brief "3, 2, 1" countdown state between Title and Playing using a `countdown: f32` timer decremented by dt, drawing `int(countdown)+1` while it's above 0.
4. **Medium:** Track rally length (paddle hits this point) and flash it center-screen when it exceeds 10 — "RALLY x12!". Data lives in a variable that resets on every score.

**Next:** [3.4 Polish: AI, sound, and juice](04-polish.md)
