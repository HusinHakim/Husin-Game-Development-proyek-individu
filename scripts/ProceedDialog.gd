extends CanvasLayer
# Modal confirmation dialog with dim backdrop and styled panel.
# Emits `confirmed` or `cancelled` based on user choice. Free with `close()`.

signal confirmed
signal cancelled

@export var title_text: String = "Proceed"
@export var message_text: String = "Do you want to proceed to the next room?"
@export var confirm_text: String = "Yes"
@export var cancel_text: String = "No"

@onready var dim: ColorRect = $Dim
@onready var panel: Panel = $Center/Panel
@onready var title_label: Label = $Center/Panel/Margin/VBox/Title
@onready var message_label: Label = $Center/Panel/Margin/VBox/Message
@onready var btn_yes: Button = $Center/Panel/Margin/VBox/Buttons/BtnYes
@onready var btn_no: Button = $Center/Panel/Margin/VBox/Buttons/BtnNo


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS    # operate even if game paused
	title_label.text = title_text
	message_label.text = message_text
	btn_yes.text = confirm_text
	btn_no.text = cancel_text
	btn_yes.pressed.connect(_on_yes)
	btn_no.pressed.connect(_on_no)
	btn_no.grab_focus()                          # default-safe focus

	# Fade-in
	dim.modulate.a = 0.0
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.92, 0.92)
	panel.pivot_offset = panel.size * 0.5
	var tw := create_tween().set_parallel(true)
	tw.tween_property(dim, "modulate:a", 1.0, 0.18)
	tw.tween_property(panel, "modulate:a", 1.0, 0.22)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ENTER, KEY_KP_ENTER, KEY_Y:
				_on_yes()
				get_viewport().set_input_as_handled()
			KEY_ESCAPE, KEY_N:
				_on_no()
				get_viewport().set_input_as_handled()


func _on_yes() -> void:
	confirmed.emit()
	close()


func _on_no() -> void:
	cancelled.emit()
	close()


func close() -> void:
	# Fade-out then queue_free.
	var tw := create_tween().set_parallel(true)
	tw.tween_property(dim, "modulate:a", 0.0, 0.15)
	tw.tween_property(panel, "modulate:a", 0.0, 0.15)
	tw.tween_property(panel, "scale", Vector2(0.92, 0.92), 0.15)
	tw.chain().tween_callback(queue_free)
