extends CanvasLayer
# Top-center boss HP bar. Auto-binds the first node in the "boss" group at
# startup (or the next one to appear if none exists yet). Polls the boss's
# `hp` field each frame, hides itself when the boss dies or the reference
# becomes invalid. Drop one BossHealthUI.tscn in any boss room — no wiring
# required as long as the boss adds itself to the "boss" group.

@export var boss_label: String = "CORRUPTED GOLEM"

const MARGIN_TOP := 18.0
const PANEL_W    := 640.0
const PANEL_H    := 60.0
const BAR_H      := 18.0
const FONT_SZ    := 18

const C_BG       := Color(0.05, 0.02, 0.03, 0.92)
const C_BORDER   := Color(0.70, 0.05, 0.10, 1.0)
const C_BAR_BG   := Color(0.18, 0.04, 0.05, 0.95)
const C_BAR_FG   := Color(0.92, 0.10, 0.12, 1.0)
const C_BAR_LOW  := Color(1.00, 0.55, 0.15, 1.0)   # tint when HP < 40%
const C_TEXT     := Color(0.98, 0.88, 0.55, 1.0)

var _boss: Node = null
var _root: Control = null
var _label: Label = null
var _fill: ColorRect = null
var _max_hp: int = 1
var _cur_hp: int = 0


func _ready() -> void:
	layer = 7   # above KillCounter (6) and inventory (5)
	_build_ui()
	visible = false
	# Wait one frame so every boss's _ready (which adds them to the group)
	# has run before we scan.
	await get_tree().process_frame
	_bind_first_boss()
	get_tree().node_added.connect(_on_node_added)
	set_process(true)


func _build_ui() -> void:
	var vp := Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height")
	)
	_root = Control.new()
	_root.position = Vector2((vp.x - PANEL_W) * 0.5, MARGIN_TOP)
	_root.size = Vector2(PANEL_W, PANEL_H)
	add_child(_root)

	# Backdrop panel.
	var bg := ColorRect.new()
	bg.position = Vector2.ZERO
	bg.size = Vector2(PANEL_W, PANEL_H)
	bg.color = C_BG
	_root.add_child(bg)

	# Border (4 thin rects so we don't need a stylebox).
	for spec in [
		[Vector2(0, 0), Vector2(PANEL_W, 2)],
		[Vector2(0, PANEL_H - 2), Vector2(PANEL_W, 2)],
		[Vector2(0, 0), Vector2(2, PANEL_H)],
		[Vector2(PANEL_W - 2, 0), Vector2(2, PANEL_H)],
	]:
		var b := ColorRect.new()
		b.position = spec[0]
		b.size = spec[1]
		b.color = C_BORDER
		_root.add_child(b)

	# Boss name label (centered).
	_label = Label.new()
	_label.text = boss_label
	_label.position = Vector2(0, 6)
	_label.size = Vector2(PANEL_W, 22)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", FONT_SZ)
	_label.add_theme_color_override("font_color", C_TEXT)
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_root.add_child(_label)

	# HP bar background + fill.
	var bar_x := 14.0
	var bar_y := PANEL_H - BAR_H - 10.0
	var bar_w := PANEL_W - 28.0

	var bar_bg := ColorRect.new()
	bar_bg.position = Vector2(bar_x, bar_y)
	bar_bg.size = Vector2(bar_w, BAR_H)
	bar_bg.color = C_BAR_BG
	_root.add_child(bar_bg)

	_fill = ColorRect.new()
	_fill.position = Vector2(bar_x, bar_y)
	_fill.size = Vector2(bar_w, BAR_H)
	_fill.color = C_BAR_FG
	_root.add_child(_fill)


# ── Boss binding ──────────────────────────────────────────────────────────────

func _on_node_added(node: Node) -> void:
	# Only re-scan if we don't have a live boss already.
	if is_instance_valid(_boss):
		return
	if node.is_in_group("boss"):
		await get_tree().process_frame
		_bind_first_boss()


func _bind_first_boss() -> void:
	for n in get_tree().get_nodes_in_group("boss"):
		if not is_instance_valid(n):
			continue
		_boss = n
		_max_hp = int(n.get("max_hp")) if "max_hp" in n else 1
		_cur_hp = int(n.get("hp")) if "hp" in n else _max_hp
		_refresh()
		# Don't show the bar until the boss is actually visible (i.e. spawned).
		# A boss that's still locked or dormant shouldn't have its HP exposed —
		# the player only sees the bar when the encounter truly starts.
		visible = _boss_is_active(n)
		if n.has_signal("died"):
			n.died.connect(_on_boss_died)
		return
	visible = false


func _boss_is_active(b: Node) -> bool:
	# Spawned & not dead. Boss sets `visible = false` while locked/dormant and
	# flips it true at spawn_at(); state DEAD means the death sequence is
	# running and the bar should already be fading out via _on_boss_died.
	if not is_instance_valid(b):
		return false
	if "visible" in b and not b.visible:
		return false
	# State enum value 0 = DORMANT in CorruptedGolem.
	if "state" in b and int(b.state) == 0:
		return false
	return true


# ── Polling loop ──────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if not is_instance_valid(_boss):
		visible = false
		return
	# Reveal/hide based on live boss state — flips on the moment the boss
	# spawns (post-unleash), without needing to wire up an extra signal.
	var should_show: bool = _boss_is_active(_boss)
	if should_show != visible:
		visible = should_show
		if should_show:
			# Reset modulate in case the previous fight faded it out.
			_root.modulate.a = 1.0
	if not visible:
		return
	var new_hp: int = int(_boss.get("hp")) if "hp" in _boss else _cur_hp
	if new_hp != _cur_hp:
		_cur_hp = new_hp
		_refresh()


func _refresh() -> void:
	if _fill == null:
		return
	var bar_w: float = PANEL_W - 28.0
	var ratio: float = clampf(float(_cur_hp) / float(maxi(_max_hp, 1)), 0.0, 1.0)
	_fill.size.x = bar_w * ratio
	_fill.color = C_BAR_LOW if ratio < 0.4 else C_BAR_FG


func _on_boss_died() -> void:
	# Brief fade-out then hide so the death anim has its moment.
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func(): visible = false)
