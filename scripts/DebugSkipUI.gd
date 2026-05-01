extends CanvasLayer
# Debug-only "Skip Wave" button in the top-right corner. Kills every enemy
# in the "enemy" group instantly so the rest of the room flow can be tested
# without actually fighting. Disable / remove for production.

@onready var btn: Button = $Margin/Button


func _ready() -> void:
	# Show ONLY in the Godot editor. Any exported build (debug or release)
	# hides the button — `OS.has_feature("editor")` is the ONE flag that's
	# guaranteed false outside the editor, regardless of the "Export With
	# Debug" checkbox state in the file dialog.
	print("[DebugSkipUI] editor=", OS.has_feature("editor"), " debug_build=", OS.is_debug_build())
	if not OS.has_feature("editor"):
		queue_free()
		return
	layer = 30
	btn.pressed.connect(_on_skip_pressed)


func _on_skip_pressed() -> void:
	var deaths_fired: int = 0
	for n in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(n):
			continue

		# Fire phantom `died` signals for any remaining respawn lives so the
		# kill counter (which sums 1+respawn_count up-front) catches up.
		var respawns_left: int = 0
		if "respawn_count" in n:
			respawns_left = maxi(int(n.respawn_count), 0)
		if n.has_signal("died"):
			for i in respawns_left:
				n.emit_signal("died")
				deaths_fired += 1

		# Force the next take_damage to be terminal (no further respawn).
		if "respawn_count" in n:
			n.respawn_count = 0

		if n.has_method("take_damage"):
			var hp_value: int = 99999
			if "max_hp" in n:
				hp_value = int(n.max_hp) + 1
			n.take_damage(hp_value)   # emits one final `died` + queue_free
			deaths_fired += 1
		else:
			if n.has_signal("died"):
				n.emit_signal("died")
				deaths_fired += 1
			n.queue_free()

	print("[DebugSkip] Fired %d death signals (incl. phantom respawns)." % deaths_fired)
	btn.disabled = true
	btn.text = "Skipped"
