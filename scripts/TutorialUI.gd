extends CanvasLayer
# TutorialUI — first-time-player help panel shown in the Start room.
# Lists the core keybinds + the "throw to fight" rule. Built procedurally
# so positioning auto-adapts to the configured viewport.

const PANEL_W := 380.0
const MARGIN := 16.0

const C_BG     := Color(0.10, 0.07, 0.06, 0.92)
const C_BORDER := Color(0.65, 0.18, 0.12, 1.00)
const C_TITLE  := Color(0.96, 0.86, 0.55, 1.00)
const C_KEY    := Color(0.85, 0.95, 1.00, 1.00)
const C_DESC   := Color(0.92, 0.92, 0.92, 1.00)
const C_WARN   := Color(1.00, 0.78, 0.45, 1.00)
const C_HINT   := Color(0.65, 0.95, 0.65, 1.00)


func _ready() -> void:
	layer = 8
	_build()


func _build() -> void:
	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel", _make_style())
	panel.position = Vector2(MARGIN, MARGIN)
	panel.custom_minimum_size = Vector2(PANEL_W, 0)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.position = Vector2(14, 12)
	vbox.custom_minimum_size = Vector2(PANEL_W - 28, 0)
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	_add_label(vbox, "How to Play", 22, C_TITLE)
	_add_label(vbox, "Slime Anomaly — pick up the world, throw it back.",
		13, Color(0.80, 0.80, 0.80), true)
	_add_spacer(vbox, 8)

	var rows: Array = [
		["WASD",         "Move"],
		["Shift",        "Dash / Sprint (uses stamina)"],
		["LMB",          "Throw active item toward cursor"],
		["RMB",          "Use Shield (Crystal Buckler)"],
		["G",            "Drop active item"],
		["1-5 / Scroll", "Select inventory slot"],
	]
	for r in rows:
		_add_keybind_row(vbox, r[0], r[1])

	_add_spacer(vbox, 8)
	_add_label(vbox,
		"You CANNOT attack directly. Throw items to defeat enemies.",
		13, C_WARN, true)
	_add_spacer(vbox, 4)
	_add_label(vbox,
		"Tip: time your shield right when the boss's red telegraph ENDS to stun it.",
		12, Color(0.85, 0.85, 0.85), true)
	_add_spacer(vbox, 6)
	_add_label(vbox, "Walk into the portal when you're ready.",
		12, C_HINT, true)

	# Resize panel to fit content height.
	await get_tree().process_frame
	panel.size = Vector2(PANEL_W, vbox.size.y + 24)


func _add_label(parent: Node, text: String, font_size: int, color: Color,
		wrap: bool = false) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(PANEL_W - 28, 0)
	parent.add_child(l)


func _add_keybind_row(parent: Node, key: String, desc: String) -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	parent.add_child(hbox)

	var k := Label.new()
	k.custom_minimum_size = Vector2(110, 0)
	k.text = key
	k.add_theme_font_size_override("font_size", 14)
	k.add_theme_color_override("font_color", C_KEY)
	hbox.add_child(k)

	var d := Label.new()
	d.text = desc
	d.add_theme_font_size_override("font_size", 14)
	d.add_theme_color_override("font_color", C_DESC)
	hbox.add_child(d)


func _add_spacer(parent: Node, h: float) -> void:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	parent.add_child(s)


func _make_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = C_BG
	s.border_color = C_BORDER
	s.border_width_left = 2
	s.border_width_top = 2
	s.border_width_right = 2
	s.border_width_bottom = 2
	s.corner_radius_top_left = 8
	s.corner_radius_top_right = 8
	s.corner_radius_bottom_left = 8
	s.corner_radius_bottom_right = 8
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 4
	return s
