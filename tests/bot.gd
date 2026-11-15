extends SceneTree
## A carving robot that works the way a player would: it looks at the surface, finds wood
## that is still waste, and takes a knife or hook stroke there, downhill to the grain.
## Shows how many strokes a spoon takes and whether the stage goals can be reached.
## godot --headless --path . -s tests/bot.gd

const Wood = preload("res://scripts/wood.gd")
const CM3 := 0.000125
var w
var rng := RandomNumberGenerator.new()


func depth_to_spoon(p: Vector3, n: Vector3, want: int) -> float:
	# how much wood of class `want` (0 waste / 2 hollow) lies under the surface point
	var t := 0.3
	while t < 30.0:
		var q := p - n * t
		if Wood.target(q.x, q.y, q.z) != want:
			return t
		t += 0.25
	return 30.0


func surface_point() -> Dictionary:
	for i in 30:
		var d := Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		var o := Vector3(rng.randf_range(3.0, 222.0), 32.0, 22.0) - d * 90.0
		var h: Dictionary = w.raycast(o, d)
		if not h.is_empty():
			return h
	return {}


func _initialize() -> void:
	rng.seed = 11
	w = Wood.new()
	w.new_billet()
	var X := Vector3(1, 0, 0)
	var Y := Vector3(0, 1, 0)
	var Z := Vector3(0, 0, 1)
	w.saw_cut(Vector3(224, 32, 32), Y, -Z, 40.0)
	w.saw_cut(Vector3(82, 0, 32), Z, Y, 21.0)
	w.saw_cut(Vector3(82, 64, 32), Z, -Y, 21.0)
	w.saw_cut(Vector3(223.3, 21, 28), Z, -X, 141.5)
	w.saw_cut(Vector3(223.3, 43, 28), Z, -X, 141.5)
	w.saw_cut(Vector3(82, 32, 0), Y, Z, 21.0)
	w.saw_cut(Vector3(223.3, 32, 21), Y, -X, 141.5)
	w.drop_offcuts()
	print("after the saw: waste %.1f cm3, hollow %.1f, lost %.2f" % [w.waste * CM3, w.cavity * CM3, w.over * CM3])
	var strokes := 0
	var torn_strokes := 0
	var tries := 0
	var t0 := Time.get_ticks_msec()
	# --- knife: the outside
	while w.waste * CM3 > 10.0 and tries < 6000:
		tries += 1
		var h := surface_point()
		if h.is_empty():
			continue
		var p: Vector3 = h.p
		var n: Vector3 = h.n
		if Wood.target(p.x - n.x * 0.4, p.y - n.y * 0.4, p.z - n.z * 0.4) != 0:
			continue
		# stroke direction: along the grain where the surface allows, else across
		var t := Vector3(1, 0, 0) - n * n.x
		if t.length() < 0.35:
			t = Vector3(0, 1, 0) - n * n.y
		t = t.normalized()
		var bl := n.cross(t).normalized()
		var half := rng.randf_range(6.0, 14.0)
		# look under the whole blade, the way a carver reads the pencil line
		var dep := 30.0
		for i in 5:
			for j in 5:
				var q := p + t * (half * (i - 2) * 0.5) + bl * (14.0 * (j - 2) * 0.5)
				var hh: Dictionary = w.raycast(q + n * 12.0, -n)
				if hh.is_empty() or float(hh.t) > 20.0:
					continue
				dep = minf(dep, depth_to_spoon(hh.p, n, 0) - 0.3)
		if dep < 0.5:
			continue
		var bite := clampf(dep - 0.3, 0.2, 2.6)
		var a := p - t * half
		var b := p + t * half
		if w.grain(a, b, n, bite, 0.0, 1.0) > w.grain(b, a, n, bite, 0.0, 1.0):
			var sw := a
			a = b
			b = sw
		var r: Dictionary = w.knife_cut(a, b, n, bite, 28.0, 0.0, 1.0)
		if r.vol > 1.0:
			strokes += 1
			if r.torn > 0.12:
				torn_strokes += 1
	print("knife: %d strokes (%d tore), %d s; waste %.1f cm3, hollow %.1f, lost %.2f cm3" % [strokes, torn_strokes, (Time.get_ticks_msec() - t0) / 1000, w.waste * CM3, w.cavity * CM3, w.over * CM3])
	# --- hook knife: the bowl, across the grain
	var hs := 0
	tries = 0
	t0 = Time.get_ticks_msec()
	while w.cavity * CM3 > 1.5 and tries < 4000:
		tries += 1
		var x := rng.randf_range(8.0, 72.0)
		var y := rng.randf_range(14.0, 50.0)
		var h2: Dictionary = w.raycast(Vector3(x, y, 60.0), Vector3(0, 0, -1))
		if h2.is_empty():
			continue
		var p2: Vector3 = h2.p
		var n2: Vector3 = h2.n
		if n2.z < 0.3:
			continue
		if Wood.target(p2.x - n2.x * 0.4, p2.y - n2.y * 0.4, p2.z - n2.z * 0.4) != 2:
			continue
		var t2 := (Vector3(0, 1, 0) - n2 * n2.y).normalized()
		var bl2 := n2.cross(t2).normalized()
		var half2 := rng.randf_range(4.0, 9.0)
		var dep2 := 30.0
		for i in 5:
			for j in 5:
				var wv := 8.0 * (j - 2) * 0.5
				var q := p2 + t2 * (half2 * (i - 2) * 0.5) + bl2 * wv
				var lift := 15.0 - sqrt(225.0 - wv * wv)
				var hgt := 8.0
				while hgt > -3.0:
					var qq := q + n2 * hgt
					if Wood.target(qq.x, qq.y, qq.z) == 1 and w.dens(qq) > 0.5:
						break
					hgt -= 0.25
				dep2 = minf(dep2, lift - hgt - 0.5)
		if dep2 < 0.5:
			continue
		var bite2 := clampf(dep2 - 0.3, 0.2, 2.2)
		var r2: Dictionary = w.knife_cut(p2 - t2 * half2, p2 + t2 * half2, n2, bite2, 16.0, 15.0, 1.0)
		if r2.vol > 1.0:
			hs += 1
	print("hook: %d strokes, %d s; waste %.1f cm3, hollow %.1f, lost %.2f cm3" % [hs, (Time.get_ticks_msec() - t0) / 1000, w.waste * CM3, w.cavity * CM3, w.over * CM3])
	var st: Dictionary = w.stats(0.63)
	print(st)
	DirAccess.make_dir_recursive_absolute("user://spoons")
	var f := FileAccess.open("user://spoons/bot.dat", FileAccess.WRITE)
	f.store_var({"vox": w.vox.compress(FileAccess.COMPRESSION_ZSTD), "size": w.vox.size(), "ccount": w.ccount, "solid": w.solid, "waste": w.waste, "cavity": w.cavity, "over": w.over})
	f.close()
	quit()
