extends Node2D
# Horizontal stamina bar drawn above the hearts row.
# Flashes red briefly when an action is rejected for insufficient stamina.

const BAR_WIDTH: float = 220.0
const BAR_HEIGHT: float = 14.0
const BOTTOM_MARGIN: float = 138.0          # sits above hearts (which use 110)
const FLASH_DURATION: float = 0.25
const BG_COLOR: Color = Color(0.10, 0.10, 0.12, 0.85)
const BORDER_COLOR: Color = Color(0.05, 0.05, 0.06, 1.0)
const FILL_COLOR: Color = Color(0.30, 0.85, 0.45, 0.95)
const LOW_FILL_COLOR: Color = Color(0.95, 0.65, 0.20, 0.95)
const FLASH_COLOR: Color = Color(1.0, 0.20, 0.20, 1.0)

var max_stamina: float = 100.0
var current_stamina: float = 100.0
var _flash_t: float = 0.0


func set_stamina(value: float, maximum: float) -> void:
	max_stamina = maxf(maximum, 1.0)
	current_stamina = clampf(value, 0.0, max_stamina)
	queue_redraw()


func flash() -> void:
	_flash_t = FLASH_DURATION
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	if _flash_t <= 0.0:
		set_process(false)
		queue_redraw()
		return
	_flash_t -= delta
	queue_redraw()


func _draw() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var x: float = vp.x * 0.5 - BAR_WIDTH * 0.5
	var y: float = vp.y - BOTTOM_MARGIN

	# Background + border
	draw_rect(Rect2(x - 2.0, y - 2.0, BAR_WIDTH + 4.0, BAR_HEIGHT + 4.0), BORDER_COLOR, true)
	draw_rect(Rect2(x, y, BAR_WIDTH, BAR_HEIGHT), BG_COLOR, true)

	# Fill
	var ratio: float = current_stamina / max_stamina
	var fill_w: float = BAR_WIDTH * ratio
	var fill_color: Color = FILL_COLOR
	if ratio < 0.25:
		fill_color = LOW_FILL_COLOR
	if _flash_t > 0.0:
		# Blend toward flash color based on remaining time.
		var t: float = _flash_t / FLASH_DURATION
		fill_color = fill_color.lerp(FLASH_COLOR, t)
		# Also flash the *background* slot briefly, so even an empty bar reads.
		var bg_flash: Color = BG_COLOR.lerp(FLASH_COLOR, t * 0.6)
		draw_rect(Rect2(x, y, BAR_WIDTH, BAR_HEIGHT), bg_flash, true)

	if fill_w > 0.0:
		draw_rect(Rect2(x, y, fill_w, BAR_HEIGHT), fill_color, true)
