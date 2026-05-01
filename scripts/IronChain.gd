class_name IronChain
extends ThrowableItem

const ENTANGLE_DURATION := 2.0
const SCENE_PATH := "res://scenes/IronChain.tscn"


func _ready() -> void:
	item_id = "iron_chain"
	item_display_name = "Iron Chain"
	damage = 20
	destroy_on_hit = true
	super._ready()
	item_icon = load("res://assets/sprites/items/iron_chain.png")
	if respawn_scene == null:
		respawn_scene = load(SCENE_PATH)


func apply_effect_to(enemy: Node) -> void:
	super.apply_effect_to(enemy)
	if enemy.has_method("apply_entangle"):
		enemy.apply_entangle(ENTANGLE_DURATION)
