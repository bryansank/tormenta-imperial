extends Node3D
## Las decoraciones pequenas del mapa 3D (las diez de DecorMesh: farola, banco,
## seto, arbol, macetero, letrero, carro, hoguera, mastil, palmeras) en un
## MultiMesh por tipo, como las calzadas en RoadBatch3D: con cien farolas, una
## llamada de dibujo (dos si algo brilla) en vez de cien, mas sus pases de
## profundidad y de sombra.
##
## El edificio sigue siendo un nodo normal (rejilla, seleccion, mover, guardar,
## obra, ruina, nivel): su modelo es un DecorProxy3D, que mide y se mueve como
## siempre pero no se dibuja. Este nodo dibuja las instancias.
##
## Nada por frame: un aviso (puesta, quitada, movida, escondida en obra o al
## moverla) marca el tipo "sucio" y el reparto se rehace UNA vez, diferido, al
## final del frame; si solo se movio una (el salto de obra terminada, la ruina,
## el nivel), solo se reescribe su transformacion.
##
## Sombra: las altas (farola, arbol, mastil, palmeras, letrero, macetero) la
## proyectan; las menudas (banco, seto, carro, hoguera) no
## (SHADOW_MIN_HEIGHT): son poco mas que suelo y la sombra cuesta un pase por
## corte. Los materiales son los de la malla: los dos de ToyPalette, compartidos.

const Decor := preload("res://scripts/buildings/DecorMesh.gd")
const Proxy := preload("res://scripts/buildings/DecorProxy3D.gd")

## Por debajo de este alto (m, la malla sin escalar) la pieza no da sombra.
const SHADOW_MIN_HEIGHT := 1.5

## id -> {DecorProxy3D: true}: las apuntadas de cada tipo.
var _members: Dictionary = {}
## id -> MultiMeshInstance3D, creada al primer uso.
var _layers: Dictionary = {}
## id -> true: tipos que rehacer enteros en el proximo reparto.
var _dirty_ids: Dictionary = {}
## DecorProxy3D -> true: solo su transformacion.
var _moved: Dictionary = {}
var _queued := false

func _ready() -> void:
	name = "DecorBatch"

static func handles(id: String) -> bool:
	return Decor.handles(id)

## El modelo que lleva el edificio `id`: un DecorProxy3D con la malla
## compartida (y su FlagAnchor, si tiene mastil), apuntado aqui. null si `id`
## no es una de las diez.
func make_proxy(id: String) -> MeshInstance3D:
	var mesh := Decor.mesh_for(id)
	if mesh == null:
		return null
	var p: MeshInstance3D = Proxy.new()
	p.name = "Toy_" + id
	p.mesh = mesh
	p.set("batch", self)
	p.set("decor_id", id)
	Decor.add_flag_anchor(p, id)
	if not _members.has(id):
		_members[id] = {}
	(_members[id] as Dictionary)[p] = true
	mark_dirty(id)
	return p

func mark_dirty(id: String) -> void:
	_dirty_ids[id] = true
	_queue()

func mark_moved(p: Node) -> void:
	_moved[p] = true
	_queue()

func _queue() -> void:
	if _queued or not is_inside_tree():
		return
	_queued = true
	_flush.call_deferred()

## Rehace ya lo pendiente (lo normal es dejar que lo haga el aviso, diferido).
func rebuild_now() -> void:
	_flush()

## Cuantas se dibujan ahora de `id` (o de todas con ""), para sondas y pruebas.
func drawn_count(id: String = "") -> int:
	var n := 0
	for key in _layers:
		if id != "" and key != id:
			continue
		var mmi: MultiMeshInstance3D = _layers[key]
		if mmi.visible:
			n += mmi.multimesh.instance_count
	return n

func get_layer(id: String) -> MultiMeshInstance3D:
	return _layers.get(id, null)

func _flush() -> void:
	_queued = false
	if not is_inside_tree():
		return
	var inv := global_transform.affine_inverse()
	for id in _dirty_ids.keys():
		_rebuild(String(id), inv)
	for p in _moved.keys():
		if not is_instance_valid(p) or _dirty_ids.has(p.decor_id):
			continue
		var idx: int = p.batch_index
		var layer: MultiMeshInstance3D = _layers.get(p.decor_id, null)
		if idx < 0 or layer == null or idx >= layer.multimesh.instance_count:
			continue
		layer.multimesh.set_instance_transform(idx, inv * (p as Node3D).global_transform)
	_dirty_ids.clear()
	_moved.clear()

func _rebuild(id: String, inv: Transform3D) -> void:
	var members: Dictionary = _members.get(id, {})
	var shown: Array = []
	for p in members.keys():
		if not is_instance_valid(p):
			members.erase(p)
			continue
		var proxy := p as MeshInstance3D
		proxy.set("batch_index", -1)
		if proxy.is_inside_tree() and proxy.is_visible_in_tree():
			shown.append(proxy)
	if shown.is_empty():
		var idle: MultiMeshInstance3D = _layers.get(id, null)
		if idle != null:
			idle.multimesh.instance_count = 0
			idle.visible = false
		return
	var mmi := _layer(id)
	var mm := mmi.multimesh
	mm.instance_count = shown.size()
	for i in shown.size():
		var proxy: MeshInstance3D = shown[i]
		proxy.set("batch_index", i)
		mm.set_instance_transform(i, inv * proxy.global_transform)
	mmi.visible = true

func _layer(id: String) -> MultiMeshInstance3D:
	if _layers.has(id):
		return _layers[id]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var mesh := Decor.mesh_for(id)
	mm.mesh = mesh
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Decor_" + id
	mmi.multimesh = mm
	var tall := mesh != null and mesh.get_aabb().size.y >= SHADOW_MIN_HEIGHT
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if tall 		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	_layers[id] = mmi
	return mmi
