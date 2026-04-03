extends Node
## Tracks era progression, milestones, and victory conditions.
## Listens to EventBus signals and advances the game state accordingly.

var current_era := 1
var milestones_completed: Dictionary = {}
var _trade_count := 0
var _stats := {"buildings_built": 0, "resources_gathered": 0, "trades_completed": 0}
var _start_time := 0.0

func _ready() -> void:
	_start_time = Time.get_unix_time_from_system()
	EventBus.construction_completed.connect(_on_construction_completed)
	EventBus.building_upgrade_completed.connect(_on_upgrade_completed)
	EventBus.market_trade_completed.connect(_on_trade_completed)
	EventBus.building_placed.connect(_on_building_placed)
	EventBus.resource_changed.connect(_on_resource_changed)

# ── Era System ──

func _check_era_advance(building_id: String) -> void:
	if current_era == 1 and building_id == "foundry":
		current_era = 2
		ResourceManager.unlock(ResourceManager.Type.STEEL)
		_complete_milestone("era_2")
		EventBus.era_advanced.emit(2)
	elif current_era == 2 and building_id == "refinery":
		current_era = 3
		ResourceManager.unlock(ResourceManager.Type.OIL)
		_complete_milestone("era_3")
		EventBus.era_advanced.emit(3)

# ── Milestones ──

func _complete_milestone(milestone_id: String) -> void:
	if milestones_completed.has(milestone_id):
		return
	milestones_completed[milestone_id] = true
	EventBus.milestone_completed.emit(milestone_id)
	if milestone_id == "hq_max":
		_trigger_victory()

func _check_building_milestones(building_id: String) -> void:
	match building_id:
		"sawmill":
			_complete_milestone("first_sawmill")
		"gold_mine":
			_complete_milestone("first_gold_mine")
		"warehouse":
			_complete_milestone("first_warehouse")
		"headquarters":
			_complete_milestone("hq_built")

func _check_military_milestone() -> void:
	var barracks_count := 0
	var tower_count := 0
	for info in GridManager.get_all_buildings():
		var data: BuildingData = info["data"]
		if data.id == "barracks":
			barracks_count += 1
		elif data.id == "tower":
			tower_count += 1
	if barracks_count >= 1 and tower_count >= 2:
		_complete_milestone("military_ready")

# ── Victory ──

func _trigger_victory() -> void:
	var elapsed := Time.get_unix_time_from_system() - _start_time
	var stats := {
		"time_played": elapsed,
		"buildings_built": _stats["buildings_built"],
		"trades_completed": _stats["trades_completed"],
		"milestones": milestones_completed.size(),
	}
	EventBus.victory_achieved.emit(stats)

# ── Signal Handlers ──

func _on_construction_completed(node: Node3D) -> void:
	var info := GridManager.get_building_info(node)
	if info.is_empty():
		return
	var data: BuildingData = info["data"]
	_check_era_advance(data.id)
	_check_building_milestones(data.id)
	_check_military_milestone()

func _on_building_placed(_data: Resource, _cell: Vector2i) -> void:
	_stats["buildings_built"] += 1

func _on_upgrade_completed(node: Node3D, new_level: int) -> void:
	var info := GridManager.get_building_info(node)
	if info.is_empty():
		return
	var data: BuildingData = info["data"]
	if data.id == "headquarters" and new_level >= GameConfig.max_building_level:
		_complete_milestone("hq_max")

func _on_trade_completed(_resource: String, _amount: int, _is_buy: bool, _price: int) -> void:
	_trade_count += 1
	_stats["trades_completed"] = _trade_count
	if _trade_count >= 10:
		_complete_milestone("market_10_trades")

func _on_resource_changed(_type: String, _amount: int, delta: int) -> void:
	if delta > 0:
		_stats["resources_gathered"] += delta

# ── Save/Load ──

func get_save_data() -> Dictionary:
	return {
		"current_era": current_era,
		"milestones": milestones_completed.duplicate(),
		"trade_count": _trade_count,
		"stats": _stats.duplicate(),
		"start_time": _start_time,
	}

func load_save_data(data: Dictionary) -> void:
	current_era = data.get("current_era", 1)
	milestones_completed = data.get("milestones", {})
	_trade_count = data.get("trade_count", 0)
	_stats = data.get("stats", {"buildings_built": 0, "resources_gathered": 0, "trades_completed": 0})
	_start_time = data.get("start_time", Time.get_unix_time_from_system())
	# Restore resource unlocks based on era
	if current_era >= 2:
		ResourceManager.unlock(ResourceManager.Type.STEEL)
	if current_era >= 3:
		ResourceManager.unlock(ResourceManager.Type.OIL)

func reset() -> void:
	current_era = 1
	milestones_completed = {}
	_trade_count = 0
	_stats = {"buildings_built": 0, "resources_gathered": 0, "trades_completed": 0}
	_start_time = Time.get_unix_time_from_system()

# ── Helpers ──

func get_milestone_list() -> Array:
	return GameConfig.milestone_definitions

func is_milestone_completed(milestone_id: String) -> bool:
	return milestones_completed.has(milestone_id)

func get_era_name() -> String:
	return GameConfig.era_names.get(current_era, "")

func get_completion_percent() -> float:
	var total: int = GameConfig.milestone_definitions.size()
	if total == 0:
		return 0.0
	return float(milestones_completed.size()) / float(total)
