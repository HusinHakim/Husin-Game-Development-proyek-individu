extends CanvasLayer
# Debug-only "Boss → 50% HP" button. Damages the first node in "boss" group
# down to (or below) the phase-2 threshold so the ult gets triggered without
# the dev needing to chip away the first half of HP manually.

@onready var btn: Button = $Margin/Button


func _ready() -> void:
	# Editor-only — exported builds (debug OR release) hide the button.
	if not OS.has_feature("editor"):
		queue_free()
		return
	layer = 30
	btn.pressed.connect(_on_pressed)


func _on_pressed() -> void:
	for n in get_tree().get_nodes_in_group("boss"):
		if not is_instance_valid(n):
			continue
		if not ("hp" in n) or not ("max_hp" in n):
			continue
		var current_hp: int = int(n.hp)
		var target_hp: int = int(int(n.max_hp) / 2)
		var delta_dmg: int = current_hp - target_hp
		if delta_dmg <= 0:
			print("[DebugHalfBossHp] Boss already at or below 50% HP (%d/%d)." % [current_hp, int(n.max_hp)])
			return
		# Route through take_damage so phase_2 + status flashes fire normally.
		# take_damage doubles damage when stunned — guard by passing the raw
		# delta only when not stunned, otherwise compute the half-amount.
		var is_stunned: bool = ("_stunned" in n) and bool(n._stunned)
		var amount: int = delta_dmg
		if is_stunned:
			amount = int(delta_dmg / 2)
		if n.has_method("take_damage"):
			n.take_damage(amount)
			print("[DebugHalfBossHp] Damaged boss by %d → expected hp ~%d." % [amount, target_hp])
		return
	print("[DebugHalfBossHp] No boss in group 'boss' yet — try after the boss spawns.")
