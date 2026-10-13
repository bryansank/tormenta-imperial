extends Node3D
## Las figuras de WorkerWalkers en 3D: un MultiMesh por silueta (obrero con
## casco, ciudadano con sombrero, ciudadana con falda y mono, nino con gorra).
##
## Cada silueta es UNA malla hecha de primitivas fundidas; la coordenada UV.x
## de cada vertice dice que parte es (0 cuerpo, 1 piel, 2 casco/sombrero/pelo)
## y el shader la pinta con los colores de esa figura: el del cuerpo va en el
## color de instancia y el del accesorio + el tono de piel en el dato propio.
## Cuatro llamadas de dibujo para toda la isla, haya 5 figuras o 70. Por
## fotograma solo se escriben las matrices de las figuras en la calle.

const SHADER_CODE := """
shader_type spatial;
render_mode cull_back, specular_disabled;
uniform vec3 skin_light : source_color = vec3(0.90, 0.74, 0.60);
uniform vec3 skin_dark : source_color = vec3(0.46, 0.31, 0.22);
varying vec3 v_albedo;
void vertex() {
	float part = UV.x;
	vec3 skin = mix(skin_light, skin_dark, INSTANCE_CUSTOM.a);
	v_albedo = part < 0.5 ? COLOR.rgb : (part < 1.5 ? skin : INSTANCE_CUSTOM.rgb);
}
void fragment() {
	ALBEDO = v_albedo;
	ROUGHNESS = 0.85;
}
"""

const Actor := preload("res://scripts/map/WalkerActor.gd")

const BODY := 0.0
const SKIN := 1.0
const ACCENT := 2.0

var _mms: Array = []          # un MultiMesh por Kind
var _bufs: Array = []         # su buffer (PackedFloat32Array), reutilizado
var _slots: Array = []        # quien ocupa cada hueco del buffer (por Kind)
var _cap := 0
## Floats por figura en el buffer: 12 de matriz, 4 de color, 4 de dato propio.
const STRIDE := 20

static var _shader: Shader = null
static var _meshes: Array = []

func setup(cap: int) -> void:
	_cap = maxi(1, cap)
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	if _meshes.is_empty():
		_meshes = [_worker_mesh(), _man_mesh(), _woman_mesh(), _child_mesh()]
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	# En tableta y movil sin sombra: ahorra un pase por figura en el Mobile.
	var shadows: bool = DeviceProfile.current() == DeviceProfile.PC
	for k in _meshes.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = _meshes[k]
		mm.instance_count = _cap
		mm.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Kind%d" % k
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		_mms.append(mm)
		var buf := PackedFloat32Array()
		buf.resize(_cap * STRIDE)
		_bufs.append(buf)
		var slots: Array = []
		slots.resize(_cap)
		_slots.append(slots)

## Las figuras en la calle, cada una en el MultiMesh de su silueta. Se
## escribe el buffer entero de cada MultiMesh (una llamada por silueta), no
## tres llamadas por figura.
func render(actors: Array) -> void:
	if _mms.is_empty():
		return
	var origin: Vector3 = GridManager.get_origin()
	var cs: float = GridManager.cell_size
	for k in _mms.size():
		# El buffer se saca de la lista mientras se escribe: un PackedFloat32Array
		# con dos duenos se copiaria entero en cada escritura.
		var buf: PackedFloat32Array = _bufs[k]
		_bufs[k] = PackedFloat32Array()
		var slots: Array = _slots[k]
		var i := 0
		for a: Actor in actors:
			if not a.out or a.kind != k or i >= _cap:
				continue
			var walking := a.state == Actor.WALKING
			var ph := a.phase
			# Balanceo de la caminata: un saltito y un vaiven de lado a lado.
			var bob := absf(sin(ph)) * 0.07 if walking else 0.0
			var sway := sin(ph) * 0.09 if walking else 0.0
			var s := maxf(0.001, a.scale)
			# Giro hacia donde anda (Y) por el vaiven (Z), escalado, sin crear
			# Basis: filas de Ry(yaw) * Rz(sway) * s.
			var yaw := atan2(a.dir.x, a.dir.y)
			var cy := cos(yaw) * s
			var sy := sin(yaw) * s
			var cz := cos(sway)
			var sz := sin(sway)
			var p := a.pos
			var o := i * STRIDE
			i += 1
			# Formato del buffer: la matriz por filas (3x4) + color + dato propio.
			buf[o] = cy * cz; buf[o + 1] = -cy * sz; buf[o + 2] = sy; buf[o + 3] = origin.x + p.x * cs
			buf[o + 4] = sz * s; buf[o + 5] = cz * s; buf[o + 6] = 0.0; buf[o + 7] = bob
			buf[o + 8] = -sy * cz; buf[o + 9] = sy * sz; buf[o + 10] = cy; buf[o + 11] = origin.z + p.y * cs
			# Los colores solo cambian cuando cambia quien ocupa el hueco.
			if slots[i - 1] != a:
				slots[i - 1] = a
				var c := a.body
				buf[o + 12] = c.r; buf[o + 13] = c.g; buf[o + 14] = c.b; buf[o + 15] = 1.0
				var acc := a.accent
				buf[o + 16] = acc.r; buf[o + 17] = acc.g; buf[o + 18] = acc.b; buf[o + 19] = a.skin
		var mm: MultiMesh = _mms[k]
		if i > 0 or mm.visible_instance_count > 0:
			mm.buffer = buf
		mm.visible_instance_count = i
		_bufs[k] = buf

func visible_count() -> int:
	var n := 0
	for mm in _mms:
		n += (mm as MultiMesh).visible_instance_count
	return n

# ── Siluetas ─────────────────────────────────────────────────────────────

static func _capsule(r: float, h: float) -> PrimitiveMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 8
	m.rings = 2
	return m

static func _sphere(r: float) -> PrimitiveMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 8
	m.rings = 4
	return m

static func _cyl(top: float, bottom: float, h: float) -> PrimitiveMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = 8
	m.rings = 1
	return m

## Funde las piezas [[malla, posicion, parte], ...] en una sola malla.
static func _merge(parts: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for p in parts:
		var arrays: Array = (p[0] as PrimitiveMesh).get_mesh_arrays()
		var off: Vector3 = p[1]
		var part: float = p[2]
		var base := verts.size()
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for j in v.size():
			verts.append(v[j] + off)
			normals.append(n[j])
			uvs.append(Vector2(part, 0.0))
		var ii: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for j in ii.size():
			idx.append(ii[j] + base)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_TEX_UV] = uvs
	out[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return mesh

static func _worker_mesh() -> ArrayMesh:
	return _merge([
		[_capsule(0.16, 0.60), Vector3(0, 0.30, 0), BODY],
		[_sphere(0.12), Vector3(0, 0.72, 0), SKIN],
		[_cyl(0.10, 0.155, 0.08), Vector3(0, 0.83, 0), ACCENT],
		# La caja de herramientas a la espalda.
		[_cyl(0.07, 0.07, 0.2), Vector3(0, 0.44, -0.15), ACCENT],
	])

static func _man_mesh() -> ArrayMesh:
	return _merge([
		[_capsule(0.15, 0.62), Vector3(0, 0.31, 0), BODY],
		[_sphere(0.115), Vector3(0, 0.74, 0), SKIN],
		[_cyl(0.16, 0.16, 0.02), Vector3(0, 0.83, 0), ACCENT],
		[_cyl(0.085, 0.095, 0.16), Vector3(0, 0.92, 0), ACCENT],
	])

static func _woman_mesh() -> ArrayMesh:
	return _merge([
		[_cyl(0.09, 0.21, 0.44), Vector3(0, 0.22, 0), BODY],
		[_capsule(0.1, 0.34), Vector3(0, 0.52, 0), BODY],
		[_sphere(0.11), Vector3(0, 0.76, 0), SKIN],
		[_sphere(0.075), Vector3(0, 0.82, -0.08), ACCENT],
		[_cyl(0.105, 0.12, 0.05), Vector3(0, 0.84, -0.01), ACCENT],
	])

static func _child_mesh() -> ArrayMesh:
	return _merge([
		[_capsule(0.11, 0.38), Vector3(0, 0.19, 0), BODY],
		[_sphere(0.1), Vector3(0, 0.47, 0), SKIN],
		[_cyl(0.09, 0.105, 0.05), Vector3(0, 0.56, 0), ACCENT],
	])
