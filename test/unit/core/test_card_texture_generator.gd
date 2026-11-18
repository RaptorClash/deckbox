# test_card_texture_generator.gd
# GUT 9.x Headless Test Suite: Procedural Card Texture Generator & 3D Material Slots
extends GutTest

const CARD_TEX_GEN_PATH = "res://core/visuals/card_texture_generator.gd"
const CARD_MESH_PATH = "res://assets/3d/card_rounded.glb"

var _gen_script: GDScript

func before_all() -> void:
	if ResourceLoader.exists(CARD_TEX_GEN_PATH):
		_gen_script = load(CARD_TEX_GEN_PATH)

func test_classic_arcade_front_and_back_textures() -> void:
	assert_not_null(_gen_script, "CardTextureGenerator script must exist")
	var sample_cards = [
		{ "id": "r0", "color": "red", "value": "0" },
		{ "id": "b7", "color": "blue", "value": "7" },
		{ "id": "g_skip", "color": "green", "value": "skip" },
		{ "id": "y_rev", "color": "yellow", "value": "reverse" },
		{ "id": "r_d2", "color": "red", "value": "draw_two" },
		{ "id": "w", "color": "wild", "value": "wild" },
		{ "id": "w4", "color": "wild", "value": "wild_draw_four" }
	]

	for card in sample_cards:
		var tex = _gen_script.get_card_front_texture(card, "classic_arcade", true)
		assert_not_null(tex, "Front texture must not be null for %s" % card["id"])
		assert_true(tex is ImageTexture, "Must return ImageTexture")
		assert_gte(tex.get_width(), 128, "Front texture width must be >= 128")
		assert_gte(tex.get_height(), 180, "Front texture height must be >= 180")

		var img: Image = tex.get_image()
		var corner_col = img.get_pixel(4, 4)
		var body_col = img.get_pixel(16, 80)
		var center_col = img.get_pixel(img.get_width() / 2, img.get_height() / 2)
		assert_false(corner_col == body_col and body_col == center_col, "Texture for %s must have distinct visual regions, not flat color" % card["id"])

	var back_tex = _gen_script.get_card_back_texture("classic_arcade")
	assert_not_null(back_tex, "Classic back texture must not be null")
	assert_gte(back_tex.get_width(), 128)
	var back_img: Image = back_tex.get_image()
	assert_ne(back_img.get_pixel(16, 16), back_img.get_pixel(back_img.get_width() / 2, back_img.get_height() / 2), "Back texture must render center logo distinct from background")

func test_minimal_dark_skin_textures() -> void:
	assert_not_null(_gen_script, "CardTextureGenerator script must exist")
	var card = { "id": "b5", "color": "blue", "value": "5" }
	var tex_classic = _gen_script.get_card_front_texture(card, "classic_arcade", true)
	var tex_minimal = _gen_script.get_card_front_texture(card, "minimal_dark", true)
	assert_not_null(tex_minimal, "Minimal dark texture must generate")

	var img_c = tex_classic.get_image()
	var img_m = tex_minimal.get_image()
	# Classic border is bright white; Minimal dark body/border is dark slate
	assert_ne(img_c.get_pixel(4, 4), img_m.get_pixel(4, 4), "Classic Arcade and Minimal Dark skins must differ visually")

	var back_classic = _gen_script.get_card_back_texture("classic_arcade")
	var back_minimal = _gen_script.get_card_back_texture("minimal_dark")
	assert_ne(back_classic.get_image().get_pixel(24, 24), back_minimal.get_image().get_pixel(24, 24), "Card backs must differ between skins")

func test_custom_card_and_adversarial_inputs() -> void:
	assert_not_null(_gen_script, "CardTextureGenerator script must exist")
	var custom_card = {
		"id": "tornado_1",
		"name": "Tornado",
		"color": "wild",
		"value": "custom",
		"actions": [{ "type": "swap_hands" }]
	}
	var tex_custom = _gen_script.get_card_front_texture(custom_card, "classic_arcade", false)
	assert_not_null(tex_custom, "Custom card texture must generate cleanly")

	var empty_tex = _gen_script.get_card_front_texture({}, "unknown_skin", true)
	assert_not_null(empty_tex, "Empty card / unknown skin must safely fall back without null or crash")

func test_3d_card_material_generation_and_caching() -> void:
	assert_not_null(_gen_script, "CardTextureGenerator script must exist")
	var card_scene = load(CARD_MESH_PATH)
	assert_not_null(card_scene, "card_rounded.glb must load")
	var card_inst = card_scene.instantiate()
	add_child_autofree(card_inst)

	var card_data = { "id": "g4", "color": "green", "value": "4" }
	_gen_script.apply_card_materials_to_mesh(card_inst, card_data, "classic_arcade", true, true)

	var mesh_inst: MeshInstance3D = _find_mesh(card_inst)
	assert_not_null(mesh_inst, "Card mesh instance must exist")
	var mat_front = mesh_inst.get_surface_override_material(0)
	var mat_back = mesh_inst.get_surface_override_material(1)
	assert_true(mat_front is StandardMaterial3D, "Surface 0 (Front) must have StandardMaterial3D")
	assert_true(mat_back is StandardMaterial3D, "Surface 1 (Back) must have StandardMaterial3D")
	assert_not_null(mat_front.albedo_texture, "Front material must have generated albedo_texture")
	assert_not_null(mat_back.albedo_texture, "Back material must have generated albedo_texture")

	# Masked card face_up=false should hide face on surface 0
	_gen_script.apply_card_materials_to_mesh(card_inst, { "masked": true }, "classic_arcade", true, false)
	var masked_front = mesh_inst.get_surface_override_material(0)
	assert_eq(masked_front.albedo_texture, _gen_script.get_card_back_texture("classic_arcade"), "Masked card must never show a front texture on surface 0")

func test_flip_dual_sided_3d_card_materials_and_neutral_back() -> void:
	assert_not_null(_gen_script, "CardTextureGenerator script must exist")
	var card_scene = load(CARD_MESH_PATH)
	var card_inst = card_scene.instantiate()
	add_child_autofree(card_inst)

	var light_card = { "id": "b_d2", "color": "blue", "value": "draw_two" }
	var dark_opp_card = { "color": "teal", "value": "draw_five" }
	_gen_script.apply_card_materials_to_mesh(card_inst, light_card, "classic_arcade", true, true, dark_opp_card)

	var mesh_inst: MeshInstance3D = _find_mesh(card_inst)
	assert_not_null(mesh_inst)
	var mat_front = mesh_inst.get_surface_override_material(0)
	var mat_back = mesh_inst.get_surface_override_material(1)
	assert_eq(mat_front.albedo_texture, _gen_script.get_card_front_texture(light_card, "classic_arcade", true))
	assert_eq(mat_back.albedo_texture, _gen_script.get_card_front_texture(dark_opp_card, "classic_arcade", true), "Flip! card back surface must render opposite Flip side texture instead of classic back")

	# Masked opponent/draw-pile card in Flip! mode renders opposite Flip side texture on front/back
	_gen_script.apply_card_materials_to_mesh(card_inst, { "masked": true }, "classic_arcade", true, false, dark_opp_card)
	var flip_masked_mat = mesh_inst.get_surface_override_material(0)
	assert_eq(flip_masked_mat.albedo_texture, _gen_script.get_card_front_texture(dark_opp_card, "classic_arcade", true), "Flip! masked card must show opposite side texture")
	assert_ne(flip_masked_mat.albedo_texture, _gen_script.get_card_back_texture("classic_arcade"), "Flip! masked card must not show classic back")

func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var f = _find_mesh(c)
		if f != null:
			return f
	return null
