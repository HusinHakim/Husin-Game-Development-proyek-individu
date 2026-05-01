extends CharacterBody2D

@export var move_speed: float = 40.0
@export var max_hp: int = 5
@export var dash_speed: float = 400.0
@export var dash_duration: float = 0.18
@export var dash_cooldown: float = 0.8

@export var max_stamina: float = 100.0
@export var dash_stamina_cost: float = 25.0
@export var throw_stamina_cost: float = 15.0
@export var stamina_regen_per_sec: float = 60.0
@export var stamina_regen_delay: float = 0.5

@export var sprint_speed_mult: float = 1.8
@export var sprint_stamina_drain: float = 25.0   # stamina/sec while sprinting

@export var shield_duration: float = 1.6          # active parry window — long enough to catch boss windup reliably
@export var shield_stun_duration: float = 3.0     # how long an enemy stays stunned after deflect

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var health_ui: Node2D = $HealthUI/HeartsDisplay
@onready var stamina_ui: Node2D = $HealthUI/StaminaDisplay
@onready var overlay: ColorRect = $DeathUI/Overlay
@onready var you_died: Label = $DeathUI/YouDied

const MAX_INVENTORY: int = 5

var hp: int
var _dead: bool = false
var _dashing: bool = false
var _dash_timer: float = 0.0
var _dash_cooldown_timer: float = 0.0
var _dash_dir: Vector2 = Vector2.ZERO
var _invincible: bool = false
var _dash_requested: bool = false

var inventory: Array = []
var active_slot: int = 0
var _inventory_ui = null

var stamina: float
var _stamina_regen_block_t: float = 0.0
var _sprinting: bool = false

var _shield: Node2D = null   # active shield instance, null when none
var _aim_arrow: Node2D = null   # mouse-aim guideline shown when a throwable is in the active slot
var _dash_sfx: AudioStreamPlayer = null   # reused per-dash whoosh
var _throw_sfx: AudioStreamPlayer = null  # reused per-throw whoosh

var _damage_flash_tween: Tween = null
var _cam_shake_tween: Tween = null


func _ready() -> void:
	add_to_group("player")
	z_index = 30   # render above all decor/walls/items; effects (shield/slash z=50) still draw on top
	hp = max_hp
	health_ui.set_hp(hp, max_hp)
	stamina = max_stamina
	if stamina_ui:
		stamina_ui.set_stamina(stamina, max_stamina)
	_inventory_ui = get_node_or_null("InventoryUI")
	if _inventory_ui:
		_inventory_ui.update_display(inventory, active_slot)
	_spawn_aim_arrow()
	_setup_dash_sfx()
	_setup_throw_sfx()
	_setup_pass_through_enemies()


func _spawn_aim_arrow() -> void:
	# Skip the aim arrow on the Start scene — it's a passive/menu-style
	# screen, not a combat room, so the global aim cue is just noise there.
	var current := get_tree().current_scene
	if current and current.scene_file_path == "res://scenes/Start.tscn":
		return
	var arrow_script: Script = load("res://scripts/AimArrow.gd")
	if arrow_script == null:
		return
	_aim_arrow = Node2D.new()
	_aim_arrow.set_script(arrow_script)
	_aim_arrow.name = "AimArrow"
	_aim_arrow.visible = false
	add_child(_aim_arrow)


func _consume_stamina(cost: float) -> bool:
	# Returns true if stamina was sufficient. Otherwise flashes UI and returns false.
	if stamina < cost:
		if stamina_ui:
			stamina_ui.flash()
		return false
	stamina -= cost
	_stamina_regen_block_t = stamina_regen_delay
	if stamina_ui:
		stamina_ui.set_stamina(stamina, max_stamina)
	return true


func _tick_stamina(delta: float) -> void:
	if _stamina_regen_block_t > 0.0:
		_stamina_regen_block_t -= delta
		return
	if stamina >= max_stamina:
		return
	stamina = minf(stamina + stamina_regen_per_sec * delta, max_stamina)
	if stamina_ui:
		stamina_ui.set_stamina(stamina, max_stamina)


func take_damage(amount: int, allow_shield_stun: bool = true) -> void:
	if _dead or _invincible:
		return
	# Shield up → no damage, regardless of source. The shield's brief active
	# window IS the parry, so timing it correctly should fully negate the
	# hit (boss melee, projectiles, AoE — anything routed through here).
	# Stun-on-block is opt-in per source: SWIPE allows stun (high-skill
	# parry payoff), SLAM does NOT (telegraph too obvious — would trivialize).
	if is_instance_valid(_shield):
		if _shield.has_signal("deflected"):
			_shield.emit_signal("deflected")
		if allow_shield_stun:
			_stun_nearby_attackers()
		return
	hp = maxi(hp - amount, 0)
	health_ui.set_hp(hp, max_hp)
	_apply_damage_feedback()
	if hp <= 0:
		_die()


func _stun_nearby_attackers() -> void:
	# Find any boss currently swinging within melee distance and stun it.
	# Scoping to "boss" group keeps regular cult enemies out — they don't
	# have apply_stun and aren't the parry targets anyway.
	for n in get_tree().get_nodes_in_group("boss"):
		if not is_instance_valid(n) or not n.has_method("apply_stun"):
			continue
		if n is Node2D:
			var d: float = (n as Node2D).global_position.distance_to(global_position)
			if d > 260.0:
				continue
		n.apply_stun(shield_stun_duration)
		return  # one boss is enough


func _apply_damage_feedback() -> void:
	# Multi-channel "ouch" feedback so the player feels the hit without
	# looking at the HP bar: bright-red sprite flash + camera shake +
	# brief red full-screen flash.
	_flash_sprite()
	_shake_camera()
	_flash_screen()


func _flash_sprite() -> void:
	if not is_instance_valid(animated_sprite):
		return
	if _damage_flash_tween and _damage_flash_tween.is_valid():
		_damage_flash_tween.kill()
	animated_sprite.modulate = Color.WHITE
	_damage_flash_tween = create_tween()
	_damage_flash_tween.tween_property(animated_sprite, "modulate", Color(2.0, 0.45, 0.45, 1.0), 0.05)
	_damage_flash_tween.tween_property(animated_sprite, "modulate", Color.WHITE, 0.20)


func _shake_camera() -> void:
	var cam: Camera2D = get_node_or_null("Camera2D")
	if not is_instance_valid(cam):
		return
	if _cam_shake_tween and _cam_shake_tween.is_valid():
		_cam_shake_tween.kill()
	var amp: float = 9.0
	_cam_shake_tween = create_tween()
	for i in range(6):
		var off := Vector2(randf_range(-amp, amp), randf_range(-amp, amp))
		_cam_shake_tween.tween_property(cam, "offset", off, 0.035)
		amp *= 0.65
	_cam_shake_tween.tween_property(cam, "offset", Vector2.ZERO, 0.05)


func _flash_screen() -> void:
	# Spawned dynamically so multiple hits stack into a deeper red without
	# fighting over a single shared overlay's alpha tween.
	var layer := CanvasLayer.new()
	layer.layer = 15            # above HealthUI/Inventory/Kill counter, below DeathUI(20)
	add_child(layer)
	var rect := ColorRect.new()
	rect.color = Color(0.85, 0.05, 0.05, 0.0)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)
	var tw := create_tween()
	tw.tween_property(rect, "color:a", 0.30, 0.05)
	tw.tween_property(rect, "color:a", 0.0, 0.30)
	tw.tween_callback(layer.queue_free)


func heal(amount: int) -> void:
	if _dead:
		return
	hp = mini(hp + amount, max_hp)
	health_ui.set_hp(hp, max_hp)


func _die() -> void:
	_dead = true
	set_physics_process(false)
	_play_death_sequence()


func _play_death_sequence() -> void:
	overlay.visible = true
	you_died.visible = true

	var tween := create_tween()
	tween.set_parallel(false)
	tween.tween_property(overlay, "modulate:a", 1.0, 2.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

	var tween2 := create_tween()
	tween2.tween_interval(0.8)
	tween2.tween_property(you_died, "modulate:a", 1.0, 1.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	await tween.finished
	await get_tree().create_timer(1.5).timeout
	# Respawn at the Start scene (full reset to the beginning of the run)
	# instead of reloading the current room.
	get_tree().change_scene_to_file("res://scenes/Start.tscn")


# ── Inventory ────────────────────────────────────────────────────────────────

func try_pickup_item(item: ThrowableItem) -> void:
	if inventory.size() >= MAX_INVENTORY:
		return
	inventory.append(item)
	item.on_pickup()
	_update_inventory_ui()


func _throw_item() -> void:
	if inventory.is_empty():
		return
	var idx := mini(active_slot, inventory.size() - 1)
	var item: ThrowableItem = inventory[idx]
	if "can_throw" in item and not item.can_throw:
		return
	if not _consume_stamina(throw_stamina_cost):
		return
	inventory.remove_at(idx)
	active_slot = mini(active_slot, maxi(inventory.size() - 1, 0))
	item.throw_toward(global_position, get_global_mouse_position())
	_play_throw_sfx()
	_update_inventory_ui()


func _try_deflect() -> void:
	# Already an active shield? Ignore (player must wait it out / for it to deflect).
	if is_instance_valid(_shield):
		return
	# Need a Crystal Buckler in inventory.
	var buck_idx: int = _find_item_index("crystal_buckler")
	if buck_idx < 0:
		return
	# Consume buckler.
	var item: ThrowableItem = inventory[buck_idx]
	inventory.remove_at(buck_idx)
	if active_slot >= inventory.size():
		active_slot = maxi(inventory.size() - 1, 0)
	item.queue_free()
	_update_inventory_ui()
	# Spawn shield as a child of the player.
	var scene: PackedScene = load("res://scenes/ShieldVisual.tscn")
	if scene == null:
		return
	_shield = scene.instantiate()
	_shield.duration = shield_duration
	_shield.stun_duration = shield_stun_duration
	add_child(_shield)
	_update_shield_rotation()


func _update_shield_rotation() -> void:
	if not is_instance_valid(_shield):
		return
	var to_mouse: Vector2 = get_global_mouse_position() - global_position
	if to_mouse.length_squared() > 4.0:
		_shield.rotation = to_mouse.angle()


func _update_aim_arrow() -> void:
	if not is_instance_valid(_aim_arrow):
		return
	# Always show the aim guideline as a global directional indicator. Hide only
	# when the player is dead (no input) or while a shield is up (the shield's
	# own visual already communicates direction — double cue clutters).
	var visible_now: bool = not _dead and not is_instance_valid(_shield)
	_aim_arrow.visible = visible_now
	if not visible_now:
		return
	var to_mouse: Vector2 = get_global_mouse_position() - global_position
	if to_mouse.length_squared() > 4.0:
		_aim_arrow.rotation = to_mouse.angle()


func _find_item_index(item_id: String) -> int:
	for i in range(inventory.size()):
		var it = inventory[i]
		if it != null and "item_id" in it and it.item_id == item_id:
			return i
	return -1


func _drop_item() -> void:
	if inventory.is_empty():
		return
	var idx := mini(active_slot, inventory.size() - 1)
	var item: ThrowableItem = inventory[idx]
	inventory.remove_at(idx)
	active_slot = mini(active_slot, maxi(inventory.size() - 1, 0))
	var offset := Vector2(randf_range(-24.0, 24.0), randf_range(-24.0, 24.0))
	item.drop_at(global_position + offset)
	_update_inventory_ui()


func _set_active_slot(slot: int) -> void:
	active_slot = clampi(slot, 0, MAX_INVENTORY - 1)
	_update_inventory_ui()


func _cycle_filled_slot(direction: int) -> void:
	# Scroll-wheel cycling — skips empty slots and wraps around. If the
	# inventory is empty, leaves active_slot alone.
	var n: int = inventory.size()
	if n <= 0:
		return
	var start: int = mini(active_slot, n - 1)
	active_slot = ((start + direction) % n + n) % n
	_update_inventory_ui()


func _update_inventory_ui() -> void:
	if _inventory_ui:
		_inventory_ui.update_display(inventory, active_slot)


# ── Input ─────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if _dead:
		return

	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_throw_item()
			MOUSE_BUTTON_RIGHT:
				_try_deflect()
			MOUSE_BUTTON_WHEEL_UP:
				_cycle_filled_slot(-1)
			MOUSE_BUTTON_WHEEL_DOWN:
				_cycle_filled_slot(1)

	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_SHIFT:
				_dash_requested = true
			KEY_G:
				_drop_item()
			KEY_1:
				_set_active_slot(0)
			KEY_2:
				_set_active_slot(1)
			KEY_3:
				_set_active_slot(2)
			KEY_4:
				_set_active_slot(3)
			KEY_5:
				_set_active_slot(4)


# ── Movement ──────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	_tick_stamina(delta)
	_update_shield_rotation()
	_update_aim_arrow()

	if _dash_cooldown_timer > 0.0:
		_dash_cooldown_timer -= delta

	if _dashing:
		_dash_timer -= delta
		velocity = _dash_dir * dash_speed
		if _dash_timer <= 0.0:
			_dashing = false
			_invincible = false
			animated_sprite.modulate.a = 1.0
		else:
			animated_sprite.modulate.a = 0.5 + sin(_dash_timer * 60.0) * 0.4
		move_and_slide()
		_dash_requested = false
		return

	if _dash_requested and _dash_cooldown_timer <= 0.0:
		_dash_requested = false
		var dir := _wasd_direction()
		if dir == Vector2.ZERO:
			dir = _facing_direction()
		if dir != Vector2.ZERO:
			if _consume_stamina(dash_stamina_cost):
				_start_dash(dir)
				return
	_dash_requested = false

	_handle_movement(delta)
	_update_animation()
	move_and_slide()


func _start_dash(dir: Vector2) -> void:
	_dashing = true
	_invincible = true
	_dash_dir = dir.normalized()
	_dash_timer = dash_duration
	_dash_cooldown_timer = dash_cooldown
	if is_instance_valid(_dash_sfx):
		# Slight pitch jitter so back-to-back dashes don't sound robotic.
		_dash_sfx.pitch_scale = randf_range(0.92, 1.08)
		_dash_sfx.play()


func _setup_pass_through_enemies() -> void:
	# Make every enemy ignore the player's body during physics. Without this,
	# enemies (mask=1) would still see the player (layer=1) even though the
	# player's mask doesn't see them — which means enemies stop / get stuck
	# on the player's body. Adding the player as a collision exception on
	# each enemy keeps walls intact but lets the player walk freely through
	# any enemy. Late-joining enemies (boss unleash, respawn) are handled by
	# the node_added listener.
	for e in get_tree().get_nodes_in_group("enemy"):
		_add_player_exception(e)
	get_tree().node_added.connect(_on_node_added_for_pass_through)


func _on_node_added_for_pass_through(node: Node) -> void:
	# group registration happens in the node's own _ready, which runs AFTER
	# tree_added — wait one frame so is_in_group() is reliable.
	await get_tree().process_frame
	if not is_instance_valid(node):
		return
	if node.is_in_group("enemy"):
		_add_player_exception(node)


func _add_player_exception(enemy: Node) -> void:
	if enemy is CollisionObject2D:
		(enemy as CollisionObject2D).add_collision_exception_with(self)


func _setup_dash_sfx() -> void:
	# Mixkit "Arrow whoosh" — royalty-free, commercial-OK, no attribution.
	var stream: AudioStream = load("res://assets/sfx/dash.mp3")
	if stream == null:
		return
	_dash_sfx = AudioStreamPlayer.new()
	_dash_sfx.stream = stream
	_dash_sfx.volume_db = -6.0
	_dash_sfx.bus = "Master"
	add_child(_dash_sfx)


func _setup_throw_sfx() -> void:
	# Mixkit "Throw hard wind woosh" — heavier, weighted whoosh distinct from
	# the dash sound. Royalty-free, commercial-OK, no attribution.
	var stream: AudioStream = load("res://assets/sfx/throw.mp3")
	if stream == null:
		return
	_throw_sfx = AudioStreamPlayer.new()
	_throw_sfx.stream = stream
	_throw_sfx.volume_db = -5.0
	_throw_sfx.bus = "Master"
	add_child(_throw_sfx)


func _play_throw_sfx() -> void:
	if not is_instance_valid(_throw_sfx):
		return
	# Stop+play so spamming throws doesn't pile overlapping playback.
	_throw_sfx.stop()
	_throw_sfx.pitch_scale = randf_range(0.92, 1.10)
	_throw_sfx.play()


func _facing_direction() -> Vector2:
	match animated_sprite.animation:
		"left":  return Vector2.LEFT
		"right": return Vector2.RIGHT
		"up":    return Vector2.UP
		"down":  return Vector2.DOWN
	return Vector2.RIGHT


func _wasd_direction() -> Vector2:
	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A): dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D): dir.x += 1.0
	if Input.is_physical_key_pressed(KEY_W): dir.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S): dir.y += 1.0
	return dir.normalized() if dir.length() > 0.0 else Vector2.ZERO


func _handle_movement(delta: float) -> void:
	var dir := _wasd_direction()
	var speed := move_speed
	# Sprint: hold Shift while moving. Drains stamina; auto-stops when empty.
	if dir != Vector2.ZERO and Input.is_physical_key_pressed(KEY_SHIFT) and stamina > 0.0:
		var drain: float = sprint_stamina_drain * delta
		stamina = maxf(stamina - drain, 0.0)
		_stamina_regen_block_t = stamina_regen_delay
		if stamina_ui:
			stamina_ui.set_stamina(stamina, max_stamina)
		_sprinting = stamina > 0.0
		if _sprinting:
			speed *= sprint_speed_mult
	else:
		_sprinting = false
	velocity = dir * speed


func _update_animation() -> void:
	if velocity == Vector2.ZERO:
		animated_sprite.play("idle")
		return

	var abs_x: float = abs(velocity.x)
	var abs_y: float = abs(velocity.y)

	if abs_y >= abs_x:
		if velocity.y > 0:
			animated_sprite.play("down")
		else:
			animated_sprite.play("up")
	else:
		if velocity.x < 0:
			animated_sprite.play("left")
		else:
			animated_sprite.play("right")
