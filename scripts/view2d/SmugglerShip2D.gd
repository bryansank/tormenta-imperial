extends Node2D
## El barco del contrabandista en la vista 2D (feat/edificios-economia): la
## silueta del vapor (BuildingArt2D.draw_smuggler_ship) junto al Puerto. Hijo de
## BuildingPlacer2D. Solo vista; lo decide EconomyManager.
##
## Rendimiento: un solo `_draw` que no se repite (sin queue_redraw por
## fotograma, sin `_process`); llega y se va con un Tween corto.

const Art := preload("res://scripts/view2d/BuildingArt2D.gd")
const View2D := preload("res://scripts/view2d/View2D.gd")
const Toys := preload("res://scripts/buildings/EconomyToys.gd")

## Casillas desde las que entra (y hacia las que sale) a lo largo de la orilla.
const SAIL_CELLS := 7.0
const SAIL_SECONDS := 4.5

var _move: Tween = null

func _ready() -> void:
	name = "SmugglerShip2D"
	z_index = 2
	visible = false
	EventBus.smuggler_ship_arrived.connect(func(_o, _p): _arrive(true))
	EventBus.smuggler_ship_departed.connect(func(_r): _leave())
	EventBus.building_moved.connect(func(_a, _b): _resync.call_deferred())
	EventBus.building_demolished.connect(func(_n, _c): _resync.call_deferred())
	EventBus.game_load_completed.connect(func(): _resync.call_deferred())
	EventBus.game_new_started.connect(_hide_now)

func _draw() -> void:
	Art.draw_smuggler_ship(self, Toys.SHIP_LENGTH * View2D.PX_PER_UNIT)

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
	var dock_px := View2D.world_to_px(berth["pos"])
	var along_px := Vector2(along.x, along.z)
	# Proa hacia donde navega: entra desde +along y sale por -along.
	rotation = (-along_px).angle()
	position = dock_px
	visible = true
	queue_redraw()
	if sail:
		position = dock_px + along_px * SAIL_CELLS * View2D.cell_px()
		_move = create_tween()
		_move.tween_property(self, "position", dock_px, SAIL_SECONDS) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _leave() -> void:
	if not visible:
		return
	var berth: Dictionary = EconomyManager.ship_berth()
	if berth.is_empty():
		_hide_now()
		return
	_kill()
	var along: Vector3 = berth["along"]
	var target := position - Vector2(along.x, along.z) * SAIL_CELLS * View2D.cell_px()
	_move = create_tween()
	_move.tween_property(self, "position", target, SAIL_SECONDS) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_move.tween_callback(_hide_now)

func _kill() -> void:
	if _move != null and _move.is_valid():
		_move.kill()
	_move = null

func _hide_now() -> void:
	_kill()
	visible = false
