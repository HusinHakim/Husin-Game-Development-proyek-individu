extends CanvasLayer
# Debug-only "Skip Rituals" button. Force-completes every unread RitualBook
# in the scene so RitualManager unleashes the boss without making the dev
# walk to and read each altar. Disable / remove for production.

@onready var btn: Button = $Margin/Button


func _ready() -> void:
	# Editor-only — exported builds (debug OR release) hide the button.
	if not OS.has_feature("editor"):
		queue_free()
		return
	layer = 30
	btn.pressed.connect(_on_skip_pressed)


func _on_skip_pressed() -> void:
	var completed: int = 0
	for n in get_tree().get_nodes_in_group("ritual_book"):
		if not is_instance_valid(n):
			continue
		# Skip already-read books — _complete() guards on its own but we
		# don't want to count them again toward `completed`.
		if "_completed" in n and n._completed:
			continue
		if n.has_method("_complete"):
			n._complete()
			completed += 1
	print("[DebugSkipRitual] Force-completed %d ritual book(s)." % completed)
	btn.disabled = true
	btn.text = "Skipped"
