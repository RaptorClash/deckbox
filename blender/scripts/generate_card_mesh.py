#!/usr/bin/env python3
"""
DeckBox Procedural Playing Card Mesh Generator
==============================================
Generates a low-poly 3D playing card mesh with rounded corners,
proper 3-slot material assignment, and normalized UV unwrap:
- Triangle budget: < 500 triangles (actual: ~92 triangles)
- Dimensions: 0.063m x 0.088m x 0.0003m (63mm x 88mm x 0.3mm poker size)
- Corner radius: 0.0035m (3.5mm)
- Material slots: Mat_Front, Mat_Back, Mat_Edge
- UV unwrap: Front [0, 1]x[0, 1], Back [0, 1]x[0, 1] (mirrored), Edge normalized
- Export target: assets/3d/card_rounded.glb

Usage:
  "C:\\Program Files\\Blender Foundation\\Blender 4.5\\blender.exe" --background --python blender/scripts/generate_card_mesh.py
  "C:\\Program Files\\Blender Foundation\\Blender 4.5\\blender.exe" --background --python blender/scripts/generate_card_mesh.py -- --output assets/3d/card_rounded.glb
"""

import sys
import os
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
    """Resets the scene to factory empty state."""
    bpy.ops.wm.read_factory_settings(use_empty=True)


def create_card_material(name: str, base_color: tuple, roughness: float = 0.4, metallic: float = 0.0) -> bpy.types.Material:
    """Creates a Principled BSDF material with specified color and roughness."""
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = base_color
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Metallic"].default_value = metallic
    return mat


def generate_card_mesh(
    output_path: str = "assets/3d/card_rounded.glb",
    width: float = 0.063,
    height: float = 0.088,
    thickness: float = 0.0003,
    corner_radius: float = 0.0035,
    corner_segments: int = 6
) -> str:
    """Procedurally generates a rounded playing card mesh and exports it to GLB."""
    clear_scene()

    mesh = bpy.data.meshes.new("CardMesh")
    obj = bpy.data.objects.new("CardMesh", mesh)
    bpy.context.collection.objects.link(obj)

    hw = width / 2.0
    hh = height / 2.0
    ht = thickness / 2.0
    r = corner_radius

    # 1. Generate 2D outline points for 4 rounded corners
    pts_2d = []
    corners = [
        (hw - r, hh - r, 0.0),                  # Top-Right: 0 to 90 deg
        (-hw + r, hh - r, math.pi / 2.0),       # Top-Left: 90 to 180 deg
        (-hw + r, -hh + r, math.pi),            # Bottom-Left: 180 to 270 deg
        (hw - r, -hh + r, 3.0 * math.pi / 2.0), # Bottom-Right: 270 to 360 deg
    ]
    for cx, cy, start_ang in corners:
        for i in range(corner_segments):
            ang = start_ang + i * (math.pi / 2.0) / corner_segments
            pts_2d.append((cx + r * math.cos(ang), cy + r * math.sin(ang)))

    # 2. Build 3D geometry in bmesh
    bm = bmesh.new()
    top_verts = [bm.verts.new(Vector((x, y, ht))) for x, y in pts_2d]
    bot_verts = [bm.verts.new(Vector((x, y, -ht))) for x, y in pts_2d]

    top_face = bm.faces.new(top_verts)
    bot_face = bm.faces.new(reversed(bot_verts))

    n = len(pts_2d)
    side_faces = []
    for i in range(n):
        next_i = (i + 1) % n
        sf = bm.faces.new([top_verts[i], bot_verts[i], bot_verts[next_i], top_verts[next_i]])
        side_faces.append(sf)

    # Triangulate top and bottom N-gons
    bmesh.ops.triangulate(bm, faces=[top_face, bot_face])

    # 3. Setup Material Slots
    mat_front = create_card_material("Mat_Front", (0.95, 0.95, 0.95, 1.0), roughness=0.35)
    mat_back = create_card_material("Mat_Back", (0.12, 0.22, 0.55, 1.0), roughness=0.35)
    mat_edge = create_card_material("Mat_Edge", (0.92, 0.90, 0.86, 1.0), roughness=0.6)

    obj.data.materials.append(mat_front) # Index 0
    obj.data.materials.append(mat_back)  # Index 1
    obj.data.materials.append(mat_edge)  # Index 2

    # 4. UV Unwrapping & Material Assignment
    uv_layer = bm.loops.layers.uv.new("UVMap")
    for f in bm.faces:
        if f.normal.z > 0.5:
            # Front face (+Z)
            f.material_index = 0
            for l in f.loops:
                u = (l.vert.co.x + hw) / width
                v = (l.vert.co.y + hh) / height
                l[uv_layer].uv = Vector((max(0.0, min(1.0, u)), max(0.0, min(1.0, v))))
        elif f.normal.z < -0.5:
            # Back face (-Z) - mirrored horizontally
            f.material_index = 1
            for l in f.loops:
                u = (hw - l.vert.co.x) / width
                v = (l.vert.co.y + hh) / height
                l[uv_layer].uv = Vector((max(0.0, min(1.0, u)), max(0.0, min(1.0, v))))
        else:
            # Edge face
            f.material_index = 2
            for l in f.loops:
                v = (l.vert.co.z + ht) / thickness
                l[uv_layer].uv = Vector((0.5, max(0.0, min(1.0, v))))

    bm.to_mesh(mesh)
    bm.free()

    # 5. Export to GLB
    target_path = Path(output_path).resolve()
    target_path.parent.mkdir(parents=True, exist_ok=True)

    bpy.ops.export_scene.gltf(
        filepath=str(target_path),
        export_format='GLB',
        export_apply=True
    )
    print(f"[SUCCESS] Card mesh exported to {target_path}")
    return str(target_path)


def main() -> int:
    if not BLENDER_AVAILABLE:
        print("[ERROR] bpy module is unavailable. Run with Blender --background.")
        return 1

    cli_args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description="Procedural Card Mesh Generator")
    parser.add_argument("--output", type=str, default="assets/3d/card_rounded.glb", help="Output .glb path")
    parser.add_argument("--width", type=float, default=0.063, help="Card width (m)")
    parser.add_argument("--height", type=float, default=0.088, help="Card height (m)")
    parser.add_argument("--thickness", type=float, default=0.0003, help="Card thickness (m)")
    parser.add_argument("--radius", type=float, default=0.0035, help="Corner radius (m)")
    parser.add_argument("--segments", type=int, default=6, help="Segments per corner")
    args = parser.parse_args(cli_args)

    generate_card_mesh(
        output_path=args.output,
        width=args.width,
        height=args.height,
        thickness=args.thickness,
        corner_radius=args.radius,
        corner_segments=args.segments
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
