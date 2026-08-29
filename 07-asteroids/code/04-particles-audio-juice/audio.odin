package main

import "core:math"
import rl "vendor:raylib"

SAMPLE_RATE :: 22050

// --- audio: synthesized beeps (from lesson 2.4) ---
append_u16le :: proc(buf: ^[dynamic]u8, v: u16) {append(buf, u8(v), u8(v >> 8))}
append_u32le :: proc(buf: ^[dynamic]u8, v: u32) {append(buf, u8(v), u8(v >> 8), u8(v >> 16), u8(v >> 24))}

make_beep :: proc(frequency, duration: f32) -> rl.Sound {
	sample_count := int(f32(SAMPLE_RATE) * duration)
	data_size := u32(sample_count * 2)
	wav: [dynamic]u8
	defer delete(wav)
	append(&wav, 'R', 'I', 'F', 'F')
	append_u32le(&wav, 36 + data_size)
	append(&wav, 'W', 'A', 'V', 'E')
	append(&wav, 'f', 'm', 't', ' ')
	append_u32le(&wav, 16)
	append_u16le(&wav, 1)
	append_u16le(&wav, 1)
	append_u32le(&wav, SAMPLE_RATE)
	append_u32le(&wav, SAMPLE_RATE * 2)
	append_u16le(&wav, 2)
	append_u16le(&wav, 16)
	append(&wav, 'd', 'a', 't', 'a')
	append_u32le(&wav, data_size)
	for i in 0 ..< sample_count {
		t := f32(i) / f32(SAMPLE_RATE)
		envelope := 1 - t/duration
		sample := i16(math.sin(2 * math.PI * frequency * t) * 12000 * envelope)
		append_u16le(&wav, transmute(u16)sample)
	}
	wave := rl.LoadWaveFromMemory(".wav", raw_data(wav), i32(len(wav)))
	sound := rl.LoadSoundFromWave(wave)
	rl.UnloadWave(wave)
	return sound
}

// Every sound in the game, synthesized once at startup.
Sounds :: struct {
	shoot:     rl.Sound,
	hit:       rl.Sound,
	explosion: rl.Sound,
	wave_low:  rl.Sound, // played together with wave_high → a two-tone jingle
	wave_high: rl.Sound,
	game_over: rl.Sound,
}

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

unload_sounds :: proc(sfx: Sounds) {
	rl.UnloadSound(sfx.shoot)
	rl.UnloadSound(sfx.hit)
	rl.UnloadSound(sfx.explosion)
	rl.UnloadSound(sfx.wave_low)
	rl.UnloadSound(sfx.wave_high)
	rl.UnloadSound(sfx.game_over)
}
