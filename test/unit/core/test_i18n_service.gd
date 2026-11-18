# test_i18n_service.gd
# GUT 9.x Headless Test Suite: 13-Language Localization, OS Auto-Detection, Fallback & 1-Line Extensibility
extends GutTest

const I18N_SERVICE_PATH = "res://core/i18n/i18n_service.gd"
const EXPECTED_CODES: Array[String] = [
	"en", "de", "fr", "es", "it", "ja", "ko", "zh-Hans", "zh-Hant", "pt", "nl", "pl", "ru"
]

var _i18n_script: GDScript

func before_all() -> void:
	if ResourceLoader.exists(I18N_SERVICE_PATH):
		_i18n_script = load(I18N_SERVICE_PATH)

func after_each() -> void:
	if _i18n_script != null:
		_i18n_script.reset_to_defaults()

func test_all_13_languages_registered_and_loaded() -> void:
	assert_not_null(_i18n_script, "I18nService script must exist")
	var langs: Array[Dictionary] = _i18n_script.get_available_languages()
	assert_gte(langs.size(), 13, "At least 13 built-in languages must be registered")

	var codes: Array[String] = []
	for entry in langs:
		codes.append(str(entry.get("code", "")))

	for expected in EXPECTED_CODES:
		assert_true(expected in codes, "Language '%s' must be available" % expected)
		_i18n_script.set_language(expected)
		assert_eq(_i18n_script.get_active_language(), expected, "Active language must switch to %s" % expected)
		var play_lbl = _i18n_script.t("nav.play")
		assert_false(play_lbl.is_empty(), "nav.play must not be empty for %s" % expected)
		assert_ne(play_lbl, "nav.play", "nav.play must resolve to translated text for %s" % expected)

func test_system_language_auto_detection_with_english_fallback() -> void:
	assert_not_null(_i18n_script, "I18nService script must exist")
	assert_eq(_i18n_script.detect_system_language("de_DE"), "de")
	assert_eq(_i18n_script.detect_system_language("de-AT"), "de")
	assert_eq(_i18n_script.detect_system_language("en_US"), "en")
	assert_eq(_i18n_script.detect_system_language("fr_CA"), "fr")
	assert_eq(_i18n_script.detect_system_language("es_MX"), "es")
	assert_eq(_i18n_script.detect_system_language("it_IT"), "it")
	assert_eq(_i18n_script.detect_system_language("ja_JP"), "ja")
	assert_eq(_i18n_script.detect_system_language("ko_KR"), "ko")
	assert_eq(_i18n_script.detect_system_language("zh_CN"), "zh-Hans")
	assert_eq(_i18n_script.detect_system_language("zh_SG"), "zh-Hans")
	assert_eq(_i18n_script.detect_system_language("zh_TW"), "zh-Hant")
	assert_eq(_i18n_script.detect_system_language("zh_HK"), "zh-Hant")
	assert_eq(_i18n_script.detect_system_language("pt_BR"), "pt")
	assert_eq(_i18n_script.detect_system_language("nl_NL"), "nl")
	assert_eq(_i18n_script.detect_system_language("pl_PL"), "pl")
	assert_eq(_i18n_script.detect_system_language("ru_RU"), "ru")

	# Unsupported / unknown locales must fall back cleanly to English ("en")
	assert_eq(_i18n_script.detect_system_language("sv_SE"), "en", "Unsupported locale must default to English")
	assert_eq(_i18n_script.detect_system_language("tr_TR"), "en", "Unsupported locale must default to English")
	assert_eq(_i18n_script.detect_system_language(""), "en", "Empty locale must default to English")
	assert_eq(_i18n_script.detect_system_language("invalid_xx"), "en", "Malformed locale must default to English")

func test_translation_fallback_and_parameter_interpolation() -> void:
	assert_not_null(_i18n_script, "I18nService script must exist")
	_i18n_script.set_language("de")
	var de_msg = _i18n_script.t("hud.turn_label", { "player": "Marvin", "dir": "↻" })
	assert_true("Marvin" in de_msg and "↻" in de_msg, "Placeholder interpolation must work")

	_i18n_script.set_language("en")
	var en_play = _i18n_script.t("nav.play")
	assert_ne(en_play, _i18n_script.t("nav.play", {}, "de"), "English and German translations for nav.play must differ")

	# Unknown language code falls back to English
	_i18n_script.set_language("xx_unknown")
	assert_eq(_i18n_script.get_active_language(), "en", "Unknown language selection must fall back to English")

func test_single_line_spec_extensibility() -> void:
	assert_not_null(_i18n_script, "I18nService script must exist")
	var ok = _i18n_script.register_language_from_spec("sv|🇸🇪|Svenska", { "nav.play": "Spela" })
	assert_true(ok, "Adding a language via single spec string must succeed")

	_i18n_script.set_language("sv")
	assert_eq(_i18n_script.get_active_language(), "sv")
	assert_eq(_i18n_script.t("nav.play"), "Spela", "Custom registered key must resolve")
	# Untranslated keys in the new language must automatically fall back to English
	assert_eq(_i18n_script.t("nav.stats"), _i18n_script.t("nav.stats", {}, "en"), "Untranslated keys in new language must fall back to English")
	assert_eq(_i18n_script.detect_system_language("sv_SE"), "sv", "Once registered via spec, OS detection must recognize the new language too")
