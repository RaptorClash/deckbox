# scenes/main_hub/main_menu.gd
# Central DeckBox Collection Hub with Game Selector Gallery, Clean Match Setup,
# Dedicated Settings & TURN Configuration Tab, LAN/QR Short-URL Host, Friends, Pack Editor, Stats & Updater.
class_name MainMenuHub
extends Control

const ConstantsScript = preload("res://core/constants.gd")
const I18nServiceScript = preload("res://core/i18n/i18n_service.gd")
const ProfileServiceScript = preload("res://core/profile/profile_service.gd")
const HttpHostScript = preload("res://core/network/http_host.gd")
const WsHostScript = preload("res://core/network/ws_host.gd")
const LanDiscoveryScript = preload("res://core/network/lan_discovery.gd")
const RoomManagerScript = preload("res://core/network/room_manager.gd")
const VersionHandshakeScript = preload("res://core/network/version_handshake.gd")
const WebRtcManagerScript = preload("res://core/network/webrtc_manager.gd")
const QRCodeScript = preload("res://core/network/qr_code.gd")
const FriendsServiceScript = preload("res://core/network/friends_service.gd")
const ReleaseUpdaterScript = preload("res://core/updater/release_updater.gd")
const ExternalLoaderScript = preload("res://core/cartridge/external_loader.gd")
const CartridgeRegistryScript = preload("res://core/cartridge/cartridge_registry.gd")
const CardTextureGenScript = preload("res://core/visuals/card_texture_generator.gd")
const UIThemeScript = preload("res://core/visuals/deckbox_ui_theme.gd")
const UnoGameScene = preload("res://games/uno/ui/uno_game.tscn")
const CardMeshScene = preload("res://assets/3d/card_rounded.glb")

const TABLE_SCENES: Dictionary = {
	"arcade_ps5": "res://scenes/tables/arcade_ps5.tscn",
	"cozy_wood": "res://scenes/tables/cozy_wood.tscn",
	"clean_25d": "res://scenes/tables/clean_25d.tscn"
}

var _profile_svc: RefCounted
var _http_host: RefCounted
var _ws_host: RefCounted
var _lan_discovery: RefCounted
var _room_manager: RefCounted
var _handshake: RefCounted
var _webrtc: RefCounted
var _friends_svc: RefCounted
var _updater: RefCounted
var _ext_loader: RefCounted
var _registry: RefCounted

var _is_hosting: bool = false
var _is_listening_lan: bool = false
var _selected_game_id: String = ""
var _active_uno_view: Control = null
var _active_tab_id: String = "play"
var _last_host_info: Dictionary = {}
var _discovered_rooms_cache: Array[Dictionary] = []
var active_preview_table_3d: Node3D = null
var _preview_showcase_root: Node3D = null
var _lounge_orbit_angle: float = 0.0

@onready var hub_shell: VBoxContainer = $HubShell
@onready var active_match_host: Control = $ActiveMatchHost
@onready var version_badge: Label = $HubShell/TopBarPanel/TopBar/VersionBadge

@onready var play_tab_btn: Button = $HubShell/TopBarPanel/TopBar/PlayTabBtn
@onready var friends_tab_btn: Button = $HubShell/TopBarPanel/TopBar/FriendsTabBtn
@onready var packs_tab_btn: Button = $HubShell/TopBarPanel/TopBar/PacksTabBtn
@onready var profile_tab_btn: Button = $HubShell/TopBarPanel/TopBar/ProfileTabBtn
@onready var stats_tab_btn: Button = $HubShell/TopBarPanel/TopBar/StatsTabBtn
@onready var settings_tab_btn: Button = $HubShell/TopBarPanel/TopBar/SettingsTabBtn
@onready var updater_tab_btn: Button = $HubShell/TopBarPanel/TopBar/UpdaterTabBtn

@onready var play_tab: Control = $HubShell/ContentStack/PlayTab
@onready var friends_tab: Control = $HubShell/ContentStack/FriendsTab
@onready var pack_editor_tab: Control = $HubShell/ContentStack/PackEditorTab
@onready var profile_tab: Control = $HubShell/ContentStack/ProfileTab
@onready var stats_tab: Control = $HubShell/ContentStack/StatsTab
@onready var settings_tab: Control = $HubShell/ContentStack/SettingsTab
@onready var updater_tab: Control = $HubShell/ContentStack/UpdaterTab

# Step 1: Game Selector Gallery
@onready var game_selector_view: VBoxContainer = $HubShell/ContentStack/PlayTab/GameSelectorView
@onready var alle_ablegen_card: PanelContainer = $HubShell/ContentStack/PlayTab/GameSelectorView/GamesGrid/AlleAblegenCard
@onready var select_uno_btn: Button = $HubShell/ContentStack/PlayTab/GameSelectorView/GamesGrid/AlleAblegenCard/CardBox/SelectUnoBtn
@onready var join_address_edit: LineEdit = $HubShell/ContentStack/PlayTab/GameSelectorView/BottomJoinRow/QuickJoinPanel/JoinBox/JoinAddressRow/JoinAddressEdit
@onready var lan_rooms_list: ItemList = $HubShell/ContentStack/PlayTab/GameSelectorView/BottomJoinRow/QuickJoinPanel/JoinBox/LanRoomsRow/LanRoomsList
@onready var join_status_label: Label = $HubShell/ContentStack/PlayTab/GameSelectorView/BottomJoinRow/QuickJoinPanel/JoinBox/JoinStatusLabel
@onready var pck_path_edit: LineEdit = $HubShell/ContentStack/PlayTab/GameSelectorView/BottomJoinRow/ExternalModulePanel/ModBox/ExternalRow/PckPathEdit
@onready var ext_status_label: Label = $HubShell/ContentStack/PlayTab/GameSelectorView/BottomJoinRow/ExternalModulePanel/ModBox/ExternalStatusLabel

# Step 2: Match Setup (Rules & Lobby ONLY)
@onready var match_setup_view: VBoxContainer = $HubShell/ContentStack/PlayTab/MatchSetupView
@onready var mode_option: OptionButton = $HubShell/ContentStack/PlayTab/MatchSetupView/Columns/SetupPanel/SetupOuter/SetupScroll/SetupBox/ModeOption
@onready var player_count_spin: SpinBox = $HubShell/ContentStack/PlayTab/MatchSetupView/Columns/SetupPanel/SetupOuter/SetupScroll/SetupBox/PlayerCountRow/PlayerCountSpin
@onready var unlimited_lan_check: CheckBox = $HubShell/ContentStack/PlayTab/MatchSetupView/Columns/SetupPanel/SetupOuter/SetupScroll/SetupBox/PlayerCountRow/UnlimitedLanCheck
@onready var no_mercy_check: CheckBox = $HubShell/ContentStack/PlayTab/MatchSetupView/Columns/SetupPanel/SetupOuter/SetupScroll/SetupBox/ExpansionsGrid/NoMercyCheck
@onready var flip_mode_check: CheckBox = $HubShell/ContentStack/PlayTab/MatchSetupView/Columns/SetupPanel/SetupOuter/SetupScroll/SetupBox/ExpansionsGrid/FlipModeCheck
@onready var include_custom_check: CheckBox = $HubShell/ContentStack/PlayTab/MatchSetupView/Columns/SetupPanel/SetupOuter/SetupScroll/SetupBox/ExpansionsGrid/IncludeCustomCheck
@onready var mercy_limit_spin: SpinBox = $HubShell/ContentStack/PlayTab/MatchSetupView/Columns/SetupPanel/SetupOuter/SetupScroll/SetupBox/ExpansionsGrid/MercyLimitRow/MercyLimitSpin
@onready var stack_d2_check: CheckBox = $HubShell/ContentStack/PlayTab/MatchSetupView/Columns/SetupPanel/SetupOuter/SetupScroll/SetupBox/RulesGrid/StackD2Check
@onready var stack_d4_check: CheckBox = $HubShell/ContentStack/PlayTab/MatchSetupView/Columns/SetupPanel/SetupOuter/SetupScroll/SetupBox/RulesGrid/StackD4Check
@onready var jump_in_check: CheckBox = $HubShell/ContentStack/PlayTab/MatchSetupView/Columns/SetupPanel/SetupOuter/SetupScroll/SetupBox/RulesGrid/JumpInCheck
@onready var seven_zero_check: CheckBox = $HubShell/ContentStack/PlayTab/MatchSetupView/Columns/SetupPanel/SetupOuter/SetupScroll/SetupBox/RulesGrid/SevenZeroCheck
@onready var draw_match_check: CheckBox = $HubShell/ContentStack/PlayTab/MatchSetupView/Columns/SetupPanel/SetupOuter/SetupScroll/SetupBox/RulesGrid/DrawMatchCheck
@onready var launch_uno_btn: Button = $HubShell/ContentStack/PlayTab/MatchSetupView/Columns/SetupPanel/SetupOuter/LaunchUnoBtn

@onready var preview_viewport: SubViewport = $LoungeViewportContainer/PreviewViewport
@onready var host_lan_btn: Button = $HubShell/ContentStack/PlayTab/MatchSetupView/Columns/LobbyPanel/LobbyBox/HostControlsRow/HostLanBtn
@onready var lan_ip_option: OptionButton = $HubShell/ContentStack/PlayTab/MatchSetupView/Columns/LobbyPanel/LobbyBox/HostControlsRow/LanIpOption
@onready var room_pin_label: Label = $HubShell/ContentStack/PlayTab/MatchSetupView/Columns/LobbyPanel/LobbyBox/RoomPinLabel
@onready var join_url_label: Label = $HubShell/ContentStack/PlayTab/MatchSetupView/Columns/LobbyPanel/LobbyBox/JoinUrlRow/JoinUrlLabel
@onready var copy_join_url_btn: Button = $HubShell/ContentStack/PlayTab/MatchSetupView/Columns/LobbyPanel/LobbyBox/JoinUrlRow/CopyJoinUrlBtn
@onready var table_url_label: Label = $HubShell/ContentStack/PlayTab/MatchSetupView/Columns/LobbyPanel/LobbyBox/TableUrlLabel
@onready var stun_label: Label = $HubShell/ContentStack/PlayTab/MatchSetupView/Columns/LobbyPanel/LobbyBox/StunLabel
@onready var qr_backplate: PanelContainer = $HubShell/ContentStack/PlayTab/MatchSetupView/Columns/LobbyPanel/LobbyBox/QrCenter/QrBackplate
@onready var qr_texture_rect: TextureRect = $HubShell/ContentStack/PlayTab/MatchSetupView/Columns/LobbyPanel/LobbyBox/QrCenter/QrBackplate/QRTextureRect

# Settings Tab (Visuals, 3D Table & Network/TURN)
@onready var language_option: OptionButton = $HubShell/ContentStack/SettingsTab/SettingsColumns/VisualSettingsPanel/VisualBox/LanguageRow/LanguageOption
@onready var view_mode_option: OptionButton = $HubShell/ContentStack/SettingsTab/SettingsColumns/VisualSettingsPanel/VisualBox/ViewModeRow/ViewModeOption
@onready var skin_option: OptionButton = $HubShell/ContentStack/SettingsTab/SettingsColumns/VisualSettingsPanel/VisualBox/SkinRow/SkinOption
@onready var theme_option: OptionButton = $HubShell/ContentStack/SettingsTab/SettingsColumns/VisualSettingsPanel/VisualBox/ThemeRow/ThemeOption
@onready var quality_option: OptionButton = $HubShell/ContentStack/SettingsTab/SettingsColumns/VisualSettingsPanel/VisualBox/QualityRow/QualityOption
@onready var bot_speed_option: OptionButton = $HubShell/ContentStack/SettingsTab/SettingsColumns/VisualSettingsPanel/VisualBox/SpeedRow/BotSpeedOption
@onready var colorblind_check: CheckButton = $HubShell/ContentStack/SettingsTab/SettingsColumns/VisualSettingsPanel/VisualBox/ColorblindCheck
@onready var turn_url_edit: LineEdit = $HubShell/ContentStack/SettingsTab/SettingsColumns/NetworkSettingsPanel/NetBox/TurnUrlEdit
@onready var turn_user_edit: LineEdit = $HubShell/ContentStack/SettingsTab/SettingsColumns/NetworkSettingsPanel/NetBox/TurnCredsRow/TurnUserEdit
@onready var turn_pass_edit: LineEdit = $HubShell/ContentStack/SettingsTab/SettingsColumns/NetworkSettingsPanel/NetBox/TurnCredsRow/TurnPassEdit
@onready var settings_status_label: Label = $HubShell/ContentStack/SettingsTab/SettingsColumns/NetworkSettingsPanel/NetBox/SettingsStatusLabel
@onready var turn_help_panel: PanelContainer = $HubShell/ContentStack/SettingsTab/SettingsColumns/NetworkSettingsPanel/NetBox/TurnHelpPanel

@onready var my_uuid_label: Label = $HubShell/ContentStack/FriendsTab/FriendsBox/MyUuidLabel
@onready var my_friend_qr_rect: TextureRect = $HubShell/ContentStack/FriendsTab/FriendsBox/FriendQrRow/MyFriendQrRect
@onready var my_friend_payload_edit: LineEdit = $HubShell/ContentStack/FriendsTab/FriendsBox/FriendQrRow/MyFriendPayloadEdit
@onready var add_friend_payload_edit: LineEdit = $HubShell/ContentStack/FriendsTab/FriendsBox/AddFriendRow/AddFriendPayloadEdit
@onready var friends_list_box: VBoxContainer = $HubShell/ContentStack/FriendsTab/FriendsBox/FriendsScroll/FriendsListBox
@onready var friends_status_label: Label = $HubShell/ContentStack/FriendsTab/FriendsBox/FriendsStatusLabel

@onready var updater_status_label: Label = $HubShell/ContentStack/UpdaterTab/UpdaterBox/UpdaterStatusLabel
@onready var releases_list: ItemList = $HubShell/ContentStack/UpdaterTab/UpdaterBox/ReleasesList
@onready var github_http_req: HTTPRequest = $GitHubReleasesRequest

var _tabs_map: Dictionary = {}
var _tab_buttons_map: Dictionary = {}

func _ready() -> void:
	theme = UIThemeScript.create_theme()
	if select_uno_btn != null:
		select_uno_btn.add_theme_stylebox_override("normal", UIThemeScript.make_accent_button())
		select_uno_btn.add_theme_stylebox_override("hover", UIThemeScript.make_accent_button(Color(1.0, 0.56, 0.20, 1.0), Color.WHITE))
	if launch_uno_btn != null:
		launch_uno_btn.add_theme_stylebox_override("normal", UIThemeScript.make_accent_button())
		launch_uno_btn.add_theme_stylebox_override("hover", UIThemeScript.make_accent_button(Color(1.0, 0.56, 0.20, 1.0), Color.WHITE))
	if alle_ablegen_card != null:
		alle_ablegen_card.add_theme_stylebox_override("panel", UIThemeScript.make_glass_panel(UIThemeScript.COL_GLASS_SURFACE, UIThemeScript.COL_BORDER_GOLD, 16, 16))
	if turn_help_panel != null:
		turn_help_panel.add_theme_stylebox_override("panel", UIThemeScript.make_glass_panel(Color(0.04, 0.06, 0.11, 0.92), Color(0.28, 0.72, 1.0, 0.30), 12, 12))
	if qr_backplate != null:
		qr_backplate.add_theme_stylebox_override("panel", UIThemeScript.make_glass_panel(Color(0.96, 0.97, 0.99, 1.0), UIThemeScript.COL_BORDER_GOLD, 16, 10))
		qr_backplate.visible = false
	if copy_join_url_btn != null:
		copy_join_url_btn.disabled = true

	_profile_svc = ProfileServiceScript.new()
	_http_host = HttpHostScript.new()
	_ws_host = WsHostScript.new()
	_lan_discovery = LanDiscoveryScript.new()
	_handshake = VersionHandshakeScript.new()
	_webrtc = WebRtcManagerScript.new()
	_friends_svc = FriendsServiceScript.new()
	_updater = ReleaseUpdaterScript.new()
	_ext_loader = ExternalLoaderScript.new()
	_registry = CartridgeRegistryScript.new()
	_registry.auto_register_builtin_cartridges()

	_ws_host.packet_received.connect(_on_ws_packet_received)
	_lan_discovery.room_found.connect(_on_lan_rooms_changed)
	_lan_discovery.room_updated.connect(_on_lan_rooms_changed)
	_lan_discovery.room_expired.connect(_on_lan_room_expired)

	_tabs_map = {
		"play": play_tab,
		"lobby": play_tab,
		"friends": friends_tab,
		"pack_editor": pack_editor_tab,
		"profile": profile_tab,
		"stats": stats_tab,
		"settings": settings_tab,
		"updater": updater_tab
	}
	_tab_buttons_map = {
		"play": play_tab_btn,
		"friends": friends_tab_btn,
		"pack_editor": packs_tab_btn,
		"profile": profile_tab_btn,
		"stats": stats_tab_btn,
		"settings": settings_tab_btn,
		"updater": updater_tab_btn
	}

	if version_badge != null:
		version_badge.text = "v%s" % ConstantsScript.APP_VERSION

	_init_play_options()
	_init_lan_ip_options()
	_wire_embedded_screens()
	_refresh_friends_ui()
	_update_3d_preview()
	show_game_selector()
	select_tab("play")
	if not DisplayServer.get_name().to_lower().contains("headless"):
		_start_lan_discovery_listener()

func _exit_tree() -> void:
	stop_lan_host()
	if _lan_discovery != null:
		_lan_discovery.stop_listening()
		_is_listening_lan = false

func _process(delta: float) -> void:
	if _is_hosting:
		if _http_host != null:
			_http_host.poll()
		if _ws_host != null:
			_ws_host.poll()
	if (_is_hosting or _is_listening_lan) and _lan_discovery != null:
		_lan_discovery.poll()
	if _preview_showcase_root != null and is_instance_valid(_preview_showcase_root):
		_preview_showcase_root.rotate_y(delta * 0.55)
	if active_preview_table_3d != null and is_instance_valid(active_preview_table_3d) and active_preview_table_3d.has_method("get_camera"):
		_lounge_orbit_angle += delta * 0.14
		var cam: Camera3D = active_preview_table_3d.get_camera()
		if cam != null:
			var cam_pos = Vector3(sin(_lounge_orbit_angle) * 1.45, 1.52, cos(_lounge_orbit_angle) * 1.45)
			var dir = (Vector3(0.0, 0.78, 0.0) - cam_pos).normalized()
			if not dir.is_zero_approx():
				cam.transform = Transform3D(Basis.looking_at(dir, Vector3.UP), cam_pos)

func is_game_selected() -> bool:
	return not _selected_game_id.is_empty()

func select_game(game_id: String) -> bool:
	var gid = game_id.to_lower().strip_edges()
	if gid.is_empty():
		return false
	_selected_game_id = gid
	if game_selector_view != null:
		game_selector_view.visible = false
	if match_setup_view != null:
		match_setup_view.visible = true
	select_tab("play")
	return true

func show_game_selector() -> void:
	_selected_game_id = ""
	if game_selector_view != null:
		game_selector_view.visible = true
	if match_setup_view != null:
		match_setup_view.visible = false

func _init_play_options() -> void:
	_populate_language_option()

	if mode_option != null:
		mode_option.clear()
		mode_option.add_item("Solo", 0)
		mode_option.set_item_metadata(0, "solo")
		mode_option.add_item("Pass & Play", 1)
		mode_option.set_item_metadata(1, "pass_and_play")
		mode_option.add_item("LAN / QR", 2)
		mode_option.set_item_metadata(2, "lan_host")

	if view_mode_option != null:
		view_mode_option.clear()
		view_mode_option.add_item("Full 3D (Standard)", 0)
		view_mode_option.set_item_metadata(0, "full_3d")
		view_mode_option.add_item("Hybrid 3D + 2.5D Fächer", 1)
		view_mode_option.set_item_metadata(1, "hybrid_25d")
		view_mode_option.add_item("Clean 2.5D (Low-Spec)", 2)
		view_mode_option.set_item_metadata(2, "clean_25d")
		view_mode_option.add_item("TV-Tisch-Modus (Großbild)", 3)
		view_mode_option.set_item_metadata(3, "table_role")

	if skin_option != null:
		skin_option.clear()
		skin_option.add_item("Classic Arcade", 0)
		skin_option.set_item_metadata(0, "classic_arcade")
		skin_option.add_item("Minimal Dark", 1)
		skin_option.set_item_metadata(1, "minimal_dark")

	if theme_option != null:
		theme_option.clear()
		theme_option.add_item("Arcade PS5 (Standard)", 0)
		theme_option.set_item_metadata(0, "arcade_ps5")
		theme_option.add_item("Cozy Wood", 1)
		theme_option.set_item_metadata(1, "cozy_wood")
		theme_option.add_item("Clean 2.5D", 2)
		theme_option.set_item_metadata(2, "clean_25d")

	if quality_option != null:
		quality_option.clear()
		quality_option.add_item("High", 0)
		quality_option.set_item_metadata(0, "high")
		quality_option.add_item("Medium", 1)
		quality_option.set_item_metadata(1, "medium")
		quality_option.add_item("Low", 2)
		quality_option.set_item_metadata(2, "low")

	if bot_speed_option != null:
		bot_speed_option.clear()
		bot_speed_option.add_item("Normal (0.7s)", 0)
		bot_speed_option.set_item_metadata(0, "normal")
		bot_speed_option.add_item("Schnell (0.25s)", 1)
		bot_speed_option.set_item_metadata(1, "fast")
		bot_speed_option.add_item("Sofort (0s)", 2)
		bot_speed_option.set_item_metadata(2, "instant")

	var prof = _profile_svc.load_profile()
	var active_lang = I18nServiceScript.ensure_initialized(str(prof.get("language", "")))
	_select_option_by_meta(language_option, active_lang)
	_select_option_by_meta(view_mode_option, str(prof.get("view_mode", "full_3d")))
	_select_option_by_meta(skin_option, str(prof.get("card_skin", "classic_arcade")))
	_select_option_by_meta(theme_option, str(prof.get("theme_preset", "arcade_ps5")))
	_select_option_by_meta(quality_option, str(prof.get("quality_preset", "high")))
	_select_option_by_meta(bot_speed_option, str(prof.get("bot_speed", "normal")))
	if colorblind_check != null:
		colorblind_check.button_pressed = bool(prof.get("colorblind_mode", true))
	if turn_url_edit != null:
		turn_url_edit.text = str(prof.get("turn_url", ""))
	if turn_user_edit != null:
		turn_user_edit.text = str(prof.get("turn_username", ""))
	if turn_pass_edit != null:
		turn_pass_edit.text = str(prof.get("turn_credential", ""))
	_apply_turn_config_from_inputs()
	apply_language()

func _populate_language_option() -> void:
	if language_option == null:
		return
	language_option.clear()
	var langs: Array[Dictionary] = I18nServiceScript.get_available_languages()
	for i in range(langs.size()):
		var entry: Dictionary = langs[i]
		var display = "%s %s (%s)" % [
			str(entry.get("flag", "")),
			str(entry.get("nameNative", entry.get("code", ""))),
			str(entry.get("code", ""))
		]
		language_option.add_item(display.strip_edges(), i)
		language_option.set_item_metadata(i, str(entry.get("code", "")))

func set_language(lang_code: String, persist: bool = false) -> String:
	var resolved = I18nServiceScript.set_language(lang_code)
	_select_option_by_meta(language_option, resolved)
	apply_language()
	if persist and _profile_svc != null:
		_profile_svc.update_profile({"language": resolved})
	return resolved

func _on_language_option_selected(index: int) -> void:
	if language_option == null or index < 0 or index >= language_option.item_count:
		return
	var code = str(language_option.get_item_metadata(index))
	if not code.is_empty():
		set_language(code, true)

func _set_rel_text(rel_path: String, key: String, params: Dictionary = {}) -> void:
	var n = get_node_or_null(rel_path)
	if n != null and "text" in n:
		n.text = I18nServiceScript.t(key, params)

func _set_rel_placeholder(rel_path: String, key: String, params: Dictionary = {}) -> void:
	var n = get_node_or_null(rel_path)
	if n != null and "placeholder_text" in n:
		n.placeholder_text = I18nServiceScript.t(key, params)

func apply_language() -> void:
	# Top Navigation Bar
	if play_tab_btn != null:
		play_tab_btn.text = I18nServiceScript.t("nav.play")
	if friends_tab_btn != null:
		friends_tab_btn.text = I18nServiceScript.t("nav.friends")
	if packs_tab_btn != null:
		packs_tab_btn.text = I18nServiceScript.t("nav.pack_editor")
	if profile_tab_btn != null:
		profile_tab_btn.text = I18nServiceScript.t("nav.profile")
	if stats_tab_btn != null:
		stats_tab_btn.text = I18nServiceScript.t("nav.stats")
	if settings_tab_btn != null:
		settings_tab_btn.text = I18nServiceScript.t("nav.settings")
	if updater_tab_btn != null:
		updater_tab_btn.text = I18nServiceScript.t("nav.updater")

	# Step 1: Game Selector Gallery
	var gs = "HubShell/ContentStack/PlayTab/GameSelectorView/"
	_set_rel_text(gs + "GalleryHeaderPanel/HeaderBox/GalleryTitle", "gallery.title")
	_set_rel_text(gs + "GalleryHeaderPanel/HeaderBox/GallerySubtitle", "gallery.subtitle")
	_set_rel_text(gs + "GamesGrid/AlleAblegenCard/CardBox/Badge", "gallery.ready_badge")
	_set_rel_text(gs + "GamesGrid/AlleAblegenCard/CardBox/Title", "gallery.alle_ablegen_title")
	_set_rel_text(gs + "GamesGrid/AlleAblegenCard/CardBox/Desc", "gallery.alle_ablegen_desc")
	if select_uno_btn != null:
		select_uno_btn.text = I18nServiceScript.t("gallery.select_btn")
	_set_rel_text(gs + "GamesGrid/WizardCard/CardBox/Badge", "gallery.wizard_badge")
	_set_rel_text(gs + "GamesGrid/WizardCard/CardBox/Title", "gallery.wizard_title")
	_set_rel_text(gs + "GamesGrid/WizardCard/CardBox/Desc", "gallery.wizard_desc")
	_set_rel_text(gs + "GamesGrid/WizardCard/CardBox/SoonBtn", "gallery.soon_btn")
	_set_rel_text(gs + "GamesGrid/DoppelkopfCard/CardBox/Badge", "gallery.doko_badge")
	_set_rel_text(gs + "GamesGrid/DoppelkopfCard/CardBox/Title", "gallery.doko_title")
	_set_rel_text(gs + "GamesGrid/DoppelkopfCard/CardBox/Desc", "gallery.doko_desc")
	_set_rel_text(gs + "GamesGrid/DoppelkopfCard/CardBox/SoonBtn", "gallery.soon_btn")

	_set_rel_text(gs + "BottomJoinRow/QuickJoinPanel/JoinBox/JoinTitle", "gallery.join_title")
	_set_rel_placeholder(gs + "BottomJoinRow/QuickJoinPanel/JoinBox/JoinAddressRow/JoinAddressEdit", "gallery.join_placeholder")
	_set_rel_text(gs + "BottomJoinRow/QuickJoinPanel/JoinBox/JoinAddressRow/JoinDirectBtn", "gallery.join_browser_btn")
	_set_rel_text(gs + "BottomJoinRow/QuickJoinPanel/JoinBox/LanRoomsRow/LanJoinBtns/JoinLanRoomBtn", "gallery.room_open_btn")
	_set_rel_text(gs + "BottomJoinRow/QuickJoinPanel/JoinBox/LanRoomsRow/LanJoinBtns/RefreshLanBtn", "gallery.lan_search_btn")
	if join_status_label != null and not join_status_label.text.begins_with("🌐"):
		join_status_label.text = I18nServiceScript.t("gallery.join_tip")
	_set_rel_text(gs + "BottomJoinRow/ExternalModulePanel/ModBox/ModTitle", "gallery.mod_title")
	_set_rel_text(gs + "BottomJoinRow/ExternalModulePanel/ModBox/ModHint", "gallery.mod_hint")
	_set_rel_placeholder(gs + "BottomJoinRow/ExternalModulePanel/ModBox/ExternalRow/PckPathEdit", "gallery.mod_placeholder")
	_set_rel_text(gs + "BottomJoinRow/ExternalModulePanel/ModBox/ExternalRow/LoadPckBtn", "gallery.mod_load_btn")
	if ext_status_label != null:
		ext_status_label.text = I18nServiceScript.t("gallery.mod_ready")

	# Step 2: Match Setup
	var ms = "HubShell/ContentStack/PlayTab/MatchSetupView/"
	_set_rel_text(ms + "SetupTopBar/BarRow/BackToGamesBtn", "setup.back_btn")
	_set_rel_text(ms + "SetupTopBar/BarRow/GameHeader", "setup.header")
	_set_rel_text(ms + "SetupTopBar/BarRow/OpenSettingsShortcutBtn", "setup.settings_shortcut")
	var sb = ms + "Columns/SetupPanel/SetupOuter/SetupScroll/SetupBox/"
	_set_rel_text(sb + "ModeLabel", "setup.mode_label")
	if mode_option != null and mode_option.item_count >= 3:
		mode_option.set_item_text(0, I18nServiceScript.t("setup.mode_solo"))
		mode_option.set_item_text(1, I18nServiceScript.t("setup.mode_pnp"))
		mode_option.set_item_text(2, I18nServiceScript.t("setup.mode_lan"))
	_set_rel_text(sb + "PlayerCountRow/PlayerCountLabel", "setup.players_label")
	if unlimited_lan_check != null:
		unlimited_lan_check.text = I18nServiceScript.t("setup.unlimited_lan")
	_set_rel_text(sb + "ExpansionsHeader", "setup.expansions_label")
	if no_mercy_check != null:
		no_mercy_check.text = I18nServiceScript.t("setup.no_mercy")
	if flip_mode_check != null:
		flip_mode_check.text = I18nServiceScript.t("setup.flip")
	if include_custom_check != null:
		include_custom_check.text = I18nServiceScript.t("setup.custom_cards")
	_set_rel_text(sb + "ExpansionsGrid/MercyLimitRow/MercyLbl", "setup.ko_limit")
	_set_rel_text(sb + "RulesHeader", "setup.rules_label")
	if stack_d2_check != null:
		stack_d2_check.text = I18nServiceScript.t("setup.stack_d2")
	if stack_d4_check != null:
		stack_d4_check.text = I18nServiceScript.t("setup.stack_d4")
	if jump_in_check != null:
		jump_in_check.text = I18nServiceScript.t("setup.jump_in")
	if seven_zero_check != null:
		seven_zero_check.text = I18nServiceScript.t("setup.seven_zero")
	if draw_match_check != null:
		draw_match_check.text = I18nServiceScript.t("setup.draw_match")
	if launch_uno_btn != null:
		launch_uno_btn.text = I18nServiceScript.t("setup.launch_btn")

	_set_rel_text(ms + "Columns/LobbyPanel/LobbyBox/LobbyHeader", "lobby.header")
	if copy_join_url_btn != null:
		copy_join_url_btn.text = I18nServiceScript.t("lobby.copy_btn")
	if _is_hosting:
		_refresh_host_urls_and_qr()
	else:
		if host_lan_btn != null:
			host_lan_btn.text = I18nServiceScript.t("lobby.host_start")
		if room_pin_label != null:
			room_pin_label.text = I18nServiceScript.t("lobby.room_pin_offline")
		if join_url_label != null:
			join_url_label.text = I18nServiceScript.t("lobby.short_url_hint")
		if table_url_label != null:
			table_url_label.text = I18nServiceScript.t("lobby.table_url_empty")

	# Settings Tab
	var st_vis = "HubShell/ContentStack/SettingsTab/SettingsColumns/VisualSettingsPanel/VisualBox/"
	_set_rel_text(st_vis + "VisualTitle", "settings.visual_title")
	_set_rel_text(st_vis + "LanguageRow/LanguageLabel", "settings.language_label")
	_set_rel_text(st_vis + "ViewModeRow/ViewLabel", "settings.view_mode")
	_set_rel_text(st_vis + "SkinRow/SkinLabel", "settings.card_skin")
	_set_rel_text(st_vis + "ThemeRow/ThemeLabel", "settings.table_theme")
	_set_rel_text(st_vis + "QualityRow/QualityLabel", "settings.quality")
	_set_rel_text(st_vis + "SpeedRow/SpeedLabel", "settings.bot_speed")
	if colorblind_check != null:
		colorblind_check.text = I18nServiceScript.t("settings.colorblind")
	_set_rel_text(st_vis + "SaveVisualSettingsBtn", "settings.save_visual_btn")

	var st_net = "HubShell/ContentStack/SettingsTab/SettingsColumns/NetworkSettingsPanel/NetBox/"
	_set_rel_text(st_net + "NetTitle", "settings.net_title")
	_set_rel_text(st_net + "TurnUrlLbl", "settings.turn_label")
	_set_rel_placeholder(st_net + "TurnUrlEdit", "settings.turn_url_placeholder")
	_set_rel_placeholder(st_net + "TurnCredsRow/TurnUserEdit", "settings.turn_user_placeholder")
	_set_rel_placeholder(st_net + "TurnCredsRow/TurnPassEdit", "settings.turn_pass_placeholder")
	_set_rel_text(st_net + "SaveNetworkSettingsBtn", "settings.save_net_btn")
	_set_rel_text(st_net + "TurnHelpPanel/TurnHelpScroll/TurnHelpLabel", "settings.turn_help")

	# Friends & Updater Tabs
	_set_rel_text("HubShell/ContentStack/FriendsTab/FriendsBox/FriendsTitle", "friends.title")
	_set_rel_text("HubShell/ContentStack/FriendsTab/FriendsBox/AddFriendRow/AddFriendBtn", "friends.add_btn")
	_set_rel_text("HubShell/ContentStack/UpdaterTab/UpdaterBox/UpdaterHeader", "updater.title")
	_set_rel_text("HubShell/ContentStack/UpdaterTab/UpdaterBox/CheckUpdatesBtn", "updater.check_btn")

	_apply_turn_config_from_inputs()
	_refresh_lan_rooms_list()
	_refresh_friends_ui()
	if stats_tab != null and stats_tab.has_method("apply_language"):
		stats_tab.apply_language()
	if profile_tab != null and profile_tab.has_method("apply_language"):
		profile_tab.apply_language()
	if _active_uno_view != null and _active_uno_view.has_method("apply_language"):
		_active_uno_view.apply_language()

func _init_lan_ip_options() -> void:
	if lan_ip_option == null or _http_host == null:
		return
	lan_ip_option.clear()
	var ips: Array[String] = _http_host.get_lan_ips()
	if ips.is_empty():
		lan_ip_option.add_item("127.0.0.1 (Lokal)", 0)
		lan_ip_option.set_item_metadata(0, "127.0.0.1")
	else:
		for i in range(ips.size()):
			var ip = ips[i]
			var label = ip + (" (Empfohlen)" if i == 0 else "")
			lan_ip_option.add_item(label, i)
			lan_ip_option.set_item_metadata(i, ip)
		lan_ip_option.select(0)
		_http_host.set_preferred_ip(ips[0])

func _on_lan_ip_selected(index: int) -> void:
	if lan_ip_option == null or _http_host == null:
		return
	var ip = str(lan_ip_option.get_item_metadata(index))
	_http_host.set_preferred_ip(ip)
	if _is_hosting:
		_refresh_host_urls_and_qr()

func _apply_turn_config_from_inputs() -> void:
	if _webrtc == null:
		return
	var t_url = turn_url_edit.text.strip_edges() if turn_url_edit != null else ""
	var t_user = turn_user_edit.text.strip_edges() if turn_user_edit != null else ""
	var t_pass = turn_pass_edit.text if turn_pass_edit != null else ""
	_webrtc.configure_custom_turn(t_url, t_user, t_pass)

	if stun_label != null:
		if t_url.is_empty():
			stun_label.text = I18nServiceScript.t("lobby.stun_default", {"stun": ConstantsScript.DEFAULT_SIGNALING_STUN})
		else:
			stun_label.text = I18nServiceScript.t("lobby.stun_turn", {"turn": t_url})

func save_settings() -> void:
	var lang_m = _get_selected_meta(language_option, I18nServiceScript.get_active_language())
	var view_m = _get_selected_meta(view_mode_option, "full_3d")
	var skin_m = _get_selected_meta(skin_option, "classic_arcade")
	var theme_m = _get_selected_meta(theme_option, "arcade_ps5")
	var quality_m = _get_selected_meta(quality_option, "high")
	var speed_m = _get_selected_meta(bot_speed_option, "normal")
	var cb_mode = colorblind_check.button_pressed if colorblind_check != null else true
	var t_url = turn_url_edit.text.strip_edges() if turn_url_edit != null else ""
	var t_user = turn_user_edit.text.strip_edges() if turn_user_edit != null else ""
	var t_pass = turn_pass_edit.text if turn_pass_edit != null else ""

	if not lang_m.is_empty():
		I18nServiceScript.set_language(lang_m)
		apply_language()
	_apply_turn_config_from_inputs()
	_update_3d_preview()

	var ok = false
	if _profile_svc != null:
		ok = _profile_svc.update_profile({
			"language": lang_m,
			"view_mode": view_m,
			"card_skin": skin_m,
			"theme_preset": theme_m,
			"quality_preset": quality_m,
			"bot_speed": speed_m,
			"colorblind_mode": cb_mode,
			"turn_url": t_url,
			"turn_username": t_user,
			"turn_credential": t_pass
		})

	if settings_status_label != null:
		settings_status_label.text = I18nServiceScript.t("settings.saved_ok") if ok else I18nServiceScript.t("settings.saved_ok")

func _get_selected_meta(opt: OptionButton, fallback: String) -> String:
	if opt != null and opt.selected >= 0:
		var m = str(opt.get_item_metadata(opt.selected))
		if not m.is_empty():
			return m
	return fallback

func _update_3d_preview() -> void:
	if preview_viewport == null:
		return
	var theme_id = _get_selected_meta(theme_option, "arcade_ps5")
	if not TABLE_SCENES.has(theme_id):
		theme_id = "arcade_ps5"

	var quality = _get_selected_meta(quality_option, "high")
	var skin_id = _get_selected_meta(skin_option, "classic_arcade")

	if active_preview_table_3d != null:
		if active_preview_table_3d.get_parent() == preview_viewport:
			preview_viewport.remove_child(active_preview_table_3d)
		active_preview_table_3d.queue_free()
		active_preview_table_3d = null
		_preview_showcase_root = null

	var scene_path = TABLE_SCENES[theme_id]
	if ResourceLoader.exists(scene_path):
		var packed = load(scene_path)
		if packed is PackedScene:
			var inst = packed.instantiate()
			if inst is Node3D:
				active_preview_table_3d = inst
				preview_viewport.add_child(active_preview_table_3d)
				if active_preview_table_3d.has_method("apply_quality_preset"):
					active_preview_table_3d.apply_quality_preset(quality)
				_spawn_preview_3d_cards(skin_id)

func _spawn_preview_3d_cards(skin_id: String = "classic_arcade") -> void:
	if active_preview_table_3d == null or CardMeshScene == null:
		return
	_preview_showcase_root = Node3D.new()
	_preview_showcase_root.name = "PreviewShowcaseRoot"
	_preview_showcase_root.position = Vector3(0.0, 0.85, 0.0)
	active_preview_table_3d.add_child(_preview_showcase_root)

	var ring = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 0.28
	torus.outer_radius = 0.30
	ring.mesh = torus
	ring.position = Vector3(0.0, -0.09, 0.0)
	var ring_mat = StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.0, 0.88, 1.0)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.0, 0.88, 1.0)
	ring_mat.emission_energy_multiplier = 1.6
	ring.material_override = ring_mat
	_preview_showcase_root.add_child(ring)

	var showcase_cards = [
		{ "id": "p1", "color": "red", "value": "7" },
		{ "id": "p2", "color": "blue", "value": "reverse" },
		{ "id": "p3", "color": "green", "value": "draw_two" },
		{ "id": "p4", "color": "wild", "value": "wild_draw_four" },
		{ "id": "p5", "color": "yellow", "value": "9" }
	]
	for i in range(showcase_cards.size()):
		var card = CardMeshScene.instantiate()
		if card != null:
			var ang = float(i) * TAU / float(showcase_cards.size())
			card.position = Vector3(cos(ang) * 0.22, 0.04, sin(ang) * 0.22)
			card.transform.basis = Basis(Vector3.UP, -ang + PI * 0.5) * Basis(Vector3.RIGHT, deg_to_rad(56.0))
			card.scale = Vector3.ONE * 2.2
			CardTextureGenScript.apply_card_materials_to_mesh(card, showcase_cards[i], skin_id, true, true)
			_preview_showcase_root.add_child(card)

func _on_preview_setting_changed(_idx: int) -> void:
	_update_3d_preview()

func _select_option_by_meta(opt: OptionButton, meta_val: String) -> void:
	if opt == null:
		return
	for i in range(opt.item_count):
		if str(opt.get_item_metadata(i)) == meta_val:
			opt.select(i)
			return

func _wire_embedded_screens() -> void:
	if profile_tab != null:
		if profile_tab.has_signal("back_requested"):
			profile_tab.back_requested.connect(func(): select_tab("play"))
		if profile_tab.has_signal("profile_saved"):
			profile_tab.profile_saved.connect(_on_profile_saved)
	if stats_tab != null and stats_tab.has_signal("back_requested"):
		stats_tab.back_requested.connect(func(): select_tab("play"))

func _on_profile_saved(prof: Dictionary) -> void:
	_select_option_by_meta(theme_option, str(prof.get("theme_preset", "arcade_ps5")))
	_select_option_by_meta(quality_option, str(prof.get("quality_preset", "high")))
	if colorblind_check != null and prof.has("colorblind_mode"):
		colorblind_check.button_pressed = bool(prof.get("colorblind_mode", true))
	_update_3d_preview()
	_refresh_friends_ui()

func select_tab(tab_id: String) -> bool:
	var key = tab_id.to_lower().strip_edges()
	if not _tabs_map.has(key):
		return false

	_active_tab_id = key
	if hub_shell != null:
		hub_shell.visible = true
	if active_match_host != null:
		active_match_host.visible = false

	for k in _tabs_map.keys():
		var node = _tabs_map[k]
		if node != null:
			node.visible = (node == _tabs_map[key])

	for k in _tab_buttons_map.keys():
		var btn: Button = _tab_buttons_map[k]
		if btn != null:
			if k == key:
				btn.add_theme_stylebox_override("normal", UIThemeScript.make_pill_button(Color(0.16, 0.26, 0.44, 0.96), UIThemeScript.COL_BORDER_GOLD, 12, 16, 9))
			else:
				btn.remove_theme_stylebox_override("normal")

	if key == "stats" and stats_tab != null and stats_tab.has_method("refresh_stats"):
		stats_tab.refresh_stats()
	elif key == "friends":
		_refresh_friends_ui()

	return true

func is_hosting_lan() -> bool:
	return _is_hosting

func start_lan_host(http_port: int = ConstantsScript.DEFAULT_PORT, ws_port: int = 8081) -> Dictionary:
	stop_lan_host()
	_init_lan_ip_options()

	var http_err = _http_host.start(http_port, "*", "res://web_lite")
	if http_err != OK and http_port != 0:
		http_err = _http_host.start(0, "*", "res://web_lite")
	if http_err != OK:
		return { "success": false, "error": "HTTP server start failed: %d" % http_err }

	var ws_err = _ws_host.start(ws_port, "*")
	if ws_err != OK and ws_port != 0:
		ws_err = _ws_host.start(0, "*")
	if ws_err != OK:
		_http_host.stop()
		return { "success": false, "error": "WebSocket server start failed: %d" % ws_err }

	var actual_http_port: int = _http_host.get_port()
	var actual_ws_port: int = _ws_host.get_port()
	var lan_ip: String = _http_host.get_lan_ip()

	var max_p = 0
	if unlimited_lan_check != null and not unlimited_lan_check.button_pressed and player_count_spin != null:
		max_p = maxi(2, int(player_count_spin.value))

	_room_manager = RoomManagerScript.new("", max_p, lan_ip, actual_http_port, actual_ws_port)
	var room_code: String = _room_manager.room_code

	_http_host.set_room_metadata({
		"room_code": room_code,
		"ws_port": actual_ws_port,
		"role": "player",
		"game_name": I18nServiceScript.t("stats.game_uno")
	})

	_webrtc.initialize_session(room_code, "", true, "host")
	_lan_discovery.start_broadcasting({
		"room_code": room_code,
		"game_id": "uno",
		"host_name": str(_profile_svc.get_profile().get("display_name", "DeckBox Host")),
		"app_version": ConstantsScript.APP_VERSION,
		"http_port": actual_http_port,
		"ws_port": actual_ws_port
	})

	_is_hosting = true
	_refresh_host_urls_and_qr()
	return _last_host_info

func _refresh_host_urls_and_qr() -> void:
	if not _is_hosting or _http_host == null or _room_manager == null:
		return
	var actual_http_port: int = _http_host.get_port()
	var actual_ws_port: int = _ws_host.get_port()
	var lan_ip: String = _http_host.get_lan_ip()
	var room_code: String = _room_manager.room_code
	var max_p: int = _room_manager.max_players

	var short_url = _http_host.get_serve_url("", "player", true)
	var table_url = "http://%s:%d/?room=%s&role=table&ws=%d" % [lan_ip, actual_http_port, room_code, actual_ws_port]

	_handshake.configure_host({
		"app_version": ConstantsScript.APP_VERSION,
		"protocol_version": ConstantsScript.PROTOCOL_VERSION,
		"rules_hash": "",
		"room_code": room_code,
		"host_ip": lan_ip,
		"http_port": actual_http_port,
		"max_players": max_p
	})

	if qr_texture_rect != null:
		qr_texture_rect.texture = QRCodeScript.generate_texture(short_url, 6, 2)
	if qr_backplate != null:
		qr_backplate.visible = true
	if room_pin_label != null:
		var cap_label = I18nServiceScript.t("lobby.cap_unlimited") if max_p <= 0 else I18nServiceScript.t("lobby.cap_seats", {"count": max_p})
		room_pin_label.text = I18nServiceScript.t("lobby.room_pin_fmt", {"pin": room_code, "cap": cap_label})
	if join_url_label != null:
		join_url_label.text = I18nServiceScript.t("lobby.short_url_fmt", {"url": short_url})
	if table_url_label != null:
		table_url_label.text = I18nServiceScript.t("lobby.table_url_fmt", {"url": table_url})
	if host_lan_btn != null:
		host_lan_btn.text = I18nServiceScript.t("lobby.host_stop")
	if copy_join_url_btn != null:
		copy_join_url_btn.disabled = false

	_last_host_info = {
		"success": true,
		"room_code": room_code,
		"http_port": actual_http_port,
		"ws_port": actual_ws_port,
		"join_url": short_url,
		"table_url": table_url
	}

func stop_lan_host() -> void:
	if _http_host != null:
		_http_host.stop()
	if _ws_host != null:
		_ws_host.stop()
	if _lan_discovery != null:
		_lan_discovery.stop_broadcasting()
	_is_hosting = false
	_last_host_info = {}
	if qr_backplate != null:
		qr_backplate.visible = false
	if qr_texture_rect != null:
		qr_texture_rect.texture = null
	if host_lan_btn != null:
		host_lan_btn.text = I18nServiceScript.t("lobby.host_start")
	if copy_join_url_btn != null:
		copy_join_url_btn.disabled = true
	if room_pin_label != null:
		room_pin_label.text = I18nServiceScript.t("lobby.room_pin_offline")
	if join_url_label != null:
		join_url_label.text = I18nServiceScript.t("lobby.short_url_hint")
	if table_url_label != null:
		table_url_label.text = I18nServiceScript.t("lobby.table_url_empty")

func _on_host_lan_btn_pressed() -> void:
	if _is_hosting:
		stop_lan_host()
	else:
		start_lan_host()

func _on_copy_join_url_pressed() -> void:
	var url = str(_last_host_info.get("join_url", ""))
	if url.is_empty():
		return
	DisplayServer.clipboard_set(url)
	if join_url_label != null:
		join_url_label.text = I18nServiceScript.t("lobby.copied_fmt", {"url": url})

# --- LAN Discovery & Direct Join for PC Players ---

func _start_lan_discovery_listener() -> void:
	if _lan_discovery == null:
		return
	var err = _lan_discovery.start_listening()
	_is_listening_lan = (err == OK)
	_refresh_lan_rooms_list()

func _on_refresh_lan_rooms_pressed() -> void:
	if not _is_listening_lan:
		_start_lan_discovery_listener()
	_refresh_lan_rooms_list()

func _on_lan_rooms_changed(_room: Dictionary) -> void:
	_refresh_lan_rooms_list()

func _on_lan_room_expired(_code: String) -> void:
	_refresh_lan_rooms_list()

func _refresh_lan_rooms_list() -> void:
	if lan_rooms_list == null or _lan_discovery == null:
		return
	lan_rooms_list.clear()
	_discovered_rooms_cache = _lan_discovery.get_discovered_rooms()
	if _discovered_rooms_cache.is_empty():
		lan_rooms_list.add_item(I18nServiceScript.t("gallery.no_lan_rooms"))
		return
	for room in _discovered_rooms_cache:
		var host_name = str(room.get("host_name", "DeckBox"))
		var host_ip = str(room.get("host_ip", "127.0.0.1"))
		var http_p = int(room.get("http_port", 8080))
		var pin = str(room.get("room_code", "----"))
		lan_rooms_list.add_item("%s • PIN %s (http://%s:%d)" % [host_name, pin, host_ip, http_p])

func _on_join_selected_lan_room_pressed() -> void:
	if lan_rooms_list == null or _discovered_rooms_cache.is_empty():
		return
	var sel = lan_rooms_list.get_selected_items()
	if sel.is_empty():
		return
	var idx = sel[0]
	if idx < 0 or idx >= _discovered_rooms_cache.size():
		return
	var r = _discovered_rooms_cache[idx]
	var url = "http://%s:%d" % [str(r.get("host_ip", "127.0.0.1")), int(r.get("http_port", 8080))]
	_open_join_url(url)

func _on_join_direct_pressed() -> void:
	if join_address_edit == null:
		return
	var raw = join_address_edit.text.strip_edges()
	if raw.is_empty():
		if join_status_label != null:
			join_status_label.text = I18nServiceScript.t("gallery.join_enter_ip")
		return
	var url = raw
	if not url.begins_with("http://") and not url.begins_with("https://"):
		if not (":" in url):
			url = "http://%s:%d" % [url, ConstantsScript.DEFAULT_PORT]
		else:
			url = "http://%s" % url
	_open_join_url(url)

func _open_join_url(url: String) -> void:
	OS.shell_open(url)
	if join_status_label != null:
		join_status_label.text = I18nServiceScript.t("gallery.join_opened", {"url": url})

func _on_ws_packet_received(peer_id: int, envelope: Dictionary) -> void:
	var msg_type = str(envelope.get("type", ""))
	if msg_type == "JOIN_REQUEST":
		var resp = _handshake.evaluate_join_request(envelope)
		if _ws_host != null:
			_ws_host.send_to(peer_id, resp)
			var payload = resp.get("payload", {})
			if payload.get("status") == "ACCEPTED" and _active_uno_view != null and _active_uno_view.cartridge != null:
				var pub = _active_uno_view.cartridge.get_public_state()
				_ws_host.send_to(peer_id, _ws_host.build_envelope("STATE_PUBLIC", pub))

func _on_no_mercy_toggled(toggled_on: bool) -> void:
	if mercy_limit_spin != null:
		mercy_limit_spin.value = 25.0 if toggled_on else 0.0
	if toggled_on:
		if stack_d2_check != null:
			stack_d2_check.button_pressed = true
		if stack_d4_check != null:
			stack_d4_check.button_pressed = true

func _gather_match_options() -> Dictionary:
	var mode = _get_selected_meta(mode_option, "solo")
	if mode == "lan_host" and not _is_hosting:
		start_lan_host()

	var view_m = _get_selected_meta(view_mode_option, "full_3d")
	var skin_m = _get_selected_meta(skin_option, "classic_arcade")
	var theme_m = _get_selected_meta(theme_option, "arcade_ps5")
	var quality = _get_selected_meta(quality_option, "high")
	var speed_m = _get_selected_meta(bot_speed_option, "normal")

	var no_mercy_on = no_mercy_check.button_pressed if no_mercy_check != null else false
	var flip_on = flip_mode_check.button_pressed if flip_mode_check != null else false
	var mercy_limit = int(mercy_limit_spin.value) if mercy_limit_spin != null else (25 if no_mercy_on else 0)
	var custom_cards_arr: Array = []
	if include_custom_check != null and include_custom_check.button_pressed and pack_editor_tab != null:
		if "model" in pack_editor_tab and pack_editor_tab.model != null and pack_editor_tab.model.has_method("get_custom_cards"):
			custom_cards_arr = pack_editor_tab.model.get_custom_cards()

	var prof = _profile_svc.get_profile()
	var cb_mode = colorblind_check.button_pressed if colorblind_check != null else bool(prof.get("colorblind_mode", true))
	var opts = {
		"mode": "pass_and_play" if mode == "pass_and_play" else "solo",
		"player_count": maxi(2, int(player_count_spin.value)) if player_count_spin != null else 4,
		"player_name": str(prof.get("display_name", "Du")),
		"view_mode": view_m,
		"card_skin": skin_m,
		"theme": theme_m,
		"quality": quality,
		"bot_speed": speed_m,
		"colorblind_mode": cb_mode,
		"rules": {
			"stacking_draw_two": stack_d2_check.button_pressed if stack_d2_check != null else false,
			"stacking_draw_four": stack_d4_check.button_pressed if stack_d4_check != null else false,
			"jump_in": jump_in_check.button_pressed if jump_in_check != null else false,
			"seven_zero_passing": seven_zero_check.button_pressed if seven_zero_check != null else false,
			"draw_to_match": draw_match_check.button_pressed if draw_match_check != null else false,
			"expansion_no_mercy": no_mercy_on,
			"expansion_flip": flip_on,
			"progressive_stacking": no_mercy_on,
			"mercy_hand_limit": mercy_limit,
			"skip_everyone_enabled": no_mercy_on,
			"discard_all_enabled": no_mercy_on,
			"custom_cards": custom_cards_arr
		}
	}
	if _is_hosting and not _last_host_info.is_empty():
		opts["join_url"] = _last_host_info.get("join_url", "")
		opts["room_code"] = _last_host_info.get("room_code", "")
	return opts

func start_uno_match(custom_options: Dictionary = {}) -> bool:
	var opts = custom_options if not custom_options.is_empty() else _gather_match_options()
	if active_match_host == null or UnoGameScene == null:
		return false

	if _active_uno_view != null:
		_active_uno_view.queue_free()
		_active_uno_view = null

	var inst = UnoGameScene.instantiate()
	if not (inst is Control):
		return false

	_active_uno_view = inst
	active_match_host.add_child(_active_uno_view)
	if _active_uno_view.has_signal("back_requested"):
		_active_uno_view.back_requested.connect(_on_match_back_requested)
	if _active_uno_view.has_method("configure_match"):
		_active_uno_view.configure_match(opts)

	if hub_shell != null:
		hub_shell.visible = false
	active_match_host.visible = true
	return true

func _on_match_back_requested() -> void:
	if _active_uno_view != null:
		_active_uno_view.queue_free()
		_active_uno_view = null
	select_tab("play")

func _on_load_external_pck_pressed() -> void:
	if pck_path_edit == null or _ext_loader == null:
		return
	var path = pck_path_edit.text.strip_edges()
	var res = _ext_loader.load_cartridge_package(path, _registry)
	if ext_status_label != null:
		if res.get("success", false):
			ext_status_label.text = "Externes Modul geladen: %s" % str(res.get("game_id", ""))
		else:
			ext_status_label.text = "Ladefehler: %s" % str(res.get("error", "Unbekannter Fehler"))

func _refresh_friends_ui() -> void:
	if _friends_svc == null:
		return
	_friends_svc.load_friends()
	var prof = _profile_svc.get_profile()
	var identity = _friends_svc.init_identity(str(prof.get("display_name", "Player")))
	var payload_str = _friends_svc.generate_qr_payload()

	if my_uuid_label != null:
		my_uuid_label.text = "Deine UUID: %s (%s)" % [str(identity.get("uuid", "")), str(identity.get("display_name", "Player"))]
	if my_friend_payload_edit != null:
		my_friend_payload_edit.text = payload_str
	if my_friend_qr_rect != null:
		my_friend_qr_rect.texture = QRCodeScript.generate_texture(payload_str, 4, 2)

	if friends_list_box != null:
		for child in friends_list_box.get_children():
			child.queue_free()
		var list = _friends_svc.get_friends()
		if list.is_empty():
			var empty_lbl = Label.new()
			empty_lbl.text = I18nServiceScript.t("friends.empty")
			friends_list_box.add_child(empty_lbl)
		else:
			for f in list:
				var lbl = Label.new()
				lbl.text = "%s — UUID: %s" % [str(f.get("display_name", "Friend")), str(f.get("uuid", "")).substr(0, 8)]
				friends_list_box.add_child(lbl)

func _on_add_friend_pressed() -> void:
	if add_friend_payload_edit == null or _friends_svc == null:
		return
	var raw = add_friend_payload_edit.text.strip_edges()
	var parsed = _friends_svc.parse_qr_payload(raw)
	if parsed.get("success", false):
		var friend_data = parsed.get("friend", parsed)
		_friends_svc.add_friend(friend_data)
		_friends_svc.save_friends()
		add_friend_payload_edit.text = ""
		if friends_status_label != null:
			friends_status_label.text = "Freund erfolgreich hinzugefügt."
		_refresh_friends_ui()
	else:
		if friends_status_label != null:
			friends_status_label.text = "Ungültiger Freundes-QR-Payload: %s" % str(parsed.get("error", ""))

func _on_check_updates_pressed() -> void:
	if updater_status_label != null:
		updater_status_label.text = "Frage GitHub Releases ab (%s)..." % ReleaseUpdaterScript.REPO_URL
	if github_http_req != null:
		github_http_req.request(ReleaseUpdaterScript.REPO_URL, ["User-Agent: DeckBox/" + ConstantsScript.APP_VERSION])

func _on_github_releases_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if releases_list != null:
		releases_list.clear()
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		if updater_status_label != null:
			updater_status_label.text = "Releases konnten nicht geladen werden (HTTP %d)." % response_code
		return

	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Array):
		if updater_status_label != null:
			updater_status_label.text = "Unerwartetes GitHub API-Format."
		return

	var plat = OS.get_name()
	var count = 0
	for rel in parsed:
		if not (rel is Dictionary):
			continue
		var tag = str(rel.get("tag_name", ""))
		var is_down = _updater.is_downgrade(ConstantsScript.APP_VERSION, tag)
		var cmp = _updater.compare_versions(tag, ConstantsScript.APP_VERSION)
		var kind = "Aktuell"
		if cmp > 0:
			kind = "Update verfügbar"
		elif is_down:
			kind = "Downgrade-Ziel"
		var asset = _updater.resolve_asset(rel.get("assets", []), plat)
		var asset_info = str(asset.get("name", "Quellcode / Kein Binary für " + plat))
		if releases_list != null:
			releases_list.add_item("%s [%s] — %s" % [tag, kind, asset_info])
		count += 1

	if updater_status_label != null:
		updater_status_label.text = "%d Release(s) für %s gefunden (Aktuell: v%s)." % [count, plat, ConstantsScript.APP_VERSION]
