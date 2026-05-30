extends Resource
class_name Powerup

@export var display_name: String = "Unnamed Powerup"
@export var description: String = ""
# A Callable that takes the player as its argument and applies the powerup effect.
# We'll assign this in code when creating each powerup.
var apply_effect: Callable

func apply(player: Node) -> void:
	if apply_effect.is_valid():
		apply_effect.call(player)
