extends Node3D
## Las marcas de las amenazas de costa en el mapa 3D (feat/amenazas-costa).
## Solo vista: lee ThreatManager y se rehace con EventBus.threats_changed, nunca
## por fotograma (sin _process).
##
## Arte propio, de juguete y barato: cada tipo es UNA malla hecha con cajas y
## color por vertice (una llamada de dibujo por marca, como mucho 2-3 a la vez),
## guardada en cache por tipo y medio, con un material compartido.
##   saqueadores en la playa: bote varado, mastil con bandera pirata, hoguera y cajas;
##   saqueadores en el agua: el bote a flote con su bandera;
##   avanzadilla de la Regencia: tienda, estandarte morado y sacos terreros;
##   pecio: casco roto y ladeado, cuadernas y el mastil partido.
## Al tocarla (los placers preguntan a ThreatManager.threat_at_cell) sale su
## tarjeta (ThreatCard).

const Generator := preload("res://scripts/combat/ExpeditionGenerator.gd")
## A la altura del agua de IslandGenerator (WATER_Y): el bote flota.
const WATER_Y := -0.5

static var _mesh_cache: Dictionary = {}
static var _material: StandardMaterial3D = null

## threat_id -> MeshInstance3D
var _marks: Dictionary = {}

func _ready() -> void:
	EventBus.threats_changed.connect(sync)
	EventBus.grid_resized.connect(func(_w, _h): sync())
	sync.call_deferred()

## Pone, mueve o quita las marcas para que coincidan con las amenazas vivas.
func sync() -> void:
	if not is_inside_tree():
		return
	var alive: Dictionary = {}
	for threat in ThreatManager.get_threats():
		var id: int = int(threat.get("id", 0))
		alive[id] = true
		var mark: MeshInstance3D = _marks.get(id, null)
		if mark == null or not is_instance_valid(mark):
			mark = MeshInstance3D.new()
			mark.name = "Threat_%d" % id
			mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mark)
			_marks[id] = mark
		var water: bool = bool(threat.get("water", false))
		mark.mesh = mesh_for(String(threat.get("type", "")), water)
		mark.material_override = _shared_material()
		var cell: Vector2i = threat.get("cell", Vector2i.ZERO)
		var pos: Vector3 = GridManager.building_center(cell, Vector2i.ONE)
		pos.y = WATER_Y if water else 0.0
		# Un giro fijo por marca (de su semilla): no todas miran igual.
		var yaw: float = float(absi(int(threat.get("seed", 0))) % 360) * PI / 180.0
		mark.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	for id in _marks.keys():
		if not alive.has(id):
			var old: Node = _marks[id]
			if is_instance_valid(old):
				old.queue_free()
			_marks.erase(id)

## Cuantas marcas hay pintadas (para pruebas).
func mark_count() -> int:
	return _marks.size()

static func _shared_material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.roughness = 0.9
		# Las cajas no cuidan el sentido de sus caras: sin recorte, siempre se ven.
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _material

## La malla de un tipo (en cache). Tamano pensado para una casilla de 2 m.
static func mesh_for(threat_type: String, water: bool) -> ArrayMesh:
	var key := "%s_%s" % [threat_type, "sea" if water else "land"]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	match threat_type:
		Generator.THREAT_VANGUARD:
			_build_vanguard(st)
		Generator.THREAT_WRECK:
			_build_wreck(st)
		_:
			_build_raiders(st, water)
	var mesh: ArrayMesh = st.commit()
	_mesh_cache[key] = mesh
	return mesh

# ── Piezas ───────────────────────────────────────────────────────────

const WOOD_DARK := Color(0.33, 0.21, 0.12)
const WOOD := Color(0.52, 0.35, 0.2)
const WOOD_LIGHT := Color(0.66, 0.5, 0.32)
const FLAG_BLACK := Color(0.08, 0.08, 0.09)
const BONE := Color(0.92, 0.9, 0.82)
const FIRE := Color(0.98, 0.55, 0.12)
const CANVAS := Color(0.72, 0.68, 0.6)
const REGENCY := Color(0.42, 0.16, 0.5)
const BRASS := Color(0.78, 0.62, 0.28)
const SAND := Color(0.68, 0.6, 0.42)

static func _build_raiders(st: SurfaceTool, water: bool) -> void:
	# El bote: casco oscuro, borda clara y dos bancos.
	var tilt := Basis() if water else Basis(Vector3.FORWARD, 0.12)
	_box(st, Vector3(0, 0.2, 0), Vector3(1.5, 0.3, 0.62), WOOD_DARK, tilt)
	_box(st, Vector3(0, 0.37, 0.28), Vector3(1.5, 0.06, 0.07), WOOD_LIGHT, tilt)
	_box(st, Vector3(0, 0.37, -0.28), Vector3(1.5, 0.06, 0.07), WOOD_LIGHT, tilt)
	_box(st, Vector3(0.82, 0.25, 0), Vector3(0.22, 0.24, 0.42), WOOD_DARK, tilt)
	_box(st, Vector3(-0.25, 0.36, 0), Vector3(0.1, 0.04, 0.5), WOOD, tilt)
	_box(st, Vector3(0.3, 0.36, 0), Vector3(0.1, 0.04, 0.5), WOOD, tilt)
	# Mastil con la bandera pirata (negra con la calavera blanca).
	_box(st, Vector3(0.05, 1.05, 0), Vector3(0.07, 1.5, 0.07), WOOD, Basis())
	_box(st, Vector3(0.38, 1.55, 0), Vector3(0.6, 0.4, 0.03), FLAG_BLACK, Basis())
	_box(st, Vector3(0.38, 1.58, 0.025), Vector3(0.16, 0.14, 0.02), BONE, Basis())
	_box(st, Vector3(0.38, 1.47, 0.025), Vector3(0.24, 0.04, 0.02), BONE, Basis(Vector3.BACK, 0.5))
	if water:
		return
	# En la playa: una hoguera y dos cajas del saqueo.
	_box(st, Vector3(-0.55, 0.06, 0.75), Vector3(0.36, 0.08, 0.36), WOOD_DARK, Basis(Vector3.UP, 0.6))
	_box(st, Vector3(-0.55, 0.16, 0.75), Vector3(0.16, 0.18, 0.16), FIRE, Basis(Vector3.UP, 0.2))
	_box(st, Vector3(0.6, 0.15, 0.8), Vector3(0.3, 0.3, 0.3), WOOD_LIGHT, Basis(Vector3.UP, 0.3))
	_box(st, Vector3(0.85, 0.12, 0.55), Vector3(0.24, 0.24, 0.24), WOOD, Basis(Vector3.UP, -0.4))

static func _build_vanguard(st: SurfaceTool) -> void:
	# La tienda: dos faldones inclinados y la cumbrera.
	_box(st, Vector3(0, 0.38, 0.24), Vector3(1.1, 0.06, 0.62), CANVAS, Basis(Vector3.RIGHT, 0.85))
	_box(st, Vector3(0, 0.38, -0.24), Vector3(1.1, 0.06, 0.62), CANVAS, Basis(Vector3.RIGHT, -0.85))
	_box(st, Vector3(0, 0.62, 0), Vector3(1.16, 0.06, 0.06), WOOD_DARK, Basis())
	# Estandarte de la Regencia: asta alta, pano morado y remate de laton.
	_box(st, Vector3(0.75, 1.0, -0.5), Vector3(0.07, 2.0, 0.07), WOOD_DARK, Basis())
	_box(st, Vector3(0.75, 1.55, -0.32), Vector3(0.03, 0.7, 0.34), REGENCY, Basis())
	_box(st, Vector3(0.75, 1.42, -0.32), Vector3(0.035, 0.1, 0.22), BRASS, Basis())
	_box(st, Vector3(0.75, 2.04, -0.5), Vector3(0.14, 0.1, 0.14), BRASS, Basis())
	# Sacos terreros delante y una caja de municion.
	for i in range(3):
		_box(st, Vector3(-0.5 + 0.38 * i, 0.1, 0.8), Vector3(0.34, 0.2, 0.22), SAND, Basis(Vector3.UP, 0.08 * (i - 1)))
	_box(st, Vector3(-0.8, 0.14, -0.6), Vector3(0.36, 0.28, 0.26), REGENCY.darkened(0.3), Basis(Vector3.UP, 0.4))

static func _build_wreck(st: SurfaceTool) -> void:
	# Casco ladeado y medio enterrado en la arena.
	var lean := Basis(Vector3.RIGHT, 0.45) * Basis(Vector3.FORWARD, -0.1)
	_box(st, Vector3(0, 0.15, 0), Vector3(1.7, 0.35, 0.7), WOOD_DARK, lean)
	_box(st, Vector3(0.95, 0.22, 0.02), Vector3(0.3, 0.3, 0.45), WOOD_DARK, lean)
	# Cuadernas al aire (el costado roto).
	for i in range(4):
		_box(st, Vector3(-0.6 + 0.35 * i, 0.42, -0.22), Vector3(0.06, 0.5, 0.06), WOOD_LIGHT, Basis(Vector3.RIGHT, 0.5))
	# El mastil partido, caido de lado, y un barril suelto.
	_box(st, Vector3(-0.1, 0.55, 0.15), Vector3(0.08, 0.9, 0.08), WOOD, Basis(Vector3.FORWARD, 0.9))
	_box(st, Vector3(-0.85, 0.14, 0.75), Vector3(0.24, 0.28, 0.24), WOOD, Basis(Vector3.UP, 0.7))
	_box(st, Vector3(-0.85, 0.2, 0.75), Vector3(0.26, 0.04, 0.26), BRASS.darkened(0.3), Basis(Vector3.UP, 0.7))

## Una caja con normales planas y color por vertice.
static func _box(st: SurfaceTool, center: Vector3, size: Vector3, color: Color, basis: Basis) -> void:
	var h := size * 0.5
	var faces := [
		[Vector3(1, 0, 0), [Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, -h.y, h.z)]],
		[Vector3(-1, 0, 0), [Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, h.y, -h.z), Vector3(-h.x, -h.y, -h.z)]],
		[Vector3(0, 1, 0), [Vector3(-h.x, h.y, -h.z), Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z)]],
		[Vector3(0, -1, 0), [Vector3(-h.x, -h.y, h.z), Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z)]],
		[Vector3(0, 0, 1), [Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, -h.y, h.z)]],
		[Vector3(0, 0, -1), [Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, -h.y, -h.z)]],
	]
	for face in faces:
		var n: Vector3 = (basis * (face[0] as Vector3)).normalized()
		var q: Array = face[1]
		var v: Array = []
		for corner in q:
			v.append(center + basis * (corner as Vector3))
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_color(color)
			st.set_normal(n)
			st.add_vertex(v[idx])
