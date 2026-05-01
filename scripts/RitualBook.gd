extends Area2D
# A ritual book/altar the player can interact with by pressing E. Each book
# can be completed exactly once; on completion it emits `ritual_completed`
# (RitualManager listens) and visually dims to show it's been read.

signal ritual_completed(book: Node)

@export var book_index: int = 1            # 1..3 — purely informational (manager numbers from order)

@onready var sprite: Sprite2D = $Sprite
@onready var prompt: Label = $Prompt
@onready var glow: Node2D = $Glow

var _player_in: bool = false
var _completed: bool = false
var _t: float = 0.0


func _ready() -> void:
	add_to_group("ritual_book")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	set_process(true)
	if prompt:
		prompt.visible = false


func _process(delta: float) -> void:
	_t += delta
	# Pulse the glow while unread; once read, glow stays hidden.
	if is_instance_valid(glow) and not _completed:
		glow.modulate.a = 0.45 + 0.30 * sin(_t * 2.6)
	# Bob the prompt slightly so it reads as floating UI rather than decor.
	if is_instance_valid(prompt) and prompt.visible:
		prompt.position.y = -56.0 + 3.0 * sin(_t * 4.0)


func _unhandled_input(event: InputEvent) -> void:
	if _completed or not _player_in:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		_complete()


func _complete() -> void:
	_completed = true
	if is_instance_valid(prompt):
		prompt.visible = false
	if is_instance_valid(glow):
		glow.visible = false
	if is_instance_valid(sprite):
		# Dim the sprite — clear visual cue that this one is done.
		sprite.modulate = Color(0.45, 0.42, 0.50, 1.0)
	ritual_completed.emit(self)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_in = true
	if not _completed and is_instance_valid(prompt):
		prompt.visible = true


func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_in = false
	if is_instance_valid(prompt):
		prompt.visible = false
