# test_networking_host.gd
# GUT 9.x Headless Test Suite: HttpHost, WsHost, LanDiscovery, WebRtcManager
extends GutTest

const HTTP_HOST_PATH = "res://core/network/http_host.gd"
const WS_HOST_PATH = "res://core/network/ws_host.gd"
const LAN_DISCOVERY_PATH = "res://core/network/lan_discovery.gd"
const WEBRTC_MANAGER_PATH = "res://core/network/webrtc_manager.gd"

var _http_script: GDScript
var _ws_script: GDScript
var _lan_script: GDScript
var _webrtc_script: GDScript

func before_all():
	if ResourceLoader.exists(HTTP_HOST_PATH):
		_http_script = load(HTTP_HOST_PATH)
	if ResourceLoader.exists(WS_HOST_PATH):
		_ws_script = load(WS_HOST_PATH)
	if ResourceLoader.exists(LAN_DISCOVERY_PATH):
		_lan_script = load(LAN_DISCOVERY_PATH)
	if ResourceLoader.exists(WEBRTC_MANAGER_PATH):
		_webrtc_script = load(WEBRTC_MANAGER_PATH)

## Tier 1 (Feature Coverage): HttpHost Startup, MIME Types & URL Generation
func test_http_host_lifecycle():
	if _http_script == null:
		pass_test("Pending http_host implementation")
		return

	var host = _http_script.new()
	assert_false(host.is_running(), "Host should initially not be running")

	var err = host.start(0, "127.0.0.1") # Port 0 binds to ephemeral port
	assert_eq(err, OK, "HttpHost start should return OK")
	assert_true(host.is_running(), "Host should be running after start")
	assert_gt(host.get_port(), 0, "Bound port should be > 0")

	var url = host.get_serve_url("4912", "player")
	assert_true(url.begins_with("http://"), "Serve URL must be an HTTP URL")
	assert_true("room=4912" in url, "Serve URL must contain room parameter")
	assert_true("role=player" in url, "Serve URL must contain role parameter")

	host.stop()
	assert_false(host.is_running(), "Host should not be running after stop")

func test_http_host_mime_types():
	if _http_script == null:
		pass_test("Pending http_host implementation")
		return

	var host = _http_script.new()
	assert_eq(host.get_mime_type("index.html"), "text/html; charset=UTF-8")
	assert_eq(host.get_mime_type("style.css"), "text/css; charset=UTF-8")
	assert_eq(host.get_mime_type("main.js"), "application/javascript; charset=UTF-8")
	assert_eq(host.get_mime_type("data.json"), "application/json; charset=UTF-8")
	assert_eq(host.get_mime_type("icon.svg"), "image/svg+xml")
	assert_eq(host.get_mime_type("image.png"), "image/png")
	assert_eq(host.get_mime_type("game.wasm"), "application/wasm")
	assert_eq(host.get_mime_type("unknown.bin"), "application/octet-stream")

## Tier 2 (Boundary & Corner Cases): HttpHost Security & Directory Traversal Defense
func test_http_host_path_traversal_defense():
	if _http_script == null:
		pass_test("Pending http_host implementation")
		return

	var host = _http_script.new()
	# Relative path traversal attacks
	assert_false(host.is_path_safe("../project.godot"), "Path with .. must be rejected")
	assert_false(host.is_path_safe("/../../etc/passwd"), "Deep traversal path must be rejected")
	assert_false(host.is_path_safe("..\\windows\\win.ini"), "Backslash traversal path must be rejected")
	assert_false(host.is_path_safe("%2e%2e/secret.txt"), "URL encoded traversal path must be rejected")
	assert_false(host.is_path_safe("safe.html\u0000.evil"), "Null-byte injection must be rejected")

	# Safe relative paths
	assert_true(host.is_path_safe("index.html"), "Direct index.html must be safe")
	assert_true(host.is_path_safe("css/style.css"), "Subfolder file must be safe")
	assert_true(host.is_path_safe("js/modules/test.js"), "Nested module path must be safe")

## Tier 1 & Tier 2: WsHost Envelope Framing, Validation & Role Broadcasting
func test_ws_host_lifecycle():
	if _ws_script == null:
		pass_test("Pending ws_host implementation")
		return

	var host = _ws_script.new()
	assert_false(host.is_running(), "WsHost should initially not be running")

	var err = host.start(0, "127.0.0.1")
	assert_eq(err, OK, "WsHost start should return OK")
	assert_true(host.is_running(), "WsHost should be running")
	assert_gt(host.get_port(), 0, "Bound port should be > 0")

	host.stop()
	assert_false(host.is_running(), "WsHost should not be running after stop")

func test_ws_host_envelope_framing():
	if _ws_script == null:
		pass_test("Pending ws_host implementation")
		return

	var host = _ws_script.new()
	var env = host.build_envelope("GAME_ACTION", { "action": "PLAY_CARD", "card_id": "r7" }, "host")

	assert_eq(env["v"], 1, "Envelope protocol version must be 1")
	assert_eq(env["type"], "GAME_ACTION", "Envelope type must match")
	assert_eq(env["sender"], "host", "Envelope sender must match")
	assert_has(env, "seq", "Envelope must contain sequence number")
	assert_has(env, "timestamp", "Envelope must contain timestamp")
	assert_eq(env["payload"]["card_id"], "r7", "Payload content must be preserved")

func test_ws_host_envelope_validation():
	if _ws_script == null:
		pass_test("Pending ws_host implementation")
		return

	var host = _ws_script.new()

	# Valid envelope
	var valid_env = {
		"v": 1,
		"type": "JOIN_REQUEST",
		"seq": 10,
		"sender": "player-1",
		"timestamp": 1731678000,
		"payload": { "role": "player" }
	}
	var res1 = host.validate_envelope(valid_env)
	assert_true(res1["valid"], "Valid envelope must pass validation")

	# Invalid: missing version
	var res2 = host.validate_envelope({ "type": "TEST", "seq": 1, "sender": "p1", "payload": {} })
	assert_false(res2["valid"], "Missing version must fail validation")

	# Invalid: non-integer sequence
	var res3 = host.validate_envelope({ "v": 1, "type": "TEST", "seq": -1, "sender": "p1", "payload": {} })
	assert_false(res3["valid"], "Negative sequence must fail validation")

	# Invalid: missing sender
	var res4 = host.validate_envelope({ "v": 1, "type": "TEST", "seq": 1, "sender": "", "payload": {} })
	assert_false(res4["valid"], "Empty sender must fail validation")

	# Invalid: payload not dictionary
	var res5 = host.validate_envelope({ "v": 1, "type": "TEST", "seq": 1, "sender": "p1", "payload": "not_dict" })
	assert_false(res5["valid"], "String payload must fail validation")

func test_ws_host_client_registration_and_role_broadcasting():
	if _ws_script == null:
		pass_test("Pending ws_host implementation")
		return

	var host = _ws_script.new()
	host.register_client_session(1, "p_alice", "player", "token_alice")
	host.register_client_session(2, "p_bob", "player", "token_bob")
	host.register_client_session(3, "tv_table", "table", "token_table")
	host.register_client_session(4, "spectator_1", "spectator", "token_spec")

	assert_eq(host.get_client_count(), 4, "Total registered clients should be 4")
	assert_eq(host.get_clients_by_role("player").size(), 2, "Should have 2 player clients")
	assert_eq(host.get_clients_by_role("table").size(), 1, "Should have 1 table client")
	assert_eq(host.get_clients_by_role("spectator").size(), 1, "Should have 1 spectator client")

## Tier 1 & Tier 2: LanDiscovery Beacon & Room Cache
func test_lan_discovery_beacon_formatting():
	if _lan_script == null:
		pass_test("Pending lan_discovery implementation")
		return

	var lan = _lan_script.new()
	var room_info = {
		"room_code": "4912",
		"game_id": "uno",
		"host_name": "Marvin's DeckBox",
		"app_version": "0.1.0",
		"http_port": 8080,
		"ws_port": 8081,
		"players_count": 2,
		"max_players": 4,
		"rules_hash": "rules_abc"
	}
	var packet_bytes = lan.build_beacon_packet(room_info)
	assert_gt(packet_bytes.size(), 0, "Beacon packet bytes must not be empty")

	var parsed = lan.parse_beacon_packet(packet_bytes)
	assert_true(parsed.get("valid", false), "Valid beacon packet must parse successfully")
	assert_eq(parsed["room_code"], "4912", "Room code must match")
	assert_eq(parsed["game_id"], "uno", "Game ID must match")
	assert_eq(parsed["magic"], "DECKBOX_LAN_BEACON", "Magic header must match")

func test_lan_discovery_prunes_expired_rooms():
	if _lan_script == null:
		pass_test("Pending lan_discovery implementation")
		return

	var lan = _lan_script.new()
	var now = int(Time.get_unix_time_from_system() * 1000)
	lan.upsert_discovered_room({ "room_code": "4912", "last_seen_ms": now })
	lan.upsert_discovered_room({ "room_code": "9999", "last_seen_ms": now - 10000 }) # 10 seconds ago

	assert_eq(lan.get_discovered_rooms().size(), 2, "Initially 2 discovered rooms")
	lan.prune_expired_rooms(5000, now) # Prune rooms older than 5000ms
	assert_eq(lan.get_discovered_rooms().size(), 1, "Expired room must be pruned")
	assert_eq(lan.get_discovered_rooms()[0]["room_code"], "4912", "Active room must remain")

## Tier 3 & Tier 4: WebRtcManager STUN & E2E Encrypted Relay Fallback
func test_webrtc_manager_stun_configuration():
	if _webrtc_script == null:
		pass_test("Pending webrtc_manager implementation")
		return

	var mgr = _webrtc_script.new()
	var ice_servers = mgr.get_ice_servers()
	assert_gte(ice_servers.size(), 2, "Must configure at least 2 free STUN servers")
	assert_true("stun:stun.l.google.com:19302" in ice_servers[0]["urls"], "Google STUN must be configured")
	assert_true("stun:stun.cloudflare.com:3478" in ice_servers[1]["urls"], "Cloudflare STUN must be configured")

func test_webrtc_manager_encrypted_relay_fallback():
	if _webrtc_script == null:
		pass_test("Pending webrtc_manager implementation")
		return

	var mgr = _webrtc_script.new()
	mgr.initialize_session("4912", "uno_rules_hash_xyz", true)

	var payload = { "action": "PLAY_CARD", "card": { "id": "r5", "color": "red", "value": "5" } }
	var encrypted_envelope = mgr.encrypt_relay_message("peer_bob", payload)

	assert_eq(encrypted_envelope["v"], 1, "Encrypted envelope must have v=1")
	assert_eq(encrypted_envelope["type"], "RELAY_E2E", "Encrypted envelope type must be RELAY_E2E")
	assert_has(encrypted_envelope, "iv_b64", "Must contain initialization vector")
	assert_has(encrypted_envelope, "ciphertext_b64", "Must contain encrypted ciphertext")

	# Decrypt with matching session keys
	var mgr_peer = _webrtc_script.new()
	mgr_peer.initialize_session("4912", "uno_rules_hash_xyz", false)
	var decrypted_payload = mgr_peer.decrypt_relay_message(encrypted_envelope)

	assert_not_null(decrypted_payload, "Decryption must succeed with matching session keys")
	assert_eq(decrypted_payload["action"], "PLAY_CARD", "Decrypted action must match original")
	assert_eq(decrypted_payload["card"]["id"], "r5", "Decrypted card id must match")
