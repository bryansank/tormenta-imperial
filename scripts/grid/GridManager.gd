extends Node
## Manages the logical grid: converts world positions to cell coordinates,
## tracks which cells are occupied, supports multi-cell buildings.

@export var cell_size: float = 2.0
@export var grid_width: int = 25   # Number of cells along X (50 / 2.0)
@export var grid_height: int = 25  # Number of cells along Z

# Origin offset: the grid starts at world (-25, -25) so cell (0,0) maps there
var _origin := Vector3(-25.0, 0.0, -25.0)

# Cell → Node3D reference of the building occupying it
var _cell_to_building: Dictionary = {}
# Node3D → { "data": BuildingData, "origin_cell": Vector2i, "cells": Array[Vector2i] }
var _building_info: Dictionary = {}

func world_to_cell(world_pos: Vector3) -> Vector2i:
	var local := world_pos - _origin
	var cx := floori(local.x / cell_size)
	var cy := floori(local.z / cell_size)
	return Vector2i(clampi(cx, 0, grid_width - 1), clampi(cy, 0, grid_height - 1))

func cell_to_world(cell: Vector2i) -> Vector3:
	var x := _origin.x + (cell.x * cell_size) + (cell_size * 0.5)
	var z := _origin.z + (cell.y * cell_size) + (cell_size * 0.5)
	return Vector3(x, 0.0, z)

## Get the world center for a multi-cell building placed at origin_cell.
func building_center(origin_cell: Vector2i, grid_size: Vector2i) -> Vector3:
	var cx := _origin.x + (origin_cell.x * cell_size) + (grid_size.x * cell_size * 0.5)
	var cz := _origin.z + (origin_cell.y * cell_size) + (grid_size.y * cell_size * 0.5)
	return Vector3(cx, 0.0, cz)

func is_valid_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < grid_width and cell.y >= 0 and cell.y < grid_height

func is_cell_free(cell: Vector2i) -> bool:
	return is_valid_cell(cell) and not _cell_to_building.has(cell)

## Check if all cells for a building of grid_size at origin_cell are free.
## If ignore_building is set, those cells are treated as free (for move operations).
func can_place(origin_cell: Vector2i, grid_size: Vector2i, ignore_building: Node3D = null) -> bool:
	var cells := _get_cells_for(origin_cell, grid_size)
	for cell in cells:
		if not is_valid_cell(cell):
			return false
		if _cell_to_building.has(cell) and _cell_to_building[cell] != ignore_building:
			return false
	return true

## Place a building. Returns the Node3D or null if invalid.
func place_building(origin_cell: Vector2i, data: BuildingData, building_node: Node3D) -> bool:
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
func move_building(building_node: Node3D, new_origin: Vector2i) -> bool:
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
func remove_building(building_node: Node3D) -> void:
	if not _building_info.has(building_node):
		return
	for cell in _building_info[building_node]["cells"]:
		_cell_to_building.erase(cell)
	_building_info.erase(building_node)

## Get the building node at a given cell, or null.
func get_building_at(cell: Vector2i) -> Node3D:
	return _cell_to_building.get(cell, null)

## Get info dict for a building node.
func get_building_info(building_node: Node3D) -> Dictionary:
	return _building_info.get(building_node, {})

## Place a non-building obstacle (resource deposit) on a single cell.
func place_obstacle(cell: Vector2i, node: Node3D) -> bool:
	if not is_cell_free(cell):
		return false
	_cell_to_building[cell] = node
	return true

## Remove an obstacle from a single cell.
func remove_obstacle(cell: Vector2i) -> void:
	_cell_to_building.erase(cell)

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
