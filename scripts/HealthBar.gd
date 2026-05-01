extends Node2D

const BAR_WIDTH: float = 100.0
const BAR_HEIGHT: float = 10.0
const BORDER: float = 1.5

var _ratio: float = 1.0


func set_hp(current: int, maximum: int) -> void:
	_ratio = clampf(float(current) / float(maximum), 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	var half: float = BAR_WIDTH * 0.5
	# Border / background
	draw_rect(Rect2(-half - BORDER, -BORDER, BAR_WIDTH + BORDER * 2.0, BAR_HEIGHT + BORDER * 2.0), Color(0.05, 0.05, 0.05, 0.9))
	# Gray background
	draw_rect(Rect2(-half, 0.0, BAR_WIDTH, BAR_HEIGHT), Color(0.25, 0.25, 0.25, 0.85))
	# Red health fill
	if _ratio > 0.0:
		draw_rect(Rect2(-half, 0.0, BAR_WIDTH * _ratio, BAR_HEIGHT), Color(0.88, 0.1, 0.1, 0.95))
