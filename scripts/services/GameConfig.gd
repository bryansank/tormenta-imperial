extends Node
## Central configuration table for all tunable game values.
## Toggle dev_mode for fast testing. All durations go through time_multiplier.

# ── Master Controls ──

var dev_mode := true
var time_multiplier := 1.0

# ── Starting Resources ──

var starting_resources := {
	"gold": 500,
	"steel": 300,
	"oil": 200,
	"wood": 400,
}

# ── Upgrade System ──

var max_building_level := 3

## Cost multiplier per level: level 1 = base cost, level 2 = 1.8x, level 3 = 3.0x
var upgrade_cost_multiplier := [1.0, 1.8, 3.0]

## Production multiplier per level
var upgrade_production_multiplier := [1.0, 1.6, 2.5]

## Upgrade duration base (seconds), scaled by time_multiplier
var upgrade_base_duration := 15.0

# ── Building Limits (max per type, -1 = unlimited) ──

var building_limits := {
	"sawmill": 3,
	"gold_mine": 2,
	"foundry": 2,
	"refinery": 1,
	"warehouse": 2,
	"barracks": 2,
	"tower": 4,
	"headquarters": 1,
}

# ── Building Prerequisites (must have at least 1 of each listed) ──

var building_prerequisites := {
	"foundry": ["sawmill"],
	"refinery": ["foundry"],
	"barracks": ["foundry", "sawmill"],
	"tower": ["barracks"],
	"headquarters": ["barracks", "refinery"],
}

# ── Storage ──

var base_storage_cap := 1000
var warehouse_storage_bonus := 500

# ── Building Processes ──

var building_processes := {
	"nucleo": [
		{"id": "wood_planks", "name": "PROC_WOOD_PLANKS", "duration": 30.0,
		 "cost": {"wood": 20}, "produces": {"wood": 50}},
		{"id": "iron_sheets", "name": "PROC_IRON_SHEETS", "duration": 45.0,
		 "cost": {"steel": 30}, "produces": {"steel": 70}},
		{"id": "water_pipes", "name": "PROC_WATER_PIPES", "duration": 60.0,
		 "cost": {"steel": 20, "wood": 10}, "produces": {"gold": 100}},
	],
	"sawmill": [
		{"id": "refined_lumber", "name": "PROC_REFINED_LUMBER", "duration": 30.0,
		 "cost": {"wood": 15}, "produces": {"wood": 30, "gold": 5}},
		{"id": "charcoal", "name": "PROC_CHARCOAL", "duration": 25.0,
		 "cost": {"wood": 20}, "produces": {"steel": 10}},
	],
	"gold_mine": [
		{"id": "deep_mining", "name": "PROC_DEEP_MINING", "duration": 35.0,
		 "cost": {"steel": 10}, "produces": {"gold": 40}},
		{"id": "gem_extraction", "name": "PROC_GEM_EXTRACTION", "duration": 60.0,
		 "cost": {"gold": 20, "steel": 5}, "produces": {"gold": 80}},
	],
	"foundry": [
		{"id": "alloy_smelting", "name": "PROC_ALLOY_SMELTING", "duration": 40.0,
		 "cost": {"steel": 25, "wood": 10}, "produces": {"steel": 60}},
		{"id": "armor_plates", "name": "PROC_ARMOR_PLATES", "duration": 45.0,
		 "cost": {"steel": 30}, "produces": {"steel": 20, "gold": 15}},
	],
	"refinery": [
		{"id": "fuel_distillation", "name": "PROC_FUEL_DISTILLATION", "duration": 30.0,
		 "cost": {"oil": 15}, "produces": {"oil": 35}},
		{"id": "chemical_processing", "name": "PROC_CHEMICAL_PROCESSING", "duration": 50.0,
		 "cost": {"oil": 20, "steel": 10}, "produces": {"oil": 25, "gold": 30}},
	],
}

# ── Mining Data ──

var mining_data := {
	"gold_vein": {"id": "mine_gold", "name": "PROC_MINE_GOLD", "duration": 15.0, "produces": {"gold": 25}},
	"iron_deposit": {"id": "mine_iron", "name": "PROC_MINE_IRON", "duration": 20.0, "produces": {"steel": 20}},
	"oil_well": {"id": "mine_oil", "name": "PROC_MINE_OIL", "duration": 25.0, "produces": {"oil": 15}},
	"forest": {"id": "mine_wood", "name": "PROC_MINE_WOOD", "duration": 10.0, "produces": {"wood": 30}},
}

# ── Deposit Config ──

var deposit_max_uses := {
	"gold_vein": 5,
	"iron_deposit": 4,
	"oil_well": 6,
	"forest": 3,
}

var deposit_count_min := 15
var deposit_count_max := 25
var deposit_center_exclusion := 4

# ── Economy ──

var demolish_refund_ratio := 0.5
var max_offline_seconds := 28800.0

# ── Duration Helpers ──

func get_duration(base: float) -> float:
	if dev_mode:
		return 1.0
	return base * time_multiplier

func get_build_time(base: float) -> float:
	if base <= 0.0:
		return 0.0
	if dev_mode:
		return 1.0
	return base * time_multiplier

func get_production_interval(base: float) -> float:
	if base <= 0.0:
		return 0.0
	if dev_mode:
		return 2.0
	return base * time_multiplier

func get_upgrade_duration(level: int) -> float:
	return get_duration(upgrade_base_duration * level)

# ── Upgrade Helpers ──

func get_upgrade_cost(data: BuildingData, to_level: int) -> Dictionary:
	if to_level < 1 or to_level > max_building_level:
		return {}
	var mult: float = upgrade_cost_multiplier[to_level - 1]
	var cost := {}
	if data.cost_gold > 0:
		cost[ResourceManager.Type.GOLD] = int(data.cost_gold * mult)
	if data.cost_steel > 0:
		cost[ResourceManager.Type.STEEL] = int(data.cost_steel * mult)
	if data.cost_oil > 0:
		cost[ResourceManager.Type.OIL] = int(data.cost_oil * mult)
	if data.cost_wood > 0:
		cost[ResourceManager.Type.WOOD] = int(data.cost_wood * mult)
	return cost

func get_production_multiplier(level: int) -> float:
	if level < 1 or level > max_building_level:
		return 1.0
	return upgrade_production_multiplier[level - 1]

# ── Process/Mining with duration already scaled ──

func get_processes_for(building_id: String) -> Array:
	var procs: Array = building_processes.get(building_id, [])
	var result: Array = []
	for proc in procs:
		var copy: Dictionary = proc.duplicate()
		copy["duration"] = get_duration(proc["duration"])
		result.append(copy)
	return result

func get_mining_info(deposit_id: String) -> Dictionary:
	var data: Dictionary = mining_data.get(deposit_id, {})
	if data.is_empty():
		return {}
	var copy: Dictionary = data.duplicate()
	copy["duration"] = get_duration(data["duration"])
	return copy

func get_deposit_max_uses(deposit_id: String) -> int:
	return deposit_max_uses.get(deposit_id, 3)

# ── Building Limit Helpers ──

func get_building_limit(building_id: String) -> int:
	return building_limits.get(building_id, -1)

func get_prerequisites(building_id: String) -> Array:
	return building_prerequisites.get(building_id, [])

# ── Storage Helpers ──

func get_storage_cap(warehouse_count: int) -> int:
	return base_storage_cap + (warehouse_count * warehouse_storage_bonus)
