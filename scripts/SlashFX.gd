extends AnimatedSprite2D
# One-shot pixelated slash effect. Auto-frees when the animation ends.
# Spawned by enemy attacks; rotation should be set by the caller to align
# with the attack direction (default sprite arc opens to the right / +x).


func _ready() -> void:
	animation_finished.connect(queue_free)
	# Slight random tilt for variety so successive slashes don't look identical.
	rotation += randf_range(-0.12, 0.12)
	scale *= randf_range(0.9, 1.15)
	play()
