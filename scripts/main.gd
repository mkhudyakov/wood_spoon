extends Node3D
## Carve a wooden spoon from half a split log: saw, knife, hook knife, finish, oil.
## Flow, input, the bench scene and all on-screen text (Russian / English).

const Wood = preload("res://scripts/wood.gd")
const WoodView = preload("res://scripts/wood_view.gd")
const Hud = preload("res://scripts/hud.gd")
const Synth = preload("res://scripts/synth.gd")
const Exporter = preload("res://scripts/exporter.gd")

enum { M_MENU, M_LOADING, M_CARVE, M_DONE, M_GALLERY }
enum { T_SAW, T_KNIFE, T_HOOK, T_SAND, T_OIL }
enum { S_SAW, S_KNIFE, S_HOOK, S_FINISH, S_OIL }

const SPECIES: Array = [
	{"id": "linden", "ru": "Липа", "en": "Linden", "ru_note": "мягкая и послушная: лучший выбор для первой ложки", "en_note": "soft and forgiving: the best choice for a first spoon",
		"early": Color(0.95, 0.89, 0.75), "late": Color(0.87, 0.77, 0.58), "bark": Color(0.30, 0.27, 0.22), "ring": 2.8, "hard": 0.7, "dens": 0.50},
	{"id": "birch", "ru": "Берёза", "en": "Birch", "ru_note": "классика: плотная, режется чисто, держит тонкую стенку", "en_note": "the classic: dense, cuts cleanly, holds a thin wall",
		"early": Color(0.93, 0.84, 0.68), "late": Color(0.80, 0.65, 0.44), "bark": Color(0.80, 0.78, 0.72), "ring": 2.3, "hard": 1.0, "dens": 0.63},
	{"id": "cherry", "ru": "Вишня", "en": "Cherry", "ru_note": "твёрдая и капризная к направлению волокон, зато какой цвет под маслом", "en_note": "hard and fussy about grain direction, but what a colour under oil",
		"early": Color(0.82, 0.58, 0.40), "late": Color(0.63, 0.37, 0.23), "bark": Color(0.24, 0.14, 0.11), "ring": 1.9, "hard": 1.25, "dens": 0.60},
]

const GOAL_SAW := 125.0      # cm^3 of waste allowed to remain after the saw
const GOAL_KNIFE := 12.0
const GOAL_HOOK := 2.5
const GOAL_TORN := 0.05
const GOAL_OIL := 0.90
const KNIFE_BITES: Array = [0.3, 0.8, 1.6, 2.6]
const HOOK_BITES: Array = [0.5, 1.1, 2.0]
const VOX_CM3 := 0.000125

var lang := "ru"
var mode := M_MENU
var species: Dictionary = SPECIES[0]
var wood
var view: MeshInstance3D
var stage := S_SAW
var tool := T_SAW
var bite_i := 1
var sharp := 1.0
var show_lines := true
var show_hint := false
var checkpoint: Dictionary = {}
var strokes := 0
var hole := false
var torn_share := 0.0
var oil_share := 0.0
var oil_points: Array = []
var spoon_no := 1
var final_stats: Dictionary = {}
var gallery: Array = []
var gallery_i := 0
var confirm_next := false
var stroke_bad := 0.0      # share of the stroke under the cursor that would tear

# scene
var hud
var synth
var cam: Camera3D
var piece: Node3D
var preview: MeshInstance3D
var preview_mesh: ImmediateMesh
var chips: CPUParticles3D
var pile: MultiMeshInstance3D
var pile_n := 0
var cam_dist := 300.0
var spin := 0.0

# input state
var rotating := false
var acting := false
var hover: Dictionary = {}
var stroke_a: Dictionary = {}
var stroke_last: Dictionary = {}
var saw_acc := 0.0
var saw_depth := 0.0
var saw_dir := Vector3.ZERO      # the line of the kerf on the surface, set by the first move of the mouse
var saw_press := Vector2.ZERO
var rub_t := 0.0
var sync_t := 0.0
var busy_t := 0.0
var toast_t := 0.0
var toast_text := ""
var toast_times := {}
var export_thread: Thread = null
var web_exporting := false
var export_msg := ""


func T(ru: String, en: String) -> String:
	return ru if lang == "ru" else en


func _ready() -> void:
	randomize()
	DisplayServer.window_set_title.call_deferred("Ложка / The Spoon")
	_build_scene()
	hud = Hud.new()
	add_child(hud)
	synth = Synth.new()
	add_child(synth)
	_load_gallery()
	_show_menu()


# ================================================================ scene

func _mat(c: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, r: float, h: float, pos: Vector3, mat: Material, axis := 1) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	if axis == 0:
		mi.rotation.z = PI * 0.5
	elif axis == 2:
		mi.rotation.x = PI * 0.5
	parent.add_child(mi)
	return mi


func _build_scene() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.07, 0.055, 0.045)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.45, 0.36)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = e
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_color = Color(1.0, 0.92, 0.8)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 1500.0
	add_child(sun)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-260, 120, 220)
	fill.light_color = Color(1.0, 0.75, 0.5)
	fill.light_energy = 1.4
	fill.omni_range = 900.0
	fill.omni_attenuation = 1.1
	add_child(fill)
	cam = Camera3D.new()
	cam.near = 5.0
	cam.far = 5000.0
	cam.fov = 34.0
	add_child(cam)

	# the bench: thick planks, a chopping block, a mug of tea
	var bench := _mat(Color(0.33, 0.23, 0.15), 0.85)
	for i in 5:
		_box(self, Vector3(1400, 40, 178), Vector3(0, -130, -360 + i * 180.0), _mat(Color(0.33, 0.23, 0.15) * (0.9 + 0.05 * (i % 3)), 0.85))
	_box(self, Vector3(1400, 600, 30), Vector3(0, 120, -560), bench)
	# a soft shadow under the piece
	var sh := MeshInstance3D.new()
	var qm := PlaneMesh.new()
	qm.size = Vector2(330, 130)
	sh.mesh = qm
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.set_color(0, Color(0, 0, 0, 0.4))
	gr.set_color(1, Color(0, 0, 0, 0.0))
	gt.gradient = gr
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	var shm := StandardMaterial3D.new()
	shm.albedo_texture = gt
	shm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sh.material_override = shm
	sh.position = Vector3(0, -109, 0)
	add_child(sh)

	piece = Node3D.new()
	add_child(piece)
	piece.basis = Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))

	preview_mesh = ImmediateMesh.new()
	preview = MeshInstance3D.new()
	preview.mesh = preview_mesh
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.vertex_color_use_as_albedo = true
	pm.no_depth_test = true
	preview.material_override = pm
	piece.add_child(preview)

	chips = CPUParticles3D.new()
	var cmesh := BoxMesh.new()
	cmesh.size = Vector3(3.2, 0.25, 1.4)
	chips.mesh = cmesh
	chips.material_override = _mat(Color(0.93, 0.84, 0.68), 0.8)
	chips.one_shot = true
	chips.explosiveness = 0.95
	chips.amount = 10
	chips.lifetime = 1.1
	chips.local_coords = false
	chips.direction = Vector3(0, 1, 0)
	chips.spread = 60.0
	chips.initial_velocity_min = 60.0
	chips.initial_velocity_max = 170.0
	chips.gravity = Vector3(0, -900, 0)
	chips.angular_velocity_min = -500.0
	chips.angular_velocity_max = 500.0
	chips.scale_amount_min = 0.5
	chips.scale_amount_max = 1.6
	chips.emitting = false
	add_child(chips)

	pile = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var pmesh := BoxMesh.new()
	pmesh.size = Vector3(6, 0.35, 2.4)
	mm.mesh = pmesh
	mm.instance_count = 700
	mm.visible_instance_count = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 700:
		var ang := rng.randf() * TAU
		var rad := sqrt(rng.randf()) * 230.0
		var bs := Basis.from_euler(Vector3(rng.randf_range(-0.5, 0.5), rng.randf() * TAU, rng.randf_range(-0.9, 0.9))).scaled(Vector3.ONE * rng.randf_range(0.5, 1.5))
		mm.set_instance_transform(i, Transform3D(bs, Vector3(cos(ang) * rad * 1.3, -108.0 + rng.randf() * 5.0, sin(ang) * rad * 0.6 + 20.0)))
	pile.multimesh = mm
	pile.material_override = chips.material_override
	add_child(pile)


func _set_wood_colours() -> void:
	var c: Color = species.early
	(chips.material_override as StandardMaterial3D).albedo_color = c


# ================================================================ flow

func _show_menu() -> void:
	mode = M_MENU
	hud.set_text(hud.task_lbl, "")
	hud.set_text(hud.tools_lbl, "")
	hud.set_text(hud.info_lbl, "")
	hud.set_text(hud.toast_lbl, "")
	hud.keys_lbl.text = ""
	var t := "[center][font_size=34][color=#e9c98a]%s[/color][/font_size]\n" % T("ЛОЖКА", "THE SPOON")
	t += "[font_size=16]%s[/font_size][/center]\n\n" % T("Половина расколотого полена, пила, нож и ложкорез.\nК вечеру из неё выйдет ложка. Спешить некуда.", "Half a split log, a saw, a knife and a hook knife.\nBy evening it will be a spoon. There is no hurry.")
	t += "[color=#e9c98a]%s[/color]\n" % T("Выберите дерево:", "Choose your wood:")
	for i in SPECIES.size():
		var sp: Dictionary = SPECIES[i]
		t += "  [color=#8fc0e8][%d][/color]  %s — %s\n" % [i + 1, T(sp.ru, sp.en), T(sp.ru_note, sp.en_note)]
	t += "\n"
	if gallery.size() > 0:
		t += "  [color=#8fc0e8][G][/color]  %s (%d)\n" % [T("Мои ложки", "My spoons"), gallery.size()]
	t += "  [color=#8fc0e8][L][/color]  Language: English / Русский\n"
	hud.show_overlay(t)
	if view != null:
		view.visible = false


func start(sp_i: int) -> void:
	species = SPECIES[sp_i]
	mode = M_LOADING
	hud.show_overlay("[center][font_size=20]%s[/font_size][/center]" % T("Раскалываем полено пополам...", "Splitting the log in half..."))
	await get_tree().process_frame
	await get_tree().process_frame
	if wood == null:
		wood = Wood.new()
	wood.new_billet()
	if view == null:
		view = WoodView.make(wood)
		piece.add_child(view)
	else:
		WoodView.sync(view, wood)
	view.visible = true
	WoodView.set_species(view, species)
	_set_wood_colours()
	piece.basis = Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
	sharp = 1.0
	strokes = 0
	hole = false
	show_hint = false
	show_lines = true
	pile_n = 0
	pile.multimesh.visible_instance_count = 0
	spoon_no = gallery.size() + 1
	hud.hide_overlay()
	mode = M_CARVE
	_enter_stage(S_SAW)


func _enter_stage(s: int) -> void:
	stage = s
	confirm_next = false
	checkpoint = wood.snapshot()
	if s == S_SAW:
		_set_tool(T_SAW)
	elif s == S_KNIFE:
		_set_tool(T_KNIFE)
	elif s == S_HOOK:
		_set_tool(T_HOOK)
	elif s == S_FINISH:
		_set_tool(T_KNIFE)
		bite_i = 0
		_inspect()
	elif s == S_OIL:
		_set_tool(T_OIL)
		show_lines = false
		oil_points = wood.surface_points(260)
		_oil_progress()
	WoodView.set_flags(view, show_lines, show_hint)
	_update_text()


func _set_tool(t: int) -> void:
	tool = t
	acting = false
	stroke_a = {}
	bite_i = clampi(bite_i, 0, (HOOK_BITES.size() if t == T_HOOK else KNIFE_BITES.size()) - 1)
	_update_text()


func _goal_met() -> bool:
	if stage == S_SAW:
		return wood.waste * VOX_CM3 <= GOAL_SAW
	if stage == S_KNIFE:
		return wood.waste * VOX_CM3 <= GOAL_KNIFE
	if stage == S_HOOK:
		return wood.cavity * VOX_CM3 <= GOAL_HOOK
	if stage == S_FINISH:
		return torn_share <= GOAL_TORN
	return oil_share >= GOAL_OIL


func _next_stage() -> void:
	if not _goal_met() and not confirm_next:
		confirm_next = true
		toast(T("Задание этапа не выполнено. Enter ещё раз — всё равно идти дальше.", "The task of this stage is not done. Enter again to go on anyway."), true)
		return
	if stage == S_OIL:
		_finish()
	else:
		_enter_stage(stage + 1)


func _inspect() -> void:
	var pts: Array = wood.surface_points(220)
	var torn := 0
	for s in pts:
		if int(s.fin) == Wood.F_TORN:
			torn += 1
	torn_share = float(torn) / maxf(pts.size(), 1.0)


func _oil_progress() -> void:
	var n := 0
	for s in oil_points:
		var p: Vector3 = s.p
		var nn: Vector3 = s.n
		if wood.attr_at(p + nn * 0.4).y > 60:
			n += 1
	oil_share = float(n) / maxf(oil_points.size(), 1.0)


func _finish() -> void:
	mode = M_DONE
	preview_mesh.clear_surfaces()
	WoodView.set_flags(view, false, false)
	hud.set_text(hud.task_lbl, "")
	hud.set_text(hud.info_lbl, "")
	hud.set_text(hud.toast_lbl, "")
	WoodView.sync(view, wood)
	final_stats = wood.stats(float(species.dens))
	final_stats["hole"] = hole
	final_stats["species"] = species.id
	final_stats["no"] = spoon_no
	final_stats["strokes"] = strokes
	_save_spoon()
	_show_final()


func _verdict(st: Dictionary) -> String:
	if bool(st.get("hole", false)) or float(st.wall) < 0.6:
		return T("Дырявая, но своя. Такой удобно сцеживать.", "It has a hole, but it is yours. Handy for straining.")
	if float(st.cavity) > 6.0:
		return T("Скорее лопатка, чем ложка: чаша почти не выбрана.", "More of a spatula than a spoon: the bowl is hardly hollowed.")
	var q := 0
	if float(st.waste) < 12.0:
		q += 1
	if float(st.over) < 1.5:
		q += 1
	if float(st.torn) < 0.05:
		q += 1
	if float(st.symmetry) > 0.93:
		q += 1
	if float(st.wall) >= 2.0 and float(st.wall) <= 5.5:
		q += 1
	if q >= 5:
		return T("Ложка мастера. Такой не стыдно есть при гостях.", "A master's spoon. You could eat with it in company.")
	if q >= 3:
		return T("Хорошая, честная ложка. Суп ей будет вкуснее.", "A good, honest spoon. Soup will taste better with it.")
	return T("Первая ложка всегда такая. Она ваша — и следующая выйдет лучше.", "A first spoon is always like this. It is yours, and the next one will be better.")


func _stats_text(st: Dictionary) -> String:
	var sp := _species_by_id(String(st.species))
	var t := "[font_size=22][color=#e9c98a]%s %d · %s[/color][/font_size]\n" % [T("Ложка №", "Spoon No."), int(st.no), T(sp.ru, sp.en)]
	t += "[color=#d8c9a8]%s[/color]\n\n" % _verdict(st)
	t += "%s  %.0f %s\n" % [T("Вес:", "Weight:"), float(st.weight), T("г", "g")]
	t += "%s  %.1f %s\n" % [T("Стенка чаши (самое тонкое место):", "Bowl wall (thinnest place):"), float(st.wall), T("мм", "mm")]
	t += "%s  %d %%\n" % [T("Симметрия:", "Symmetry:"), int(float(st.symmetry) * 100.0)]
	t += "%s  %.1f %s      %s  %.1f %s\n" % [T("Осталось лишнего:", "Waste left on:"), float(st.waste), T("см³", "cm³"), T("срезано лишнего:", "cut away too much:"), float(st.over), T("см³", "cm³")]
	t += "%s  %d %%   %s %d %%   %s %d %%\n" % [T("Поверхность: срезы ножа", "Surface: knife facets"), int(float(st.knife) * 100.0), T("шлифовка", "sanded"), int(float(st.sanded) * 100.0), T("задиры", "torn"), int(float(st.torn) * 100.0)]
	t += "%s  %d\n" % [T("Срезов сделано:", "Cuts made:"), int(st.strokes)]
	return t


func _show_final() -> void:
	var t := _stats_text(final_stats)
	t += "\n[color=#8fc0e8][E][/color] %s    [color=#8fc0e8][N][/color] %s    [color=#8fc0e8][Esc][/color] %s" % [T("сохранить фото и 3D-модель (STL)", "save a photo and a 3D model (STL)"), T("новая ложка", "a new spoon"), T("меню", "menu")]
	if export_msg != "":
		t += "\n[color=#9c9]%s[/color]" % export_msg
	hud.set_text(hud.tools_lbl, t)
	hud.keys_lbl.text = T("Мышь с правой кнопкой — повернуть, колесо — ближе / дальше", "Right mouse button: turn, wheel: closer / further")


func _species_by_id(id: String) -> Dictionary:
	for sp in SPECIES:
		if sp.id == id:
			return sp
	return SPECIES[0]


# ---------------------------------------------------------------- saved spoons

func _load_gallery() -> void:
	gallery = []
	var d := DirAccess.open("user://spoons")
	if d == null:
		return
	var names := d.get_files()
	names.sort()
	for f in names:
		if f.ends_with(".spoon"):
			gallery.append("user://spoons/" + f)


func _save_spoon() -> void:
	DirAccess.make_dir_recursive_absolute("user://spoons")
	var path := "user://spoons/spoon_%03d.spoon" % spoon_no
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	var vx: PackedByteArray = wood.vox
	f.store_var({"stats": final_stats, "size": vx.size(), "vox": vx.compress(FileAccess.COMPRESSION_ZSTD), "ccount": wood.ccount})
	f.close()
	if not gallery.has(path):
		gallery.append(path)


func _show_gallery(i: int) -> void:
	if gallery.is_empty():
		return
	gallery_i = posmod(i, gallery.size())
	var f := FileAccess.open(gallery[gallery_i], FileAccess.READ)
	if f == null:
		return
	var d = f.get_var()
	if typeof(d) != TYPE_DICTIONARY:
		return
	if wood == null:
		wood = Wood.new()
		wood.new_billet()
	var z: PackedByteArray = d.vox
	wood.vox = z.decompress(int(d.size), FileAccess.COMPRESSION_ZSTD)
	wood.ccount = d.ccount
	wood.dirty = true
	if view == null:
		view = WoodView.make(wood)
		piece.add_child(view)
	else:
		WoodView.sync(view, wood)
	view.visible = true
	final_stats = d.stats
	species = _species_by_id(String(final_stats.species))
	WoodView.set_species(view, species)
	WoodView.set_flags(view, false, false)
	mode = M_GALLERY
	hud.hide_overlay()
	hud.set_text(hud.task_lbl, "")
	hud.set_text(hud.info_lbl, "")
	hud.set_text(hud.toast_lbl, "")
	var t := _stats_text(final_stats)
	t += "\n[color=#8fc0e8]← →[/color] %s (%d / %d)    [color=#8fc0e8][Esc][/color] %s" % [T("другие ложки", "other spoons"), gallery_i + 1, gallery.size(), T("меню", "menu")]
	hud.set_text(hud.tools_lbl, t)
	hud.keys_lbl.text = ""


func _export() -> void:
	if export_thread != null:
		return
	DirAccess.make_dir_recursive_absolute("user://spoons")
	var base := "user://spoons/spoon_%03d" % int(final_stats.get("no", spoon_no))
	get_viewport().get_texture().get_image().save_png(base + ".png")
	export_msg = T("Сохраняю 3D-модель...", "Saving the 3D model...")
	_show_final()
	if OS.has_feature("web"):
		# no threads and no folder to open in a browser: build the STL in place, hand both files over as downloads
		if web_exporting:
			return
		web_exporting = true
		JavaScriptBridge.download_buffer(FileAccess.get_file_as_bytes(base + ".png"), base.get_file() + ".png", "image/png")
		await get_tree().process_frame
		await get_tree().process_frame
		var ok: bool = Exporter.write_stl(wood, base + ".stl")
		if ok:
			JavaScriptBridge.download_buffer(FileAccess.get_file_as_bytes(base + ".stl"), base.get_file() + ".stl", "model/stl")
		export_msg = T("Скачано: ", "Downloaded: ") + base.get_file() + (".png, .stl" if ok else ".png  (STL: error)")
		web_exporting = false
		if mode == M_DONE:
			_show_final()
		return
	export_thread = Thread.new()
	export_thread.start(Exporter.write_stl.bind(wood, base + ".stl"))


# ================================================================ text

func toast(text: String, bad := false) -> void:
	toast_text = "[color=%s]%s[/color]" % ["#f0a070" if bad else "#d8c9a8", text]
	toast_t = 5.0
	hud.set_text(hud.toast_lbl, toast_text)


func toast_once(key: String, text: String, bad := false, every := 12.0) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if toast_times.has(key) and now - float(toast_times[key]) < every:
		return
	toast_times[key] = now
	toast(text, bad)


func _line(done: bool, text: String) -> String:
	return "[color=%s]%s %s[/color]\n" % ["#8fd08f" if done else "#f0e2c0", "+" if done else "-", text]


func _update_text() -> void:
	if mode != M_CARVE:
		return
	var w: float = wood.waste * VOX_CM3
	var cv: float = wood.cavity * VOX_CM3
	var ov: float = wood.over * VOX_CM3
	var names: Array = [T("Пила", "Saw"), T("Нож", "Knife"), T("Ложкорез", "Hook knife"), T("Отделка", "Finish"), T("Масло", "Oil")]
	var t := "[color=#e9c98a]%s %d/5 · %s[/color]\n" % [T("ЗАДАНИЕ", "TASK"), stage + 1, names[stage]]
	if stage == S_SAW:
		t += _line(w <= GOAL_SAW, T("Отпилить лишнее от полена: осталось %.0f см³, нужно не больше %.0f", "Saw the waste off the log: %.0f cm³ left, no more than %.0f wanted") % [w, GOAL_SAW])
		t += T("1. Торец черенка: сверху по метке X 223, насквозь.\n2. Шейка, X 82: запилы с боков и снизу, каждый на 21 мм.\n3. С торца вдоль черенка: в 11 мм по обе стороны от оси и в 11 мм под верхом — до запилов.\nОтпиленное падает само. Всё, что не взяла пила, — ножом.\n",
			"1. End of the handle: from the top at the X 223 mark, right through.\n2. Neck, X 82: stop cuts from both sides and from below, 21 mm each.\n3. From the end along the handle: 11 mm either side of the axis and 11 mm below the top, up to the stop cuts.\nOffcuts fall by themselves. What the saw leaves is knife work.\n")
	elif stage == S_KNIFE:
		t += _line(w <= GOAL_KNIFE, T("Довести форму: лишнего %.1f см³, нужно не больше %.0f", "Shape it: %.1f cm³ of waste, no more than %.0f wanted") % [w, GOAL_KNIFE])
		t += T("Зелёная линия — чисто, жёлтая — зацепит, красная — задир.\n", "Green line: clean. Yellow: it will catch. Red: tear-out.\n")
	elif stage == S_HOOK:
		t += _line(cv <= GOAL_HOOK, T("Выбрать чашу: осталось %.1f см³, нужно не больше %.1f", "Hollow the bowl: %.1f cm³ left, no more than %.1f wanted") % [cv, GOAL_HOOK])
		t += T("Режьте поперёк волокон, от края к середине. Стенка — 3 мм.\n", "Cut across the grain, from the rim to the middle. Wall: 3 mm.\n")
	elif stage == S_FINISH:
		t += _line(torn_share <= GOAL_TORN, T("Убрать задиры тонкими срезами: сейчас %d %% поверхности, нужно не больше 5", "Clean up torn grain with thin cuts: now %d %% of the surface, no more than 5 wanted") % int(torn_share * 100.0))
		t += T("По желанию: шкурка (4). I — осмотреть заново.\n", "If you like: sandpaper (4). I: inspect again.\n")
	else:
		t += _line(oil_share >= GOAL_OIL, T("Натереть льняным маслом всю ложку: покрыто %d %%, нужно 90", "Rub linseed oil into the whole spoon: %d %% covered, 90 wanted") % int(oil_share * 100.0))
	if ov > 0.05:
		t += "[color=#f0a070]%s %.1f %s[/color]\n" % [T("Срезано лишнего (уже не вернуть):", "Cut away too much (it will not come back):"), ov, T("см³", "cm³")]
	if _goal_met():
		t += "[color=#8fd08f]%s[/color]" % T("Готово. Enter — дальше.", "Done. Enter: go on.")
	hud.set_text(hud.task_lbl, t)

	var tn: Array = [T("Пила", "Saw"), T("Нож", "Knife"), T("Ложкорез", "Hook knife"), T("Шкурка", "Sandpaper"), T("Масло", "Oil")]
	var tt := ""
	for i in tn.size():
		if i == tool:
			tt += "[color=#e9c98a]> %d  %s[/color]\n" % [i + 1, tn[i]]
		else:
			tt += "[color=#998b74]  %d  %s[/color]\n" % [i + 1, tn[i]]
	if tool == T_KNIFE or tool == T_HOOK:
		var bites: Array = HOOK_BITES if tool == T_HOOK else KNIFE_BITES
		tt += "\n%s  [color=#e9c98a]%.1f %s[/color]  (Z / X)\n" % [T("Стружка:", "Shaving:"), float(bites[bite_i]), T("мм", "mm")]
		tt += "%s  [color=%s]%d %%[/color]  (R — %s)\n" % [T("Острота:", "Edge:"), "#8fd08f" if sharp > 0.5 else "#f0a070", int(sharp * 100.0), T("править", "strop")]
	hud.set_text(hud.tools_lbl, tt)

	var keys := ""
	if tool == T_SAW:
		keys = T("Зажмите левую кнопку и водите мышью вдоль пропила, туда-сюда", "Hold the left button and move the mouse to and fro along the cut")
	elif tool == T_KNIFE or tool == T_HOOK:
		keys = T("Проведите с зажатой левой кнопкой — срез от начала до конца линии", "Drag with the left button: one cut from the start to the end of the line")
	elif tool == T_SAND:
		keys = T("Трите с зажатой левой кнопкой", "Rub with the left button held")
	else:
		keys = T("Втирайте масло с зажатой левой кнопкой", "Rub the oil in with the left button held")
	keys += T("   ·   правая кнопка: повернуть   ·   пробел: перевернуть   ·   колесо: ближе   ·   H: лишнее   ·   U: откат этапа   ·   Enter: дальше   ·   M: звук   ·   P: музыка", "   ·   right button: turn   ·   space: flip   ·   wheel: zoom   ·   H: waste   ·   U: redo stage   ·   Enter: go on   ·   M: sound   ·   P: music")
	hud.keys_lbl.text = keys


# ================================================================ picking

func _mouse_ray() -> Array:
	var mp := get_viewport().get_mouse_position()
	var ro_w := cam.project_ray_origin(mp)
	var rd_w := cam.project_ray_normal(mp)
	var inv := piece.global_transform.affine_inverse()
	var c := Vector3(Wood.LEN, Wood.WID, Wood.HGT) * 0.5
	return [inv * ro_w + c, (inv.basis * rd_w).normalized()]


func _to_world(p: Vector3) -> Vector3:
	return piece.global_transform * (p - Vector3(Wood.LEN, Wood.WID, Wood.HGT) * 0.5)


func _dir_world(d: Vector3) -> Vector3:
	return (piece.global_transform.basis * d).normalized()


func _pick() -> Dictionary:
	var r := _mouse_ray()
	return wood.raycast(r[0], r[1])


# ================================================================ tools at work

func _burst(p: Vector3, n: Vector3, amount: int) -> void:
	chips.global_position = _to_world(p)
	chips.direction = _dir_world(n) + Vector3(0, 0.6, 0)
	chips.amount = clampi(amount, 2, 40)
	chips.restart()
	chips.emitting = true
	pile_n = mini(pile_n + maxi(amount / 3, 1), 700)
	pile.multimesh.visible_instance_count = pile_n


func _after_cut() -> void:
	strokes += 1
	_update_text()


func _check_break(x0: float, x1: float) -> void:
	var a := maxf(minf(x0, x1) - 3.0, 86.0)
	var b := minf(maxf(x0, x1) + 3.0, 214.0)
	if b <= a:
		return
	var sec: float = wood.min_section(a, b)
	if sec < 14.0:
		wood.broken = true
		synth.thock = 0.8
		hud.show_overlay("[center][font_size=24][color=#f0a070]%s[/color][/font_size]\n\n%s\n\n[color=#8fc0e8][U][/color] %s      [color=#8fc0e8][N][/color] %s[/center]" % [T("Черенок сломался", "The handle snapped"), T("Сечение стало тоньше спички. Дерево такого не прощает.", "The section got thinner than a match. Wood does not forgive that."), T("взять заготовку с начала этапа", "take the blank from the start of this stage"), T("новое полено", "a new log")])
	elif sec < 30.0:
		toast_once("thin", T("Черенок здесь уже тоньше карандаша (%.0f мм²). Ещё немного — и сломается.", "The handle here is already thinner than a pencil (%.0f mm²). A little more and it snaps.") % sec, true, 6.0)


func _do_stroke() -> void:
	var a: Vector3 = stroke_a.p
	var b: Vector3 = stroke_last.p
	var na: Vector3 = stroke_a.n
	var nb: Vector3 = stroke_last.n
	var hook := tool == T_HOOK
	var maxlen := 45.0 if hook else 80.0
	var chord := b - a
	if chord.length() < 2.5:
		return
	if chord.length() > maxlen:
		b = a + chord.normalized() * maxlen
	if hover.is_empty():
		b += (b - a).normalized() * 5.0      # the stroke ran off the edge: the chip comes free
	var n := (na + nb).normalized()
	var hard: float = species.hard
	var bites: Array = HOOK_BITES if hook else KNIFE_BITES
	var bite: float = float(bites[bite_i]) * (0.55 + 0.45 * sharp)
	var tear_k := hard * (1.0 + 1.6 * (1.0 - sharp))
	var res: Dictionary = wood.knife_cut(a, b, n, bite, 16.0 if hook else 28.0, 15.0 if hook else 0.0, tear_k)
	var vol: float = res.vol
	synth.slice_len = clampf((b - a).length() / 160.0, 0.12, 0.5)
	synth.slice = synth.slice_len
	synth.tearing = float(res.torn)
	if vol > 0.5:
		_burst((a + b) * 0.5, n, int(vol / 25.0) + 2)
	sharp = maxf(sharp - vol * hard / 60000.0, 0.0)
	if float(res.torn) > 0.12:
		toast_once("tear", T("Задир: срез шёл против волокна. Режьте с другой стороны — «под горку».", "Tear-out: that cut went against the grain. Cut from the other side, downhill."), true, 8.0)
	if sharp < 0.35:
		toast_once("dull", T("Нож затупился: мнёт и рвёт. R — править на ремне.", "The knife is dull: it crushes and tears. R: strop it."), true, 15.0)
	if hook:
		var mid := (a + b) * 0.5
		var h: Dictionary = wood.raycast(mid + n * 25.0, -n)
		if not h.is_empty():
			var th: float = wood.thickness(h.p, h.n)
			if th < 0.7:
				hole = true
				toast(T("Прорезали дно насквозь. Дырку уже не заделать.", "You went through the bottom. That hole is there to stay."), true)
			elif th < 2.0:
				toast_once("wall", T("Стенка здесь %.1f мм — тоньше нельзя.", "The wall here is %.1f mm: no thinner.") % th, true, 5.0)
	_check_break(a.x, b.x)
	if stage == S_FINISH and strokes % 6 == 0:
		_inspect()
	_after_cut()


func _saw_info() -> String:
	if stroke_a.is_empty():
		return ""
	var p: Vector3 = stroke_a.p
	var n: Vector3 = stroke_a.n
	var t := 0.0
	var left := -1.0
	while t < 160.0:
		var q := p - n * t
		if Wood.target(q.x, q.y, q.z) != 0:
			left = t - saw_depth
			break
		t += 0.5
	var s := "%s  [color=#e9c98a]%.0f %s[/color]\n" % [T("Глубина пропила:", "Depth of cut:"), saw_depth, T("мм", "mm")]
	if left >= 0.0:
		s += "[color=%s]%s  %.0f %s[/color]\n" % ["#f0a070" if left < 1.0 else "#8fd08f", T("До ложки осталось:", "Left to the spoon:"), maxf(left, 0.0), T("мм", "mm")]
	return s


func _strop() -> void:
	busy_t = 1.6
	synth.strop = 0.8
	sharp = 1.0
	toast(T("Нож поправлен на ремне с пастой. Снова бреет.", "The knife is stropped. It shaves again."))
	_update_text()


# ================================================================ frame loop

func _process(dt: float) -> void:
	dt = minf(dt, 0.05)
	cam.position = Vector3(0, 0.8, 0.6).normalized() * cam_dist
	cam.look_at(Vector3(0, -4, 0), Vector3.UP)
	if toast_t > 0.0:
		toast_t -= dt
		if toast_t <= 0.0:
			hud.set_text(hud.toast_lbl, "")
	if export_thread != null and not export_thread.is_alive():
		var res = export_thread.wait_to_finish()
		export_thread = null
		export_msg = T("Сохранено: ", "Saved: ") + ProjectSettings.globalize_path("user://spoons") + ("" if res else "  (STL: error)")
		if mode == M_DONE:
			_show_final()
		OS.shell_open(ProjectSettings.globalize_path("user://spoons"))
	if mode == M_DONE or mode == M_GALLERY:
		if not rotating:
			piece.basis = Basis(Vector3.UP, dt * 0.35) * piece.basis
		return
	if mode != M_CARVE or wood == null:
		return
	if busy_t > 0.0:
		busy_t -= dt
	sync_t += dt
	if wood.dirty and sync_t > 0.07:
		WoodView.sync(view, wood)
		sync_t = 0.0
	if wood.broken or hud.overlay_visible():
		preview_mesh.clear_surfaces()
		return
	hover = {} if rotating else _pick()
	_tool_frame(dt)
	_draw_marks()
	_update_info()


func _tool_frame(dt: float) -> void:
	if not acting:
		hud.set_charge(Vector2.ZERO, 0.0)
		return
	if tool == T_KNIFE or tool == T_HOOK:
		if not hover.is_empty():
			stroke_last = hover
	elif tool == T_SAW:
		var want := saw_acc * 0.07 * (1.0 / float(species.hard))
		if saw_dir != Vector3.ZERO and want - saw_depth >= 0.8:
			var into: Vector3 = -Vector3(stroke_a.n)
			wood.saw_cut(stroke_a.p, saw_dir, into, want, saw_depth)
			saw_depth = want
			var tip: Vector3 = Vector3(stroke_a.p) + into * (saw_depth + 1.0)
			if Wood.target(tip.x, tip.y, tip.z) != 0 and wood.dens(tip) > 0.5:
				toast_once("sawline", T("Стоп — пила дошла до ложки. Глубже — уже по ней.", "Stop: the saw has reached the spoon. Any deeper cuts into it."), true, 3.0)
			synth.rasp = 0.6
			if randf() < 0.3:
				_burst(stroke_a.p, stroke_a.n, 2)
			_update_text()
	elif tool == T_SAND or tool == T_OIL:
		rub_t += dt
		if rub_t > 0.05 and not hover.is_empty():
			rub_t = 0.0
			if tool == T_SAND:
				wood.sand(hover.p, 5.0)
				synth.sanding = 0.7
			else:
				wood.oil(hover.p, 10.0)
				synth.sanding = 0.25
				_oil_progress()
				_update_text()


func _seg(a: Vector3, b: Vector3, col: Color) -> void:
	var c := Vector3(Wood.LEN, Wood.WID, Wood.HGT) * 0.5
	preview_mesh.surface_set_color(col)
	preview_mesh.surface_add_vertex(a - c)
	preview_mesh.surface_set_color(col)
	preview_mesh.surface_add_vertex(b - c)


func _ring(p: Vector3, n: Vector3, r: float, col: Color) -> void:
	var u := n.cross(Vector3(1, 0, 0))
	if u.length() < 0.1:
		u = n.cross(Vector3(0, 1, 0))
	u = u.normalized()
	var v := n.cross(u)
	for i in 16:
		var a0 := i * TAU / 16.0
		var a1 := (i + 1) * TAU / 16.0
		_seg(p + (u * cos(a0) + v * sin(a0)) * r + n * 0.5, p + (u * cos(a1) + v * sin(a1)) * r + n * 0.5, col)


## Light marks on the wood: where the tool will go and what it will take.
func _draw_marks() -> void:
	preview_mesh.clear_surfaces()
	var h: Dictionary = hover
	if acting and not stroke_a.is_empty():
		h = stroke_a
	if h.is_empty():
		return
	var p: Vector3 = h.p
	var n: Vector3 = h.n
	var pale := Color(1.0, 0.95, 0.8)
	preview_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	if tool == T_SAW:
		if acting and saw_dir != Vector3.ZERO:
			_seg(p - saw_dir * 60.0 + n * 0.5, p + saw_dir * 60.0 + n * 0.5, pale)
			_seg(p, p - n * saw_depth, Color(1.0, 0.7, 0.3))
		else:
			_ring(p, n, 2.5, pale)
	elif tool == T_KNIFE or tool == T_HOOK:
		var hw := 8.0 if tool == T_HOOK else 14.0
		if acting and not stroke_last.is_empty() and (Vector3(stroke_last.p) - p).length() > 1.0:
			var q: Vector3 = stroke_last.p
			var nn: Vector3 = (n + Vector3(stroke_last.n)).normalized()
			var bites: Array = HOOK_BITES if tool == T_HOOK else KNIFE_BITES
			var cd := (q - p).normalized()
			var tk: float = float(species.hard) * (1.0 + 1.6 * (1.0 - sharp))
			var bad: float = wood.grain(p, q, nn, float(bites[bite_i]) * (0.55 + 0.45 * sharp), 15.0 if tool == T_HOOK else 0.0, tk)
			stroke_bad = bad
			var col := Color(0.4, 0.95, 0.45)
			if bad > 0.3:
				col = Color(1.0, 0.3, 0.25)
			elif bad > 0.0:
				col = Color(1.0, 0.8, 0.3)
			var bl := nn.cross(cd).normalized() * hw
			var up := nn * 0.6
			_seg(p + up, q + up, col)
			_seg(p - bl + up, q - bl + up, col * Color(1, 1, 1, 0.5))
			_seg(p + bl + up, q + bl + up, col * Color(1, 1, 1, 0.5))
			_seg(q - bl + up, q + bl + up, col)
		else:
			_ring(p, n, 2.5, pale)
	elif tool == T_SAND:
		_ring(p, n, 5.0, pale)
	else:
		_ring(p, n, 10.0, pale)
	preview_mesh.surface_end()


func _update_info() -> void:
	var t := ""
	if tool == T_SAW and acting:
		t = _saw_info()
	elif (tool == T_KNIFE or tool == T_HOOK) and acting and not stroke_a.is_empty() and not stroke_last.is_empty():
		var a: Vector3 = stroke_a.p
		var b: Vector3 = stroke_last.p
		var n: Vector3 = (Vector3(stroke_a.n) + Vector3(stroke_last.n)).normalized()
		if stroke_bad > 0.3:
			t = "[color=#f0a070]%s[/color]\n" % T("ПРОТИВ ВОЛОКНА — будет задир", "AGAINST THE GRAIN: it will tear")
		elif stroke_bad > 0.0:
			t = "[color=#e9c98a]%s[/color]\n" % T("на подъёме зацепит волокно — тоньше стружку или короче срез", "it will catch the grain on the way up: thinner shaving or shorter cut")
		elif absf((b - a).normalized().x) < 0.35:
			t = "[color=#8fd08f]%s[/color]\n" % T("поперёк волокон", "across the grain")
		else:
			t = "[color=#8fd08f]%s[/color]\n" % T("по волокну", "with the grain")
		t += "%s %.0f %s\n" % [T("Длина среза:", "Length of cut:"), (b - a).length(), T("мм", "mm")]
	if not hover.is_empty() and (tool == T_HOOK or tool == T_KNIFE or tool == T_SAND) and not acting:
		var th: float = wood.thickness(hover.p, hover.n)
		if th < 40.0:
			t += "%s  [color=%s]%.1f %s[/color]\n" % [T("Толщина под пальцами:", "Thickness under your fingers:"), "#f0a070" if th < 2.0 else "#e9c98a", th, T("мм", "mm")]
	if tool == T_SAW and not acting and not hover.is_empty():
		var hp: Vector3 = hover.p
		t = "[color=#e9c98a]X %.0f[/color]  ·  %s [color=#e9c98a]%.0f[/color]  ·  %s [color=#e9c98a]%.0f[/color] %s\n" % [hp.x, T("от оси", "off the axis"), absf(hp.y - 32.0), T("под верхом", "below the top"), 32.0 - hp.z, T("мм", "mm")]
	hud.set_text(hud.info_lbl, t)


# ================================================================ input

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			cam_dist = maxf(cam_dist * 0.92, 110.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			cam_dist = minf(cam_dist * 1.08, 520.0)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			rotating = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_LEFT and mode == M_CARVE and not wood.broken and not hud.overlay_visible():
			if mb.pressed:
				_press()
			else:
				_release()
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		if rotating and mode != M_MENU:
			piece.basis = (Basis(Vector3.UP, mm.relative.x * 0.008) * Basis(Vector3.RIGHT, mm.relative.y * 0.008) * piece.basis).orthonormalized()
		elif acting and tool == T_SAW:
			if saw_dir == Vector3.ZERO:
				_set_saw_dir()
			else:
				saw_acc += mm.relative.length()
	elif ev is InputEventKey:
		var k := ev as InputEventKey
		if k.pressed and not k.echo:
			_key(k.physical_keycode)


func _press() -> void:
	if busy_t > 0.0:
		return
	var h := _pick()
	if h.is_empty():
		return
	acting = true
	stroke_a = h
	stroke_last = h
	saw_acc = 0.0
	saw_depth = 0.0
	saw_dir = Vector3.ZERO
	saw_press = get_viewport().get_mouse_position()
	rub_t = 1.0


## The saw lies along the first move of the mouse over the wood (snapped to the grain,
## square to it, or upright when within 15 degrees of one of those).
func _set_saw_dir() -> void:
	if (get_viewport().get_mouse_position() - saw_press).length() < 14.0:
		return
	var p: Vector3 = stroke_a.p
	var n: Vector3 = stroke_a.n
	var r := _mouse_ray()
	var ro: Vector3 = r[0]
	var rd: Vector3 = r[1]
	var den := rd.dot(n)
	if absf(den) < 0.05:
		return
	var v := ro + rd * ((p - ro).dot(n) / den) - p
	v -= n * v.dot(n)
	if v.length() < 0.5:
		return
	v = v.normalized()
	for ax in [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)]:
		var c: Vector3 = ax - n * n.dot(ax)
		if c.length() > 0.5:
			c = c.normalized()
			if absf(v.dot(c)) > 0.966:
				v = c * signf(v.dot(c))
	saw_dir = v


func _release() -> void:
	if not acting:
		return
	acting = false
	preview_mesh.clear_surfaces()
	hud.set_charge(Vector2.ZERO, 0.0)
	if tool == T_KNIFE or tool == T_HOOK:
		hover = _pick()
		_do_stroke()
	elif tool == T_SAW:
		if saw_depth > 0.5:
			var lost0: int = wood.over
			var fell: float = wood.drop_offcuts()
			if (wood.over - lost0) * VOX_CM3 > 1.0:
				toast(T("Отпилили кусок самой ложки.  U — вернуть начало этапа.", "That offcut took part of the spoon with it.  U: back to the stage start."), true)
				synth.thock = 0.4
			elif fell > 50.0:
				toast(T("Отпиленный кусок упал на верстак: %.0f см³.", "The offcut drops onto the bench: %.0f cm³.") % (fell * 0.001))
				synth.thock = 0.4
			_after_cut()
	elif tool == T_SAND:
		if stage == S_FINISH:
			_inspect()
		_after_cut()
	stroke_a = {}


func _key(kc: int) -> void:
	if kc == KEY_L:
		lang = "en" if lang == "ru" else "ru"
		if mode == M_MENU:
			_show_menu()
		elif mode == M_DONE:
			_show_final()
		elif mode == M_GALLERY:
			_show_gallery(gallery_i)
		else:
			_update_text()
		return
	if kc == KEY_P:
		synth.music = not synth.music
		toast(T("Музыка: вкл.", "Music: on") if synth.music else T("Музыка: выкл.", "Music: off"))
		return
	if kc == KEY_M:
		synth.muted = not synth.muted
		return
	if mode == M_MENU:
		if kc >= KEY_1 and kc < KEY_1 + SPECIES.size():
			start(kc - KEY_1)
		elif kc == KEY_G and gallery.size() > 0:
			_show_gallery(gallery.size() - 1)
	elif mode == M_GALLERY:
		if kc == KEY_LEFT:
			_show_gallery(gallery_i - 1)
		elif kc == KEY_RIGHT:
			_show_gallery(gallery_i + 1)
		elif kc == KEY_ESCAPE:
			hud.set_text(hud.tools_lbl, "")
			_show_menu()
	elif mode == M_DONE:
		if kc == KEY_E:
			_export()
		elif kc == KEY_N or kc == KEY_ESCAPE:
			hud.set_text(hud.tools_lbl, "")
			export_msg = ""
			_show_menu()
	elif mode == M_CARVE:
		if wood.broken:
			if kc == KEY_U:
				wood.restore(checkpoint)
				hud.hide_overlay()
				_update_text()
			elif kc == KEY_N:
				hud.hide_overlay()
				_show_menu()
			return
		if kc >= KEY_1 and kc <= KEY_5:
			_set_tool(kc - KEY_1)
		elif kc == KEY_Z:
			bite_i = maxi(bite_i - 1, 0)
			_update_text()
		elif kc == KEY_X:
			bite_i = mini(bite_i + 1, (HOOK_BITES.size() if tool == T_HOOK else KNIFE_BITES.size()) - 1)
			_update_text()
		elif kc == KEY_R:
			_strop()
		elif kc == KEY_H:
			show_hint = not show_hint
			WoodView.set_flags(view, show_lines, show_hint)
		elif kc == KEY_SPACE:
			piece.basis = (Basis(_dir_world(Vector3(1, 0, 0)), PI) * piece.basis).orthonormalized()
		elif kc == KEY_I:
			_inspect()
			_update_text()
		elif kc == KEY_U:
			wood.restore(checkpoint)
			toast(T("Взята заготовка с начала этапа.", "Back to the blank from the start of this stage."))
			_update_text()
		elif kc == KEY_ENTER or kc == KEY_KP_ENTER:
			_next_stage()
		elif kc == KEY_ESCAPE:
			_show_menu()
