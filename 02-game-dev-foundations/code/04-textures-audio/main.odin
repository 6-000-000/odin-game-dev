package main

import "core:math"
import rl "vendor:raylib"

SCREEN_W :: 800
SCREEN_H :: 450

SPEED :: 250
FRAME_W :: 32
SAMPLE_RATE :: 22050

// --- little-endian byte writers for the WAV header ---
append_u16le :: proc(buf: ^[dynamic]u8, v: u16) {
	append(buf, u8(v), u8(v >> 8))
}
append_u32le :: proc(buf: ^[dynamic]u8, v: u32) {
	append(buf, u8(v), u8(v >> 8), u8(v >> 16), u8(v >> 24))
}

// Synthesize a decaying sine beep as an in-memory WAV, return a ready Sound.
make_beep :: proc(frequency, duration: f32) -> rl.Sound {
	sample_count := int(f32(SAMPLE_RATE) * duration)
	data_size := u32(sample_count * 2) // 16-bit mono

	wav: [dynamic]u8
	defer delete(wav)

	append(&wav, 'R', 'I', 'F', 'F')
	append_u32le(&wav, 36 + data_size)
	append(&wav, 'W', 'A', 'V', 'E')
	append(&wav, 'f', 'm', 't', ' ')
	append_u32le(&wav, 16)           // fmt chunk size
	append_u16le(&wav, 1)            // PCM
	append_u16le(&wav, 1)            // mono
	append_u32le(&wav, SAMPLE_RATE)
	append_u32le(&wav, SAMPLE_RATE * 2) // byte rate
	append_u16le(&wav, 2)            // block align
	append_u16le(&wav, 16)           // bits per sample
	append(&wav, 'd', 'a', 't', 'a')
	append_u32le(&wav, data_size)

	for i in 0 ..< sample_count {
		t := f32(i) / f32(SAMPLE_RATE)
		envelope := 1 - t/duration // linear decay
		sample := i16(math.sin(2 * math.PI * frequency * t) * 12000 * envelope)
		append_u16le(&wav, transmute(u16)sample)
	}

	wave := rl.LoadWaveFromMemory(".wav", raw_data(wav), i32(len(wav)))
	sound := rl.LoadSoundFromWave(wave)
	rl.UnloadWave(wave)
	return sound
}

// Build a 2-frame 32x32 "robot" sprite sheet procedurally.
make_bot_texture :: proc() -> rl.Texture2D {
	img := rl.GenImageColor(FRAME_W * 2, 32, rl.BLANK)
	defer rl.UnloadImage(img)

	// frame 0: body + legs together
	rl.ImageDrawRectangle(&img, 4, 4, 24, 20, rl.SKYBLUE)
	rl.ImageDrawRectangle(&img, 10, 10, 4, 4, rl.DARKBLUE) // eye
	rl.ImageDrawRectangle(&img, 20, 10, 4, 4, rl.DARKBLUE)
	rl.ImageDrawRectangle(&img, 8, 24, 6, 8, rl.DARKGRAY) // legs
	rl.ImageDrawRectangle(&img, 18, 24, 6, 8, rl.DARKGRAY)

	// frame 1: legs apart (offset by FRAME_W)
	rl.ImageDrawRectangle(&img, FRAME_W + 4, 4, 24, 20, rl.SKYBLUE)
	rl.ImageDrawRectangle(&img, FRAME_W + 10, 10, 4, 4, rl.DARKBLUE)
	rl.ImageDrawRectangle(&img, FRAME_W + 20, 10, 4, 4, rl.DARKBLUE)
	rl.ImageDrawRectangle(&img, FRAME_W + 4, 24, 6, 8, rl.DARKGRAY)
	rl.ImageDrawRectangle(&img, FRAME_W + 22, 24, 6, 8, rl.DARKGRAY)

	return rl.LoadTextureFromImage(img)
}

main :: proc() {
	rl.InitWindow(SCREEN_W, SCREEN_H, "2.4 - textures, sprites, audio")
	defer rl.CloseWindow()
	rl.InitAudioDevice()
	defer rl.CloseAudioDevice()
	rl.SetTargetFPS(60)

	bot_tex := make_bot_texture()
	defer rl.UnloadTexture(bot_tex)

	chirp := make_beep(880, 0.15)
	defer rl.UnloadSound(chirp)
	blip := make_beep(220, 0.1)
	defer rl.UnloadSound(blip)

	pos := rl.Vector2{SCREEN_W / 2, SCREEN_H / 2}
	angle: f32 = 0
	moving := false

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()

		dir := rl.Vector2{0, 0}
		if rl.IsKeyDown(.D) do dir.x += 1
		if rl.IsKeyDown(.A) do dir.x -= 1
		if rl.IsKeyDown(.S) do dir.y += 1
		if rl.IsKeyDown(.W) do dir.y -= 1

		moving = dir != {0, 0}
		if moving {
			dir = rl.Vector2Normalize(dir)
			pos += dir * SPEED * dt
			angle = math.atan2(dir.y, dir.x) * rl.RAD2DEG + 90 // face heading
		}

		// wall bump: clamp + sound once per entry
		clamped := rl.Vector2 {
			clamp(pos.x, FRAME_W, SCREEN_W - FRAME_W),
			clamp(pos.y, FRAME_W, SCREEN_H - FRAME_W),
		}
		if clamped != pos {
			pos = clamped
			if !rl.IsSoundPlaying(blip) do rl.PlaySound(blip)
		}

		if rl.IsKeyPressed(.SPACE) do rl.PlaySound(chirp)

		// animate only while walking
		frame := 0
		if moving do frame = int(rl.GetTime() * 8) % 2

		rl.BeginDrawing()
		rl.ClearBackground(rl.RAYWHITE)

		rl.DrawTexturePro(
		bot_tex,
		{f32(frame) * FRAME_W, 0, FRAME_W, 32}, // source frame
		{pos.x, pos.y, FRAME_W, 32},            // destination
		{FRAME_W / 2, 16},                      // origin: center — rotate in place
		angle,
		rl.WHITE,
		)

		rl.DrawText("WASD walk | SPACE chirp | bump the walls", 10, 10, 20, rl.DARKGRAY)
		rl.EndDrawing()
	}
}
