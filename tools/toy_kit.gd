extends RefCounted
## Caja de herramientas del horneado de modelos "maqueta" (tools/build_toy_models.gd).
##
## Carga piezas CC0 (glTF/GLB de assets/models/cc0/<pack>/, carpetas con
## .gdignore: Godot no las importa ni las exporta, son solo la fuente del
## horneado), muestrea su atlas en cada vertice y lo pasa a la paleta comun
## (ToyPalette). Las coloca en un LotMesh junto con piezas propias (cajas,
## cilindros, vigas) y todo sale como UNA malla con color por vertice.
##
## No corre en el juego: el juego solo carga lo horneado (.res / .tscn).

const Palette := preload("res://scripts/buildings/ToyPalette.gd")
const MeshKit := preload("res://scripts/buildings/LotMesh.gd")

const PACKS := {
	"kk": "res://assets/models/cc0/kaykit_medieval_hexagon/",
	"kn": "res://assets/models/cc0/kenney_city_kit_industrial/",
	"kc": "res://assets/models/cc0/kaykit_city_builder_bits/",
	# Kenney Fantasy Town y Pirate (feat/edificios-utiles-1): solo las piezas que
	# usan las recetas (aspas del Molino, farol, torre del Faro, bandera, barril).
	"ft": "res://assets/models/cc0/kenney_fantasy_town_kit/",
	"sur": "res://assets/models/cc0/kenney_survival_kit/",
	"pir": "res://assets/models/cc0/kenney_pirate_kit/",
}

## nombre ("kk:barrel") -> {"v", "n", "slot", "d", "aabb"} (triangulos sueltos).
var _cache := {}

static func P(slot: int) -> Color:
	return Palette.color(slot)

func piece_path(piece: String) -> String:
	var pack := piece.get_slice(":", 0)
	var file := piece.get_slice(":", 1)
	var dir: String = PACKS[pack]
	var abs_dir := ProjectSettings.globalize_path(dir)
	for ext in [".gltf", ".glb"]:
		if FileAccess.file_exists(abs_dir + file + ext):
			return abs_dir + file + ext
	push_error("toy_kit: no existe la pieza " + piece)
	return ""

## La pieza, cargada y pasada a la paleta (cacheada).
func piece(name: String) -> Dictionary:
	if _cache.has(name):
		return _cache[name]
	var out := {"v": PackedVector3Array(), "n": PackedVector3Array(), "slot": PackedByteArray(), "d": PackedFloat32Array(), "aabb": AABB()}
	var path := piece_path(name)
	if path == "":
		_cache[name] = out
		return out
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_file(path, st, 0, path.get_base_dir())
	if err != OK:
		push_error("toy_kit: no carga %s (%d)" % [path, err])
		_cache[name] = out
		return out
	var scene := doc.generate_scene(st) as Node3D
	_collect(scene, Transform3D.IDENTITY, out)
	scene.free()
	var first := true
	var box := AABB()
	for p in out["v"]:
		if first:
			box = AABB(p, Vector3.ZERO)
			first = false
		else:
			box = box.expand(p)
	out["aabb"] = box
	_cache[name] = out
	return out

func _collect(node: Node, xf: Transform3D, out: Dictionary) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mi := node as MeshInstance3D
		var mesh: Mesh = mi.mesh
		for s in mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			_add_surface(mesh.surface_get_arrays(s), mat, xf, out)
	for c in node.get_children():
		if c is Node3D:
			_collect(c, xf * (c as Node3D).transform, out)

var _images := {}

func _image_of(mat: Material) -> Image:
	if not (mat is BaseMaterial3D):
		return null
	var tex := (mat as BaseMaterial3D).albedo_texture
	if tex == null:
		return null
	var key := tex.get_rid().get_id()
	if _images.has(key):
		return _images[key]
	var img := tex.get_image()
	if img != null and img.is_compressed():
		img.decompress()
	_images[key] = img
	return img

func _add_surface(arrays: Array, mat: Material, xf: Transform3D, out: Dictionary) -> void:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms = arrays[Mesh.ARRAY_NORMAL]
	var uvs = arrays[Mesh.ARRAY_TEX_UV]
	var idx = arrays[Mesh.ARRAY_INDEX]
	var img := _image_of(mat)
	var base_col := Color.WHITE
	if mat is BaseMaterial3D:
		base_col = (mat as BaseMaterial3D).albedo_color
	var order: PackedInt32Array
	if idx != null and (idx as PackedInt32Array).size() > 0:
		order = idx
	else:
		order = PackedInt32Array(range(verts.size()))
	var nb := xf.basis.inverse().transposed()
	for i in order:
		out["v"].append(xf * verts[i])
		var n := Vector3.UP
		if norms != null and (norms as PackedVector3Array).size() > i:
			n = (nb * (norms as PackedVector3Array)[i]).normalized()
		out["n"].append(n)
		var c := base_col
		if img != null and uvs != null and (uvs as PackedVector2Array).size() > i:
			var uv: Vector2 = (uvs as PackedVector2Array)[i]
			var px := clampi(int(fposmod(uv.x, 1.0) * img.get_width()), 0, img.get_width() - 1)
			var py := clampi(int(fposmod(uv.y, 1.0) * img.get_height()), 0, img.get_height() - 1)
			c = img.get_pixel(px, py) * base_col
		out["slot"].append(Palette.slot_of(c))
		out["d"].append(Palette.shade(c))

## Coloca `name` en `mk` con la transformacion `xf` (sobre la de mk). `opts`:
## - "map": {Slot origen: Slot destino} para recolorear (p. ej. el tejado);
## - "tint": Color que multiplica todo (variantes sutiles);
## - "noglow": las ventanas no se encienden (van a IRON);
## - "only": Array de Slots: solo los triangulos de esas casillas;
## - "skip": Array de Slots: sin los triangulos de esas casillas.
func add(mk, name: String, xf: Transform3D, opts := {}) -> void:
	var p := piece(name)
	var v: PackedVector3Array = p["v"]
	var n: PackedVector3Array = p["n"]
	var slots: PackedByteArray = p["slot"]
	var ds: PackedFloat32Array = p["d"]
	var remap: Dictionary = opts.get("map", {})
	var tint: Color = opts.get("tint", Color.WHITE)
	var noglow := bool(opts.get("noglow", false))
	var only: Array = opts.get("only", [])
	var skip: Array = opts.get("skip", [])
	var sv := PackedVector3Array()
	var sn := PackedVector3Array()
	var sc := PackedColorArray()
	var gv := PackedVector3Array()
	var gn := PackedVector3Array()
	var gc := PackedColorArray()
	var i := 0
	while i + 2 < v.size():
		var tri_slot := int(slots[i])
		if (not only.is_empty() and not only.has(tri_slot)) or skip.has(tri_slot):
			i += 3
			continue
		var glow := true
		for k in 3:
			var sl := int(remap.get(int(slots[i + k]), int(slots[i + k])))
			if sl != Palette.Slot.GLOW or noglow:
				glow = false
		for k in 3:
			var sl := int(remap.get(int(slots[i + k]), int(slots[i + k])))
			if sl == Palette.Slot.GLOW and (noglow or not glow):
				sl = Palette.Slot.IRON
			var col := Palette.tint(sl, ds[i + k])
			if not glow:
				col = Color(col.r * tint.r, col.g * tint.g, col.b * tint.b)
			if glow:
				gv.append(v[i + k]); gn.append(n[i + k]); gc.append(col)
			else:
				sv.append(v[i + k]); sn.append(n[i + k]); sc.append(col)
		i += 3
	var saved: Transform3D = mk.xf
	mk.xf = saved * xf
	if not sv.is_empty():
		mk.append(sv, sn, sc, false)
	if not gv.is_empty():
		mk.append(gv, gn, gc, true)
	mk.xf = saved

func aabb(name: String) -> AABB:
	return piece(name)["aabb"]

## La transformacion que deja la pieza apoyada en `pos` (su base en pos.y,
## centrada en planta), girada `rot_deg` y escalada: `size` es el lado mayor en
## planta que se quiere (o `scale` directo si size <= 0). `stretch` estira por eje.
func fit(name: String, pos: Vector3, size: float, rot_deg := 0.0, scale := 1.0, stretch := Vector3.ONE) -> Transform3D:
	var a := aabb(name)
	var s := scale
	if size > 0.0:
		s = size / maxf(0.001, maxf(a.size.x, a.size.z))
	var basis := Basis(Vector3.UP, deg_to_rad(rot_deg)) * Basis.from_scale(stretch * s)
	var c := a.get_center()
	var anchor := Vector3(c.x, a.position.y, c.z)
	return Transform3D(basis, pos - basis * anchor)

## Atajo: coloca la pieza con `fit()` y la anade.
func put(mk, name: String, pos: Vector3, size: float, rot_deg := 0.0, opts := {}) -> Transform3D:
	var xf := fit(name, pos, size, rot_deg, float(opts.get("scale", 1.0)), opts.get("stretch", Vector3.ONE))
	add(mk, name, xf, opts)
	return xf

## Histograma de casillas de la pieza (para el modo --dump).
func histogram(name: String) -> Dictionary:
	var h := {}
	for s in piece(name)["slot"]:
		var k: String = Palette.NAMES[int(s)]
		h[k] = int(h.get(k, 0)) + 1
	return h

static func tri_count(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var t := 0
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var idx = arr[Mesh.ARRAY_INDEX]
		if idx != null and (idx as PackedInt32Array).size() > 0:
			t += (idx as PackedInt32Array).size() / 3
		else:
			t += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return t
