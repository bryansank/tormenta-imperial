"""Build and export all decoration models to Blender."""
import sys
sys.path.insert(0, '.')
from tools.blender_helper import send_to_blender

CODE = r'''
import bpy
from mathutils import Vector
import math

def clear():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=True)
    for b in bpy.data.meshes:
        if b.users == 0: bpy.data.meshes.remove(b)
    for b in bpy.data.materials:
        if b.users == 0: bpy.data.materials.remove(b)

def mat(name, color, metallic=0.0, roughness=0.5):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    for n in m.node_tree.nodes:
        if n.type == 'BSDF_PRINCIPLED':
            n.inputs['Base Color'].default_value = color
            n.inputs['Metallic'].default_value = metallic
            n.inputs['Roughness'].default_value = roughness
    return m

def box(n, l, s, m):
    bpy.ops.mesh.primitive_cube_add(size=1, location=l)
    o=bpy.context.active_object; o.name=n; o.scale=s; o.data.materials.append(m)
def cyl(n, l, r, d, m, v=16):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=d, vertices=v, location=l)
    o=bpy.context.active_object; o.name=n; o.data.materials.append(m)
def sph(n, l, r, m):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, segments=10, ring_count=8, location=l)
    o=bpy.context.active_object; o.name=n; o.data.materials.append(m)

def export(name, path):
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    mesh_objs = [o for o in bpy.data.objects if o.type == 'MESH']
    if mesh_objs:
        bpy.ops.object.select_all(action='DESELECT')
        for o in mesh_objs: o.select_set(True)
        bpy.context.view_layer.objects.active = mesh_objs[0]
        bpy.ops.object.join()
        j = bpy.context.active_object; j.name = name
        bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='BOUNDS')
        bbox = [j.matrix_world @ Vector(c) for c in j.bound_box]
        j.location.z -= min(v.z for v in bbox)
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_apply=True, export_materials='EXPORT')

BASE = r'C:/Users/Key/Documents/1_PERSONAL_KEY/tormenta-imperial/assets/models/buildings'

# ROAD
clear()
M = {}
M['pv'] = mat('RD_Pave', (0.40, 0.40, 0.42, 1), 0.1, 0.9)
M['ed'] = mat('RD_Edge', (0.50, 0.48, 0.42, 1), 0.0, 0.9)
M['mk'] = mat('RD_Mark', (0.80, 0.75, 0.55, 1), 0.0, 0.7)
box('Road', (0,0,0.03), (1.95, 1.95, 0.06), M['pv'])
box('EdgeF', (0, -0.95, 0.05), (1.95, 0.08, 0.08), M['ed'])
box('EdgeB', (0, 0.95, 0.05), (1.95, 0.08, 0.08), M['ed'])
box('EdgeL', (-0.95, 0, 0.05), (0.08, 1.95, 0.08), M['ed'])
box('EdgeR', (0.95, 0, 0.05), (0.08, 1.95, 0.08), M['ed'])
box('Line', (0, 0, 0.065), (0.06, 0.6, 0.01), M['mk'])
export('Road', BASE + '/road/road.glb')
print('Road exported')

# GARDEN
clear()
M = {}
M['gr'] = mat('GD_Grass', (0.25, 0.50, 0.15, 1), 0.0, 0.9)
M['dk'] = mat('GD_DGr', (0.15, 0.35, 0.10, 1), 0.0, 0.8)
M['fl'] = mat('GD_Flower', (0.85, 0.25, 0.40, 1), 0.0, 0.5)
M['yl'] = mat('GD_Yellow', (0.90, 0.80, 0.15, 1), 0.0, 0.5)
M['wd'] = mat('GD_Wood', (0.42, 0.28, 0.14, 1), 0.0, 0.8)
M['cn'] = mat('GD_Stone', (0.55, 0.52, 0.48, 1), 0.0, 0.9)
box('Grass', (0,0,0.03), (1.9, 1.9, 0.06), M['gr'])
box('Path', (0, 0, 0.04), (0.3, 1.6, 0.02), M['cn'])
for pos in [(-0.5, -0.4), (0.5, 0.3), (-0.3, 0.6)]:
    sph(f'Bush_{pos[0]}', (pos[0], pos[1], 0.18), 0.2, M['dk'])
    bpy.context.active_object.scale = (1, 1, 0.7)
for i, pos in enumerate([(-0.6, 0.2), (0.3, -0.5), (0.6, 0.6), (-0.4, -0.6)]):
    sph(f'Flower{i}', (pos[0], pos[1], 0.12), 0.07, M['fl'] if i % 2 == 0 else M['yl'])
for x in [-0.9, -0.45, 0, 0.45, 0.9]:
    box(f'Fence_{x}', (x, -0.9, 0.1), (0.04, 0.04, 0.15), M['wd'])
box('FenceRail', (0, -0.9, 0.14), (1.8, 0.02, 0.02), M['wd'])
cyl('Trunk', (0.55, -0.2, 0.25), 0.06, 0.4, M['wd'], 6)
sph('Canopy', (0.55, -0.2, 0.55), 0.25, M['dk'])
bpy.context.active_object.scale = (1, 1, 0.8)
export('Garden', BASE + '/garden/garden.glb')
print('Garden exported')

# FOUNTAIN
clear()
M = {}
M['st'] = mat('FT_Stone', (0.65, 0.62, 0.55, 1), 0.1, 0.7)
M['wt'] = mat('FT_Water', (0.30, 0.55, 0.70, 1), 0.0, 0.1)
M['br'] = mat('FT_Brass', (0.65, 0.48, 0.12, 1), 0.9, 0.3)
M['cn'] = mat('FT_Concrete', (0.58, 0.55, 0.50, 1), 0.0, 0.9)
M['gd'] = mat('FT_Gold', (0.80, 0.60, 0.10, 1), 1.0, 0.2)
cyl('Platform', (0,0,0.04), 0.9, 0.08, M['cn'], 16)
bpy.ops.mesh.primitive_torus_add(major_radius=0.7, minor_radius=0.12, major_segments=24, minor_segments=8, location=(0,0,0.15))
bpy.context.active_object.name = 'Basin'
bpy.context.active_object.data.materials.append(M['st'])
cyl('Water', (0,0,0.12), 0.62, 0.04, M['wt'], 24)
cyl('Pillar', (0,0,0.35), 0.1, 0.5, M['st'], 8)
cyl('Bowl', (0,0,0.58), 0.2, 0.08, M['br'], 12)
bpy.ops.mesh.primitive_cone_add(radius1=0.03, radius2=0.0, depth=0.3, location=(0,0,0.78))
bpy.context.active_object.name = 'Jet'
bpy.context.active_object.data.materials.append(M['wt'])
for i in range(4):
    a = i * math.pi * 0.5
    x, y = math.sin(a) * 0.7, math.cos(a) * 0.7
    sph(f'Acc_{i}', (x, y, 0.15), 0.06, M['gd'])
export('Fountain', BASE + '/fountain/fountain.glb')
print('Fountain exported')

# STATUE
clear()
M = {}
M['st'] = mat('ST_Stone', (0.55, 0.52, 0.48, 1), 0.1, 0.8)
M['br'] = mat('ST_Bronze', (0.50, 0.35, 0.12, 1), 0.8, 0.4)
M['gd'] = mat('ST_Gold', (0.85, 0.65, 0.12, 1), 1.0, 0.2)
M['cn'] = mat('ST_Concrete', (0.58, 0.55, 0.50, 1), 0.0, 0.9)
M['dk'] = mat('ST_Dark', (0.20, 0.18, 0.15, 1), 0.5, 0.6)
box('Platform', (0,0,0.06), (1.5, 1.5, 0.12), M['cn'])
box('Pedestal', (0,0,0.35), (0.8, 0.8, 0.5), M['st'])
box('PedTop', (0,0,0.62), (0.9, 0.9, 0.06), M['st'])
box('PedBot', (0,0,0.12), (0.9, 0.9, 0.06), M['st'])
cyl('Body', (0,0,1.0), 0.18, 0.65, M['br'], 8)
sph('Head', (0,0,1.4), 0.12, M['br'])
box('ArmL', (-0.22, 0, 1.05), (0.3, 0.08, 0.08), M['br'])
box('ArmR', (0.22, 0, 1.05), (0.3, 0.08, 0.08), M['br'])
box('ArmUp', (0.25, 0, 1.2), (0.08, 0.08, 0.3), M['br'])
sph('Eagle', (0.25, 0, 1.42), 0.08, M['gd'])
box('Plaque', (0, -0.42, 0.35), (0.5, 0.04, 0.2), M['gd'])
for x, y in [(-0.6,-0.6), (0.6,-0.6), (-0.6,0.6), (0.6,0.6)]:
    cyl(f'Bollard_{x}_{y}', (x, y, 0.12), 0.04, 0.18, M['dk'], 6)
export('Statue', BASE + '/statue/statue.glb')
print('Statue exported')
'''

import json
result = send_to_blender(CODE, timeout=60)
print(json.dumps(result, indent=2))
