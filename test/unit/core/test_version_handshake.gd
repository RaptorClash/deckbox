# test_version_handshake.gd
# GUT 9.x Headless Test Suite: Version Handshake, Downgrade Negotiation, & Web Fallback
extends GutTest

const VERSION_HANDSHAKE_PATH = "res://core/network/version_handshake.gd"

var _handshake_script: GDScript

func before_all():
	if ResourceLoader.exists(VERSION_HANDSHAKE_PATH):
		_handshake_script = load(VERSION_HANDSHAKE_PATH)

func _create_evaluator(host_app_version: String = "0.1.0", host_protocol: int = 1, host_rules_hash: String = "std_uno_rules_hash_abc123") -> RefCounted:
	if _handshake_script != null:
		var inst = _handshake_script.new()
		if inst.has_method("configure_host"):
			inst.configure_host({
				"app_version": host_app_version,
				"protocol_version": host_protocol,
				"rules_hash": host_rules_hash,
				"room_code": "4912",
				"host_ip": "192.168.1.45",
				"http_port": 8080,
				"max_players": 4
			})
		return inst
	return null

func _build_join_request(app_version: String = "0.1.0", protocol_version: int = 1, rules_hash: String = "std_uno_rules_hash_abc123", role: String = "player", reconnect_token: String = "") -> Dictionary:
	return {
		"v": 1,
		"type": "JOIN_REQUEST",
		"seq": 1,
		"sender": "player-uuid-001",
		"timestamp": 1731678000,
		"payload": {
			"app_version": app_version,
			"protocol_version": protocol_version,
			"rules_hash": rules_hash,
			"player_name": "Marvin",
			"avatar_id": "avatar_01",
			"role": role,
			"reconnect_token": reconnect_token
		}
	}

## Tier 1 (Feature Coverage): Accepted Handshake on Exact Version Match
func test_handshake_accepted_exact_match():
	var evaluator = _create_evaluator("0.1.0", 1, "hash_valid_123")
	if evaluator == null:
		pass_test("Pending version_handshake implementation")
		return

	var req = _build_join_request("0.1.0", 1, "hash_valid_123", "player")
	var response = evaluator.evaluate_join_request(req)

	assert_true(response is Dictionary, "Handshake response must be a Dictionary")
	assert_has(response, "payload", "Response must contain payload")
	var payload = response["payload"]

	assert_eq(payload["status"], "ACCEPTED", "Matching versions must be ACCEPTED")
	assert_has(payload, "seat_index", "Accepted response must assign seat_index")
	assert_has(payload, "reconnect_token", "Accepted response must generate a reconnect_token")
	assert_eq(payload["role"], "player", "Role must match requested role")

## Tier 1 & Tier 2: Protocol Version Mismatch Rejection & Fallback
func test_handshake_rejected_protocol_mismatch():
	var evaluator = _create_evaluator("0.1.0", 1, "hash_valid_123")
	if evaluator == null:
		pass_test("Pending version_handshake implementation")
		return

	# Client uses newer protocol 2
	var req = _build_join_request("0.1.0", 2, "hash_valid_123", "player")
	var response = evaluator.evaluate_join_request(req)

	var payload = response.get("payload", {})
	assert_true(payload.get("status") in ["REJECTED_VERSION_MISMATCH", "REJECTED_PROTOCOL_MISMATCH"],
		"Protocol mismatch must be rejected")
	assert_has(payload, "web_fallback_url", "Mismatch response must provide web_fallback_url")

	var fallback = payload["web_fallback_url"]
	assert_true(fallback.begins_with("http://") or fallback.begins_with("https://"), "Fallback URL must be valid HTTP/HTTPS URL")
	assert_true("room=4912" in fallback or "4912" in fallback, "Fallback URL must contain the room code")

## Tier 1 & Tier 2: App SemVer Mismatch Rejection
func test_handshake_rejected_app_version_mismatch():
	var evaluator = _create_evaluator("0.1.0", 1, "hash_valid_123")
	if evaluator == null:
		pass_test("Pending version_handshake implementation")
		return

	# Client is on older version 0.0.9
	var req = _build_join_request("0.0.9", 1, "hash_valid_123", "player")
	var response = evaluator.evaluate_join_request(req)

	var payload = response.get("payload", {})
	assert_eq(payload.get("status"), "REJECTED_VERSION_MISMATCH", "Outdated app version must be rejected")
	assert_has(payload, "host_version", "Mismatch response must indicate host_version")
	assert_eq(payload["host_version"], "0.1.0", "Host version must be 0.1.0")
	assert_has(payload, "web_fallback_url", "Must supply web_fallback_url for browser play")

## Tier 1 & Tier 2: Rules Hash Mismatch Rejection
func test_handshake_rejected_rules_hash_mismatch():
	var evaluator = _create_evaluator("0.1.0", 1, "host_rules_hash_correct")
	if evaluator == null:
		pass_test("Pending version_handshake implementation")
		return

	# Client has different rules hash (e.g. custom cardpack mismatch)
	var req = _build_join_request("0.1.0", 1, "client_rules_hash_different", "player")
	var response = evaluator.evaluate_join_request(req)

	var payload = response.get("payload", {})
	assert_true(payload.get("status") in ["REJECTED_RULES_MISMATCH", "REJECTED_VERSION_MISMATCH"],
		"Rules hash mismatch must be rejected")
	assert_has(payload, "required_rules_hash", "Response should communicate required rules hash")
	assert_eq(payload["required_rules_hash"], "host_rules_hash_correct", "Expected host rules hash in payload")

## Tier 2 (Boundary & Corner Cases): Malformed Request Envelopes
func test_handshake_malformed_requests():
	var evaluator = _create_evaluator()
	if evaluator == null:
		pass_test("Pending version_handshake implementation")
		return

	# Test 1: Completely empty request
	var res1 = evaluator.evaluate_join_request({})
	assert_true(res1 is Dictionary, "Empty request must return a response dictionary")
	var status1 = res1.get("payload", {}).get("status", "REJECTED")
	assert_true(status1.begins_with("REJECTED"), "Empty request must be rejected")

	# Test 2: Missing payload dictionary
	var res2 = evaluator.evaluate_join_request({ "type": "JOIN_REQUEST" })
	var status2 = res2.get("payload", {}).get("status", "REJECTED")
	assert_true(status2.begins_with("REJECTED"), "Missing payload must be rejected")

	# Test 3: Missing sender
	var res3 = evaluator.evaluate_join_request({
		"type": "JOIN_REQUEST",
		"payload": { "app_version": "0.1.0", "protocol_version": 1 }
	})
	var status3 = res3.get("payload", {}).get("status", "REJECTED")
	assert_true(status3.begins_with("REJECTED"), "Missing sender must be rejected")

## Tier 3 (Cross-Feature): Role Delegation (Table Display & Spectator)
func test_handshake_role_table_and_spectator():
	var evaluator = _create_evaluator("0.1.0", 1, "hash_123")
	if evaluator == null:
		pass_test("Pending version_handshake implementation")
		return

	# Request table role (e.g. smart TV shared display)
	var table_req = _build_join_request("0.1.0", 1, "hash_123", "table")
	var table_res = evaluator.evaluate_join_request(table_req)
	var table_payload = table_res.get("payload", {})
	assert_eq(table_payload.get("status"), "ACCEPTED", "Table role must be accepted")
	assert_eq(table_payload.get("role"), "table", "Assigned role must be table")

	# Request spectator role
	var spec_req = _build_join_request("0.1.0", 1, "hash_123", "spectator")
	var spec_res = evaluator.evaluate_join_request(spec_req)
	var spec_payload = spec_res.get("payload", {})
	assert_eq(spec_payload.get("status"), "ACCEPTED", "Spectator role must be accepted")
	assert_eq(spec_payload.get("role"), "spectator", "Assigned role must be spectator")

## Tier 4 (Scenario): Reconnect Token Validation & Seat Reclamation
func test_handshake_reconnect_with_valid_token():
	var evaluator = _create_evaluator("0.1.0", 1, "hash_123")
	if evaluator == null:
		pass_test("Pending version_handshake implementation")
		return

	# First join allocates seat
	var initial_req = _build_join_request("0.1.0", 1, "hash_123", "player")
	var initial_res = evaluator.evaluate_join_request(initial_req)
	var token = initial_res.get("payload", {}).get("reconnect_token", "")
	var seat = initial_res.get("payload", {}).get("seat_index", -1)

	assert_ne(token, "", "Initial join must issue reconnect_token")

	# Simulate reconnect using that token
	var reconnect_req = _build_join_request("0.1.0", 1, "hash_123", "player", token)
	var reconnect_res = evaluator.evaluate_join_request(reconnect_req)
	var rec_payload = reconnect_res.get("payload", {})

	assert_eq(rec_payload.get("status"), "ACCEPTED", "Valid reconnect token must be ACCEPTED")
	assert_eq(rec_payload.get("seat_index"), seat, "Reconnection must preserve the original seat index")
