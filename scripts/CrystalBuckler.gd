class_name CrystalBuckler
extends ThrowableItem

# Crystal Buckler — defensive item picked up from the ground.
# Used by pressing E near an attacking enemy to deflect their attack
# and stun them. Single-use (consumed on successful deflect).
# Throwing it (LMB) just lobs it as a low-damage projectile so the
# inventory contract stays consistent.

const SCENE_PATH := "res://scenes/CrystalBuckler.tscn"


func _ready() -> void:
	item_id = "crystal_buckler"
	item_display_name = "Crystal Buckler"
	damage = 0
	destroy_on_hit = true
	can_throw = false           # NOT throwable — used as a temporary shield via E
	respawn_delay = 5.0
	super._ready()
	item_icon = load("res://assets/sprites/items/crystal_buckler.png")
	if respawn_scene == null:
		respawn_scene = load(SCENE_PATH)
