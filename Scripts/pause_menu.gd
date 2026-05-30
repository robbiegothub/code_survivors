extends CanvasLayer

@onready var resume_button: Button = $Buttons/ResumeButton
@onready var menu_button: Button = $Buttons/MenuButton
@onready var quit_button: Button = $Buttons/QuitButton

func _init() -> void:
	# Must process while paused so we can resume the game
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	visible = false
	resume_button.pressed.connect(_on_resume_pressed)
	menu_button.pressed.connect(_on_menu_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		# Don't open pause menu if level-up screen is already showing
		var level_up := get_tree().current_scene.get_node_or_null("LevelUpScreen")
		if level_up != null and level_up.visible:
			return
		toggle()

func toggle() -> void:
	if visible:
		_resume()
	else:
		_pause()

func _pause() -> void:
	get_tree().paused = true
	visible = true

func _resume() -> void:
	get_tree().paused = false
	visible = false

func _on_resume_pressed() -> void:
	_resume()

func _on_menu_pressed() -> void:
	get_tree().paused = false  # Unpause before scene change, important!
	SceneManager.go_to_menu()

func _on_quit_pressed() -> void:
	SceneManager.quit_game()
