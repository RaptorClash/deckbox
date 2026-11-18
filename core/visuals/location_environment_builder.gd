# core/visuals/location_environment_builder.gd
# Procedural 3D room, landscape & table styling builder for DeckBox locations.
# Replaces the empty background void with immersive 3D scenes & matching table finishes.
class_name LocationEnvironmentBuilder
extends RefCounted

const LOCATIONS: Array[String] = [
	"cozy_house",
	"forest_glade",
	"neon_club",
	"bowling_alley",
	"rustic_pub"
]

const THEME_PRESETS: Dictionary = {
	"cozy_house": {
		"sky": Color(0.14, 0.11, 0.09, 1.0),
		"ambient": Color(0.95, 0.84, 0.70, 1.0),
		"ambient_energy": 0.72,
		"fog_color": Color(0.18, 0.14, 0.11, 1.0),
		"key_color": Color(1.0, 0.92, 0.80, 1.0),
		"key_energy": 1.12,
		"felt": Color(0.16, 0.48, 0.27, 1.0),
		"rim": Color(0.42, 0.24, 0.13, 1.0),
		"accent": Color(0.88, 0.65, 0.28, 1.0)
	},
	"forest_glade": {
		"sky": Color(0.06, 0.12, 0.14, 1.0),
		"ambient": Color(0.58, 0.78, 0.66, 1.0),
		"ambient_energy": 0.76,
		"fog_color": Color(0.08, 0.16, 0.15, 1.0),
		"key_color": Color(0.85, 0.95, 0.88, 1.0),
		"key_energy": 1.05,
		"felt": Color(0.14, 0.42, 0.24, 1.0),
		"rim": Color(0.32, 0.21, 0.12, 1.0),
		"accent": Color(1.0, 0.62, 0.22, 1.0)
	},
	"neon_club": {
		"sky": Color(0.05, 0.04, 0.12, 1.0),
		"ambient": Color(0.55, 0.50, 0.85, 1.0),
		"ambient_energy": 0.74,
		"fog_color": Color(0.06, 0.05, 0.15, 1.0),
		"key_color": Color(0.82, 0.88, 1.0, 1.0),
		"key_energy": 1.10,
		"felt": Color(0.08, 0.14, 0.26, 1.0),
		"rim": Color(0.16, 0.17, 0.24, 1.0),
		"accent": Color(0.15, 0.90, 1.0, 1.0)
	},
	"bowling_alley": {
		"sky": Color(0.08, 0.08, 0.16, 1.0),
		"ambient": Color(0.75, 0.78, 0.95, 1.0),
		"ambient_energy": 0.78,
		"fog_color": Color(0.10, 0.10, 0.18, 1.0),
		"key_color": Color(0.95, 0.92, 1.0, 1.0),
		"key_energy": 1.15,
		"felt": Color(0.12, 0.34, 0.46, 1.0),
		"rim": Color(0.72, 0.50, 0.26, 1.0),
		"accent": Color(1.0, 0.46, 0.18, 1.0)
	},
	"rustic_pub": {
		"sky": Color(0.11, 0.07, 0.05, 1.0),
		"ambient": Color(0.92, 0.72, 0.48, 1.0),
		"ambient_energy": 0.70,
		"fog_color": Color(0.14, 0.09, 0.06, 1.0),
		"key_color": Color(1.0, 0.84, 0.62, 1.0),
		"key_energy": 1.08,
		"felt": Color(0.38, 0.16, 0.14, 1.0),
		"rim": Color(0.30, 0.16, 0.08, 1.0),
		"accent": Color(0.98, 0.72, 0.28, 1.0)
	}
}

static func get_available_locations() -> Array[String]:
	return LOCATIONS.duplicate()

static func apply_to_table(table_node: Node3D, location_id: String) -> Node3D:
	if table_node == null:
		return null
	var loc = location_id.strip_edges().to_lower()
	if not THEME_PRESETS.has(loc):
		loc = "cozy_house"
	var cfg: Dictionary = THEME_PRESETS[loc]

	var old_backdrop = table_node.get_node_or_null("LocationBackdrop3D")
	if old_backdrop != null:
		table_node.remove_child(old_backdrop)
		old_backdrop.queue_free()

	var backdrop := Node3D.new()
	backdrop.name = "LocationBackdrop3D"
	table_node.add_child(backdrop)

	_apply_world_and_lights(table_node, cfg)
	_apply_table_materials(table_node, cfg)

	match loc:
		"cozy_house":
			_build_cozy_house(backdrop, cfg)
		"forest_glade":
			_build_forest_glade(backdrop, cfg)
		"neon_club":
			_build_neon_club(backdrop, cfg)
		"bowling_alley":
			_build_bowling_alley(backdrop, cfg)
		"rustic_pub":
			_build_rustic_pub(backdrop, cfg)

	return backdrop

static func _apply_world_and_lights(table_node: Node3D, cfg: Dictionary) -> void:
	var world_env: WorldEnvironment = table_node.get_node_or_null("WorldEnvironment")
	if world_env != null:
		var env: Environment = world_env.environment
		if env == null:
			env = Environment.new()
			world_env.environment = env
		env.background_mode = Environment.BG_COLOR
		env.background_color = cfg["sky"]
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = cfg["ambient"]
		env.ambient_light_energy = float(cfg["ambient_energy"])
		env.fog_enabled = true
		env.fog_light_color = cfg["fog_color"]
		env.fog_density = 0.018

	var key_light: DirectionalLight3D = table_node.get_node_or_null("Lighting/KeyLight")
	if key_light != null:
		key_light.light_color = cfg["key_color"]
		key_light.light_energy = float(cfg["key_energy"])

static func _apply_table_materials(table_node: Node3D, cfg: Dictionary) -> void:
	var table_mesh = table_node.get_node_or_null("TableMesh")
	if table_mesh == null:
		return
	var felt_col: Color = cfg["felt"]
	var rim_col: Color = cfg["rim"]
	var accent_col: Color = cfg["accent"]

	var stack: Array[Node] = [table_mesh]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for ch in n.get_children():
			stack.append(ch)
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh == null:
				continue
			var nname := mi.name.to_lower()
			for s_idx in range(mi.mesh.get_surface_count()):
				var base_mat: Material = mi.get_active_material(s_idx)
				var mat_name := base_mat.resource_name.to_lower() if base_mat != null else ""
				var target_mat: StandardMaterial3D = null
				if base_mat is StandardMaterial3D:
					target_mat = (base_mat as StandardMaterial3D).duplicate()
				else:
					target_mat = StandardMaterial3D.new()

				if "felt" in nname or "felt" in mat_name or "cloth" in mat_name or "surface" in nname:
					target_mat.albedo_color = felt_col
					target_mat.roughness = 0.85
				elif "neon" in nname or "neon" in mat_name or "ring" in nname or "glow" in mat_name or "led" in mat_name:
					target_mat.albedo_color = accent_col
					target_mat.emission_enabled = true
					target_mat.emission = accent_col
					target_mat.emission_energy_multiplier = 1.4
				elif "rim" in nname or "wood" in mat_name or "frame" in nname or "leg" in nname:
					target_mat.albedo_color = rim_col
					target_mat.roughness = 0.55
				elif s_idx == 0:
					target_mat.albedo_color = felt_col
				else:
					target_mat.albedo_color = rim_col

				mi.set_surface_override_material(s_idx, target_mat)

static func _make_box(parent: Node3D, box_name: String, size: Vector3, pos: Vector3, color: Color, roughness: float = 0.78, emission_energy: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = box_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	if emission_energy > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission_energy
	mi.material_override = mat
	parent.add_child(mi)
	return mi

static func _make_cyl(parent: Node3D, cyl_name: String, top_r: float, bot_r: float, h: float, pos: Vector3, color: Color, roughness: float = 0.75, emission_energy: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = cyl_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_r
	mesh.bottom_radius = bot_r
	mesh.height = h
	mesh.radial_segments = 16
	mi.mesh = mesh
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	if emission_energy > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission_energy
	mi.material_override = mat
	parent.add_child(mi)
	return mi

static func _make_light(parent: Node3D, light_name: String, pos: Vector3, color: Color, energy: float = 1.8, light_range: float = 14.0) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.name = light_name
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	parent.add_child(l)
	return l

static func _build_cozy_house(root: Node3D, cfg: Dictionary) -> void:
	# Warm parquet floor & living-room rug under table
	_make_box(root, "ParquetFloor", Vector3(28.0, 0.1, 24.0), Vector3(0.0, -0.06, 0.0), Color(0.28, 0.18, 0.11, 1.0), 0.58)
	_make_box(root, "LivingRug", Vector3(5.6, 0.03, 4.2), Vector3(0.0, 0.0, 0.0), Color(0.45, 0.20, 0.18, 1.0), 0.92)
	_make_box(root, "RugBorder", Vector3(5.8, 0.02, 4.4), Vector3(0.0, -0.005, 0.0), Color(0.76, 0.58, 0.34, 1.0), 0.85)
	# Warm living room walls
	_make_box(root, "BackWall", Vector3(26.0, 9.0, 0.4), Vector3(0.0, 4.4, -7.2), Color(0.24, 0.19, 0.16, 1.0), 0.88)
	_make_box(root, "LeftWall", Vector3(0.4, 9.0, 22.0), Vector3(-9.5, 4.4, 0.0), Color(0.22, 0.17, 0.14, 1.0), 0.88)
	_make_box(root, "RightWall", Vector3(0.4, 9.0, 22.0), Vector3(9.5, 4.4, 0.0), Color(0.22, 0.17, 0.14, 1.0), 0.88)
	# Wainscoting & glowing evening window
	_make_box(root, "Wainscot", Vector3(25.6, 1.6, 0.46), Vector3(0.0, 0.8, -7.15), Color(0.36, 0.24, 0.15, 1.0), 0.65)
	_make_box(root, "WindowFrame", Vector3(3.8, 2.8, 0.2), Vector3(-2.6, 3.6, -6.92), Color(0.45, 0.30, 0.18, 1.0), 0.6)
	_make_box(root, "WindowGlow", Vector3(3.4, 2.4, 0.12), Vector3(-2.6, 3.6, -6.90), Color(0.95, 0.78, 0.48, 1.0), 0.3, 0.85)
	# Bookshelf + warm floor lamp
	_make_box(root, "Bookshelf", Vector3(2.8, 4.0, 0.8), Vector3(3.6, 2.0, -6.5), Color(0.34, 0.20, 0.11, 1.0), 0.65)
	for s_y in [1.1, 2.1, 3.1]:
		_make_box(root, "BookRow_%s" % str(s_y), Vector3(2.2, 0.55, 0.55), Vector3(3.6, s_y, -6.35), cfg["accent"], 0.75)
	_make_cyl(root, "LampStand", 0.06, 0.14, 2.6, Vector3(-5.8, 1.3, -4.6), Color(0.22, 0.18, 0.14, 1.0), 0.4)
	_make_cyl(root, "LampShade", 0.25, 0.48, 0.65, Vector3(-5.8, 2.75, -4.6), Color(0.98, 0.85, 0.58, 1.0), 0.4, 1.35)
	_make_light(root, "WarmLampLight", Vector3(-5.2, 2.8, -4.0), Color(1.0, 0.82, 0.55, 1.0), 2.1, 16.0)

static func _build_forest_glade(root: Node3D, _cfg: Dictionary) -> void:
	# Mossy glade ground & central clearing patch
	_make_box(root, "ForestFloor", Vector3(34.0, 0.1, 30.0), Vector3(0.0, -0.06, 0.0), Color(0.11, 0.24, 0.12, 1.0), 0.94)
	_make_cyl(root, "GladeClearing", 4.5, 4.6, 0.04, Vector3(0.0, -0.005, 0.0), Color(0.16, 0.31, 0.15, 1.0), 0.92)
	# Campfire stone ring at back-left
	_make_cyl(root, "CampfireEmber", 0.45, 0.6, 0.25, Vector3(-4.6, 0.12, -5.2), Color(1.0, 0.46, 0.12, 1.0), 0.5, 2.2)
	_make_light(root, "CampfireLight", Vector3(-4.4, 1.2, -5.0), Color(1.0, 0.58, 0.24, 1.0), 2.6, 16.0)
	# Ring of stylized pine trees around the glade
	var tree_positions: Array[Vector3] = [
		Vector3(-7.5, 0.0, -5.5), Vector3(-4.8, 0.0, -7.8), Vector3(-1.2, 0.0, -8.5),
		Vector3(2.4, 0.0, -8.2), Vector3(5.6, 0.0, -6.8), Vector3(8.0, 0.0, -4.4),
		Vector3(-8.4, 0.0, -1.6), Vector3(8.5, 0.0, -1.0), Vector3(-7.6, 0.0, 2.5),
		Vector3(7.6, 0.0, 2.8), Vector3(0.5, 0.0, -10.8), Vector3(-5.8, 0.0, -10.2)
	]
	for idx in range(tree_positions.size()):
		var p: Vector3 = tree_positions[idx]
		var scale_h := 0.85 + 0.25 * float(idx % 3)
		_make_cyl(root, "Trunk_%d" % idx, 0.22, 0.32, 2.6 * scale_h, Vector3(p.x, 1.3 * scale_h, p.z), Color(0.28, 0.17, 0.09, 1.0), 0.9)
		_make_cyl(root, "CanopyA_%d" % idx, 0.10, 1.45, 2.4 * scale_h, Vector3(p.x, 3.1 * scale_h, p.z), Color(0.08, 0.28, 0.13, 1.0), 0.88)
		_make_cyl(root, "CanopyB_%d" % idx, 0.05, 1.05, 1.9 * scale_h, Vector3(p.x, 4.4 * scale_h, p.z), Color(0.11, 0.35, 0.17, 1.0), 0.85)
	_make_light(root, "MoonGladeLight", Vector3(3.0, 6.0, -5.0), Color(0.65, 0.85, 0.95, 1.0), 1.6, 22.0)

static func _build_neon_club(root: Node3D, cfg: Dictionary) -> void:
	# Glossy dark club floor + illuminated dance floor border
	_make_box(root, "ClubFloor", Vector3(30.0, 0.1, 26.0), Vector3(0.0, -0.06, 0.0), Color(0.05, 0.05, 0.09, 1.0), 0.18)
	_make_box(root, "NeonPadBorder", Vector3(6.2, 0.02, 4.8), Vector3(0.0, 0.0, 0.0), Color(0.09, 0.10, 0.16, 1.0), 0.25)
	_make_box(root, "BackClubWall", Vector3(28.0, 10.0, 0.4), Vector3(0.0, 4.8, -7.8), Color(0.06, 0.06, 0.11, 1.0), 0.45)
	# Neon light pillars & horizontal cyber stripes
	var pillar_x: Array[float] = [-6.8, -3.4, 0.0, 3.4, 6.8]
	for idx in range(pillar_x.size()):
		var col: Color = Color(0.95, 0.18, 0.72, 1.0) if idx % 2 == 0 else (cfg["accent"] as Color)
		_make_box(root, "ClubPillar_%d" % idx, Vector3(0.45, 7.5, 0.45), Vector3(pillar_x[idx], 3.75, -6.9), Color(0.09, 0.10, 0.15, 1.0), 0.35)
		_make_box(root, "NeonStrip_%d" % idx, Vector3(0.16, 6.8, 0.50), Vector3(pillar_x[idx], 3.7, -6.85), col, 0.2, 2.2)
	_make_box(root, "TopNeonBeam", Vector3(16.0, 0.18, 0.25), Vector3(0.0, 5.4, -6.8), Color(0.18, 0.90, 1.0, 1.0), 0.2, 2.0)
	_make_light(root, "ClubMagentaLight", Vector3(-4.5, 4.0, -4.5), Color(1.0, 0.25, 0.75, 1.0), 2.3, 18.0)
	_make_light(root, "ClubCyanLight", Vector3(4.5, 4.0, -4.5), Color(0.20, 0.90, 1.0, 1.0), 2.3, 18.0)

static func _build_bowling_alley(root: Node3D, cfg: Dictionary) -> void:
	# Concourse floor + glossy hardwood bowling lanes extending backward
	_make_box(root, "AlleyFloor", Vector3(32.0, 0.1, 28.0), Vector3(0.0, -0.06, 0.0), Color(0.10, 0.11, 0.17, 1.0), 0.35)
	for lane_idx in range(-2, 3):
		var lx := float(lane_idx) * 2.5
		_make_box(root, "LaneDeck_%d" % lane_idx, Vector3(2.1, 0.04, 15.0), Vector3(lx, -0.002, -4.2), Color(0.76, 0.56, 0.30, 1.0), 0.22)
		_make_box(root, "Gutter_%d" % lane_idx, Vector3(0.32, 0.03, 15.0), Vector3(lx + 1.21, -0.01, -4.2), Color(0.16, 0.18, 0.24, 1.0), 0.45)
		# Pins at back of lane
		for pin_x in [-0.36, 0.0, 0.36]:
			_make_cyl(root, "Pin_%d_%s" % [lane_idx, str(pin_x)], 0.07, 0.11, 0.65, Vector3(lx + pin_x, 0.33, -9.2), Color(0.96, 0.96, 0.98, 1.0), 0.3, 0.2)
	# Retro glowing scoring arch & ball return rack
	_make_box(root, "PinDeckMask", Vector3(15.5, 3.8, 0.4), Vector3(0.0, 4.2, -9.8), Color(0.11, 0.12, 0.20, 1.0), 0.45)
	_make_box(root, "AlleyNeonSign", Vector3(13.5, 0.28, 0.46), Vector3(0.0, 2.55, -9.6), cfg["accent"], 0.25, 2.0)
	_make_box(root, "AlleyTealNeon", Vector3(13.5, 0.18, 0.46), Vector3(0.0, 5.65, -9.6), Color(0.18, 0.92, 0.88, 1.0), 0.25, 1.8)
	_make_light(root, "AlleyWarmLight", Vector3(0.0, 4.5, -5.0), Color(1.0, 0.72, 0.42, 1.0), 2.1, 20.0)

static func _build_rustic_pub(root: Node3D, cfg: Dictionary) -> void:
	# Dark aged oak floorboards & tavern brick/timber walls
	_make_box(root, "PubFloor", Vector3(28.0, 0.1, 24.0), Vector3(0.0, -0.06, 0.0), Color(0.20, 0.12, 0.07, 1.0), 0.72)
	_make_box(root, "PubBackWall", Vector3(26.0, 9.0, 0.4), Vector3(0.0, 4.4, -7.4), Color(0.26, 0.13, 0.10, 1.0), 0.88)
	_make_box(root, "PubLeftWall", Vector3(0.4, 9.0, 22.0), Vector3(-9.5, 4.4, 0.0), Color(0.23, 0.12, 0.09, 1.0), 0.88)
	_make_box(root, "PubRightWall", Vector3(0.4, 9.0, 22.0), Vector3(9.5, 4.4, 0.0), Color(0.23, 0.12, 0.09, 1.0), 0.88)
	# Oak bar counter along back wall + tavern shelves
	_make_box(root, "BarCounter", Vector3(9.0, 1.45, 1.15), Vector3(0.0, 0.72, -5.6), Color(0.32, 0.17, 0.09, 1.0), 0.55)
	_make_box(root, "BarTop", Vector3(9.4, 0.14, 1.35), Vector3(0.0, 1.50, -5.6), Color(0.44, 0.24, 0.12, 1.0), 0.35)
	_make_box(root, "BottleShelf", Vector3(7.5, 0.12, 0.5), Vector3(0.0, 2.8, -6.9), Color(0.34, 0.19, 0.10, 1.0), 0.5)
	for b_idx in range(-5, 6):
		var bcol: Color = Color(0.18, 0.55, 0.22, 1.0) if b_idx % 2 == 0 else (cfg["accent"] as Color)
		_make_cyl(root, "Bottle_%d" % b_idx, 0.06, 0.11, 0.55, Vector3(float(b_idx) * 0.62, 3.12, -6.85), bcol, 0.25, 0.25)
	# Warm hanging pub lanterns & barrels
	_make_cyl(root, "PubBarrelL", 0.52, 0.45, 1.3, Vector3(-6.2, 0.65, -5.4), Color(0.36, 0.20, 0.10, 1.0), 0.75)
	_make_cyl(root, "PubBarrelR", 0.52, 0.45, 1.3, Vector3(6.2, 0.65, -5.4), Color(0.36, 0.20, 0.10, 1.0), 0.75)
	_make_cyl(root, "LanternL", 0.18, 0.24, 0.45, Vector3(-3.2, 4.2, -4.6), Color(1.0, 0.76, 0.36, 1.0), 0.3, 1.8)
	_make_cyl(root, "LanternR", 0.18, 0.24, 0.45, Vector3(3.2, 4.2, -4.6), Color(1.0, 0.76, 0.36, 1.0), 0.3, 1.8)
	_make_light(root, "PubAmberLight", Vector3(0.0, 3.8, -4.4), Color(1.0, 0.74, 0.40, 1.0), 2.3, 18.0)
