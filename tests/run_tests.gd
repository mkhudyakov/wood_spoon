extends SceneTree
## Headless checks of the wood model and the game flow.
## Run: godot --headless --path . -s tests/run_tests.gd

const Wood = preload("res://scripts/wood.gd")
const Exporter = preload("res://scripts/exporter.gd")
const CM3 := 0.000125
var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var w = Wood.new()
	w.new_billet()
	print("billet built in %d ms" % (Time.get_ticks_msec() - t0))
	print("  waste %.0f cm3, bowl hollow %.1f cm3, solid %.0f cm3" % [w.waste * CM3, w.cavity * CM3, w.solid * CM3])
	check(w.waste * CM3 > 250.0 and w.waste * CM3 < 360.0, "a half log has about 300 cm3 of waste around the spoon")
	check(w.cavity * CM3 > 14.0 and w.cavity * CM3 < 23.0, "the bowl hollow is about 18 cm3")
	var fresh: Dictionary = w.snapshot()

	print("--- saw")
	var X := Vector3(1, 0, 0)
	var Y := Vector3(0, 1, 0)
	var Z := Vector3(0, 0, 1)
	w.saw_cut(Vector3(224, 32, 32), Y, -Z, 40.0)
	check(w.drop_offcuts() > 3000.0, "sawing right through drops the offcut")
	check(w.dens(Vector3(226, 32, 28)) < 0.5 and w.dens(Vector3(200, 32, 28)) > 0.5, "the short end is gone, the spoon stays")
	w.saw_cut(Vector3(82, 0, 32), Z, Y, 21.0)
	w.saw_cut(Vector3(82, 64, 32), Z, -Y, 21.0)
	check(w.dens(Vector3(82, 12, 28)) < 0.5 and w.dens(Vector3(82, 32, 28)) > 0.5, "stop cuts at the neck leave the handle whole")
	check(w.drop_offcuts() == 0.0, "a stop cut drops nothing")
	w.saw_cut(Vector3(223.3, 21, 28), Z, -X, 100.0)
	check(w.drop_offcuts() == 0.0, "a rip cut that has not reached the stop cut drops nothing")
	w.saw_cut(Vector3(223.3, 21, 28), Z, -X, 141.5, 100.0)
	var fell: float = w.drop_offcuts()
	check(fell > 50000.0, "the rip cut meets the stop cut: the cheek falls (%.0f cm3)" % (fell * 0.001))
	check(w.dens(Vector3(150, 10, 28)) < 0.5 and w.dens(Vector3(40, 10, 28)) > 0.5, "the cheek is gone, the bowl side is still there")
	check(w.dens(Vector3(150, 20.2, 28)) < 0.5, "no sliver left beside the kerf")
	check(w.over * CM3 < 0.1, "the saw did not touch the spoon (%.2f)" % (w.over * CM3))

	print("--- knife and the grain")
	w.restore(fresh)
	var up := Vector3(0, 0, 1)
	var r: Dictionary = w.knife_cut(Vector3(100, 32, 32), Vector3(140, 32, 32), up, 2.0, 28.0, 0.0, 1.0)
	check(r.vol > 500.0, "a deep 40 mm stroke lifts a real shaving (%.0f mm3)" % r.vol)
	check(r.torn > 0.05, "its rising half runs against the grain and tears (%.2f)" % r.torn)
	w.restore(fresh)
	r = w.knife_cut(Vector3(100, 20, 32), Vector3(140, 20, 32), up, 0.3, 28.0, 0.0, 1.0)
	check(r.torn == 0.0 and r.vol > 20.0, "a thin paring cut is clean (%.0f mm3)" % r.vol)
	r = w.knife_cut(Vector3(170, 14, 32), Vector3(170, 50, 32), up, 2.0, 28.0, 0.0, 1.0)
	check(r.torn == 0.0, "across the grain nothing tears")
	check(Wood.uphill(Vector3(100, 32, 20), Vector3(120, 32, 26), Vector3(-0.29, 0, 0.96)) > 0.055, "climbing a slope along the grain is 'against the grain'")
	check(Wood.uphill(Vector3(120, 32, 26), Vector3(100, 32, 20), Vector3(-0.29, 0, 0.96)) < 0.0, "coming down the same slope is 'with the grain'")
	t0 = Time.get_ticks_msec()
	for i in 10:
		w.knife_cut(Vector3(60 + i, 32, 32), Vector3(110 + i, 30, 32), up, 1.6, 28.0, 0.0, 1.0)
	print("  10 knife strokes in %d ms" % (Time.get_ticks_msec() - t0))
	r = w.knife_cut(Vector3(30, 20, 32), Vector3(30, 44, 32), up, 1.5, 24.0, 15.0, 1.0)
	check(r.vol > 50.0 and w.cavity < fresh.cavity, "the hook knife scoops the bowl (%.0f mm3)" % r.vol)
	var h: Dictionary = w.raycast(Vector3(150, 32, 80), Vector3(0, 0, -1))
	check(not h.is_empty() and absf(float(Vector3(h.p).z) - 32.0) < 0.6 and Vector3(h.n).z > 0.9, "ray picking finds the split face and its normal")
	check(absf(w.thickness(h.p, h.n) - 32.0) < 1.0, "thickness under the fingers: the full 32 mm")

	print("--- a perfect spoon")
	w.restore(fresh)
	for c in w.nz:
		for b in w.ny:
			var base: int = w.cbase[c] + b * w.rowstride
			for a in w.nx:
				var m: int = w._mask_at(a, b, c)
				var i: int = base + a * 3
				if w.vox[i] >= 128 and m != 1:
					w._gone(a, b, c)
					w.vox[i] = 0
				w.vox[i + 1] = Wood.F_KNIFE * 40
	var st: Dictionary = w.stats(0.63)
	print("  ", st)
	check(w.waste == 0 and w.cavity == 0 and w.over == 0, "nothing left to cut, nothing cut too much")
	check(st.wall > 2.5 and st.wall < 5.0, "bowl wall about 3.5 mm (%.1f)" % st.wall)
	check(st.symmetry > 0.97, "symmetric (%.3f)" % st.symmetry)
	check(st.weight > 12.0 and st.weight < 40.0, "weighs like a spoon (%.0f g)" % st.weight)
	check(st.neck > 60.0, "a sound neck (%.0f mm2)" % st.neck)
	check(st.knife > 0.9, "all knife finish")
	w.oil(Vector3(40, 32, 25), 30.0)
	check(w.attr_at(Vector3(40, 32, 31.0)).y > 60, "oil soaks in where the rag went")
	DirAccess.make_dir_recursive_absolute("user://spoons")
	t0 = Time.get_ticks_msec()
	check(Exporter.write_stl(w, "user://spoons/test.stl"), "STL written in %d ms" % (Time.get_ticks_msec() - t0))
	var fsz := FileAccess.open("user://spoons/test.stl", FileAccess.READ).get_length()
	check(fsz > 100000, "the STL has real geometry (%d kB)" % (fsz / 1024))
	# keep the perfect spoon for the screenshot script
	var f := FileAccess.open("user://spoons/perfect.dat", FileAccess.WRITE)
	f.store_var({"vox": w.vox.compress(FileAccess.COMPRESSION_ZSTD), "size": w.vox.size(), "ccount": w.ccount})
	f.close()
	DirAccess.remove_absolute("user://spoons/test.stl")

	print("--- the game itself")
	var scn = load("res://main.tscn").instantiate()
	root.add_child(scn)
	await process_frame
	scn.set_process(false)
	scn.start(1)
	for i in 6:
		await process_frame
	check(scn.mode == scn.M_CARVE and scn.stage == scn.S_SAW, "a birch billet is on the bench, saw stage")
	check(not scn._goal_met(), "a whole log: the saw task is not done")
	scn.confirm_next = true
	scn._next_stage()
	check(scn.stage == scn.S_KNIFE and scn.tool == scn.T_KNIFE, "on to the knife")
	scn._set_tool(scn.T_KNIFE)
	scn.stroke_a = {"p": Vector3(120, 32, 32), "n": Vector3(0, 0, 1)}
	scn.stroke_last = {"p": Vector3(160, 30, 32), "n": Vector3(0, 0, 1)}
	scn.hover = scn.stroke_last
	scn._do_stroke()
	check(scn.strokes == 1 and scn.sharp < 1.0, "a knife stroke counts and dulls the edge a little")
	scn._strop()
	check(scn.sharp == 1.0, "stropping brings the edge back")
	scn.confirm_next = true
	scn._next_stage()
	scn.confirm_next = true
	scn._next_stage()
	check(scn.stage == scn.S_FINISH, "stages can be skipped with a second Enter")
	scn.confirm_next = true
	scn._next_stage()
	check(scn.stage == scn.S_OIL and scn.oil_points.size() > 100, "oil stage samples the surface")
	scn.wood.oil(Vector3(115, 32, 16), 200.0)
	scn._oil_progress()
	check(scn.oil_share > 0.95, "oil everywhere: %d %%" % int(scn.oil_share * 100.0))
	var n0: int = scn.gallery.size()
	scn._next_stage()
	check(scn.mode == scn.M_DONE and scn.gallery.size() == n0 + 1, "the spoon is finished and saved")
	scn._show_gallery(scn.gallery.size() - 1)
	check(scn.mode == scn.M_GALLERY, "and can be looked at again")
	DirAccess.remove_absolute(scn.gallery[scn.gallery.size() - 1])
	scn.lang = "en"
	scn._show_menu()
	print("==== %s (%d failures)" % ["ALL PASSED" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
