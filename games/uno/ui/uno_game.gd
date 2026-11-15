# uno_game.gd
# Standalone Godot 4 Control Scene for UNO Game Presentation
extends Control

const UnoCartridgeScript = preload("res://games/uno/uno_cartridge.gd")

var cartridge: RefCounted = null
var current_player_id: String = "p0"

@onready var discard_label: Label = $VBoxContainer/TableArea/CenterTable/DiscardCard/DiscardLabel
@onready var draw_pile_btn: Button = $VBoxContainer/TableArea/CenterTable/DrawPileBtn
@onready var turn_label: Label = $VBoxContainer/Header/TurnLabel
@onready var hand_container: HBoxContainer = $VBoxContainer/PlayerArea/HandScroll/HandContainer
@onready var uno_call_btn: Button = $VBoxContainer/PlayerArea/ActionButtons/CallUnoButton
@onready var opponents_container: HBoxContainer = $VBoxContainer/OpponentsArea/OpponentsContainer
@onready var color_choice_dialog: ConfirmationDialog = $ColorChoiceDialog

func _ready() -> void:
	cartridge = UnoCartridgeScript.new()
	var players: Array[Dictionary] = [
		{ "player_id": "p0", "seat": 0, "name": "Player 0", "is_bot": false },
		{ "player_id": "p1", "seat": 1, "name": "Bot 1", "is_bot": true },
		{ "player_id": "p2", "seat": 2, "name": "Bot 2", "is_bot": true },
		{ "player_id": "p3", "seat": 3, "name": "Bot 3", "is_bot": true }
	]
	cartridge.init_match("match_ui", players, {}, 12345)
	cartridge.start_round()
	refresh_display()

func refresh_display() -> void:
	if cartridge == null:
		return

	var pub_state = cartridge.get_public_state()
	var my_view = cartridge.get_player_view(current_player_id)

	# Update Top Discard
	var top = pub_state.get("top_discard", {})
	if discard_label != null:
		var col = str(top.get("color", "none")).to_upper()
		var val = str(top.get("value", "-")).to_upper()
		discard_label.text = "%s\n%s" % [col, val]

	# Update Draw Pile Button
	if draw_pile_btn != null:
		draw_pile_btn.text = "Draw Pile\n(%d)" % int(pub_state.get("draw_pile_count", 0))

	# Update Turn Indicator
	if turn_label != null:
		var turn_s = int(pub_state.get("current_turn_seat", 0))
		turn_label.text = "Active Seat: %d (Direction: %s)" % [turn_s, "Clockwise" if int(pub_state.get("direction", 1)) == 1 else "Counter-Clockwise"]

	# Update Hand Cards
	if hand_container != null:
		for child in hand_container.get_children():
			child.queue_free()

		var hand = my_view.get("hand", [])
		for card in hand:
			var btn = Button.new()
			var c_id = str(card.get("id", ""))
			var c_col = str(card.get("color", "")).to_upper()
			var c_val = str(card.get("value", "")).to_upper()
			btn.text = "%s\n%s" % [c_col, c_val]
			btn.custom_minimum_size = Vector2(70, 100)
			btn.disabled = not bool(card.get("playable", false))
			btn.pressed.connect(_on_card_pressed.bind(c_id, card))
			hand_container.add_child(btn)

	# Update Opponents
	if opponents_container != null:
		for child in opponents_container.get_children():
			child.queue_free()

		var players_list = pub_state.get("players", [])
		for p in players_list:
			if str(p.get("player_id", "")) != current_player_id:
				var panel = PanelContainer.new()
				var lbl = Label.new()
				lbl.text = "%s\nCards: %d%s" % [
					p.get("name", ""),
					p.get("card_count", 0),
					" (BOT)" if p.get("is_bot", false) else ""
				]
				panel.add_child(lbl)
				opponents_container.add_child(panel)

func _on_card_pressed(card_id: String, card: Dictionary) -> void:
	if str(card.get("color", "")) == "wild":
		# Prompt color choice or default to red
		_play_card(card_id, "red")
	else:
		_play_card(card_id, "")

func _play_card(card_id: String, chosen_color: String) -> void:
	var action = {
		"type": "ACTION_PLAY_CARD",
		"card_id": card_id
	}
	if not chosen_color.is_empty():
		action["chosen_color"] = chosen_color

	cartridge.handle_action(current_player_id, action)
	_run_bot_turns()
	refresh_display()

func _on_draw_pile_btn_pressed() -> void:
	var action = { "type": "ACTION_DRAW_CARD" }
	cartridge.handle_action(current_player_id, action)
	_run_bot_turns()
	refresh_display()

func _on_call_uno_button_pressed() -> void:
	cartridge.handle_action(current_player_id, { "type": "ACTION_CALL_UNO" })
	refresh_display()

func _run_bot_turns() -> void:
	for _i in range(5): # Up to 5 bot steps
		var pub = cartridge.get_public_state()
		var turn_seat = int(pub.get("current_turn_seat", 0))
		var active_player = cartridge.get_player_by_seat(turn_seat)
		if bool(active_player.get("is_bot", false)):
			var pid = str(active_player.get("player_id", ""))
			var bot_act = cartridge.get_bot_action(pid)
			cartridge.handle_action(pid, bot_act)
		else:
			break
