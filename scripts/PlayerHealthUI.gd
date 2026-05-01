extends Node2D

var max_hp: int = 3
var current_hp: int = 3

const HEART_SIZE: float = 14.0
const HEART_SPACING: float = 36.0
# Pushed above the 80px-tall inventory bar (bottom margin 12) + gap
const BOTTOM_MARGIN: float = 110.0


func set_hp(value: int, maximum: int) -> void:
	current_hp = clampi(value, 0, maximum)
	max_hp = maximum
	queue_redraw()


func _draw() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var total_width: float = (max_hp - 1) * HEART_SPACING
	var start_x: float = vp.x * 0.5 - total_width * 0.5
	var y: float = vp.y - BOTTOM_MARGIN

	for i in range(max_hp):
		var cx: float = start_x + i * HEART_SPACING
		var center := Vector2(cx, y)
		if i < current_hp:
			_draw_heart(center, HEART_SIZE, Color(0.92, 0.12, 0.12))
		else:
			_draw_heart(center, HEART_SIZE, Color(0.25, 0.08, 0.08))


func _draw_heart(center: Vector2, size: float, color: Color) -> void:
	# Two circles for upper lobes
	draw_circle(center + Vector2(-size * 0.27, -size * 0.15), size * 0.38, color)
	draw_circle(center + Vector2( size * 0.27, -size * 0.15), size * 0.38, color)
	# Bottom triangle to form the point
	var pts := PackedVector2Array([
		center + Vector2(-size * 0.6,  -size * 0.1),
		center + Vector2( size * 0.6,  -size * 0.1),
		center + Vector2(0.0,           size * 0.58),
	])
	draw_colored_polygon(pts, color)
