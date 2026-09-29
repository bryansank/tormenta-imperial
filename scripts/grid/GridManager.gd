extends Node
## Manages the logical grid: converts world positions to cell coordinates,
## tracks which cells are occupied, supports multi-cell buildings.

## Tamano de la rejilla de un guardado sin la clave "grid" (todos los de antes
## del mapa aleatorio) y de las escenas montadas a mano en los tests.
const DEFAULT_SIZE := 40

@export var cell_size: float = 2.0
@export var grid_width: int = DEFAULT_SIZE   # Number of cells along X
@export var grid_height: int = DEFAULT_SIZE  # Number of cells along Z

# Origin offset: the grid is centred on the world origin, so with 40x40 cells of
# 2.0 it starts at world (-40, -40). set_grid_size() keeps it centred.
var _origin := Vector3(-40.0, 0.0, -40.0)

## Semilla de la forma de la isla de esta partida (IslandGenerator.shape_for_seed).
## Viaja con el tamano en el guardado, asi la isla sale igual al cargar y en las
## dos vistas. -1 = sin semilla (escena de test): cada vista sortea la suya.
var island_seed: int = -1

## Cambia el tamano de la rejilla y la recentra. Solo con la rejilla vacia: una
## partida nueva antes de poner el Nucleo, o una carga antes de poner nada. Emite
## EventBus.grid_resized si el tamano cambia (la isla, la rejilla dibujada y las
## camaras se reajustan).
func set_grid_size(width: int, height: int) -> void:
	_apply_map(width, height, island_seed)

## Tamano y semilla de isla juntos. Avisa (grid_resized) si cambia cualquiera de
## los dos: una isla de otra forma tambien hay que redibujarla.
func _apply_map(width: int, height: int, new_seed: int) -> void:
	width = maxi(width, 1)
	height = maxi(height, 1)
	if not _cell_to_building.is_empty():
		push_warning("GridManager.set_grid_size: la rejilla no esta vacia; lo que haya queda en sus celdas")
	var changed := width != grid_width or height != grid_height or new_seed != island_seed
	grid_width = width
	grid_height = height
	island_seed = new_seed
	_origin = Vector3(-width * cell_size * 0.5, 0.0, -height * cell_size * 0.5)
	if changed:
		EventBus.grid_resized.emit(width, height)

## Sortea el tamano (y la forma de la isla) de una partida nueva, con el RNG
## global: una semilla fijada con seed() da siempre el mismo mapa.
func roll_new_map() -> void:
	var lo: int = mini(GameConfig.grid_size_min, GameConfig.grid_size_max)
	var hi: int = maxi(GameConfig.grid_size_min, GameConfig.grid_size_max)
	var w: int = _roll_even(lo, hi)
	var h: int = _roll_even(lo, hi)
	_apply_map(w, h, randi() % 1000000)

## Un lado par en [lo, hi] (lo si el rango no tiene ninguno).
static func _roll_even(lo: int, hi: int) -> int:
	var first: int = lo + (lo % 2)
	if first > hi:
		return lo
	return first + 2 * randi_range(0, (hi - first) / 2)

## Vuelve al 40x40 de siempre, sin semilla de isla.
func reset_size() -> void:
	_apply_map(DEFAULT_SIZE, DEFAULT_SIZE, -1)

func get_save_data() -> Dictionary:
	return {"width": grid_width, "height": grid_height, "island_seed": island_seed}

## Idempotente. Sin clave (guardado de antes del mapa aleatorio) es 40x40.
func load_save_data(data: Dictionary) -> void:
	_apply_map(int(data.get("width", DEFAULT_SIZE)), int(data.get("height", DEFAULT_SIZE)),
		int(data.get("island_seed", -1)))

## World position of the grid's corner (cell 0,0). Public so the island and the
## grid overlay can fit themselves to the real grid instead of hardcoding it.
func get_origin() -> Vector3:
	return _origin

## World size of the whole grid (X, Z).
func get_world_size() -> Vector2:
	return Vector2(grid_width * cell_size, grid_height * cell_size)

# Cell → Node reference of the building occupying it
var _cell_to_building: Dictionary = {}
# Node → { "data": BuildingData, "origin_cell": Vector2i, "cells": Array[Vector2i] }
var _building_info: Dictionary = {}

func world_to_cell(world_pos: Vector3) -> Vector2i:
	var local := world_pos - _origin
	var cx: int = floori(local.x / cell_size)
	var cy: int = floori(local.z / cell_size)
	return Vector2i(clampi(cx, 0, grid_width - 1), clampi(cy, 0, grid_height - 1))

func cell_to_world(cell: Vector2i) -> Vector3:
	var x: float = _origin.x + (cell.x * cell_size) + (cell_size * 0.5)
	var z: float = _origin.z + (cell.y * cell_size) + (cell_size * 0.5)
	return Vector3(x, 0.0, z)

## Get the world center for a multi-cell building placed at origin_cell.
func building_center(origin_cell: Vector2i, grid_size: Vector2i) -> Vector3:
	var cx: float = _origin.x + (origin_cell.x * cell_size) + (grid_size.x * cell_size * 0.5)
	var cz: float = _origin.z + (origin_cell.y * cell_size) + (grid_size.y * cell_size * 0.5)
	return Vector3(cx, 0.0, cz)

func is_valid_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < grid_width and cell.y >= 0 and cell.y < grid_height

func is_cell_free(cell: Vector2i) -> bool:
	return is_valid_cell(cell) and not _cell_to_building.has(cell)

## Check if all cells for a building of grid_size at origin_cell are free.
## If ignore_building is set, those cells are treated as free (for move operations).
## ignore_obstacle does the same for a deposit the building is about to consume
## (the Refinery sits on its oil well), so moving a consumer can ignore both.
func can_place(origin_cell: Vector2i, grid_size: Vector2i, ignore_building: Node = null, ignore_obstacle: Node = null) -> bool:
	var cells := _get_cells_for(origin_cell, grid_size)
	for cell in cells:
		if not is_valid_cell(cell):
			return false
		if _cell_to_building.has(cell):
			var occupant: Node = _cell_to_building[cell]
			if occupant != ignore_building and (ignore_obstacle == null or occupant != ignore_obstacle):
				return false
	return true

## Cells covered by a footprint of grid_size placed at origin. Public twin of
## _get_cells_for, for callers outside this class (placement rules, tests).
func cells_for(origin: Vector2i, grid_size: Vector2i) -> Array:
	return _get_cells_for(origin, grid_size)

## Place a building. Returns the Node or null if invalid.
func place_building(origin_cell: Vector2i, data: BuildingData, building_node: Node) -> bool:
	if not can_place(origin_cell, data.grid_size):
		return false
	var cells := _get_cells_for(origin_cell, data.grid_size)
	for cell in cells:
		_cell_to_building[cell] = building_node
	_building_info[building_node] = {
		"data": data,
		"origin_cell": origin_cell,
		"cells": cells,
	}
	return true

## Move a building to a new cell. Returns true if successful.
func move_building(building_node: Node, new_origin: Vector2i) -> bool:
	if not _building_info.has(building_node):
		return false
	var info: Dictionary = _building_info[building_node]
	var data: BuildingData = info["data"]
	if not can_place(new_origin, data.grid_size, building_node):
		return false
	# Free old cells
	for cell in info["cells"]:
		_cell_to_building.erase(cell)
	# Occupy new cells
	var new_cells := _get_cells_for(new_origin, data.grid_size)
	for cell in new_cells:
		_cell_to_building[cell] = building_node
	_building_info[building_node]["origin_cell"] = new_origin
	_building_info[building_node]["cells"] = new_cells
	return true

## Remove a building entirely.
func remove_building(building_node: Node) -> void:
	if not _building_info.has(building_node):
		return
	for cell in _building_info[building_node]["cells"]:
		_cell_to_building.erase(cell)
	_building_info.erase(building_node)

## Get the building node at a given cell, or null.
func get_building_at(cell: Vector2i) -> Node:
	return _cell_to_building.get(cell, null)

## Get info dict for a building node.
func get_building_info(building_node: Node) -> Dictionary:
	return _building_info.get(building_node, {})

## Place a non-building obstacle (resource deposit) on one or more cells.
func place_obstacle(cell: Vector2i, node: Node, grid_size: Vector2i = Vector2i(1, 1)) -> bool:
	var cells := _get_cells_for(cell, grid_size)
	for c in cells:
		if not is_cell_free(c):
			return false
	for c in cells:
		_cell_to_building[c] = node
	return true

## Remove an obstacle from one or more cells.
func remove_obstacle(cell: Vector2i, grid_size: Vector2i = Vector2i(1, 1)) -> void:
	var cells := _get_cells_for(cell, grid_size)
	for c in cells:
		_cell_to_building.erase(c)

## Get all placed buildings as an array of info dicts (includes "node" key).
func get_all_buildings() -> Array:
	var result: Array = []
	for node in _building_info:
		if is_instance_valid(node):
			var info: Dictionary = _building_info[node].duplicate()
			info["node"] = node
			result.append(info)
	return result

## Clear all tracked buildings and obstacles.
func clear_all() -> void:
	_cell_to_building.clear()
	_building_info.clear()

func _get_cells_for(origin: Vector2i, grid_size: Vector2i) -> Array:
	var cells: Array = []
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			cells.append(Vector2i(origin.x + x, origin.y + y))
	return cells
