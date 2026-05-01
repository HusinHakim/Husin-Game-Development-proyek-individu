class_name ThrowableItem
extends Area2D

@export var item_id: String = "item"
@export var item_display_name: String = "Item"
@export var item_icon: Texture2D = null
@export var damage: int = 10
@export var throw_speed: float = 500.0
@export var max_range: float = 380.0
@export var respawn_delay: float = 3.0
@export var respawn_scene: PackedScene = null  # subclass should set this in _ready
@export var drop_pickup_cooldown: float = 0.6  # delay before a manually-dropped item can be re-picked up
var destroy_on_hit: bool = false
var can_throw: bool = true       # subclass may set false (e.g. shield items)
var should_respawn: bool = true  # loot drops (e.g. Stalagmite) set false so pickup doesn't spawn copies forever

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D

enum ItemState { GROUND, HELD, FLYING }
var item_state: ItemState = ItemState.GROUND

var _velocity: Vector2 = Vector2.ZERO
var _distance_traveled: float = 0.0
var _ground_rotation: float = 0.0
var _spawn_pos: Vector2 = Vector2.ZERO
var _spawn_scale: Vector2 = Vector2.ONE
var _pickup_blocked: bool = false   # true during drop cooldown — blocks re-pickup by player overlap


func _ready() -> void:
	add_to_group("throwable_item")
	_ground_rotation = randf_range(-0.35, 0.35)
	rotation = _ground_rotation
	_spawn_pos = global_position
	_spawn_scale = scale
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	if item_state != ItemState.FLYING:
		return
	global_position += _velocity * delta
	_distance_traveled += _velocity.length() * delta
	rotation += delta * 7.0
	# Hit detection: prefer Area2D body_entered, but body_entered/get_overlapping_bodies
	# can silently miss in edge cases (timing after monitoring=true, scaled Area2D,
	# CharacterBody2D physics sync). So we also do a hard distance check against
	# every node in group "enemy" using their `hit_radius` property.
	for body in get_overlapping_bodies():
		if not is_instance_valid(body):
			continue
		if body.is_in_group("enemy"):
			print("[Throw:%s] tick HIT %s" % [item_id, body.name])
			_hit_enemy(body)
			return
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy) or not (enemy is Node2D):
			continue
		var r: float = 32.0
		if "hit_radius" in enemy:
			r = enemy.hit_radius
		if r <= 0.0:
			continue
		if global_position.distance_to((enemy as Node2D).global_position) <= r:
			print("[Throw:%s] distance HIT %s" % [item_id, enemy.name])
			_hit_enemy(enemy)
			return
	if _distance_traveled >= max_range:
		# Miss: destroy_on_hit items vanish (respawn already scheduled at pickup),
		# others land on the ground where they ran out of range.
		if destroy_on_hit:
			queue_free()
		else:
			_land()


func _hit_enemy(enemy: Node) -> void:
	apply_effect_to(enemy)
	if destroy_on_hit:
		queue_free()
	else:
		_land()


func _on_body_entered(body: Node) -> void:
	print("[Throw:%s] body_entered=%s groups=%s state=%d" % [
		item_id, body.name, str(body.get_groups()), item_state
	])
	match item_state:
		ItemState.GROUND:
			if body.is_in_group("player") and not _pickup_blocked:
				body.try_pickup_item(self)
		ItemState.FLYING:
			if body.is_in_group("enemy"):
				print("  -> HIT ", body.name, " for ", damage, " dmg")
				_hit_enemy(body)


func on_pickup() -> void:
	item_state = ItemState.HELD
	visible = false
	collision.disabled = true
	monitoring = false
	set_process(false)
	if should_respawn:
		_schedule_respawn()


func throw_toward(origin: Vector2, target_pos: Vector2) -> void:
	item_state = ItemState.FLYING
	global_position = origin
	visible = true
	collision.disabled = false
	monitoring = true
	set_process(true)
	_velocity = (target_pos - origin).normalized() * throw_speed
	_distance_traveled = 0.0
	print("[Throw:%s] thrown origin=%s target=%s velocity=%s" % [
		item_id, str(origin), str(target_pos), str(_velocity)
	])
	# If the player threw from INSIDE an enemy's body collision, body_entered
	# never fires (signal only triggers on transition into the area). Resolve
	# by manually checking overlap on the next physics frame and applying the
	# hit immediately.
	_resolve_initial_overlap()


func _resolve_initial_overlap() -> void:
	await get_tree().physics_frame
	if not is_instance_valid(self) or item_state != ItemState.FLYING:
		return
	var bodies = get_overlapping_bodies()
	print("[Throw:%s] resolve_initial_overlap bodies=%s" % [item_id, str(bodies)])
	for body in bodies:
		if body.is_in_group("enemy"):
			print("  -> initial overlap HIT ", body.name, " for ", damage, " dmg")
			_hit_enemy(body)
			return


func drop_at(pos: Vector2) -> void:
	item_state = ItemState.GROUND
	global_position = pos
	_velocity = Vector2.ZERO
	visible = true
	collision.disabled = false
	monitoring = true
	set_process(false)
	rotation = randf_range(-0.35, 0.35)
	_start_pickup_cooldown()


func _start_pickup_cooldown() -> void:
	# Block re-pickup by the dropping player for a short window. Without this
	# the item is dropped at the player's feet -> body_entered fires next
	# frame -> instantly back in inventory.
	if drop_pickup_cooldown <= 0.0:
		return
	_pickup_blocked = true
	# Subtle visual cue: dim the item while it's not yet pickable.
	modulate = Color(1, 1, 1, 0.55)
	var t := get_tree().create_timer(drop_pickup_cooldown)
	t.timeout.connect(func() -> void:
		if not is_instance_valid(self):
			return
		_pickup_blocked = false
		modulate = Color.WHITE
	)


func apply_effect_to(enemy: Node) -> void:
	if enemy.has_method("take_damage"):
		enemy.take_damage(damage)


func _land() -> void:
	item_state = ItemState.GROUND
	_velocity = Vector2.ZERO
	collision.disabled = false
	monitoring = true
	set_process(false)
	rotation = randf_range(-0.35, 0.35)


func _schedule_respawn() -> void:
	# Spawns a fresh copy of this item's scene at the original pickup point
	# after `respawn_delay` seconds. Timer is parented to the room so the
	# respawn fires even if this node is queue_freed (thrown & destroyed).
	var packed: PackedScene = respawn_scene
	if packed == null:
		# Fallback to scene_file_path if subclass forgot to set respawn_scene
		var path := scene_file_path
		if path.is_empty():
			push_warning("ThrowableItem '%s' cannot respawn — set respawn_scene in subclass _ready() or place node as a scene instance" % item_display_name)
			return
		packed = load(path) as PackedScene
		if packed == null:
			return

	var parent_ref := get_parent()
	if not is_instance_valid(parent_ref):
		return
	var pos := _spawn_pos
	var saved_scale := _spawn_scale

	var timer := Timer.new()
	timer.wait_time = respawn_delay
	timer.one_shot = true
	timer.autostart = true
	parent_ref.add_child(timer)

	timer.timeout.connect(func() -> void:
		if is_instance_valid(parent_ref):
			var new_item: ThrowableItem = packed.instantiate()
			parent_ref.add_child(new_item)
			# Apply original transform AFTER add_child so global coords are right.
			# Then propagate spawn data so chain can keep respawning at the
			# correct place + scale indefinitely (each new chain captures
			# `_spawn_pos`/`_spawn_scale` in its own _ready, but at that moment
			# position/scale haven't been set yet — so we override here).
			new_item.global_position = pos
			new_item.scale = saved_scale
			new_item._spawn_pos = pos
			new_item._spawn_scale = saved_scale
		timer.queue_free()
	)
