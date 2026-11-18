# constants.gd
# Global constants, version metadata, and single-line extensible language registry for DeckBox
class_name Constants
extends RefCounted

const APP_NAME: String = "DeckBox"
const APP_VERSION: String = "0.1.0"
const PROTOCOL_VERSION: int = 1
const DEFAULT_PORT: int = 8080
const DEFAULT_SIGNALING_STUN: String = "stun:stun.l.google.com:19302"

const DEFAULT_FALLBACK_LANGUAGE: String = "en"

# To add a new language: append ONE "code|flag|Native Name" entry here and drop i18n/<code>.json into res://i18n/
# (or add an entry to i18n/languages.json).
const LANGUAGE_SPECS: Array[String] = [
	"en|🇬🇧|English",
	"de|🇩🇪|Deutsch",
	"fr|🇫🇷|Français",
	"es|🇪🇸|Español",
	"it|🇮🇹|Italiano",
	"ja|🇯🇵|日本語",
	"ko|🇰🇷|한국어",
	"zh-Hans|🇨🇳|简体中文",
	"zh-Hant|🇹🇼|繁體中文",
	"pt|🇵🇹|Português",
	"nl|🇳🇱|Nederlands",
	"pl|🇵🇱|Polski",
	"ru|🇷🇺|Русский"
]
