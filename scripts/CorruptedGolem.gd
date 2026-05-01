extends CharacterBody2D
# Corrupted Golem — boss kedua (D47 multi-phase). Berbeda dari RockBoss:
# spritesheet hanya 1 arah (front-facing) jadi facing horizontal pakai flip_h.
# Dua serangan: swipe (jarak dekat, cepat) + slam (jarak menengah, AoE besar).

signal died
signal phase_changed(phase: int)

@export var move_speed: float = 60.0
@export var detection_radius: float = 240.0   # informational; actual area is in CorruptedGolem.tscn DetectionShape
@export var melee_range: float = 130.0
@export var slam_range: float = 220.0
@export var swipe_damage: int = 1
@export var slam_damage: int = 1   # equalized with swipe — same hit weight
@export var max_hp: int = 260
@export var hit_radius: float = 130.0
@export var idle_duration: float = 0.55
@export var attack_cooldown: float = 1.6
@export var phase2_threshold: float = 0.5
@export var phase2_speed_mult: float = 1.5
@export var phase2_cooldown_mult: float = 0.55
@export var death_drop_scene: PackedScene = null
@export var death_drop_offset: Vector2 = Vector2.ZERO
@export var slash_fx_scene: PackedScene = preload("res://scenes/SlashFX.tscn")
@export var slash_fx_offset: float = 60.0
@export var swipe_windup: float = 0.45
@export var slam_windup: float = 0.75
@export var hurt_flash_duration: float = 0.12

# Ranged attack: plays the "charge" animation and spits a CultProjectile
# from the boss's hand on the launch frame.
@export var cult_projectile_scene: PackedScene = preload("res://scenes/CultProjectile.tscn")
@export var shoot_range: float = 600.0           # max distance to consider shooting
@export var shoot_min_range: float = 240.0       # below this, prefer melee
@export var shoot_windup: float = 0.55
@export var shoot_release_frame: int = 3         # frame in "charge" anim where the orb appears in the hand
@export var shoot_projectile_speed: float = 320.0

# Global slowdown for every animation. < 1.0 = slower, > 1.0 = faster.
# Apply via AnimatedSprite2D.speed_scale so per-anim FPS values in the .tres
# stay untouched and re-tunable from the inspector at runtime.
@export var anim_speed_scale: float = 0.6
# Override speed for attack anims (attack 1 / area ult / shoot). Higher than
# the base so impacts feel snappy without speeding up idle/hurt/death.
@export var attack_anim_speed_scale: float = 1.1

# Phase-2 ult: massive boss-centered AoE, auto-triggered when HP first hits
# the phase2 threshold. The big red circle telegraph gives the player time
# to back out of range before the slam lands.
@export var ult_range: float = 280.0
@export var ult_damage: int = 9999                 # one-shot kill — ult is the "GTFO" mechanic
@export var ult_windup: float = 1.1                # red circle telegraph duration
@export var ult_impact_frame: int = 8              # frame in "area ult" anim where the SFX/visual lands
@export var ult_cooldown: float = 4.0

# Frame inside the "attack 2" anim where the chain actually strikes. SFX
# fires on this frame instead of at execute() time so the whoosh/clank syncs
# with the visible swing instead of the wind-up.
@export var attack_strike_frame: int = 4
# Source file was trimmed (head -0.7s) so playback starts on the chain
# rattle. Leave at 0.0 unless you swap the SFX for another with intro.
@export var flail_sfx_start_offset: float = 0.0

# When true, the boss ignores detection events and stays DORMANT (invisible,
# collision off) until something calls unleash() on it. Use this for boss
# arenas where the encounter starts on a trigger (rituals, switch, cutscene).
@export var start_locked: bool = false

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var detection_area: Area2D = $DetectionArea
@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var health_bar: Node2D = $HealthBar
@onready var hit_area: Area2D = $HitArea
@onready var hand_marker: Marker2D = $HandMarker   # local-space launch point (right hand)

enum State { DORMANT, IDLE, WALK, WINDUP_SWIPE, WINDUP_SLAM, WINDUP_SHOOT, WINDUP_ULT, SWIPE, SLAM, SHOOT, ULT, DEAD }

# Animation name aliases — change here if SpriteFrames is renamed.
# The sheet exposes: idle, attack 1, attack 2, area ult, shoot, hurt, die.
# No dedicated "walk" so WALK state plays idle while moving.
# Normal attacks (close + medium range) all funnel into "attack 2" now;
# "attack 1" is intentionally unused per the design tweak.
const ANIM_IDLE  := "idle"
const ANIM_WALK  := "idle"
const ANIM_SWIPE := "attack 2"
const ANIM_SLAM  := "attack 2"
const ANIM_SHOOT := "shoot"
const ANIM_HURT  := "hurt"
const ANIM_DEATH := "die"
# "area ult" is reserved exclusively for the phase-2 ult triggered at 50% HP.
const ANIM_AREA_ULT := "area ult"

var state: State = State.DORMANT
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
var _facing_x: float = 1.0   # +1 = facing right, -1 = facing left
var _shoot_fired: bool = false
var _shoot_target: Vector2 = Vector2.ZERO
var _floating_projectile: Node = null   # orb spawned at frame 3, sits in hand until charge anim ends
var _ult_dealt_this_anim: bool = false
var _flail_played_this_anim: bool = false   # one-shot guard — fires sfx exactly once per swing
# Separate cooldown for ult so it doesn't reset alongside swipe/slam/shoot
# attacks. Counts down only after the first ult (the phase-2 entry burst),
# so subsequent ults need to wait the full ult_cooldown.
var ult_cd: float = 0.0
var _locked: bool = false
# Audio
var _flail_sfx: AudioStreamPlayer = null      # chain swing on swipe/slam/ult
var _ambient_sfx: AudioStreamPlayer2D = null  # positional rocky drone — louder when player is close


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("boss")
	z_index = 1
	hp = max_hp
	_locked = start_locked
	if _locked:
		# Stay invisible until unleash() is called (e.g. by RitualManager
		# after all ritual books are read).
		visible = false
	health_bar.visible = false
	if health_bar.has_method("set_hp"):
		health_bar.set_hp(hp, max_hp)
	collision.disabled = true
	animated_sprite.visible = false
	animated_sprite.speed_scale = anim_speed_scale
	animated_sprite.animation_finished.connect(_on_animation_finished)
	# Force loop flags at runtime: the SpriteFrames may have been re-imported
	# or renamed via the editor with loop=true (Godot's default for new anims),
	# which would silence animation_finished and lock the boss in the attack
	# state. We override here so the .tres file's loop config can't break us.
	_enforce_loop_flags()
	if hit_area:
		hit_area.monitoring = false
		hit_area.body_entered.connect(_on_hit_area_body_entered)
	_check_initial_player_overlap()
	_setup_flail_sfx()
	_setup_ambient_sfx()


func _check_initial_player_overlap() -> void:
	await get_tree().physics_frame
	if not is_instance_valid(self) or state != State.DORMANT:
		return
	if _locked:
		return
	if not is_instance_valid(detection_area):
		return
	for body in detection_area.get_overlapping_bodies():
		if body.is_in_group("player"):
			_on_detection_area_body_entered(body)
			return


# --- Damage / Death ---------------------------------------------------------

func take_damage(amount: int) -> void:
	if state == State.DEAD or state == State.DORMANT:
		return
	if _stunned:
		amount *= 2
	hp = maxi(hp - amount, 0)
	if health_bar.has_method("set_hp"):
		health_bar.set_hp(hp, max_hp)
	_flash_hurt()
	if phase == 1 and float(hp) / float(max_hp) <= phase2_threshold:
		_enter_phase_2()
	if hp <= 0:
		_die()


func _enter_phase_2() -> void:
	phase = 2
	move_speed *= phase2_speed_mult
	attack_cooldown *= phase2_cooldown_mult
	phase_changed.emit(phase)
	print("[CorruptedGolem] PHASE 2 triggered at hp=%d/%d → entering ULT" % [hp, max_hp])
	# Enrage moment: immediately wind up the ult so the player feels the
	# transition. Subsequent ults can be triggered manually if you add a
	# cooldown-driven path later.
	_enter_ult()


func _flash_hurt() -> void:
	# Brief white-purple tint to telegraph hits — death anim handles "hurt" sequence,
	# this is just a per-shot visual ping that doesn't interrupt the state machine.
	if not is_instance_valid(animated_sprite):
		return
	animated_sprite.modulate = Color(1.7, 1.4, 1.7, 1.0)
	await get_tree().create_timer(hurt_flash_duration).timeout
	if is_instance_valid(animated_sprite) and state != State.DEAD:
		animated_sprite.modulate = Color(1, 1, 1, 1)


func _die() -> void:
	died.emit()
	state = State.DEAD
	velocity = Vector2.ZERO
	collision.disabled = true
	if hit_area:
		hit_area.monitoring = false
	health_bar.visible = false
	_clear_telegraph()
	_clear_floating_projectile()
	_stop_ambient_sfx()
	set_physics_process(false)
	# Play death animation, then fade and free.
	animated_sprite.modulate = Color(1, 1, 1, 1)
	if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(ANIM_DEATH):
		animated_sprite.play(ANIM_DEATH)
		await animated_sprite.animation_finished
	if is_instance_valid(self):
		_drop_loot()
		var tween := create_tween()
		tween.tween_property(animated_sprite, "modulate:a", 0.0, 0.6)
		tween.tween_callback(queue_free)


func _drop_loot() -> void:
	if death_drop_scene == null:
		return
	var parent := get_parent()
	if not is_instance_valid(parent):
		return
	for i in range(4):
		var drop := death_drop_scene.instantiate()
		parent.add_child(drop)
		var off := Vector2(randf_range(-50, 50), randf_range(-50, 50))
		drop.global_position = global_position + death_drop_offset + off


# --- Status -----------------------------------------------------------------

func apply_entangle(duration: float) -> void:
	_apply_disable(duration, "Entangled", Color(0.35, 0.70, 1.0, 0.95))


func apply_stun(duration: float) -> void:
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
	_clear_telegraph()
	_clear_floating_projectile()
	if hit_area:
		hit_area.monitoring = false
	_enter_idle()
	animated_sprite.speed_scale = 0.0

	# Status bar attaches to a fresh anchor above the boss head, NOT to the
	# in-world HealthBar (which we keep hidden because BossHealthUI shows HP
	# at the top of the screen). Anchor is freed when the bar finishes.
	var anchor := Node2D.new()
	anchor.position = Vector2(0, -90)   # above sprite top — readable while fighting
	add_child(anchor)
	var status := StatusEffectBar.new()
	# Boss uses a smaller bar so it doesn't overwhelm the sprite or compete
	# with the BossHealthUI panel at the top of the screen. Cult enemies
	# (Enemy.gd) use the default 1.0 scale.
	status.setup(duration, label, bar_color, 0.55)
	anchor.add_child(status)
	status.tree_exited.connect(func():
		if is_instance_valid(anchor):
			anchor.queue_free()
	)

	await get_tree().create_timer(duration).timeout
	if is_instance_valid(self) and state != State.DEAD:
		animated_sprite.speed_scale = anim_speed_scale
		move_speed = saved_speed
		_entangled = false
		attack_cd = 0.0


# --- Main loop --------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if attack_cd > 0.0:
		attack_cd -= delta
	if ult_cd > 0.0:
		ult_cd -= delta

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
			if attack_cd <= 0.0 and not _entangled:
				if dist <= melee_range:
					_enter_swipe()
					return
				elif dist <= slam_range:
					_enter_slam()
					return
				elif dist <= shoot_range and dist >= shoot_min_range:
					_enter_shoot()
					return
			velocity = diff.normalized() * move_speed
			move_and_slide()

		State.WINDUP_SWIPE:
			velocity = Vector2.ZERO
			_windup_timer -= delta
			if _windup_timer <= 0.0:
				_execute_swipe()
			move_and_slide()

		State.WINDUP_SLAM:
			velocity = Vector2.ZERO
			_windup_timer -= delta
			if _windup_timer <= 0.0:
				_execute_slam()
			move_and_slide()

		State.WINDUP_SHOOT:
			velocity = Vector2.ZERO
			_windup_timer -= delta
			if _windup_timer <= 0.0:
				_execute_shoot()
			move_and_slide()

		State.WINDUP_ULT:
			velocity = Vector2.ZERO
			_windup_timer -= delta
			if _windup_timer <= 0.0:
				_execute_ult()
			move_and_slide()

		State.SWIPE, State.SLAM:
			velocity = Vector2.ZERO
			# Fire flail SFX once when the swing reaches the strike frame so
			# the chain whoosh syncs with the visible swing instead of the
			# wind-up start.
			if not _flail_played_this_anim and animated_sprite.frame >= attack_strike_frame:
				_play_flail_sfx()
				_flail_played_this_anim = true
			move_and_slide()

		State.SHOOT:
			velocity = Vector2.ZERO
			# At the release frame, conjure the orb in the boss's hand. It floats
			# (no direction/speed) parented to HandMarker until the charge anim
			# finishes — then _on_animation_finished launches it at the player.
			if not _shoot_fired and animated_sprite.frame >= shoot_release_frame:
				_spawn_floating_projectile()
				_shoot_fired = true
			move_and_slide()

		State.ULT:
			velocity = Vector2.ZERO
			# Damage is now deferred to animation_finished — the player has
			# the entire windup + slam anim to escape the red circle. We
			# still fire the flail SFX at the visual impact frame so the
			# slam crack feels grounded mid-anim.
			if not _flail_played_this_anim and animated_sprite.frame >= ult_impact_frame:
				_play_flail_sfx()
				_flail_played_this_anim = true
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
		if dist <= slam_range:
			_enter_slam()
			return
		if dist <= shoot_range and dist >= shoot_min_range:
			_enter_shoot()
			return
	_enter_walk()


func _enter_idle() -> void:
	state = State.IDLE
	state_timer = 0.0
	velocity = Vector2.ZERO
	# Restore base speed — attacks may have boosted speed_scale.
	if not _entangled:
		animated_sprite.speed_scale = anim_speed_scale
	_play_anim(ANIM_IDLE)


func _enter_walk() -> void:
	state = State.WALK
	state_timer = 0.0
	if not _entangled:
		animated_sprite.speed_scale = anim_speed_scale
	_play_anim(ANIM_WALK)


func _enter_swipe() -> void:
	state = State.WINDUP_SWIPE
	velocity = Vector2.ZERO
	_windup_timer = swipe_windup
	_spawn_telegraph(true)
	_play_anim(ANIM_IDLE)  # hold a stance during windup; telegraph cone is the cue


func _enter_slam() -> void:
	state = State.WINDUP_SLAM
	velocity = Vector2.ZERO
	_windup_timer = slam_windup
	_spawn_telegraph(false)
	_play_anim(ANIM_IDLE)


func _execute_swipe() -> void:
	_clear_telegraph()
	state = State.SWIPE
	_attack_dealt_this_anim = false
	_flail_played_this_anim = false
	velocity = Vector2.ZERO
	animated_sprite.speed_scale = attack_anim_speed_scale
	_play_anim(ANIM_SWIPE)
	if hit_area:
		hit_area.monitoring = true
	_spawn_slash_fx(1.0)


func _execute_slam() -> void:
	_clear_telegraph()
	state = State.SLAM
	_attack_dealt_this_anim = false
	_flail_played_this_anim = false
	velocity = Vector2.ZERO
	animated_sprite.speed_scale = attack_anim_speed_scale
	_play_anim(ANIM_SLAM)
	if hit_area:
		hit_area.monitoring = true
	_spawn_slash_fx(1.5)


func _enter_ult() -> void:
	# Cancels whatever the boss was doing — phase 2 trigger is non-negotiable.
	_clear_telegraph()
	_clear_floating_projectile()
	if hit_area:
		hit_area.monitoring = false
	state = State.WINDUP_ULT
	velocity = Vector2.ZERO
	_windup_timer = ult_windup
	_spawn_ult_telegraph()
	_play_anim(ANIM_IDLE)


func _execute_ult() -> void:
	# IMPORTANT: don't clear the telegraph here — the red circle must stay
	# visible throughout the slam animation. It's only cleared once the anim
	# finishes (in _on_animation_finished) at the same instant damage lands.
	state = State.ULT
	_ult_dealt_this_anim = false
	_flail_played_this_anim = false
	velocity = Vector2.ZERO
	animated_sprite.speed_scale = attack_anim_speed_scale
	# Pick "area ult" if it exists in SpriteFrames, else fall back to the
	# normal "attack 2" anim so the ult mechanic still runs even if the
	# dedicated anim was renamed/removed in the editor.
	var sf := animated_sprite.sprite_frames
	var anim_to_play: String = ANIM_AREA_ULT
	if sf == null or not sf.has_animation(ANIM_AREA_ULT):
		anim_to_play = ANIM_SLAM
		print("[CorruptedGolem] WARN: '%s' anim missing — falling back to '%s' for ULT." % [ANIM_AREA_ULT, ANIM_SLAM])
	_play_anim(anim_to_play)
	_spawn_slash_fx(2.2)
	print("[CorruptedGolem] ULT executed (anim=%s, range=%.0f, damage=%d)" % [anim_to_play, ult_range, ult_damage])


func _apply_ult_damage() -> void:
	if not is_instance_valid(_player_ref):
		return
	if not _player_ref.has_method("take_damage"):
		return
	var d: float = _player_ref.global_position.distance_to(global_position)
	if d <= ult_range:
		_player_ref.take_damage(ult_damage)


func _spawn_ult_telegraph() -> void:
	_clear_telegraph()
	var tel := _AttackTelegraph.new()
	tel.is_circle = true
	tel.range_value = ult_range
	tel.duration = ult_windup
	add_child(tel)
	_telegraph = tel


func _enter_shoot() -> void:
	state = State.WINDUP_SHOOT
	velocity = Vector2.ZERO
	_windup_timer = shoot_windup
	# Lock target at windup start so the projectile fires at where the player
	# *was* — feels fairer than perfect leading.
	if is_instance_valid(_player_ref):
		_shoot_target = _player_ref.global_position
	# No telegraph cone for shoot — animation itself is the wind-up cue.
	_play_anim(ANIM_IDLE)  # brief pause/aim before shoot anim


func _execute_shoot() -> void:
	state = State.SHOOT
	_shoot_fired = false
	velocity = Vector2.ZERO
	# Refresh target at moment of cast for a fresh aim.
	if is_instance_valid(_player_ref):
		_shoot_target = _player_ref.global_position
	if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(ANIM_SHOOT):
		animated_sprite.speed_scale = attack_anim_speed_scale
		animated_sprite.play(ANIM_SHOOT)
	else:
		# No shoot anim available — spawn the orb immediately and launch it.
		_spawn_floating_projectile()
		_launch_floating_projectile()
		_shoot_fired = true
		attack_cd = attack_cooldown
		_enter_idle()


func _spawn_floating_projectile() -> void:
	# Phase 1 of shoot: orb materializes in the hand. Parent it to HandMarker
	# so it tracks the boss's hand position even as the boss turns/moves, with
	# direction=zero so CultProjectile._physics_process applies no translation.
	if cult_projectile_scene == null or not is_instance_valid(hand_marker):
		return
	var proj := cult_projectile_scene.instantiate()
	hand_marker.add_child(proj)
	# Place at the marker origin (i.e. the hand). HandMarker is mirrored via
	# _facing_x by repositioning the marker, see _refresh_hand_marker_x.
	if proj is Node2D:
		(proj as Node2D).position = Vector2.ZERO
	if "speed" in proj:
		proj.speed = 0.0
	if "direction" in proj:
		proj.direction = Vector2.ZERO
	_floating_projectile = proj


func _launch_floating_projectile() -> void:
	# Phase 2 of shoot: detach orb from the hand, hand it to the room, and
	# init() with the locked-at-cast target so it flies straight.
	if not is_instance_valid(_floating_projectile):
		return
	var orb: Node = _floating_projectile
	_floating_projectile = null
	var room := get_parent()
	if not is_instance_valid(room) or not (orb is Node2D):
		if is_instance_valid(orb):
			orb.queue_free()
		return
	var orb2d: Node2D = orb as Node2D
	var spawn_world: Vector2 = orb2d.global_position
	orb2d.get_parent().remove_child(orb2d)
	room.add_child(orb2d)
	orb2d.global_position = spawn_world
	var target: Vector2 = _shoot_target
	if is_instance_valid(_player_ref):
		target = _player_ref.global_position
	if orb.has_method("init"):
		orb.init(spawn_world, target)
	if "speed" in orb:
		orb.speed = shoot_projectile_speed




func _spawn_telegraph(is_swipe: bool) -> void:
	_clear_telegraph()
	var tel := _AttackTelegraph.new()
	tel.is_swipe = is_swipe
	tel.facing_vector = _facing_vector()
	tel.range_value = melee_range if is_swipe else slam_range
	tel.duration = swipe_windup if is_swipe else slam_windup
	add_child(tel)
	_telegraph = tel


func _clear_telegraph() -> void:
	if is_instance_valid(_telegraph):
		_telegraph.queue_free()
	_telegraph = null


func _clear_floating_projectile() -> void:
	if is_instance_valid(_floating_projectile):
		_floating_projectile.queue_free()
	_floating_projectile = null


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
	return Vector2(_facing_x, 0)


# --- Direction --------------------------------------------------------------

func _update_facing(toward: Vector2) -> void:
	if absf(toward.x) < 1.0:
		return
	var new_facing: float = 1.0 if toward.x > 0.0 else -1.0
	if new_facing == _facing_x:
		return
	_facing_x = new_facing
	# Sheet originally faces "right"; flip when facing left.
	animated_sprite.flip_h = (_facing_x < 0.0)
	# Mirror HandMarker x so the floating orb spawns from the visible hand on
	# both sides. We store the magnitude in metadata and mirror against it.
	if is_instance_valid(hand_marker):
		var base_x: float = hand_marker.get_meta("base_x", absf(hand_marker.position.x))
		hand_marker.set_meta("base_x", base_x)
		hand_marker.position.x = base_x * _facing_x


func _play_anim(name: String) -> void:
	if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(name):
		animated_sprite.play(name)


func _enforce_loop_flags() -> void:
	# `idle` and `walk` should loop; everything else (attacks, hurt, death)
	# must fire `animation_finished` so the state machine can advance.
	# Pairs (not a dict) because ANIM_IDLE and ANIM_WALK can resolve to the
	# same string ("idle"), which would make a duplicate dict key.
	var sf := animated_sprite.sprite_frames
	if sf == null:
		return
	var pairs := [
		[ANIM_IDLE, true],
		[ANIM_WALK, true],
		[ANIM_SWIPE, false],
		[ANIM_SLAM, false],
		[ANIM_SHOOT, false],
		[ANIM_AREA_ULT, false],
		[ANIM_HURT, false],
		[ANIM_DEATH, false],
	]
	for p in pairs:
		var anim_name: String = p[0]
		var should_loop: bool = p[1]
		if sf.has_animation(anim_name):
			sf.set_animation_loop(anim_name, should_loop)


# --- Animation events -------------------------------------------------------

func _on_animation_finished() -> void:
	if state == State.DEAD or state == State.DORMANT:
		return
	var anim: String = animated_sprite.animation
	# Ult ends → THIS is the moment damage lands. Apply it now (one-shot
	# kill if player is inside the red circle), then clear the telegraph
	# and recover. Player had the whole windup + slam anim to evacuate.
	# Match by STATE (not anim name) so both the dedicated ULT anim AND
	# the fallback "attack 2" path land here.
	if state == State.ULT:
		if not _ult_dealt_this_anim:
			_apply_ult_damage()
			_ult_dealt_this_anim = true
		_clear_telegraph()
		attack_cd = maxf(attack_cd, 0.6)
		_enter_idle()
		return
	if anim == ANIM_SWIPE or anim == ANIM_SLAM:
		if hit_area:
			hit_area.monitoring = false
		attack_cd = attack_cooldown
		_enter_idle()
	elif anim == ANIM_SHOOT:
		# Safety net: if release_frame was set past the anim length, the orb
		# never spawned — conjure it now so the cast still produces a shot.
		if not _shoot_fired:
			_spawn_floating_projectile()
			_shoot_fired = true
		_launch_floating_projectile()
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
	# In-world HP bar is suppressed for the boss — the top-center BossHealthUI
	# shows HP. The HealthBar node still exists so StatusEffectBar can attach
	# to it, but its draw is invisible.
	health_bar.visible = false
	_play_anim(ANIM_IDLE)
	_start_ambient_sfx()
	# Boss has actually appeared — bring the BGM back in. MusicManager faded
	# it out when room_4 loaded; this is the cue to swell back up.
	if Engine.has_singleton("MusicManager") or get_node_or_null("/root/MusicManager"):
		var mm := get_node_or_null("/root/MusicManager")
		if mm and mm.has_method("boss_spawn_fade_in"):
			mm.boss_spawn_fade_in()


func _on_detection_area_body_entered(body: Node2D) -> void:
	if _locked:
		return
	if not body.is_in_group("player"):
		return
	_player_ref = body
	if state == State.DORMANT:
		spawn_at(global_position)


func unleash() -> void:
	# Called by RitualManager once the rituals are done. Just drops the lock
	# — the boss STAYS dormant + invisible until the player crosses its
	# detection area. This way the player has to actually approach the arena
	# center to start the fight; rituals only "arm" it.
	_locked = false
	# Re-check overlap in case the player is already standing in the
	# detection area when the rituals finished (e.g. the 3rd book was nearby).
	_check_initial_player_overlap()


# --- Damage to player on contact during attack ------------------------------

func _on_hit_area_body_entered(body: Node2D) -> void:
	if _attack_dealt_this_anim:
		return
	if not body.is_in_group("player"):
		return
	if not body.has_method("take_damage"):
		return
	# Damage geometry MUST match the visible telegraph cone:
	#   swipe → 55° half-arc, range = melee_range (130)
	#   slam  → 90° half-arc, range = slam_range  (220)
	# hit_area's CircleShape2D was enlarged to slam_range so the swipe path
	# also needs an explicit range gate — without it, a swipe could hit a
	# player at 200px even though the swipe telegraph only reaches 130.
	var arc_deg: float
	var max_range: float
	var dmg: int
	match state:
		State.SWIPE:
			arc_deg = 55.0
			max_range = melee_range
			dmg = swipe_damage
		State.SLAM:
			arc_deg = 90.0
			max_range = slam_range
			dmg = slam_damage
		_:
			return  # not in an attacking state — ignore stray overlaps

	var to_body: Vector2 = body.global_position - global_position
	var dist: float = to_body.length()
	if dist > max_range:
		return
	if dist > 1.0:
		var face: Vector2 = _facing_vector()
		var angle_diff: float = absf(to_body.normalized().angle_to(face))
		if angle_diff > deg_to_rad(arc_deg):
			return
	# SLAM doesn't grant the parry stun — only SWIPE does. Player can still
	# block the SLAM's damage by raising shield in time, but the boss won't
	# get punished for it (telegraph too readable to deserve the reward).
	var stun_on_block: bool = (state == State.SWIPE)
	body.take_damage(dmg, stun_on_block)
	_attack_dealt_this_anim = true


# --- Audio ------------------------------------------------------------------

func _setup_flail_sfx() -> void:
	# Mixkit "Arcane chain spell" — chain swing for normal attacks. Stream is
	# 5.5s but only the chain-rattle attack portion is used per swing (we
	# stop()+play() each attack, so it's never allowed to finish).
	var stream: AudioStream = load("res://assets/sfx/golem_flail.mp3")
	if stream == null:
		return
	_flail_sfx = AudioStreamPlayer.new()
	_flail_sfx.stream = stream
	_flail_sfx.volume_db = -6.0
	_flail_sfx.bus = "Master"
	add_child(_flail_sfx)


func _play_flail_sfx() -> void:
	if not is_instance_valid(_flail_sfx):
		return
	# Cut any previous play so chained swings sound crisp instead of stacking.
	_flail_sfx.stop()
	_flail_sfx.pitch_scale = randf_range(0.93, 1.07)
	# Skip the file's leading magical-wind intro so the chain rattle drops
	# exactly when the swing lands on screen.
	_flail_sfx.play(maxf(flail_sfx_start_offset, 0.0))


func _setup_ambient_sfx() -> void:
	# Mixkit "Bass rumble hum" — positional rocky drone. AudioStreamPlayer2D
	# attenuates by distance from the listener (player camera) so the player
	# hears it loud when close, fades to silence when far. Loops forever.
	var stream: AudioStream = load("res://assets/sfx/golem_ambient.mp3")
	if stream == null:
		return
	# AudioStreamMP3 supports loop flag at runtime; toggle so the 7s clip
	# repeats seamlessly while the boss is alive.
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	_ambient_sfx = AudioStreamPlayer2D.new()
	_ambient_sfx.stream = stream
	_ambient_sfx.volume_db = -8.0
	_ambient_sfx.max_distance = 900.0       # past this → silent
	_ambient_sfx.attenuation = 1.4          # falloff steepness — higher = quieter sooner
	_ambient_sfx.bus = "Master"
	# Don't autoplay — start it on spawn_at() so it doesn't broadcast from a
	# locked, invisible boss before the encounter begins.
	add_child(_ambient_sfx)


func _start_ambient_sfx() -> void:
	if is_instance_valid(_ambient_sfx) and not _ambient_sfx.playing:
		_ambient_sfx.play()


func _stop_ambient_sfx() -> void:
	if is_instance_valid(_ambient_sfx) and _ambient_sfx.playing:
		_ambient_sfx.stop()


# --- Inner class: red telegraph cone ---------------------------------------

class _AttackTelegraph extends Node2D:
	var is_swipe: bool = true
	var is_circle: bool = false           # ult mode — full radial AoE
	var facing_vector: Vector2 = Vector2.RIGHT
	var range_value: float = 130.0
	var duration: float = 0.4
	var elapsed: float = 0.0

	func _ready() -> void:
		z_index = 4
		set_process(true)

	func _process(delta: float) -> void:
		elapsed += delta
		queue_redraw()

	func _draw() -> void:
		var t: float = clampf(elapsed / maxf(duration, 0.001), 0.0, 1.0)
		var pulse: float = 0.5 + 0.5 * sin(elapsed * 16.0)
		var fill_alpha: float = clampf(0.18 + 0.18 * pulse + 0.30 * t, 0.0, 0.78)

		if is_circle:
			# ULT: big saturated red disc + thick pulsing rim. Pulses brighter
			# as impact nears so the player has a clear "GET OUT NOW" cue.
			var ult_fill := Color(1.00, 0.08, 0.08, clampf(fill_alpha + 0.05, 0.0, 0.85))
			var ult_rim  := Color(1.00, 0.20, 0.10, clampf(0.55 + 0.45 * t + 0.2 * pulse, 0.7, 1.0))
			draw_circle(Vector2.ZERO, range_value, ult_fill)
			# Outer rim (thick) + inner glow ring for readability.
			var n: int = 64
			var rim_pts: PackedVector2Array = PackedVector2Array()
			var inner_pts: PackedVector2Array = PackedVector2Array()
			var inner_r: float = range_value * (0.86 + 0.04 * pulse)
			for i in range(n):
				var a: float = TAU * float(i) / float(n)
				var u: Vector2 = Vector2(cos(a), sin(a))
				rim_pts.append(u * range_value)
				inner_pts.append(u * inner_r)
			for i in range(n):
				draw_line(rim_pts[i], rim_pts[(i + 1) % n], ult_rim, 4.0)
				draw_line(inner_pts[i], inner_pts[(i + 1) % n], Color(1.0, 0.6, 0.3, 0.45 * pulse), 2.0)
			return

		# Slam telegraph leans purple to match the golem palette; swipe stays red.
		var hue: Color = Color(0.85, 0.18, 0.95, fill_alpha) if not is_swipe else Color(1.00, 0.18, 0.16, fill_alpha)
		var border_color: Color = Color(hue.r, hue.g, hue.b, clampf(0.5 + 0.5 * t, 0.6, 1.0))

		var ang: float = facing_vector.angle()
		var half_arc: float = deg_to_rad(55.0 if is_swipe else 90.0)
		var n_cone: int = 22
		var pts: PackedVector2Array = PackedVector2Array()
		pts.append(Vector2.ZERO)
		for i in range(n_cone + 1):
			var a2: float = ang - half_arc + (2.0 * half_arc) * float(i) / float(n_cone)
			pts.append(Vector2(cos(a2), sin(a2)) * range_value)
		draw_colored_polygon(pts, hue)
		for i in range(pts.size()):
			draw_line(pts[i], pts[(i + 1) % pts.size()], border_color, 2.0)
