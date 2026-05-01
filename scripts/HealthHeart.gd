class_name HealthHeart
extends Area2D

@export var heart_color: Color = Color(0.92, 0.15, 0.15, 1.0)
@export var heal_amount: int = 1

const SIZE := 5
const OUTLINE_COLOR := Color(0.18, 0.06, 0.06, 1.0)

var _time: float = 0.0


func _ready() -> void:
	add_to_group("health_heart")
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if body.has_method("heal"):
		body.heal(heal_amount)
	queue_free()


func _draw() -> void:
	var pulse := 1.0 + 0.07 * sin(_time * 3.2)
	var s := SIZE * pulse

	# Soft glow halo
	draw_circle(
		Vector2.ZERO,
		s * 1.6,
		Color(heart_color.r * 0.7, heart_color.g * 0.7, heart_color.b * 0.7, 0.22)
	)
	# Dark outline (slightly larger heart)
	_draw_heart(Vector2.ZERO, s * 1.18, OUTLINE_COLOR)
	# Filled heart
	_draw_heart(Vector2.ZERO, s, heart_color)
	# Highlight dot
	draw_circle(Vector2(-s * 0.2, -s * 0.32), s * 0.16, Color(1.0, 1.0, 1.0, 0.6))


func _draw_heart(center: Vector2, size: float, color: Color) -> void:
	# Two circles for upper lobes
	draw_circle(center + Vector2(-size * 0.27, -size * 0.15), size * 0.40, color)
	draw_circle(center + Vector2( size * 0.27, -size * 0.15), size * 0.40, color)
	# Triangle that forms the bottom point
	var pts := PackedVector2Array([
		center + Vector2(-size * 0.62, -size * 0.10),
		center + Vector2( size * 0.62, -size * 0.10),
		center + Vector2( 0.0,           size * 0.62),
	])
	draw_colored_polygon(pts, color)
