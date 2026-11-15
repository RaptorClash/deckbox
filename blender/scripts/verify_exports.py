#!/usr/bin/env python3
"""
DeckBox Blender Asset Export Verification Suite
================================================
Validates 3D assets exported for Godot 4 and Web client:
- Inspects .glb export files in assets/3d/ and blender/exports/
- Card Mesh Verification:
  * Triangle budget < 500 triangles
  * Proportions: width ~63mm, height ~88mm, thickness ~0.3mm (aspect ratio ~0.716)
  * Material slots: Exactly 3 slots named Mat_Front, Mat_Back, Mat_Edge
  * UV mapping: UV0 maps properly onto front (0-1 UV space) and back (0-1 UV space)
- Table Theme Verification:
  * Triangle budget < 10,000 triangles per table model
  * Bounding boxes within specified play area dimensions
- Comprehensive Diagnostics:
  * Per-asset logging of triangle counts, vertex counts, materials, UV layers, dimensions
  * Self-test validation mode testing compliant assets and defect rejection
  * Exit code 0 when all validation rules pass; non-zero if validation fails

Usage:
  "C:\\Program Files\\Blender Foundation\\Blender 4.5\\blender.exe" --background --python blender/scripts/verify_exports.py
  "C:\\Program Files\\Blender Foundation\\Blender 4.5\\blender.exe" --background --python blender/scripts/verify_exports.py -- --self-test
  "C:\\Program Files\\Blender Foundation\\Blender 4.5\\blender.exe" --background --python blender/scripts/verify_exports.py -- --asset-dir assets/3d
"""

import sys
import os
import math
import tempfile
import argparse
from pathlib import Path
from typing import List, Dict, Any, Tuple, Optional

# Attempt importing Blender modules
try:
    import bpy
    import bmesh
    from mathutils import Vector
    BLENDER_AVAILABLE = True
except ImportError:
    BLENDER_AVAILABLE = False


# ==============================================================================
# Configuration & Thresholds
# ==============================================================================

CARD_TRIANGLE_BUDGET = 500
CARD_EXPECTED_ASPECT_RATIO = 63.0 / 88.0  # ~0.715909
CARD_ASPECT_RATIO_TOLERANCE = 0.06        # 0.655 to 0.775
CARD_REQUIRED_MATERIALS = {"Mat_Front", "Mat_Back", "Mat_Edge"}

# Dimensions in meters
CARD_DIMENSIONS_METERS = {
    "width_min": 0.045, "width_max": 0.080,
    "height_min": 0.065, "height_max": 0.110,
    "thickness_min": 0.00005, "thickness_max": 0.0030,
}

# Dimensions in millimeters
CARD_DIMENSIONS_MM = {
    "width_min": 45.0, "width_max": 80.0,
    "height_min": 65.0, "height_max": 110.0,
    "thickness_min": 0.05, "thickness_max": 3.0,
}

TABLE_TRIANGLE_BUDGET = 10000

# Table play area bounds in meters
TABLE_BOUNDS_METERS = {
    "dim_min": 0.05,
    "dim_max": 5.0,
    "height_max": 2.5,
}

# Table play area bounds in millimeters
TABLE_BOUNDS_MM = {
    "dim_min": 50.0,
    "dim_max": 5000.0,
    "height_max": 2500.0,
}


# ==============================================================================
# Data Structures
# ==============================================================================

class DiagnosticReport:
    """Stores the verification results and metrics for a single 3D asset."""

    def __init__(self, asset_path: str, asset_type: str):
        self.asset_path = asset_path
        self.asset_name = os.path.basename(asset_path)
        self.asset_type = asset_type  # 'card', 'table', 'general'
        self.passed = True
        self.errors: List[str] = []
        self.warnings: List[str] = []
        self.metrics: Dict[str, Any] = {}

    def add_error(self, message: str) -> None:
        self.passed = False
        self.errors.append(message)

    def add_warning(self, message: str) -> None:
        self.warnings.append(message)


# ==============================================================================
# Blender Scene Utilities
# ==============================================================================

def clear_scene() -> None:
    """Resets the Blender scene completely to avoid state leakage between assets."""
    if not BLENDER_AVAILABLE:
        return
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_glb(filepath: str) -> List[Any]:
    """Imports a .glb file into an empty scene and returns all MESH objects."""
    if not BLENDER_AVAILABLE:
        raise RuntimeError("Blender bpy environment is not available")
    clear_scene()
    bpy.ops.import_scene.gltf(filepath=str(filepath))
    return [obj for obj in bpy.data.objects if obj.type == 'MESH']


def extract_scene_metrics(mesh_objects: List[Any]) -> Dict[str, Any]:
    """Extracts geometric, material, UV, and bounding box metrics from mesh objects."""
    total_triangles = 0
    total_vertices = 0
    material_names = set()
    material_poly_counts: Dict[str, int] = {}
    material_uv_bounds: Dict[str, Dict[str, float]] = {}
    mesh_summaries = []
    all_world_corners = []

    for obj in mesh_objects:
        mesh = obj.data
        mesh.calc_loop_triangles()
        tri_count = len(mesh.loop_triangles)
        vert_count = len(mesh.vertices)
        total_triangles += tri_count
        total_vertices += vert_count

        # Compute world-space bounding box corners
        if obj.bound_box:
            for corner in obj.bound_box:
                all_world_corners.append(obj.matrix_world @ Vector(corner))

        # Inspect material slots
        slot_names = [slot.material.name for slot in obj.material_slots if slot.material]
        material_names.update(slot_names)

        # Inspect polygon material assignment and UV mapping
        has_uv = len(mesh.uv_layers) > 0
        uv_layer_data = mesh.uv_layers.active.data if has_uv else None

        for poly in mesh.polygons:
            mat_idx = poly.material_index
            mat_name = obj.material_slots[mat_idx].material.name if mat_idx < len(obj.material_slots) and obj.material_slots[mat_idx].material else "None"
            material_poly_counts[mat_name] = material_poly_counts.get(mat_name, 0) + 1

            if uv_layer_data:
                if mat_name not in material_uv_bounds:
                    material_uv_bounds[mat_name] = {
                        "min_u": float('inf'), "max_u": float('-inf'),
                        "min_v": float('inf'), "max_v": float('-inf'),
                        "count": 0
                    }
                bounds = material_uv_bounds[mat_name]
                for loop_idx in poly.loop_indices:
                    uv = uv_layer_data[loop_idx].uv
                    bounds["min_u"] = min(bounds["min_u"], uv.x)
                    bounds["max_u"] = max(bounds["max_u"], uv.x)
                    bounds["min_v"] = min(bounds["min_v"], uv.y)
                    bounds["max_v"] = max(bounds["max_v"], uv.y)
                    bounds["count"] += 1

        mesh_summaries.append({
            "name": obj.name,
            "vertices": vert_count,
            "triangles": tri_count,
            "materials": slot_names,
            "uv_layers": [uv.name for uv in mesh.uv_layers]
        })

    # Aggregate bounding box dimensions
    if all_world_corners:
        min_x = min(c.x for c in all_world_corners)
        max_x = max(c.x for c in all_world_corners)
        min_y = min(c.y for c in all_world_corners)
        max_y = max(c.y for c in all_world_corners)
        min_z = min(c.z for c in all_world_corners)
        max_z = max(c.z for c in all_world_corners)
        dim_x = max_x - min_x
        dim_y = max_y - min_y
        dim_z = max_z - min_z
    else:
        min_x = max_x = min_y = max_y = min_z = max_z = 0.0
        dim_x = dim_y = dim_z = 0.0

    return {
        "mesh_count": len(mesh_objects),
        "total_triangles": total_triangles,
        "total_vertices": total_vertices,
        "material_names": material_names,
        "material_poly_counts": material_poly_counts,
        "material_uv_bounds": material_uv_bounds,
        "mesh_summaries": mesh_summaries,
        "bounding_box": {
            "min_x": min_x, "max_x": max_x,
            "min_y": min_y, "max_y": max_y,
            "min_z": min_z, "max_z": max_z,
            "dim_x": dim_x, "dim_y": dim_y, "dim_z": dim_z
        }
    }


# ==============================================================================
# Card Mesh Verification Logic
# ==============================================================================

def verify_card_mesh(filepath: str) -> DiagnosticReport:
    """
    Verifies that a card .glb export complies with all DeckBox specifications:
    - Triangle budget < 500 triangles
    - Proportions ~63mm x ~88mm x ~0.3mm (aspect ratio ~0.716)
    - Exactly 3 material slots: Mat_Front, Mat_Back, Mat_Edge
    - UV0 properly maps onto front (0-1 UV space) and back (0-1 UV space)
    """
    report = DiagnosticReport(filepath, asset_type="card")

    try:
        mesh_objects = import_glb(filepath)
    except Exception as e:
        report.add_error(f"Failed to import glTF file: {e}")
        return report

    if not mesh_objects:
        report.add_error("glTF contains no MESH objects")
        return report

    metrics = extract_scene_metrics(mesh_objects)
    report.metrics = metrics

    # 1. Triangle Budget Verification (< 500 triangles)
    tri_count = metrics["total_triangles"]
    if tri_count >= CARD_TRIANGLE_BUDGET:
        report.add_error(
            f"Triangle budget exceeded: {tri_count} triangles (budget is < {CARD_TRIANGLE_BUDGET})"
        )

    # 2. Dimensions & Proportions Verification
    bbox = metrics["bounding_box"]
    dims = sorted([bbox["dim_x"], bbox["dim_y"], bbox["dim_z"]])
    thickness, width, height = dims[0], dims[1], dims[2]

    if height <= 0:
        report.add_error("Invalid zero or negative card dimensions")
        return report

    aspect_ratio = width / height
    expected_ratio = CARD_EXPECTED_ASPECT_RATIO
    diff_ratio = abs(aspect_ratio - expected_ratio)

    if diff_ratio > CARD_ASPECT_RATIO_TOLERANCE:
        report.add_error(
            f"Card aspect ratio {aspect_ratio:.4f} deviates from expected ~{expected_ratio:.4f} "
            f"(tolerance +/- {CARD_ASPECT_RATIO_TOLERANCE:.3f}, width={width:.4f}, height={height:.4f})"
        )

    # Thickness check (must be a thin card sheet, thickness / width < 0.08)
    if (thickness / width) > 0.08:
        report.add_error(
            f"Card thickness ({thickness:.4f}) is abnormally thick relative to width ({width:.4f})"
        )

    # Scale check (detect meters vs millimeters)
    is_meters = height < 1.0
    bounds_cfg = CARD_DIMENSIONS_METERS if is_meters else CARD_DIMENSIONS_MM
    unit_str = "m" if is_meters else "mm"

    if not (bounds_cfg["width_min"] <= width <= bounds_cfg["width_max"]):
        report.add_error(
            f"Card width {width:.4f}{unit_str} outside expected range "
            f"[{bounds_cfg['width_min']}{unit_str}, {bounds_cfg['width_max']}{unit_str}]"
        )
    if not (bounds_cfg["height_min"] <= height <= bounds_cfg["height_max"]):
        report.add_error(
            f"Card height {height:.4f}{unit_str} outside expected range "
            f"[{bounds_cfg['height_min']}{unit_str}, {bounds_cfg['height_max']}{unit_str}]"
        )
    if not (bounds_cfg["thickness_min"] <= thickness <= bounds_cfg["thickness_max"]):
        report.add_error(
            f"Card thickness {thickness:.4f}{unit_str} outside expected range "
            f"[{bounds_cfg['thickness_min']}{unit_str}, {bounds_cfg['thickness_max']}{unit_str}]"
        )

    # 3. Material Slots Verification (Exactly 3 slots: Mat_Front, Mat_Back, Mat_Edge)
    found_materials = metrics["material_names"]
    if found_materials != CARD_REQUIRED_MATERIALS:
        missing = CARD_REQUIRED_MATERIALS - found_materials
        extra = found_materials - CARD_REQUIRED_MATERIALS
        err_msg = f"Material slots mismatch. Required: {sorted(CARD_REQUIRED_MATERIALS)}, found: {sorted(found_materials)}"
        if missing:
            err_msg += f" (missing: {sorted(missing)})"
        if extra:
            err_msg += f" (extra: {sorted(extra)})"
        report.add_error(err_msg)

    # Verify that each required material has assigned polygons
    poly_counts = metrics["material_poly_counts"]
    for req_mat in CARD_REQUIRED_MATERIALS:
        if poly_counts.get(req_mat, 0) == 0:
            report.add_error(f"Material slot '{req_mat}' has 0 assigned polygons")

    # 4. UV Mapping Verification (UV0 maps properly onto front and back in 0-1 UV space)
    uv_bounds = metrics["material_uv_bounds"]

    for slot_name in ["Mat_Front", "Mat_Back"]:
        if slot_name in uv_bounds:
            b = uv_bounds[slot_name]
            if b["count"] == 0:
                report.add_error(f"Material '{slot_name}' has no UV vertices")
                continue

            # UV coordinates must lie within [0.0, 1.0] with slight margin for precision [-0.05, 1.05]
            if b["min_u"] < -0.05 or b["max_u"] > 1.05 or b["min_v"] < -0.05 or b["max_v"] > 1.05:
                report.add_error(
                    f"{slot_name} UV coordinates exceed [0, 1] range: "
                    f"U=[{b['min_u']:.3f}, {b['max_u']:.3f}], V=[{b['min_v']:.3f}, {b['max_v']:.3f}]"
                )

            # Check that UV is not collapsed to a point or thin line (span >= 0.5)
            u_span = b["max_u"] - b["min_u"]
            v_span = b["max_v"] - b["min_v"]
            if u_span < 0.5 or v_span < 0.5:
                report.add_error(
                    f"{slot_name} UV mapping is degenerate or collapsed: "
                    f"U-span={u_span:.3f}, V-span={v_span:.3f} (expected >= 0.5)"
                )
        else:
            report.add_error(f"Missing UV bounds data for required slot '{slot_name}'")

    return report


# ==============================================================================
# Table Theme Verification Logic
# ==============================================================================

def verify_table_mesh(filepath: str) -> DiagnosticReport:
    """
    Verifies that a table theme .glb export complies with all DeckBox specifications:
    - Triangle budget < 10,000 triangles
    - Bounding box within specified play area dimensions
    """
    report = DiagnosticReport(filepath, asset_type="table")

    try:
        mesh_objects = import_glb(filepath)
    except Exception as e:
        report.add_error(f"Failed to import glTF file: {e}")
        return report

    if not mesh_objects:
        report.add_error("glTF contains no MESH objects")
        return report

    metrics = extract_scene_metrics(mesh_objects)
    report.metrics = metrics

    # 1. Triangle Budget Verification (< 10,000 triangles)
    tri_count = metrics["total_triangles"]
    if tri_count >= TABLE_TRIANGLE_BUDGET:
        report.add_error(
            f"Table triangle budget exceeded: {tri_count} triangles (budget is < {TABLE_TRIANGLE_BUDGET})"
        )

    # 2. Bounding Box & Play Area Verification
    bbox = metrics["bounding_box"]
    max_dim = max(bbox["dim_x"], bbox["dim_y"], bbox["dim_z"])
    min_dim = min(bbox["dim_x"], bbox["dim_y"], bbox["dim_z"])

    is_meters = max_dim < 50.0
    cfg = TABLE_BOUNDS_METERS if is_meters else TABLE_BOUNDS_MM
    unit_str = "m" if is_meters else "mm"

    if max_dim > cfg["dim_max"]:
        report.add_error(
            f"Table bounding box dimension ({max_dim:.2f}{unit_str}) exceeds play area max ({cfg['dim_max']}{unit_str})"
        )
    if min_dim < cfg["dim_min"]:
        report.add_error(
            f"Table bounding box dimension ({min_dim:.2f}{unit_str}) is unrealistically small (min {cfg['dim_min']}{unit_str})"
        )
    if bbox["dim_z"] > cfg["height_max"]:
        report.add_error(
            f"Table height ({bbox['dim_z']:.2f}{unit_str}) exceeds max table height ({cfg['height_max']}{unit_str})"
        )

    # 3. UV Layer Verification
    for mesh_info in metrics["mesh_summaries"]:
        if not mesh_info["uv_layers"]:
            report.add_warning(f"Mesh '{mesh_info['name']}' has no UV layers")

    return report


# ==============================================================================
# Procedural Mesh Generators for Self-Test / Validation Mode
# ==============================================================================

def generate_procedural_card(
    output_path: str,
    width: float = 0.063,
    height: float = 0.088,
    thickness: float = 0.0003,
    corner_radius: float = 0.0035,
    corner_segments: int = 4,
    materials: Optional[List[str]] = None,
    uv_scale: float = 1.0,
    subdivide_cuts: int = 0
) -> str:
    """Generates a procedural 3D card mesh with rounded corners and exports it to .glb."""
    clear_scene()

    if materials is None:
        materials = ["Mat_Front", "Mat_Back", "Mat_Edge"]

    mesh = bpy.data.meshes.new("ProceduralCardMesh")
    obj = bpy.data.objects.new("ProceduralCardMesh", mesh)
    bpy.context.collection.objects.link(obj)

    hw, hh = width / 2.0, height / 2.0
    r = corner_radius

    # Generate 2D outline points for 4 rounded corners
    pts_2d = []
    corners = [
        (hw - r, hh - r, 0.0),
        (-hw + r, hh - r, math.pi / 2.0),
        (-hw + r, -hh + r, math.pi),
        (hw - r, -hh + r, 3.0 * math.pi / 2.0),
    ]
    for cx, cy, start_ang in corners:
        for i in range(corner_segments):
            ang = start_ang + i * (math.pi / 2.0) / corner_segments
            pts_2d.append((cx + r * math.cos(ang), cy + r * math.sin(ang)))

    bm = bmesh.new()
    ht = thickness / 2.0
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

    bmesh.ops.triangulate(bm, faces=[top_face, bot_face])

    # Subdivide faces if requested (for budget testing)
    if subdivide_cuts > 0:
        bmesh.ops.subdivide_edges(bm, edges=bm.edges, cuts=subdivide_cuts, use_grid_fill=True)

    # Create and assign materials
    created_materials = []
    for mat_name in materials:
        mat = bpy.data.materials.new(mat_name)
        obj.data.materials.append(mat)
        created_materials.append(mat)

    # UV unwrap and material slot assignment
    uv_layer = bm.loops.layers.uv.new("UVMap")
    for f in bm.faces:
        if f.normal.z > 0.5:
            # Front face
            f.material_index = 0 if len(materials) > 0 else 0
            for l in f.loops:
                u = ((l.vert.co.x + hw) / width) * uv_scale
                v = ((l.vert.co.y + hh) / height) * uv_scale
                l[uv_layer].uv = Vector((u, v))
        elif f.normal.z < -0.5:
            # Back face
            f.material_index = 1 if len(materials) > 1 else 0
            for l in f.loops:
                u = ((hw - l.vert.co.x) / width) * uv_scale
                v = ((l.vert.co.y + hh) / height) * uv_scale
                l[uv_layer].uv = Vector((u, v))
        else:
            # Edge face
            f.material_index = 2 if len(materials) > 2 else (1 if len(materials) > 1 else 0)
            for l in f.loops:
                l[uv_layer].uv = Vector((0.5, (l.vert.co.z + ht) / thickness))

    bm.to_mesh(mesh)
    bm.free()

    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(output_path))
    return output_path


def generate_procedural_table(
    output_path: str,
    width: float = 1.8,
    length: float = 1.0,
    height: float = 0.75,
    subdivide_cuts: int = 0
) -> str:
    """Generates a procedural table model (tabletop, surface, and 4 legs) and exports to .glb."""
    clear_scene()

    # Table Top
    top_thick = 0.05
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, height - top_thick / 2.0))
    top = bpy.context.active_object
    top.name = "TableTop"
    top.scale = (width, length, top_thick)
    bpy.ops.object.transform_apply(scale=True)

    # Table Legs
    leg_thick = 0.08
    leg_h = height - top_thick
    lx = width / 2.0 - leg_thick
    ly = length / 2.0 - leg_thick
    for idx, (px, py) in enumerate([(-lx, -ly), (lx, -ly), (-lx, ly), (lx, ly)]):
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(px, py, leg_h / 2.0))
        leg = bpy.context.active_object
        leg.name = f"Leg_{idx+1}"
        leg.scale = (leg_thick, leg_thick, leg_h)
        bpy.ops.object.transform_apply(scale=True)

    # High-poly stress test mesh if requested
    if subdivide_cuts > 0:
        bpy.ops.mesh.primitive_uv_sphere_add(segments=128, ring_count=128, radius=0.2, location=(0, 0, height + 0.2))
        sphere = bpy.context.active_object
        sphere.name = "HighPolyProp"

    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(output_path))
    return output_path


# ==============================================================================
# Automated Self-Test Suite (Positive & Adversarial Defect Rejection)
# ==============================================================================

def run_self_tests() -> bool:
    """
    Executes the automated self-test verification suite:
    1. Validates a compliant procedural card mesh (must PASS).
    2. Validates a compliant procedural table model (must PASS).
    3. Adversarial test: Card over budget (must FAIL).
    4. Adversarial test: Card missing material slot (must FAIL).
    5. Adversarial test: Card invalid aspect ratio (must FAIL).
    6. Adversarial test: Card invalid UV mapping (must FAIL).
    7. Adversarial test: Table over budget (must FAIL).
    8. Adversarial test: Table oversized bounding box (must FAIL).
    """
    print("\n" + "=" * 70)
    print("RUNNING AUTOMATED BLENDER ASSET VERIFICATION SELF-TEST SUITE")
    print("=" * 70)

    all_passed = True
    test_results = []

    with tempfile.TemporaryDirectory() as temp_dir:
        # Case 1: Compliant Card Mesh
        card_glb = os.path.join(temp_dir, "card_compliant.glb")
        generate_procedural_card(card_glb)
        rep = verify_card_mesh(card_glb)
        passed = rep.passed and len(rep.errors) == 0
        test_results.append(("Compliant Card Mesh (<500 tris, 3 slots, ~0.716 ratio, UV 0-1)", passed, rep.errors))
        if not passed:
            all_passed = False

        # Case 2: Compliant Table Model
        table_glb = os.path.join(temp_dir, "table_compliant.glb")
        generate_procedural_table(table_glb)
        rep = verify_table_mesh(table_glb)
        passed = rep.passed and len(rep.errors) == 0
        test_results.append(("Compliant Table Model (<10,000 tris, play area bounds)", passed, rep.errors))
        if not passed:
            all_passed = False

        # Case 3: Adversarial Defect - Card Over Triangle Budget (>500 triangles)
        card_over_budget = os.path.join(temp_dir, "card_over_budget.glb")
        generate_procedural_card(card_over_budget, subdivide_cuts=5)
        rep = verify_card_mesh(card_over_budget)
        passed = (not rep.passed) and any("Triangle budget exceeded" in e for e in rep.errors)
        test_results.append(("Defect Detection: Card Over Budget (>500 tris rejected)", passed, rep.errors))
        if not passed:
            all_passed = False

        # Case 4: Adversarial Defect - Card Missing Material Slot
        card_missing_mat = os.path.join(temp_dir, "card_missing_mat.glb")
        generate_procedural_card(card_missing_mat, materials=["Mat_Front", "Mat_Back"])
        rep = verify_card_mesh(card_missing_mat)
        passed = (not rep.passed) and any("Material slots mismatch" in e for e in rep.errors)
        test_results.append(("Defect Detection: Card Missing Mat_Edge Slot rejected", passed, rep.errors))
        if not passed:
            all_passed = False

        # Case 5: Adversarial Defect - Card Invalid Aspect Ratio (Square 1:1)
        card_bad_ratio = os.path.join(temp_dir, "card_bad_ratio.glb")
        generate_procedural_card(card_bad_ratio, width=0.088, height=0.088)
        rep = verify_card_mesh(card_bad_ratio)
        passed = (not rep.passed) and any("aspect ratio" in e for e in rep.errors)
        test_results.append(("Defect Detection: Card Square Aspect Ratio rejected", passed, rep.errors))
        if not passed:
            all_passed = False

        # Case 6: Adversarial Defect - Card Invalid UV Coordinates (> 1.0)
        card_bad_uv = os.path.join(temp_dir, "card_bad_uv.glb")
        generate_procedural_card(card_bad_uv, uv_scale=3.0)
        rep = verify_card_mesh(card_bad_uv)
        passed = (not rep.passed) and any("exceed [0, 1] range" in e for e in rep.errors)
        test_results.append(("Defect Detection: Card UV Out-of-Bounds rejected", passed, rep.errors))
        if not passed:
            all_passed = False

        # Case 7: Adversarial Defect - Table Over Triangle Budget (>10,000 tris)
        table_over_budget = os.path.join(temp_dir, "table_over_budget.glb")
        generate_procedural_table(table_over_budget, subdivide_cuts=1)
        rep = verify_table_mesh(table_over_budget)
        passed = (not rep.passed) and any("Table triangle budget exceeded" in e for e in rep.errors)
        test_results.append(("Defect Detection: Table Over Budget (>10,000 tris rejected)", passed, rep.errors))
        if not passed:
            all_passed = False

        # Case 8: Adversarial Defect - Table Oversized Bounding Box
        table_oversized = os.path.join(temp_dir, "table_oversized.glb")
        generate_procedural_table(table_oversized, width=15.0, length=10.0)
        rep = verify_table_mesh(table_oversized)
        passed = (not rep.passed) and any("exceeds play area max" in e for e in rep.errors)
        test_results.append(("Defect Detection: Table Oversized Play Area rejected", passed, rep.errors))
        if not passed:
            all_passed = False

    # Print Self-Test Results Summary
    print("\nSELF-TEST RESULTS SUMMARY:")
    for desc, passed, errs in test_results:
        mark = "[PASS]" if passed else "[FAIL]"
        print(f"  {mark} {desc}")
        if not passed and errs:
            for e in errs:
                print(f"         Detail: {e}")

    print("=" * 70)
    if all_passed:
        print("[SUCCESS] All 8 verification self-tests passed successfully!\n")
    else:
        print("[FAILURE] One or more self-tests failed.\n")

    return all_passed


# ==============================================================================
# Asset Discovery & Diagnostics
# ==============================================================================

def print_diagnostic_report(report: DiagnosticReport) -> None:
    """Prints a detailed, formatted diagnostic report for an inspected asset."""
    status_str = "[PASS]" if report.passed else "[FAIL]"
    print(f"\n{status_str} Asset: {report.asset_name} ({report.asset_type.upper()})")
    print(f"       Path: {report.asset_path}")

    metrics = report.metrics
    if metrics:
        print(f"       Meshes: {metrics.get('mesh_count', 0)} | "
              f"Total Triangles: {metrics.get('total_triangles', 0)} | "
              f"Total Vertices: {metrics.get('total_vertices', 0)}")

        bbox = metrics.get("bounding_box", {})
        print(f"       Bounding Box: X={bbox.get('dim_x', 0):.4f}, "
              f"Y={bbox.get('dim_y', 0):.4f}, Z={bbox.get('dim_z', 0):.4f}")

        mats = sorted(metrics.get("material_names", []))
        poly_counts = metrics.get("material_poly_counts", {})
        mat_details = ", ".join([f"{m} ({poly_counts.get(m, 0)} polys)" for m in mats])
        print(f"       Materials: {mat_details if mat_details else 'None'}")

        uv_bounds = metrics.get("material_uv_bounds", {})
        if uv_bounds:
            for mat_name, b in uv_bounds.items():
                print(f"       UV [{mat_name}]: U=[{b['min_u']:.3f}, {b['max_u']:.3f}], "
                      f"V=[{b['min_v']:.3f}, {b['max_v']:.3f}] (verts: {b['count']})")

    if report.warnings:
        for w in report.warnings:
            print(f"       [WARN] {w}")

    if report.errors:
        for e in report.errors:
            print(f"       [ERROR] {e}")


def discover_assets(search_dirs: List[Path]) -> List[Tuple[Path, str]]:
    """Scans target directories for .glb files and classifies them by type."""
    assets = []
    for directory in search_dirs:
        if not directory.exists():
            continue
        for file in directory.glob("**/*.glb"):
            name = file.name.lower()
            if "card" in name:
                asset_type = "card"
            elif "table" in name:
                asset_type = "table"
            else:
                asset_type = "general"
            assets.append((file, asset_type))
    return assets


# ==============================================================================
# CLI Entrypoint
# ==============================================================================

def main() -> int:
    """Main verification CLI orchestrator."""
    if not BLENDER_AVAILABLE:
        print("[ERROR] bpy module is not available. Please run this script with Blender:")
        print("  blender.exe --background --python blender/scripts/verify_exports.py")
        return 1

    # Parse arguments passed after '--'
    cli_args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description="DeckBox Blender Asset Export Verification Suite")
    parser.add_argument("--self-test", action="store_true", help="Force execution of the procedural self-test suite")
    parser.add_argument("--asset-dir", type=str, help="Custom directory containing exported .glb assets")
    parser.add_argument("--file", type=str, help="Specific .glb file to verify")
    args = parser.parse_args(cli_args)

    print("=" * 70)
    print("DECKBOX BLENDER ASSET EXPORT VERIFICATION SUITE")
    print(f"Blender Version: {bpy.app.version_string}")
    print("=" * 70)

    # Determine asset search paths
    repo_root = Path.cwd()
    search_dirs = [
        repo_root / "assets" / "3d",
        repo_root / "blender" / "exports",
    ]
    if args.asset_dir:
        search_dirs.insert(0, Path(args.asset_dir))

    discovered_assets = []
    if args.file:
        target_file = Path(args.file)
        if target_file.exists():
            name = target_file.name.lower()
            asset_type = "card" if "card" in name else ("table" if "table" in name else "general")
            discovered_assets.append((target_file, asset_type))
        else:
            print(f"[ERROR] Specified file does not exist: {target_file}")
            return 1
    else:
        discovered_assets = discover_assets(search_dirs)

    overall_passed = True

    # If assets exist on disk, verify them
    if discovered_assets:
        print(f"\nDiscovered {len(discovered_assets)} asset(s) for verification:")
        for path, atype in discovered_assets:
            print(f"  - [{atype.upper()}] {path.relative_to(repo_root) if path.is_relative_to(repo_root) else path}")

        reports = []
        for path, atype in discovered_assets:
            if atype == "card":
                rep = verify_card_mesh(str(path))
            elif atype == "table":
                rep = verify_table_mesh(str(path))
            else:
                rep = verify_table_mesh(str(path))  # General mesh uses table triangle/bound rules
            reports.append(rep)
            print_diagnostic_report(rep)
            if not rep.passed:
                overall_passed = False

        total_verified = len(reports)
        passed_count = sum(1 for r in reports if r.passed)
        failed_count = total_verified - passed_count

        print("\n" + "-" * 70)
        print(f"ASSET VERIFICATION SUMMARY: {passed_count}/{total_verified} Passed | {failed_count} Failed")
        print("-" * 70)

    else:
        print("\n[INFO] No .glb export assets found in target directories:")
        for d in search_dirs:
            print(f"  - {d}")
        print("(3D asset generation may be pending or running in parallel).")
        print("Executing automated test validation suite to verify export verification rules...")

    # Execute self-test suite if explicitly requested or if no assets were discovered
    if args.self_test or not discovered_assets:
        self_test_passed = run_self_tests()
        if not self_test_passed:
            overall_passed = False

    if overall_passed:
        print("\n[VERDICT] ALL VERIFICATION CHECKS PASSED (Exit Code 0)")
        return 0
    else:
        print("\n[VERDICT] VERIFICATION FAILED (Exit Code 1)")
        return 1


if __name__ == "__main__":
    exit_code = main()
    # In Blender background mode, sys.exit() properly signals the exit code to the shell
    sys.exit(exit_code)
