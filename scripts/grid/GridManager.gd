extends Node
## Manages the logical grid: converts world positions to cell coordinates,
## tracks which cells are occupied, and emits signals through EventBus.

@export var cell_size: float = 2.0
@export var grid_width: int = 25   # Number of cells along X (50 / 2.0)
@export var grid_height: int = 25  # Number of cells along Z

# Origin offset: the grid starts at world (-25, -25) so cell (0,0) maps there
var _origin := Vector3(-25.0, 0.0, -25.0)

# Occupancy map: Dictionary[Vector2i, bool] — true means occupied
var _occupied: Dictionary = {}

## Convert a world position (Vector3) to grid coordinates (Vector2i).
func world_to_cell(world_pos: Vector3) -> Vector2i:
	var local := world_pos - _origin
	var cx := floori(local.x / cell_size)
	var cy := floori(local.z / cell_size)
	return Vector2i(clampi(cx, 0, grid_width - 1), clampi(cy, 0, grid_height - 1))

## Convert grid coordinates (Vector2i) to the center of that cell in world space.
func cell_to_world(cell: Vector2i) -> Vector3:
	var x := _origin.x + (cell.x * cell_size) + (cell_size * 0.5)
	var z := _origin.z + (cell.y * cell_size) + (cell_size * 0.5)
	return Vector3(x, 0.0, z)

## Check if a cell is within grid bounds.
func is_valid_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < grid_width and cell.y >= 0 and cell.y < grid_height

## Check if a cell is free (not occupied).
func is_cell_free(cell: Vector2i) -> bool:
	return is_valid_cell(cell) and not _occupied.has(cell)

## Mark a cell as occupied. Returns true if successful.
func occupy_cell(cell: Vector2i) -> bool:
	if not is_cell_free(cell):
		return false
	_occupied[cell] = true
	return true

## Free an occupied cell.
func free_cell(cell: Vector2i) -> void:
	_occupied.erase(cell)

## Get all occupied cells.
func get_occupied_cells() -> Array:
	return _occupied.keys()
