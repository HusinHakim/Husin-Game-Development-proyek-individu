extends CanvasLayer

const SLOT_W        := 58.0
const SLOT_H        := 80.0   # key-hint 12 + icon 38 + label 20 + padding
const SLOT_GAP      := 6.0
const MAX_SLOTS     := 5
const MARGIN_BOTTOM := 12.0
const ICON_SIZE     := 36.0

const C_BG_EMPTY      := Color(0.11, 0.09, 0.08, 0.84)
const C_BG_FILLED     := Color(0.20, 0.17, 0.13, 0.90)
const C_BG_ACTIVE     := Color(0.30, 0.20, 0.06, 0.94)
const C_BORDER        := Color(0.42, 0.36, 0.28, 1.00)
const C_BORDER_ACTIVE := Color(0.85, 0.62, 0.18, 1.00)
const C_KEY_HINT      := Color(0.55, 0.48, 0.36, 1.00)
const C_KEY_ACTIVE    := Color(0.95, 0.72, 0.24, 1.00)
const C_ITEM_TEXT     := Color(0.92, 0.86, 0.74, 1.00)

var _panels:     Array[Panel]       = []
var _item_labels: Array[Label]      = []
var _key_labels:  Array[Label]      = []
var _icon_rects:  Array[TextureRect] = []


func _ready() -> void:
	layer = 5
	_build_ui()


func _build_ui() -> void:
	var total_w := MAX_SLOTS * SLOT_W + (MAX_SLOTS - 1) * SLOT_GAP
	var vp := Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height")
	)

	var hbox := HBoxContainer.new()
	hbox.position = Vector2(
		(vp.x - total_w) * 0.5,
		vp.y - SLOT_H - MARGIN_BOTTOM
	)
	hbox.size = Vector2(total_w, SLOT_H)
	hbox.add_theme_constant_override("separation", int(SLOT_GAP))
	add_child(hbox)

	for i in range(MAX_SLOTS):
		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(SLOT_W, SLOT_H)
		panel.add_theme_stylebox_override("panel", _make_style(false, false))
		hbox.add_child(panel)
		_panels.append(panel)

		# ── Key hint (top-left) ──────────────────────────────────────
		var key_lbl := Label.new()
		key_lbl.text = str(i + 1)
		key_lbl.position = Vector2(4.0, 2.0)
		key_lbl.size = Vector2(SLOT_W - 8.0, 12.0)
		key_lbl.add_theme_font_size_override("font_size", 10)
		key_lbl.add_theme_color_override("font_color", C_KEY_HINT)
		panel.add_child(key_lbl)
		_key_labels.append(key_lbl)

		# ── Item icon (center, below key hint) ───────────────────────
		var icon_x := (SLOT_W - ICON_SIZE) * 0.5
		var icon := TextureRect.new()
		icon.position = Vector2(icon_x, 14.0)
		icon.size = Vector2(ICON_SIZE, ICON_SIZE)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		panel.add_child(icon)
		_icon_rects.append(icon)

		# ── Item name label (bottom) ─────────────────────────────────
		var item_lbl := Label.new()
		item_lbl.position = Vector2(2.0, 54.0)
		item_lbl.size = Vector2(SLOT_W - 4.0, 22.0)
		item_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		item_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		item_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		item_lbl.add_theme_font_size_override("font_size", 8)
		item_lbl.add_theme_color_override("font_color", C_ITEM_TEXT)
		panel.add_child(item_lbl)
		_item_labels.append(item_lbl)

	update_display([], 0)


func update_display(inventory: Array, active_slot: int) -> void:
	for i in range(MAX_SLOTS):
		var has_item  := i < inventory.size()
		var is_active := i == active_slot

		_panels[i].add_theme_stylebox_override("panel", _make_style(is_active, has_item))

		if has_item:
			_item_labels[i].text = inventory[i].item_display_name
			_icon_rects[i].texture = inventory[i].item_icon
		else:
			_item_labels[i].text = ""
			_icon_rects[i].texture = null

		_key_labels[i].add_theme_color_override(
			"font_color", C_KEY_ACTIVE if is_active else C_KEY_HINT
		)


func _make_style(active: bool, filled: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color    = C_BG_ACTIVE if active else (C_BG_FILLED if filled else C_BG_EMPTY)
	s.border_color = C_BORDER_ACTIVE if active else C_BORDER
	s.border_width_left   = 2
	s.border_width_top    = 2
	s.border_width_right  = 2
	s.border_width_bottom = 2
	s.corner_radius_top_left     = 4
	s.corner_radius_top_right    = 4
	s.corner_radius_bottom_left  = 4
	s.corner_radius_bottom_right = 4
	return s
