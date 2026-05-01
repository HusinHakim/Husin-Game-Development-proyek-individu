extends Area2D
# Simple portal: when the player walks onto the area, opens a styled
# ProceedDialog asking whether to continue to the next scene.
#
# Used by main-menu / hub portals where there's no enemy gating.
# For gameplay rooms that need "kill all enemies first + press F",
# use scenes/Interactable.tscn instead.

signal proceed_confirmed
signal proceed_cancelled

@export_file("*.tscn") var next_scene_path: String = ""
@export var dialog_title: String = "Proceed"
@export var dialog_message: String = "Do you want to proceed to the next room?"

# Kept for backward-compat with old scenes that set this property; ignored.
@export var require_enemies_defeated: bool = false

const PROCEED_DIALOG_PATH: String = "res://scenes/ProceedDialog.tscn"

var _player: Node2D = null
var _dialog_open: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Hide any legacy inline dialog left over in older scenes.
	var legacy: CanvasLayer = get_node_or_null("DialogLayer")
	if legacy:
		legacy.visible = false


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player = body
	if _dialog_open:
		return
	_open_dialog()


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player = null


func _open_dialog() -> void:
	_dialog_open = true
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
		print("[Portal] Confirmed — next_scene_path empty.")
		_close_dialog_state()


func _on_dialog_cancelled() -> void:
	proceed_cancelled.emit()
	_close_dialog_state()


func _close_dialog_state() -> void:
	_dialog_open = false
	if is_instance_valid(_player):
		_player.set_physics_process(true)
