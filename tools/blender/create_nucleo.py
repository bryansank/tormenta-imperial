"""
Blender Script: Núcleo — Tormenta Imperial
============================================
Imposing Dieselpunk Government HQ / Command Center
Style: Empires & Allies meets Dieselpunk — colorful, chunky, authoritative

Features:
- Grand central building with dome
- Columned entrance portico
- Clock tower
- Flag pole
- Industrial smokestacks
- Warm vibrant palette
"""

import bpy
import bmesh
import math
import os

EXPORT_PATH = "c:/Users/bkey/Documents/PERSONAL/apss/empires/assets/models/buildings/nucleo/nucleo.glb"

# ─── PALETTE — Warm, vibrant, authoritative ─────────────────────────────────
WALL = {"base_color": (0.78, 0.72, 0.58, 1.0), "metallic": 0.05, "roughness": 0.75}
WALL_DARK = {"base_color": (0.55, 0.48, 0.38, 1.0), "metallic": 0.1, "roughness": 0.7}
ROOF = {"base_color": (0.58, 0.15, 0.12, 1.0), "metallic": 0.15, "roughness": 0.55}
TRIM = {"base_color": (0.75, 0.55, 0.18, 1.0), "metallic": 0.85, "roughness": 0.35}
STEEL = {"base_color": (0.40, 0.42, 0.45, 1.0), "metallic": 0.75, "roughness": 0.5}
CONCRETE = {"base_color": (0.62, 0.58, 0.52, 1.0), "metallic": 0.0, "roughness": 0.9}
WINDOW = {"base_color": (0.95, 0.78, 0.25, 1.0), "metallic": 0.0, "roughness": 1.0,
          "emission": (0.95, 0.78, 0.25, 1.0), "emission_strength": 0.8, "specular": 0.0}
DOOR = {"base_color": (0.35, 0.22, 0.10, 1.0), "metallic": 0.0, "roughness": 0.85}
DOME = {"base_color": (0.28, 0.45, 0.35, 1.0), "metallic": 0.6, "roughness": 0.4}
FLAG_RED = {"base_color": (0.85, 0.15, 0.10, 1.0), "metallic": 0.0, "roughness": 0.7}


def clean_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for m in list(bpy.data.materials): bpy.data.materials.remove(m)
    for m in list(bpy.data.meshes): bpy.data.meshes.remove(m)


def mat(name, props):
    m = bpy.data.materials.new(name=name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = props["base_color"]
    b.inputs["Metallic"].default_value = props["metallic"]
    b.inputs["Roughness"].default_value = props["roughness"]
    if "specular" in props:
        b.inputs["Specular IOR Level"].default_value = props["specular"]
    if "emission" in props:
        b.inputs["Emission Color"].default_value = props["emission"]
        b.inputs["Emission Strength"].default_value = props["emission_strength"]
    return m


def box(name, loc, size, material):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    o.data.materials.append(material)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return o


def cyl(name, loc, r, h, material, seg=12):
    bpy.ops.mesh.primitive_cylinder_add(vertices=seg, radius=r, depth=h, location=loc)
    o = bpy.context.active_object
    o.name = name
    o.data.materials.append(material)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return o


def cone(name, loc, r1, r2, h, material, seg=12):
    bpy.ops.mesh.primitive_cone_add(vertices=seg, radius1=r1, radius2=r2, depth=h, location=loc)
    o = bpy.context.active_object
    o.name = name
    o.data.materials.append(material)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return o


def sphere(name, loc, r, material, seg=12, rings=8):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=rings, radius=r, location=loc)
    o = bpy.context.active_object
    o.name = name
    o.data.materials.append(material)
    return o


def build_nucleo():
    clean_scene()

    M_wall = mat("Wall", WALL)
    M_wall_dk = mat("WallDark", WALL_DARK)
    M_roof = mat("Roof", ROOF)
    M_trim = mat("Trim", TRIM)
    M_steel = mat("Steel", STEEL)
    M_conc = mat("Concrete", CONCRETE)
    M_win = mat("Window", WINDOW)
    M_door = mat("Door", DOOR)
    M_dome = mat("Dome", DOME)
    M_flag = mat("Flag", FLAG_RED)

    objs = []

    # ═══════════════════════════════════════════════════════════════
    # FOUNDATION — Wide concrete base, 2 steps
    # ═══════════════════════════════════════════════════════════════
    objs.append(box("Found1", (0, 0, 0.1), (5.4, 5.4, 0.2), M_conc))
    objs.append(box("Found2", (0, 0, 0.25), (5.2, 5.2, 0.1), M_conc))

    # ═══════════════════════════════════════════════════════════════
    # MAIN BUILDING — L-shape base: central + two wings
    # ═══════════════════════════════════════════════════════════════
    # Central block (tallest)
    objs.append(box("Central", (0, 0, 1.65), (3.6, 3.8, 2.7), M_wall))
    # Left wing
    objs.append(box("WingL", (-2.0, 0, 1.3), (1.6, 3.4, 2.0), M_wall))
    # Right wing
    objs.append(box("WingR", (2.0, 0, 1.3), (1.6, 3.4, 2.0), M_wall))

    # Wall base band (darker)
    objs.append(box("BaseBand", (0, 0, 0.5), (5.0, 5.0, 0.3), M_wall_dk))

    # ═══════════════════════════════════════════════════════════════
    # TRIM — Horizontal gold bands
    # ═══════════════════════════════════════════════════════════════
    for h in [0.7, 2.3]:
        objs.append(box(f"TrimH_{h}", (0, 0, h), (5.05, 5.05, 0.08), M_trim))

    # Crown molding at top of central
    objs.append(box("Crown", (0, 0, 3.05), (3.8, 4.0, 0.12), M_trim))
    # Crown on wings
    objs.append(box("CrownL", (-2.0, 0, 2.35), (1.7, 3.5, 0.1), M_trim))
    objs.append(box("CrownR", (2.0, 0, 2.35), (1.7, 3.5, 0.1), M_trim))

    # ═══════════════════════════════════════════════════════════════
    # ROOF — Red roofs on wings, flat on central
    # ═══════════════════════════════════════════════════════════════
    objs.append(box("RoofC", (0, 0, 3.15), (3.7, 3.9, 0.15), M_roof))
    objs.append(box("RoofL", (-2.0, 0, 2.45), (1.65, 3.45, 0.12), M_roof))
    objs.append(box("RoofR", (2.0, 0, 2.45), (1.65, 3.45, 0.12), M_roof))

    # Pitched roof caps on wings (triangular prism approximation)
    for wx in [-2.0, 2.0]:
        objs.append(box(f"RoofPeak_{wx}", (wx, 0, 2.6), (1.2, 3.2, 0.15), M_roof))

    # ═══════════════════════════════════════════════════════════════
    # DOME — Central dome on top of main building
    # ═══════════════════════════════════════════════════════════════
    objs.append(cyl("DomeBase", (0, 0, 3.35), 1.0, 0.2, M_conc, 16))
    # Dome hemisphere (scaled sphere)
    dome = sphere("Dome", (0, 0, 3.65), 0.9, M_dome, 16, 8)
    dome.scale = (1, 1, 0.6)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    objs.append(dome)
    # Dome tip (gold finial)
    objs.append(sphere("DomeTip", (0, 0, 4.1), 0.15, M_trim, 8, 6))
    # Dome spire
    objs.append(cyl("DomeSpire", (0, 0, 4.35), 0.04, 0.4, M_trim, 4))

    # ═══════════════════════════════════════════════════════════════
    # ENTRANCE PORTICO — Front colonnade, grand entrance
    # ═══════════════════════════════════════════════════════════════
    # Portico roof
    objs.append(box("PorticoRoof", (0, -2.3, 2.15), (2.8, 0.8, 0.15), M_roof))
    objs.append(box("PorticoTrim", (0, -2.3, 2.05), (2.9, 0.85, 0.08), M_trim))

    # Columns (4 columns)
    col_positions = [-1.1, -0.37, 0.37, 1.1]
    for cx in col_positions:
        objs.append(cyl(f"Col_{cx}", (cx, -2.3, 1.15), 0.12, 1.8, M_conc, 8))
        # Column cap
        objs.append(box(f"ColCap_{cx}", (cx, -2.3, 2.05), (0.3, 0.3, 0.08), M_trim))
        # Column base
        objs.append(box(f"ColBase_{cx}", (cx, -2.3, 0.3), (0.3, 0.3, 0.06), M_conc))

    # Steps
    for s in range(3):
        objs.append(box(f"Step_{s}", (0, -2.5 - s * 0.2, 0.3 - s * 0.1),
                        (2.6 + s * 0.2, 0.2, 0.1), M_conc))

    # Door (grand double door)
    objs.append(box("Door", (0, -1.95, 1.0), (1.0, 0.1, 1.5), M_door))
    # Door arch
    objs.append(box("DoorArch", (0, -1.95, 1.8), (1.2, 0.12, 0.15), M_trim))
    # Door light
    objs.append(box("DoorLight", (0, -1.97, 1.3), (0.6, 0.04, 0.8), M_win))

    # ═══════════════════════════════════════════════════════════════
    # WINDOWS — Amber glow, NO reflection/metallic (just emission)
    # ═══════════════════════════════════════════════════════════════
    win_configs = [
        # Front face (above portico, central)
        (-1.2, -1.92, 2.2, 0.5, 0.04, 0.4),
        (1.2, -1.92, 2.2, 0.5, 0.04, 0.4),
        # Front wings
        (-2.0, -1.72, 1.5, 0.5, 0.04, 0.5),
        (2.0, -1.72, 1.5, 0.5, 0.04, 0.5),
        # Left side
        (-2.82, -0.8, 1.5, 0.04, 0.5, 0.5),
        (-2.82, 0.8, 1.5, 0.04, 0.5, 0.5),
        # Right side
        (2.82, -0.8, 1.5, 0.04, 0.5, 0.5),
        (2.82, 0.8, 1.5, 0.04, 0.5, 0.5),
        # Back
        (-1.0, 1.92, 1.5, 0.5, 0.04, 0.5),
        (1.0, 1.92, 1.5, 0.5, 0.04, 0.5),
        (-1.0, 1.92, 2.4, 0.4, 0.04, 0.3),
        (1.0, 1.92, 2.4, 0.4, 0.04, 0.3),
        # Central upper windows
        (-0.6, -1.92, 2.7, 0.3, 0.04, 0.25),
        (0.6, -1.92, 2.7, 0.3, 0.04, 0.25),
    ]
    for i, (wx, wy, wz, sx, sy, sz) in enumerate(win_configs):
        objs.append(box(f"Win_{i}", (wx, wy, wz), (sx, sy, sz), M_win))
        # Window frame
        is_front = abs(sy) < 0.1
        objs.append(box(f"WF_{i}", (wx, wy, wz),
                        (sx + 0.08 if is_front else sx,
                         sy + 0.08 if not is_front else sy,
                         sz + 0.06), M_trim))

    # ═══════════════════════════════════════════════════════════════
    # CLOCK TOWER — Left rear, imposing
    # ═══════════════════════════════════════════════════════════════
    objs.append(box("Tower1", (-1.8, 1.3, 3.0), (1.0, 1.0, 2.5), M_wall_dk))
    objs.append(box("TowerTrim", (-1.8, 1.3, 4.3), (1.1, 1.1, 0.1), M_trim))
    objs.append(box("TowerRoof", (-1.8, 1.3, 4.55), (0.9, 0.9, 0.35), M_roof))
    objs.append(cone("TowerSpire", (-1.8, 1.3, 4.95), 0.45, 0.05, 0.5, M_roof, 8))
    # Clock face (amber)
    for dx, dy in [(0, -0.52), (0, 0.52), (-0.52, 0), (0.52, 0)]:
        is_x = abs(dx) > 0.1
        objs.append(box("ClockFace",
                        (-1.8 + dx, 1.3 + dy, 4.0),
                        (0.04 if is_x else 0.3, 0.3 if is_x else 0.04, 0.3),
                        M_win))

    # ═══════════════════════════════════════════════════════════════
    # SMOKESTACKS — Industrial character (right rear)
    # ═══════════════════════════════════════════════════════════════
    for i, (sx, sy, h) in enumerate([(1.8, 1.3, 1.8), (2.2, 1.5, 1.4)]):
        objs.append(cyl(f"Stack_{i}", (sx, sy, 3.2 + h / 2), 0.22, h, M_steel, 8))
        objs.append(cyl(f"StackRing_{i}", (sx, sy, 3.2 + h), 0.28, 0.1, M_trim, 8))
        objs.append(cyl(f"StackCap_{i}", (sx, sy, 3.2 + h + 0.08), 0.2, 0.06, M_roof, 8))

    # ═══════════════════════════════════════════════════════════════
    # FLAG POLE — Top of dome
    # ═══════════════════════════════════════════════════════════════
    objs.append(cyl("FlagPole", (0, 0, 4.8), 0.03, 0.8, M_steel, 4))
    objs.append(box("Flag", (0.25, 0, 5.05), (0.45, 0.05, 0.28), M_flag))

    # ═══════════════════════════════════════════════════════════════
    # DECORATIVE — Corner pilasters, gutters
    # ═══════════════════════════════════════════════════════════════
    corners = [(-2.5, -1.7), (2.5, -1.7), (-2.5, 1.7), (2.5, 1.7),
               (-1.2, -1.9), (1.2, -1.9), (-1.2, 1.9), (1.2, 1.9)]
    for cx, cy in corners:
        objs.append(box(f"Pilaster_{cx}_{cy}", (cx, cy, 1.3), (0.15, 0.15, 2.0), M_wall_dk))

    # ═══════════════════════════════════════════════════════════════
    # JOIN & FINALIZE
    # ═══════════════════════════════════════════════════════════════
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()

    nucleo = bpy.context.active_object
    nucleo.name = "Nucleo"

    # Fix origin: center XY, bottom Z = 0
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    mesh_data = nucleo.data
    xs = [v.co.x for v in mesh_data.vertices]
    ys = [v.co.y for v in mesh_data.vertices]
    zs = [v.co.z for v in mesh_data.vertices]
    cx = (min(xs) + max(xs)) / 2
    cy = (min(ys) + max(ys)) / 2
    mz = min(zs)
    for v in mesh_data.vertices:
        v.co.x -= cx
        v.co.y -= cy
        v.co.z -= mz
    nucleo.location = (0, 0, 0)

    bpy.ops.object.shade_flat()
    print(f"[Nucleo] Vertices: {len(nucleo.data.vertices)}")
    print(f"[Nucleo] Faces: {len(nucleo.data.polygons)}")
    return nucleo


def export_glb(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format='GLB',
        use_selection=True, export_apply=True,
        export_materials='EXPORT', export_yup=True,
    )
    print(f"[Nucleo] Exported: {path}")


if __name__ == "__main__" or True:
    n = build_nucleo()
    n.select_set(True)
    bpy.context.view_layer.objects.active = n
    export_glb(EXPORT_PATH)
    print("[Nucleo] Done!")
