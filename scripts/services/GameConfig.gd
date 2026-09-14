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
	"sawmill": 5,
	"gold_mine": 4,
	"foundry": 3,
	"refinery": 2,
	"warehouse": 5,
	"barracks": 3,
	"tower": 6,
	"headquarters": 1,
	"house": 10,
	"garden": -1,
	"statue": 5,
	"fountain": 5,
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

# ── Deposit Placement Requirements (building must overlap a deposit) ──

var building_requires_deposit := {
	"refinery": "oil_well",
}

# ── Storage ──
#
# El almacen es UNA bolsa compartida por los cuatro recursos, no un tope por
# recurso. Guardar oro tiene que significar no guardar acero: es lo que hace que
# el mercado sirva, que gastar antes de la Tormenta sea la jugada correcta y que
# llegar lleno al Diezmo sea una decision y no un descuido.
#
# El techo esta cuadrado a proposito: 1000 + 5x500 = 3500 en Era 3, que es
# exactamente lo que cuesta la mejora del Cuartel General a Nv.3 (1500 oro +
# 800 acero + 500 petroleo + 700 madera). Para ganar hay que llegar con la bolsa
# llena y los cinco almacenes en pie, que es justo cuando mas tienes que perder.

## Tope base de la bolsa, por era. Sin almacenes la Frontera aprieta de verdad.
var base_storage_cap_by_era := {
	1: 300,
	2: 550,
	3: 1000,
}

var warehouse_storage_bonus := 500

## Bonificacion permanente de almacenamiento del arbol tecnologico (runtime).
var tech_storage_bonus := 0

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
	"gold_vein": 8,
	"iron_deposit": 7,
	"oil_well": 10,
	"forest": 8,
}

var deposit_count_min := 18
var deposit_count_max := 28
var deposit_center_exclusion := 6

# ── Deposit Sizes (random range per type: min_w, max_w, min_h, max_h) ──
var deposit_sizes := {
	"gold_vein": {"min_w": 2, "max_w": 3, "min_h": 2, "max_h": 3},
	"iron_deposit": {"min_w": 2, "max_w": 3, "min_h": 2, "max_h": 3},
	"oil_well": {"min_w": 2, "max_w": 3, "min_h": 2, "max_h": 3},
	"forest": {"min_w": 2, "max_w": 4, "min_h": 2, "max_h": 4},
}

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

# ── Audio ──
# Volumes are linear [0.0, 1.0]; AudioManager converts to dB per bus.
# Master scales all others. Set any to 0.0 to mute that channel.

var audio_master_volume := 0.9
var audio_music_volume := 0.6
var audio_sfx_volume := 0.8
var audio_ambient_volume := 0.5

# ── User Settings persistence ──
# Device-local preferences (volumes, UI toggles) — separate from save_game.json
# so they survive "new game" and apply before any save is loaded.

const USER_SETTINGS_PATH := "user://settings.cfg"

## Whether the map cell grid overlay is shown permanently (toggle in Settings).
var ui_grid_visible := false

## Whether the on-screen helper callouts are shown ("?" button). On by default
## so new players get guidance; the choice persists once toggled.
var ui_helper_visible := true

## Whether the game runs in exclusive fullscreen. Toggled with F11 or from the
## Settings panel; persists in user://settings.cfg like the rest of preferences.
var ui_fullscreen := false

func _ready() -> void:
	load_user_settings()
	# El modo de ventana se aplica en cuanto arranca, antes de que se dibuje la UI.
	_apply_window_mode()

func load_user_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(USER_SETTINGS_PATH) != OK:
		return
	audio_master_volume = clampf(float(cf.get_value("audio", "master", audio_master_volume)), 0.0, 1.0)
	audio_music_volume = clampf(float(cf.get_value("audio", "music", audio_music_volume)), 0.0, 1.0)
	audio_sfx_volume = clampf(float(cf.get_value("audio", "sfx", audio_sfx_volume)), 0.0, 1.0)
	audio_ambient_volume = clampf(float(cf.get_value("audio", "ambient", audio_ambient_volume)), 0.0, 1.0)
	ui_grid_visible = bool(cf.get_value("ui", "grid_visible", ui_grid_visible))
	ui_helper_visible = bool(cf.get_value("ui", "helper_visible", ui_helper_visible))
	ui_fullscreen = bool(cf.get_value("ui", "fullscreen", ui_fullscreen))

func save_user_settings() -> void:
	var cf := ConfigFile.new()
	cf.load(USER_SETTINGS_PATH)  # keep unknown sections if the file already exists
	cf.set_value("audio", "master", audio_master_volume)
	cf.set_value("audio", "music", audio_music_volume)
	cf.set_value("audio", "sfx", audio_sfx_volume)
	cf.set_value("audio", "ambient", audio_ambient_volume)
	cf.set_value("ui", "grid_visible", ui_grid_visible)
	cf.set_value("ui", "helper_visible", ui_helper_visible)
	cf.set_value("ui", "fullscreen", ui_fullscreen)
	cf.save(USER_SETTINGS_PATH)

# ── Pantalla completa ──

## Pone la ventana en el modo que marque ui_fullscreen. Sin senales: se usa
## tambien en _ready(), cuando EventBus todavia no existe.
func _apply_window_mode() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var wanted := DisplayServer.WINDOW_MODE_FULLSCREEN if ui_fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != wanted:
		DisplayServer.window_set_mode(wanted)

## Cambia a pantalla completa (o vuelve a ventana), lo guarda y lo anuncia.
func set_fullscreen(enabled: bool) -> void:
	if ui_fullscreen == enabled and not _window_mode_mismatched(enabled):
		return
	ui_fullscreen = enabled
	_apply_window_mode()
	save_user_settings()
	EventBus.fullscreen_changed.emit(ui_fullscreen)

func toggle_fullscreen() -> void:
	set_fullscreen(not ui_fullscreen)

## True si la ventana no esta en el modo que dice la preferencia (p.ej. el
## usuario salio de pantalla completa con el gestor de ventanas).
func _window_mode_mismatched(enabled: bool) -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	var wanted := DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED
	return DisplayServer.window_get_mode() != wanted

## Seconds to cross-fade between music tracks (e.g. on era change).
var audio_music_fade := 1.5

## Number of pooled voices for overlapping one-shot SFX.
var audio_sfx_voices := 8

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

# ══════════════════════════════════════════════════════════════════════
# ── Army / Units (management → combat bridge) ──
# ══════════════════════════════════════════════════════════════════════
# Units are trained at Barracks, cost resources + time, consume gold upkeep,
# and contribute to Military Power. Combat (planned) will consume this army.

## Unit definitions. `era` gates availability; `power` feeds the Military Power
## score; `upkeep_gold` is deducted per upkeep tick; `train_time` in seconds.
var unit_types := {
	"infantry": {
		"name": "UNIT_INFANTRY",
		"tier": 1,
		"era": 1,
		"cost": {"gold": 40, "wood": 20},
		"train_time": 20.0,
		"upkeep_gold": 1,
		"power": 10,
	},
	"artillery": {
		"name": "UNIT_ARTILLERY",
		"tier": 2,
		"era": 2,
		"cost": {"gold": 80, "steel": 30},
		"train_time": 35.0,
		"upkeep_gold": 2,
		"power": 28,
	},
	"vehicle": {
		"name": "UNIT_VEHICLE",
		"tier": 3,
		"era": 3,
		"cost": {"gold": 140, "steel": 60, "oil": 30},
		"train_time": 55.0,
		"upkeep_gold": 4,
		"power": 65,
	},
}

## Army capacity: you may hold a few units even with no barracks; each barracks
## raises the ceiling. Bigger base = larger, stronger army.
var army_base_capacity := 3
var army_capacity_per_barracks := 8
## Seconds between upkeep deductions (scaled by dev_mode like other durations).
var army_upkeep_interval := 30.0

func get_unit_def(unit_id: String) -> Dictionary:
	return unit_types.get(unit_id, {})

func get_unit_ids() -> Array:
	return unit_types.keys()

func get_army_capacity(barracks_count: int) -> int:
	return army_base_capacity + army_capacity_per_barracks * maxi(0, barracks_count)

func get_army_upkeep_interval() -> float:
	return get_duration(army_upkeep_interval)

# ══════════════════════════════════════════════════════════════════════
# ── Combat (PVE expeditions) ──
# ══════════════════════════════════════════════════════════════════════
# The army trained above is spent here. Kept deliberately small: an 8x8 board
# with up to 6 units per side stays readable on a phone and resolves in minutes.

## Board and party limits.
var combat_board_size := Vector2i(8, 8)
var combat_deploy_cap := 6
## Rounds before the encounter is force-resolved by total HP (FR-015).
var combat_turn_limit := 20
## Seconds between enemy AI actions, so the player can follow what happened.
var combat_ai_step_delay := 0.45

## Per-unit combat stats, parallel to `unit_types`. `min_range` keeps artillery
## from firing at adjacent targets, which is what makes positioning matter.
var combat_unit_stats := {
	"infantry":  {"hp": 30, "atk": 8,  "def": 2, "move": 3, "range": 1, "min_range": 1, "initiative": 5},
	"artillery": {"hp": 22, "atk": 14, "def": 1, "move": 1, "range": 3, "min_range": 2, "initiative": 3},
	"vehicle":   {"hp": 60, "atk": 12, "def": 5, "move": 4, "range": 1, "min_range": 1, "initiative": 4},
}

## Enemy scaling: deeper nodes and later eras field tougher rosters.
var combat_enemy_scale_per_depth := 0.15
var combat_enemy_scale_per_era := 0.25
var combat_boss_multiplier := 1.8

## Expedition map shape (min, max).
var combat_map_depth := Vector2i(4, 6)
var combat_map_branching := Vector2i(2, 3)
var combat_draft_options := 3

## Node risk (0 low / 1 medium / 2 high). The same dial pushes the roster up and
## the loot with it, so taking the dangerous road is a bet, not a punishment.
var combat_risk_enemy_scale := 0.20
var combat_risk_reward_bonus := 0.35

## Enemy roster size at depth 0, era 1, risk 0. Every pressure term grows it from
## here up to `combat_deploy_cap`.
var combat_enemy_base_slots := 2

## What one draft pick is worth. Kept modest on purpose: a run is 6-8 fights, not
## thirty, so a single pick should tilt a fight, never decide the expedition.
var combat_draft_values := {
	"atk": 2,
	"def": 2,
	"move": 1,
	"initiative": 2,
	"heal_pct": 0.3,
}
## A draft aimed at one unit type instead of the whole party hits harder, because
## it helps fewer units.
var combat_draft_focus_multiplier := 2

## Base reward per cleared encounter, scaled by node depth and risk.
var combat_reward_base := {"gold": 60, "wood": 30}

## Morale is the bridge between base and battlefield: a demoralised population
## reacts late and hits softer, and casualties cost morale back home.
var combat_morale_initiative_bonus := 2
var combat_morale_attack_range := Vector2(0.85, 1.15)
var combat_morale_on_victory := 8.0
var combat_morale_per_casualty := 3.0

func get_combat_stats(unit_id: String) -> Dictionary:
	return combat_unit_stats.get(unit_id, {})

func get_combat_ai_step_delay() -> float:
	return combat_ai_step_delay if not dev_mode else combat_ai_step_delay * 0.5

# ══════════════════════════════════════════════════════════════════════
# ── The Imperial Storm ──
# ══════════════════════════════════════════════════════════════════════
# The storm is dispatched, not rolled: it arrives on a schedule the player can
# see and plan around. A storm you cannot prepare for is just a random event.

## Seconds of calm between storms, and how long the warning lasts before it hits.
## The warning is the whole mechanic — it is what turns the storm into decisions.
var storm_interval := 300.0
var storm_warning := 45.0
var storm_duration := 60.0

## The first storm is deliberately late and gentle: it has to teach the cycle,
## not end the run.
var storm_first_interval := 420.0
var storm_first_severity := 1

## Production multiplier while the ash is overhead. Not zero — watching the
## factories crawl is worse than watching them stop.
var storm_production_multiplier := 0.35
## Live, temporary multiplier applied on top of everything else in
## ProductionManager. 1.0 means nothing is happening. Only events write to it,
## and whoever sets it is responsible for putting it back.
var event_production_multiplier := 1.0
## Morale lost per storm tick, and how often those ticks land.
var storm_morale_per_tick := 2.0
var storm_tick_interval := 5.0

## Severity climbs with the era and with how much smoke you make. The Regency does
## not spend a storm on a province that does not show up in the ledger.
var storm_severity_max := 5
var storm_severity_per_era := 1
## One extra step of severity per this many producing buildings.
var storm_buildings_per_severity := 6

## Daño por tic de tormenta, como fracción de la salud máxima del edificio. Se
## multiplica por la severidad: una tormenta fuerte deja la base en ruinas.
var storm_damage_per_tick := 0.06
## Cuántos edificios muerde cada tic. No los toca todos: la tormenta se siente
## caprichosa, y eso hace que proteger los importantes signifique algo.
var storm_buildings_hit_per_tick := 2

## Las torres, por fin, sirven: cada una en pie reduce el daño de la tormenta.
## Es la palanca de preparación principal y la razón de que existan.
var storm_tower_mitigation := 0.15
var storm_tower_mitigation_max := 0.6

## Reparar cuesta esta fracción del coste de construcción, escalada por el daño
## recibido. Reparar un rasguño es barato; levantar una ruina, casi construirla.
var storm_repair_cost_ratio := 0.5

func get_storm_damage(severity: int, max_health: int, towers: int) -> int:
	var raw: float = float(max_health) * storm_damage_per_tick * float(maxi(1, severity))
	return maxi(1, roundi(raw * (1.0 - get_storm_mitigation(towers))))

## Cuánto absorben las torres. Con techo: ninguna cantidad de torres vuelve a la
## base inmune, porque entonces la Tormenta dejaría de ser una amenaza.
func get_storm_mitigation(towers: int) -> float:
	return clampf(storm_tower_mitigation * float(maxi(0, towers)), 0.0, storm_tower_mitigation_max)

## Share of everything in store that the Assessors take when the Tithe is not
## repelled. A percentage, not a flat sum: hoarding into a storm is the mistake.
var storm_tithe_ratio := 0.25
## How many enemies the Assessors field, before severity scaling.
var storm_tithe_base_force := 3

func get_storm_interval(is_first: bool) -> float:
	return get_duration(storm_first_interval if is_first else storm_interval)

func get_storm_warning() -> float:
	return get_duration(storm_warning)

func get_storm_duration() -> float:
	return get_duration(storm_duration)

func get_storm_tick_interval() -> float:
	return get_duration(storm_tick_interval)

# ── Storage Helpers ──

## Tope base de la era. Una era fuera de tabla se acota a la mas cercana en vez de
## devolver 0: un save corrupto no puede dejar al jugador sin almacen.
func get_base_storage_cap(era: int) -> int:
	var keys: Array = base_storage_cap_by_era.keys()
	keys.sort()
	var clamped: int = clampi(era, int(keys[0]), int(keys[-1]))
	return int(base_storage_cap_by_era.get(clamped, base_storage_cap_by_era[keys[0]]))

## Tope de la bolsa compartida: escala con la era y con cada almacen en pie.
func get_storage_cap(warehouse_count: int, era: int = 1) -> int:
	return get_base_storage_cap(era) + (warehouse_count * warehouse_storage_bonus) + tech_storage_bonus

# ── Deposit Helpers ──

func is_deposit_unlocked(deposit_id: String) -> bool:
	var res_name: String = deposit_resource_required.get(deposit_id, "")
	if res_name.is_empty():
		return true
	return ResourceManager.is_unlocked_by_name(res_name)

# ══════════════════════════════════════════════════════════════════════
# ── Game Phase System (gradual unlock of mechanics) ──
# ══════════════════════════════════════════════════════════════════════
#
# Phase 0 "Fundacion"   — Build freely. No consumption, no morale changes, no market, no events.
# Phase 1 "Asentamiento" — Consumption starts (gentle). Pop growth starts.
# Phase 2 "Economia"     — Market unlocks. Morale becomes dynamic.
# Phase 3 "Supervivencia"— Random events start. Decorations affect morale.
# Phase 4+ "Expansion"   — Everything active (eras 2, 3 flow naturally).

enum Phase { FOUNDATION, SETTLEMENT, ECONOMY, SURVIVAL, EXPANSION }

## Which milestone triggers each phase transition
var phase_triggers := {
	Phase.SETTLEMENT: "first_sawmill",     # Build first Sawmill
	Phase.ECONOMY: "first_gold_mine",      # Build first Gold Mine
	Phase.SURVIVAL: "first_warehouse",     # Build first Warehouse
	Phase.EXPANSION: "era_2",              # Build Foundry (era 2)
}

## Gentle early-game timers (overrides for phases 1-2)
var early_consumption_interval := 60.0     # Phase 1-2: every 60s (vs 30s normal)
var early_morale_penalty := -3             # Phase 1-2: gentle penalty (vs -8)
var early_growth_interval := 40.0          # Phase 1-2: slow growth (vs 20s)

# ══════════════════════════════════════════════════════════════════════
# ── Cancelacion, hambruna y suelo de ruina ──
# ══════════════════════════════════════════════════════════════════════
# Tres reglas que van juntas: lo que cuesta arrepentirse, lo que cuesta no pagar
# y hasta donde se puede caer. Seccion aparte a proposito, para que el balance de
# la Tormenta y el de la economia se toquen sin pisarse.

## La Tasa de Corrupcion: que fraccion de lo pagado vuelve al cancelar un
## proceso, un minado o un entrenamiento — y lo que hoy se perdia al demoler con
## algo en curso. En calma solo se pierde la comision; con la Tormenta en marcha
## los Tasadores ya vienen de camino y la fuga de capitales se cobra el doble.
## Si cancelar fuese igual de barato siempre, cancelar seria gratis.
var cancel_refund_ratio := 0.70
var cancel_refund_ratio_storm := 0.40

## Tics de impago que se perdonan antes de que empiece a morir gente y a desertar
## tropa. Dos de gracia: al tercero duele. Margen para reaccionar, no para
## ignorarlo.
var unpaid_grace_ticks := 2
## Cuanto se pierde por tic una vez agotada la gracia.
var starvation_deaths_per_tick := 1
var desertion_units_per_tick := 1
## Moral que cuestan la hambruna y la desercion, ademas del golpe que ya pega el
## impago por si mismo.
var starvation_morale_penalty := -6
var desertion_morale_penalty := -5

## El suelo de ruina: se puede caer hasta el fondo, pero no se pierde la partida.
## Siempre queda alguien para volver a empezar.
var population_floor := 1

## Cuanto devuelve cancelar ahora mismo.
func get_cancel_refund_ratio() -> float:
	return cancel_refund_ratio_storm if _storm_cycle_running() else cancel_refund_ratio

## Reembolso exacto de un coste (nombre de recurso -> cantidad). Redondea hacia
## abajo, y es exactamente el numero que la UI ensena antes de confirmar: nadie
## deberia descubrir el porcentaje perdiendolo.
func get_cancel_refund(cost: Dictionary) -> Dictionary:
	var ratio := get_cancel_refund_ratio()
	var refund := {}
	for res_name in cost:
		var amount := int(floor(float(cost[res_name]) * ratio))
		if amount > 0:
			refund[res_name] = amount
	return refund

## Si un contador de tics impagados ya agoto la gracia y toca cobrarselo.
func unpaid_hurts(unpaid_ticks: int) -> bool:
	return unpaid_ticks > unpaid_grace_ticks

## UNICA lectura de la fase de la Tormenta en todo el sistema de cancelacion.
## Aislada a proposito: cuando el ciclo gane fases nuevas o cambien de nombre,
## adaptarlo es esta linea y ninguna mas. Cualquier fase que no sea calma cuenta
## como "Tormenta en marcha", el Diezmo incluido — que es cuando mas duele.
func _storm_cycle_running() -> bool:
	return StormManager.get_phase() != StormCycle.Phase.CALM
