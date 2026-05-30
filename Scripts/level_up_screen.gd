extends CanvasLayer

signal powerup_selected(powerup: Powerup)

@onready var choices_container: HBoxContainer = $Panel/Content/Choices

# Make the screen process even while the game is paused
func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func show_choices(powerups: Array[Powerup]) -> void:
	# Clear any leftover buttons from a previous level up
	for child in choices_container.get_children():
		child.queue_free()
	
	# Pause the game while choosing
	get_tree().paused = true
	visible = true
	
	# Build a button for each powerup
	for powerup in powerups:
		var button := _build_choice_button(powerup)
		choices_container.add_child(button)

func _build_choice_button(powerup: Powerup) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(140, 180)
	btn.text = "%s\n\n%s" % [powerup.display_name, powerup.description]
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(_on_choice_pressed.bind(powerup))
	return btn

func _on_choice_pressed(powerup: Powerup) -> void:
	powerup_selected.emit(powerup)
	get_tree().paused = false
	visible = false
