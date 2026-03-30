extends Node
## Central configuration table for all tunable game values.
## Toggle dev_mode for fast testing. All durations go through time_multiplier.
##
## Usage:
##   GameConfig.dev_mode = true      → all times ~1-2s for testing
##   GameConfig.time_multiplier = 0.5 → everything 2x faster
##   GameConfig.get_duration(30.0)   → returns 30.0 * time_multiplier (or 1.0 in dev)

# ── Master Controls ──

## When true, all durations become near-instant for testing
var dev_mode := true

## Global speed multiplier for all durations (build, process, mining, production)
## 1.0 = normal, 0.5 = 2x faster, 0.1 = 10x faster
var time_multiplier := 1.0

# ── Starting Resources ──

var starting_resources := {
	"gold": 500,
	"steel": 300,
	"oil": 200,
	"wood": 400,
}

# ── Building Processes (nucleo) ──

var building_processes := {
	"nucleo": [
		{"id": "wood_planks", "name": "PROC_WOOD_PLANKS", "duration": 30.0,
		 "cost": {"wood": 20}, "produces": {"wood": 50}},
		{"id": "iron_sheets", "name": "PROC_IRON_SHEETS", "duration": 45.0,
		 "cost": {"steel": 30}, "produces": {"steel": 70}},
		{"id": "water_pipes", "name": "PROC_WATER_PIPES", "duration": 60.0,
		 "cost": {"steel": 20, "wood": 10}, "produces": {"gold": 100}},
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

## Fraction of build cost returned on demolish (0.5 = 50%)
var demolish_refund_ratio := 0.5

## Max offline seconds for progression (28800 = 8 hours)
var max_offline_seconds := 28800.0

# ── Duration Helpers ──

## Apply time_multiplier (or dev override) to any base duration
func get_duration(base: float) -> float:
	if dev_mode:
		return 1.0
	return base * time_multiplier

## Same but for build times specifically (allows separate tuning later)
func get_build_time(base: float) -> float:
	if base <= 0.0:
		return 0.0
	if dev_mode:
		return 1.0
	return base * time_multiplier

## Same for production intervals
func get_production_interval(base: float) -> float:
	if base <= 0.0:
		return 0.0
	if dev_mode:
		return 2.0
	return base * time_multiplier

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
