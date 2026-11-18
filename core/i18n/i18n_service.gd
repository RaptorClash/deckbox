# core/i18n/i18n_service.gd
# Zero-boilerplate 13-language localization service with OS locale auto-detection,
# English fallback, parameter interpolation, and single-line language extensibility.
class_name I18nService
extends RefCounted

const ConstantsScript = preload("res://core/constants.gd")
const I18N_DIR: String = "res://i18n"

static var _initialized: bool = false
static var _active_language: String = "en"
static var _languages: Array[Dictionary] = []
static var _bundles: Dictionary = {} # lang_code -> Dictionary[key -> String]

static func _ensure_registry() -> void:
	if _initialized:
		return
	_initialized = true
	_languages.clear()
	_bundles.clear()

	# 1. Load optional i18n/languages.json first or parse single-line LANGUAGE_SPECS from Constants
	var cfg_path = I18N_DIR.path_join("languages.json")
	if FileAccess.file_exists(cfg_path):
		var parsed = _read_json_dict_or_array(cfg_path)
		if parsed is Array:
			for entry in parsed:
				if entry is Dictionary and entry.has("code"):
					_register_lang_entry({
						"code": str(entry.get("code", "")).strip_edges(),
						"flag": str(entry.get("flag", "🌐")),
						"nameNative": str(entry.get("nameNative", entry.get("code", ""))),
						"nameEn": str(entry.get("nameEn", entry.get("nameNative", "")))
					})
				elif entry is String:
					register_language_from_spec(entry)

	# 2. Always ensure every entry in Constants.LANGUAGE_SPECS is registered (1-line addition support)
	for spec in ConstantsScript.LANGUAGE_SPECS:
		register_language_from_spec(spec)

	_load_bundle(ConstantsScript.DEFAULT_FALLBACK_LANGUAGE)

static func _register_lang_entry(entry: Dictionary) -> bool:
	var code = str(entry.get("code", "")).strip_edges()
	if code.is_empty():
		return false
	for existing in _languages:
		if str(existing.get("code", "")) == code:
			return true
	_languages.append(entry)
	return true

static func reset_to_defaults() -> void:
	_initialized = false
	_active_language = ConstantsScript.DEFAULT_FALLBACK_LANGUAGE
	_languages.clear()
	_bundles.clear()
	_ensure_registry()

static func register_language_from_spec(spec_line: String, inline_translations: Dictionary = {}) -> bool:
	_ensure_registry()
	var parts = spec_line.split("|")
	if parts.size() < 2:
		return false
	var code = parts[0].strip_edges()
	if code.is_empty():
		return false
	var flag = parts[1].strip_edges() if parts.size() >= 2 else "🌐"
	var native_name = parts[2].strip_edges() if parts.size() >= 3 else code
	_register_lang_entry({
		"code": code,
		"flag": flag,
		"nameNative": native_name,
		"nameEn": native_name
	})
	if not inline_translations.is_empty():
		var existing = _bundles.get(code, {})
		if not (existing is Dictionary):
			existing = {}
		for k in inline_translations.keys():
			existing[str(k)] = str(inline_translations[k])
		_bundles[code] = existing
	return true

static func get_available_languages() -> Array[Dictionary]:
	_ensure_registry()
	var out: Array[Dictionary] = []
	for entry in _languages:
		out.append(entry.duplicate(true))
	return out

static func has_language(code: String) -> bool:
	_ensure_registry()
	var clean = code.strip_edges()
	for entry in _languages:
		if str(entry.get("code", "")) == clean:
			return true
	return false

static func detect_system_language(raw_locale: String = "__AUTO__") -> String:
	_ensure_registry()
	var loc = raw_locale.strip_edges()
	if loc == "__AUTO__":
		loc = OS.get_locale().strip_edges()
	if loc.is_empty():
		return ConstantsScript.DEFAULT_FALLBACK_LANGUAGE

	var norm = loc.replace("_", "-").to_lower()
	# Exact match (case-insensitive)
	for entry in _languages:
		var code = str(entry.get("code", ""))
		if code.to_lower() == norm:
			return code

	# Chinese script normalization (zh-cn / zh-sg -> zh-Hans; zh-tw / zh-hk / zh-mo -> zh-Hant)
	if norm.begins_with("zh"):
		if "hant" in norm or "-tw" in norm or "-hk" in norm or "-mo" in norm:
			if has_language("zh-Hant"):
				return "zh-Hant"
		if has_language("zh-Hans"):
			return "zh-Hans"

	# Primary language tag match (e.g., "de-at" -> "de", "pt-br" -> "pt")
	var primary = norm.split("-")[0]
	for entry in _languages:
		var code = str(entry.get("code", ""))
		if code.to_lower() == primary:
			return code

	return ConstantsScript.DEFAULT_FALLBACK_LANGUAGE

static func set_language(lang_code: String) -> String:
	_ensure_registry()
	var target = lang_code.strip_edges()
	if target.is_empty() or target.to_lower() == "auto":
		target = detect_system_language()

	if not has_language(target):
		# Try matching normalized/case-insensitive or primary tag before falling back to English
		var matched = _match_registered_code(target)
		target = matched if not matched.is_empty() else ConstantsScript.DEFAULT_FALLBACK_LANGUAGE

	_active_language = target
	_load_bundle(target)
	return _active_language

static func ensure_initialized(saved_language: String = "") -> String:
	_ensure_registry()
	if saved_language.strip_edges().is_empty():
		return set_language(detect_system_language())
	return set_language(saved_language)

static func get_active_language() -> String:
	_ensure_registry()
	return _active_language

static func t(key: String, params: Dictionary = {}, lang_override: String = "") -> String:
	_ensure_registry()
	var lang = _active_language if lang_override.strip_edges().is_empty() else lang_override.strip_edges()
	if not has_language(lang):
		var matched = _match_registered_code(lang)
		lang = matched if not matched.is_empty() else ConstantsScript.DEFAULT_FALLBACK_LANGUAGE

	var bundle = _load_bundle(lang)
	var raw_val = str(bundle.get(key, ""))
	if raw_val.is_empty() and lang != ConstantsScript.DEFAULT_FALLBACK_LANGUAGE:
		var fallback_bundle = _load_bundle(ConstantsScript.DEFAULT_FALLBACK_LANGUAGE)
		raw_val = str(fallback_bundle.get(key, ""))
	if raw_val.is_empty():
		raw_val = key

	if not params.is_empty():
		for p_key in params.keys():
			raw_val = raw_val.replace("{" + str(p_key) + "}", str(params[p_key]))
	return raw_val

static func _match_registered_code(code: String) -> String:
	var norm = code.replace("_", "-").to_lower()
	for entry in _languages:
		var c = str(entry.get("code", ""))
		if c.to_lower() == norm:
			return c
	var primary = norm.split("-")[0]
	for entry in _languages:
		var c = str(entry.get("code", ""))
		if c.to_lower() == primary:
			return c
	return ""

static func _load_bundle(lang_code: String) -> Dictionary:
	if _bundles.has(lang_code) and _bundles[lang_code] is Dictionary and not _bundles[lang_code].is_empty():
		return _bundles[lang_code]

	var path = I18N_DIR.path_join("%s.json" % lang_code)
	if not FileAccess.file_exists(path):
		# Try lowercase filename fallback
		var lower_path = I18N_DIR.path_join("%s.json" % lang_code.to_lower())
		if FileAccess.file_exists(lower_path):
			path = lower_path

	if FileAccess.file_exists(path):
		var parsed = _read_json_dict_or_array(path)
		if parsed is Dictionary:
			_bundles[lang_code] = parsed
			return parsed

	if not _bundles.has(lang_code):
		_bundles[lang_code] = {}
	return _bundles[lang_code]

static func _read_json_dict_or_array(path: String) -> Variant:
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text = f.get_as_text()
	f.close()
	var json = JSON.new()
	if json.parse(text) == OK:
		return json.data
	return null
