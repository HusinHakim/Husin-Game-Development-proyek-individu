extends Area2D
# Generic interactable trigger. Attach to an Area2D wrapping any object
# (door, chest, NPC). When the player overlaps the area, a styled
# "[F] <label>" prompt floats above the object. Pressing F opens the
# ProceedDialog and emits proceed_confirmed / proceed_cancelled.

signal proceed_confirmed
signal proceed_cancelled
signal interacted               # fired the moment F is pressed (before dialog)

@export_file("*.tscn") var next_scene_path: String = ""
@export var require_enemies_defeated: bool = false
@export var hide_when_locked: bool = true
@export var prompt_offset: Vector2 = Vector2(0, -56)
@export_range(0.05, 2.0, 0.05) var prompt_scale: float = 1.0
@export var prompt_label: String = "Open"
@export var dialog_title: String = "Proceed"
@export var dialog_message: String = "Do you want to proceed to the next room?"
@export var interact_keycode: int = KEY_F
@export var lock_message: String = "Defeat all enemies first"

const PROCEED_DIALOG_PATH: String = "res://scenes/ProceedDialog.tscn"

var _player: Node2D = null
var _prompt: Node2D = null
var _dialog_open: bool = false
var _is_locked: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	_prompt = _InteractPrompt.new()
	_prompt.position = prompt_offset
	_prompt.scale = Vector2(prompt_scale, prompt_scale)
	_prompt.key_text = OS.get_keycode_string(interact_keycode)
	_prompt.label_text = prompt_label
	add_child(_prompt)

	if require_enemies_defeated:
		call_deferred("_scan_and_bind_enemies")


func _unhandled_input(event: InputEvent) -> void:
	if _player == null or _dialog_open:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.physical_keycode != interact_keycode:
		return
	if _is_locked:
		if not hide_when_locked:
			_prompt.shake()
		return
	_open_dialog()
	get_viewport().set_input_as_handled()


# --- Body callbacks ---------------------------------------------------------

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player = body
	_refresh_prompt_visibility()


func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player = null
	_prompt.hide_prompt()


func _refresh_prompt_visibility() -> void:
	if _player == null:
		_prompt.hide_prompt()
		return
	if _is_locked and hide_when_locked:
		_prompt.hide_prompt()
		return
	_prompt.set_locked(_is_locked, lock_message)
	_prompt.show_prompt()


# --- Dialog -----------------------------------------------------------------

func _open_dialog() -> void:
	interacted.emit()
	_dialog_open = true
	_prompt.hide_prompt()
	if is_instance_valid(_player):
		_player.set_physics_process(false)

	var scene: PackedScene = load(PROCEED_DIALOG_PATH)
	if scene == null:
		push_error("ProceedDialog scene missing at " + PROCEED_DIALOG_PATH)
		_close_dialog_state()
		return
	var dlg: CanvasLayer = scene.instantiate()
	dlg.title_text = dialog_title
	dlg.message_text = dialog_message
	get_tree().current_scene.add_child(dlg)
	dlg.confirmed.connect(_on_dialog_confirmed)
	dlg.cancelled.connect(_on_dialog_cancelled)


func _on_dialog_confirmed() -> void:
	proceed_confirmed.emit()
	if next_scene_path != "":
		get_tree().change_scene_to_file(next_scene_path)
	else:
		print("[Interactable] Confirmed — next_scene_path empty.")
		_close_dialog_state()


func _on_dialog_cancelled() -> void:
	proceed_cancelled.emit()
	_close_dialog_state()


func _close_dialog_state() -> void:
	_dialog_open = false
	if is_instance_valid(_player):
		_player.set_physics_process(true)
		_prompt.show_prompt()


# --- Lock gating ------------------------------------------------------------

func _scan_and_bind_enemies() -> void:
	var enemies: Array = get_tree().get_nodes_in_group("enemy")
	if enemies.is_empty():
		_is_locked = false
		_refresh_prompt_visibility()
		return
	_is_locked = true
	for n in enemies:
		if n.has_signal("died"):
			n.died.connect(_on_enemy_died)
	_refresh_prompt_visibility()


func _on_enemy_died() -> void:
	# `died` is emitted before the enemy actually queue_free's, so scanning the
	# group right now still sees the dying enemy. Defer the check to the next
	# frame, after all pending queue_free's have processed.
	await get_tree().process_frame
	if not is_instance_valid(self):
		return
	if _any_enemies_alive():
		return
	_is_locked = false
	_refresh_prompt_visibility()


func _any_enemies_alive() -> bool:
	for n in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(n):
			continue
		if n.is_queued_for_deletion():
			continue
		return true
	return false


func unlock_now() -> void:
	_is_locked = false
	if _player != null:
		_prompt.set_locked(false, prompt_label)


# --- Prompt UI (inline Node2D with custom _draw) ---------------------------

class _InteractPrompt extends Node2D:
	var key_text: String = "F"
	var label_text: String = "Open"
	var locked: bool = false
	var locked_text: String = ""
	var _shown: bool = false
	var _alpha: float = 0.0
	var _pulse: float = 0.0
	var _shake_t: float = 0.0

	func _ready() -> void:
		set_process(true)
		z_index = 50

	func _process(delta: float) -> void:
		var target: float = 1.0 if _shown else 0.0
		_alpha = move_toward(_alpha, target, delta * 8.0)
		_pulse += delta
		if _shake_t > 0.0:
			_shake_t -= delta
		queue_redraw()

	func show_prompt() -> void:
		_shown = true

	func hide_prompt() -> void:
		_shown = false

	func set_locked(is_locked: bool, message: String) -> void:
		locked = is_locked
		locked_text = message

	func shake() -> void:
		_shake_t = 0.35

	func _draw() -> void:
		if _alpha <= 0.005:
			return
		var font: Font = ThemeDB.fallback_font
		if font == null:
			return

		var fsize: int = 14
		var key_str: String = key_text
		var lbl_str: String = locked_text if locked else label_text

		var lbl_size: Vector2 = font.get_string_size(lbl_str, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize)
		var key_box: Vector2 = Vector2(20, 20)
		var pad: Vector2 = Vector2(12, 8)
		var inner_w: float = key_box.x + 8.0 + lbl_size.x
		var inner_h: float = maxf(key_box.y, float(fsize))
		var bg: Vector2 = Vector2(inner_w + pad.x * 2, inner_h + pad.y * 2)
		var bg_pos: Vector2 = -bg * 0.5

		# Bobbing & shake
		bg_pos.y += sin(_pulse * 3.0) * 2.0
		if _shake_t > 0.0:
			bg_pos.x += sin(_shake_t * 60.0) * 4.0

		# Drop shadow
		draw_rect(Rect2(bg_pos + Vector2(0, 3), bg), Color(0, 0, 0, 0.35 * _alpha), true)
		# BG
		var bg_color: Color = Color(0.45, 0.10, 0.10, 0.93 * _alpha) if locked else Color(0.07, 0.08, 0.12, 0.93 * _alpha)
		draw_rect(Rect2(bg_pos, bg), bg_color, true)
		# Border
		var border_color: Color = Color(0.95, 0.55, 0.30, _alpha) if locked else Color(0.83, 0.66, 0.32, _alpha)
		draw_rect(Rect2(bg_pos, bg), border_color, false, 2.0)

		# Key cap
		var key_pos: Vector2 = Vector2(bg_pos.x + pad.x, bg_pos.y + (bg.y - key_box.y) * 0.5)
		draw_rect(Rect2(key_pos, key_box), Color(0.97, 0.84, 0.42, _alpha), true)
		draw_rect(Rect2(key_pos, key_box), Color(0.30, 0.22, 0.08, _alpha), false, 1.5)
		# Key letter (centered)
		var key_letter_size: Vector2 = font.get_string_size(key_str, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize)
		var key_baseline_y: float = key_pos.y + (key_box.y + float(fsize)) * 0.5 - 2.0
		var key_baseline: Vector2 = Vector2(key_pos.x + (key_box.x - key_letter_size.x) * 0.5, key_baseline_y)
		draw_string(font, key_baseline, key_str, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0.10, 0.07, 0.02, _alpha))

		# Label text
		var lbl_baseline: Vector2 = Vector2(key_pos.x + key_box.x + 8.0, key_baseline_y)
		var lbl_color: Color = Color(1.0, 0.85, 0.85, _alpha) if locked else Color(0.98, 0.96, 0.92, _alpha)
		draw_string(font, lbl_baseline, lbl_str, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, lbl_color)
