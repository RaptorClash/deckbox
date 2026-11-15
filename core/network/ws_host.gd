# ws_host.gd
# Embedded WebSocket host using Godot 4 WebSocketPeer with role-based routing and JSON framing
class_name WsHost
extends RefCounted

signal client_connected(peer_id: int)
signal client_disconnected(peer_id: int, player_id: String, code: int, reason: String)
signal packet_received(peer_id: int, envelope: Dictionary)

const DEFAULT_PORT: int = 8081

var _tcp_server: TCPServer = TCPServer.new()
var _is_running: bool = false
var _port: int = 0
var _bind_address: String = "*"
var _peer_counter: int = 1
var _seq_counter: int = 1

# peer_id -> Dictionary { "peer_id": int, "ws": WebSocketPeer, "stream": StreamPeerTCP, "player_id": String, "role": String, "reconnect_token": String }
var _sessions: Dictionary = {}

func start(port: int = DEFAULT_PORT, bind_address: String = "*") -> Error:
	if _is_running:
		stop()

	_bind_address = bind_address
	var err = _tcp_server.listen(port, bind_address)
	if err != OK:
		return err

	_port = _tcp_server.get_local_port()
	_is_running = true
	return OK

func stop() -> void:
	if not _is_running:
		return
	for peer_id in _sessions.keys():
		disconnect_peer(peer_id, 1001, "Server shutdown")
	_sessions.clear()
	_tcp_server.stop()
	_is_running = false

func is_running() -> bool:
	return _is_running

func get_port() -> int:
	return _port

func get_client_count() -> int:
	return _sessions.size()

func get_clients_by_role(role: String) -> Array[int]:
	var result: Array[int] = []
	for peer_id in _sessions.keys():
		if _sessions[peer_id].get("role", "") == role:
			result.append(peer_id)
	return result

func register_client_session(peer_id: int, player_id: String, role: String, reconnect_token: String) -> void:
	if _sessions.has(peer_id):
		_sessions[peer_id]["player_id"] = player_id
		_sessions[peer_id]["role"] = role
		_sessions[peer_id]["reconnect_token"] = reconnect_token
	else:
		_sessions[peer_id] = {
			"peer_id": peer_id,
			"ws": null,
			"stream": null,
			"player_id": player_id,
			"role": role,
			"reconnect_token": reconnect_token
		}

func build_envelope(type: String, payload: Dictionary, sender: String = "host") -> Dictionary:
	var seq = _seq_counter
	_seq_counter += 1
	return {
		"v": 1,
		"type": type,
		"seq": seq,
		"sender": sender,
		"timestamp": int(Time.get_unix_time_from_system()),
		"payload": payload
	}

func validate_envelope(dict: Variant) -> Dictionary:
	if not (dict is Dictionary):
		return { "valid": false, "error": "Not a dictionary" }

	if dict.get("v") != 1:
		return { "valid": false, "error": "Invalid or missing version 'v' (expected 1)" }

	var type = str(dict.get("type", "")).strip_edges()
	if type.is_empty():
		return { "valid": false, "error": "Missing or empty 'type'" }

	var seq = dict.get("seq")
	if not (seq is int or (seq is float and seq == floor(seq))) or seq < 0:
		return { "valid": false, "error": "Sequence 'seq' must be a non-negative integer" }

	var sender = str(dict.get("sender", "")).strip_edges()
	if sender.is_empty():
		return { "valid": false, "error": "Missing or empty 'sender'" }

	var payload = dict.get("payload")
	if not (payload is Dictionary):
		return { "valid": false, "error": "'payload' must be a Dictionary" }

	return { "valid": true }

func send_to(peer_id: int, envelope: Dictionary) -> Error:
	if not _sessions.has(peer_id):
		return ERR_DOES_NOT_EXIST
	var ws: WebSocketPeer = _sessions[peer_id].get("ws")
	if ws == null:
		return ERR_UNAVAILABLE
	if ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return ERR_CONNECTION_ERROR

	var json_str = JSON.stringify(envelope)
	return ws.send_text(json_str)

func broadcast(envelope: Dictionary, exclude_peer_id: int = -1) -> void:
	var json_str = JSON.stringify(envelope)
	for peer_id in _sessions.keys():
		if peer_id == exclude_peer_id:
			continue
		var ws: WebSocketPeer = _sessions[peer_id].get("ws")
		if ws != null and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			ws.send_text(json_str)

func broadcast_to_role(role: String, envelope: Dictionary, exclude_peer_id: int = -1) -> void:
	var json_str = JSON.stringify(envelope)
	for peer_id in _sessions.keys():
		if peer_id == exclude_peer_id:
			continue
		if _sessions[peer_id].get("role", "") != role:
			continue
		var ws: WebSocketPeer = _sessions[peer_id].get("ws")
		if ws != null and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			ws.send_text(json_str)

func disconnect_peer(peer_id: int, code: int = 1000, reason: String = "") -> void:
	if not _sessions.has(peer_id):
		return
	var sess = _sessions[peer_id]
	var ws: WebSocketPeer = sess.get("ws")
	if ws != null:
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN or ws.get_ready_state() == WebSocketPeer.STATE_CONNECTING:
			ws.close(code, reason)
	var stream: StreamPeerTCP = sess.get("stream")
	if stream != null:
		stream.disconnect_from_host()
	var player_id = sess.get("player_id", "")
	_sessions.erase(peer_id)
	client_disconnected.emit(peer_id, player_id, code, reason)

func poll() -> void:
	if not _is_running:
		return

	# Accept new TCP connections and initiate WebSocket handshake
	while _tcp_server.is_connection_available():
		var tcp_conn: StreamPeerTCP = _tcp_server.take_connection()
		if tcp_conn != null:
			tcp_conn.set_no_delay(true)
			var ws = WebSocketPeer.new()
			ws.set_heartbeat_interval(10.0)
			var err = ws.accept_stream(tcp_conn)
			if err == OK:
				var peer_id = _peer_counter
				_peer_counter += 1
				_sessions[peer_id] = {
					"peer_id": peer_id,
					"ws": ws,
					"stream": tcp_conn,
					"player_id": "",
					"role": "spectator",
					"reconnect_token": ""
				}
				client_connected.emit(peer_id)
			else:
				tcp_conn.disconnect_from_host()

	# Poll active sessions
	var dead_peers: Array[int] = []
	for peer_id in _sessions.keys():
		var sess = _sessions[peer_id]
		var ws: WebSocketPeer = sess.get("ws")
		if ws == null:
			continue

		ws.poll()
		var state = ws.get_ready_state()
		match state:
			WebSocketPeer.STATE_OPEN:
				while ws.get_available_packet_count() > 0:
					var packet_bytes = ws.get_packet()
					var packet_str = packet_bytes.get_string_from_utf8()
					var json = JSON.new()
					if json.parse(packet_str) == OK and (json.data is Dictionary):
						var validation = validate_envelope(json.data)
						if validation.get("valid", false):
							packet_received.emit(peer_id, json.data)
			WebSocketPeer.STATE_CLOSED:
				var code = ws.get_close_code()
				var reason = ws.get_close_reason()
				dead_peers.append(peer_id)
				client_disconnected.emit(peer_id, sess.get("player_id", ""), code, reason)

	for p in dead_peers:
		_sessions.erase(p)
