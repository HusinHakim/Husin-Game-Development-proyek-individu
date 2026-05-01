extends CanvasLayer
# MainMenu — pre-game title screen. Shows the project name, the difficulty
# disclaimer, and Start / Quit buttons. Built entirely in code so the .tscn
# stays minimal and styling lives in one place.

const START_SCENE_PATH := "res://scenes/Start.tscn"
const VIEW_W := 1280
const VIEW_H := 720
const STACK_W := 620.0

const C_BG_TOP    := Color(0.06, 0.03, 0.08, 1.0)
const C_BG_BOT    := Color(0.02, 0.01, 0.04, 1.0)
const C_TITLE     := Color(0.92, 0.18, 0.16, 1.0)
const C_TITLE_GLO := Color(0.55, 0.05, 0.08, 1.0)
const C_SUBTITLE  := Color(0.72, 0.66, 0.55, 1.0)
const C_PANEL_BG  := Color(0.08, 0.04, 0.06, 0.95)
const C_PANEL_BD  := Color(0.65, 0.12, 0.10, 1.0)
const C_WARN_HEAD := Color(1.00, 0.82, 0.30, 1.0)
const C_WARN_BODY := Color(0.95, 0.90, 0.85, 1.0)
const C_BTN_BG    := Color(0.10, 0.05, 0.07, 0.95)
const C_BTN_BD    := Color(0.55, 0.18, 0.16, 1.0)
const C_BTN_HOVER := Color(0.18, 0.07, 0.09, 1.0)
const C_BTN_TEXT  := Color(0.96, 0.86, 0.55, 1.0)

var _title_label: Label = null
var _t: float = 0.0


func _ready() -> void:
	layer = 100
	_build()
	set_process(true)


func _process(delta: float) -> void:
	# Slow breathing pulse on the title — gentle red/dark cycle for atmosphere.
	_t += delta
	if _title_label:
		var pulse: float = 0.85 + 0.15 * sin(_t * 1.6)
		_title_label.add_theme_color_override(
			"font_color",
			Color(C_TITLE.r * pulse, C_TITLE.g * pulse * 0.6, C_TITLE.b * pulse * 0.6, 1.0)
		)


# ── UI build ─────────────────────────────────────────────────────────────────

func _build() -> void:
	# Backdrop: solid base color filling the whole viewport.
	var bg := ColorRect.new()
	bg.position = Vector2.ZERO
	bg.size = Vector2(VIEW_W, VIEW_H)
	bg.color = C_BG_BOT
	add_child(bg)

	# Top half: slightly lighter to suggest a subtle gradient.
	var bg_top := ColorRect.new()
	bg_top.position = Vector2.ZERO
	bg_top.size = Vector2(VIEW_W, VIEW_H * 0.55)
	bg_top.color = C_BG_TOP
	bg_top.modulate.a = 0.85
	add_child(bg_top)

	# Edge vignette — 4 thin rects darkening the borders.
	var border := 60
	for spec in [
		[Vector2.ZERO, Vector2(VIEW_W, border)],                                  # top
		[Vector2(0, VIEW_H - border), Vector2(VIEW_W, border)],                   # bottom
		[Vector2.ZERO, Vector2(border, VIEW_H)],                                  # left
		[Vector2(VIEW_W - border, 0), Vector2(border, VIEW_H)],                   # right
	]:
		var v := ColorRect.new()
		v.position = spec[0]
		v.size = spec[1]
		v.color = Color(0, 0, 0, 0.35)
		add_child(v)

	# Vertical content stack — centered horizontally, near top of vertical center.
	var stack := VBoxContainer.new()
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 22)
	stack.position = Vector2((VIEW_W - STACK_W) * 0.5, 80)
	stack.size = Vector2(STACK_W, VIEW_H - 160)
	stack.custom_minimum_size = Vector2(STACK_W, 0)
	add_child(stack)

	_title_label = _label("ABERRANT", 72, C_TITLE)
	_title_label.add_theme_color_override("font_shadow_color", C_TITLE_GLO)
	_title_label.add_theme_constant_override("shadow_offset_x", 0)
	_title_label.add_theme_constant_override("shadow_offset_y", 4)
	_title_label.add_theme_constant_override("shadow_outline_size", 6)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(_title_label)

	var subtitle := _label("A Slime Anomaly  ·  Game Jam CSUI 2026", 16, C_SUBTITLE)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(subtitle)

	stack.add_child(_spacer(8))
	stack.add_child(_build_disclaimer())
	stack.add_child(_spacer(4))
	stack.add_child(_build_buttons())


func _build_disclaimer() -> Panel:
	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel", _make_panel_style(C_PANEL_BG, C_PANEL_BD, 2.0, 8.0))
	panel.custom_minimum_size = Vector2(STACK_W, 188)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var v := VBoxContainer.new()
	v.position = Vector2(20, 14)
	v.size = Vector2(STACK_W - 40, 160)
	v.custom_minimum_size = Vector2(STACK_W - 40, 0)
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)

	var head := _label("⚠  WARNING", 22, C_WARN_HEAD)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(head)

	var body := _label(
		"This game is brutally hard. You CANNOT attack directly — your only " +
		"weapon is the world itself. Pick things up. Throw them back. Time your " +
		"shield right when the boss telegraph ENDS to stun and double damage.\n\n" +
		"Expect to die. A lot.",
		14, C_WARN_BODY, true
	)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(body)

	return panel


func _build_buttons() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)

	var start_btn := _button("START GAME", 240)
	start_btn.pressed.connect(_on_start_pressed)
	row.add_child(start_btn)

	var quit_btn := _button("QUIT", 140)
	quit_btn.pressed.connect(_on_quit_pressed)
	row.add_child(quit_btn)

	return row


# ── Button callbacks ─────────────────────────────────────────────────────────

func _on_start_pressed() -> void:
	get_tree().change_scene_to_file(START_SCENE_PATH)


func _on_quit_pressed() -> void:
	get_tree().quit()


# ── Helpers ──────────────────────────────────────────────────────────────────

func _label(text: String, font_size: int, color: Color, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	# Fill parent container width so HORIZONTAL_ALIGNMENT_CENTER actually
	# centers the text horizontally rather than shrinking to text width.
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _spacer(h: float) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	return s


func _button(label_text: String, min_w: float) -> Button:
	var b := Button.new()
	b.text = label_text
	b.custom_minimum_size = Vector2(min_w, 56)
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_color_override("font_color", C_BTN_TEXT)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 0.85, 1.0))
	b.add_theme_color_override("font_pressed_color", Color(0.85, 0.50, 0.18, 1.0))
	b.add_theme_stylebox_override("normal",  _make_panel_style(C_BTN_BG, C_BTN_BD, 2.0, 6.0))
	b.add_theme_stylebox_override("hover",   _make_panel_style(C_BTN_HOVER, Color(1.0, 0.55, 0.25, 1.0), 2.0, 6.0))
	b.add_theme_stylebox_override("pressed", _make_panel_style(Color(0.05, 0.02, 0.03, 1.0), C_BTN_BD, 2.0, 6.0))
	b.add_theme_stylebox_override("focus",   _make_panel_style(Color(0, 0, 0, 0), Color(1.0, 0.85, 0.40, 1.0), 2.0, 6.0))
	return b


func _make_panel_style(bg: Color, border: Color, border_w: float, radius: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_left = int(border_w)
	s.border_width_top = int(border_w)
	s.border_width_right = int(border_w)
	s.border_width_bottom = int(border_w)
	s.corner_radius_top_left = int(radius)
	s.corner_radius_top_right = int(radius)
	s.corner_radius_bottom_left = int(radius)
	s.corner_radius_bottom_right = int(radius)
	s.shadow_color = Color(0, 0, 0, 0.5)
	s.shadow_size = 6
	return s
