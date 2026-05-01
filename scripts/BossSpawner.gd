extends Node
# Boss respawn manager. Hooks into pre-placed bosses' `died` signal and
# spawns replacements at random positions far from the player until
# `total_to_spawn` is reached.
#
# Place this node as a sibling of the boss instances in a room.

@export var boss_scene: PackedScene
@export var death_drop_scene: PackedScene = null
@export var total_to_spawn: int = 3
@export var min_distance_from_player: float = 350.0
# Local-coordinate spawn zone (relative to spawner's parent).
@export var spawn_zone_min: Vector2 = Vector2(-560, -50)
@export var spawn_zone_max: Vector2 = Vector2(560, 110)

var _spawned_count: int = 0
var _player: Node2D = null
var _bosses_parent: Node = null


func _ready() -> void:
	_bosses_parent = get_parent()
	# Wait one frame so any pre-placed bosses run their _ready (and join the
	# "boss" group) before we count and connect.
	await get_tree().process_frame
	_player = get_tree().get_first_node_in_group("player")
	for boss in get_tree().get_nodes_in_group("boss"):
		if boss.get_parent() == _bosses_parent:
			_hook_boss(boss)
			_spawned_count += 1
	print("[BossSpawner] initial bosses hooked = %d / total=%d" % [_spawned_count, total_to_spawn])


func _hook_boss(boss: Node) -> void:
	if boss.has_signal("died"):
		boss.died.connect(_on_boss_died)


func _on_boss_died() -> void:
	# Defer one frame so we don't spawn during the dying boss's signal chain.
	await get_tree().process_frame
	if _spawned_count >= total_to_spawn:
		print("[BossSpawner] no replacement (cap reached %d/%d)" % [_spawned_count, total_to_spawn])
		return
	_spawn_one()


func _spawn_one() -> void:
	if boss_scene == null or not is_instance_valid(_bosses_parent):
		return
	var pos: Vector2 = _pick_spawn_position()
	var boss: Node2D = boss_scene.instantiate()
	if death_drop_scene and "death_drop_scene" in boss:
		boss.death_drop_scene = death_drop_scene
	_bosses_parent.add_child(boss)
	boss.position = pos
	_hook_boss(boss)
	_spawned_count += 1
	print("[BossSpawner] spawned replacement #%d at local %s" % [_spawned_count, str(pos)])


func _pick_spawn_position() -> Vector2:
	# Pick a position inside the spawn zone that is at least
	# `min_distance_from_player` away. Falls back to the farthest candidate
	# if no position satisfies the threshold.
	var player_local: Vector2 = Vector2.ZERO
	if is_instance_valid(_player) and is_instance_valid(_bosses_parent):
		player_local = (_bosses_parent as Node2D).to_local(_player.global_position)
	var best: Vector2 = Vector2.ZERO
	var best_dist: float = -1.0
	# First pass: try to satisfy min_distance.
	for _i in range(20):
		var p: Vector2 = Vector2(
			randf_range(spawn_zone_min.x, spawn_zone_max.x),
			randf_range(spawn_zone_min.y, spawn_zone_max.y)
		)
		var d: float = p.distance_to(player_local)
		if d >= min_distance_from_player and d > best_dist:
			best_dist = d
			best = p
	if best_dist > 0.0:
		return best
	# Fallback: pick the farthest of any candidate.
	for _i in range(10):
		var p: Vector2 = Vector2(
			randf_range(spawn_zone_min.x, spawn_zone_max.x),
			randf_range(spawn_zone_min.y, spawn_zone_max.y)
		)
		var d: float = p.distance_to(player_local)
		if d > best_dist:
			best_dist = d
			best = p
	return best
