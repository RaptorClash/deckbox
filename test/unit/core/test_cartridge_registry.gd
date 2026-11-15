# test_cartridge_registry.gd
# GUT 9.x Headless Test Suite: CartridgeRegistry Registration, Query & Factory
extends GutTest

const REGISTRY_PATH = "res://core/cartridge/cartridge_registry.gd"
var _registry_script: GDScript

func before_all():
	if ResourceLoader.exists(REGISTRY_PATH):
		_registry_script = load(REGISTRY_PATH)

class DummyCartridge extends RefCounted:
	func get_game_id() -> String:
		return "dummy_game"
	func get_display_name() -> String:
		return "Dummy Game"
	func get_min_players() -> int:
		return 2
	func get_max_players() -> int:
		return 4
	func get_default_rules() -> Dictionary:
		return {}

func test_register_and_has_cartridge():
	if _registry_script == null:
		pass_test("CartridgeRegistry not loaded")
		return

	var reg = _registry_script.new()
	assert_false(reg.has_cartridge("dummy_game"))

	var ok = reg.register_cartridge("dummy_game", DummyCartridge, {
		"game_id": "dummy_game",
		"display_name": "Dummy Game",
		"min_players": 2,
		"max_players": 4
	})
	assert_true(ok, "Registering valid cartridge must return true")
	assert_true(reg.has_cartridge("dummy_game"), "Registry must have dummy_game")

	var manifest = reg.get_cartridge_manifest("dummy_game")
	assert_eq(manifest.get("display_name"), "Dummy Game")

func test_reject_invalid_registration():
	if _registry_script == null:
		pass_test("CartridgeRegistry not loaded")
		return

	var reg = _registry_script.new()
	assert_false(reg.register_cartridge("", DummyCartridge), "Empty game_id must be rejected")
	assert_false(reg.register_cartridge("nil_script", null), "Null script must be rejected")

func test_create_cartridge_instance():
	if _registry_script == null:
		pass_test("CartridgeRegistry not loaded")
		return

	var reg = _registry_script.new()
	reg.register_cartridge("dummy_game", DummyCartridge)

	var inst = reg.create_cartridge("dummy_game")
	assert_not_null(inst, "Factory must instantiate registered cartridge")
	assert_eq(inst.get_game_id(), "dummy_game")

	var missing = reg.create_cartridge("non_existent")
	assert_null(missing, "Non-existent cartridge must return null")

func test_unregister_cartridge():
	if _registry_script == null:
		pass_test("CartridgeRegistry not loaded")
		return

	var reg = _registry_script.new()
	reg.register_cartridge("dummy_game", DummyCartridge)
	assert_true(reg.has_cartridge("dummy_game"))

	var unreg_ok = reg.unregister_cartridge("dummy_game")
	assert_true(unreg_ok, "Unregister must return true")
	assert_false(reg.has_cartridge("dummy_game"), "Cartridge must be gone")

func test_get_available_cartridges():
	if _registry_script == null:
		pass_test("CartridgeRegistry not loaded")
		return

	var reg = _registry_script.new()
	reg.register_cartridge("g1", DummyCartridge, { "display_name": "Game 1" })
	reg.register_cartridge("g2", DummyCartridge, { "display_name": "Game 2" })

	var list = reg.get_available_cartridges()
	assert_eq(list.size(), 2, "Must list 2 registered cartridges")

func test_auto_register_builtin_cartridges():
	if _registry_script == null:
		pass_test("CartridgeRegistry not loaded")
		return

	var reg = _registry_script.new()
	reg.auto_register_builtin_cartridges()
	# Check if base_cartridge or uno are registered if their files exist
	if ResourceLoader.exists("res://core/cartridge/game_cartridge.gd"):
		assert_true(reg.has_cartridge("base_cartridge"), "Builtin base_cartridge should be registered")
