# 2.4 Textures, sprites, and audio

**Module:** 02-game-dev-foundations

## Goals

- Load and draw textures, including rotated/scaled/partial draws (`DrawTexturePro`)
- Animate a sprite by stepping through frames of a sprite sheet
- Play sound effects and understand the music streaming model
- Generate assets *in code* — so this course needs zero binary files

## New concepts

| Concept | What it is |
|---|---|
| `rl.Texture2D` | An image living in GPU memory |
| `rl.Image` | Pixel data in CPU memory — manipulated, then uploaded |
| `DrawTexturePro` | The full-control draw: source rect → dest rect, origin, rotation |
| `rl.Sound` / `rl.Music` | Short fully-loaded clips vs. streamed long audio |

## Walkthrough

## Images, textures, and the Load/Unload discipline

raylib resources come in pairs — you load, you unload, `defer` makes it tidy:

```odin
// From a file (the normal way once you have art):
texture := rl.LoadTexture("assets/player.png")
defer rl.UnloadTexture(texture)

// Generated in code (what this course does — zero asset files!):
img := rl.GenImageChecked(64, 64, 8, 8, rl.WHITE, rl.DARKGRAY)
texture2 := rl.LoadTextureFromImage(img)
rl.UnloadImage(img)              // CPU copy no longer needed after upload
defer rl.UnloadTexture(texture2)
```

An `Image` is CPU-side pixels (you can draw into it, recolor it, resize it). `LoadTextureFromImage` uploads to the GPU as a `Texture2D`; the `Image` can then be freed. Sounds follow the same shape: `LoadSound`/`UnloadSound`, `LoadMusicStream`/`UnloadMusicStream`.

🌐 **Web dev callout — GPU memory is a manual cache**
> Think of `Texture2D` like a decoded image the browser holds for `<img>`, except *you* own its lifetime. Forgetting `UnloadTexture` leaks GPU memory exactly like forgetting `URL.revokeObjectURL` leaks blobs — the tracking allocator won't catch this one (it's raylib's memory, not Odin's), so the `defer` habit matters.

## Drawing textures: from simple to full control

```odin
rl.DrawTexture(tex, 100, 100, rl.WHITE)                      // top-left at (100,100)
rl.DrawTextureV(tex, {100, 100}, rl.WHITE)                   // Vector2
rl.DrawTextureEx(tex, {100, 100}, 45, 2, rl.WHITE)           // rotation°, scale

// The one you'll use for real sprites — source rect → dest rect:
rl.DrawTexturePro(
	tex,
	{0, 0, 32, 32},              // source: which pixels of the sheet
	{pos.x, pos.y, 32, 32},      // dest: where + how big on screen
	{16, 16},                    // origin: pivot inside dest (center = rotate in place)
	angle,                       // rotation degrees (clockwise, y-down world)
	rl.WHITE,                    // tint (WHITE = unchanged; RED tints, Fade ghosts)
)
```

The **origin** is the subtle one: rotation pivots around it. For a sprite that spins in place, the origin is its center — half the dest size. The tint multiplies the texture's colors: `rl.WHITE` is identity, `rl.RED` reddens, `rl.Fade(rl.WHITE, 0.5)` makes a ghost.

## Sprite animation = changing the source rectangle

A sprite sheet is one texture with frames in a row (or grid). Animation is just math on which sub-rectangle you draw:

```odin
FRAME_W :: 32
frame := int(rl.GetTime() * 8) % 2             // 8 fps flip between 2 frames
src := rl.Rectangle{f32(frame) * FRAME_W, 0, FRAME_W, 32}
rl.DrawTextureRec(sheet, src, pos, rl.WHITE)
```

That's the entire technique behind every 2D sprite animation you've ever seen. Frame index from time (or from a timer you reset on state changes), source rect from frame index.

## Audio: sounds and music

```odin
rl.InitAudioDevice()
defer rl.CloseAudioDevice()

jump := rl.LoadSound("assets/jump.wav")
defer rl.UnloadSound(jump)
if rl.IsKeyPressed(.SPACE) do rl.PlaySound(jump)     // fire and forget, overlaps freely
```

`Sound` is fully in memory — short effects, can overlap (play jump 5 times in 5 frames, all 5 audible). `Music` is streamed from disk for long tracks and needs `rl.UpdateMusicStream(music)` every frame:

```odin
music := rl.LoadMusicStream("assets/theme.ogg")
rl.PlayMusicStream(music)
// every frame: rl.UpdateMusicStream(music)
```

## Generating a sound in code

raylib can load a WAV from a memory buffer (`rl.LoadWaveFromMemory`). A WAV file is a 44-byte header plus PCM samples, so ~20 lines of Odin synthesizes a beep — a sine wave with a decay envelope:

```odin
sample := i16(math.sin(2 * math.PI * frequency * t) * 12000 * envelope)
```

(The trig needs one new line at the top of the file: `import "core:math"`.)

The full listing below contains a reusable `make_beep(frequency, duration)` proc. Drop it into any project to get placeholder audio with zero asset files — real games later swap in `.wav` files from a pack like [kenney.nl](https://kenney.nl) (free, excellent).

## Full listing

Runnable snapshot: [`code/04-textures-audio/main.odin`](code/04-textures-audio/main.odin) — builds a 2-frame sprite sheet procedurally, animates a little "bot" that walks with WASD (rotating to face movement), and synthesizes two beeps (move-blip on wall bump, chirp on SPACE).

```sh
odin run 02-game-dev-foundations/code/04-textures-audio
```

## Checkpoint

- The bot animates (two frames alternating) while moving and rotates toward its heading
- SPACE plays a chirp; bumping a wall blips
- You understand every parameter of that `DrawTexturePro` call — read it again until you do

## Exercises

1. **Easy:** Change the checkerboard generation to 4 frames (walk cycle of 4 poses — different colored legs is fine). Adjust the frame math.
2. **Easy:** Make the bot pulse its tint with `rl.Fade(rl.WHITE, 0.6 + 0.4*math.sin(t*6))` while SPACE is held.
3. **Medium:** Add a second `make_beep` at double frequency with half duration as a "jump" sound on SPACE, and make the bot hop (offset its y by `-abs(sin(hop_t)) * 20` for 0.4 s).
4. **Medium:** Stretch goal — modify `make_beep` to mix two sines an octave apart (`sin(2πft) + 0.5*sin(4πft)`). Notice how much less "pure" the tone feels. Congratulations, you're doing additive synthesis.

**Next:** [2.5 The architecture roadmap](05-architecture-roadmap.md)
