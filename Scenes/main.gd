extends Node2D

@onready var level_up_screen: CanvasLayer = $LevelUpScreen
@onready var block_editor: CanvasLayer = $BlockEditor

func _ready() -> void:
	# Fresh run: re-lock all blocks down to the starters.
	BlockCatalog.reset()

	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		push_error("Main couldn't find the player!")
		return

	player.leveled_up.connect(_on_player_leveled_up.bind(player))
	level_up_screen.choice_selected.connect(_on_choice_selected.bind(player))

	# Hand the block editor a reference to the weapon controller so it can read and
	# overwrite the running weapon program. Toggled with "toggle_block_editor" (B).
	var weapon_controller := player.get_node("WeaponController")
	block_editor.setup(weapon_controller)

func _on_player_leveled_up(_new_level: int, _player: Node) -> void:
	# Offer three random grants: blocks (+1 each, one-time-use) or a compute-budget upgrade.
	var grants := BlockCatalog.get_random_grants(3)
	if grants.is_empty():
		return
	level_up_screen.show_choices(grants)

func _on_choice_selected(choice_id: StringName, _player: Node) -> void:
	BlockCatalog.apply_grant(choice_id)
	# Drop the player straight into the editor so they can wire up their new gear.
	block_editor.open()
