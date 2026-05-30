extends Node

# Paths to all our scenes in one place — easy to change later
const MAIN_MENU := "res://scenes/MainMenu.tscn"
const GAME := "res://scenes/Main.tscn"

func go_to_menu() -> void:
	get_tree().change_scene_to_file(MAIN_MENU)

func start_game() -> void:
	get_tree().change_scene_to_file(GAME)

func quit_game() -> void:
	get_tree().quit()
