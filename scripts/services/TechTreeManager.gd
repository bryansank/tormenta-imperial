extends Node
## Tech tree with 3 branches: Industrial, Military, Logistics.
## Each tech costs resources and time to research. Techs provide permanent bonuses.
## Requires HQ to exist. Higher tiers require previous tech in branch.

# ── State ──
var _researched: Dictionary = {}  # tech_id -> true
var _researching: Dictionary = {}  # {"tech_id": String, "remaining": float, "duration": float} or empty
var _research_points := 0  # accumulated from HQ production
var _base_market_spread: float
var _base_morale_recovery: int
var _base_storage_cap: int

func _ready() -> void:
	_base_market_spread = GameConfig.market_spread
	_base_morale_recovery = GameConfig.morale_satisfied_recovery
	_base_storage_cap = GameConfig.base_storage_cap
	EventBus.production_tick.connect(_on_production_tick)

func _process(delta: float) -> void:
	if _researching.is_empty():
		return
	_researching["remaining"] -= delta
	if _researching["remaining"] <= 0.0:
		_complete_research()

# ── Tech Definitions ──

func get_all_techs() -> Array:
	return GameConfig.tech_definitions

func get_tech(tech_id: String) -> Dictionary:
	for tech in GameConfig.tech_definitions:
		if tech["id"] == tech_id:
			return tech
	return {}

func get_branch_techs(branch: String) -> Array:
	var result: Array = []
	for tech in GameConfig.tech_definitions:
		if tech["branch"] == branch:
			result.append(tech)
	return result

# ── Research ──

func can_research(tech_id: String) -> bool:
	if is_researched(tech_id):
		return false
	if is_researching():
		return false
	var tech := get_tech(tech_id)
	if tech.is_empty():
		return false
	# Check prerequisites
	for req in tech.get("requires", []):
		if not is_researched(req):
			return false
	# Check cost
	var cost := _get_tech_cost(tech)
	return ResourceManager.can_afford(cost)

func start_research(tech_id: String) -> bool:
	if not can_research(tech_id):
		return false
	var tech := get_tech(tech_id)
	var cost := _get_tech_cost(tech)
	ResourceManager.spend_cost(cost)
	var duration := GameConfig.get_duration(tech.get("duration", 30.0))
	_researching = {
		"tech_id": tech_id,
		"remaining": duration,
		"duration": duration,
	}
	EventBus.notification_posted.emit(
		Tr.t("NOTIF_RESEARCH_STARTED") % Tr.t(tech["name"]),
		"info", Color(0.5, 0.7, 1.0)
	)
	return true

func _complete_research() -> void:
	var tech_id: String = _researching["tech_id"]
	_researching = {}
	_researched[tech_id] = true
	var tech := get_tech(tech_id)
	# Apply bonus
	_apply_tech_bonus(tech)
	EventBus.notification_posted.emit(
		Tr.t("NOTIF_RESEARCH_DONE") % Tr.t(tech["name"]),
		"positive", Color(0.3, 0.9, 0.5)
	)
	EventBus.milestone_completed.emit("tech_" + tech_id)
	GameManager.save_game()

func _apply_tech_bonus(tech: Dictionary) -> void:
	var bonus: Dictionary = tech.get("bonus", {})
	for key in bonus:
		match key:
			"production_mult":
				GameConfig.tech_production_bonus += bonus[key]
			"storage_bonus":
				GameConfig.base_storage_cap += bonus[key]
			"market_spread_reduction":
				GameConfig.market_spread = maxf(0.1, GameConfig.market_spread - bonus[key])
			"morale_bonus":
				GameConfig.morale_satisfied_recovery += bonus[key]
			"consumption_reduction":
				GameConfig.tech_consumption_reduction += bonus[key]
			"build_speed":
				GameConfig.tech_build_speed_bonus += bonus[key]

# ── Queries ──

func is_researched(tech_id: String) -> bool:
	return _researched.has(tech_id)

func is_researching() -> bool:
	return not _researching.is_empty()

func get_research_progress() -> float:
	if _researching.is_empty():
		return 0.0
	return clampf(1.0 - (_researching["remaining"] / _researching["duration"]), 0.0, 1.0)

func get_current_research() -> Dictionary:
	return _researching

func get_researched_count() -> int:
	return _researched.size()

# ── HQ Research Points ──

func _on_production_tick(node: Node3D) -> void:
	var info := GridManager.get_building_info(node)
	if info.is_empty():
		return
	var data: BuildingData = info["data"]
	if data.id == "headquarters":
		_research_points += 1

# ── Cost Helper ──

func _get_tech_cost(tech: Dictionary) -> Dictionary:
	var cost := {}
	var raw_cost: Dictionary = tech.get("cost", {})
	for res_name in raw_cost:
		var type := ResourceManager.name_to_type(res_name)
		if type != -1:
			cost[type] = raw_cost[res_name]
	return cost

# ── Save/Load ──

func get_save_data() -> Dictionary:
	return {
		"researched": _researched.duplicate(),
		"researching": _researching.duplicate(),
		"research_points": _research_points,
	}

func load_save_data(data: Dictionary) -> void:
	_researched = data.get("researched", {})
	_researching = data.get("researching", {})
	_research_points = data.get("research_points", 0)
	# Re-apply all researched bonuses
	for tech_id in _researched:
		var tech := get_tech(tech_id)
		if not tech.is_empty():
			_apply_tech_bonus(tech)

func reset() -> void:
	_researched = {}
	_researching = {}
	_research_points = 0
	# Reset tech bonuses applied to GameConfig
	GameConfig.tech_production_bonus = 0.0
	GameConfig.tech_consumption_reduction = 0.0
	GameConfig.tech_build_speed_bonus = 0.0
	GameConfig.market_spread = _base_market_spread
	GameConfig.morale_satisfied_recovery = _base_morale_recovery
	GameConfig.base_storage_cap = _base_storage_cap
