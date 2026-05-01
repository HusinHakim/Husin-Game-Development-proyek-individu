extends CharacterBody2D
# Rock Boss — multi-phase boss (D47 Sis Puella Magica diversifier).
# Animations: idle / walk / stomp / swipe — each with 4 directions
# (down, left, right, up). Anim names: "<state>_<dir>".

signal died
signal phase_changed(phase: int)

@export var move_speed: float = 70.0
@export var detection_radius: float = 600.0
@export var melee_range: float = 110.0           # swipe attack range
@export var stomp_range: float = 170.0           # stomp attack range (AoE)
@export var swipe_damage: int = 1
@export var stomp_damage: int = 1
@export var max_hp: int = 220
@export var hit_radius: float = 110.0              # manual hit-test radius for thrown items
@export var idle_duration: float = 0.6
@export var attack_cooldown: float = 1.4
@export var phase2_threshold: float = 0.5        # HP fraction for phase 2 trigger
@export var phase2_speed_mult: float = 1.6
@export var phase2_cooldown_mult: float = 0.6
@export var death_drop_scene: PackedScene = null
@export var death_drop_offset: Vector2 = Vector2.ZERO
@export var slash_fx_scene: PackedScene = preload("res://scenes/SlashFX.tscn")
@export var slash_fx_offset: float = 55.0     # forward distance from boss center
@export var swipe_windup: float = 0.45        # red telegraph duration before swipe lands
@export var stomp_windup: float = 0.65        # red telegraph duration before stomp lands

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var detection_area: Area2D = $DetectionArea
@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var health_bar: Node2D = $HealthBar
@onready var hit_area: Area2D = $HitArea           # damages player on contact during stomp/swipe

var _slice_sfx: AudioStreamPlayer = null    # heavy slash on swipe/stomp

enum State { DORMANT, IDLE, WALK, WINDUP_SWIPE, WINDUP_STOMP, SWIPE, STOMP, DEAD }
enum Dir { DOWN, LEFT, RIGHT, UP }

var state: State = State.DORMANT
var facing: int = Dir.DOWN
var hp: int
var phase: int = 1
var state_timer: float = 0.0
var attack_cd: float = 0.0
var _player_ref: Node2D = null
var _entangled: bool = false
var _attack_dealt_this_anim: bool = false
var _windup_timer: float = 0.0
var _telegraph: Node2D = null
var _stunned: bool = false


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("boss")
	z_index = 1   # render above throwable items (which sit at default z=0)
	hp = max_hp
	health_bar.visible = false
	if health_bar.has_method("set_hp"):
		health_bar.set_hp(hp, max_hp)
	collision.disabled = true
	animated_sprite.visible = false
	animated_sprite.animation_finished.connect(_on_animation_finished)
	if hit_area:
		hit_area.monitoring = false
		hit_area.body_entered.connect(_on_hit_area_body_entered)
	# Workaround: body_entered does NOT fire for bodies that already overlap
	# the DetectionArea when it enters the tree. Without this, a boss
	# instanced near the player stays DORMANT (collision disabled) and
	# thrown items pass through.
	_check_initial_player_overlap()
	_setup_slice_sfx()


func _setup_slice_sfx() -> void:
	# Mixkit "Heavy sword hit" — heavy slash for swipe/stomp.
	var stream: AudioStream = load("res://assets/sfx/boss_slice.mp3")
	if stream == null:
		return
	_slice_sfx = AudioStreamPlayer.new()
	_slice_sfx.stream = stream
	_slice_sfx.volume_db = -4.0
	_slice_sfx.bus = "Master"
	add_child(_slice_sfx)


func _play_slice_sfx() -> void:
	if not is_instance_valid(_slice_sfx):
		return
	# Stop+play so back-to-back attacks don't pile overlapping playback.
	_slice_sfx.stop()
	_slice_sfx.pitch_scale = randf_range(0.92, 1.08)
	_slice_sfx.play()


func _check_initial_player_overlap() -> void:
	await get_tree().physics_frame
	if not is_instance_valid(self) or state != State.DORMANT:
		return
	if not is_instance_valid(detection_area):
		return
	for body in detection_area.get_overlapping_bodies():
		if body.is_in_group("player"):
			_on_detection_area_body_entered(body)
			return


# --- Damage / Death ---------------------------------------------------------

func take_damage(amount: int) -> void:
	print("[RockBoss:%s] take_damage(%d) state=%d stunned=%s hp_before=%d" % [
		name, amount, state, str(_stunned), hp
	])
	if state == State.DEAD or state == State.DORMANT:
		print("  -> ignored (state=DEAD/DORMANT)")
		return
	# Stun lowers boss resistance: incoming damage is doubled while stunned.
	if _stunned:
		amount *= 2
	hp = maxi(hp - amount, 0)
	print("  -> applied=%d hp_now=%d" % [amount, hp])
	if health_bar.has_method("set_hp"):
		health_bar.set_hp(hp, max_hp)
	# Phase transition
	if phase == 1 and float(hp) / float(max_hp) <= phase2_threshold:
		_enter_phase_2()
	if hp <= 0:
		_die()


func _enter_phase_2() -> void:
	phase = 2
	move_speed *= phase2_speed_mult
	attack_cooldown *= phase2_cooldown_mult
	phase_changed.emit(phase)


func _die() -> void:
	died.emit()
	state = State.DEAD
	velocity = Vector2.ZERO
	collision.disabled = true
	if hit_area:
		hit_area.monitoring = false
	health_bar.visible = false
	animated_sprite.stop()
	set_physics_process(false)
	_clear_telegraph()
	_drop_loot()
	# Fade out then queue_free
	var tween := create_tween()
	tween.tween_property(animated_sprite, "modulate:a", 0.0, 0.8)
	tween.tween_callback(queue_free)


func _drop_loot() -> void:
	if death_drop_scene == null:
		return
	var parent := get_parent()
	if not is_instance_valid(parent):
		return
	# Boss drops a small cluster
	for i in range(3):
		var drop := death_drop_scene.instantiate()
		parent.add_child(drop)
		var off := Vector2(randf_range(-40, 40), randf_range(-40, 40))
		drop.global_position = global_position + death_drop_offset + off


# --- Status -----------------------------------------------------------------

func apply_entangle(duration: float) -> void:
	_apply_disable(duration, "Entangled", Color(0.35, 0.70, 1.0, 0.95))


func apply_stun(duration: float) -> void:
	# Marks the boss as stunned (2× damage taken) and disables it for `duration`.
	if _stunned or state == State.DEAD:
		return
	_stunned = true
	_apply_disable(duration, "Stunned", Color(1.0, 0.85, 0.20, 0.95))
	await get_tree().create_timer(duration).timeout
	if is_instance_valid(self):
		_stunned = false


func _apply_disable(duration: float, label: String, bar_color: Color) -> void:
	if _entangled or state == State.DEAD:
		return
	_entangled = true
	var saved_speed := move_speed
	move_speed = 0.0
	# Cancel everything in flight and snap back to IDLE so the state machine
	# has a clean starting point when the disable lifts. (Previously we left
	# SWIPE/STOMP state alone — but stopping the animation also stops the
	# animation_finished signal that normally transitions out of those states,
	# so the boss got stuck forever.)
	_clear_telegraph()
	if hit_area:
		hit_area.monitoring = false
	_enter_idle()
	# Freeze the idle animation so the boss visually stands still while
	# disabled — no breathing/swaying, just a clear "I'm out of action" pose.
	animated_sprite.speed_scale = 0.0

	var status := StatusEffectBar.new()
	status.setup(duration, label, bar_color)
	health_bar.add_child(status)

	await get_tree().create_timer(duration).timeout
	if is_instance_valid(self) and state != State.DEAD:
		animated_sprite.speed_scale = 1.0
		move_speed = saved_speed
		_entangled = false
		# Reset attack cooldown so the boss can choose a new action right away
		# instead of standing still waiting for the previous cooldown to drain.
		attack_cd = 0.0


# --- Main loop --------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if attack_cd > 0.0:
		attack_cd -= delta

	match state:
		State.DORMANT, State.DEAD:
			pass

		State.IDLE:
			velocity = Vector2.ZERO
			state_timer += delta
			if state_timer >= idle_duration and is_instance_valid(_player_ref):
				_decide_next_action()
			move_and_slide()

		State.WALK:
			if not is_instance_valid(_player_ref):
				_enter_idle()
				return
			var diff: Vector2 = _player_ref.global_position - global_position
			var dist: float = diff.length()
			_update_facing(diff)
			# Pick attack if in range and off cooldown.
			if attack_cd <= 0.0 and not _entangled:
				if dist <= melee_range:
					_enter_swipe()
					return
				elif dist <= stomp_range:
					_enter_stomp()
					return
			velocity = diff.normalized() * move_speed
			move_and_slide()

		State.WINDUP_SWIPE:
			velocity = Vector2.ZERO
			_windup_timer -= delta
			if _windup_timer <= 0.0:
				_execute_swipe()
			move_and_slide()

		State.WINDUP_STOMP:
			velocity = Vector2.ZERO
			_windup_timer -= delta
			if _windup_timer <= 0.0:
				_execute_stomp()
			move_and_slide()

		State.SWIPE, State.STOMP:
			velocity = Vector2.ZERO
			move_and_slide()


# --- Decisions / state transitions -----------------------------------------

func _decide_next_action() -> void:
	if not is_instance_valid(_player_ref):
		_enter_idle()
		return
	var diff: Vector2 = _player_ref.global_position - global_position
	var dist: float = diff.length()
	_update_facing(diff)
	if attack_cd <= 0.0 and not _entangled:
		if dist <= melee_range:
			_enter_swipe()
			return
		if dist <= stomp_range:
			_enter_stomp()
			return
	_enter_walk()


func _enter_idle() -> void:
	state = State.IDLE
	state_timer = 0.0
	velocity = Vector2.ZERO
	_play_dir_anim("idle")


func _enter_walk() -> void:
	state = State.WALK
	state_timer = 0.0
	_play_dir_anim("walk")


func _enter_swipe() -> void:
	state = State.WINDUP_SWIPE
	velocity = Vector2.ZERO
	_windup_timer = swipe_windup
	_spawn_telegraph(true)


func _enter_stomp() -> void:
	state = State.WINDUP_STOMP
	velocity = Vector2.ZERO
	_windup_timer = stomp_windup
	_spawn_telegraph(false)


func _execute_swipe() -> void:
	_clear_telegraph()
	state = State.SWIPE
	_attack_dealt_this_anim = false
	velocity = Vector2.ZERO
	_play_dir_anim("swipe")
	if hit_area:
		hit_area.monitoring = true
	_spawn_slash_fx(1.0)
	_play_slice_sfx()


func _execute_stomp() -> void:
	_clear_telegraph()
	state = State.STOMP
	_attack_dealt_this_anim = false
	velocity = Vector2.ZERO
	_play_dir_anim("stomp")
	if hit_area:
		hit_area.monitoring = true
	_spawn_slash_fx(1.4)        # bigger slash for the heavier stomp attack
	_play_slice_sfx()


func _spawn_telegraph(is_swipe: bool) -> void:
	_clear_telegraph()
	var tel := _AttackTelegraph.new()
	tel.is_swipe = is_swipe
	tel.facing_vector = _facing_vector()
	tel.range_value = melee_range if is_swipe else stomp_range
	tel.duration = swipe_windup if is_swipe else stomp_windup
	add_child(tel)
	_telegraph = tel


func _clear_telegraph() -> void:
	if is_instance_valid(_telegraph):
		_telegraph.queue_free()
	_telegraph = null


func _spawn_slash_fx(scale_mult: float = 1.0) -> void:
	if slash_fx_scene == null:
		return
	var parent := get_parent()
	if not is_instance_valid(parent):
		return
	var fx: Node2D = slash_fx_scene.instantiate()
	parent.add_child(fx)
	var dir_vec: Vector2 = _facing_vector()
	fx.global_position = global_position + dir_vec * slash_fx_offset
	fx.rotation = dir_vec.angle()
	fx.scale *= scale_mult


func _facing_vector() -> Vector2:
	match facing:
		Dir.UP: return Vector2(0, -1)
		Dir.DOWN: return Vector2(0, 1)
		Dir.LEFT: return Vector2(-1, 0)
		Dir.RIGHT: return Vector2(1, 0)
		_: return Vector2(1, 0)


# --- Direction --------------------------------------------------------------

func _update_facing(toward: Vector2) -> void:
	if toward.length_squared() < 1.0:
		return
	# Pick the cardinal direction whose unit vector best matches `toward`.
	if absf(toward.x) > absf(toward.y):
		facing = Dir.RIGHT if toward.x > 0.0 else Dir.LEFT
	else:
		facing = Dir.DOWN if toward.y > 0.0 else Dir.UP


func _dir_suffix() -> String:
	match facing:
		Dir.UP: return "up"
		Dir.LEFT: return "left"
		Dir.RIGHT: return "right"
		_: return "down"


func _play_dir_anim(base: String) -> void:
	var anim := "%s_%s" % [base, _dir_suffix()]
	if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(anim):
		animated_sprite.play(anim)


# --- Animation events -------------------------------------------------------

func _on_animation_finished() -> void:
	if state == State.DEAD or state == State.DORMANT:
		return
	var anim: String = animated_sprite.animation
	if anim.begins_with("swipe") or anim.begins_with("stomp"):
		if hit_area:
			hit_area.monitoring = false
		attack_cd = attack_cooldown
		_enter_idle()


# --- Spawn ------------------------------------------------------------------

func spawn_at(pos: Vector2) -> void:
	if state != State.DORMANT:
		return
	global_position = pos
	state = State.IDLE
	state_timer = 0.0
	hp = max_hp
	if health_bar.has_method("set_hp"):
		health_bar.set_hp(hp, max_hp)
	visible = true
	animated_sprite.visible = true
	collision.disabled = false
	health_bar.visible = true
	_play_dir_anim("idle")
	print("[RockBoss:%s] spawned at %s collision_enabled=%s layer=%d" % [
		name, str(pos), str(not collision.disabled), collision_layer
	])


func _on_detection_area_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_ref = body
	if state == State.DORMANT:
		spawn_at(global_position)


# --- Damage to player on contact during attack ------------------------------

func _on_hit_area_body_entered(body: Node2D) -> void:
	if _attack_dealt_this_anim:
		return
	if not body.is_in_group("player"):
		return
	if not body.has_method("take_damage"):
		return
	# Damage only inside the same forward cone shown by the red telegraph.
	# This keeps the danger zone visually honest — being outside the red
	# arc means truly safe, even if HitArea overlaps you.
	var to_body: Vector2 = body.global_position - global_position
	if to_body.length_squared() > 1.0:
		var face: Vector2 = _facing_vector()
		var angle_diff: float = absf(to_body.normalized().angle_to(face))
		var arc_rad: float = deg_to_rad(50.0 if state == State.SWIPE else 70.0)
		if angle_diff > arc_rad:
			return
	var dmg: int = stomp_damage if state == State.STOMP else swipe_damage
	body.take_damage(dmg)
	_attack_dealt_this_anim = true


# --- Inner class: red telegraph drawn before an attack lands ---------------

class _AttackTelegraph extends Node2D:
	var is_swipe: bool = true
	var facing_vector: Vector2 = Vector2.RIGHT
	var range_value: float = 110.0
	var duration: float = 0.4
	var elapsed: float = 0.0

	func _ready() -> void:
		z_index = 4                 # below SlashFX (5), above boss sprite (0)
		set_process(true)

	func _process(delta: float) -> void:
		elapsed += delta
		queue_redraw()

	func _draw() -> void:
		var t: float = clampf(elapsed / maxf(duration, 0.001), 0.0, 1.0)
		var pulse: float = 0.5 + 0.5 * sin(elapsed * 16.0)
		# Alpha ramps up as the attack approaches; pulses for warning.
		var fill_alpha: float = clampf(0.18 + 0.18 * pulse + 0.30 * t, 0.0, 0.78)
		var fill_color: Color = Color(1.00, 0.18, 0.16, fill_alpha)
		var border_color: Color = Color(1.00, 0.10, 0.06, clampf(0.5 + 0.5 * t, 0.6, 1.0))

		# Both swipe and stomp use a directional cone; stomp's is wider/longer.
		var ang: float = facing_vector.angle()
		var half_arc: float = deg_to_rad(50.0 if is_swipe else 70.0)
		var n: int = 20
		var pts: PackedVector2Array = PackedVector2Array()
		pts.append(Vector2.ZERO)
		for i in range(n + 1):
			var a: float = ang - half_arc + (2.0 * half_arc) * float(i) / float(n)
			pts.append(Vector2(cos(a), sin(a)) * range_value)
		draw_colored_polygon(pts, fill_color)
		for i in range(pts.size()):
			draw_line(pts[i], pts[(i + 1) % pts.size()], border_color, 2.0)
