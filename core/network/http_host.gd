# http_host.gd
# Embedded non-blocking HTTP server for web_lite assets with MIME and traversal security
class_name HttpHost
extends RefCounted

signal server_started(port: int)
signal server_stopped()
signal request_served(method: String, path: String, status_code: int)

const DEFAULT_PORT: int = 8080
const MAX_HEADER_SIZE: int = 8192

var _tcp_server: TCPServer = TCPServer.new()
var _is_running: bool = false
var _port: int = 0
var _bind_address: String = "*"
var _web_root: String = "res://web_lite"
var _preferred_ip: String = ""
var _room_metadata: Dictionary = {}

# Active client streams: Array of Dictionary { "peer": StreamPeerTCP, "buffer": PackedByteArray, "created_at": int, "closing": bool, "close_at": int }
var _clients: Array[Dictionary] = []

func start(port: int = DEFAULT_PORT, bind_address: String = "*", web_root: String = "res://web_lite") -> Error:
	if _is_running:
		stop()

	_bind_address = bind_address
	_web_root = web_root

	var err = _tcp_server.listen(port, bind_address)
	if err != OK:
		return err

	_port = _tcp_server.get_local_port()
	_is_running = true
	server_started.emit(_port)
	return OK

func stop() -> void:
	if not _is_running:
		return
	for c in _clients:
		if c.peer is StreamPeerTCP:
			c.peer.disconnect_from_host()
	_clients.clear()
	_tcp_server.stop()
	_is_running = false
	server_stopped.emit()

func is_running() -> bool:
	return _is_running

func get_port() -> int:
	return _port

func set_preferred_ip(ip: String) -> void:
	_preferred_ip = ip.strip_edges()

func set_room_metadata(meta: Dictionary) -> void:
	_room_metadata = meta.duplicate(true)

static func _ipv4_priority_tier(ip: String) -> int:
	if ip.begins_with("192.168.56."):
		return 3 # VirtualBox Host-Only adapter
	if ip.begins_with("192.168."):
		return 0 # Home Wi-Fi / Router LAN subnet
	if ip.begins_with("10."):
		return 1 # Private Class A LAN / VPN
	if ip.begins_with("172."):
		var parts = ip.split(".")
		if parts.size() >= 2:
			var second = int(parts[1])
			if second >= 16 and second <= 31:
				return 3 # WSL / Docker / Hyper-V bridge
	return 2

static func rank_ipv4_addresses(ips: Array) -> Array[String]:
	var buckets: Dictionary = { 0: [], 1: [], 2: [], 3: [] }
	var seen: Dictionary = {}
	for raw_ip in ips:
		var ip = str(raw_ip).strip_edges()
		if ip.is_empty() or ":" in ip or not ("." in ip):
			continue
		if ip.begins_with("127.") or ip.begins_with("169.254.") or ip == "0.0.0.0":
			continue
		if seen.has(ip):
			continue
		seen[ip] = true
		var tier = _ipv4_priority_tier(ip)
		buckets[tier].append(ip)

	var ranked: Array[String] = []
	for tier in [0, 1, 2, 3]:
		for ip in buckets[tier]:
			ranked.append(ip)
	return ranked

func get_lan_ips() -> Array[String]:
	return rank_ipv4_addresses(IP.get_local_addresses())

func get_lan_ip() -> String:
	if not _preferred_ip.is_empty():
		return _preferred_ip
	var ranked = get_lan_ips()
	if not ranked.is_empty():
		return ranked[0]
	return "127.0.0.1"

func get_serve_url(room_code: String = "", role: String = "player", short_mode: bool = false) -> String:
	var ip = get_lan_ip()
	if short_mode:
		return "http://%s:%d" % [ip, _port]
	if room_code.is_empty():
		return "http://%s:%d/" % [ip, _port]
	return "http://%s:%d/?room=%s&role=%s" % [ip, _port, room_code, role]

func is_path_safe(rel_path: String) -> bool:
	if rel_path.is_empty():
		return false

	# Check for null byte injection
	if "\u0000" in rel_path or "%00" in rel_path:
		return false

	# Check for backslash or URL-encoded dots/slashes
	var lowered = rel_path.to_lower()
	if "\\" in lowered or "%2e" in lowered or "%2f" in lowered or "%5c" in lowered:
		return false

	# Segment check for directory traversal
	var clean = rel_path.split("?")[0].split("#")[0].strip_edges()
	var parts = clean.split("/")
	for p in parts:
		if p == ".." or p == ".":
			return false

	# Ensure simplified path doesn't start with / or ..
	var sim = clean.simplify_path()
	if sim.begins_with("..") or sim.begins_with("/"):
		return false

	return true

func get_mime_type(file_path: String) -> String:
	var ext = file_path.get_extension().to_lower()
	match ext:
		"html", "htm":
			return "text/html; charset=UTF-8"
		"css":
			return "text/css; charset=UTF-8"
		"js", "mjs":
			return "application/javascript; charset=UTF-8"
		"json":
			return "application/json; charset=UTF-8"
		"svg":
			return "image/svg+xml"
		"png":
			return "image/png"
		"jpg", "jpeg":
			return "image/jpeg"
		"ico":
			return "image/x-icon"
		"wasm":
			return "application/wasm"
		"webp":
			return "image/webp"
		_:
			return "application/octet-stream"

func poll() -> void:
	if not _is_running:
		return

	# Accept pending connections
	while _tcp_server.is_connection_available():
		var peer: StreamPeerTCP = _tcp_server.take_connection()
		if peer != null:
			peer.set_no_delay(true)
			_clients.append({
				"peer": peer,
				"buffer": PackedByteArray(),
				"created_at": Time.get_ticks_msec(),
				"closing": false,
				"close_at": 0
			})

	# Process active clients
	var now = Time.get_ticks_msec()
	var remaining: Array[Dictionary] = []

	for client in _clients:
		var peer: StreamPeerTCP = client["peer"]
		peer.poll()

		var status = peer.get_status()
		if status != StreamPeerTCP.STATUS_CONNECTED:
			peer.disconnect_from_host()
			continue

		if bool(client.get("closing", false)):
			if now >= int(client.get("close_at", 0)):
				peer.disconnect_from_host()
				continue
			remaining.append(client)
			continue

		# Timeout client after 10s of inactivity
		if now - client["created_at"] > 10000:
			peer.disconnect_from_host()
			continue

		var avail = peer.get_available_bytes()
		if avail > 0:
			var res = peer.get_partial_data(avail)
			if res[0] == OK:
				var chunk: PackedByteArray = res[1]
				var buf: PackedByteArray = client["buffer"]
				buf.append_array(chunk)
				client["buffer"] = buf

				# Look for end of HTTP headers \r\n\r\n
				var req_str = buf.get_string_from_utf8()
				var header_end = req_str.find("\r\n\r\n")
				if header_end != -1:
					_handle_request(peer, req_str.substr(0, header_end))
					client["closing"] = true
					client["close_at"] = now + 150
					client["buffer"] = PackedByteArray()
					remaining.append(client)
					continue
				elif buf.size() > MAX_HEADER_SIZE:
					_send_response(peer, 400, "Bad Request", "Request header too large".to_utf8_buffer(), "text/plain")
					client["closing"] = true
					client["close_at"] = now + 80
					remaining.append(client)
					continue

		remaining.append(client)

	_clients = remaining

func _handle_request(peer: StreamPeerTCP, header_text: String) -> void:
	var lines = header_text.split("\r\n")
	if lines.size() == 0:
		_send_response(peer, 400, "Bad Request", "Empty request".to_utf8_buffer(), "text/plain")
		return

	var req_line = lines[0].split(" ")
	if req_line.size() < 2:
		_send_response(peer, 400, "Bad Request", "Malformed request line".to_utf8_buffer(), "text/plain")
		return

	var method = req_line[0].to_upper()
	var raw_uri = req_line[1]

	if method != "GET" and method != "HEAD":
		_send_response(peer, 405, "Method Not Allowed", "Allow: GET, HEAD".to_utf8_buffer(), "text/plain")
		request_served.emit(method, raw_uri, 405)
		return

	# Parse URI: strip query and hash
	var uri_path = raw_uri.split("?")[0].split("#")[0].strip_edges()
	if uri_path == "/api/room":
		var meta = {
			"room_code": str(_room_metadata.get("room_code", "")),
			"ws_port": int(_room_metadata.get("ws_port", 8081)),
			"role": str(_room_metadata.get("role", "player")),
			"game_name": str(_room_metadata.get("game_name", "Alle Ablegen!"))
		}
		var json_bytes = JSON.stringify(meta).to_utf8_buffer()
		if method == "HEAD":
			_send_headers(peer, 200, "OK", json_bytes.size(), "application/json; charset=UTF-8")
		else:
			_send_response(peer, 200, "OK", json_bytes, "application/json; charset=UTF-8")
		request_served.emit(method, uri_path, 200)
		return

	if uri_path == "/" or uri_path.is_empty():
		uri_path = "/index.html"

	var rel_path = uri_path.substr(1) if uri_path.begins_with("/") else uri_path

	if not is_path_safe(rel_path):
		_send_response(peer, 403, "Forbidden", "Access denied".to_utf8_buffer(), "text/plain")
		request_served.emit(method, uri_path, 403)
		return

	var disk_path = _web_root.path_join(rel_path)
	if not FileAccess.file_exists(disk_path):
		_send_response(peer, 404, "Not Found", "File not found".to_utf8_buffer(), "text/plain")
		request_served.emit(method, uri_path, 404)
		return

	var file_bytes = FileAccess.get_file_as_bytes(disk_path)
	var mime = get_mime_type(disk_path)

	if method == "HEAD":
		_send_headers(peer, 200, "OK", file_bytes.size(), mime)
	else:
		_send_response(peer, 200, "OK", file_bytes, mime)

	request_served.emit(method, uri_path, 200)

func _send_headers(peer: StreamPeerTCP, status_code: int, reason: String, content_length: int, content_type: String) -> void:
	var response = "HTTP/1.1 %d %s\r\n" % [status_code, reason]
	response += "Content-Type: %s\r\n" % content_type
	response += "Content-Length: %d\r\n" % content_length
	response += "Access-Control-Allow-Origin: *\r\n"
	response += "Connection: close\r\n\r\n"
	peer.put_data(response.to_utf8_buffer())

func _send_response(peer: StreamPeerTCP, status_code: int, reason: String, body: PackedByteArray, content_type: String) -> void:
	_send_headers(peer, status_code, reason, body.size(), content_type)
	if body.size() > 0:
		peer.put_data(body)
