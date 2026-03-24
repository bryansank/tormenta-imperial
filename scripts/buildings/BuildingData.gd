class_name BuildingData
extends Resource
## Data definition for a building type. Each .tres file is one building kind.

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""

# Grid size in cells (e.g. 1x1, 2x2)
@export var grid_size: Vector2i = Vector2i(1, 1)

# Cost to build {ResourceManager.Type: amount}
@export var cost_gold: int = 0
@export var cost_steel: int = 0
@export var cost_oil: int = 0
@export var cost_wood: int = 0

# Build time in seconds (0 = instant)
@export var build_time: float = 0.0

# Resource production per cycle (passive income)
@export var produces_gold: int = 0
@export var produces_steel: int = 0
@export var produces_oil: int = 0
@export var produces_wood: int = 0
@export var production_interval: float = 10.0  # seconds between production

# Visual
@export var mesh_height: float = 1.5
@export var mesh_color: Color = Color(0.5, 0.5, 0.5, 1.0)

# Stats
@export var max_health: int = 100

## Helper: get cost as dictionary compatible with ResourceManager.
func get_cost() -> Dictionary:
	var cost := {}
	if cost_gold > 0:
		cost[ResourceManager.Type.GOLD] = cost_gold
	if cost_steel > 0:
		cost[ResourceManager.Type.STEEL] = cost_steel
	if cost_oil > 0:
		cost[ResourceManager.Type.OIL] = cost_oil
	if cost_wood > 0:
		cost[ResourceManager.Type.WOOD] = cost_wood
	return cost

## Helper: check if this building produces any resources.
func is_producer() -> bool:
	return produces_gold > 0 or produces_steel > 0 or produces_oil > 0 or produces_wood > 0
