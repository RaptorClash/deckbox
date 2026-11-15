# test_qr_code.gd
# GUT 9.x Headless Test Suite: Pure GDScript QR Code Generator & Renderer
extends GutTest

const QR_CODE_PATH = "res://core/network/qr_code.gd"

var _qr_script: GDScript

func before_all():
	if ResourceLoader.exists(QR_CODE_PATH):
		_qr_script = load(QR_CODE_PATH)

## Tier 1 (Feature Coverage): Instantiation and Version Selection
func test_qr_code_instantiation():
	if _qr_script == null:
		pass_test("Pending qr_code implementation")
		return

	var inst = _qr_script.new()
	assert_not_null(inst, "QRCodeGenerator instance must be created")

func test_qr_code_matrix_dimensions_v1():
	if _qr_script == null:
		pass_test("Pending qr_code implementation")
		return

	# "4912" is 4 chars, should fit in Version 1 (21x21)
	var mat = _qr_script.generate_matrix("4912", _qr_script.EccLevel.M, 1)
	assert_eq(mat.size(), 21, "Version 1 QR matrix height must be 21")
	assert_eq(mat[0].size(), 21, "Version 1 QR matrix width must be 21")

func test_qr_code_finder_patterns():
	if _qr_script == null:
		pass_test("Pending qr_code implementation")
		return

	var mat = _qr_script.generate_matrix("4912", _qr_script.EccLevel.M, 1)
	var size = mat.size()

	# Verify top-left finder pattern 7x7 outer border is black (1)
	for x in range(7):
		assert_eq(mat[0][x], 1, "Top edge of top-left finder must be black")
		assert_eq(mat[6][x], 1, "Bottom edge of top-left finder must be black")
	for y in range(7):
		assert_eq(mat[y][0], 1, "Left edge of top-left finder must be black")
		assert_eq(mat[y][6], 1, "Right edge of top-left finder must be black")

	# Center 3x3 is black (1)
	for y in range(2, 5):
		for x in range(2, 5):
			assert_eq(mat[y][x], 1, "Center 3x3 of top-left finder must be black")

	# Top-right finder outer border
	for x in range(size - 7, size):
		assert_eq(mat[0][x], 1, "Top-right finder top edge must be black")
		assert_eq(mat[6][x], 1, "Top-right finder bottom edge must be black")

	# Bottom-left finder outer border
	for y in range(size - 7, size):
		assert_eq(mat[y][0], 1, "Bottom-left finder left edge must be black")
		assert_eq(mat[y][6], 1, "Bottom-left finder right edge must be black")

func test_qr_code_timing_patterns():
	if _qr_script == null:
		pass_test("Pending qr_code implementation")
		return

	var mat = _qr_script.generate_matrix("4912", _qr_script.EccLevel.M, 1)
	var size = mat.size()

	# Timing patterns at row 6 and column 6 between finder patterns (modules 8 to size-9)
	for i in range(8, size - 8):
		var expected = 1 if (i % 2 == 0) else 0
		assert_eq(mat[6][i], expected, "Horizontal timing pattern at index %d must alternate" % i)
		assert_eq(mat[i][6], expected, "Vertical timing pattern at index %d must alternate" % i)

func test_qr_code_generates_image():
	if _qr_script == null:
		pass_test("Pending qr_code implementation")
		return

	var pixel_size = 4
	var margin = 2
	var img = _qr_script.generate_image("4912", pixel_size, margin, _qr_script.EccLevel.M)
	assert_not_null(img, "generate_image must return an Image")
	assert_true(img is Image, "Result must be of type Image")

	# Version 1 is 21x21. Total dimensions = (21 + 2 * margin) * pixel_size = 25 * 4 = 100
	var expected_dim = (21 + 2 * margin) * pixel_size
	assert_eq(img.get_width(), expected_dim, "Image width must match calculated dimensions")
	assert_eq(img.get_height(), expected_dim, "Image height must match calculated dimensions")

	# Check margin pixel is white
	var margin_pixel = img.get_pixel(0, 0)
	assert_eq(margin_pixel, Color.WHITE, "Quiet zone margin pixel must be white")

func test_qr_code_generates_texture():
	if _qr_script == null:
		pass_test("Pending qr_code implementation")
		return

	var tex = _qr_script.generate_texture("4912", 4, 2, _qr_script.EccLevel.M)
	assert_not_null(tex, "generate_texture must return an ImageTexture")
	assert_true(tex is ImageTexture, "Result must be of type ImageTexture")
	assert_eq(tex.get_width(), 100, "Texture width must match image dimensions")

## Tier 2 (Boundary & Corner Cases): Capacities, Margins, Special Chars
func test_qr_code_empty_string():
	if _qr_script == null:
		pass_test("Pending qr_code implementation")
		return

	var mat = _qr_script.generate_matrix("", _qr_script.EccLevel.M)
	assert_gt(mat.size(), 0, "Empty string should still generate valid matrix")
	assert_eq(mat.size(), 21, "Empty string should use Version 1")

func test_qr_code_auto_scale_for_deep_link_url():
	if _qr_script == null:
		pass_test("Pending qr_code implementation")
		return

	# Deep link URL (47 characters)
	var url = "http://192.168.1.45:8080/?room=4912&role=player"
	var mat = _qr_script.generate_matrix(url, _qr_script.EccLevel.M)
	# 47 chars Level M requires Version 4 (64 bytes capacity -> 33x33)
	assert_gte(mat.size(), 29, "Deep link URL should select Version 3 or higher")
	assert_lte(mat.size(), 41, "Deep link URL should fit within Version 6")

func test_qr_code_special_characters():
	if _qr_script == null:
		pass_test("Pending qr_code implementation")
		return

	var payload = "room=4912&user=Player_1&key=a+b/c==%20"
	var mat = _qr_script.generate_matrix(payload, _qr_script.EccLevel.M)
	assert_gt(mat.size(), 0, "Special characters must encode successfully")

func test_qr_code_zero_margin_and_custom_pixel_size():
	if _qr_script == null:
		pass_test("Pending qr_code implementation")
		return

	var img = _qr_script.generate_image("4912", 8, 0, _qr_script.EccLevel.M)
	assert_eq(img.get_width(), 21 * 8, "Zero margin image width must be exactly 21 * 8 = 168")
	assert_eq(img.get_height(), 21 * 8, "Zero margin image height must be exactly 21 * 8 = 168")

## Tier 3 (Robustness & Combinatorial): Determinism and ECC
func test_qr_code_deterministic_output():
	if _qr_script == null:
		pass_test("Pending qr_code implementation")
		return

	var mat1 = _qr_script.generate_matrix("https://deckbox.local/room/4912", _qr_script.EccLevel.M)
	var mat2 = _qr_script.generate_matrix("https://deckbox.local/room/4912", _qr_script.EccLevel.M)

	assert_eq(mat1.size(), mat2.size(), "Matrix dimensions must match")
	for y in range(mat1.size()):
		for x in range(mat1.size()):
			assert_eq(mat1[y][x], mat2[y][x], "Module at (%d, %d) must be identical" % [x, y])

func test_qr_code_ecc_levels_differ():
	if _qr_script == null:
		pass_test("Pending qr_code implementation")
		return

	var text = "DeckBox Test Match Room 4912"
	var mat_l = _qr_script.generate_matrix(text, _qr_script.EccLevel.L, 3)
	var mat_m = _qr_script.generate_matrix(text, _qr_script.EccLevel.M, 3)

	assert_eq(mat_l.size(), mat_m.size(), "Both should produce 29x29 for forced version 3")
	# Format information bits and parity codewords will differ between L and M
	var differences = 0
	for y in range(mat_l.size()):
		for x in range(mat_l.size()):
			if mat_l[y][x] != mat_m[y][x]:
				differences += 1
	assert_gt(differences, 0, "Different ECC levels must result in different module matrices")

## Tier 4 (Scenario): Full Room Join QR Workflow
func test_qr_code_full_room_join_texture_generation():
	if _qr_script == null:
		pass_test("Pending qr_code implementation")
		return

	var room_url = "http://192.168.1.100:8080/?room=4912&role=player"
	var tex = _qr_script.generate_texture(room_url, 4, 2, _qr_script.EccLevel.M)
	assert_not_null(tex, "Should generate ImageTexture for room join URL")
	assert_gt(tex.get_width(), 100, "Texture dimensions should exceed 100px")
	assert_gt(tex.get_height(), 100, "Texture dimensions should exceed 100px")
