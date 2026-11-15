extends CanvasLayer
## On-screen text: the task (always visible), tools, readouts, messages, and a centre panel for menus.

var root: Control
var task_lbl: RichTextLabel
var tools_lbl: RichTextLabel
var info_lbl: RichTextLabel
var toast_lbl: RichTextLabel
var keys_lbl: Label
var overlay_lbl: RichTextLabel
var charge_bar: ColorRect
var _overlay: PanelContainer
var _cache := {}


func _ready() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	task_lbl = _panel(0.5, 0.0, -360, 10, 720, 15, Color(0.1, 0.08, 0.05, 0.86), Color(0.75, 0.6, 0.35))
	tools_lbl = _panel(0.0, 0.0, 10, 10, 300, 14, Color(0.08, 0.07, 0.06, 0.8), Color(0.4, 0.33, 0.25))
	info_lbl = _panel(1.0, 0.0, -330, 10, 320, 14, Color(0.08, 0.07, 0.06, 0.8), Color(0.4, 0.33, 0.25))
	toast_lbl = _panel(0.5, 1.0, -360, -44, 720, 15, Color(0.08, 0.07, 0.06, 0.8), Color(0.4, 0.33, 0.25))
	keys_lbl = Label.new()
	keys_lbl.anchor_top = 1.0
	keys_lbl.anchor_bottom = 1.0
	keys_lbl.anchor_right = 1.0
	keys_lbl.offset_top = -32
	keys_lbl.offset_left = 10
	keys_lbl.offset_right = -10
	keys_lbl.add_theme_font_size_override("font_size", 13)
	keys_lbl.add_theme_color_override("font_color", Color(0.9, 0.86, 0.78))
	keys_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	keys_lbl.add_theme_constant_override("outline_size", 4)
	keys_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(keys_lbl)
	charge_bar = ColorRect.new()
	charge_bar.color = Color(0.95, 0.7, 0.3, 0.9)
	charge_bar.size = Vector2(0, 8)
	charge_bar.visible = false
	root.add_child(charge_bar)
	_overlay = PanelContainer.new()
	_overlay.add_theme_stylebox_override("panel", _style(Color(0.07, 0.055, 0.04, 0.94), Color(0.8, 0.62, 0.35)))
	_overlay.anchor_left = 0.5
	_overlay.anchor_right = 0.5
	_overlay.anchor_top = 0.5
	_overlay.anchor_bottom = 0.5
	_overlay.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_overlay.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(_overlay)
	overlay_lbl = _rich(760, 16)
	_overlay.add_child(overlay_lbl)
	_overlay.visible = false


func _style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(12)
	return sb


func _rich(width: float, font_size: int) -> RichTextLabel:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(width, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("normal_font_size", font_size)
	l.add_theme_font_size_override("bold_font_size", font_size)
	return l


func _panel(ax: float, ay: float, ox: float, oy: float, w: float, font_size: int, bg: Color, border: Color) -> RichTextLabel:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _style(bg, border))
	pc.anchor_left = ax
	pc.anchor_right = ax
	pc.anchor_top = ay
	pc.anchor_bottom = ay
	pc.offset_left = ox
	pc.offset_right = ox + w
	pc.offset_top = oy
	pc.offset_bottom = oy
	if ay > 0.5:
		pc.grow_vertical = Control.GROW_DIRECTION_BEGIN
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(pc)
	var l := _rich(w - 26.0, font_size)
	pc.add_child(l)
	return l


func set_text(l: RichTextLabel, t: String) -> void:
	if _cache.get(l) == t:
		return
	_cache[l] = t
	l.text = t
	(l.get_parent() as Control).visible = t != ""


func show_overlay(t: String) -> void:
	_overlay.visible = true
	if _cache.get(overlay_lbl) != t:
		_cache[overlay_lbl] = t
		overlay_lbl.text = t


func hide_overlay() -> void:
	_overlay.visible = false


func overlay_visible() -> bool:
	return _overlay.visible


func set_charge(pos: Vector2, v: float) -> void:
	charge_bar.visible = v > 0.0
	charge_bar.position = pos + Vector2(-40, 28)
	charge_bar.size = Vector2(80.0 * clampf(v, 0.0, 1.0), 8)
