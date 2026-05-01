extends CanvasLayer

# Top-center HUD showing how many enemies have been killed in this room.
# Scans all nodes in the "enemy" group at startup, sums (1 + respawn_count)
# for each, and connects to their `died` signal to increment the counter.
# Also listens to `node_added` so enemies spawned later (e.g. boss
# replacements via BossSpawner) get tracked too.

@export var label_prefix: String = "Cults Killed"   # override per room
@export var max_kills_override: int = 0             # if > 0, used instead of auto-count

const MARGIN_TOP := 14.0
const PANEL_W    := 260.0
const PANEL_H    := 52.0
const FONT_SZ    := 22

const C_BG          := Color(0.10, 0.07, 0.06, 0.90)
const C_BORDER      := Color(0.65, 0.18, 0.12, 1.00)
const C_TEXT        := Color(0.96, 0.86, 0.55, 1.00)
const C_TEXT_DONE   := Color(0.55, 0.95, 0.55, 1.00)

var _kills: int = 0
var _max_kills: int = 0
var _label: Label = null


func _ready() -> void:
	layer = 6  # above inventory (5) but below death overlay (20)
	_build_ui()
	# Wait one frame so every enemy's _ready (which adds them to the group)
	# has run before we count.
	await get_tree().process_frame
	_setup_tracking()
	get_tree().node_added.connect(_on_node_added)


func _build_ui() -> void:
	var vp := Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height")
	)

	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel", _make_style())
	panel.position = Vector2((vp.x - PANEL_W) * 0.5, MARGIN_TOP)
	panel.size = Vector2(PANEL_W, PANEL_H)
	add_child(panel)

	_label = Label.new()
	_label.size = Vector2(PANEL_W, PANEL_H)
	_label.position = Vector2.ZERO
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", FONT_SZ)
	_label.add_theme_color_override("font_color", C_TEXT)
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("shadow_offset_x", 2)
	_label.add_theme_constant_override("shadow_offset_y", 2)
	_label.text = "%s  0 / 0" % label_prefix
	panel.add_child(_label)


func _setup_tracking() -> void:
	if max_kills_override > 0:
		_max_kills = max_kills_override
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if max_kills_override <= 0:
			# Not every enemy type exposes `respawn_count` (e.g. RockBoss has none).
			var rc: int = 0
			if "respawn_count" in enemy:
				rc = int(enemy.respawn_count)
			_max_kills += 1 + rc
		_hook_enemy(enemy)
	_update_label()


func _hook_enemy(enemy: Node) -> void:
	if enemy.has_signal("died") and not enemy.died.is_connected(_on_enemy_died):
		enemy.died.connect(_on_enemy_died)


func _on_node_added(node: Node) -> void:
	# Enemies (e.g. boss replacements) spawned after _setup_tracking should
	# also be hooked. Wait one frame so the new node's _ready can register
	# its group membership before we test.
	await get_tree().process_frame
	if not is_instance_valid(node):
		return
	if node.is_in_group("enemy"):
		_hook_enemy(node)


func _on_enemy_died() -> void:
	_kills += 1
	_update_label()


func _update_label() -> void:
	_label.text = "%s  %d / %d" % [label_prefix, _kills, _max_kills]
	if _max_kills > 0 and _kills >= _max_kills:
		_label.add_theme_color_override("font_color", C_TEXT_DONE)


func _make_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = C_BG
	s.border_color = C_BORDER
	s.border_width_left   = 2
	s.border_width_top    = 2
	s.border_width_right  = 2
	s.border_width_bottom = 2
	s.corner_radius_top_left     = 8
	s.corner_radius_top_right    = 8
	s.corner_radius_bottom_left  = 8
	s.corner_radius_bottom_right = 8
	s.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	s.shadow_size = 4
	return s
