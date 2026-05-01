extends Area2D

var speed: float = 250.0
var direction: Vector2 = Vector2.ZERO

@onready var visuals: Node2D = $Visuals
@onready var trail: CPUParticles2D = $Trail
@onready var light: PointLight2D = $Light
@onready var outer_glow: Sprite2D = $Visuals/OuterGlow

var _time: float = 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	$VisibleOnScreenNotifier2D.screen_exited.connect(queue_free)
	_play_cast_sfx()


func _play_cast_sfx() -> void:
	# Mixkit "Light spell" — royalty-free, commercial-OK, no attribution.
	# Spawn a transient AudioStreamPlayer so the sound finishes even if the
	# projectile is freed mid-flight (e.g. screen exit, player hit).
	var stream: AudioStream = load("res://assets/sfx/cult_cast.mp3")
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = -8.0
	p.pitch_scale = randf_range(0.92, 1.08)
	p.bus = "Master"
	# Parent to scene root so freeing the projectile doesn't cut the sound.
	var host: Node = get_tree().current_scene
	if host == null:
		host = self
	host.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func init(from: Vector2, to: Vector2) -> void:
	global_position = from
	direction = (to - from).normalized()
	trail.direction = -direction


func _physics_process(delta: float) -> void:
	_time += delta
	global_position += direction * speed * delta

	# Spin the orb layers at different speeds for a warping look
	visuals.rotation += delta * 5.0
	$Visuals/MidRing.rotation -= delta * 3.0

	# Pulse the light energy and glow scale
	var pulse: float = sin(_time * 8.0) * 0.2 + 0.85
	light.energy = pulse * 1.1
	outer_glow.scale = Vector2(2.5, 2.5) * (0.9 + sin(_time * 6.0) * 0.15)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		if body.has_method("take_damage"):
			body.take_damage(1)
		_explode()


func _explode() -> void:
	# Detach trail so it fades out naturally, then free the rest
	trail.emitting = false
	set_physics_process(false)
	visuals.visible = false
	light.visible = false
	# Wait for remaining trail particles to fade before freeing
	await get_tree().create_timer(0.35).timeout
	queue_free()
