# card_pack_schema.gd
# Schema Validation for .cardpack JSON Manifests, Colors, Asset Paths & Action Primitives
class_name CardPackSchema
extends RefCounted

const CURRENT_SCHEMA_VERSION: int = 1
const ALLOWED_GAMES: Array[String] = ["uno", "*"]
const ALLOWED_CARD_COLORS: Array[String] = [
	"red", "blue", "green", "yellow",
	"pink", "teal", "purple", "orange",
	"wild", "special", "colorless"
]
const ALLOWED_PRIMITIVE_TYPES: Array[String] = [
	"draw_cards", "skip_next", "reverse", "choose_color",
	"swap_hands", "discard_color", "negate_penalty", "custom_prompt",
	"flip_side", "skip_everyone"
]
const ALLOWED_TARGETS: Array[String] = ["next", "all_opponents", "chosen", "self"]
const ALLOWED_SWAP_TARGETS: Array[String] = ["choose_opponent", "left", "right"]

const MAX_CARDS_PER_TYPE: int = 20
const MAX_CUSTOM_CARDS_PER_PACK: int = 50
const MAX_ACTIONS_PER_CARD: int = 5
const MAX_TEXT_LENGTH: int = 200

static func is_safe_relative_path(path: String) -> bool:
	if path.strip_edges().is_empty():
		return false
	if path.contains("..") or path.contains(char(0)):
		return false
	if path.begins_with("/") or path.begins_with("\\"):
		return false
	if path.contains(":"):
		return false
	return true

static func validate_action(action: Variant) -> Dictionary:
	var errors: Array[String] = []
	if not (action is Dictionary):
		return { "valid": false, "errors": ["Action must be a Dictionary"] }

	var type_str = str(action.get("type", ""))
	if not ALLOWED_PRIMITIVE_TYPES.has(type_str):
		return { "valid": false, "errors": ["Unknown or prohibited action primitive type: '%s'" % type_str] }

	match type_str:
		"draw_cards":
			var count = int(action.get("count", 1))
			if count < 1 or count > 20:
				errors.append("draw_cards count must be between 1 and 20, got %d" % count)
			var target = str(action.get("target", "next"))
			if not ALLOWED_TARGETS.has(target):
				errors.append("Invalid draw_cards target: '%s'" % target)
		"skip_next":
			var count = int(action.get("count", 1))
			if count < 1 or count > 4:
				errors.append("skip_next count must be between 1 and 4, got %d" % count)
		"reverse":
			pass
		"choose_color":
			if action.has("options"):
				var opts = action.get("options")
				if not (opts is Array) or opts.is_empty():
					errors.append("choose_color options must be a non-empty Array of strings")
		"swap_hands":
			var target = str(action.get("target", "choose_opponent"))
			if not ALLOWED_SWAP_TARGETS.has(target):
				errors.append("Invalid swap_hands target: '%s'" % target)
		"discard_color":
			var color = str(action.get("color", ""))
			if color.is_empty():
				errors.append("discard_color requires a non-empty color parameter")
		"negate_penalty":
			pass
		"custom_prompt":
			var text = str(action.get("text", ""))
			if text.is_empty() or text.length() > MAX_TEXT_LENGTH:
				errors.append("custom_prompt text must be between 1 and %d characters" % MAX_TEXT_LENGTH)

	return { "valid": errors.is_empty(), "errors": errors }

static func validate_custom_card(card: Variant) -> Dictionary:
	var errors: Array[String] = []
	if not (card is Dictionary):
		return { "valid": false, "errors": ["Custom card must be a Dictionary"] }

	var card_id = str(card.get("id", card.get("card_id", "")))
	if card_id.is_empty():
		errors.append("Card must have a non-empty id or card_id")
	else:
		var regex = RegEx.new()
		regex.compile("^[a-zA-Z0-9_-]+$")
		if not regex.search(card_id):
			errors.append("Card id '%s' contains invalid characters (allowed: a-z, A-Z, 0-9, _, -)" % card_id)

	var name_str = str(card.get("name", ""))
	if name_str.is_empty() or name_str.length() > 64:
		errors.append("Card name must be between 1 and 64 characters")

	var color = str(card.get("color", ""))
	if not ALLOWED_CARD_COLORS.has(color):
		errors.append("Invalid card color '%s'; allowed: %s" % [color, str(ALLOWED_CARD_COLORS)])

	var count = int(card.get("count", 1))
	if count < 1 or count > MAX_CARDS_PER_TYPE:
		errors.append("Card count must be between 1 and %d, got %d" % [MAX_CARDS_PER_TYPE, count])

	if card.has("icon_path"):
		var icon_p = str(card.get("icon_path", ""))
		if not is_safe_relative_path(icon_p):
			errors.append("Unsafe icon_path: '%s'" % icon_p)

	if card.has("icon"):
		var icon_p = str(card.get("icon", ""))
		if not is_safe_relative_path(icon_p):
			errors.append("Unsafe icon path: '%s'" % icon_p)

	var actions = card.get("actions", [])
	if not (actions is Array):
		errors.append("Card actions must be an Array")
	elif actions.size() < 1 or actions.size() > MAX_ACTIONS_PER_CARD:
		errors.append("Card actions count must be between 1 and %d" % MAX_ACTIONS_PER_CARD)
	else:
		for i in range(actions.size()):
			var act_res = validate_action(actions[i])
			if not act_res.get("valid", false):
				for err in act_res.get("errors", []):
					errors.append("Action %d error: %s" % [i, err])

	return { "valid": errors.is_empty(), "errors": errors }

static func validate_pack(pack: Variant) -> Dictionary:
	var errors: Array[String] = []
	if not (pack is Dictionary):
		return { "valid": false, "errors": ["Pack data must be a Dictionary"] }

	var ver = int(pack.get("schema_version", 0))
	if ver < 1:
		errors.append("schema_version must be >= 1, got %d" % ver)

	var pack_id = str(pack.get("id", pack.get("pack_id", "")))
	if pack_id.is_empty():
		errors.append("Pack must specify a non-empty id or pack_id")
	else:
		var regex_id = RegEx.new()
		regex_id.compile("^[a-zA-Z0-9_-]+$")
		if not regex_id.search(pack_id):
			errors.append("Pack id '%s' contains invalid characters" % pack_id)

	var name_str = str(pack.get("name", ""))
	if name_str.is_empty() or name_str.length() > 64:
		errors.append("Pack name must be between 1 and 64 characters")

	var semver_str = str(pack.get("version", ""))
	var semver_regex = RegEx.new()
	semver_regex.compile("^\\d+\\.\\d+\\.\\d+$")
	if not semver_regex.search(semver_str):
		errors.append("Pack version '%s' must follow SemVer format (e.g. 1.0.0)" % semver_str)

	var author_str = str(pack.get("author", ""))
	if author_str.is_empty() or author_str.length() > 64:
		errors.append("Pack author must be between 1 and 64 characters")

	if pack.has("description"):
		var desc_str = str(pack.get("description", ""))
		if desc_str.length() > 500:
			errors.append("Pack description must not exceed 500 characters")

	if pack.has("assets") and pack.get("assets") is Dictionary:
		var assets = pack.get("assets")
		for key in assets.keys():
			var val = str(assets[key])
			if not is_safe_relative_path(val):
				errors.append("Unsafe asset path for '%s': '%s'" % [key, val])

	if pack.has("custom_cards"):
		var cards = pack.get("custom_cards")
		if not (cards is Array):
			errors.append("custom_cards must be an Array")
		elif cards.size() > MAX_CUSTOM_CARDS_PER_PACK:
			errors.append("Pack exceeds maximum of %d custom cards (has %d)" % [MAX_CUSTOM_CARDS_PER_PACK, cards.size()])
		else:
			var seen_ids: Dictionary = {}
			for i in range(cards.size()):
				var c = cards[i]
				var c_res = validate_custom_card(c)
				if not c_res.get("valid", false):
					for err in c_res.get("errors", []):
						errors.append("Card %d error: %s" % [i, err])
				if c is Dictionary:
					var cid = str(c.get("id", c.get("card_id", "")))
					if seen_ids.has(cid):
						errors.append("Duplicate card ID detected: '%s'" % cid)
					else:
						seen_ids[cid] = true

	return { "valid": errors.is_empty(), "errors": errors }
