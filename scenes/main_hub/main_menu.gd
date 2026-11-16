# scenes/main_hub/main_menu.gd
# Central DeckBox Collection Hub connecting Games, LAN/QR Lobby, 3D Table Preview, Friends, Pack Editor, Profile, Stats, and Updater.
class_name MainMenuHub
extends Control

const ConstantsScript = preload("res://core/constants.gd")
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
var _active_uno_view: Control = null
var _active_tab_id: String = "play"
var _last_host_info: Dictionary = {}
var active_preview_table_3d: Node3D = null
var _preview_showcase_root: Node3D = null

@onready var hub_shell: VBoxContainer = $HubShell
@onready var active_match_host: Control = $ActiveMatchHost
@onready var version_badge: Label = $HubShell/TopBar/VersionBadge

@onready var play_tab: Control = $HubShell/ContentStack/PlayTab
@onready var friends_tab: Control = $HubShell/ContentStack/FriendsTab
@onready var pack_editor_tab: Control = $HubShell/ContentStack/PackEditorTab
@onready var profile_tab: Control = $HubShell/ContentStack/ProfileTab
@onready var stats_tab: Control = $HubShell/ContentStack/StatsTab
@onready var updater_tab: Control = $HubShell/ContentStack/UpdaterTab

@onready var mode_option: OptionButton = $HubShell/ContentStack/PlayTab/Columns/SetupPanel/SetupBox/ModeOption
@onready var player_count_spin: SpinBox = $HubShell/ContentStack/PlayTab/Columns/SetupPanel/SetupBox/PlayerCountRow/PlayerCountSpin
@onready var theme_option: OptionButton = $HubShell/ContentStack/PlayTab/Columns/SetupPanel/SetupBox/ThemeOption
@onready var quality_option: OptionButton = $HubShell/ContentStack/PlayTab/Columns/SetupPanel/SetupBox/QualityOption
@onready var stack_d2_check: CheckBox = $HubShell/ContentStack/PlayTab/Columns/SetupPanel/SetupBox/RulesGrid/StackD2Check
@onready var stack_d4_check: CheckBox = $HubShell/ContentStack/PlayTab/Columns/SetupPanel/SetupBox/RulesGrid/StackD4Check
@onready var jump_in_check: CheckBox = $HubShell/ContentStack/PlayTab/Columns/SetupPanel/SetupBox/RulesGrid/JumpInCheck
@onready var seven_zero_check: CheckBox = $HubShell/ContentStack/PlayTab/Columns/SetupPanel/SetupBox/RulesGrid/SevenZeroCheck
@onready var draw_match_check: CheckBox = $HubShell/ContentStack/PlayTab/Columns/SetupPanel/SetupBox/RulesGrid/DrawMatchCheck
@onready var pck_path_edit: LineEdit = $HubShell/ContentStack/PlayTab/Columns/SetupPanel/SetupBox/ExternalRow/PckPathEdit
@onready var ext_status_label: Label = $HubShell/ContentStack/PlayTab/Columns/SetupPanel/SetupBox/ExternalStatusLabel

@onready var preview_viewport: SubViewport = $HubShell/ContentStack/PlayTab/Columns/LobbyPanel/LobbyBox/PreviewViewportContainer/PreviewViewport
@onready var host_lan_btn: Button = $HubShell/ContentStack/PlayTab/Columns/LobbyPanel/LobbyBox/HostLanBtn
@onready var room_pin_label: Label = $HubShell/ContentStack/PlayTab/Columns/LobbyPanel/LobbyBox/RoomPinLabel
@onready var join_url_label: Label = $HubShell/ContentStack/PlayTab/Columns/LobbyPanel/LobbyBox/JoinUrlLabel
@onready var table_url_label: Label = $HubShell/ContentStack/PlayTab/Columns/LobbyPanel/LobbyBox/TableUrlLabel
@onready var stun_label: Label = $HubShell/ContentStack/PlayTab/Columns/LobbyPanel/LobbyBox/StunLabel
@onready var qr_texture_rect: TextureRect = $HubShell/ContentStack/PlayTab/Columns/LobbyPanel/LobbyBox/QrCenter/QRTextureRect

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

func _ready() -> void:
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

	_tabs_map = {
		"play": play_tab,
		"lobby": play_tab,
		"friends": friends_tab,
		"pack_editor": pack_editor_tab,
		"profile": profile_tab,
		"stats": stats_tab,
		"updater": updater_tab
	}

	if version_badge != null:
		version_badge.text = "v%s" % ConstantsScript.APP_VERSION

	_init_play_options()
	_wire_embedded_screens()
	_refresh_friends_ui()
	_update_3d_preview()
	select_tab("play")

func _exit_tree() -> void:
	stop_lan_host()

func _process(delta: float) -> void:
	if _is_hosting:
		if _http_host != null:
			_http_host.poll()
		if _ws_host != null:
			_ws_host.poll()
		if _lan_discovery != null:
			_lan_discovery.poll()
	if _preview_showcase_root != null and is_instance_valid(_preview_showcase_root):
		_preview_showcase_root.rotate_y(delta * 0.65)

func _init_play_options() -> void:
	if mode_option != null:
		mode_option.clear()
		mode_option.add_item("Solo vs. 3 KI-Bots", 0)
		mode_option.set_item_metadata(0, "solo")
		mode_option.add_item("Pass & Play (Hot-Seat)", 1)
		mode_option.set_item_metadata(1, "pass_and_play")
		mode_option.add_item("LAN / QR Multiplayer Host", 2)
		mode_option.set_item_metadata(2, "lan_host")

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

	var prof = _profile_svc.load_profile()
	var pref_theme = str(prof.get("theme_preset", "arcade_ps5"))
	var pref_quality = str(prof.get("quality_preset", "high"))
	_select_option_by_meta(theme_option, pref_theme)
	_select_option_by_meta(quality_option, pref_quality)

	if stun_label != null and _webrtc != null:
		stun_label.text = "Online P2P STUN: %s (Zero Secrets)" % ConstantsScript.DEFAULT_SIGNALING_STUN

func _update_3d_preview() -> void:
	if preview_viewport == null:
		return
	var theme_id = "arcade_ps5"
	if theme_option != null and theme_option.selected >= 0:
		theme_id = str(theme_option.get_item_metadata(theme_option.selected))
	if not TABLE_SCENES.has(theme_id):
		theme_id = "arcade_ps5"

	var quality = "high"
	if quality_option != null and quality_option.selected >= 0:
		quality = str(quality_option.get_item_metadata(quality_option.selected))

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
				_spawn_preview_3d_cards()

func _spawn_preview_3d_cards() -> void:
	if active_preview_table_3d == null or CardMeshScene == null:
		return
	_preview_showcase_root = Node3D.new()
	_preview_showcase_root.name = "PreviewShowcaseRoot"
	_preview_showcase_root.position = Vector3(0.0, 0.85, 0.0)
	active_preview_table_3d.add_child(_preview_showcase_root)

	var ring = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 0.28
	torus.outer_radius = 0.31
	ring.mesh = torus
	ring.position = Vector3(0.0, -0.09, 0.0)
	var ring_mat = StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.0, 0.88, 1.0)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.0, 0.88, 1.0)
	ring_mat.emission_energy_multiplier = 1.6
	ring.material_override = ring_mat
	_preview_showcase_root.add_child(ring)

	var colors = [
		Color(0.86, 0.16, 0.18),
		Color(0.14, 0.42, 0.90),
		Color(0.14, 0.68, 0.30),
		Color(0.88, 0.70, 0.08)
	]
	for i in range(4):
		var card = CardMeshScene.instantiate()
		if card != null:
			var ang = float(i) * PI * 0.5
			card.position = Vector3(cos(ang) * 0.18, 0.02, sin(ang) * 0.18)
			card.rotation_degrees = Vector3(-35.0, rad_to_deg(-ang) + 90.0, 0.0)
			card.scale = Vector3.ONE * 2.1
			var mesh_inst = _find_mesh(card)
			if mesh_inst != null:
				var m = StandardMaterial3D.new()
				m.albedo_color = colors[i]
				m.roughness = 0.3
				mesh_inst.set_surface_override_material(0, m)
			_preview_showcase_root.add_child(card)

func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var f = _find_mesh(c)
		if f != null:
			return f
	return null

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

	if key == "stats" and stats_tab != null and stats_tab.has_method("refresh_stats"):
		stats_tab.refresh_stats()
	elif key == "friends":
		_refresh_friends_ui()

	return true

func is_hosting_lan() -> bool:
	return _is_hosting

func start_lan_host(http_port: int = ConstantsScript.DEFAULT_PORT, ws_port: int = 8081) -> Dictionary:
	stop_lan_host()

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

	_room_manager = RoomManagerScript.new("", 4, lan_ip, actual_http_port, actual_ws_port)
	var room_code: String = _room_manager.room_code

	var player_url = "http://%s:%d/?room=%s&role=player&ws=%d" % [lan_ip, actual_http_port, room_code, actual_ws_port]
	var table_url = "http://%s:%d/?room=%s&role=table&ws=%d" % [lan_ip, actual_http_port, room_code, actual_ws_port]

	_handshake.configure_host({
		"app_version": ConstantsScript.APP_VERSION,
		"protocol_version": ConstantsScript.PROTOCOL_VERSION,
		"rules_hash": "",
		"room_code": room_code,
		"host_ip": lan_ip,
		"http_port": actual_http_port,
		"max_players": 4
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

	if qr_texture_rect != null:
		qr_texture_rect.texture = QRCodeScript.generate_texture(player_url, 5, 2)
	if room_pin_label != null:
		room_pin_label.text = "Room PIN: %s (Host active)" % room_code
	if join_url_label != null:
		join_url_label.text = "Player URL: %s" % player_url
	if table_url_label != null:
		table_url_label.text = "Table Display URL: %s" % table_url
	if host_lan_btn != null:
		host_lan_btn.text = "Stop LAN / QR Host"

	_last_host_info = {
		"success": true,
		"room_code": room_code,
		"http_port": actual_http_port,
		"ws_port": actual_ws_port,
		"join_url": player_url,
		"table_url": table_url
	}
	return _last_host_info

func stop_lan_host() -> void:
	if _http_host != null:
		_http_host.stop()
	if _ws_host != null:
		_ws_host.stop()
	if _lan_discovery != null:
		_lan_discovery.stop_broadcasting()
		_lan_discovery.stop_listening()
	_is_hosting = false
	if host_lan_btn != null:
		host_lan_btn.text = "Start LAN / QR Host"
	if room_pin_label != null:
		room_pin_label.text = "Room PIN: ---- (Offline)"
	if join_url_label != null:
		join_url_label.text = "Player URL: (Start host to generate QR & link)"
	if table_url_label != null:
		table_url_label.text = "Table Display URL: ----"

func _on_host_lan_btn_pressed() -> void:
	if _is_hosting:
		stop_lan_host()
	else:
		start_lan_host()

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

func _gather_match_options() -> Dictionary:
	var mode = "solo"
	if mode_option != null and mode_option.selected >= 0:
		mode = str(mode_option.get_item_metadata(mode_option.selected))
	if mode == "lan_host" and not _is_hosting:
		start_lan_host()

	var theme = "arcade_ps5"
	if theme_option != null and theme_option.selected >= 0:
		theme = str(theme_option.get_item_metadata(theme_option.selected))

	var quality = "high"
	if quality_option != null and quality_option.selected >= 0:
		quality = str(quality_option.get_item_metadata(quality_option.selected))

	var prof = _profile_svc.get_profile()
	return {
		"mode": "pass_and_play" if mode == "pass_and_play" else "solo",
		"player_count": int(player_count_spin.value) if player_count_spin != null else 2,
		"player_name": str(prof.get("display_name", "You")),
		"theme": theme,
		"quality": quality,
		"colorblind_mode": bool(prof.get("colorblind_mode", false)),
		"rules": {
			"stacking_draw_two": stack_d2_check.button_pressed if stack_d2_check != null else false,
			"stacking_draw_four": stack_d4_check.button_pressed if stack_d4_check != null else false,
			"jump_in": jump_in_check.button_pressed if jump_in_check != null else false,
			"seven_zero_passing": seven_zero_check.button_pressed if seven_zero_check != null else false,
			"draw_to_match": draw_match_check.button_pressed if draw_match_check != null else false
		}
	}

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
			ext_status_label.text = "Loaded external cartridge: %s" % str(res.get("game_id", ""))
		else:
			ext_status_label.text = "Load error: %s" % str(res.get("error", "Unknown error"))

func _refresh_friends_ui() -> void:
	if _friends_svc == null:
		return
	_friends_svc.load_friends()
	var prof = _profile_svc.get_profile()
	var identity = _friends_svc.init_identity(str(prof.get("display_name", "Player")))
	var payload_str = _friends_svc.generate_qr_payload()

	if my_uuid_label != null:
		my_uuid_label.text = "Your UUID: %s (%s)" % [str(identity.get("uuid", "")), str(identity.get("display_name", "Player"))]
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
			empty_lbl.text = "No friends added yet. Share your QR code or paste a friend's payload above."
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
			friends_status_label.text = "Friend added successfully."
		_refresh_friends_ui()
	else:
		if friends_status_label != null:
			friends_status_label.text = "Invalid friend QR payload: %s" % str(parsed.get("error", ""))

func _on_check_updates_pressed() -> void:
	if updater_status_label != null:
		updater_status_label.text = "Checking GitHub Releases (%s)..." % ReleaseUpdaterScript.REPO_URL
	if github_http_req != null:
		github_http_req.request(ReleaseUpdaterScript.REPO_URL, ["User-Agent: DeckBox/" + ConstantsScript.APP_VERSION])

func _on_github_releases_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if releases_list != null:
		releases_list.clear()
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		if updater_status_label != null:
			updater_status_label.text = "Could not fetch releases (HTTP %d). Offline fallback stays available." % response_code
		return

	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Array):
		if updater_status_label != null:
			updater_status_label.text = "Unexpected GitHub API payload."
		return

	var plat = OS.get_name()
	var count = 0
	for rel in parsed:
		if not (rel is Dictionary):
			continue
		var tag = str(rel.get("tag_name", ""))
		var is_down = _updater.is_downgrade(ConstantsScript.APP_VERSION, tag)
		var cmp = _updater.compare_versions(tag, ConstantsScript.APP_VERSION)
		var kind = "Current"
		if cmp > 0:
			kind = "Update Available"
		elif is_down:
			kind = "Downgrade Target"
		var asset = _updater.resolve_asset(rel.get("assets", []), plat)
		var asset_info = str(asset.get("name", "Source / No binary for " + plat))
		if releases_list != null:
			releases_list.add_item("%s [%s] — %s" % [tag, kind, asset_info])
		count += 1

	if updater_status_label != null:
		updater_status_label.text = "Found %d release(s) for %s (Current: v%s)." % [count, plat, ConstantsScript.APP_VERSION]
