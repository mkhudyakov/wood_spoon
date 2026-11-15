extends Node
## Procedural sound of the workshop: the slice of a knife, the rasp of the saw,
## sandpaper, the strop, a quiet fire, and soft background music: an original tune in the
## Hutsul mode (D E F G# A B C) for a sopilka flute over tsymbaly-like plucked strings.

const RATE := 22050.0

var slice := 0.0       # knife stroke in progress (set to its length in seconds)
var slice_len := 0.2
var tearing := 0.0
var thock := 0.0
var rasp := 0.0
var sanding := 0.0
var strop := 0.0
var fire := 0.5        # ambience level
var muted := false
var music := true
var music_vol := 0.085

# --- the tune, in sixteenth notes; numbers are semitones above D
const STEP := 0.172
const TUNE_A: Array = [7, 9, 10, 9,  7, 6, 3, 2,  0, 3, 7, 3,  2, -1, 2, -1,
		7, 9, 10, 12,  10, 9, 7, 6,  7, 3, 2, 3,  0, -1, 0, -1]
const TUNE_B: Array = [12, 12, 10, 9,  10, 9, 7, 6,  7, 9, 10, 7,  6, -1, 7, -1,
		15, 14, 12, 10,  9, 10, 12, 9,  7, 6, 3, 2,  0, -1, 0, -1]
var _notes := PackedFloat32Array()      # one entry per eighth: frequency, 0 = hold, -1 = rest
var _m_t := 0.0
var _m_i := -1
var _f_freq := 0.0
var _f_ph := 0.0
var _f_env := 0.0
var _f_on := 0.0
var _b_freq := 146.83
var _b_ph := 0.0
var _b_env := 0.0
var _c_ph := 0.0
var _c_env := 0.0
var _breath := 0.0

var _player: AudioStreamPlayer
var _pb: AudioStreamGeneratorPlayback
var _lp := 0.0
var _lp2 := 0.0
var _bp := 0.0
var _pop := 0.0
var _ph := 0.0
var _t := 0.0


func _ready() -> void:
	for part in [TUNE_A, TUNE_A, TUNE_B, TUNE_B]:
		for v in part:
			_notes.append(0.0 if int(v) < 0 else 587.33 * pow(2.0, int(v) / 12.0))
	for i in 48:
		_notes.append(-1.0)      # a breath: only the strings play
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.12
	_player = AudioStreamPlayer.new()
	_player.stream = gen
	_player.volume_db = -3.0
	_player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	add_child(_player)
	_player.play()
	_pb = _player.get_stream_playback() as AudioStreamGeneratorPlayback


func _process(_dt: float) -> void:
	if _pb == null:
		return
	var n := _pb.get_frames_available()
	if n <= 0:
		return
	n = mini(n, 4096)
	var buf := PackedVector2Array()
	buf.resize(n)
	var dt := 1.0 / RATE
	for i in n:
		var s := 0.0
		var nz := randf() - 0.5
		_t += dt
		# fire: a soft low rumble and the odd crackle
		_lp += (nz - _lp) * 0.02
		s += _lp * 0.5 * fire
		if randf() < 0.00012 * fire:
			_pop = 0.25 + randf() * 0.5
		if _pop > 0.001:
			s += (randf() - 0.5) * _pop * 0.5
			_pop *= 0.985
		# knife: a hiss that rises and falls over the length of the stroke
		if slice > 0.0:
			var ph := 1.0 - slice / slice_len
			var env := sin(ph * PI)
			_bp += (nz - _bp) * (0.25 + 0.35 * ph)
			s += (nz - _bp) * env * 0.55 + _bp * env * 0.35
			if tearing > 0.0 and randf() < 0.004:
				s += (randf() - 0.5) * 1.2 * tearing
			slice -= dt
		if thock > 0.001:
			_ph += 95.0 * dt
			s += (sin(_ph * TAU) * 0.9 + nz * 0.8) * thock
			thock *= 0.9988
		if rasp > 0.001:
			_lp2 += (nz - _lp2) * 0.5
			s += _lp2 * rasp * (0.6 + 0.4 * sin(_t * 380.0))
			rasp *= 0.9993
		if sanding > 0.001:
			s += (nz - _lp) * sanding * 0.35
			sanding *= 0.9996
		if strop > 0.001:
			s += (nz - _lp) * strop * 0.3 * maxf(sin(_t * 9.0), 0.0)
			strop *= 0.99992
		if music:
			s += _music(dt, nz) * music_vol
		if muted:
			s = 0.0
		buf[i] = Vector2(s, s)
	_pb.push_buffer(buf)


## One sample of the background tune. Each entry of _notes lasts an eighth (two STEPs).
func _music(dt: float, nz: float) -> float:
	_m_t += dt
	var i := int(_m_t / (STEP * 2.0))
	if i != _m_i:
		_m_i = i
		var k := i % _notes.size()
		var f := _notes[k]
		if f > 0.0:
			_f_freq = f
			_f_on = 1.0
			_f_env *= 0.45       # tonguing: a small dip at the start of each note
		elif f < 0.0:
			_f_on = 0.0
		# strings: bass on the beat (D, then A), a soft chord off the beat
		if k % 2 == 0:
			_b_freq = 146.83 if (k / 2) % 2 == 0 else 110.0
			_b_env = 1.0
			_b_ph = 0.0
		else:
			_c_env = 1.0
			_c_ph = 0.0
	var out := 0.0
	# sopilka
	_f_env += (_f_on - _f_env) * 0.0016
	if _f_env > 0.002:
		_f_ph = fmod(_f_ph + _f_freq * (1.0 + 0.005 * sin(_m_t * 34.0)) * dt, 1.0)
		_breath += (nz - _breath) * 0.3
		out += (sin(_f_ph * TAU) + 0.22 * sin(_f_ph * 2.0 * TAU) + 0.07 * sin(_f_ph * 3.0 * TAU) + _breath * 0.12) * _f_env * 0.5
	# tsymbaly
	if _b_env > 0.002:
		_b_ph += _b_freq * dt
		out += (sin(_b_ph * TAU) + 0.5 * sin(_b_ph * 2.0 * TAU) + 0.25 * sin(_b_ph * 3.0 * TAU)) * _b_env * 0.45
		_b_env *= 0.99986
	if _c_env > 0.002:
		_c_ph += dt
		out += (sin(_c_ph * 220.0 * TAU) + sin(_c_ph * 293.66 * TAU) + 0.7 * sin(_c_ph * 349.23 * TAU) + 0.3 * sin(_c_ph * 587.33 * TAU)) * _c_env * 0.14
		_c_env *= 0.9998
	return out
