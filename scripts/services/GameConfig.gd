extends Node
## Central configuration table for all tunable game values.
## Toggle dev_mode for fast testing. All durations go through time_multiplier.

# ── Master Controls ──

var dev_mode := true
var time_multiplier := 1.0

# ── Population & Morale Constants ──

var morale_start := 75
var morale_min := 0
var morale_max := 100
var morale_growth_threshold := 30
var morale_danger_threshold := 20
var morale_satisfied_recovery := 3
var morale_unsatisfied_penalty := -8
var population_start := 5
var consumption_interval := 30.0
var growth_interval := 20.0

# ── Random Event Timing ──

var event_interval_min := 120.0
var event_interval_max := 300.0
var event_interval_min_dev := 15.0
var event_interval_max_dev := 30.0

# ── Starting Resources ──

var starting_resources := {
	"gold": 300,
	"wood": 200,
}

# ── Upgrade System ──

var max_building_level := 3

## Cost multiplier per level: level 1 = base cost, level 2 = 1.8x, level 3 = 3.0x
var upgrade_cost_multiplier := [1.0, 1.8, 3.0]

## Production multiplier per level
var upgrade_production_multiplier := [1.0, 1.6, 2.5]

## Upgrade duration base (seconds), scaled by time_multiplier
var upgrade_base_duration := 15.0

# ── HQ Upgrade Override (capstone building, much more expensive) ──

var hq_upgrade_costs := {
	2: {"gold": 800, "steel": 500, "oil": 300, "wood": 400},
	3: {"gold": 1500, "steel": 800, "oil": 500, "wood": 700},
}

# ── Building Limits (max per type, -1 = unlimited) ──

var building_limits := {
	"sawmill": 3,
	"gold_mine": 2,
	"foundry": 2,
	"refinery": 1,
	"warehouse": 3,
	"barracks": 2,
	"tower": 4,
	"headquarters": 1,
	"house": 6,
	"garden": -1,
	"statue": 3,
	"fountain": 3,
	"road": -1,
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

var base_storage_cap := 800
var warehouse_storage_bonus := 400

# ── Building Processes (margins ~1.5x) ──

var building_processes := {
	"nucleo": [
		{"id": "wood_planks", "name": "PROC_WOOD_PLANKS", "duration": 30.0,
		 "cost": {"wood": 20}, "produces": {"wood": 35}},
		{"id": "iron_sheets", "name": "PROC_IRON_SHEETS", "duration": 45.0,
		 "cost": {"steel": 20}, "produces": {"steel": 30}},
		{"id": "water_pipes", "name": "PROC_WATER_PIPES", "duration": 60.0,
		 "cost": {"steel": 15, "wood": 10}, "produces": {"gold": 60}},
	],
	"sawmill": [
		{"id": "refined_lumber", "name": "PROC_REFINED_LUMBER", "duration": 30.0,
		 "cost": {"wood": 15}, "produces": {"wood": 25, "gold": 5}},
		{"id": "charcoal", "name": "PROC_CHARCOAL", "duration": 25.0,
		 "cost": {"wood": 25}, "produces": {"steel": 12}},
	],
	"gold_mine": [
		{"id": "deep_mining", "name": "PROC_DEEP_MINING", "duration": 35.0,
		 "cost": {"steel": 10}, "produces": {"gold": 35}},
		{"id": "gem_extraction", "name": "PROC_GEM_EXTRACTION", "duration": 60.0,
		 "cost": {"gold": 20, "steel": 5}, "produces": {"gold": 60}},
	],
	"foundry": [
		{"id": "alloy_smelting", "name": "PROC_ALLOY_SMELTING", "duration": 40.0,
		 "cost": {"steel": 20, "wood": 10}, "produces": {"steel": 45}},
		{"id": "armor_plates", "name": "PROC_ARMOR_PLATES", "duration": 45.0,
		 "cost": {"steel": 30}, "produces": {"steel": 15, "gold": 20}},
	],
	"refinery": [
		{"id": "fuel_distillation", "name": "PROC_FUEL_DISTILLATION", "duration": 30.0,
		 "cost": {"oil": 15}, "produces": {"oil": 25}},
		{"id": "chemical_processing", "name": "PROC_CHEMICAL_PROCESSING", "duration": 50.0,
		 "cost": {"oil": 20, "steel": 10}, "produces": {"oil": 18, "gold": 25}},
	],
}

# ── Mining Data ──

var mining_data := {
	"gold_vein": {"id": "mine_gold", "name": "PROC_MINE_GOLD", "duration": 12.0, "produces": {"gold": 20}},
	"iron_deposit": {"id": "mine_iron", "name": "PROC_MINE_IRON", "duration": 18.0, "produces": {"steel": 15}},
	"oil_well": {"id": "mine_oil", "name": "PROC_MINE_OIL", "duration": 22.0, "produces": {"oil": 10}},
	"forest": {"id": "mine_wood", "name": "PROC_MINE_WOOD", "duration": 8.0, "produces": {"wood": 20}},
}

# ── Deposit Config ──

var deposit_max_uses := {
	"gold_vein": 5,
	"iron_deposit": 4,
	"oil_well": 6,
	"forest": 4,
}

var deposit_count_min := 15
var deposit_count_max := 25
var deposit_center_exclusion := 4

# ── Deposit Resource Mapping (which resource a deposit requires unlocked) ──

var deposit_resource_required := {
	"gold_vein": "gold",
	"iron_deposit": "steel",
	"oil_well": "oil",
	"forest": "wood",
}

# ── Resource Display Colors ──

var resource_colors := {
	"gold": Color(1.0, 0.85, 0.1),
	"steel": Color(0.7, 0.75, 0.8),
	"oil": Color(0.5, 0.4, 0.6),
	"wood": Color(0.55, 0.35, 0.15),
}

# ── Economy ──

var demolish_refund_ratio := 0.5
var max_offline_seconds := 28800.0

# ── Market Config ──

var market_base_prices := {
	"wood": 3,
	"steel": 8,
	"oil": 12,
}

var market_spread := 0.3
var market_volatility := 0.15
var market_tick_interval := 60.0
var market_price_sensitivity := 0.02
var market_min_price_mult := 0.5
var market_max_price_mult := 2.5
var market_mean_reversion := 0.05

# ── Era Config ──

var era_names := {
	1: "ERA_FRONTIER",
	2: "ERA_INDUSTRIAL",
	3: "ERA_PETROLEUM",
}

# ── Milestone Definitions ──

var milestone_definitions := [
	{"id": "first_sawmill", "name": "MILE_PIONEER", "era": 1},
	{"id": "first_gold_mine", "name": "MILE_PROSPECTOR", "era": 1},
	{"id": "first_warehouse", "name": "MILE_STOCKPILER", "era": 1},
	{"id": "era_2", "name": "MILE_INDUSTRIALIST", "era": 2},
	{"id": "era_3", "name": "MILE_OIL_BARON", "era": 3},
	{"id": "market_10_trades", "name": "MILE_MERCHANT", "era": 0},
	{"id": "military_ready", "name": "MILE_COMMANDER", "era": 0},
	{"id": "hq_built", "name": "MILE_GENERAL", "era": 3},
	{"id": "hq_max", "name": "MILE_VICTORY", "era": 3},
]

# ── Tech Tree Config ──

## Bonuses applied by researched techs (modified at runtime)
var tech_production_bonus := 0.0       # added to production multiplier
var tech_consumption_reduction := 0.0  # subtracted from consumption per pop
var tech_build_speed_bonus := 0.0      # subtracted from build times

## 15 techs across 3 branches, 5 tiers each
var tech_definitions := [
	# ── Industrial Branch (production & efficiency) ──
	{"id": "ind_1", "branch": "industrial", "tier": 1, "name": "TECH_IND_1",
	 "cost": {"gold": 150, "wood": 80}, "duration": 30.0, "requires": [],
	 "bonus": {"production_mult": 0.1}},
	{"id": "ind_2", "branch": "industrial", "tier": 2, "name": "TECH_IND_2",
	 "cost": {"gold": 300, "steel": 100}, "duration": 45.0, "requires": ["ind_1"],
	 "bonus": {"storage_bonus": 200}},
	{"id": "ind_3", "branch": "industrial", "tier": 3, "name": "TECH_IND_3",
	 "cost": {"gold": 500, "steel": 200, "wood": 100}, "duration": 60.0, "requires": ["ind_2"],
	 "bonus": {"production_mult": 0.15}},
	{"id": "ind_4", "branch": "industrial", "tier": 4, "name": "TECH_IND_4",
	 "cost": {"gold": 800, "steel": 300, "oil": 100}, "duration": 90.0, "requires": ["ind_3"],
	 "bonus": {"consumption_reduction": 0.3}},
	{"id": "ind_5", "branch": "industrial", "tier": 5, "name": "TECH_IND_5",
	 "cost": {"gold": 1200, "steel": 500, "oil": 200}, "duration": 120.0, "requires": ["ind_4"],
	 "bonus": {"production_mult": 0.25}},

	# ── Military Branch (defense & combat prep) ──
	{"id": "mil_1", "branch": "military", "tier": 1, "name": "TECH_MIL_1",
	 "cost": {"gold": 200, "steel": 50}, "duration": 30.0, "requires": [],
	 "bonus": {"morale_bonus": 1}},
	{"id": "mil_2", "branch": "military", "tier": 2, "name": "TECH_MIL_2",
	 "cost": {"gold": 350, "steel": 150}, "duration": 45.0, "requires": ["mil_1"],
	 "bonus": {"morale_bonus": 1}},
	{"id": "mil_3", "branch": "military", "tier": 3, "name": "TECH_MIL_3",
	 "cost": {"gold": 600, "steel": 250, "wood": 100}, "duration": 60.0, "requires": ["mil_2"],
	 "bonus": {"morale_bonus": 2}},
	{"id": "mil_4", "branch": "military", "tier": 4, "name": "TECH_MIL_4",
	 "cost": {"gold": 900, "steel": 400, "oil": 150}, "duration": 90.0, "requires": ["mil_3"],
	 "bonus": {"morale_bonus": 2}},
	{"id": "mil_5", "branch": "military", "tier": 5, "name": "TECH_MIL_5",
	 "cost": {"gold": 1500, "steel": 600, "oil": 300}, "duration": 120.0, "requires": ["mil_4"],
	 "bonus": {"morale_bonus": 3}},

	# ── Logistics Branch (market, storage, speed) ──
	{"id": "log_1", "branch": "logistics", "tier": 1, "name": "TECH_LOG_1",
	 "cost": {"gold": 120, "wood": 60}, "duration": 25.0, "requires": [],
	 "bonus": {"market_spread_reduction": 0.05}},
	{"id": "log_2", "branch": "logistics", "tier": 2, "name": "TECH_LOG_2",
	 "cost": {"gold": 250, "wood": 120, "steel": 50}, "duration": 40.0, "requires": ["log_1"],
	 "bonus": {"storage_bonus": 300}},
	{"id": "log_3", "branch": "logistics", "tier": 3, "name": "TECH_LOG_3",
	 "cost": {"gold": 450, "steel": 150, "wood": 80}, "duration": 55.0, "requires": ["log_2"],
	 "bonus": {"build_speed": 0.15}},
	{"id": "log_4", "branch": "logistics", "tier": 4, "name": "TECH_LOG_4",
	 "cost": {"gold": 700, "steel": 250, "oil": 100}, "duration": 80.0, "requires": ["log_3"],
	 "bonus": {"market_spread_reduction": 0.08}},
	{"id": "log_5", "branch": "logistics", "tier": 5, "name": "TECH_LOG_5",
	 "cost": {"gold": 1100, "steel": 400, "oil": 250}, "duration": 110.0, "requires": ["log_4"],
	 "bonus": {"storage_bonus": 500, "build_speed": 0.2}},
]

# ── Duration Helpers ──

func get_duration(base: float) -> float:
	if dev_mode:
		return maxf(base * 0.1, 1.0)
	return base * time_multiplier

func get_production_with_tech(base_mult: float) -> float:
	return base_mult + tech_production_bonus

func get_build_time(base: float) -> float:
	if base <= 0.0:
		return 0.0
	if dev_mode:
		return 1.0
	var speed_reduction := maxf(0.0, 1.0 - tech_build_speed_bonus)
	return base * time_multiplier * speed_reduction

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
	# HQ has special override costs
	if data.id == "headquarters" and hq_upgrade_costs.has(to_level):
		var hq_cost_raw: Dictionary = hq_upgrade_costs[to_level]
		var cost := {}
		for res_name in hq_cost_raw:
			var type := ResourceManager.name_to_type(res_name)
			if type != -1:
				cost[type] = hq_cost_raw[res_name]
		return cost
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

# ── Deposit Helpers ──

func is_deposit_unlocked(deposit_id: String) -> bool:
	var res_name: String = deposit_resource_required.get(deposit_id, "")
	if res_name.is_empty():
		return true
	return ResourceManager.is_unlocked_by_name(res_name)
