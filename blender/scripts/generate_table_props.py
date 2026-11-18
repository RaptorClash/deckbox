#!/usr/bin/env python3
"""
DeckBox Procedural Stadium Table Props Generator
================================================
Generates 3 high-craft rounded stadium 3D table models within <10,000 triangles:
1. arcade_ps5: Dark metallic chassis, recessed navy-obsidian felt, raised padded rail,
   hollow glowing neon perimeter ring & center play-zone ring, dual pedestal pillars.
2. cozy_wood: Warm mahogany rounded rim, emerald felt, brushed brass inlay ring, 4 tapered legs.
3. clean_25d: Minimalist satin border, high-contrast slate playmat, sleek central pedestal.

Usage:
  "C:\\Program Files\\Blender Foundation\\Blender 4.5\\blender.exe" --background --python blender/scripts/generate_table_props.py
"""

import sys
import math
import argparse
from pathlib import Path

try:
    import bpy
    import bmesh
    from mathutils import Vector
    BLENDER_AVAILABLE = True
except ImportError:
    BLENDER_AVAILABLE = False


def clear_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def ensure_planar_uv(obj: bpy.types.Object) -> None:
    if not obj or not obj.data:
        return
    mesh = obj.data
    if len(mesh.uv_layers) == 0:
        mesh.uv_layers.new(name="UVMap")
    uv_layer = mesh.uv_layers.active.data
    for poly in mesh.polygons:
        for loop_idx in poly.loop_indices:
            v = mesh.vertices[mesh.loops[loop_idx].vertex_index].co
            uv_layer[loop_idx].uv = (v.x * 0.5 + 0.5, v.y * 0.5 + 0.5)


def create_material(
    name: str,
    base_color: tuple,
    roughness: float = 0.5,
    metallic: float = 0.0,
    emission_color: tuple = None,
    emission_strength: float = 1.0,
) -> bpy.types.Material:
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = base_color
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Metallic"].default_value = metallic
        if emission_color:
            bsdf.inputs["Emission Color"].default_value = emission_color
            bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


def _stadium_points(width: float, depth: float, corner_r: float, segs: int) -> list:
    hw = width * 0.5
    hd = depth * 0.5
    r = min(corner_r, hw * 0.95, hd * 0.95)
    pts = []
    corners = [
        (hw - r, hd - r, 0.0),
        (-hw + r, hd - r, math.pi * 0.5),
        (-hw + r, -hd + r, math.pi),
        (hw - r, -hd + r, math.pi * 1.5),
    ]
    for cx, cy, start_ang in corners:
        for i in range(segs):
            ang = start_ang + (i / float(segs)) * (math.pi * 0.5)
            pts.append((cx + r * math.cos(ang), cy + r * math.sin(ang)))
    return pts


def _circle_points(radius: float, segs: int) -> list:
    return [
        (radius * math.cos(2.0 * math.pi * i / float(segs)), radius * math.sin(2.0 * math.pi * i / float(segs)))
        for i in range(segs)
    ]


def build_extruded_loop(name: str, pts_2d: list, z_bot: float, z_top: float, mat: bpy.types.Material) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)

    bm = bmesh.new()
    bot_verts = [bm.verts.new(Vector((x, y, z_bot))) for x, y in pts_2d]
    top_verts = [bm.verts.new(Vector((x, y, z_top))) for x, y in pts_2d]

    top_face = bm.faces.new(top_verts)
    bot_face = bm.faces.new(list(reversed(bot_verts)))
    n = len(pts_2d)
    for i in range(n):
        ni = (i + 1) % n
        bm.faces.new([bot_verts[i], bot_verts[ni], top_verts[ni], top_verts[i]])

    bmesh.ops.triangulate(bm, faces=[top_face, bot_face])
    bm.to_mesh(mesh)
    bm.free()

    obj.data.materials.append(mat)
    ensure_planar_uv(obj)
    return obj


def build_hollow_ring(name: str, outer_pts: list, inner_pts: list, z_bot: float, z_top: float, mat: bpy.types.Material) -> bpy.types.Object:
    """Builds a watertight hollow 3D ring/rail between matching outer and inner 2D loops."""
    assert len(outer_pts) == len(inner_pts)
    n = len(outer_pts)

    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)

    bm = bmesh.new()
    ob = [bm.verts.new(Vector((x, y, z_bot))) for x, y in outer_pts]
    ot = [bm.verts.new(Vector((x, y, z_top))) for x, y in outer_pts]
    ib = [bm.verts.new(Vector((x, y, z_bot))) for x, y in inner_pts]
    it = [bm.verts.new(Vector((x, y, z_top))) for x, y in inner_pts]

    for i in range(n):
        ni = (i + 1) % n
        # Top cap
        bm.faces.new([ot[i], ot[ni], it[ni], it[i]])
        # Bottom cap
        bm.faces.new([ib[i], ib[ni], ob[ni], ob[i]])
        # Outer wall
        bm.faces.new([ob[i], ob[ni], ot[ni], ot[i]])
        # Inner wall
        bm.faces.new([it[i], it[ni], ib[ni], ib[i]])

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()

    obj.data.materials.append(mat)
    ensure_planar_uv(obj)
    return obj


def generate_arcade_ps5(output_path: str, preset: str = "high") -> str:
    """Generates the futuristic rounded-stadium arcade_ps5 table model."""
    clear_scene()
    c_seg = 10 if preset == "high" else (7 if preset == "medium" else 4)
    p_seg = 28 if preset == "high" else (18 if preset == "medium" else 12)

    m_chassis = create_material("Mat_Arcade_Chassis", (0.04, 0.045, 0.07, 1.0), roughness=0.28, metallic=0.82)
    m_rail = create_material("Mat_Arcade_Rail", (0.07, 0.08, 0.12, 1.0), roughness=0.45, metallic=0.15)
    m_felt = create_material("Mat_Arcade_Felt", (0.025, 0.04, 0.085, 1.0), roughness=0.88, metallic=0.0)
    m_neon = create_material(
        "Mat_Arcade_Neon",
        (0.0, 0.85, 1.0, 1.0),
        roughness=0.15,
        emission_color=(0.0, 0.88, 1.0, 1.0),
        emission_strength=2.8,
    )
    m_center_ring = create_material(
        "Mat_Arcade_CenterRing",
        (0.08, 0.55, 0.95, 1.0),
        roughness=0.2,
        emission_color=(0.1, 0.65, 1.0, 1.0),
        emission_strength=1.4,
    )

    # 1. Under-chassis slab
    outer_pts = _stadium_points(2.04, 1.32, 0.48, c_seg)
    build_extruded_loop("ArcadeChassis", outer_pts, 0.685, 0.742, m_chassis)

    # 2. Recessed dark felt surface (top at z=0.750)
    felt_pts = _stadium_points(1.80, 1.08, 0.38, c_seg)
    build_extruded_loop("ArcadeFelt", felt_pts, 0.740, 0.750, m_felt)

    # 3. Raised padded armrest rail around felt
    rail_outer = _stadium_points(2.04, 1.32, 0.48, c_seg)
    rail_inner = _stadium_points(1.80, 1.08, 0.38, c_seg)
    build_hollow_ring("ArcadeArmrestRail", rail_outer, rail_inner, 0.742, 0.774, m_rail)

    # 4. Hollow glowing neon trim ring nestled along inner rim (never covers felt!)
    neon_outer = _stadium_points(1.80, 1.08, 0.38, c_seg)
    neon_inner = _stadium_points(1.76, 1.04, 0.36, c_seg)
    build_hollow_ring("ArcadeNeonTrim", neon_outer, neon_inner, 0.749, 0.755, m_neon)

    # 5. Subtle center play-zone ring on felt
    ring_segs = c_seg * 4
    build_hollow_ring(
        "ArcadeCenterZone",
        _circle_points(0.41, ring_segs),
        _circle_points(0.39, ring_segs),
        0.7495,
        0.7515,
        m_center_ring,
    )

    # 6. Dual cylindrical pedestal legs + sleek base bar
    for idx, lx in enumerate([-0.55, 0.55]):
        bpy.ops.mesh.primitive_cylinder_add(vertices=p_seg, radius=0.14, depth=0.685, location=(lx, 0.0, 0.3425))
        leg = bpy.context.active_object
        leg.name = f"ArcadeLeg_{idx+1}"
        leg.data.materials.append(m_chassis)
        ensure_planar_uv(leg)

    base_pts = _stadium_points(1.50, 0.54, 0.24, c_seg)
    build_extruded_loop("ArcadeFloorBase", base_pts, 0.0, 0.025, m_chassis)

    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(output_path), export_format='GLB', export_apply=True)
    print(f"[SUCCESS] arcade_ps5 exported to {output_path}")
    return output_path


def generate_cozy_wood(output_path: str, preset: str = "high") -> str:
    """Generates the warm mahogany rounded-stadium cozy_wood table model."""
    clear_scene()
    c_seg = 10 if preset == "high" else (7 if preset == "medium" else 4)

    m_wood = create_material("Mat_Wood_Mahogany", (0.23, 0.085, 0.035, 1.0), roughness=0.42, metallic=0.05)
    m_felt = create_material("Mat_Felt_Emerald", (0.035, 0.24, 0.095, 1.0), roughness=0.90)
    m_brass = create_material("Mat_Brass_Trim", (0.88, 0.72, 0.28, 1.0), roughness=0.22, metallic=0.92)

    # 1. Under-table mahogany apron
    outer_pts = _stadium_points(1.98, 1.26, 0.42, c_seg)
    build_extruded_loop("CozyApron", outer_pts, 0.685, 0.742, m_wood)

    # 2. Recessed emerald casino felt
    felt_pts = _stadium_points(1.74, 1.02, 0.34, c_seg)
    build_extruded_loop("CozyFelt", felt_pts, 0.740, 0.750, m_felt)

    # 3. Raised mahogany armrest rail
    rail_inner = _stadium_points(1.74, 1.02, 0.34, c_seg)
    build_hollow_ring("CozyWoodRim", outer_pts, rail_inner, 0.742, 0.774, m_wood)

    # 4. Brushed brass inlay ring around inner edge + center ring
    inlay_inner = _stadium_points(1.71, 0.99, 0.32, c_seg)
    build_hollow_ring("CozyBrassInlay", rail_inner, inlay_inner, 0.749, 0.753, m_brass)

    ring_segs = c_seg * 4
    build_hollow_ring(
        "CozyCenterRing",
        _circle_points(0.40, ring_segs),
        _circle_points(0.388, ring_segs),
        0.7495,
        0.7515,
        m_brass,
    )

    # 5. 4 wooden legs with brass floor feet
    leg_coords = [(-0.72, -0.40), (0.72, -0.40), (-0.72, 0.40), (0.72, 0.40)]
    for idx, (lx, ly) in enumerate(leg_coords):
        bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.042, depth=0.635, location=(lx, ly, 0.3725))
        leg = bpy.context.active_object
        leg.name = f"WoodLeg_{idx+1}"
        leg.data.materials.append(m_wood)
        ensure_planar_uv(leg)

        bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.046, depth=0.055, location=(lx, ly, 0.0275))
        foot = bpy.context.active_object
        foot.name = f"BrassFoot_{idx+1}"
        foot.data.materials.append(m_brass)
        ensure_planar_uv(foot)

    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(output_path), export_format='GLB', export_apply=True)
    print(f"[SUCCESS] cozy_wood exported to {output_path}")
    return output_path


def generate_clean_25d(output_path: str, preset: str = "high") -> str:
    """Generates the minimalist clean_25d rounded-stadium table model."""
    clear_scene()
    c_seg = 10 if preset == "high" else (7 if preset == "medium" else 4)
    p_seg = 32 if preset == "high" else (20 if preset == "medium" else 12)

    m_surf = create_material("Mat_Clean_Surface", (0.14, 0.17, 0.22, 1.0), roughness=0.82)
    m_border = create_material("Mat_Clean_Border", (0.86, 0.88, 0.92, 1.0), roughness=0.35, metallic=0.1)
    m_accent = create_material("Mat_Clean_Accent", (0.35, 0.58, 0.85, 1.0), roughness=0.35)
    m_base = create_material("Mat_Clean_Base", (0.10, 0.12, 0.15, 1.0), roughness=0.55, metallic=0.4)

    # 1. Clean rounded border & recessed surface
    outer_pts = _stadium_points(1.94, 1.24, 0.42, c_seg)
    build_extruded_loop("CleanChassis", outer_pts, 0.70, 0.742, m_border)

    felt_pts = _stadium_points(1.74, 1.04, 0.34, c_seg)
    build_extruded_loop("CleanSurface", felt_pts, 0.740, 0.750, m_surf)

    build_hollow_ring("CleanBorderRail", outer_pts, felt_pts, 0.742, 0.764, m_border)

    ring_segs = c_seg * 4
    build_hollow_ring(
        "CleanCenterRing",
        _circle_points(0.40, ring_segs),
        _circle_points(0.388, ring_segs),
        0.7495,
        0.7515,
        m_accent,
    )

    # 2. Central pedestal & floor disc
    bpy.ops.mesh.primitive_cylinder_add(vertices=p_seg, radius=0.15, depth=0.70, location=(0.0, 0.0, 0.35))
    pillar = bpy.context.active_object
    pillar.name = "CleanPillar"
    pillar.data.materials.append(m_base)
    ensure_planar_uv(pillar)

    bpy.ops.mesh.primitive_cylinder_add(vertices=p_seg, radius=0.46, depth=0.025, location=(0.0, 0.0, 0.0125))
    base = bpy.context.active_object
    base.name = "CleanBase"
    base.data.materials.append(m_base)
    ensure_planar_uv(base)

    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(output_path), export_format='GLB', export_apply=True)
    print(f"[SUCCESS] clean_25d exported to {output_path}")
    return output_path


def main() -> int:
    if not BLENDER_AVAILABLE:
        print("[ERROR] bpy module is unavailable. Run with Blender --background.")
        return 1

    cli_args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description="Procedural Stadium Table Props Generator")
    parser.add_argument("--output-dir", type=str, default="assets/3d", help="Directory for exported .glb models")
    parser.add_argument("--preset", type=str, default="high", choices=["high", "medium", "low"], help="Quality preset")
    args = parser.parse_args(cli_args)

    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    generate_arcade_ps5(str(out_dir / "table_arcade.glb"), preset=args.preset)
    generate_cozy_wood(str(out_dir / "table_cozy.glb"), preset=args.preset)
    generate_clean_25d(str(out_dir / "table_clean.glb"), preset=args.preset)
    return 0


if __name__ == "__main__":
    sys.exit(main())
