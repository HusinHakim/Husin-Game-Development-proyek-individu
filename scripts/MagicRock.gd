class_name MagicRock
extends ThrowableItem

# Magic Rock — arcane stone scattered across underdark rooms.
# Throwable; deals solid raw damage. No special status effect, but
# combos with the Crystal Buckler stun (7× damage on stunned bosses).

const SCENE_PATH := "res://scenes/MagicRock.tscn"


func _ready() -> void:
	item_id = "magic_rock"
	item_display_name = "Magic Rock"
	damage = 25
	destroy_on_hit = true
	throw_speed = 520.0
	max_range = 360.0
	respawn_delay = 4.0
	super._ready()
	item_icon = load("res://assets/sprites/items/magic_rock.png")
	if respawn_scene == null:
		respawn_scene = load(SCENE_PATH)
