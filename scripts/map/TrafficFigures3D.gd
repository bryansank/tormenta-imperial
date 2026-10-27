extends Node3D
## Los camiones de RoadTraffic en 3D: UN MultiMesh con UNA malla de camion
## diesel de juguete (cabina redondeada, morro con rejilla, caja de carga,
## cuatro ruedas gordas y el tubo de escape), hecha de primitivas fundidas.
##
## Como las figuras de la gente (WalkerFigures3D), la coordenada UV.x de cada
## vertice dice que parte es (0 pintura de la cabina, 1 chasis y ruedas, 2 la
## carga, 3 faros y ventanilla) y el shader la pinta: la pintura va en el color
## de instancia y la carga en el dato propio; con el dato propio .a = 0 (vuelve
## vacio) la carga se aplasta contra la caja y no se ve. Una llamada de dibujo
## para todos los camiones (mas la sombra en PC), sin luces ni texturas. Por
## fotograma solo se escriben las matrices de los que estan en la carretera.
## ~330 triangulos por camion.

const SHADER_CODE := """
shader_type spatial;
render_mode cull_back, specular_disabled;
uniform vec3 chassis = vec3(0.16, 0.13, 0.12);
uniform vec3 lamp = vec3(1.0, 0.86, 0.5);
uniform float bed_top = 0.42;
uniform bool vc_srgb = false;
varying vec3 v_albedo;
void vertex() {
	float part = UV.x;
	if (part > 1.5 && part < 2.5 && INSTANCE_CUSTOM.a < 0.5) {
		// Vuelve vacio: la carga se aplasta dentro de la caja.
		VERTEX.y = min(VERTEX.y, bed_top - 0.01);
	}
	v_albedo = part < 0.5 ? COLOR.rgb : (part < 1.5 ? chassis : (part < 2.5 ? INSTANCE_CUSTOM.rgb : lamp));
}
void fragment() {
	vec3 c = v_albedo;
	if (vc_srgb) {
		c = mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
	}
	ALBEDO = c;
	ROUGHNESS = 0.78;
}
"""

const Truck := preload("res://scripts/map/TruckActor.gd")
const Tone := preload("res://scripts/buildings/ToyTones.gd")

const PAINT := 0.0
const CHASSIS := 1.0
const CARGO := 2.0
const LAMP := 3.0
## Algo mayor que a escala (como las figuritas): se lee de lejos.
const TRUCK_SCALE := 1.0
## Floats por camion en el buffer: 12 de matriz, 4 de color, 4 de dato propio.
const STRIDE := 20

var _mm: MultiMesh = null
var _buf := PackedFloat32Array()
var _cap := 0

static var _shader: Shader = null
static var _mesh: ArrayMesh = null

func setup(cap: int) -> void:
	_cap = maxi(1, cap)
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	if _mesh == null:
		_mesh = truck_mesh()
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	var ch := Tone.of("iron")
	mat.set_shader_parameter("chassis", Vector3(ch.r, ch.g, ch.b))
	mat.set_shader_parameter("vc_srgb", Tone.vertex_color_is_srgb())
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = _mesh
	_mm.instance_count = _cap
	_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "TruckLayer"
	mmi.multimesh = _mm
	mmi.material_override = mat
	# En tableta y movil sin sombra: ahorra un pase en el Mobile.
	var shadows: bool = DeviceProfile.current() == DeviceProfile.PC
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	_buf.resize(_cap * STRIDE)

## Los camiones en la carretera, en el buffer del MultiMesh (una escritura).
func render(trucks: Array) -> void:
	if _mm == null:
		return
	var origin: Vector3 = GridManager.get_origin()
	var cs: float = GridManager.cell_size
	var buf := _buf
	_buf = PackedFloat32Array()
	var i := 0
	for t: Truck in trucks:
		if not t.out or i >= _cap:
			continue
		var s := maxf(0.001, t.scale)
		var yaw := atan2(t.dir.x, t.dir.y)
		var cy := cos(yaw) * s
		var sy := sin(yaw) * s
		var o := i * STRIDE
		i += 1
		buf[o] = cy; buf[o + 1] = 0.0; buf[o + 2] = sy; buf[o + 3] = origin.x + t.pos.x * cs
		buf[o + 4] = 0.0; buf[o + 5] = s; buf[o + 6] = 0.0; buf[o + 7] = 0.0
		buf[o + 8] = -sy; buf[o + 9] = 0.0; buf[o + 10] = cy; buf[o + 11] = origin.z + t.pos.y * cs
		var c := t.paint
		buf[o + 12] = c.r; buf[o + 13] = c.g; buf[o + 14] = c.b; buf[o + 15] = 1.0
		# La carga cambia en cada viaje (llena / vacia): se escribe siempre.
		var k := t.cargo
		buf[o + 16] = k.r; buf[o + 17] = k.g; buf[o + 18] = k.b; buf[o + 19] = 1.0 if t.loaded else 0.0
	if i > 0 or _mm.visible_instance_count > 0:
		_mm.buffer = buf
	_mm.visible_instance_count = i
	_buf = buf

func visible_count() -> int:
	return _mm.visible_instance_count if _mm != null else 0

# ── La malla ─────────────────────────────────────────────────────────────

static func _box(size: Vector3) -> PrimitiveMesh:
	var m := BoxMesh.new()
	m.size = size
	return m

static func _wheel(r: float, w: float) -> PrimitiveMesh:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = w
	m.radial_segments = 8
	m.rings = 1
	return m

static func _cyl(r: float, h: float) -> PrimitiveMesh:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	m.radial_segments = 6
	m.rings = 1
	return m

## El camion: frente hacia +Z (por donde avanza), base en y = 0. Unos 1,4 m de
## largo y 0,7 de ancho: cabe de sobra en el carril de una calzada de 2 m.
## [malla, posicion, parte, giro en Z (rad)].
static func truck_mesh() -> ArrayMesh:
	var parts := [
		# Chasis y parachoques.
		[_box(Vector3(0.58, 0.12, 1.36)), Vector3(0, 0.22, 0), CHASSIS, 0.0],
		[_box(Vector3(0.66, 0.08, 0.08)), Vector3(0, 0.22, 0.7), CHASSIS, 0.0],
		# Morro (el capo largo del diesel) con su rejilla.
		[_box(Vector3(0.52, 0.26, 0.34)), Vector3(0, 0.41, 0.48), PAINT, 0.0],
		[_box(Vector3(0.36, 0.2, 0.03)), Vector3(0, 0.42, 0.66), CHASSIS, 0.0],
		# Cabina con techo y ventanilla.
		[_box(Vector3(0.6, 0.42, 0.36)), Vector3(0, 0.5, 0.16), PAINT, 0.0],
		[_box(Vector3(0.64, 0.05, 0.42)), Vector3(0, 0.73, 0.16), PAINT, 0.0],
		[_box(Vector3(0.5, 0.15, 0.02)), Vector3(0, 0.58, 0.345), LAMP, 0.0],
		# Faros.
		[_box(Vector3(0.1, 0.08, 0.04)), Vector3(0.2, 0.4, 0.665), LAMP, 0.0],
		[_box(Vector3(0.1, 0.08, 0.04)), Vector3(-0.2, 0.4, 0.665), LAMP, 0.0],
		# Escape vertical tras la cabina.
		[_cyl(0.035, 0.42), Vector3(0.27, 0.68, -0.04), CHASSIS, 0.0],
		# Caja de carga: suelo y tres tablas (abierta por arriba).
		[_box(Vector3(0.62, 0.06, 0.66)), Vector3(0, 0.31, -0.33), PAINT, 0.0],
		[_box(Vector3(0.04, 0.16, 0.66)), Vector3(0.3, 0.42, -0.33), PAINT, 0.0],
		[_box(Vector3(0.04, 0.16, 0.66)), Vector3(-0.3, 0.42, -0.33), PAINT, 0.0],
		[_box(Vector3(0.62, 0.16, 0.04)), Vector3(0, 0.42, -0.65), PAINT, 0.0],
		# La carga: un monton que asoma (troncos, pepitas, lingotes, bidones...
		# todo se lee como un bulto del color del recurso).
		[_box(Vector3(0.54, 0.3, 0.58)), Vector3(0, 0.49, -0.33), CARGO, 0.0],
		[_box(Vector3(0.4, 0.12, 0.44)), Vector3(0, 0.68, -0.33), CARGO, 0.0],
	]
	# Cuatro ruedas gordas (el eje en X).
	for x in [-0.3, 0.3]:
		for z in [0.42, -0.42]:
			parts.append([_wheel(0.16, 0.12), Vector3(x, 0.16, z), CHASSIS, PI * 0.5])
	return _merge(parts)

static func _merge(parts: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for p in parts:
		var arrays: Array = (p[0] as PrimitiveMesh).get_mesh_arrays()
		var off: Vector3 = p[1]
		var part: float = p[2]
		var b := Basis(Vector3(0, 0, 1), float(p[3]))
		var base := verts.size()
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for j in v.size():
			verts.append((b * v[j] + off) * TRUCK_SCALE)
			normals.append(b * n[j])
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
