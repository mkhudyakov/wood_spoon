extends SceneTree
## Renders 40 s of the background tune to a WAV file, to check it by ear or by numbers.
## godot --headless --path . -s tests/music_wav.gd -- /path/out.wav

func _initialize() -> void:
	var sy = load("res://scripts/synth.gd").new()
	for part in [sy.TUNE_A, sy.TUNE_A, sy.TUNE_B, sy.TUNE_B]:
		for v in part:
			sy._notes.append(0.0 if int(v) < 0 else 587.33 * pow(2.0, int(v) / 12.0))
	for i in 48:
		sy._notes.append(-1.0)
	var n := int(sy.RATE * 40.0)
	var data := PackedByteArray()
	data.resize(n * 2)
	var peak := 0.0
	var sq := 0.0
	for i in n:
		var s: float = sy._music(1.0 / sy.RATE, randf() - 0.5) * sy.music_vol
		peak = maxf(peak, absf(s))
		sq += s * s
		data.encode_s16(i * 2, int(clampf(s * 4.0, -1.0, 1.0) * 32767.0))
	print("peak %.3f  rms %.3f  (knife stroke peaks near 0.5)" % [peak, sqrt(sq / n)])
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = int(sy.RATE)
	w.data = data
	w.save_to_wav(OS.get_cmdline_user_args()[0])
	sy.free()
	quit()
