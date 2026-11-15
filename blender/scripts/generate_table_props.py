#!/usr/bin/env python3
"""
DeckBox Procedural Table Props Generator
========================================
Generates 3 themed 3D table models with quality presets:
1. arcade_ps5: Dark chassis, glowing neon cyan perimeter, dark felt.
2. cozy_wood: Rich mahogany wooden rim, emerald green felt, brass corner caps.
3. clean_25d: Clean orthographic top-down table, slate surface, pedestal disc.

Budget: < 10,000 triangles per model.
Export targets:
- assets/3d/table_arcade.glb
- assets/3d/table_cozy.glb
- assets/3d/table_clean.glb

Usage:
  "C:\\Program Files\\Blender Foundation\\Blender 4.5\\blender.exe" --background --python blender/scripts/generate_table_props.py
  "C:\\Program Files\\Blender Foundation\\Blender 4.5\\blender.exe" --background --python blender/scripts/generate_table_props.py -- --preset high
"""

import sys
import os
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


def ensure_uv(obj: bpy.types.Object) -> None:
    if obj and obj.data and len(obj.data.uv_layers) == 0:
        obj.data.uv_layers.new(name="UVMap")


def create_material(name: str, base_color: tuple, roughness: float = 0.5, metallic: float = 0.0, emission_color: tuple = None, emission_strength: float = 1.0) -> bpy.types.Material:
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


def generate_arcade_ps5(output_path: str, preset: str = "high") -> str:
    """Generates the futuristic arcade_ps5 table model."""
    clear_scene()
    seg = 32 if preset == "high" else (20 if preset == "medium" else 12)

    # 1. Dark Aerodynamic Chassis
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.725))
    top = bpy.context.active_object
    top.name = "ArcadeChassis"
    top.scale = (1.8, 1.1, 0.05)
    bpy.ops.object.transform_apply(scale=True)
    ensure_uv(top)

    # 2. Recessed Dark Felt Surface
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.751))
    felt = bpy.context.active_object
    felt.name = "ArcadeFelt"
    felt.scale = (1.5, 0.8, 0.005)
    bpy.ops.object.transform_apply(scale=True)
    ensure_uv(felt)

    # 3. Glowing Neon Cyan Ring
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.752))
    neon = bpy.context.active_object
    neon.name = "ArcadeNeon"
    neon.scale = (1.55, 0.85, 0.002)
    bpy.ops.object.transform_apply(scale=True)
    ensure_uv(neon)

    # 4. Aerodynamic Pedestal Legs
    bpy.ops.mesh.primitive_cylinder_add(vertices=seg, radius=0.2, depth=0.7, location=(-0.5, 0, 0.35))
    leg1 = bpy.context.active_object
    leg1.name = "ArcadeLeg_L"
    ensure_uv(leg1)

    bpy.ops.mesh.primitive_cylinder_add(vertices=seg, radius=0.2, depth=0.7, location=(0.5, 0, 0.35))
    leg2 = bpy.context.active_object
    leg2.name = "ArcadeLeg_R"
    ensure_uv(leg2)

    # Materials
    m_body = create_material("Mat_Arcade_Chassis", (0.05, 0.05, 0.07, 1.0), roughness=0.3, metallic=0.8)
    m_felt = create_material("Mat_Arcade_Felt", (0.03, 0.05, 0.10, 1.0), roughness=0.85)
    m_neon = create_material("Mat_Arcade_Neon", (0.0, 0.85, 1.0, 1.0), emission_color=(0.0, 0.85, 1.0, 1.0), emission_strength=5.0)

    top.data.materials.append(m_body)
    felt.data.materials.append(m_felt)
    neon.data.materials.append(m_neon)
    leg1.data.materials.append(m_body)
    leg2.data.materials.append(m_body)

    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(output_path), export_format='GLB', export_apply=True)
    print(f"[SUCCESS] arcade_ps5 exported to {output_path}")
    return output_path


def generate_cozy_wood(output_path: str, preset: str = "high") -> str:
    """Generates the warm mahogany cozy_wood table model."""
    clear_scene()

    # 1. Beveled Mahogany Rim
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.72))
    rim = bpy.context.active_object
    rim.name = "CozyWoodRim"
    rim.scale = (1.7, 1.05, 0.06)
    bpy.ops.object.transform_apply(scale=True)
    ensure_uv(rim)

    # 2. Recessed Green Felt Surface
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.751))
    felt = bpy.context.active_object
    felt.name = "CozyFelt"
    felt.scale = (1.45, 0.80, 0.005)
    bpy.ops.object.transform_apply(scale=True)
    ensure_uv(felt)

    # 3. 4 Turned Wooden Legs + Brass Corner Caps
    leg_coords = [(-0.75, -0.425), (0.75, -0.425), (-0.75, 0.425), (0.75, 0.425)]
    legs = []
    caps = []
    for idx, (lx, ly) in enumerate(leg_coords):
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(lx, ly, 0.345))
        leg = bpy.context.active_object
        leg.name = f"WoodLeg_{idx+1}"
        leg.scale = (0.08, 0.08, 0.69)
        bpy.ops.object.transform_apply(scale=True)
        ensure_uv(leg)
        legs.append(leg)

        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(lx, ly, 0.72))
        cap = bpy.context.active_object
        cap.name = f"BrassCap_{idx+1}"
        cap.scale = (0.09, 0.09, 0.07)
        bpy.ops.object.transform_apply(scale=True)
        ensure_uv(cap)
        caps.append(cap)

    # Materials
    m_wood = create_material("Mat_Wood_Mahogany", (0.24, 0.08, 0.03, 1.0), roughness=0.45)
    m_felt = create_material("Mat_Felt_Green", (0.04, 0.25, 0.09, 1.0), roughness=0.9)
    m_brass = create_material("Mat_Brass_Trim", (0.88, 0.72, 0.28, 1.0), roughness=0.2, metallic=0.95)

    rim.data.materials.append(m_wood)
    felt.data.materials.append(m_felt)
    for leg in legs:
        leg.data.materials.append(m_wood)
    for cap in caps:
        cap.data.materials.append(m_brass)

    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(output_path), export_format='GLB', export_apply=True)
    print(f"[SUCCESS] cozy_wood exported to {output_path}")
    return output_path


def generate_clean_25d(output_path: str, preset: str = "high") -> str:
    """Generates the minimalist clean_25d table model."""
    clear_scene()
    seg = 36 if preset == "high" else (24 if preset == "medium" else 14)

    # 1. Clean Off-White Border / Tabletop
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.725))
    top = bpy.context.active_object
    top.name = "CleanBorder"
    top.scale = (1.6, 1.0, 0.05)
    bpy.ops.object.transform_apply(scale=True)
    ensure_uv(top)

    # 2. Neutral Slate Play Surface
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.751))
    felt = bpy.context.active_object
    felt.name = "CleanSurface"
    felt.scale = (1.4, 0.8, 0.005)
    bpy.ops.object.transform_apply(scale=True)
    ensure_uv(felt)

    # 3. Minimalist Pedestal Column & Floor Disc Base
    bpy.ops.mesh.primitive_cylinder_add(vertices=seg, radius=0.15, depth=0.70, location=(0, 0, 0.35))
    pillar = bpy.context.active_object
    pillar.name = "CleanPillar"
    ensure_uv(pillar)

    bpy.ops.mesh.primitive_cylinder_add(vertices=seg, radius=0.45, depth=0.025, location=(0, 0, 0.0125))
    base = bpy.context.active_object
    base.name = "CleanBase"
    ensure_uv(base)

    # Materials
    m_surf = create_material("Mat_Clean_Surface", (0.18, 0.22, 0.26, 1.0), roughness=0.8)
    m_border = create_material("Mat_Clean_Border", (0.90, 0.90, 0.92, 1.0), roughness=0.35)
    m_base = create_material("Mat_Clean_Base", (0.12, 0.13, 0.15, 1.0), roughness=0.6)

    felt.data.materials.append(m_surf)
    top.data.materials.append(m_border)
    pillar.data.materials.append(m_base)
    base.data.materials.append(m_base)

    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(output_path), export_format='GLB', export_apply=True)
    print(f"[SUCCESS] clean_25d exported to {output_path}")
    return output_path


def main() -> int:
    if not BLENDER_AVAILABLE:
        print("[ERROR] bpy module is unavailable. Run with Blender --background.")
        return 1

    cli_args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description="Procedural Table Props Generator")
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
