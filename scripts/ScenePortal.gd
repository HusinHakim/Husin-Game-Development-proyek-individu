extends Area2D
# A visible portal that continuously breathes (alpha pulse) and triggers a
# fade-to-black scene transition when the player overlaps it. No dialog, no
# button press — touching the portal starts the transition. Use this when
# you want an atmospheric scene exit instead of the prompt-driven Interactable.

@export_file("*.tscn") var next_scene_path: String = ""
@export var portal_radius: float = 48.0
@export var pulse_period: float = 2.6           # full breathe cycle in seconds
@export var min_alpha: float = 0.45             # darkest point of the breathe
@export var max_alpha: float = 1.00             # brightest point
@export var fade_duration: float = 1.6          # seconds for the black fade-out
@export var require_enemies_defeated: bool = false  # gates trigger AND visibility
@export var reveal_duration: float = 1.5        # how long the portal fades in once enemies die

const C_RING_OUTER := Color(0.65, 0.30, 1.00)
const C_RING_INNER := Color(0.95, 0.65, 1.00)
const C_CORE       := Color(0.20, 0.05, 0.35)

var _t: float = 0.0
var _triggered: bool = false
var _player: Node2D = null
var _revealed: bool = false      # true once the appear-fade finished
var _revealing: bool = false     # true while the appear-fade is running


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	# Hide + disable interactions until enemies are dead. If gating is off,
	# stay visible from the start (matches old behavior).
	if require_enemies_defeated:
		modulate.a = 0.0
		monitoring = false
	else:
		_revealed = true
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	# Watch for the "all enemies dead" condition once, then start the fade-in.
	if require_enemies_defeated and not _revealed and not _revealing:
		if _all_enemies_dead():
			_start_reveal()
	queue_redraw()


func _start_reveal() -> void:
	_revealing = true
	# Re-enable Area2D detection AFTER the fade so the player can't trigger it
	# by walking through an invisible portal.
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, reveal_duration)
	tw.tween_callback(func():
		monitoring = true
		_revealed = true
		_revealing = false
	)


# ── Visuals ───────────────────────────────────────────────────────────────────

func _draw() -> void:
	# Single sine-driven alpha pulse — keeps draw self-contained.
	var phase: float = sin((_t / maxf(pulse_period, 0.01)) * TAU)
	var a: float = lerpf(min_alpha, max_alpha, 0.5 + 0.5 * phase)

	var r: float = portal_radius
	# Dark inner core
	draw_circle(Vector2.ZERO, r * 0.45, Color(C_CORE.r, C_CORE.g, C_CORE.b, a * 0.85))
	# Inner ring (bright)
	_draw_ring(r * 0.65, 4.0, Color(C_RING_INNER.r, C_RING_INNER.g, C_RING_INNER.b, a))
	# Outer ring (rotating swirl effect — different speed per ring for parallax)
	_draw_dashed_ring(r * 0.95, 3.0, Color(C_RING_OUTER.r, C_RING_OUTER.g, C_RING_OUTER.b, a * 0.85), 24, _t * 0.8)
	_draw_dashed_ring(r * 1.20, 2.0, Color(C_RING_OUTER.r, C_RING_OUTER.g, C_RING_OUTER.b, a * 0.55), 36, -_t * 0.6)


func _draw_ring(radius: float, width: float, color: Color) -> void:
	var n: int = 48
	for i in range(n):
		var a0: float = TAU * float(i) / float(n)
		var a1: float = TAU * float(i + 1) / float(n)
		draw_line(
			Vector2(cos(a0), sin(a0)) * radius,
			Vector2(cos(a1), sin(a1)) * radius,
			color, width
		)


func _draw_dashed_ring(radius: float, width: float, color: Color, segments: int, rot: float) -> void:
	# Half the segments draw as dashes, half as gaps — gives the rotating swirl feel.
	for i in range(segments):
		if i % 2 == 1:
			continue
		var a0: float = rot + TAU * float(i) / float(segments)
		var a1: float = rot + TAU * float(i + 1) / float(segments)
		draw_line(
			Vector2(cos(a0), sin(a0)) * radius,
			Vector2(cos(a1), sin(a1)) * radius,
			color, width
		)


# ── Trigger ───────────────────────────────────────────────────────────────────

func _on_body_entered(body: Node2D) -> void:
	if _triggered:
		return
	if not body.is_in_group("player"):
		return
	if require_enemies_defeated and not _all_enemies_dead():
		return
	_player = body
	_triggered = true
	_run_fade_and_change()


func _all_enemies_dead() -> bool:
	# Lazy version of Interactable's check — if anything's still in "enemy"
	# (boss included), the gate stays closed.
	for n in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(n):
			return false
	return true


func _run_fade_and_change() -> void:
	# Lock the player so they don't keep moving during the fade.
	if is_instance_valid(_player):
		_player.set_physics_process(false)

	# Spawn a fullscreen black ColorRect on a high-layer CanvasLayer so it
	# covers HUD too. Tween its alpha 0 → 1, then swap scenes.
	var layer := CanvasLayer.new()
	layer.layer = 100
	get_tree().current_scene.add_child(layer)
	var rect := ColorRect.new()
	rect.color = Color(0, 0, 0, 0)
	rect.position = Vector2.ZERO
	var vp := Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height")
	)
	rect.size = vp
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(rect)

	var tw := create_tween()
	tw.tween_property(rect, "color:a", 1.0, fade_duration)
	tw.tween_callback(func():
		if next_scene_path != "":
			get_tree().change_scene_to_file(next_scene_path)
		else:
			push_warning("[ScenePortal] next_scene_path is empty — no scene change.")
			# Fade back in so the player isn't stuck on a black screen.
			var tw2 := create_tween()
			tw2.tween_property(rect, "color:a", 0.0, fade_duration)
			tw2.tween_callback(func():
				layer.queue_free()
				if is_instance_valid(_player):
					_player.set_physics_process(true)
				_triggered = false
			)
	)
