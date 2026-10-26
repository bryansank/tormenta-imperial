extends Node
## Un solo reloj para todos los edificios de la vista 2D (2026-10-26), como el
## de BuildingPlacer en 3D. Antes cada Building2D y cada StatusBadge2D tenia su
## _process: con 81 edificios eran ~160 llamadas por fotograma solo para mirar
## si tocaba hacer algo (1,4 ms + 1,0 ms en la colonia grande, tablet).
##
## Ahora:
## - Cada edificio esta en una de `Building2D.CHECK_FRAMES` cubetas; cada
##   fotograma se revisa UNA cubeta (`check_state()`): la firma, la parcela y, una
##   vez de cada `BADGE_EVERY` revisiones, su badge.
## - Si cambia el zoom de la camara, se recolocan los badges a la vista (una vez,
##   no cada fotograma).
## - El _process propio de un Building2D solo se enciende para lo que se mueve
##   de verdad: seleccionado (el pulso), en obras (el rotulo sigue al zoom) y los
##   primeros fotogramas tras nacer. El badge no tiene _process.
##
## Sin escena: lo crea el primer Building2D que entra en el arbol y cuelga de la
## raiz (sobrevive a la recarga de escena, como un autoload, y no guarda nada de
## la partida: los edificios se dan de baja al salir del arbol).

const CHECK_FRAMES := 10
## Cada edificio se revisa una vez cada ROUND_SECONDS de tiempo real, no cada
## CHECK_FRAMES fotogramas: a 130 fps una ronda por fotogramas eran 13
## revisiones por segundo y edificio (~840 us/fotograma en la colonia grande).
## Una cubeta cada ROUND_SECONDS / CHECK_FRAMES; con pocos fps, como mucho
## una ronda entera por fotograma. Es lo que hace BuildingPlacer en 3D con
## building_look_sync_interval; las senales de obra, dano o reparacion no
## esperan (repintan por su cuenta o en la siguiente cubeta).
const ROUND_SECONDS := 0.4

static var _instance: Node = null

var _buckets: Array = []
var _frame := 0
var _acc := 0.0
var _zoom := -1.0

static func register(building: Node) -> void:
	if not is_instance_valid(_instance):
		_instance = load("res://scripts/view2d/Building2DClock.gd").new()
		_instance.name = "Building2DClock"
		var tree := building.get_tree()
		if tree != null:
			tree.root.add_child.call_deferred(_instance)
	_instance._add(building)

static func unregister(building: Node) -> void:
	if is_instance_valid(_instance):
		_instance._remove(building)

func _init() -> void:
	for i in CHECK_FRAMES:
		_buckets.append([])

func _add(building: Node) -> void:
	var b: Array = _buckets[int(building.get("_slot")) % CHECK_FRAMES]
	if not b.has(building):
		b.append(building)

func _remove(building: Node) -> void:
	for b in _buckets:
		(b as Array).erase(building)

## Cuantos edificios lleva (para las pruebas).
func count() -> int:
	var n := 0
	for b in _buckets:
		n += (b as Array).size()
	return n

func _process(delta: float) -> void:
	var step := ROUND_SECONDS / float(CHECK_FRAMES)
	_acc = minf(_acc + delta, ROUND_SECONDS)
	while _acc >= step:
		_acc -= step
		_check_next_bucket()
	_follow_zoom()

func _check_next_bucket() -> void:
	_frame = (_frame + 1) % CHECK_FRAMES
	var bucket: Array = _buckets[_frame]
	for i in range(bucket.size() - 1, -1, -1):
		var building = bucket[i]
		if not is_instance_valid(building):
			bucket.remove_at(i)
			continue
		building.check_state()

## Con zoom nuevo, los badges a la vista se recolocan (una vez por cambio).
func _follow_zoom() -> void:
	var cam := get_viewport().get_camera_2d() if get_viewport() != null else null
	if cam == null:
		return
	var z := cam.zoom.x
	if is_equal_approx(z, _zoom):
		return
	_zoom = z
	for b in _buckets:
		for building in b:
			if is_instance_valid(building):
				building.place_badge()
