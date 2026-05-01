extends Node
# Spawns random throwable items in the boss arena while the boss is alive.
# Activates when the boss first becomes non-DORMANT (i.e. has actually
# spawned post-unleash). Caps simultaneous item count so the floor doesn't
# get flooded with pickups, and keeps fresh items dripping in via a timer.
#
# Defaults: CrystalBuckler / IronChain / Stalagmite — matching the player's
# tool kit (shield / chain entangle / stalagmite ranged).

@export var item_scene_paths: PackedStringArray = PackedStringArray([
	"res://scenes/CrystalBuckler.tscn",
	"res://scenes/IronChain.tscn",
	"res://scenes/Stalagmite.tscn"
])
# Pick weights parallel to item_scene_paths. Shield (CrystalBuckler) drop
# rate raised — player needs reliable parry tools for the boss windups.
@export var item_weights: PackedFloat32Array = PackedFloat32Array([
	0.35,   # CrystalBuckler — uncommon (was 0.15, bumped for boss room)
	0.35,   # IronChain — common
	0.30,   # Stalagmite — common
])
@export var spawn_zone_min: Vector2 = Vector2(-700, -300)
@export var spawn_zone_max: Vector2 = Vector2(700, 350)
# Optional CollisionPolygon2D defining the valid spawn area. When set, every
# candidate position is point-in-polygon tested against this shape so items
# never spawn outside the playable arena. The polygon's points are read in
# the polygon's parent's local coordinate space — must share parent (or
# matching transform) with this spawner for the test to be in the same
# coordinate system.
@export var play_area_polygon_path: NodePath = NodePath("")
@export var max_active: int = 7              # hard cap on items this spawner has produced
@export var spawn_interval: float = 1.4      # seconds between attempts (lower = faster drops)
@export var initial_burst: int = 5           # spawn this many at the moment boss activates
@export var min_distance_from_player: float = 90.0
@export var min_distance_from_other: float = 100.0
@export var max_attempts: int = 25

const STATE_DORMANT := 0
const STATE_DEAD := 11   # CorruptedGolem.State.DEAD index — see enum order

var _scenes: Array[PackedScene] = []
var _spawned: Array = []
var _active: bool = false
var _timer: float = 0.0
var _boss: Node = null
var _polygon_points: PackedVector2Array = PackedVector2Array()
var _polygon_offset: Vector2 = Vector2.ZERO   # poly_parent.global_pos - our_parent.global_pos


func _ready() -> void:
	for p in item_scene_paths:
		var s := load(p)
		if s is PackedScene:
			_scenes.append(s)
	# Polygon binding waits one frame so the scene's other nodes finish _ready.
	call_deferred("_bind_polygon")
	set_process(true)


func _bind_polygon() -> void:
	if play_area_polygon_path.is_empty():
		return
	var node := get_node_or_null(play_area_polygon_path)
	if node == null or not ("polygon" in node):
		push_warning("[BossItemSpawner] play_area_polygon_path doesn't resolve to a CollisionPolygon2D — falling back to rectangular spawn zone.")
		return
	_polygon_points = node.polygon
	# Compute coordinate-space offset so we can test world-aligned candidates
	# regardless of where the polygon sits in the scene hierarchy.
	var our_parent := get_parent()
	var poly_parent := node.get_parent()
	var our_world: Vector2 = (our_parent as Node2D).global_position if our_parent is Node2D else Vector2.ZERO
	var poly_world: Vector2 = (poly_parent as Node2D).global_position if poly_parent is Node2D else Vector2.ZERO
	_polygon_offset = poly_world - our_world


func _process(delta: float) -> void:
	# Late-bind the boss in case the scene order had us _ready first.
	if not is_instance_valid(_boss):
		_boss = _find_boss()
		if _boss == null:
			return

	if not _active:
		if _boss_is_active():
			_active = true
			_do_initial_burst()
		return

	# Stop spawning once the boss starts dying (state DEAD) — items in play
	# stay so the player can finish the fight if hp == 0 mid-throw.
	if "state" in _boss and int(_boss.state) == STATE_DEAD:
		set_process(false)
		return

	# Drop any items that were freed (picked up + non-respawning, or thrown
	# into walls and queue_freed) before checking the cap.
	_spawned = _spawned.filter(func(it): return is_instance_valid(it))

	_timer -= delta
	if _timer <= 0.0:
		_timer = spawn_interval
		if _spawned.size() < max_active:
			_spawn_one()


func _boss_is_active() -> bool:
	if not is_instance_valid(_boss):
		return false
	if "visible" in _boss and not _boss.visible:
		return false
	if "state" in _boss and int(_boss.state) == STATE_DORMANT:
		return false
	return true


func _find_boss() -> Node:
	var bosses := get_tree().get_nodes_in_group("boss")
	return bosses[0] if not bosses.is_empty() else null


func _do_initial_burst() -> void:
	for i in range(initial_burst):
		_spawn_one()


# ── Spawning ──────────────────────────────────────────────────────────────────

func _spawn_one() -> void:
	if _scenes.is_empty():
		return
	var idx: int = _pick_weighted_index()
	var scene: PackedScene = _scenes[idx]
	var local_pos: Vector2 = _pick_position()
	var parent := get_parent()
	if not is_instance_valid(parent):
		return
	var inst: Node = scene.instantiate()
	parent.add_child(inst)
	if inst is Node2D:
		(inst as Node2D).position = local_pos
		# ThrowableItem reads _spawn_pos for its respawn point — overwrite so
		# items respawn where they were dropped, not at scene origin.
		if "_spawn_pos" in inst:
			inst._spawn_pos = (inst as Node2D).global_position
	_spawned.append(inst)


func _pick_weighted_index() -> int:
	# If weights are missing or shorter than scenes, fall back to uniform.
	if item_weights.size() < _scenes.size():
		return randi() % _scenes.size()
	var total: float = 0.0
	for i in range(_scenes.size()):
		total += maxf(item_weights[i], 0.0)
	if total <= 0.0:
		return randi() % _scenes.size()
	var roll: float = randf() * total
	var acc: float = 0.0
	for i in range(_scenes.size()):
		acc += maxf(item_weights[i], 0.0)
		if roll <= acc:
			return i
	return _scenes.size() - 1


func _pick_position() -> Vector2:
	# Sample N candidates; prefer one that's far from the player AND any
	# already-placed item. Falls back to the candidate with the best worst-
	# case distance if no slot meets the strict thresholds.
	var player := get_tree().get_first_node_in_group("player")
	var player_world: Vector2 = Vector2.ZERO
	if is_instance_valid(player) and player is Node2D:
		player_world = (player as Node2D).global_position
	var origin: Vector2 = Vector2.ZERO
	if get_parent() is Node2D:
		origin = (get_parent() as Node2D).global_position

	var best: Vector2 = _random_local()
	var best_in_poly: bool = _is_in_play_area(best)
	var best_score: float = -1.0
	for _i in range(max_attempts):
		var local := _random_local()
		# REJECT immediately if outside the configured polygon. Other checks
		# (player distance, item spacing) only matter for valid candidates.
		if not _is_in_play_area(local):
			continue
		var world := origin + local
		var d_player: float = INF
		if is_instance_valid(player):
			d_player = world.distance_to(player_world)
		if d_player < min_distance_from_player:
			continue
		var d_other: float = INF
		for it in _spawned:
			if not is_instance_valid(it) or not (it is Node2D):
				continue
			d_other = minf(d_other, world.distance_to((it as Node2D).global_position))
		if d_other >= min_distance_from_other:
			return local
		var score: float = minf(d_player, d_other)
		# Prefer in-polygon candidates when picking the fallback.
		if not best_in_poly or score > best_score:
			best_score = score
			best = local
			best_in_poly = true
	return best


func _is_in_play_area(local: Vector2) -> bool:
	# No polygon configured → unrestricted (use rectangular zone only).
	if _polygon_points.is_empty():
		return true
	# Translate candidate from our parent's local frame into the polygon's
	# parent's local frame (where the polygon points live).
	var in_poly_frame: Vector2 = local - _polygon_offset
	return Geometry2D.is_point_in_polygon(in_poly_frame, _polygon_points)


func _random_local() -> Vector2:
	return Vector2(
		randf_range(spawn_zone_min.x, spawn_zone_max.x),
		randf_range(spawn_zone_min.y, spawn_zone_max.y)
	)
