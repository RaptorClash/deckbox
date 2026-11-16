# games/uno/ui/uno_main.gd
# Standalone Entrypoint for the 'DeckBox UNO' Build Target (--target uno)
class_name UnoStandaloneMain
extends Control

@onready var uno_game_view: Control = $UnoGame

func _ready() -> void:
	if uno_game_view != null and uno_game_view.has_signal("back_requested"):
		uno_game_view.back_requested.connect(_on_back_requested)

func launch_match(options: Dictionary = {}) -> bool:
	if uno_game_view == null or not uno_game_view.has_method("configure_match"):
		return false
	uno_game_view.configure_match(options)
	return true

func _on_back_requested() -> void:
	var main_hub_path = "res://scenes/main_hub/main_menu.tscn"
	if ResourceLoader.exists(main_hub_path) and get_tree() != null:
		get_tree().change_scene_to_file(main_hub_path)
	else:
		launch_match({ "mode": "solo" })
