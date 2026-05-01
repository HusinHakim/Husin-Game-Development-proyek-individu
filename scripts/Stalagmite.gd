class_name Stalagmite
extends ThrowableItem

# Stalagmite — sharp stone shard dropped by RockBoss kills.
# High raw damage, single-use (shatters on impact).

const SCENE_PATH := "res://scenes/Stalagmite.tscn"


func _ready() -> void:
	item_id = "stalagmite"
	item_display_name = "Stalagmite"
	damage = 35
	destroy_on_hit = true
	throw_speed = 560.0
	max_range = 320.0
	# Loot drop only — comes from boss death; no autonomous respawn after pickup.
	should_respawn = false
	super._ready()
	item_icon = load("res://assets/sprites/items/stalagmite.png")


func apply_effect_to(enemy: Node) -> void:
	# Plain damage; no extra status effect.
	super.apply_effect_to(enemy)
