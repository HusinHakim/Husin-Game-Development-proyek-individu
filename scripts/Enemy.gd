extends CharacterBody2D

@export var move_speed: float = 120.0
@export var wander_radius: float = 200.0
@export var walk_duration: float = 5.0
@export var idle_duration: float = 1.5
@export var detection_radius: float = 400.0
@export var max_hp: int = 100
@export var cast_chance: float = 0.75
@export var projectile_scene: PackedScene
@export var respawn_delay: float = 5.0
@export var respawn_count: int = 1            # respawns left before permanent death
@export var death_drop_scene: PackedScene = null
@export var death_drop_offset: Vector2 = Vector2.ZERO
@export var hit_radius: float = 32.0           # manual hit-test radius for thrown items

signal died  # emitted on every death (incl. respawnable ones) for kill-counter UI

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var detection_area: Area2D = $DetectionArea
@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var health_bar: Node2D = $HealthBar
@onready var staff_tip: Marker2D = $StaffTip

var _charged_proj = null  # projectile sitting at staff tip before release
var _entangled: bool = false

# Spritesheet "entangled" sudah di-align (body terpusat + robe-bottom seragam)
# dan body-nya seukuran frame walk, jadi scale 1.0 & offset ~0.
# (Fine-tune di editor kalau posisinya perlu digeser sedikit.)
const ENTANGLED_SCALE := Vector2(1.0, 1.0)
const ENTANGLED_OFFSET := Vector2(0, -1)

enum State { DORMANT, SPAWNING, WALK, IDLE, CAST }

var state: State = State.DORMANT
var home: Vector2
var target: Vector2
var state_timer: float = 0.0
var hp: int
var _player_ref: Node2D = null


func _ready() -> void:
	add_to_group("enemy")
	z_index = 1   # render above throwable items (which sit at default z=0)
	home = global_position
	hp = max_hp
	health_bar.visible = false
	health_bar.set_hp(hp, max_hp)
	animated_sprite.visible = false
	collision.disabled = true
	animated_sprite.animation_finished.connect(_on_animation_finished)


func take_damage(amount: int) -> void:
	hp = maxi(hp - amount, 0)
	health_bar.set_hp(hp, max_hp)
	if hp <= 0:
		_die_and_respawn()


# Hit flash (#2) — dipanggil HitFX.on_hit. Skip saat sekarat/respawn (DORMANT)
# supaya tidak mengganggu sprite yang sudah disembunyikan.
func flash_hit() -> void:
	if state == State.DORMANT:
		return
	HitFX.flash(animated_sprite)


func _die_and_respawn() -> void:
	# Notify listeners (e.g. KillCounterUI) before any state change.
	died.emit()
	# Drop loot at the spot where the enemy died (always, even on final death).
	_drop_loot()

	# Hide and disable the enemy.
	state = State.DORMANT
	visible = false
	collision.disabled = true
	health_bar.visible = false
	set_physics_process(false)

	# Stop any in-flight animation so a stale `animation_finished` signal
	# (e.g. cast anim completing mid-await) cannot pull state out of DORMANT
	# and make spawn_at() bail out at respawn.
	animated_sprite.stop()

	# Clear active cast / status effects
	if is_instance_valid(_charged_proj):
		_charged_proj.queue_free()
		_charged_proj = null
	_entangled = false
	for child in health_bar.get_children():
		if child is StatusEffectBar:
			child.queue_free()

	# Respawn budget exhausted → permanent death.
	if respawn_count <= 0:
		queue_free()
		return
	respawn_count -= 1

	await get_tree().create_timer(respawn_delay).timeout
	if not is_instance_valid(self):
		return

	hp = max_hp
	health_bar.set_hp(hp, max_hp)
	visible = true
	set_physics_process(true)
	spawn_at(home)


func _drop_loot() -> void:
	if death_drop_scene == null:
		return
	var parent := get_parent()
	if not is_instance_valid(parent):
		return
	var drop := death_drop_scene.instantiate()
	parent.add_child(drop)
	drop.global_position = global_position + death_drop_offset


func apply_entangle(duration: float) -> void:
	if _entangled:
		return
	_entangled = true
	var saved_speed := move_speed
	move_speed = 0.0
	_cancel_cast_if_active()
	# Bekukan + mulai animasi terbelit (berlaku dari WALK/IDLE/CAST).
	_enter_idle()

	var status := StatusEffectBar.new()
	status.setup(duration, "Entangled", Color(0.35, 0.70, 1.0, 0.95))
	health_bar.add_child(status)

	await get_tree().create_timer(duration).timeout
	if is_instance_valid(self):
		move_speed = saved_speed
		_entangled = false


func _cancel_cast_if_active() -> void:
	if state != State.CAST:
		return
	if is_instance_valid(_charged_proj):
		_charged_proj.queue_free()
		_charged_proj = null
	_enter_idle()


func _physics_process(delta: float) -> void:
	match state:
		State.DORMANT:
			pass

		State.SPAWNING:
			velocity = Vector2.ZERO
			move_and_slide()

		State.WALK:
			state_timer += delta
			var diff: Vector2 = target - global_position
			if diff.length() < 4.0 or state_timer >= walk_duration:
				velocity = Vector2.ZERO
				_enter_idle()
			else:
				var dir: Vector2 = diff.normalized()
				velocity = dir * move_speed
				animated_sprite.flip_h = dir.x < 0
			move_and_slide()

		State.IDLE:
			state_timer += delta
			velocity = Vector2.ZERO
			# While entangled, never transition out of IDLE — that keeps the
			# sprite locked on the frozen "diam" pose (walk frame 0) instead
			# of cycling back into the walk animation while move_speed=0.
			if state_timer >= idle_duration and not _entangled:
				var should_cast: bool = (
					projectile_scene != null
					and is_instance_valid(_player_ref)
					and randf() < cast_chance
				)
				if should_cast:
					_enter_cast()
				else:
					_pick_target()
					_play_anim("walk")
					state = State.WALK
					state_timer = 0.0
			move_and_slide()

		State.CAST:
			velocity = Vector2.ZERO
			move_and_slide()


func _enter_idle() -> void:
	state = State.IDLE
	state_timer = 0.0
	if _entangled:
		_play_entangled()
		return
	animated_sprite.animation = "walk"
	animated_sprite.stop()
	animated_sprite.frame = 0
	animated_sprite.offset = Vector2.ZERO
	animated_sprite.scale = Vector2.ONE


# Mainkan animasi terbelit sekali (non-loop): rantai melilit → tahan → lepas.
# Speed di SpriteFrames disetel ~4 fps × 8 frame ≈ 2.0s = ENTANGLE_DURATION,
# jadi frame "lepas rantai" jatuh tepat saat efek berakhir.
func _play_entangled() -> void:
	animated_sprite.flip_h = false   # art chained punya orientasi tetap
	animated_sprite.scale = ENTANGLED_SCALE
	animated_sprite.offset = ENTANGLED_OFFSET
	if animated_sprite.animation != "entangled":
		animated_sprite.play("entangled")


func _enter_cast() -> void:
	state = State.CAST
	# Face the player
	if is_instance_valid(_player_ref):
		animated_sprite.flip_h = _player_ref.global_position.x < global_position.x
	_play_anim("cast")
	_spawn_charge()


func _play_anim(anim: String) -> void:
	animated_sprite.offset = Vector2.ZERO   # reset offset pose entangled
	match anim:
		"spawn":
			animated_sprite.scale = Vector2(1.087, 1.087)
		_:
			animated_sprite.scale = Vector2(1.0, 1.0)
	animated_sprite.play(anim)


func _pick_target() -> void:
	var angle: float = randf_range(0.0, TAU)
	var dist: float = randf_range(40.0, wander_radius)
	target = home + Vector2(cos(angle), sin(angle)) * dist


func spawn_at(pos: Vector2) -> void:
	if state != State.DORMANT:
		return
	global_position = pos
	home = pos
	state = State.SPAWNING
	animated_sprite.visible = true
	health_bar.visible = true
	collision.disabled = true
	_play_anim("spawn")


func _on_animation_finished() -> void:
	# Safety: ignore stray animation events while the enemy is dormant
	# (e.g. dying / waiting to respawn). Otherwise a leftover cast/walk anim
	# completing during the respawn await would change state out of DORMANT
	# and the next spawn_at(home) would early-return.
	if state == State.DORMANT:
		return
	match animated_sprite.animation:
		"spawn":
			collision.disabled = false
			# If entangled at spawn finish, drop straight into IDLE so the
			# sprite stays frozen instead of playing a "walk in place" loop.
			if _entangled:
				_enter_idle()
				return
			_pick_target()
			_play_anim("walk")
			state = State.WALK
			state_timer = 0.0
		"cast":
			_release_projectile()
			_enter_idle()


func _get_staff_tip_global() -> Vector2:
	if animated_sprite.flip_h:
		# Mirror the tip's x around the enemy's global x
		var tip := staff_tip.global_position
		tip.x = global_position.x - (tip.x - global_position.x)
		return tip
	return staff_tip.global_position


func _spawn_charge() -> void:
	if projectile_scene == null:
		return
	var proj = projectile_scene.instantiate()
	get_parent().add_child(proj)
	# Place at staff tip, frozen (speed=0, no direction yet)
	proj.global_position = _get_staff_tip_global()
	proj.speed = 0.0
	# Grow from nothing to signal charging
	proj.scale = Vector2.ZERO
	var tween := proj.create_tween()
	tween.tween_property(proj, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_charged_proj = proj


func _release_projectile() -> void:
	if not is_instance_valid(_charged_proj):
		_charged_proj = null
		return
	if not is_instance_valid(_player_ref):
		_charged_proj.queue_free()
		_charged_proj = null
		return
	var aim_pos: Vector2 = _player_ref.global_position + Vector2(0, -30)
	_charged_proj.init(_get_staff_tip_global(), aim_pos)
	_charged_proj.speed = 380.0
	_charged_proj = null


func _on_detection_area_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_ref = body
	if state != State.DORMANT:
		return

	var camera: Camera2D = body.get_node_or_null("Camera2D")
	if camera == null:
		spawn_at(global_position)
		return

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size / camera.zoom
	var half: Vector2 = viewport_size * 0.5
	var cam_pos: Vector2 = camera.global_position

	var spawn_pos: Vector2 = global_position
	for _i in range(10):
		var candidate: Vector2 = cam_pos + Vector2(
			randf_range(-half.x * 0.8, half.x * 0.8),
			randf_range(-half.y * 0.8, half.y * 0.8)
		)
		if candidate.distance_to(body.global_position) > 150.0:
			spawn_pos = candidate
			break

	spawn_at(spawn_pos)
