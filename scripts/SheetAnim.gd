extends Sprite2D
# Lightweight horizontal-strip animator. Use for ambient decorations
# (animated eyes, tentacles, veins) without having to build a full
# SpriteFrames resource per asset. Point `sheet` at a horizontal
# spritesheet, set `frame_w`/`frame_h`/`frame_count`, and the node
# cycles through frames at `fps`. Each instance starts on a random
# frame so identical decorations don't blink in unison.

@export var sheet: Texture2D
@export var frame_w: int = 32
@export var frame_h: int = 32
@export var frame_count: int = 8
@export var fps: float = 8.0
@export var randomize_start: bool = true

var _t: float = 0.0


func _ready() -> void:
	if sheet:
		texture = sheet
		region_enabled = true
	if randomize_start:
		_t = randf() * float(frame_count) / maxf(fps, 0.001)
	_update_region()


func _process(delta: float) -> void:
	_t += delta
	_update_region()


func _update_region() -> void:
	if texture == null:
		return
	var f: int = int(_t * fps) % maxi(frame_count, 1)
	region_rect = Rect2(f * frame_w, 0, frame_w, frame_h)
