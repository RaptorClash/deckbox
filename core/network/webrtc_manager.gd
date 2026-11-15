# webrtc_manager.gd
# Free WebRTC STUN P2P manager with transparent E2E encrypted relay fallback
class_name WebRtcManager
extends RefCounted

signal signaling_message_ready(target_peer_id: String, message: Dictionary)
signal peer_connected(peer_id: String, is_relay: bool)
signal peer_disconnected(peer_id: String)
signal packet_received(peer_id: String, envelope: Dictionary)

const ICE_SERVERS: Array = [
	{ "urls": ["stun:stun.l.google.com:19302"] },
	{ "urls": ["stun:stun.cloudflare.com:3478"] }
]

var _room_code: String = ""
var _rules_hash: String = ""
var _is_host: bool = false
var _peer_id: String = "local_peer"
var _session_key: PackedByteArray = PackedByteArray()
var _crypto: Crypto = Crypto.new()

# peer_id -> Dictionary { "pc": WebRTCPeerConnection, "dc": WebRTCDataChannel, "is_initiator": bool, "connected": bool, "created_at": int }
var _peers: Dictionary = {}

func get_ice_servers() -> Array:
	return ICE_SERVERS.duplicate(true)

func initialize_session(room_code: String, rules_hash: String, is_host: bool, peer_id: String = "local_peer") -> void:
	_room_code = room_code
	_rules_hash = rules_hash
	_is_host = is_host
	_peer_id = peer_id

	# Derive symmetric session key from room code and rules hash
	var key_material = (room_code + ":" + rules_hash).to_utf8_buffer()
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(key_material)
	_session_key = ctx.finish()

func encrypt_relay_message(target_peer: String, payload: Dictionary) -> Dictionary:
	var iv = _crypto.generate_random_bytes(16)
	var plaintext = JSON.stringify(payload).to_utf8_buffer()
	var ciphertext = _xor_keystream(plaintext, _session_key, iv)

	return {
		"v": 1,
		"type": "RELAY_E2E",
		"sender": _peer_id,
		"target": target_peer,
		"timestamp": int(Time.get_unix_time_from_system()),
		"iv_b64": Marshalls.raw_to_base64(iv),
		"ciphertext_b64": Marshalls.raw_to_base64(ciphertext)
	}

func decrypt_relay_message(envelope: Dictionary) -> Variant:
	if envelope.get("v") != 1 or envelope.get("type") != "RELAY_E2E":
		return null

	var iv_b64 = str(envelope.get("iv_b64", ""))
	var cipher_b64 = str(envelope.get("ciphertext_b64", ""))
	if iv_b64.is_empty() or cipher_b64.is_empty():
		return null

	var iv = Marshalls.base64_to_raw(iv_b64)
	var ciphertext = Marshalls.base64_to_raw(cipher_b64)
	var plaintext = _xor_keystream(ciphertext, _session_key, iv)

	var json_str = plaintext.get_string_from_utf8()
	var json = JSON.new()
	if json.parse(json_str) == OK:
		return json.data
	return null

func add_peer(peer_id: String, is_initiator: bool) -> void:
	if _peers.has(peer_id):
		remove_peer(peer_id)

	var pc = WebRTCPeerConnection.new()
	var config = { "iceServers": ICE_SERVERS }
	var err = pc.initialize(config)
	if err != OK:
		return

	var peer_record = {
		"pc": pc,
		"dc": null,
		"is_initiator": is_initiator,
		"connected": false,
		"created_at": Time.get_ticks_msec()
	}

	pc.session_description_created.connect(func(type, sdp):
		pc.set_local_description(type, sdp)
		signaling_message_ready.emit(peer_id, { "type": type, "sdp": sdp })
	)

	pc.ice_candidate_created.connect(func(media, index, name):
		signaling_message_ready.emit(peer_id, {
			"type": "candidate",
			"media": media,
			"index": index,
			"name": name
		})
	)

	pc.data_channel_received.connect(func(channel):
		peer_record["dc"] = channel
	)

	if is_initiator:
		var dc = pc.create_data_channel("deckbox_game")
		peer_record["dc"] = dc
		pc.create_offer()

	_peers[peer_id] = peer_record

func remove_peer(peer_id: String) -> void:
	if not _peers.has(peer_id):
		return
	var record = _peers[peer_id]
	if record["pc"] is WebRTCPeerConnection:
		record["pc"].close()
	_peers.erase(peer_id)
	peer_disconnected.emit(peer_id)

func handle_signaling_message(sender_id: String, message: Dictionary) -> void:
	if not _peers.has(sender_id):
		add_peer(sender_id, false)

	var pc: WebRTCPeerConnection = _peers[sender_id]["pc"]
	var type = message.get("type", "")

	match type:
		"offer":
			pc.set_remote_description("offer", message.get("sdp", ""))
		"answer":
			pc.set_remote_description("answer", message.get("sdp", ""))
		"candidate":
			pc.add_ice_candidate(message.get("media", ""), int(message.get("index", 0)), message.get("name", ""))

func send_packet(peer_id: String, envelope: Dictionary) -> Error:
	if not _peers.has(peer_id):
		return ERR_DOES_NOT_EXIST
	var record = _peers[peer_id]
	var dc: WebRTCDataChannel = record.get("dc")
	if dc != null and dc.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
		var json_str = JSON.stringify(envelope)
		return dc.put_packet(json_str.to_utf8_buffer())

	# Transparent fallback: emit relay message
	var relay_msg = encrypt_relay_message(peer_id, envelope)
	signaling_message_ready.emit(peer_id, relay_msg)
	return OK

func broadcast_packet(envelope: Dictionary, exclude_peer: String = "") -> void:
	for peer_id in _peers.keys():
		if peer_id == exclude_peer:
			continue
		send_packet(peer_id, envelope)

func poll() -> void:
	for peer_id in _peers.keys():
		var record = _peers[peer_id]
		var pc: WebRTCPeerConnection = record["pc"]
		pc.poll()

		var dc: WebRTCDataChannel = record.get("dc")
		if dc != null:
			dc.poll()
			if dc.get_ready_state() == WebRTCDataChannel.STATE_OPEN and not record["connected"]:
				record["connected"] = true
				peer_connected.emit(peer_id, false)

			while dc.get_available_packet_count() > 0:
				var pkt = dc.get_packet()
				var json = JSON.new()
				if json.parse(pkt.get_string_from_utf8()) == OK and (json.data is Dictionary):
					packet_received.emit(peer_id, json.data)

func _xor_keystream(data: PackedByteArray, key: PackedByteArray, iv: PackedByteArray) -> PackedByteArray:
	var result = PackedByteArray()
	result.resize(data.size())
	var block_idx: int = 0
	var out_idx: int = 0

	while out_idx < data.size():
		var ctx = HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(key)
		ctx.update(iv)
		ctx.update(var_to_bytes(block_idx))
		var stream_block = ctx.finish()
		block_idx += 1

		for i in range(stream_block.size()):
			if out_idx >= data.size():
				break
			result[out_idx] = data[out_idx] ^ stream_block[i]
			out_idx += 1

	return result
