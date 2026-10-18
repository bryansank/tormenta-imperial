extends RefCounted
## Lo que gana el NUCLEO en 3D con cada nivel (1.2, feat/nucleo-y-planos; doc 21
## §6.1: "su modelo crece con el nivel"). Es la receta de juguete del Nucleo por
## niveles: el modelo horneado (tools/toy_recipes/nucleo.gd) no cambia y encima
## se le ponen piezas de maqueta, todas en el suelo o sobre el propio modelo:
##
## - Nivel 2: dos farolas de laton delante y una losa de escalinata.
## - Nivel 3: dos alas bajas de ladrillo a los lados, con ventanas encendidas.
## - Nivel 4: dos torreones de piedra con cupulin de laton y ventana encendida
##   en las esquinas de delante, y dos farolas detras (lo alto del Nucleo ya
##   lleva el mastil de la bandera: no se toca).
## - Nivel 5: cuatro obeliscos de piedra con punta dorada en las esquinas.
##
## Cada nivel incluye los anteriores. Ademas el modelo gana un poco de alto
## (CORE_GROW_Y por nivel). Una malla por nivel y medida (cacheada), con los dos
## materiales de la maqueta (LotMesh -> ToyPalette): una llamada de dibujo, sin
## sombra propia, sin nodos ni _process de mas. Cuelga del modelo ("CoreTrim")
## y esta en el grupo "building_fx", como LevelTrim. En 2D lo pinta
## BuildingArt2D._nucleo_level().

const MeshKit := preload("res://scripts/buildings/LotMesh.gd")
const Tone := preload("res://scripts/buildings/ToyTones.gd")
const Lot := preload("res://scripts/buildings/BuildingLot.gd")

const NODE_NAME := "CoreTrim"
## Alto que gana el modelo por nivel por encima del 1 (fraccion).
const CORE_GROW_Y := 0.04

static var _meshes: Dictionary = {}

## Escala relativa del modelo del Nucleo a nivel `level` (1 = la de serie).
static func level_scale(level: int) -> Vector3:
	return Vector3(1.0, 1.0 + CORE_GROW_Y * float(maxi(0, level - 1)), 1.0)

## Pone (o quita, nivel 1) las piezas de `level` en `model`. Llamar con el
## modelo ya escalado.
static func apply(model: Node3D, level: int) -> void:
	if model == null:
		return
	var old := model.get_node_or_null(NODE_NAME)
	if level <= 1:
		if old != null:
			old.queue_free()
		return
	var box: AABB = Lot.model_aabb(model, model)
	if box.size == Vector3.ZERO:
		return
	var s := model.scale
	if is_zero_approx(s.x) or is_zero_approx(s.y) or is_zero_approx(s.z):
		return
	var mi := old as MeshInstance3D
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = NODE_NAME
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.add_to_group("building_fx")
		model.add_child(mi)
	var size := Vector3(box.size.x * absf(s.x), box.size.y * absf(s.y), box.size.z * absf(s.z))
	mi.scale = Vector3(1.0 / s.x, 1.0 / s.y, 1.0 / s.z)
	mi.position = Vector3(box.get_center().x, box.position.y, box.get_center().z)
	mi.mesh = trim_mesh(level, size)

## La malla de `level` para un modelo de `size` (ancho, alto, fondo) en metros,
## con el origen en el centro de su base. +z es delante (hacia la camara).
static func trim_mesh(level: int, size: Vector3) -> ArrayMesh:
	var lv := clampi(level, 2, 5)
	var key := "%d|%.1f,%.1f,%.1f" % [lv, size.x, size.y, size.z]
	if _meshes.has(key):
		return _meshes[key]
	var mb = MeshKit.new()
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var h := clampf(size.y, 1.5, 9.0)
	# Nivel 2: farolas delante y la losa de la escalinata.
	_lamp(mb, Vector3(-hx * 0.62, 0.0, hz * 0.92), 0.95)
	_lamp(mb, Vector3(hx * 0.62, 0.0, hz * 0.92), 0.95)
	mb.box(Vector3(0.0, 0.04, hz * 0.95), Vector3(hx * 0.7, 0.08, 0.36), Tone.of("stone_light"))
	mb.box(Vector3(0.0, 0.1, hz * 0.88), Vector3(hx * 0.5, 0.06, 0.24), Tone.of("stone"))
	if lv >= 3:
		# Alas bajas de ladrillo a los lados, delante de las calderas.
		for sx: float in [-1.0, 1.0]:
			var w := clampf(size.x * 0.16, 0.45, 1.0)
			var d := clampf(size.z * 0.24, 0.6, 1.4)
			var wh := clampf(h * 0.18, 0.5, 1.2)
			var c := Vector3(sx * (hx - w * 0.5), 0.0, hz * 0.35)
			mb.box(c + Vector3(0, wh * 0.5, 0), Vector3(w, wh, d), Tone.of("brick"))
			mb.box(c + Vector3(0, wh + 0.05, 0), Vector3(w + 0.1, 0.1, d + 0.1), Tone.of("steel"))
			mb.box(c + Vector3(0, wh + 0.1, 0), Vector3(w * 0.6, 0.06, d * 0.8), Tone.of("brass"))
			# Ventanas encendidas hacia fuera y hacia delante.
			for t: float in [-0.25, 0.25]:
				mb.box(c + Vector3(sx * (w * 0.5 + 0.01), wh * 0.55, d * t), Vector3(0.03, wh * 0.3, d * 0.16), Tone.of("warm"), true)
			mb.box(c + Vector3(0, wh * 0.55, d * 0.5 + 0.01), Vector3(w * 0.4, wh * 0.3, 0.03), Tone.of("warm"), true)
	if lv >= 4:
		# Torreones en las esquinas de delante y dos farolas detras (lejos de la
		# esquina trasera derecha, donde ColonyFlag3D pone su mastil si no hay ancla).
		for sx: float in [-1.0, 1.0]:
			var p := Vector3(sx * (hx - 0.25), 0.0, hz - 0.25)
			var th := clampf(h * 0.26, 0.9, 1.8)
			mb.cyl(p, 0.24, th, Tone.of("stone_light"), 8)
			mb.cyl(p + Vector3(0, th, 0), 0.28, 0.08, Tone.of("brass"), 8)
			mb.ball(p + Vector3(0, th + 0.12, 0), 0.22, Tone.of("brass"), Vector3(1.0, 0.8, 1.0))
			mb.box(p + Vector3(0, th * 0.65, 0.23), Vector3(0.14, 0.2, 0.04), Tone.of("warm"), true)
		_lamp(mb, Vector3(-hx * 0.45, 0.0, -hz * 0.95), 0.8)
		_lamp(mb, Vector3(hx * 0.45, 0.0, -hz * 0.95), 0.8)
	if lv >= 5:
		# Obeliscos de piedra con la punta dorada en las cuatro esquinas.
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var p := Vector3(sx * (hx + 0.05), 0.0, sz * (hz + 0.05))
				var oh := clampf(h * 0.32, 1.0, 2.2)
				mb.box(p + Vector3(0, 0.08, 0), Vector3(0.36, 0.16, 0.36), Tone.of("stone_dark"))
				mb.cyl(p + Vector3(0, 0.16, 0), 0.13, oh, Tone.of("stone_light"), 4, Vector3.UP, 0.07)
				mb.cyl(p + Vector3(0, 0.16 + oh, 0), 0.07, 0.2, Tone.of("gold"), 4, Vector3.UP, 0.0)
	var mesh: ArrayMesh = mb.commit()
	_meshes[key] = mesh
	return mesh

## Una farola de laton: base, poste de hierro y farol encendido.
static func _lamp(mb, p: Vector3, height: float) -> void:
	mb.box(p + Vector3(0, 0.05, 0), Vector3(0.16, 0.1, 0.16), Tone.of("iron"))
	mb.cyl(p + Vector3(0, 0.1, 0), 0.035, height, Tone.of("iron"), 6)
	mb.box(p + Vector3(0, 0.1 + height + 0.08, 0), Vector3(0.14, 0.16, 0.14), Tone.of("warm"), true)
	mb.cyl(p + Vector3(0, 0.1 + height + 0.16, 0), 0.1, 0.08, Tone.of("gold"), 6, Vector3.UP, 0.0)
