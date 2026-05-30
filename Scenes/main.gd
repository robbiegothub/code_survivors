extends Node2D

@onready var level_up_screen: CanvasLayer = $LevelUpScreen

func _ready() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		push_error("Main couldn't find the player!")
		return
	
	player.leveled_up.connect(_on_player_leveled_up.bind(player))
	level_up_screen.powerup_selected.connect(_on_powerup_selected.bind(player))

func _on_player_leveled_up(_new_level: int, player: Node) -> void:
	var choices := PowerupRegistry.get_random_choices(3)
	level_up_screen.show_choices(choices)

func _on_powerup_selected(powerup: Powerup, player: Node) -> void:
	powerup.apply(player)
