extends SceneTree
## Dev helper: renders game states to PNG. Run windowed after run_tests.gd:
## godot --path . -s tests/shot.gd -- <output dir>

var m
var out := "."


func _initialize() -> void:
	out = OS.get_cmdline_user_args()[0]
	m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await frames(4)
	await shot("1_menu")
	m.lang = "ru"
	m.start(1)
	await frames(10)
	await shot("2_billet")
	m.wood.saw_cut(Vector3(224, 32, 32), Vector3(0, 1, 0), Vector3(0, 0, -1), 40.0)
	m.wood.saw_cut(Vector3(82, 0, 32), Vector3(0, 0, 1), Vector3(0, 1, 0), 21.0)
	m.wood.saw_cut(Vector3(82, 64, 32), Vector3(0, 0, 1), Vector3(0, -1, 0), 21.0)
	m.wood.saw_cut(Vector3(223.3, 21, 28), Vector3(0, 0, 1), Vector3(-1, 0, 0), 141.5)
	m.wood.saw_cut(Vector3(223.3, 43, 28), Vector3(0, 0, 1), Vector3(-1, 0, 0), 141.5)
	m.wood.drop_offcuts()
	m.confirm_next = true
	m._next_stage()
	m._update_text()
	await frames(10)
	await shot("3_sawn")
	m.show_hint = true
	m.WoodView.set_flags(m.view, true, true)
	m.piece.basis = Basis(Vector3.RIGHT, -0.9) * m.piece.basis
	await frames(6)
	await shot("4_hint")
	m.show_hint = false
	m.WoodView.set_flags(m.view, true, false)
	m.piece.basis = Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
	for i in 8:
		m.wood.knife_cut(Vector3(100 + i * 3, 30, 32), Vector3(150 + i * 3, 34, 32), Vector3(0, 0, 1), 1.6, 28.0, 0.0, 1.0)
	m.wood.knife_cut(Vector3(190, 32, 32), Vector3(150, 32, 32), Vector3(0, 0, 1), 2.6, 28.0, 0.0, 1.0)
	for i in 10:
		m.wood.knife_cut(Vector3(20 + i * 4, 18, 32), Vector3(24 + i * 4, 46, 32), Vector3(0, 0, 1), 1.5, 24.0, 15.0, 1.0)
	m._update_text()
	await frames(10)
	await shot("5_knife")
	# a finished spoon (carved stroke by stroke by tests/bot.gd), raw and then oiled
	var f := FileAccess.open("user://spoons/bot.dat", FileAccess.READ)
	if f != null:
		var d = f.get_var()
		m.wood.vox = (d.vox as PackedByteArray).decompress(int(d.size), FileAccess.COMPRESSION_ZSTD)
		m.wood.ccount = d.ccount
		m.wood.solid = d.solid
		m.wood.waste = d.waste
		m.wood.cavity = d.cavity
		m.wood.over = d.over
		m.wood.dirty = true
		m._enter_stage(m.S_FINISH)
		m.piece.basis = Basis(Vector3.RIGHT, 0.35) * Basis(Vector3.UP, 0.45) * m.piece.basis
		m.cam_dist = 250.0
		await frames(10)
		await shot("6_spoon_raw")
		m._enter_stage(m.S_OIL)
		m.wood.oil(Vector3(60, 32, 20), 70.0)
		m._oil_progress()
		m._update_text()
		await frames(10)
		await shot("7_spoon_half_oiled")
		m.wood.oil(Vector3(115, 32, 16), 200.0)
		m._oil_progress()
		var n0: int = m.gallery.size()
		m._next_stage()
		await frames(30)
		await shot("8_done")
		if m.gallery.size() > n0:
			DirAccess.remove_absolute(m.gallery[m.gallery.size() - 1])
	quit()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("saved ", name)
