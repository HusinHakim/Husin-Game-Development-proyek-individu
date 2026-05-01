extends Node
# ItemScatterer — randomizes sibling item positions on room load.
# Iterates Node2D siblings whose name starts with one of the configured
# prefixes and reassigns each a random position inside the spawn zone,
# keeping at least `min_distance` apart from already-placed items.
# `ThrowableItem._spawn_pos` is rewritten so respawns honor the new layout.
#
# Place this node as a sibling of the items it should scatter.

@export var spawn_zone_min: Vector2 = Vector2(-450, -60)
@export var spawn_zone_max: Vector2 = Vector2(450, 150)
@export var min_distance: float = 140.0
@export var max_attempts: int = 30
@export var name_prefixes: PackedStringArray = ["CrystalBuckler", "MagicRock"]


func _ready() -> void:
	# ThrowableItem captures _spawn_pos in its own _ready (= original scene
	# position). Wait one frame so we run AFTER, then move + overwrite.
	await get_tree().process_frame
	_scatter()


func _scatter() -> void:
	var parent: Node = get_parent()
	if not is_instance_valid(parent):
		return
	var targets: Array = []
	for child in parent.get_children():
		if not (child is Node2D):
			continue
		var nm: String = child.name
		for prefix in name_prefixes:
			if nm.begins_with(prefix):
				targets.append(child)
				break
	targets.shuffle()
	var placed: Array = []
	for item in targets:
		var pos: Vector2 = _pick_position(placed)
		(item as Node2D).position = pos
		if "_spawn_pos" in item:
			item._spawn_pos = (item as Node2D).global_position
		placed.append(pos)


func _pick_position(taken: Array) -> Vector2:
	# Try `max_attempts` random points; return the first that meets the
	# min-distance threshold. If none meet it (zone too crowded), fall back
	# to the candidate with the largest nearest-neighbor distance.
	var best: Vector2 = Vector2(
		randf_range(spawn_zone_min.x, spawn_zone_max.x),
		randf_range(spawn_zone_min.y, spawn_zone_max.y)
	)
	var best_min: float = -1.0
	for _i in range(max_attempts):
		var p := Vector2(
			randf_range(spawn_zone_min.x, spawn_zone_max.x),
			randf_range(spawn_zone_min.y, spawn_zone_max.y)
		)
		var nearest: float = INF
		for t in taken:
			nearest = minf(nearest, p.distance_to(t as Vector2))
		if nearest >= min_distance:
			return p
		if nearest > best_min:
			best_min = nearest
			best = p
	return best
