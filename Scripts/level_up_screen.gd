extends CanvasLayer

# Shows a row of choice cards on level up. Generic: each choice is a Dictionary
# { id, title, description }. Emits the chosen id. (Now used to offer block unlocks.)
signal choice_selected(choice_id: StringName)

@onready var choices_container: HBoxContainer = $Panel/Content/Choices

# Make the screen process even while the game is paused
func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func show_choices(choices: Array) -> void:
	# Clear any leftover buttons from a previous level up
	for child in choices_container.get_children():
		child.queue_free()

	# Pause the game while choosing
	get_tree().paused = true
	visible = true

	for choice in choices:
		choices_container.add_child(_build_choice_button(choice))

func _build_choice_button(choice: Dictionary) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(160, 200)
	btn.text = "%s\n\n%s" % [choice["title"], choice["description"]]
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(_on_choice_pressed.bind(choice["id"]))
	return btn

func _on_choice_pressed(choice_id: StringName) -> void:
	# Close ourselves *before* emitting: a listener may re-pause (e.g. open the
	# block editor), and we must not stomp that after the fact.
	visible = false
	get_tree().paused = false
	choice_selected.emit(choice_id)
