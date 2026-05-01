extends Node2D
# AimArrow — translucent guideline arrow from the player toward the mouse.
# Spawned as a child of Player. Player toggles `visible` based on whether a
# throwable is currently in the active slot. Local space: drawn along +X,
# rotated each frame so +X aligns with the player→mouse vector.

@export var length: float = 90.0           # arrow shaft length (in player local px)
@export var head_size: float = 12.0
@export var color: Color = Color(1.0, 0.95, 0.55, 0.85)

var _t: float = 0.0


func _ready() -> void:
	z_index = 2     # above player sprite (1), below shield (50)
	z_as_relative = false
	set_process(true)
	# Counter-scale the parent so the arrow renders at consistent world size
	# regardless of how heavily the player is scaled in any given room.
	var parent := get_parent()
	if parent is Node2D:
		var s: Vector2 = (parent as Node2D).scale
		if absf(s.x) > 0.001 and absf(s.y) > 0.001:
			scale = Vector2(1.0 / s.x, 1.0 / s.y)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	# Subtle pulse so the arrow reads as "active UI hint", not solid HUD geometry.
	var pulse: float = 0.75 + 0.25 * sin(_t * 6.0)
	var c: Color = Color(color.r, color.g, color.b, color.a * pulse)
	var c_dark: Color = Color(0.25, 0.18, 0.05, color.a * 0.7 * pulse)

	var start: Vector2 = Vector2(18.0, 0.0)        # offset away from player center
	var end: Vector2 = Vector2(length, 0.0)

	# Dashed shaft — short segments alternating with gaps for "guideline" feel.
	var seg: float = 8.0
	var gap: float = 6.0
	var x: float = start.x
	while x < end.x - head_size * 0.6:
		var x2: float = minf(x + seg, end.x - head_size * 0.6)
		# Outline (dark) underneath for contrast over light backgrounds.
		draw_line(Vector2(x, 0.0), Vector2(x2, 0.0), c_dark, 5.0)
		draw_line(Vector2(x, 0.0), Vector2(x2, 0.0), c, 3.0)
		x += seg + gap

	# Arrow head — filled triangle with dark outline.
	var tip: Vector2 = end
	var p1: Vector2 = end + Vector2(-head_size, -head_size * 0.7)
	var p2: Vector2 = end + Vector2(-head_size,  head_size * 0.7)
	var head_pts := PackedVector2Array([tip, p1, p2])
	draw_colored_polygon(head_pts, c)
	# Outline
	draw_line(tip, p1, c_dark, 2.0)
	draw_line(tip, p2, c_dark, 2.0)
	draw_line(p1, p2, c_dark, 2.0)
