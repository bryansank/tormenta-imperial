"""
Tormenta Imperial - Dieselpunk Building Generator v2
=====================================================
Run inside Blender 4.x: Open Scripting tab > Open > Run Script (Alt+P)

Features:
- Subdivision Surface for smooth organic shapes
- Procedural noise textures for rust, grime, wear
- Voronoi textures for riveted/plated metal look
- Color ramps for realistic material transitions
- Varied geometry: arches, domes, tapered columns, greebles
- Ambient glow from windows and furnaces
"""

import bpy
import bmesh
import os
import math
import random
from mathutils import Vector, noise

# === CONFIG ===
EXPORT_DIR = r"C:\Users\Key\Documents\1_PERSONAL_KEY\tormenta-imperial\assets\models\buildings"
CELL = 2.0
random.seed(42)


# ============================================================
# UTILITIES
# ============================================================

def clear_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for block in [bpy.data.materials, bpy.data.meshes, bpy.data.textures,
                  bpy.data.node_groups, bpy.data.images]:
        for item in block:
            block.remove(item)


def join_all(name):
    """Join all mesh objects in scene into one, set origin to bottom-center."""
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    if not meshes:
        return None
    bpy.ops.object.select_all(action='DESELECT')
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.active_object
    obj.name = name
    # Bottom-center origin
    bbox = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    min_z = min(v.z for v in bbox)
    cx = (min(v.x for v in bbox) + max(v.x for v in bbox)) / 2
    cy = (min(v.y for v in bbox) + max(v.y for v in bbox)) / 2
    obj.location.x -= cx
    obj.location.y -= cy
    obj.location.z -= min_z
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return obj


def export_glb(obj, bid):
    folder = os.path.join(EXPORT_DIR, bid)
    os.makedirs(folder, exist_ok=True)
    fp = os.path.join(folder, f"{bid}.glb")
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(filepath=fp, use_selection=True, export_format='GLB', export_apply=True)
    print(f"  >> {fp}")


# ============================================================
# PROCEDURAL PBR MATERIALS (Node-based with textures)
# ============================================================

def _add_noise_variation(nodes, links, bsdf, base_color, scale=8.0, detail=6.0, roughness_var=0.1):
    """Add noise-based color/roughness variation to a Principled BSDF."""
    tex_coord = nodes.new('ShaderNodeTexCoord')
    tex_coord.location = (-800, 0)

    noise_tex = nodes.new('ShaderNodeTexNoise')
    noise_tex.location = (-600, 0)
    noise_tex.inputs['Scale'].default_value = scale
    noise_tex.inputs['Detail'].default_value = detail
    noise_tex.inputs['Roughness'].default_value = 0.6
    links.new(tex_coord.outputs['Object'], noise_tex.inputs['Vector'])

    # Color ramp for variation
    ramp = nodes.new('ShaderNodeValToRGB')
    ramp.location = (-400, 0)
    ramp.color_ramp.elements[0].color = base_color
    # Slightly darker variant
    ramp.color_ramp.elements[1].color = (
        base_color[0] * 0.6, base_color[1] * 0.6, base_color[2] * 0.6, 1.0
    )
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[1].position = 0.75
    links.new(noise_tex.outputs['Fac'], ramp.inputs['Fac'])
    links.new(ramp.outputs['Color'], bsdf.inputs['Base Color'])

    # Roughness variation
    map_range = nodes.new('ShaderNodeMapRange')
    map_range.location = (-400, -200)
    map_range.inputs['From Min'].default_value = 0.0
    map_range.inputs['From Max'].default_value = 1.0
    rough_base = bsdf.inputs['Roughness'].default_value
    map_range.inputs['To Min'].default_value = max(0, rough_base - roughness_var)
    map_range.inputs['To Max'].default_value = min(1, rough_base + roughness_var)
    links.new(noise_tex.outputs['Fac'], map_range.inputs['Value'])
    links.new(map_range.outputs['Result'], bsdf.inputs['Roughness'])


def _add_voronoi_plates(nodes, links, bsdf, base_color, scale=4.0):
    """Add voronoi texture for plated/riveted metal look."""
    tex_coord = nodes.new('ShaderNodeTexCoord')
    tex_coord.location = (-800, 0)

    voronoi = nodes.new('ShaderNodeTexVoronoi')
    voronoi.location = (-600, 0)
    voronoi.inputs['Scale'].default_value = scale
    voronoi.distance = 'MANHATTAN'
    links.new(tex_coord.outputs['Object'], voronoi.inputs['Vector'])

    ramp = nodes.new('ShaderNodeValToRGB')
    ramp.location = (-400, 0)
    ramp.color_ramp.elements[0].color = base_color
    ramp.color_ramp.elements[1].color = (
        base_color[0] * 0.75, base_color[1] * 0.75, base_color[2] * 0.8, 1.0
    )
    ramp.color_ramp.elements[0].position = 0.4
    ramp.color_ramp.elements[1].position = 0.6
    links.new(voronoi.outputs['Distance'], ramp.inputs['Fac'])
    links.new(ramp.outputs['Color'], bsdf.inputs['Base Color'])

    # Use voronoi for bump
    bump = nodes.new('ShaderNodeBump')
    bump.location = (-200, -300)
    bump.inputs['Strength'].default_value = 0.3
    links.new(voronoi.outputs['Distance'], bump.inputs['Height'])
    links.new(bump.outputs['Normal'], bsdf.inputs['Normal'])


def make_mat(name, base_color, metallic=0.0, roughness=0.5,
             emission_color=None, emission_str=0.0,
             use_noise=False, use_voronoi=False, noise_scale=8.0, voronoi_scale=4.0):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    out = nodes.new('ShaderNodeOutputMaterial')
    out.location = (400, 0)
    bsdf = nodes.new('ShaderNodeBsdfPrincipled')
    bsdf.location = (0, 0)
    bsdf.inputs['Base Color'].default_value = base_color
    bsdf.inputs['Metallic'].default_value = metallic
    bsdf.inputs['Roughness'].default_value = roughness
    if emission_color and emission_str > 0:
        bsdf.inputs['Emission Color'].default_value = emission_color
        bsdf.inputs['Emission Strength'].default_value = emission_str
    links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])

    if use_voronoi:
        _add_voronoi_plates(nodes, links, bsdf, base_color, voronoi_scale)
    elif use_noise:
        _add_noise_variation(nodes, links, bsdf, base_color, noise_scale)

    return mat


# --- Material palette ---
def M_dark_steel():
    return make_mat("DarkSteel", (0.06, 0.065, 0.08, 1), 0.9, 0.3, use_voronoi=True, voronoi_scale=6.0)

def M_rusted():
    return make_mat("Rusted", (0.30, 0.13, 0.05, 1), 0.55, 0.75, use_noise=True, noise_scale=12.0)

def M_brass():
    return make_mat("Brass", (0.60, 0.42, 0.08, 1), 0.92, 0.25, use_noise=True, noise_scale=5.0)

def M_wood():
    return make_mat("Wood", (0.18, 0.10, 0.04, 1), 0.0, 0.82, use_noise=True, noise_scale=15.0)

def M_concrete():
    return make_mat("Concrete", (0.22, 0.20, 0.18, 1), 0.0, 0.92, use_noise=True, noise_scale=10.0)

def M_glow():
    return make_mat("Glow", (1, 0.65, 0.15, 1), 0.0, 0.1,
                    emission_color=(1.0, 0.72, 0.22, 1), emission_str=5.0)

def M_red_glow():
    return make_mat("RedGlow", (1, 0.15, 0.05, 1), 0.0, 0.1,
                    emission_color=(1.0, 0.2, 0.05, 1), emission_str=4.0)

def M_smoke():
    return make_mat("Smoke", (0.04, 0.04, 0.045, 1), 0.7, 0.45, use_noise=True, noise_scale=6.0)

def M_copper():
    return make_mat("Copper", (0.50, 0.24, 0.08, 1), 0.88, 0.35, use_noise=True, noise_scale=8.0)

def M_oil():
    return make_mat("Oil", (0.04, 0.035, 0.03, 1), 0.25, 0.88, use_noise=True, noise_scale=14.0)

def M_gold():
    return make_mat("Gold", (0.70, 0.55, 0.08, 1), 0.95, 0.18, use_noise=True, noise_scale=4.0)

def M_patina():
    return make_mat("Patina", (0.12, 0.28, 0.15, 1), 0.35, 0.65, use_noise=True, noise_scale=10.0)

def M_stone():
    return make_mat("Stone", (0.32, 0.30, 0.27, 1), 0.0, 0.95, use_noise=True, noise_scale=8.0)

def M_cobble():
    return make_mat("Cobble", (0.24, 0.21, 0.19, 1), 0.0, 0.95, use_voronoi=True, voronoi_scale=12.0)

def M_foliage():
    return make_mat("Foliage", (0.10, 0.28, 0.06, 1), 0.0, 0.8, use_noise=True, noise_scale=20.0)

def M_water():
    return make_mat("Water", (0.12, 0.28, 0.42, 1), 0.05, 0.02,
                    emission_color=(0.15, 0.35, 0.55, 1), emission_str=0.8,
                    use_noise=True, noise_scale=25.0)

def M_bronze():
    return make_mat("Bronze", (0.42, 0.28, 0.10, 1), 0.88, 0.32, use_noise=True, noise_scale=6.0)

def M_corrugated():
    """Corrugated metal - distinctive wavy pattern."""
    return make_mat("Corrugated", (0.15, 0.12, 0.10, 1), 0.6, 0.6, use_noise=True, noise_scale=30.0)

def M_dirty_glass():
    return make_mat("DirtyGlass", (0.5, 0.45, 0.35, 1), 0.0, 0.3,
                    emission_color=(0.8, 0.6, 0.3, 1), emission_str=1.5)


# ============================================================
# GEOMETRY PRIMITIVES (with subdivision & deformers)
# ============================================================

def box(name, sx, sy, sz, loc, mat, subdiv=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.active_object
    o.name = name
    o.scale = (sx, sy, sz)
    bpy.ops.object.transform_apply(scale=True)
    if subdiv > 0:
        mod = o.modifiers.new("Sub", 'SUBSURF')
        mod.levels = subdiv
        mod.render_levels = subdiv
        bpy.ops.object.modifier_apply(modifier="Sub")
    o.data.materials.append(mat)
    return o


def cyl(name, r, h, loc, mat, verts=16, subdiv=0):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=h, location=loc)
    o = bpy.context.active_object
    o.name = name
    if subdiv > 0:
        mod = o.modifiers.new("Sub", 'SUBSURF')
        mod.levels = subdiv
        bpy.ops.object.modifier_apply(modifier="Sub")
    o.data.materials.append(mat)
    return o


def cone(name, r1, r2, h, loc, mat, verts=16):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r1, radius2=r2, depth=h, location=loc)
    o = bpy.context.active_object
    o.name = name
    o.data.materials.append(mat)
    return o


def sphere(name, r, loc, mat, seg=16, ring=8):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=loc, segments=seg, ring_count=ring)
    o = bpy.context.active_object
    o.name = name
    o.data.materials.append(mat)
    return o


def torus(name, major_r, minor_r, loc, mat, major_seg=24, minor_seg=8):
    bpy.ops.mesh.primitive_torus_add(major_radius=major_r, minor_radius=minor_r,
                                      major_segments=major_seg, minor_segments=minor_seg,
                                      location=loc)
    o = bpy.context.active_object
    o.name = name
    o.data.materials.append(mat)
    return o


def pipe(name, start, end, r, mat):
    dx, dy, dz = end[0]-start[0], end[1]-start[1], end[2]-start[2]
    dist = math.sqrt(dx*dx + dy*dy + dz*dz)
    if dist < 0.001:
        return None
    mid = ((start[0]+end[0])/2, (start[1]+end[1])/2, (start[2]+end[2])/2)
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=dist, location=mid, vertices=8)
    o = bpy.context.active_object
    o.name = name
    phi = math.atan2(dy, dx)
    theta = math.acos(max(-1, min(1, dz / dist)))
    o.rotation_euler = (theta, 0, phi)
    bpy.ops.object.transform_apply(rotation=True)
    o.data.materials.append(mat)
    return o


def bevel_obj(obj, w=0.02, seg=2):
    bpy.context.view_layer.objects.active = obj
    mod = obj.modifiers.new("Bev", 'BEVEL')
    mod.width = w
    mod.segments = seg
    try:
        bpy.ops.object.modifier_apply(modifier="Bev")
    except:
        obj.modifiers.remove(mod)


def deform_noise(obj, strength=0.05, scale=3.0):
    """Displace vertices slightly with noise for organic look."""
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    bm = bmesh.from_edit_mesh(obj.data)
    for v in bm.verts:
        n = noise.noise_vector(v.co * scale)
        v.co += Vector(n) * strength
    bmesh.update_edit_mesh(obj.data)
    bpy.ops.object.mode_set(mode='OBJECT')
    obj.select_set(False)


def add_greebles(parent_loc, w, d, h, mat, count=8, seed=0):
    """Add small mechanical detail boxes/cylinders on surfaces."""
    rng = random.Random(seed)
    parts = []
    for i in range(count):
        gx = rng.uniform(-w * 0.45, w * 0.45)
        gy = rng.uniform(-d * 0.45, d * 0.45)
        gz = rng.uniform(h * 0.2, h * 0.8)
        # Random side
        side = rng.choice(['x+', 'x-', 'y+', 'y-'])
        if side == 'x+':
            pos = (parent_loc[0] + w * 0.5, parent_loc[1] + gy, parent_loc[2] + gz - h / 2)
        elif side == 'x-':
            pos = (parent_loc[0] - w * 0.5, parent_loc[1] + gy, parent_loc[2] + gz - h / 2)
        elif side == 'y+':
            pos = (parent_loc[0] + gx, parent_loc[1] + d * 0.5, parent_loc[2] + gz - h / 2)
        else:
            pos = (parent_loc[0] + gx, parent_loc[1] - d * 0.5, parent_loc[2] + gz - h / 2)

        if rng.random() > 0.5:
            g = box(f"greeble_{i}", rng.uniform(0.04, 0.12), rng.uniform(0.04, 0.12),
                    rng.uniform(0.05, 0.15), pos, mat)
        else:
            g = cyl(f"greeble_{i}", rng.uniform(0.02, 0.06), rng.uniform(0.05, 0.18), pos, mat, 6)
        parts.append(g)
    return parts


def add_rivets_line(start, end, count, mat, r=0.025):
    """Add a line of rivets between two points."""
    parts = []
    for i in range(count):
        t = i / max(1, count - 1)
        pos = (
            start[0] + (end[0] - start[0]) * t,
            start[1] + (end[1] - start[1]) * t,
            start[2] + (end[2] - start[2]) * t,
        )
        rv = sphere(f"rivet_{i}", r, pos, mat, 6, 4)
        parts.append(rv)
    return parts


def smokestack(x, y, base_z, height, mat_body, mat_rim, r=0.18):
    """Create a tapered smokestack with rim."""
    parts = []
    # Tapered body
    s = cone(f"stack", r, r * 0.85, height, (x, y, base_z + height / 2), mat_body, 10)
    parts.append(s)
    # Decorative rings
    for frac in [0.3, 0.6, 0.9]:
        ring = torus(f"ring", r * 0.95, 0.02, (x, y, base_z + height * frac), mat_rim, 12, 6)
        parts.append(ring)
    # Flared rim at top
    rim = cone(f"rim", r * 1.2, r * 0.9, 0.12, (x, y, base_z + height + 0.06), mat_rim, 10)
    parts.append(rim)
    return parts


# ============================================================
# BUILDING GENERATORS
# ============================================================

def build_nucleo():
    """3x3 Command Center - Heart of the Empire"""
    p = []
    w, d = 3 * CELL, 3 * CELL

    # Massive foundation with steps
    p.append(box("found", w * 1.02, d * 1.02, 0.35, (0, 0, 0.175), M_concrete()))
    p.append(box("step", w * 0.96, d * 0.96, 0.15, (0, 0, 0.425), M_stone()))

    # Main body with subdivision for smoother edges
    body = box("body", w * 0.88, d * 0.88, 3.2, (0, 0, 2.1), M_dark_steel(), subdiv=1)
    bevel_obj(body, 0.08, 2)
    p.append(body)

    # Mid section - riveted plates
    mid = box("mid", w * 0.68, d * 0.68, 1.6, (0, 0, 4.1), M_rusted())
    bevel_obj(mid, 0.05, 2)
    p.append(mid)

    # Central octagonal tower
    tower = cyl("tower", 0.9, 2.8, (0, 0, 6.0), M_dark_steel(), 8, subdiv=1)
    p.append(tower)

    # Brass dome
    dome = sphere("dome", 1.05, (0, 0, 7.7), M_brass(), 16, 8)
    # Cut bottom half with a box (boolean-free: just move up)
    p.append(dome)

    # Spire on dome
    p.append(cone("spire", 0.12, 0.02, 0.8, (0, 0, 8.6), M_gold(), 6))

    # Amber windows - 4 sides
    for side in range(4):
        angle = side * math.pi / 2
        nx = math.cos(angle)
        ny = math.sin(angle)
        for i in range(4):
            offset = -1.2 + i * 0.8
            if abs(nx) > 0.5:
                wx, wy = nx * w * 0.445, offset
                sx, sy = 0.06, 0.28
            else:
                wx, wy = offset, ny * d * 0.445
                sx, sy = 0.28, 0.06
            p.append(box(f"win_{side}_{i}", sx, sy, 0.55, (wx, wy, 2.2), M_glow()))
            # Window frame
            p.append(box(f"frame_{side}_{i}", sx + 0.03, sy + 0.03, 0.6, (wx, wy, 2.2), M_brass()))

    # Tower windows
    for i in range(4):
        angle = i * math.pi / 2 + math.pi / 4
        wx = 0.85 * math.cos(angle)
        wy = 0.85 * math.sin(angle)
        p.append(box(f"twin_{i}", 0.06, 0.2, 0.4, (wx, wy, 6.0), M_glow()))

    # Smokestacks with rings
    for sx, sy in [(-w * 0.32, -d * 0.32), (w * 0.32, d * 0.32)]:
        p.extend(smokestack(sx, sy, 4.0, 2.8, M_smoke(), M_brass(), 0.22))

    # Copper pipe network
    cp = M_copper()
    for s in [-1, 1]:
        p.append(pipe(f"vp_{s}", (s * w * 0.44, 0, 0.8), (s * w * 0.44, 0, 3.8), 0.055, cp))
        p.append(pipe(f"hp_{s}", (s * w * 0.44, -0.8, 3.5), (s * w * 0.44, 0.8, 3.5), 0.055, cp))
        # Valve
        p.append(sphere(f"valve_{s}", 0.08, (s * w * 0.44, 0, 2.5), M_brass(), 8, 6))

    # Greeble details
    p.extend(add_greebles((0, 0, 2.1), w * 0.88, d * 0.88, 3.2, M_copper(), 12, seed=1))

    # Rivet lines on body edges
    brass = M_brass()
    for s in [-1, 1]:
        p.extend(add_rivets_line((s * w * 0.44, -d * 0.44, 0.7), (s * w * 0.44, -d * 0.44, 3.5), 8, brass))
        p.extend(add_rivets_line((s * w * 0.44, d * 0.44, 0.7), (s * w * 0.44, d * 0.44, 3.5), 8, brass))


def build_house():
    """1x1 Worker dwelling - small but characterful"""
    w, d = CELL * 0.82, CELL * 0.82

    # Walls with noise deformation for worn look
    walls = box("walls", w, d, 1.7, (0, 0, 0.85), M_corrugated())
    deform_noise(walls, 0.015, 5.0)

    # Angled corrugated roof
    roof = box("roof", w * 1.12, d * 1.15, 0.12, (0, 0.05, 1.85), M_rusted())
    roof.rotation_euler = (0.18, 0.05, 0)
    bpy.ops.object.transform_apply(rotation=True)

    # Chimney with smoke ring
    cyl("chimney", 0.07, 0.55, (w * 0.28, -d * 0.28, 2.1), M_smoke(), 8)
    torus("smoke_ring", 0.07, 0.015, (w * 0.28, -d * 0.28, 2.42), M_smoke(), 8, 4)

    # Wooden door with frame
    box("door_frame", 0.1, 0.42, 0.72, (w * 0.5, 0, 0.36), M_brass())
    box("door", 0.07, 0.36, 0.65, (w * 0.5, 0, 0.33), M_wood())

    # Warm window
    box("win_frame", 0.09, 0.32, 0.28, (-w * 0.5, 0.05, 1.15), M_brass())
    box("win", 0.07, 0.26, 0.22, (-w * 0.5, 0.05, 1.15), M_glow())

    # Side window
    box("win2_frame", 0.26, 0.09, 0.2, (0.1, d * 0.5, 1.2), M_brass())
    box("win2", 0.2, 0.07, 0.15, (0.1, d * 0.5, 1.2), M_dirty_glass())

    # Pipe on side with valve
    pipe("pipe1", (w * 0.38, d * 0.48, 0.4), (w * 0.38, d * 0.48, 1.7), 0.028, M_copper())
    sphere("valve", 0.04, (w * 0.38, d * 0.48, 1.1), M_brass(), 6, 4)

    # Small crate at door
    box("crate", 0.18, 0.15, 0.14, (w * 0.5 + 0.15, -0.15, 0.07), M_wood())


def build_sawmill():
    """2x1 Wood production - steam-powered sawmill"""
    w, d = 2 * CELL * 0.88, CELL * 0.88

    # Foundation
    box("found", w * 1.02, d * 1.02, 0.2, (0, 0, 0.1), M_concrete())

    # Main structure
    body = box("body", w, d, 2.3, (0, 0, 1.25), M_dark_steel())
    bevel_obj(body, 0.04, 2)

    # Corrugated sloped roof
    roof = box("roof", w * 1.06, d * 1.18, 0.1, (0, 0.05, 2.5), M_corrugated())
    roof.rotation_euler = (0.22, 0, 0)
    bpy.ops.object.transform_apply(rotation=True)

    # Large saw blade
    blade = cyl("blade", 0.55, 0.04, (w * 0.2, 0, 1.6), M_dark_steel(), 24)
    blade.rotation_euler = (0, math.pi / 2, 0)
    bpy.ops.object.transform_apply(rotation=True)
    # Blade center hub
    cyl("hub", 0.08, 0.08, (w * 0.2, 0, 1.6), M_brass(), 8)

    # Log pile with varied sizes
    for i in range(4):
        r = 0.09 + random.random() * 0.06
        l = 0.9 + random.random() * 0.4
        log = cyl(f"log_{i}", r, l, (-w * 0.33, -d * 0.12 + i * 0.2, r), M_wood(), 8)
        log.rotation_euler = (math.pi / 2, random.uniform(-0.1, 0.1), random.uniform(-0.05, 0.05))
        bpy.ops.object.transform_apply(rotation=True)

    # Smokestack
    smokestack(w * 0.35, d * 0.28, 2.4, 2.2, M_smoke(), M_brass(), 0.18)

    # Conveyor with rollers
    box("conveyor", w * 0.5, 0.18, 0.06, (-w * 0.08, d * 0.42, 0.85), M_dark_steel())
    for i in range(5):
        cyl(f"roller_{i}", 0.03, 0.2, (-w * 0.28 + i * w * 0.1, d * 0.42, 0.82), M_brass(), 6)

    # Steam pipes
    cp = M_copper()
    pipe("p1", (-w * 0.44, d * 0.38, 1.0), (-w * 0.44, d * 0.38, 2.3), 0.04, cp)
    pipe("p2", (-w * 0.44, d * 0.38, 2.3), (-w * 0.1, d * 0.38, 2.3), 0.04, cp)

    # Greebles
    add_greebles((0, 0, 1.25), w, d, 2.3, M_copper(), 8, seed=10)

    # Windows
    for i in range(2):
        box(f"win_{i}", 0.06, 0.22, 0.3, (w * 0.48, -d * 0.15 + i * 0.5, 1.8), M_dirty_glass())


def build_gold_mine():
    """2x2 Gold production - imposing mine entrance"""
    w, d = 2 * CELL * 0.88, 2 * CELL * 0.88

    box("found", w, d, 0.2, (0, 0, 0.1), M_concrete())

    # Mine entrance - arched
    entrance = box("entrance", w * 0.55, d * 0.45, 2.6, (0, d * 0.12, 1.4), M_dark_steel())
    bevel_obj(entrance, 0.06, 2)

    # Arch top (half cylinder)
    arch = cyl("arch", w * 0.28, d * 0.46, (0, d * 0.12, 2.8), M_rusted(), 12)
    arch.rotation_euler = (math.pi / 2, 0, 0)
    bpy.ops.object.transform_apply(rotation=True)

    # Dark entrance hole
    box("hole", w * 0.4, 0.1, 1.8, (0, -d * 0.1, 1.1), M_oil())

    # Headframe tower - A-frame style
    for s in [-1, 1]:
        leg = box(f"leg_{s}", 0.15, 0.15, 4.2, (w * 0.22 + s * 0.35, d * 0.18, 2.1), M_dark_steel())
        leg.rotation_euler = (0, s * -0.12, 0)
        bpy.ops.object.transform_apply(rotation=True)

    # Crossbeams
    box("xbeam1", 1.0, 0.1, 0.1, (w * 0.22, d * 0.18, 3.5), M_rusted())
    box("xbeam2", 1.0, 0.1, 0.1, (w * 0.22, d * 0.18, 2.0), M_rusted())

    # Pulley wheel
    torus("wheel", 0.3, 0.04, (w * 0.22, d * 0.18, 4.3), M_brass(), 16, 6)
    cyl("axle", 0.04, 0.3, (w * 0.22, d * 0.18, 4.3), M_dark_steel(), 8)

    # Mine cart
    cart = box("cart", 0.35, 0.28, 0.2, (-w * 0.2, -d * 0.28, 0.3), M_rusted())
    # Wheels
    for dx, dy in [(-0.12, -0.1), (0.12, -0.1), (-0.12, 0.1), (0.12, 0.1)]:
        cyl(f"cw", 0.04, 0.03, (-w * 0.2 + dx, -d * 0.28 + dy, 0.18), M_dark_steel(), 8)

    # Rails
    for offset in [-0.12, 0.12]:
        box(f"rail_{offset}", w * 0.45, 0.025, 0.03, (-w * 0.08, -d * 0.28 + offset, 0.14), M_dark_steel())

    # Gold ore pile with glow
    cone("ore", 0.38, 0.0, 0.32, (-w * 0.35, -d * 0.1, 0.36), M_gold(), 8)
    sphere("ore_glow", 0.15, (-w * 0.35, -d * 0.1, 0.25), M_glow(), 8, 4)

    # Lanterns
    for x, y in [(-w * 0.28, -d * 0.08), (w * 0.05, -d * 0.08)]:
        box("lantern_body", 0.06, 0.06, 0.1, (x, y, 2.2), M_brass())
        sphere("lantern_glow", 0.035, (x, y, 2.15), M_glow(), 6, 4)

    # Greebles and pipes
    add_greebles((0, d * 0.12, 1.4), w * 0.55, d * 0.45, 2.6, M_copper(), 6, seed=20)
    pipe("dp", (w * 0.35, d * 0.35, 0.5), (w * 0.35, d * 0.35, 3.0), 0.04, M_copper())


def build_warehouse():
    """1x1 Storage building"""
    w, d = CELL * 0.88, CELL * 0.88

    body = box("body", w, d, 2.1, (0, 0, 1.05), M_dark_steel())
    bevel_obj(body, 0.03, 2)

    # Rolling door with corrugated texture
    box("door", 0.06, w * 0.58, 1.45, (w * 0.5, 0, 0.73), M_corrugated())
    # Door frame
    box("frame_l", 0.08, 0.06, 1.5, (w * 0.5, w * 0.3, 0.75), M_brass())
    box("frame_r", 0.08, 0.06, 1.5, (w * 0.5, -w * 0.3, 0.75), M_brass())
    box("frame_t", 0.08, w * 0.62, 0.06, (w * 0.5, 0, 1.48), M_brass())

    # Flat roof
    box("roof", w * 1.05, d * 1.05, 0.08, (0, 0, 2.15), M_rusted())

    # Crane rail on roof
    box("rail", 0.04, d * 0.75, 0.04, (0, 0, 2.22), M_dark_steel())
    box("crane_h", 0.3, 0.04, 0.04, (0, 0.1, 2.22), M_brass())

    # Crates inside (visible)
    box("c1", 0.22, 0.22, 0.22, (-0.15, -0.1, 0.11), M_wood())
    box("c2", 0.18, 0.18, 0.18, (0.1, 0.12, 0.09), M_wood())
    box("c3", 0.2, 0.2, 0.2, (-0.08, 0.15, 0.32), M_wood())
    # Barrel
    cyl("barrel", 0.1, 0.25, (0.2, -0.15, 0.12), M_rusted(), 8)

    # Light above door
    sphere("light", 0.04, (w * 0.5 + 0.03, 0, 1.6), M_glow(), 8, 4)

    # Side greebles
    add_greebles((0, 0, 1.05), w, d, 2.1, M_copper(), 5, seed=30)


def build_foundry():
    """2x1 Steel foundry - Era 2 unlock"""
    w, d = 2 * CELL * 0.88, CELL * 0.88

    box("found", w * 1.02, d * 1.02, 0.25, (0, 0, 0.125), M_concrete())

    body = box("body", w, d, 3.0, (0, 0, 1.65), M_dark_steel())
    bevel_obj(body, 0.05, 2)

    # Blast furnace - large riveted cylinder
    furnace = cyl("furnace", 0.55, 2.8, (-w * 0.18, 0, 2.0), M_rusted(), 12, subdiv=1)
    # Furnace bands
    for h in [1.0, 1.8, 2.6]:
        torus(f"fband_{h}", 0.57, 0.025, (-w * 0.18, 0, h), M_brass(), 12, 6)

    # Molten glow at furnace base
    cyl("glow_base", 0.3, 0.25, (-w * 0.18, d * 0.44, 0.8), M_red_glow(), 8)

    # Two smokestacks
    for i, xo in enumerate([-0.5, 0.5]):
        smokestack(w * 0.28 + xo * 0.4, d * 0.1, 3.2, 3.2, M_smoke(), M_brass(), 0.2)

    # Pipe network
    cp = M_copper()
    for yo in [-0.35, 0.35]:
        pipe(f"vp_{yo}", (w * 0.38, yo * d, 1.2), (w * 0.38, yo * d, 3.2), 0.05, cp)
    pipe("hp", (w * 0.38, -d * 0.35, 2.8), (w * 0.38, d * 0.35, 2.8), 0.05, cp)
    # Valves
    for yo in [-0.35, 0.35]:
        sphere(f"valve_{yo}", 0.06, (w * 0.38, yo * d, 2.0), M_brass(), 8, 4)

    # Red glow windows
    for i in range(3):
        box(f"gwin_{i}", 0.06, 0.22, 0.35, (-w * 0.44, -0.3 + i * 0.3, 1.2), M_red_glow())

    # Side windows
    for i in range(2):
        box(f"swin_{i}", 0.06, 0.2, 0.25, (w * 0.44, -0.2 + i * 0.4, 2.2), M_dirty_glass())

    # Greebles
    add_greebles((0, 0, 1.65), w, d, 3.0, M_copper(), 10, seed=40)

    # Rivets on edges
    brass = M_brass()
    add_rivets_line((-w * 0.5, -d * 0.5, 0.4), (-w * 0.5, -d * 0.5, 3.0), 8, brass)
    add_rivets_line((w * 0.5, -d * 0.5, 0.4), (w * 0.5, -d * 0.5, 3.0), 8, brass)


def build_barracks():
    """2x2 Military barracks"""
    w, d = 2 * CELL * 0.88, 2 * CELL * 0.88

    box("found", w * 1.02, d * 1.02, 0.3, (0, 0, 0.15), M_concrete())

    body = box("body", w, d, 2.6, (0, 0, 1.45), M_dark_steel())
    bevel_obj(body, 0.06, 2)

    # Reinforced corners with bevels
    for x, y in [(-1, -1), (-1, 1), (1, -1), (1, 1)]:
        c = box(f"corner_{x}_{y}", 0.28, 0.28, 2.9, (x * w * 0.47, y * d * 0.47, 1.6), M_rusted())
        bevel_obj(c, 0.04, 2)

    # Watchtower
    wt = cyl("watchtower", 0.4, 1.8, (w * 0.38, -d * 0.38, 3.6), M_dark_steel(), 8)
    bevel_obj(wt, 0.03, 1)
    # Tower roof - pyramid
    cone("wt_roof", 0.5, 0.05, 0.6, (w * 0.38, -d * 0.38, 4.8), M_rusted(), 4)
    # Searchlight
    cone("searchlight", 0.05, 0.08, 0.15, (w * 0.38, -d * 0.5, 4.3), M_glow(), 8)

    # Heavy door
    box("door_frame", 0.1, 0.85, 1.3, (w * 0.5, 0, 0.65), M_brass())
    box("door", 0.08, 0.75, 1.2, (w * 0.5, 0, 0.6), M_rusted())
    # Door rivets
    brass = M_brass()
    for dy in [-0.25, 0, 0.25]:
        for dz in [0.3, 0.7, 1.1]:
            sphere(f"dr", 0.02, (w * 0.52, dy, dz), brass, 4, 3)

    # Sandbags
    for i in range(5):
        bag = box(f"bag_{i}", 0.28, 0.45, 0.12,
                  (w * 0.52 + 0.18, -0.55 + i * 0.28, 0.12 + (i % 2) * 0.12), M_concrete())
        deform_noise(bag, 0.02, 3.0)

    # Narrow slit windows
    for i in range(4):
        box(f"slit_{i}", 0.06, 0.05, 0.25, (-w * 0.5, -d * 0.3 + i * d * 0.2, 1.9), M_dark_steel())

    # Flag pole
    cyl("pole", 0.02, 1.5, (0, d * 0.48, 3.5), M_dark_steel(), 6)
    box("flag", 0.02, 0.35, 0.2, (0, d * 0.48 + 0.18, 4.15), M_red_glow())

    add_greebles((0, 0, 1.45), w, d, 2.6, M_copper(), 8, seed=50)


def build_refinery():
    """2x2 Oil refinery - Era 3 unlock"""
    w, d = 2 * CELL * 0.88, 2 * CELL * 0.88

    box("found", w, d, 0.2, (0, 0, 0.1), M_oil())

    # Processing building
    bld = box("bld", w * 0.55, d * 0.65, 2.8, (-w * 0.12, 0, 1.5), M_dark_steel())
    bevel_obj(bld, 0.05, 2)

    # Distillation columns - varied heights
    for i, (xo, r, h) in enumerate([(0.15, 0.28, 5.0), (0.3, 0.22, 4.2), (0.0, 0.18, 3.5)]):
        col = cyl(f"col_{i}", r, h, (w * xo, d * 0.05 + i * 0.3 - 0.3, h / 2 + 0.2), M_dark_steel(), 12, subdiv=1)
        # Bands
        for j in range(4):
            torus(f"band_{i}_{j}", r + 0.02, 0.018,
                  (w * xo, d * 0.05 + i * 0.3 - 0.3, h * 0.2 + j * h * 0.22 + 0.2),
                  M_brass(), 12, 6)

    # Storage tanks (horizontal)
    for i, yo in enumerate([-0.25, 0.25]):
        tank = cyl(f"tank_{i}", 0.45, 1.2, (-w * 0.32, d * yo, 0.55), M_oil(), 12)
        tank.rotation_euler = (0, math.pi / 2, 0)
        bpy.ops.object.transform_apply(rotation=True)
        # Tank bands
        for j in range(3):
            t = torus(f"tband_{i}_{j}", 0.47, 0.015,
                      (-w * 0.32 + (-0.35 + j * 0.35), d * yo, 0.55), M_brass(), 12, 6)
            t.rotation_euler = (0, math.pi / 2, 0)
            bpy.ops.object.transform_apply(rotation=True)

    # Pipe network
    cp = M_copper()
    pipe("p1", (w * 0.12, d * 0.3, 3.5), (w * 0.12, -d * 0.3, 3.5), 0.045, cp)
    pipe("p2", (-w * 0.32, d * 0.25, 1.2), (w * 0.12, d * 0.25, 1.2), 0.045, cp)
    pipe("p3", (w * 0.12, d * 0.25, 1.2), (w * 0.12, d * 0.25, 3.5), 0.045, cp)
    pipe("p4", (-w * 0.32, -d * 0.25, 1.2), (-w * 0.12, -d * 0.25, 1.2), 0.04, cp)

    # Flare stack
    cyl("flare_stack", 0.1, 5.5, (w * 0.38, -d * 0.38, 2.75), M_smoke(), 8)
    cone("flame", 0.14, 0.0, 0.35, (w * 0.38, -d * 0.38, 5.7), M_red_glow(), 8)
    sphere("flame_glow", 0.2, (w * 0.38, -d * 0.38, 5.6), M_glow(), 8, 4)

    # Ladder on main column
    for h in range(8):
        box(f"rung_{h}", 0.02, 0.15, 0.02, (w * 0.15 + 0.3, d * 0.05, 0.6 + h * 0.5), M_dark_steel())

    add_greebles((-w * 0.12, 0, 1.5), w * 0.55, d * 0.65, 2.8, M_copper(), 10, seed=60)


def build_tower():
    """1x1 Guard tower"""
    w = CELL * 0.7

    # Base
    base = box("base", w, w, 0.45, (0, 0, 0.225), M_concrete())
    bevel_obj(base, 0.03, 2)

    # Main column - octagonal, tapered
    col = cyl("col", 0.28, 3.8, (0, 0, 2.15), M_dark_steel(), 8, subdiv=1)

    # Decorative bands
    for h in [0.8, 1.6, 2.4, 3.2]:
        torus(f"band_{h}", 0.32, 0.02, (0, 0, h), M_brass(), 8, 6)

    # Platform
    plat = box("plat", w * 1.15, w * 1.15, 0.12, (0, 0, 4.1), M_dark_steel())
    bevel_obj(plat, 0.02, 1)

    # Armored parapet walls with crenellations
    for side in range(4):
        angle = side * math.pi / 2
        nx, ny = math.cos(angle), math.sin(angle)
        cx = nx * w * 0.55
        cy = ny * w * 0.55
        if abs(nx) > 0.5:
            wall = box(f"wall_{side}", 0.08, w * 0.85, 0.45, (cx, cy, 4.4), M_rusted())
        else:
            wall = box(f"wall_{side}", w * 0.85, 0.08, 0.45, (cx, cy, 4.4), M_rusted())

    # Searchlight (cone shape)
    cone("light_body", 0.1, 0.06, 0.18, (0, 0, 4.75), M_brass(), 8)
    sphere("light_glow", 0.055, (0, 0, 4.7), M_glow(), 8, 4)

    # Cross bracing
    pipe("brace1", (-0.2, -0.2, 0.5), (0.2, 0.2, 2.5), 0.015, M_dark_steel())
    pipe("brace2", (0.2, -0.2, 0.5), (-0.2, 0.2, 2.5), 0.015, M_dark_steel())


def build_headquarters():
    """2x2 Capstone HQ - Most imposing building"""
    w, d = 2 * CELL * 0.88, 2 * CELL * 0.88

    # Grand stepped foundation
    box("step1", w * 1.04, d * 1.04, 0.35, (0, 0, 0.175), M_stone())
    box("step2", w * 0.98, d * 0.98, 0.25, (0, 0, 0.475), M_concrete())

    # Main body
    body = box("body", w * 0.85, d * 0.85, 3.8, (0, 0, 2.5), M_dark_steel())
    bevel_obj(body, 0.08, 2)

    # Command tower
    cmd = box("cmd", w * 0.42, d * 0.42, 2.2, (0, 0, 5.1), M_rusted())
    bevel_obj(cmd, 0.05, 2)

    # Brass dome with spire
    dome = sphere("dome", 0.85, (0, 0, 6.6), M_brass(), 20, 10)
    cone("spire", 0.1, 0.02, 1.0, (0, 0, 7.6), M_gold(), 6)

    # Grand entrance columns
    for yo in [-0.35, 0.35]:
        c = cyl(f"column_{yo}", 0.1, 2.8, (w * 0.42, yo * d * 0.3, 2.0), M_brass(), 10, subdiv=1)
        # Column capital
        cone(f"cap_{yo}", 0.15, 0.1, 0.15, (w * 0.42, yo * d * 0.3, 3.45), M_gold(), 10)
        # Column base
        box(f"cbase_{yo}", 0.22, 0.22, 0.15, (w * 0.42, yo * d * 0.3, 0.68), M_stone())

    # Grand door
    box("door_frame", 0.1, d * 0.38, 2.0, (w * 0.42, 0, 1.6), M_brass())
    box("door", 0.08, d * 0.32, 1.85, (w * 0.42, 0, 1.53), M_wood())

    # Eagle emblem (diamond shape)
    emblem = box("emblem", 0.06, 0.35, 0.35, (w * 0.43, 0, 3.2), M_gold())
    emblem.rotation_euler = (0, 0, math.pi / 4)
    bpy.ops.object.transform_apply(rotation=True)

    # Large amber windows - all 4 sides
    for side in range(4):
        angle = side * math.pi / 2
        nx, ny = math.cos(angle), math.sin(angle)
        for i in range(5):
            offset = -d * 0.32 + i * d * 0.16
            if abs(nx) > 0.5:
                pos = (nx * w * 0.43, offset, 2.8)
                sx, sy = 0.05, 0.18
            else:
                pos = (offset, ny * d * 0.43, 2.8)
                sx, sy = 0.18, 0.05
            box(f"win_{side}_{i}", sx, sy, 0.65, pos, M_glow())
            box(f"wf_{side}_{i}", sx + 0.02, sy + 0.02, 0.7, pos, M_brass())

    # Tower windows
    for i in range(4):
        angle = i * math.pi / 2 + math.pi / 4
        wx, wy = 0.38 * math.cos(angle), 0.38 * math.sin(angle)
        box(f"twin_{i}", 0.05, 0.15, 0.4, (wx, wy, 5.2), M_glow())

    # Smokestacks
    for xo in [-0.35, 0.35]:
        smokestack(xo * w, d * 0.38, 3.8, 2.5, M_smoke(), M_brass(), 0.15)

    # Antennas with red tips
    for pos in [(-w * 0.15, -d * 0.15), (w * 0.15, d * 0.15)]:
        cyl("ant", 0.015, 1.8, (pos[0], pos[1], 7.0), M_dark_steel(), 6)
        sphere("ant_tip", 0.03, (pos[0], pos[1], 7.95), M_red_glow(), 6, 4)

    # Greebles and rivets
    add_greebles((0, 0, 2.5), w * 0.85, d * 0.85, 3.8, M_copper(), 15, seed=70)
    brass = M_brass()
    for s in [-1, 1]:
        add_rivets_line((s * w * 0.43, -d * 0.43, 0.8), (s * w * 0.43, -d * 0.43, 4.2), 10, brass)


def build_road():
    """1x1 Decorative path with rail tracks"""
    w = CELL * 0.95

    # Cobblestone base with voronoi texture
    base = box("base", w, w, 0.1, (0, 0, 0.05), M_cobble())
    deform_noise(base, 0.008, 8.0)

    # Steel rails
    for offset in [-0.28, 0.28]:
        box(f"rail_{offset}", w, 0.035, 0.035, (0, offset, 0.12), M_dark_steel())

    # Wooden ties
    for i in range(6):
        tie = box(f"tie_{i}", 0.055, 0.65, 0.025, (-w * 0.42 + i * w * 0.17, 0, 0.075), M_wood())

    # Drain grate
    for i in range(3):
        box(f"grate_{i}", 0.18, 0.01, 0.01, (w * 0.35, -0.04 + i * 0.04, 0.06), M_dark_steel())


def build_garden():
    """1x1 Industrial garden"""
    w = CELL * 0.85

    # Metal planter with riveted look
    planter = box("planter", w, w, 0.38, (0, 0, 0.19), M_rusted())
    bevel_obj(planter, 0.02, 1)

    # Rim
    box("rim", w * 1.02, w * 1.02, 0.05, (0, 0, 0.39), M_brass())

    # Soil
    soil = box("soil", w * 0.88, w * 0.88, 0.08, (0, 0, 0.38), M_oil())
    deform_noise(soil, 0.01, 5.0)

    # Plants - varied organic shapes
    positions = [(-0.22, -0.18), (0.2, 0.15), (-0.08, 0.25), (0.18, -0.22), (0, 0)]
    for i, (px, py) in enumerate(positions):
        h = 0.25 + random.random() * 0.35
        r = 0.08 + random.random() * 0.1
        plant = sphere(f"plant_{i}", r, (px, py, 0.42 + h * 0.5), M_foliage(), 8, 6)
        plant.scale.z = h / r
        bpy.ops.object.transform_apply(scale=True)
        deform_noise(plant, 0.02, 4.0)

    # Gear decoration
    gear = torus("gear", 0.08, 0.015, (w * 0.48, 0, 0.2), M_brass(), 8, 4)
    gear.rotation_euler = (0, math.pi / 2, 0)
    bpy.ops.object.transform_apply(rotation=True)

    # Steam pipe
    pipe("steam", (w * 0.35, w * 0.4, 0.05), (w * 0.35, w * 0.4, 0.65), 0.02, M_copper())
    sphere("valve", 0.03, (w * 0.35, w * 0.4, 0.45), M_brass(), 6, 4)


def build_fountain():
    """1x1 Ornamental dieselpunk fountain"""
    # Base pool - beveled for smooth edges
    pool = cyl("pool", 0.68, 0.22, (0, 0, 0.11), M_stone(), 20, subdiv=1)
    bevel_obj(pool, 0.02, 2)

    # Pool rim
    torus("rim", 0.68, 0.035, (0, 0, 0.24), M_brass(), 20, 8)

    # Water surface
    water = cyl("water", 0.58, 0.03, (0, 0, 0.2), M_water(), 16)

    # Central column - ornate
    col = cyl("col", 0.1, 1.1, (0, 0, 0.75), M_bronze(), 8, subdiv=1)

    # Decorative bands on column
    for h in [0.4, 0.7, 1.0]:
        torus(f"cband_{h}", 0.12, 0.015, (0, 0, h), M_brass(), 8, 6)

    # Gear-shaped spout arms
    for i in range(4):
        angle = i * math.pi / 2
        x, y = 0.22 * math.cos(angle), 0.22 * math.sin(angle)
        arm = box(f"arm_{i}", 0.04, 0.04, 0.12, (x, y, 1.15), M_brass())
        arm.rotation_euler = (0.4 * (1 if i % 2 == 0 else -1), 0, angle)
        bpy.ops.object.transform_apply(rotation=True)
        # Water drip glow
        sphere(f"drip_{i}", 0.025, (x * 1.3, y * 1.3, 1.0), M_water(), 6, 4)

    # Top ornament - small dome
    sphere("top", 0.08, (0, 0, 1.38), M_gold(), 8, 6)
    cone("finial", 0.04, 0.01, 0.12, (0, 0, 1.5), M_gold(), 6)


def build_statue():
    """1x1 Dieselpunk monument"""
    # Art deco pedestal
    base = box("base", 0.65, 0.65, 0.28, (0, 0, 0.14), M_dark_steel())
    bevel_obj(base, 0.03, 2)
    mid = box("mid", 0.5, 0.5, 0.5, (0, 0, 0.53), M_rusted())
    bevel_obj(mid, 0.03, 2)
    top_p = box("top_p", 0.55, 0.55, 0.08, (0, 0, 0.82), M_brass())

    # Gear decorations on pedestal
    for side in range(4):
        angle = side * math.pi / 2
        nx, ny = math.cos(angle), math.sin(angle)
        g = torus(f"gear_{side}", 0.07, 0.012, (nx * 0.26, ny * 0.26, 0.53), M_brass(), 8, 4)
        if abs(nx) > 0.5:
            g.rotation_euler = (0, math.pi / 2, 0)
        else:
            g.rotation_euler = (math.pi / 2, 0, 0)
        bpy.ops.object.transform_apply(rotation=True)

    # Figure body (subdivision for smoother look)
    torso = box("torso", 0.22, 0.16, 0.55, (0, 0, 1.14), M_bronze())
    bevel_obj(torso, 0.02, 2)

    # Head
    head = sphere("head", 0.075, (0, 0, 1.48), M_bronze(), 10, 6)

    # Helmet
    helmet = sphere("helmet", 0.082, (0, 0, 1.52), M_dark_steel(), 10, 5)
    helmet.scale.z = 0.7
    bpy.ops.object.transform_apply(scale=True)

    # Cape/coat tails
    cape = box("cape", 0.18, 0.12, 0.35, (0, 0.06, 0.98), M_dark_steel())
    cape.rotation_euler = (0.15, 0, 0)
    bpy.ops.object.transform_apply(rotation=True)
    deform_noise(cape, 0.01, 4.0)

    # Arms
    for s in [-1, 1]:
        arm = box(f"arm_{s}", 0.055, 0.055, 0.32, (s * 0.15, 0, 1.08), M_bronze())
        arm.rotation_euler = (0, s * 0.35, 0)
        bpy.ops.object.transform_apply(rotation=True)

    # Sword in right hand
    box("sword_hilt", 0.025, 0.025, 0.08, (0.2, 0.04, 1.25), M_gold())
    box("sword_blade", 0.015, 0.015, 0.45, (0.22, 0.04, 1.55), M_dark_steel())

    # Plaque
    box("plaque", 0.02, 0.25, 0.1, (0.26, 0, 0.53), M_brass())


# ============================================================
# MAIN
# ============================================================

BUILDINGS = [
    ("nucleo", build_nucleo),
    ("house", build_house),
    ("sawmill", build_sawmill),
    ("gold_mine", build_gold_mine),
    ("warehouse", build_warehouse),
    ("foundry", build_foundry),
    ("barracks", build_barracks),
    ("refinery", build_refinery),
    ("tower", build_tower),
    ("headquarters", build_headquarters),
    ("road", build_road),
    ("garden", build_garden),
    ("fountain", build_fountain),
    ("statue", build_statue),
]


def generate_all():
    print("=" * 60)
    print("TORMENTA IMPERIAL - Dieselpunk Building Generator v2")
    print("=" * 60)

    for bid, builder in BUILDINGS:
        print(f"\n--- {bid} ---")
        clear_scene()
        builder()

        obj = join_all(bid.capitalize())
        if not obj:
            print(f"  SKIP: {bid} (no geometry)")
            continue

        bpy.ops.object.select_all(action='DESELECT')
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj

        # Shade smooth with auto-smooth
        bpy.ops.object.shade_smooth()

        export_glb(obj, bid)
        print(f"  OK: {bid}")

    print(f"\n{'=' * 60}")
    print(f"DONE! {len(BUILDINGS)} buildings exported to:")
    print(f"  {EXPORT_DIR}")
    print("=" * 60)


generate_all()
