extends Control

@onready var play_button: Button = $MenuContainer/PlayButton
@onready var quit_button: Button = $MenuContainer/QuitButton

func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

func _on_play_pressed() -> void:
	SceneManager.start_game()

func _on_quit_pressed() -> void:
	SceneManager.quit_game()
