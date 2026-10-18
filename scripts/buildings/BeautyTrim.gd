extends RefCounted
## Lo que gana una casa con belleza alta en 3D (feat/edificios-defensa-vida,
## doc 21 §6.4 y V9): el MISMO modelo de la casa, con adornos de maqueta encima.
##
## - Nivel 2, "casa bonita": jardineras con flores bajo las ventanas del frente,
##   un seto bajo en las esquinas de delante y matas de flores junto a la puerta.
## - Nivel 3, "casa elegante": lo de la bonita, mas hiedra en la fachada, dos
##   farolas encendidas (superficie de brillo, sin luz real) y una guirnalda de
##   banderines de laton y rojo en el alero.
## - Nivel 1: nada (se quita).
##
## Como LevelTrim: una malla por nivel y medida, cacheada para todo el mapa, con
## los dos materiales de la maqueta (LotMesh -> ToyPalette): una llamada de
## dibujo, sin sombra propia, sin nodos ni `_process` de mas. Cuelga del modelo
## ("BeautyTrim"), asi que se oculta en obra y se hunde con el en la ruina; su
## escala deshace la del modelo para medir en metros. Esta en el grupo
## "building_fx": ni la medida de la cima ni el hollin la cuentan. Se pone al
## cambiar la belleza (EventBus.beauty_changed), nunca por frame.

const MeshKit := preload("res://scripts/buildings/LotMesh.gd")
const Tone := preload("res://scripts/buildings/ToyTones.gd")
const Lot := preload("res://scripts/buildings/BuildingLot.gd")

const NODE_NAME := "BeautyTrim"

static var _meshes: Dictionary = {}

## Pone (o quita, nivel 1) los adornos de `level` en la casa `node`.
static func apply(node: Node, level: int) -> void:
	if node == null or not is_instance_valid(node) or not (node is Node3D):
		return
	var model := model_of(node)
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

## El modelo de la casa: el que conoce su aspecto (LookVisual), si no el primer
## hijo 3D que no sea rotulo ni efecto (como ProductionManager.apply_level_visual).
static func model_of(node: Node) -> Node3D:
	var look := node.get_node_or_null("LookVisual")
	if look != null and look.has_method("get_model"):
		var m = look.get_model()
		if m is Node3D:
			return m
	for child in node.get_children():
		if child is Node3D and not (child is Label3D) and not (child is Sprite3D) \
				and not child.is_in_group("building_fx") \
				and child.name != "ConstructionBar" and child.name != "LookVisual" \
				and child.name != "ColonyFlag":
			return child
	return null

## La malla de `level` para un modelo de `size` (ancho, alto, fondo) en metros,
## con el origen en el centro de su base y el frente hacia +Z.
static func trim_mesh(level: int, size: Vector3) -> ArrayMesh:
	var key := "%d|%.1f,%.1f,%.1f" % [level, size.x, size.y, size.z]
	if _meshes.has(key):
		return _meshes[key]
	var mb = MeshKit.new()
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var h := clampf(size.y, 0.8, 3.0)
	_window_boxes(mb, hx, hz, h)
	_front_garden(mb, hx, hz)
	if level >= 3:
		_ivy(mb, hx, hz, h)
		_lamps(mb, hx, hz)
		_bunting(mb, hx, hz, h)
	var mesh: ArrayMesh = mb.commit()
	_meshes[key] = mesh
	return mesh

## Dos jardineras de madera con flores rojas y crema, pegadas al frente.
static func _window_boxes(mb, hx: float, hz: float, h: float) -> void:
	var y := h * 0.32
	for sx in [-0.5, 0.5]:
		var c := Vector3(sx * hx, y, hz + 0.07)
		mb.box(c, Vector3(hx * 0.55, 0.1, 0.14), Tone.of("wood_dark"))
		for k in 4:
			var fx: float = c.x - hx * 0.2 + float(k) * hx * 0.13
			var col := Tone.of("red") if k % 2 == 0 else Tone.of("cream")
			mb.ball(Vector3(fx, y + 0.09, c.z), 0.06, col)
		mb.box(c + Vector3(0, 0.06, 0), Vector3(hx * 0.5, 0.04, 0.1), Tone.of("leaf"))

## Seto bajo en las esquinas de delante y matas de flores junto a la puerta.
static func _front_garden(mb, hx: float, hz: float) -> void:
	for sx in [-1.0, 1.0]:
		var c := Vector3(sx * (hx - 0.18), 0.0, hz + 0.22)
		mb.box(c + Vector3(0, 0.11, 0), Vector3(0.34, 0.22, 0.2), Tone.of("leaf_dark"))
		mb.box(c + Vector3(0, 0.23, 0), Vector3(0.3, 0.03, 0.17), Tone.of("leaf"))
	for k in 3:
		var p := Vector3(-0.25 + float(k) * 0.25, 0.0, hz + 0.3)
		mb.ball(p + Vector3(0, 0.08, 0), 0.08, Tone.of("leaf"))
		mb.ball(p + Vector3(0, 0.16, 0), 0.045, Tone.of("gold") if k == 1 else Tone.of("red"))

## Hiedra en la fachada: manchas verdes subiendo por las esquinas del frente.
static func _ivy(mb, hx: float, hz: float, h: float) -> void:
	for sx in [-1.0, 1.0]:
		for k in 3:
			var y := 0.25 + float(k) * h * 0.18
			mb.box(Vector3(sx * (hx - 0.12 - 0.04 * float(k)), y, hz + 0.03), Vector3(0.22, 0.24, 0.04), Tone.of("leaf_dark") if k % 2 == 0 else Tone.of("leaf"))

## Dos farolas encendidas a los lados de la entrada.
static func _lamps(mb, hx: float, hz: float) -> void:
	for sx in [-1.0, 1.0]:
		var p := Vector3(sx * (hx * 0.45), 0.0, hz + 0.42)
		mb.box(p + Vector3(0, 0.04, 0), Vector3(0.12, 0.08, 0.12), Tone.of("iron"))
		mb.cyl(p + Vector3(0, 0.08, 0), 0.03, 0.62, Tone.of("iron"), 6)
		mb.box(p + Vector3(0, 0.76, 0), Vector3(0.12, 0.14, 0.12), Tone.of("warm"), true)
		mb.cyl(p + Vector3(0, 0.83, 0), 0.09, 0.07, Tone.of("gold"), 6, Vector3.UP, 0.0)

## Guirnalda de banderines bajo el alero del frente, laton y rojo.
static func _bunting(mb, hx: float, hz: float, h: float) -> void:
	var y := h * 0.66
	var n := 7
	mb.box(Vector3(0, y + 0.06, hz + 0.08), Vector3(hx * 1.8, 0.015, 0.015), Tone.of("iron"))
	for i in n:
		var x := -hx * 0.85 + float(i) * (hx * 1.7) / float(n - 1)
		var col := Tone.of("brass") if i % 2 == 0 else Tone.of("red")
		mb.box(Vector3(x, y, hz + 0.08), Vector3(0.1, 0.11, 0.015), col)
