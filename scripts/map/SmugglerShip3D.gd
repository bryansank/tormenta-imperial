extends Node3D
## El barco del contrabandista en la vista 3D (feat/edificios-economia, doc 14
## §P4). Hijo de BuildingPlacer, como WorkerWalkers: solo vista, nunca se
## guarda. Lo que pasa lo decide EconomyManager; esto solo lo ensena.
##
## Rendimiento (doc 21 §6.6): una MeshInstance3D con la malla compartida de
## EconomyToys.ship_mesh() (~420 triangulos, los dos materiales de la maqueta),
## escondida el 90 % del tiempo. Sin `_process`: llega y se va con un Tween de
## pocos segundos, y mientras esta atracado se mece con un Tween en bucle que
## se mata al zarpar.

const Toys := preload("res://scripts/buildings/EconomyToys.gd")
const DepositMeshScript := preload("res://scripts/map/DepositMesh.gd")

## Casillas desde las que entra (y hacia las que sale) a lo largo de la orilla.
const SAIL_CELLS := 7.0
## Segundos reales de llegada y salida (es aspecto: no siguen a la velocidad x2).
const SAIL_SECONDS := 4.5
## Vaiven atracado: altura (m) y medio periodo (s).
const BOB_HEIGHT := 0.05
const BOB_SECONDS := 1.6

var _hull: MeshInstance3D
var _move: Tween = null
var _bob: Tween = null

func _ready() -> void:
	name = "SmugglerShip3D"
	_hull = MeshInstance3D.new()
	_hull.name = "Hull"
	_hull.mesh = Toys.ship_mesh()
	_hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_hull)
	visible = false
	EventBus.smuggler_ship_arrived.connect(func(_o, _p): _arrive(true))
	EventBus.smuggler_ship_departed.connect(func(_r): _leave())
	EventBus.building_moved.connect(func(_a, _b): _resync.call_deferred())
	EventBus.building_demolished.connect(func(_n, _c): _resync.call_deferred())
	EventBus.game_load_completed.connect(func(): _resync.call_deferred())
	EventBus.game_new_started.connect(_hide_now)

## Tras cargar o mover el Puerto: un barco atracado aparece ya en su sitio.
func _resync() -> void:
	if EconomyManager.is_ship_docked() and not EconomyManager.ship_berth().is_empty():
		_arrive(false)
	elif visible:
		_hide_now()

func _arrive(sail: bool) -> void:
	var berth: Dictionary = EconomyManager.ship_berth()
	if berth.is_empty():
		return
	_kill()
	var along: Vector3 = berth["along"]
	var dock_pos: Vector3 = berth["pos"] + Vector3(0, DepositMeshScript.SEA_Y, 0)
	# Proa hacia donde navega: entra desde +along y sale por -along.
	var dir := -along
	transform = Transform3D(Basis(dir, Vector3.UP, dir.cross(Vector3.UP)), dock_pos)
	visible = true
	if sail:
		position = dock_pos + along * SAIL_CELLS * GridManager.cell_size
		_move = create_tween()
		_move.tween_property(self, "position", dock_pos, SAIL_SECONDS) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_start_bob()

func _leave() -> void:
	if not visible:
		return
	var berth: Dictionary = EconomyManager.ship_berth()
	if berth.is_empty():
		_hide_now()
		return
	_kill()
	var along: Vector3 = berth["along"]
	var target := position - along * SAIL_CELLS * GridManager.cell_size
	_move = create_tween()
	_move.tween_property(self, "position", target, SAIL_SECONDS) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_move.tween_callback(_hide_now)

func _start_bob() -> void:
	_hull.position = Vector3.ZERO
	_bob = create_tween().set_loops()
	_bob.tween_property(_hull, "position:y", BOB_HEIGHT, BOB_SECONDS).set_trans(Tween.TRANS_SINE)
	_bob.tween_property(_hull, "position:y", -BOB_HEIGHT, BOB_SECONDS).set_trans(Tween.TRANS_SINE)

func _kill() -> void:
	if _move != null and _move.is_valid():
		_move.kill()
	if _bob != null and _bob.is_valid():
		_bob.kill()
	_move = null
	_bob = null

func _hide_now() -> void:
	_kill()
	visible = false
