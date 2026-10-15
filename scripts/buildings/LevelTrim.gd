extends RefCounted
## El añadido de nivel de un edificio mejorado (3D): el MISMO modelo, un poco
## mas grande (ProductionManager.apply_level_visual), con un remate de laton
## encima que dice "este ya va por el II / el III" sin cambiarle la cara.
##
## - Nivel 2: una corona de laton (cuatro remates en las esquinas del tejado
##   unidos por un fleje).
## - Nivel 3: lo del 2 y, en el centro, un mastil corto con un banderin rojo.
##
## Una malla por nivel y medida (cacheada para todo el mapa), con los dos
## materiales de la maqueta (LotMesh -> ToyPalette): una llamada de dibujo y
## sin sombra. Cuelga del modelo ("LevelTrim"), asi que crece, se hunde y se
## ladea con el; esta en el grupo "building_fx", de modo que ni la medida de la
## cima ni el hollin de BuildingHealth lo cuentan.

const MeshKit := preload("res://scripts/buildings/LotMesh.gd")
const Tone := preload("res://scripts/buildings/ToyTones.gd")
const Lot := preload("res://scripts/buildings/BuildingLot.gd")

const NODE_NAME := "LevelTrim"

static var _meshes: Dictionary = {}

## Pone (o quita, nivel 1) el remate de `level` sobre `model`.
static func apply(model: Node3D, level: int) -> void:
	if model == null:
		return
	var old := model.get_node_or_null(NODE_NAME)
	if level <= 1:
		if old != null:
			old.queue_free()
		return
	# La caja del modelo en su propio espacio (sin el remate viejo: es building_fx).
	var box: AABB = Lot.model_aabb(model, model)
	if box.size == Vector3.ZERO:
		return
	var mi := old as MeshInstance3D
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = NODE_NAME
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.add_to_group("building_fx")
		model.add_child(mi)
	mi.mesh = trim_mesh(level, Vector2(box.size.x, box.size.z))
	mi.position = Vector3(box.get_center().x, box.end.y, box.get_center().z)

## La malla del remate para un tejado de `size` (ancho, fondo) en metros.
static func trim_mesh(level: int, size: Vector2) -> ArrayMesh:
	var key := "%d|%.1f,%.1f" % [level, size.x, size.y]
	if _meshes.has(key):
		return _meshes[key]
	var mb = MeshKit.new()
	var brass := Tone.of("brass")
	var gold := Tone.of("gold")
	var iron := Tone.of("iron")
	# Las esquinas, un poco hacia dentro del borde del tejado.
	var hx := size.x * 0.36
	var hz := size.y * 0.36
	var s := clampf(minf(size.x, size.y) * 0.07, 0.1, 0.22)
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var p := Vector3(c.x * hx, 0.0, c.y * hz)
		mb.box(p + Vector3(0, s * 0.5, 0), Vector3(s, s, s), brass)
		mb.cyl(p + Vector3(0, s, 0), s * 0.32, s * 1.1, gold, 6, Vector3.UP, 0.0)
	# Fleje de laton que une los remates (se lee "corona" desde la camara).
	var band := s * 0.28
	mb.box(Vector3(0, band * 0.5, -hz), Vector3(hx * 2.0, band, band), brass.darkened(0.15))
	mb.box(Vector3(0, band * 0.5, hz), Vector3(hx * 2.0, band, band), brass.darkened(0.15))
	mb.box(Vector3(-hx, band * 0.5, 0), Vector3(band, band, hz * 2.0), brass.darkened(0.15))
	mb.box(Vector3(hx, band * 0.5, 0), Vector3(band, band, hz * 2.0), brass.darkened(0.15))
	if level >= 3:
		var h := clampf(minf(size.x, size.y) * 0.45, 0.7, 1.3)
		mb.box(Vector3(0, s * 0.4, 0), Vector3(s * 1.4, s * 0.8, s * 1.4), iron)
		mb.cyl(Vector3(0, s * 0.8, 0), 0.04, h, iron, 6)
		mb.ball(Vector3(0, s * 0.8 + h + 0.05, 0), 0.08, gold)
		# Banderin triangular rojo, a dos caras.
		var top := Vector3(0, s * 0.8 + h - 0.04, 0)
		var red := Tone.of("red")
		var a := top
		var b := top + Vector3(0, -h * 0.36, 0)
		var tip := top + Vector3(h * 0.5, -h * 0.18, 0)
		mb._tri(a, b, tip, Vector3.BACK, red, false)
		mb._tri(a, tip, b, Vector3.FORWARD, red.darkened(0.12), false)
	var mesh: ArrayMesh = mb.commit()
	_meshes[key] = mesh
	return mesh
