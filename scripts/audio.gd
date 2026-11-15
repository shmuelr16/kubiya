extends Node
## All game audio, synthesised in code at startup. No audio files ship with the game.
##
## Sound effects are short noise bursts. Music is generative: two instrument
## samples (a soft pluck and a pad) are replayed at different pitches by a small
## sequencer, so the tune never loops and costs almost no CPU.

const RATE := 22050
const SFX_VOICES := 8
const MUSIC_VOICES := 10
const BEAT := 0.62
const MUSIC_DB := -17.0

## Semitones from C4 for the pluck: C major pentatonic over two octaves.
const SCALE: PackedInt32Array = [-12, -10, -8, -5, -3, 0, 2, 4, 7, 9, 12]
## Semitones from C3 for the pad: C, A minor, F, G.
const CHORDS := [[0, 4, 7], [-3, 0, 4], [-7, -3, 0], [-5, -1, 2]]

var streams := {}
var music_on := true
var notes_played := 0

var _sfx: Array[AudioStreamPlayer] = []
var _music: Array[AudioStreamPlayer] = []
var _sfx_next := 0
var _music_next := 0
var _thread: Thread
var _rng := RandomNumberGenerator.new()
var _beat_timer := 2.0
var _beat := 0
var _phrase := 0
var _rest := 2
var _melody := 5


func _ready() -> void:
	for i in SFX_VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx.append(p)
	for i in MUSIC_VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_music.append(p)
	_rng.randomize()
	if OS.has_feature("threads"):
		_thread = Thread.new()
		_thread.start(_synthesise_all)
	else:
		_synthesise_all()


func _exit_tree() -> void:
	if _thread != null:
		_thread.wait_to_finish()


func is_ready() -> bool:
	return not streams.is_empty()


func play(sound: String, pitch := 1.0, db := 0.0) -> void:
	if not streams.has(sound):
		return
	var p := _sfx[_sfx_next]
	_sfx_next = (_sfx_next + 1) % SFX_VOICES
	p.stream = streams[sound]
	p.pitch_scale = pitch
	p.volume_db = db
	p.play()


func toggle_music() -> void:
	music_on = not music_on
	if not music_on:
		for p in _music:
			p.stop()


func _process(delta: float) -> void:
	if not music_on or streams.is_empty():
		return
	_beat_timer -= delta
	if _beat_timer <= 0.0:
		_beat_timer += BEAT
		_on_beat()


func _on_beat() -> void:
	if _beat % 8 == 0:
		@warning_ignore("integer_division")
		var chord: Array = CHORDS[(_beat / 8) % CHORDS.size()]
		for semitone: int in chord:
			_note("pad", semitone, MUSIC_DB - 5.0)
	_beat += 1

	# Melody comes in phrases with silence between them.
	if _rest > 0:
		_rest -= 1
		if _rest == 0:
			_phrase = _rng.randi_range(6, 12)
		return
	_phrase -= 1
	if _phrase <= 0:
		_rest = _rng.randi_range(4, 10)
	if _rng.randf() < 0.6:
		_melody = clampi(_melody + _rng.randi_range(-2, 2), 0, SCALE.size() - 1)
		_note("pluck", SCALE[_melody], MUSIC_DB)


func _note(instrument: String, semitone: int, db: float) -> void:
	var p := _music[_music_next]
	_music_next = (_music_next + 1) % MUSIC_VOICES
	p.stream = streams[instrument]
	p.pitch_scale = pow(2.0, semitone / 12.0)
	p.volume_db = db
	p.play()
	notes_played += 1


# --- Synthesis. Runs on a worker thread; touches no nodes. ---

func _synthesise_all() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var out := {
		"dig": _wav(_burst(rng, 0.07, 0.35, 45.0, 0.0, 0.0)),
		"break": _wav(_burst(rng, 0.28, 0.25, 14.0, 90.0, 0.6)),
		"place": _wav(_burst(rng, 0.12, 0.15, 30.0, 140.0, 0.8)),
		"step": _wav(_burst(rng, 0.09, 0.12, 40.0, 70.0, 0.3)),
		"splash": _wav(_splash(rng)),
		"pop": _wav(_pop()),
		"pluck": _wav(_pluck()),
		"pad": _wav(_pad()),
	}
	_publish.call_deferred(out)


func _publish(out: Dictionary) -> void:
	streams = out


## Low-passed noise with an exponential decay, plus an optional sine thump.
func _burst(rng: RandomNumberGenerator, dur: float, lowpass: float, decay: float,
		thump_hz: float, thump_gain: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	for i in n:
		var t := float(i) / RATE
		y += lowpass * (rng.randf_range(-1.0, 1.0) - y)
		var s := y * exp(-t * decay) * minf(t / 0.002, 1.0)
		if thump_gain > 0.0:
			s += sin(TAU * thump_hz * t) * exp(-t * decay * 1.2) * thump_gain
		out[i] = s
	return out


## Noise whose filter closes over time: bright hit, dull tail.
func _splash(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(0.55 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	for i in n:
		var t := float(i) / RATE
		var lowpass := lerpf(0.55, 0.05, minf(t / 0.4, 1.0))
		y += lowpass * (rng.randf_range(-1.0, 1.0) - y)
		out[i] = y * exp(-t * 7.0) * minf(t / 0.004, 1.0)
	return out


## Short rising blip for picking up and crafting.
func _pop() -> PackedFloat32Array:
	var n := int(0.09 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		phase += TAU * lerpf(520.0, 980.0, t / 0.09) / RATE
		out[i] = sin(phase) * exp(-t * 28.0) * minf(t / 0.003, 1.0)
	return out


## Soft plucked tone at C4, like a thumb piano.
func _pluck() -> PackedFloat32Array:
	var f := 261.63
	var n := int(1.4 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var s := sin(TAU * f * t) + 0.35 * sin(TAU * f * 2.0 * t) * exp(-t * 6.0) \
				+ 0.12 * sin(TAU * f * 3.0 * t) * exp(-t * 10.0)
		out[i] = s * exp(-t * 4.2) * minf(t / 0.004, 1.0)
	return out


## Slow warm pad at C3: two slightly detuned sines and a quiet octave.
func _pad() -> PackedFloat32Array:
	var f := 130.81
	var dur := 4.6
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var s := sin(TAU * f * t) + 0.6 * sin(TAU * f * 1.005 * t) + 0.22 * sin(TAU * f * 2.0 * t)
		var env := smoothstep(0.0, 0.9, t) * (1.0 - smoothstep(dur - 2.2, dur, t))
		out[i] = s * env
	return out


## Normalises to a fixed peak and packs as 16-bit mono.
func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var peak := 0.0001
	for s in samples:
		peak = maxf(peak, absf(s))
	var gain := 0.8 / peak
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i] * gain, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav
