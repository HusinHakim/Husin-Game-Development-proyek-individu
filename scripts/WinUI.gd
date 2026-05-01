extends CanvasLayer
# Victory overlay. Auto-binds to the first node in the "boss" group at scene
# load and waits for its `died` signal. When the boss dies, fades a black
# overlay in, reveals "VICTORY" + a flavor subtitle, then shows a "Back to
# Menu" button that returns the player to MainMenu.tscn.
#
# Mirrors the visual cadence of Player.gd's DeathUI sequence — slow overlay
# fade, then label fade, then UI input becomes available.

const MAIN_MENU_PATH := "res://scenes/MainMenu.tscn"

@export var victory_title: String = "VICTORY"
@export var victory_subtitle: String = "The Warden has fallen."
@export var overlay_fade_in: float = 2.5
@export var label_fade_in: float = 1.8
@export var subtitle_delay: float = 1.6
@export var button_delay: float = 2.6

const C_OVERLAY  := Color(0, 0, 0, 1)
const C_TITLE    := Color(1.0, 0.85, 0.40, 1.0)        # warm gold
const C_TITLE_SH := Color(0.25, 0.10, 0.02, 1.0)
const C_SUB      := Color(0.92, 0.86, 0.70, 1.0)
const C_BTN_BG   := Color(0.10, 0.06, 0.04, 0.95)
const C_BTN_BD   := Color(0.85, 0.65, 0.30, 1.0)
const C_BTN_HOV  := Color(0.20, 0.12, 0.08, 1.0)
const C_BTN_TXT  := Color(0.98, 0.86, 0.55, 1.0)

var _overlay: ColorRect = null
var _title: Label = null
var _subtitle: Label = null
var _button: Button = null
var _boss: Node = null
var _triggered: bool = false


func _ready() -> void:
	layer = 25   # above DeathUI(20) so it wins if both somehow fire
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	# Wait one frame so the boss's _ready (group registration) has run.
	await get_tree().process_frame
	_bind_boss()
	get_tree().node_added.connect(_on_node_added)


func _build_ui() -> void:
	var vp := Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height")
	)
	# Overlay (fades to fully black)
	_overlay = ColorRect.new()
	_overlay.position = Vector2.ZERO
	_overlay.size = vp
	_overlay.color = C_OVERLAY
	_overlay.modulate = Color(1, 1, 1, 0)
	_overlay.visible = false
	add_child(_overlay)

	# Title
	_title = Label.new()
	_title.text = victory_title
	_title.position = Vector2(vp.x * 0.5 - 250, vp.y * 0.5 - 80)
	_title.size = Vector2(500, 80)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 64)
	_title.add_theme_color_override("font_color", C_TITLE)
	_title.add_theme_color_override("font_shadow_color", C_TITLE_SH)
	_title.add_theme_constant_override("shadow_offset_x", 3)
	_title.add_theme_constant_override("shadow_offset_y", 3)
	_title.modulate = Color(1, 1, 1, 0)
	_title.visible = false
	add_child(_title)

	# Subtitle
	_subtitle = Label.new()
	_subtitle.text = victory_subtitle
	_subtitle.position = Vector2(vp.x * 0.5 - 250, vp.y * 0.5 + 8)
	_subtitle.size = Vector2(500, 30)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_subtitle.add_theme_font_size_override("font_size", 20)
	_subtitle.add_theme_color_override("font_color", C_SUB)
	_subtitle.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_subtitle.add_theme_constant_override("shadow_offset_x", 1)
	_subtitle.add_theme_constant_override("shadow_offset_y", 1)
	_subtitle.modulate = Color(1, 1, 1, 0)
	_subtitle.visible = false
	add_child(_subtitle)

	# Back-to-Menu button
	_button = Button.new()
	_button.text = "BACK TO MENU"
	_button.size = Vector2(280, 56)
	_button.position = Vector2(vp.x * 0.5 - 140, vp.y * 0.5 + 90)
	_button.add_theme_font_size_override("font_size", 18)
	_button.add_theme_color_override("font_color", C_BTN_TXT)
	_button.add_theme_color_override("font_hover_color", Color(1, 1, 0.85, 1))
	_button.add_theme_stylebox_override("normal",  _box(C_BTN_BG, C_BTN_BD))
	_button.add_theme_stylebox_override("hover",   _box(C_BTN_HOV, Color(1.0, 0.85, 0.45, 1)))
	_button.add_theme_stylebox_override("pressed", _box(Color(0.05, 0.03, 0.02, 1), C_BTN_BD))
	_button.modulate = Color(1, 1, 1, 0)
	_button.visible = false
	_button.disabled = true
	_button.pressed.connect(_on_back_to_menu)
	add_child(_button)


func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_left = 2
	s.border_width_top = 2
	s.border_width_right = 2
	s.border_width_bottom = 2
	s.corner_radius_top_left = 6
	s.corner_radius_top_right = 6
	s.corner_radius_bottom_left = 6
	s.corner_radius_bottom_right = 6
	return s


# ── Boss binding ─────────────────────────────────────────────────────────────

func _bind_boss() -> void:
	for n in get_tree().get_nodes_in_group("boss"):
		if not is_instance_valid(n):
			continue
		_boss = n
		if n.has_signal("died"):
			n.died.connect(_on_boss_died)
		return


func _on_node_added(node: Node) -> void:
	if is_instance_valid(_boss):
		return
	if node.is_in_group("boss"):
		await get_tree().process_frame
		_bind_boss()


# ── Sequence ─────────────────────────────────────────────────────────────────

func _on_boss_died() -> void:
	if _triggered:
		return
	_triggered = true
	_play_victory_sequence()


func _play_victory_sequence() -> void:
	_overlay.visible = true
	_title.visible = true
	_subtitle.visible = true

	# Overlay fades in slowly. Title eases in slightly behind it.
	var tw := create_tween()
	tw.tween_property(_overlay, "modulate:a", 1.0, overlay_fade_in).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

	var tw2 := create_tween()
	tw2.tween_interval(0.8)
	tw2.tween_property(_title, "modulate:a", 1.0, label_fade_in).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	var tw3 := create_tween()
	tw3.tween_interval(subtitle_delay)
	tw3.tween_property(_subtitle, "modulate:a", 1.0, label_fade_in).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# Reveal the button after the dramatic beat. Disabled until then so the
	# player can't accidentally click before it's visible.
	var tw4 := create_tween()
	tw4.tween_interval(button_delay)
	tw4.tween_callback(func(): _button.visible = true; _button.disabled = false)
	tw4.tween_property(_button, "modulate:a", 1.0, 0.6).set_ease(Tween.EASE_OUT)


func _on_back_to_menu() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_PATH)
