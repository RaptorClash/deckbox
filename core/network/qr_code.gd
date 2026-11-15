# qr_code.gd
# Pure GDScript QR Code generator and module renderer (ISO/IEC 18004 compliant)
class_name QRCodeGenerator
extends RefCounted

enum EccLevel { L = 0, M = 1, Q = 2, H = 3 }

const FORMAT_MASK: int = 0x5412
const FORMAT_POLY: int = 0x537

static var _gf_exp: PackedInt32Array = PackedInt32Array()
static var _gf_log: PackedInt32Array = PackedInt32Array()
static var _gf_ready: bool = false

# Version definitions (1 to 6)
static var VERSION_INFO: Dictionary = {
	1: { EccLevel.L: { "data": 19, "ec": 7, "blocks": 1 }, EccLevel.M: { "data": 16, "ec": 10, "blocks": 1 } },
	2: { EccLevel.L: { "data": 34, "ec": 10, "blocks": 1 }, EccLevel.M: { "data": 28, "ec": 16, "blocks": 1 } },
	3: { EccLevel.L: { "data": 55, "ec": 15, "blocks": 1 }, EccLevel.M: { "data": 44, "ec": 26, "blocks": 1 } },
	4: { EccLevel.L: { "data": 80, "ec": 20, "blocks": 1 }, EccLevel.M: { "data": 64, "ec": 18, "blocks": 2 } },
	5: { EccLevel.L: { "data": 108, "ec": 26, "blocks": 1 }, EccLevel.M: { "data": 86, "ec": 24, "blocks": 2 } },
	6: { EccLevel.L: { "data": 136, "ec": 18, "blocks": 2 }, EccLevel.M: { "data": 108, "ec": 16, "blocks": 4 } }
}

static var ALIGN_POS: Dictionary = {
	1: [], 2: [6, 18], 3: [6, 22], 4: [6, 26], 5: [6, 30], 6: [6, 34]
}

static func _init_gf() -> void:
	if _gf_ready:
		return
	_gf_exp.resize(512)
	_gf_log.resize(256)
	var x: int = 1
	for i in range(255):
		_gf_exp[i] = x
		_gf_log[x] = i
		x <<= 1
		if (x & 0x100) != 0:
			x ^= 0x11D # primitive polynomial x^8 + x^4 + x^3 + x^2 + 1
	for i in range(255, 512):
		_gf_exp[i] = _gf_exp[i - 255]
	_gf_ready = true

static func _gf_mul(x: int, y: int) -> int:
	if x == 0 or y == 0:
		return 0
	return _gf_exp[_gf_log[x] + _gf_log[y]]

static func select_version(text_len: int, ecc: EccLevel = EccLevel.M) -> int:
	for v in range(1, 7):
		if VERSION_INFO.has(v) and VERSION_INFO[v].has(ecc):
			var max_bytes = VERSION_INFO[v][ecc]["data"] - 2
			if text_len <= max_bytes:
				return v
	return 6

static func _rs_encode(data: PackedByteArray, ec_len: int) -> PackedByteArray:
	_init_gf()
	# Compute generator polynomial g(x) = (x - alpha^0)(x - alpha^1)...
	var gen: PackedInt32Array = PackedInt32Array()
	gen.resize(ec_len + 1)
	gen.fill(0)
	gen[0] = 1
	for i in range(ec_len):
		var root = _gf_exp[i]
		for j in range(i + 1, 0, -1):
			gen[j] = gen[j] ^ _gf_mul(gen[j - 1], root)

	var res: PackedInt32Array = PackedInt32Array()
	res.resize(data.size() + ec_len)
	res.fill(0)
	for i in range(data.size()):
		res[i] = data[i]

	for i in range(data.size()):
		var coef = res[i]
		if coef != 0:
			for j in range(ec_len + 1):
				res[i + j] = res[i + j] ^ _gf_mul(gen[j], coef)

	var ec_bytes = PackedByteArray()
	for i in range(data.size(), data.size() + ec_len):
		ec_bytes.append(res[i])
	return ec_bytes

static func _encode_data(text: String, version: int, ecc: EccLevel) -> PackedByteArray:
	var total_data_bytes = VERSION_INFO[version][ecc]["data"]
	var text_bytes = text.to_utf8_buffer()

	# Byte mode indicator (0100) + character count indicator (8 bits for V1-6)
	var bit_buffer: Array[int] = []
	# Mode: 0100
	bit_buffer.append(0); bit_buffer.append(1); bit_buffer.append(0); bit_buffer.append(0)
	# Char count: 8 bits
	var count = text_bytes.size()
	for i in range(7, -1, -1):
		bit_buffer.append((count >> i) & 1)

	# Data bytes
	for b in text_bytes:
		for i in range(7, -1, -1):
			bit_buffer.append((b >> i) & 1)

	# Terminator: up to 4 zero bits
	var max_bits = total_data_bytes * 8
	var term_len = mini(4, max_bits - bit_buffer.size())
	for i in range(term_len):
		bit_buffer.append(0)

	# Pad to byte boundary
	while bit_buffer.size() % 8 != 0:
		bit_buffer.append(0)

	# Convert to byte array
	var codewords = PackedByteArray()
	for i in range(0, bit_buffer.size(), 8):
		var val: int = 0
		for b in range(8):
			val = (val << 1) | bit_buffer[i + b]
		codewords.append(val)

	# Pad with alternating 0xEC and 0x11
	var pad: Array[int] = [0xEC, 0x11]
	var pad_idx: int = 0
	while codewords.size() < total_data_bytes:
		codewords.append(pad[pad_idx])
		pad_idx = (pad_idx + 1) % 2

	return codewords

static func _place_finder(matrix: Array, is_func: Array, start_x: int, start_y: int, size: int) -> void:
	for dy in range(7):
		for dx in range(7):
			var px = start_x + dx
			var py = start_y + dy
			var is_black = (dx == 0 or dx == 6 or dy == 0 or dy == 6 or (dx >= 2 and dx <= 4 and dy >= 2 and dy <= 4))
			matrix[py][px] = 1 if is_black else 0
			is_func[py][px] = true

	# Separator border
	for dy in range(-1, 8):
		for dx in range(-1, 8):
			var px = start_x + dx
			var py = start_y + dy
			if px >= 0 and px < size and py >= 0 and py < size:
				if not is_func[py][px]:
					matrix[py][px] = 0
					is_func[py][px] = true

static func _place_alignment(matrix: Array, is_func: Array, cx: int, cy: int) -> void:
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var px = cx + dx
			var py = cy + dy
			var is_black = (abs(dx) == 2 or abs(dy) == 2 or (dx == 0 and dy == 0))
			matrix[py][px] = 1 if is_black else 0
			is_func[py][px] = true

static func _apply_mask(base_matrix: Array, is_func: Array, mask: int, size: int) -> Array:
	var copy: Array = []
	for y in range(size):
		var row: Array[int] = []
		row.resize(size)
		for x in range(size):
			var val = base_matrix[y][x]
			if not is_func[y][x]:
				var invert: bool = false
				match mask:
					0: invert = ((x + y) % 2 == 0)
					1: invert = (y % 2 == 0)
					2: invert = (x % 3 == 0)
					3: invert = ((x + y) % 3 == 0)
					4: invert = (((y / 2) + (x / 3)) % 2 == 0)
					5: invert = (((x * y) % 2) + ((x * y) % 3) == 0)
					6: invert = ((((x * y) % 2) + ((x * y) % 3)) % 2 == 0)
					7: invert = ((((x + y) % 2) + ((x * y) % 3)) % 2 == 0)
				if invert:
					val ^= 1
			row[x] = val
		copy.append(row)
	return copy

static func _write_format_info(matrix: Array, ecc: EccLevel, mask: int, size: int) -> void:
	# Format information: 5 bits data (2 bits ecc + 3 bits mask) + 10 bits BCH
	var ecc_bits: int = 1 # Level M = 00 in ISO, but 1 in our enum
	match ecc:
		EccLevel.L: ecc_bits = 1
		EccLevel.M: ecc_bits = 0
		EccLevel.Q: ecc_bits = 3
		EccLevel.H: ecc_bits = 2

	var data = ((ecc_bits << 3) | mask) << 10
	var rem = data
	for i in range(14, 9, -1):
		if (rem & (1 << i)) != 0:
			rem ^= (FORMAT_POLY << (i - 10))

	var format_val = (data | rem) ^ FORMAT_MASK

	var bits: Array[int] = []
	for i in range(14, -1, -1):
		bits.append((format_val >> i) & 1)

	# Format info around top-left finder
	var positions_tl = [
		[0, 8], [1, 8], [2, 8], [3, 8], [4, 8], [5, 8], [7, 8], [8, 8],
		[8, 7], [8, 5], [8, 4], [8, 3], [8, 2], [8, 1], [8, 0]
	]
	for i in range(15):
		var p = positions_tl[i]
		matrix[p[1]][p[0]] = bits[i]

	# Split format info around bottom-left and top-right finders
	for i in range(7):
		matrix[size - 1 - i][8] = bits[i]
	for i in range(8):
		matrix[8][size - 8 + i] = bits[7 + i]

static func _evaluate_penalty(matrix: Array, size: int) -> int:
	var penalty: int = 0
	# N1: Five or more consecutive same-color modules in row/col
	for y in range(size):
		var count: int = 1
		var last: int = matrix[y][0]
		for x in range(1, size):
			if matrix[y][x] == last:
				count += 1
				if count == 5:
					penalty += 3
				elif count > 5:
					penalty += 1
			else:
				last = matrix[y][x]
				count = 1

	for x in range(size):
		var count: int = 1
		var last: int = matrix[0][x]
		for y in range(1, size):
			if matrix[y][x] == last:
				count += 1
				if count == 5:
					penalty += 3
				elif count > 5:
					penalty += 1
			else:
				last = matrix[y][x]
				count = 1

	# N2: 2x2 blocks of same color
	for y in range(size - 1):
		for x in range(size - 1):
			var v = matrix[y][x]
			if matrix[y + 1][x] == v and matrix[y][x + 1] == v and matrix[y + 1][x + 1] == v:
				penalty += 3

	return penalty

static func generate_matrix(text: String, ecc: EccLevel = EccLevel.M, force_version: int = 0) -> Array:
	_init_gf()
	var version: int = force_version
	if version <= 0:
		version = select_version(text.length(), ecc)
	version = clampi(version, 1, 6)

	var info: Dictionary = VERSION_INFO[version][ecc]
	var size: int = 4 * version + 17

	var matrix: Array = []
	var is_func: Array = []
	for y in range(size):
		var row_m: Array[int] = []
		var row_f: Array[bool] = []
		row_m.resize(size)
		row_f.resize(size)
		row_m.fill(0)
		row_f.fill(false)
		matrix.append(row_m)
		is_func.append(row_f)

	# Finder & Separator patterns
	_place_finder(matrix, is_func, 0, 0, size)
	_place_finder(matrix, is_func, size - 7, 0, size)
	_place_finder(matrix, is_func, 0, size - 7, size)

	# Alignment pattern (Versions 2-6)
	var align_coords = ALIGN_POS.get(version, [])
	if align_coords.size() >= 2:
		_place_alignment(matrix, is_func, align_coords[1], align_coords[1])

	# Timing patterns
	for i in range(8, size - 8):
		var val = 1 if (i % 2 == 0) else 0
		if not is_func[6][i]:
			matrix[6][i] = val
			is_func[6][i] = true
		if not is_func[i][6]:
			matrix[i][6] = val
			is_func[i][6] = true

	# Dark module & format reservations
	matrix[size - 8][8] = 1
	is_func[size - 8][8] = true
	for i in range(9):
		is_func[8][i] = true
		is_func[i][8] = true
	for i in range(size - 8, size):
		is_func[8][i] = true
		is_func[i][8] = true

	# Data encoding & RS interleaving
	var data_codewords = _encode_data(text, version, ecc)
	var num_blocks: int = info["blocks"]
	var ec_len: int = info["ec"]
	var data_len_per_block: int = info["data"] / num_blocks

	var data_blocks: Array[PackedByteArray] = []
	var ec_blocks: Array[PackedByteArray] = []
	for b in range(num_blocks):
		var block_data = data_codewords.slice(b * data_len_per_block, (b + 1) * data_len_per_block)
		data_blocks.append(block_data)
		ec_blocks.append(_rs_encode(block_data, ec_len))

	var interleaved: PackedByteArray = PackedByteArray()
	for i in range(data_len_per_block):
		for b in range(num_blocks):
			interleaved.append(data_blocks[b][i])
	for i in range(ec_len):
		for b in range(num_blocks):
			interleaved.append(ec_blocks[b][i])

	var bits: Array[int] = []
	for b in interleaved:
		for i in range(7, -1, -1):
			bits.append((b >> i) & 1)

	# Data placement in zig-zag
	var bit_idx: int = 0
	var right: int = size - 1
	var upward: bool = true
	while right > 0:
		if right == 6:
			right -= 1 # Skip timing column
		var row_range = range(size - 1, -1, -1) if upward else range(0, size)
		for y in row_range:
			for x in [right, right - 1]:
				if not is_func[y][x]:
					var bit_val = bits[bit_idx] if bit_idx < bits.size() else 0
					matrix[y][x] = bit_val
					bit_idx += 1
		upward = not upward
		right -= 2

	# Evaluate 8 masks and pick the lowest penalty
	var best_matrix: Array = []
	var min_penalty: int = 999999999
	for mask in range(8):
		var test_m = _apply_mask(matrix, is_func, mask, size)
		_write_format_info(test_m, ecc, mask, size)
		var penalty = _evaluate_penalty(test_m, size)
		if penalty < min_penalty:
			min_penalty = penalty
			best_matrix = test_m

	return best_matrix

static func generate_image(text: String, module_pixel_size: int = 6, margin: int = 2, ecc: EccLevel = EccLevel.M) -> Image:
	var mat = generate_matrix(text, ecc)
	var count = mat.size()
	var total_dim = (count + 2 * margin) * module_pixel_size
	var img = Image.create(total_dim, total_dim, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)

	var black = Color.BLACK
	for y in range(count):
		for x in range(count):
			if mat[y][x] == 1:
				var px = (x + margin) * module_pixel_size
				var py = (y + margin) * module_pixel_size
				for dy in range(module_pixel_size):
					for dx in range(module_pixel_size):
						img.set_pixel(px + dx, py + dy, black)
	return img

static func generate_texture(text: String, module_pixel_size: int = 6, margin: int = 2, ecc: EccLevel = EccLevel.M) -> ImageTexture:
	var img = generate_image(text, module_pixel_size, margin, ecc)
	return ImageTexture.create_from_image(img)
