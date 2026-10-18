extends RefCounted
## Lo que gana un edificio mejorado en 3D (2026-10-17, rehecho): el MISMO
## modelo, mas alto y algo mas ancho (ProductionManager.apply_level_visual), y
## debajo y al lado piezas de maqueta que se leen de un vistazo, todas
## apoyadas en el suelo (nada flota):
##
## - Nivel 2: un zocalo de piedra con su fleje de laton (el modelo se sube
##   encima) y, en la esquina trasera derecha, una chimenea de ladrillo con dos
##   bandas de laton, mas alta que el tejado.
## - Nivel 3: el zocalo de dos escalones, la chimenea mas alta con un farol
##   encendido y una segunda chimenea en la esquina trasera izquierda.
## - Decoraciones (jardin, fuente, estatua): el zocalo y farolas de laton en
##   las esquinas (dos delante en el II, cuatro en el III) en lugar de chimeneas.
##
## Antes (hasta 2026-10-16) era un aro de laton sobre la caja del modelo con un
## banderin rojo en el III: en los modelos con grua o castillete el aro flotaba
## en el aire como un recuadro, y el banderin parecia otra bandera.
##
## Una malla por nivel, clase y medida (cacheada para todo el mapa), con los dos
## materiales de la maqueta (LotMesh -> ToyPalette): una llamada de dibujo, sin
## sombra propia y sin nodos ni _process de mas. Cuelga del modelo
## ("LevelTrim"), asi que se oculta en obra y se hunde y se ladea con el en la
## ruina; su escala deshace la del modelo para medir en metros. Esta en el
## grupo "building_fx": ni la medida de la cima ni el hollin de BuildingHealth
## lo cuentan.

const MeshKit := preload("res://scripts/buildings/LotMesh.gd")
const Tone := preload("res://scripts/buildings/ToyTones.gd")
const Lot := preload("res://scripts/buildings/BuildingLot.gd")

const NODE_NAME := "LevelTrim"

## Alto del zocalo por nivel (metros): el modelo se sube esto encima.
const PLINTH := [0.0, 0.0, 0.16, 0.3]
## Crecimiento del modelo por nivel por encima del 1: en planta poco (la
## parcela no da para mas), en alto bastante (se nota desde la camara).
const GROW_XZ := 0.04
const GROW_Y := 0.12

static var _meshes: Dictionary = {}

## Alto del zocalo de `level`.
static func plinth_height(level: int) -> float:
	return PLINTH[clampi(level, 0, 3)]

## Escala relativa del modelo a nivel `level` (1 = la de serie).
static func level_scale(level: int) -> Vector3:
	var n := float(maxi(0, level - 1))
	return Vector3(1.0 + GROW_XZ * n, 1.0 + GROW_Y * n, 1.0 + GROW_XZ * n)

## Pone (o quita, nivel 1) las piezas de `level` en `model`. `decor`: es una
## decoracion (farolas en vez de chimeneas). Llamar con el modelo ya escalado
## y subido a su zocalo.
static func apply(model: Node3D, level: int, decor := false) -> void:
	if model == null:
		return
	var old := model.get_node_or_null(NODE_NAME)
	if level <= 1:
		if old != null:
			old.queue_free()
		return
	# La caja del modelo en su propio espacio (sin estas piezas: son building_fx).
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
	# En metros: la escala del hijo deshace la del modelo.
	var size := Vector3(box.size.x * absf(s.x), box.size.y * absf(s.y), box.size.z * absf(s.z))
	mi.scale = Vector3(1.0 / s.x, 1.0 / s.y, 1.0 / s.z)
	mi.position = Vector3(box.get_center().x, box.position.y, box.get_center().z)
	mi.mesh = trim_mesh(level, size, decor)

## La malla de `level` para un modelo de `size` (ancho, alto, fondo) en metros,
## con el origen en el centro de su base (el suelo del modelo, sobre el zocalo).
static func trim_mesh(level: int, size: Vector3, decor := false) -> ArrayMesh:
	var key := "%d|%d|%.1f,%.1f,%.1f" % [level, 1 if decor else 0, size.x, size.y, size.z]
	if _meshes.has(key):
		return _meshes[key]
	var mb = MeshKit.new()
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	_plinth(mb, level, hx, hz)
	if decor:
		_lamps(mb, level, hx, hz)
	else:
		_chimneys(mb, level, hx, hz, size.y)
	var mesh: ArrayMesh = mb.commit()
	_meshes[key] = mesh
	return mesh

## El zocalo: losa de piedra un poco mas ancha que el modelo, con el fleje de
## laton en el canto; en el III, dos escalones.
static func _plinth(mb, level: int, hx: float, hz: float) -> void:
	var h := plinth_height(level)
	var stone := Tone.of("stone_light")
	var brass := Tone.of("brass")
	var pad := 0.1
	if level >= 3:
		var low := h * 0.5
		mb.box(Vector3(0, -h + low * 0.5, 0), Vector3((hx + pad + 0.1) * 2.0, low, (hz + pad + 0.1) * 2.0), Tone.of("stone"))
		mb.box(Vector3(0, -low * 0.5, 0), Vector3((hx + pad) * 2.0, low, (hz + pad) * 2.0), stone)
	else:
		mb.box(Vector3(0, -h * 0.5, 0), Vector3((hx + pad) * 2.0, h, (hz + pad) * 2.0), stone)
	# El fleje: cuatro listones de laton en el canto de arriba, por fuera.
	var band := 0.05
	var y := -band * 0.5
	var ox := hx + pad + band * 0.5
	var oz := hz + pad + band * 0.5
	mb.box(Vector3(0, y, oz), Vector3(ox * 2.0 + band, band, band), brass)
	mb.box(Vector3(0, y, -oz), Vector3(ox * 2.0 + band, band, band), brass)
	mb.box(Vector3(ox, y, 0), Vector3(band, band, oz * 2.0), brass)
	mb.box(Vector3(-ox, y, 0), Vector3(band, band, oz * 2.0), brass)

## Las chimeneas de ladrillo: en las esquinas traseras (-z, lejos de la
## camara), metidas en la huella para que se lean "del edificio".
static func _chimneys(mb, level: int, hx: float, hz: float, height: float) -> void:
	var brick := Tone.of("brick")
	var brass := Tone.of("brass")
	var iron := Tone.of("iron")
	var r := clampf(minf(hx, hz) * 0.14, 0.11, 0.18)
	var roof := clampf(height, 0.9, 3.2)
	var corners := [Vector2(1, -1)]
	if level >= 3:
		corners.append(Vector2(-1, -1))
	for i in corners.size():
		var c: Vector2 = corners[i]
		var h := roof * 0.9 + 0.3 + 0.4 * float(level - 2) - 0.3 * float(i)
		var p := Vector3(c.x * (hx - r * 0.9), 0.0, c.y * (hz - r * 0.9))
		mb.box(p + Vector3(0, h * 0.5, 0), Vector3(r * 2.0, h, r * 2.0), brick)
		# Dos bandas de laton y la corona de hierro.
		for t in [0.55, 0.85]:
			mb.box(p + Vector3(0, h * t, 0), Vector3(r * 2.0 + 0.06, 0.06, r * 2.0 + 0.06), brass)
		mb.box(p + Vector3(0, h + 0.04, 0), Vector3(r * 2.0 + 0.1, 0.08, r * 2.0 + 0.1), iron)
		mb.box(p + Vector3(0, h + 0.09, 0), Vector3(r * 1.2, 0.02, r * 1.2), Tone.of("coal"))
		if level >= 3 and i == 0:
			# El farol de la chimenea mayor: encendido (superficie de brillo).
			mb.box(p + Vector3(0, h * 0.7, r + 0.04), Vector3(r * 0.9, r * 0.9, 0.05), Tone.of("warm"), true)

## Farolas de laton en las esquinas del zocalo: delante en el II, las cuatro en el III.
static func _lamps(mb, level: int, hx: float, hz: float) -> void:
	var iron := Tone.of("iron")
	var gold := Tone.of("gold")
	var corners := [Vector2(-1, 1), Vector2(1, 1)]
	if level >= 3:
		corners.append_array([Vector2(-1, -1), Vector2(1, -1)])
	var h := 0.75 + 0.15 * float(level - 2)
	for c: Vector2 in corners:
		var p := Vector3(c.x * (hx + 0.02), 0.0, c.y * (hz + 0.02))
		mb.box(p + Vector3(0, 0.05, 0), Vector3(0.16, 0.1, 0.16), iron)
		mb.cyl(p + Vector3(0, 0.1, 0), 0.035, h, iron, 6)
		mb.box(p + Vector3(0, 0.1 + h + 0.08, 0), Vector3(0.14, 0.16, 0.14), Tone.of("warm"), true)
		mb.cyl(p + Vector3(0, 0.1 + h + 0.16, 0), 0.1, 0.08, gold, 6, Vector3.UP, 0.0)
