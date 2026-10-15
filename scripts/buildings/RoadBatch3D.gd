extends Node3D
## Todas las calzadas del mapa 3D en, como mucho, 16 llamadas de dibujo
## (docs/26 §6, punto 2): un MultiMesh por mascara de vecinos (N=1, E=2, S=4,
## O=8), cada uno con la malla cacheada de DieselpunkBuildingFactory.road_mesh()
## y el material solido comun de ToyPalette.
##
## Antes cada tramo era su propia MeshInstance3D con sombra: con 276 tramos,
## unos 1400-1600 draw calls entre el pase de profundidad, el de color y los
## cortes de sombra. Ahora el nodo de cada calzada (el que guarda la rejilla, se
## selecciona y se guarda) no lleva malla: solo se apunta aqui.
##
## Sin sombra proyectada: la calzada es suelo (el bordillo mide 14 cm) y la
## sombra de los edificios le sigue cayendo encima (recibir no cuesta pases).
##
## Nada por frame: cualquier cambio (poner, quitar, mover, esconder un tramo)
## marca "sucio" y el reparto se rehace UNA vez, diferido, al final del frame.
## Al cargar una partida con cientos de tramos es una sola pasada; antes cada
## tramo rehacia su malla y la de sus cuatro vecinos, hasta cinco veces.
##
## La mascara se lee de la rejilla (PlacementRules.road_neighbor_mask) en
## coordenadas de mundo: girar un tramo al colocarlo ya no tuerce sus uniones.

const Rules := preload("res://scripts/buildings/PlacementRules.gd")

## Los nodos de calzada apuntados (Node3D -> true).
var _roads: Dictionary = {}
## Una capa por mascara (int -> MultiMeshInstance3D), creada al primer uso.
var _layers: Dictionary = {}
var _dirty := false
var _cell_size := 0.0

func _ready() -> void:
	name = "RoadBatch"

## Apunta la calzada `node` (ya en la rejilla) y repinta la red.
func add_road(node: Node3D) -> void:
	if node == null or _roads.has(node):
		mark_dirty()
		return
	_roads[node] = true
	# Esconder un tramo (moverlo) o a su contenedor tambien lo quita del dibujo.
	node.visibility_changed.connect(mark_dirty)
	node.tree_exiting.connect(_on_road_exiting.bind(node))
	mark_dirty()

## La red cambio (un tramo puesto, quitado o movido): se rehace al final del frame.
func mark_dirty() -> void:
	if _dirty or not is_inside_tree():
		return
	_dirty = true
	_rebuild.call_deferred()

func _on_road_exiting(node: Node3D) -> void:
	_roads.erase(node)
	if is_inside_tree() and not is_queued_for_deletion():
		mark_dirty()

## Cuantos tramos se dibujan ahora (para sondas y pruebas).
func drawn_count() -> int:
	var n := 0
	for mask in _layers:
		var mmi: MultiMeshInstance3D = _layers[mask]
		if mmi.visible:
			n += mmi.multimesh.instance_count
	return n

## Rehace ya el reparto (lo normal es dejar que lo haga mark_dirty, diferido).
func rebuild_now() -> void:
	_rebuild()

func _rebuild() -> void:
	_dirty = false
	if not is_inside_tree():
		return
	var cs: float = GridManager.cell_size
	if not is_equal_approx(cs, _cell_size):
		# Otra medida de casilla: las mallas de las capas ya no valen.
		for mask in _layers:
			(_layers[mask] as Node).queue_free()
		_layers.clear()
		_cell_size = cs
	var by_mask: Dictionary = {}
	for node in _roads.keys():
		if not is_instance_valid(node):
			_roads.erase(node)
			continue
		var road := node as Node3D
		if not road.is_inside_tree() or not road.is_visible_in_tree():
			continue
		# Demolida en este mismo frame: ya no esta en la rejilla.
		var info := GridManager.get_building_info(road)
		if info.is_empty():
			continue
		var cell: Vector2i = info["origin_cell"]
		var mask := Rules.road_neighbor_mask(cell)
		if not by_mask.has(mask):
			by_mask[mask] = []
		var w := GridManager.cell_to_world(cell)
		(by_mask[mask] as Array).append(Transform3D(Basis.IDENTITY, Vector3(w.x, road.global_position.y, w.z)))
	for mask in _layers:
		if not by_mask.has(mask):
			var idle: MultiMeshInstance3D = _layers[mask]
			idle.multimesh.instance_count = 0
			idle.visible = false
	for mask in by_mask:
		var xfs: Array = by_mask[mask]
		var mmi := _layer(int(mask))
		var mm := mmi.multimesh
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		mmi.visible = true

func _layer(mask: int) -> MultiMeshInstance3D:
	if _layers.has(mask):
		return _layers[mask]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = DieselpunkBuildingFactory.road_mesh(_cell_size, _cell_size, mask)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Roads_%d" % mask
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	_layers[mask] = mmi
	return mmi
