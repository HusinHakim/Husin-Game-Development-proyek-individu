class_name StatusEffectBar
extends Node2D

# Drawn as child of the enemy's HealthBar node.
# Order matters: bar drawn FIRST (background), then label LAST — otherwise
# the bar's rect call paints over the text.

var total_duration: float = 1.0
var remaining: float = 1.0
var label_text: String = "EFFECT"
var bar_color: Color = Color(0.35, 0.7, 1.0, 0.95)

# Default size — readable on cult enemies at zoom 3x. The boss caller passes
# a size_scale to setup() to render a smaller bar (so it doesn't overwhelm
# the larger boss sprite + sit alongside the boss HP UI at the top).
const BAR_W      := 160.0
const BAR_H      := 14.0
const BAR_TOP_Y  := -20.0   # tucked just above HP bar (HP bar starts at y=0)
const LABEL_Y    := -26.0   # text baseline hugs the timer bar
const FONT_SZ    := 24
const OUTLINE_PX := 4

var size_scale: float = 1.0   # multiplier applied to all dimensions in _draw


func setup(duration: float, text: String, color: Color, scale_factor: float = 1.0) -> void:
	total_duration = duration
	remaining = duration
	label_text = text.to_upper()
	bar_color = color
	size_scale = scale_factor
	z_index = 10  # ensure it draws above sibling nodes


func _process(delta: float) -> void:
	remaining -= delta
	if remaining <= 0.0:
		queue_free()
	else:
		queue_redraw()


func _draw() -> void:
	# Apply per-instance scale to all geometry — boss passes ~0.55 to render
	# a compact bar, cult enemies use the default 1.0 for full readability.
	var w: float       = BAR_W * size_scale
	var h: float       = BAR_H * size_scale
	var bar_y: float   = BAR_TOP_Y * size_scale
	var label_y: float = LABEL_Y * size_scale
	var fs: int        = maxi(int(round(FONT_SZ * size_scale)), 8)
	var outline: int   = maxi(int(round(OUTLINE_PX * size_scale)), 1)
	var ratio          := clampf(remaining / total_duration, 0.0, 1.0)
	var half           := w * 0.5

	# 1) Timer bar — drawn FIRST so the label can overlay it
	draw_rect(Rect2(-half, bar_y, w, h), Color(0.07, 0.08, 0.14, 0.92))
	if ratio > 0.0:
		draw_rect(Rect2(-half, bar_y, w * ratio, h), bar_color)
	draw_rect(Rect2(-half, bar_y, w, h), Color(0.25, 0.5, 0.85, 1.0), false, maxf(size_scale, 1.0))

	# 2) Label "ENTANGLED" — drawn LAST with thick outline for visibility
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var pos := Vector2(-half, label_y)
	draw_string_outline(
		font, pos, label_text, HORIZONTAL_ALIGNMENT_CENTER, w,
		fs, outline, Color(0.05, 0.04, 0.08, 1.0)
	)
	draw_string(
		font, pos, label_text, HORIZONTAL_ALIGNMENT_CENTER, w,
		fs, Color(0.7, 0.95, 1.0, 1.0)
	)
