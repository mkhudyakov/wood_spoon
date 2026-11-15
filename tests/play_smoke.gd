extends SceneTree
## Drives the real mouse / key handlers in a window: one saw cut, one chop, knife strokes,
## hook, sanding, oil; reports frame time. godot --path . -s tests/play_smoke.gd -- <out dir>

var m
var out := "."


func _initialize() -> void:
	out = OS.get_cmdline_user_args()[0]
	m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await frames(4)
	m._key(KEY_2)
	await frames(12)
	print("mode ", m.mode, " stage ", m.stage)
	var t0 := Time.get_ticks_usec()
	await frames(120)
	print("idle frame: %.2f ms" % ((Time.get_ticks_usec() - t0) / 120000.0))
	# saw: on the top face at the end mark; the first move of the mouse (across) sets the line
	var sp := world_to_screen(Vector3(223.5, 32, 32))
	root.warp_mouse(sp)
	await frames(3)
	m._key(KEY_1)
	m._press()
	root.warp_mouse(world_to_screen(Vector3(224.5, 42, 32)))
	await frames(2)
	m._set_saw_dir()
	print("saw acting: ", m.acting, " hit ", m.stroke_a.get("p"), " line ", m.saw_dir)
	for i in 12:
		m.saw_acc += 60.0
		await frames(2)
	print("saw depth %.1f" % m.saw_depth)
	var w1: float = m.wood.waste
	m._release()
	await frames(3)
	print("offcut fell: %.1f cm3" % ((w1 - m.wood.waste) * 0.000125))
	await shot("p1_saw")
	# knife on the top face
	m.piece.basis = Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
	m._key(KEY_2)
	m._key(KEY_X)
	await frames(3)
	for i in 3:
		root.warp_mouse(world_to_screen(Vector3(110, 26 + i * 5, 32)))
		await frames(3)
		var w0: int = m.wood.solid
		m._press()
		await frames(2)
		root.warp_mouse(world_to_screen(Vector3(150, 28 + i * 5, 32)))
		await frames(4)
		if i == 1:
			await shot("p3_knife_drag")
		m._release()
		await frames(2)
		print("knife stroke %d took %.2f cm3, sharp %.2f" % [i, (w0 - m.wood.solid) * 0.000125, m.sharp])
	# hook in the bowl, across the grain
	m._key(KEY_3)
	root.warp_mouse(world_to_screen(Vector3(40, 20, 32)))
	await frames(3)
	var c0: int = m.wood.cavity
	m._press()
	await frames(2)
	root.warp_mouse(world_to_screen(Vector3(40, 44, 32)))
	await frames(4)
	m._release()
	await frames(2)
	print("hook took %.2f cm3 of the bowl" % ((c0 - m.wood.cavity) * 0.000125))
	# sand and oil
	m._key(KEY_4)
	root.warp_mouse(world_to_screen(Vector3(130, 32, 32)))
	await frames(2)
	m._press()
	await frames(20)
	m._release()
	m._key(KEY_5)
	m._press()
	await frames(20)
	m._release()
	print("oil at the rag: ", m.wood.attr_at(Vector3(130, 32, 31.5)))
	await frames(4)
	await shot("p4_after")
	t0 = Time.get_ticks_usec()
	await frames(120)
	print("frame with marks: %.2f ms" % ((Time.get_ticks_usec() - t0) / 120000.0))
	for k in [KEY_H, KEY_H, KEY_SPACE, KEY_SPACE, KEY_R, KEY_I, KEY_U, KEY_L, KEY_L, KEY_M, KEY_M, KEY_ENTER, KEY_ENTER]:
		m._key(k)
		await frames(2)
	print("stage after Enter x2: ", m.stage)
	quit()


func world_to_screen(p: Vector3) -> Vector2:
	return m.cam.unproject_position(m._to_world(p))


func frames(n: int) -> void:
	for i in n:
		await process_frame


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
