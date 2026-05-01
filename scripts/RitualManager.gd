extends CanvasLayer
# Tracks the room's ritual books. Each completion triggers an on-screen
# notification with thematic flavor. When all rituals are done, calls
# `unleash()` on the first node in group "boss" so it stops being dormant.

@export var total_rituals: int = 3
@export var notification_messages: PackedStringArray = PackedStringArray([
	"Black ink bleeds from the page. Something deep below opens its eyes.",
	"The second incantation echoes. The ground throbs like a furious heart.",
	"The last seal shatters. The Warden rises — there is nowhere left to run."
])
@export var final_title: String = "RITUALS COMPLETE"
@export var final_subtitle: String = "The Warden approaches."

const PANEL_W := 720.0
const PANEL_H := 110.0
const MARGIN_BOTTOM := 110.0
const FADE_IN := 0.30
const HOLD := 3.0
const FADE_OUT := 0.70

const C_PANEL_BG  := Color(0.05, 0.02, 0.04, 0.92)
const C_PANEL_BD  := Color(0.70, 0.18, 0.05, 1.0)
const C_TITLE     := Color(1.00, 0.55, 0.15, 1.0)
const C_BODY      := Color(0.95, 0.88, 0.78, 1.0)

var _completed: int = 0
var _root: Control = null
var _bg: ColorRect = null
var _title_label: Label = null
var _body_label: Label = null
var _notif_tween: Tween = null


func _ready() -> void:
	layer = 8   # above kill counter (6) and boss HP (7)
	_build_ui()
	_root.modulate.a = 0.0
	# Wait one frame so all RitualBook _ready callbacks have run and added
	# themselves to the "ritual_book" group before we hook them up.
	await get_tree().process_frame
	_connect_books()


# ── UI ────────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var vp := Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height")
	)
	_root = Control.new()
	_root.position = Vector2((vp.x - PANEL_W) * 0.5, vp.y - PANEL_H - MARGIN_BOTTOM)
	_root.size = Vector2(PANEL_W, PANEL_H)
	add_child(_root)

	_bg = ColorRect.new()
	_bg.position = Vector2.ZERO
	_bg.size = Vector2(PANEL_W, PANEL_H)
	_bg.color = C_PANEL_BG
	_root.add_child(_bg)

	# Border (4 thin rects).
	for spec in [
		[Vector2(0, 0), Vector2(PANEL_W, 2)],
		[Vector2(0, PANEL_H - 2), Vector2(PANEL_W, 2)],
		[Vector2(0, 0), Vector2(2, PANEL_H)],
		[Vector2(PANEL_W - 2, 0), Vector2(2, PANEL_H)],
	]:
		var b := ColorRect.new()
		b.position = spec[0]
		b.size = spec[1]
		b.color = C_PANEL_BD
		_root.add_child(b)

	_title_label = Label.new()
	_title_label.position = Vector2(20, 12)
	_title_label.size = Vector2(PANEL_W - 40, 26)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 22)
	_title_label.add_theme_color_override("font_color", C_TITLE)
	_title_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_title_label.add_theme_constant_override("shadow_offset_x", 1)
	_title_label.add_theme_constant_override("shadow_offset_y", 1)
	_root.add_child(_title_label)

	_body_label = Label.new()
	_body_label.position = Vector2(28, 46)
	_body_label.size = Vector2(PANEL_W - 56, PANEL_H - 56)
	_body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.add_theme_font_size_override("font_size", 16)
	_body_label.add_theme_color_override("font_color", C_BODY)
	_body_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_body_label.add_theme_constant_override("shadow_offset_x", 1)
	_body_label.add_theme_constant_override("shadow_offset_y", 1)
	_root.add_child(_body_label)


# ── Wiring ────────────────────────────────────────────────────────────────────

func _connect_books() -> void:
	for book in get_tree().get_nodes_in_group("ritual_book"):
		if book.has_signal("ritual_completed"):
			book.ritual_completed.connect(_on_ritual_completed)


# ── Ritual completion ────────────────────────────────────────────────────────

func _on_ritual_completed(_book: Node) -> void:
	_completed += 1
	var idx: int = clampi(_completed - 1, 0, notification_messages.size() - 1)
	var title: String = "RITUAL %d / %d" % [_completed, total_rituals]
	var body: String = notification_messages[idx]
	_show_notification(title, body)
	if _completed >= total_rituals:
		# Brief delay so the final notification reads before the boss fight UI
		# (boss HP bar) pops in.
		await get_tree().create_timer(0.9).timeout
		_unleash_boss()


func _unleash_boss() -> void:
	for n in get_tree().get_nodes_in_group("boss"):
		if n.has_method("unleash"):
			n.unleash()
			return


# ── Notification show/hide ───────────────────────────────────────────────────

func _show_notification(title: String, body: String) -> void:
	_title_label.text = title
	_body_label.text = body
	if _notif_tween and _notif_tween.is_valid():
		_notif_tween.kill()
	_root.modulate.a = 0.0
	_notif_tween = create_tween()
	_notif_tween.tween_property(_root, "modulate:a", 1.0, FADE_IN)
	_notif_tween.tween_interval(HOLD)
	_notif_tween.tween_property(_root, "modulate:a", 0.0, FADE_OUT)
