extends Node
## Tech tree with 3 branches: Industrial, Military, Logistics.
## Each tech costs resources and time to research. Techs provide permanent bonuses.
## Higher tiers require the previous tech in the branch. There is NO HQ requirement:
## the HQ is an era-3 building and gating the tree behind it would leave it unusable
## for most of the game. Research is paid in resources, not points.

# ── State ──
var _researched: Dictionary = {}  # tech_id -> true
var _researching: Dictionary = {}  # {"tech_id": String, "remaining": float, "duration": float} or empty
var _base_market_spread: float
var _base_morale_recovery: int

func _ready() -> void:
	_base_market_spread = GameConfig.market_spread
	_base_morale_recovery = GameConfig.morale_satisfied_recovery

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

## Por que `can_research()` dice que no, como clave de Tr ("" si se puede).
## Mismo orden de comprobaciones que `can_research()`, para que el motivo que ve
## el jugador sea siempre el primero que le para de verdad.
##   TECH_BLOCK_DONE        ya investigada
##   TECH_BLOCK_RESEARCHING hay otra investigacion en curso
##   TECH_BLOCK_PREREQ      falta el nivel anterior (ver get_missing_prerequisites)
##   TECH_BLOCK_COST        faltan recursos (ver get_missing_cost)
func get_research_blocker(tech_id: String) -> String:
	if is_researched(tech_id):
		return "TECH_BLOCK_DONE"
	if is_researching():
		return "TECH_BLOCK_RESEARCHING"
	var tech := get_tech(tech_id)
	if tech.is_empty():
		return "TECH_BLOCK_PREREQ"
	if not get_missing_prerequisites(tech_id).is_empty():
		return "TECH_BLOCK_PREREQ"
	if not ResourceManager.can_afford(_get_tech_cost(tech)):
		return "TECH_BLOCK_COST"
	return ""

## Las tecnologias que faltan por investigar antes de esta.
func get_missing_prerequisites(tech_id: String) -> Array:
	var missing: Array = []
	for req in get_tech(tech_id).get("requires", []):
		if not is_researched(req):
			missing.append(req)
	return missing

## Lo que falta de cada recurso para pagarla: {"steel": 40}. Vacio si alcanza.
func get_missing_cost(tech_id: String) -> Dictionary:
	var missing: Dictionary = {}
	var raw_cost: Dictionary = get_tech(tech_id).get("cost", {})
	for res_name in raw_cost:
		var type := ResourceManager.name_to_type(res_name)
		if type == -1:
			continue
		var short: int = int(raw_cost[res_name]) - ResourceManager.get_amount(type)
		if short > 0:
			missing[res_name] = short
	return missing

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
				# Suma al tope de la bolsa compartida, no al tope de un recurso.
				GameConfig.tech_storage_bonus += bonus[key]
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
	}

func load_save_data(data: Dictionary) -> void:
	_researched = data.get("researched", {})
	_researching = data.get("researching", {})
	# Los guardados viejos traen "research_points" (puntos que nunca se gastaron):
	# se ignoran.
	# Re-apply all researched bonuses
	for tech_id in _researched:
		var tech := get_tech(tech_id)
		if not tech.is_empty():
			_apply_tech_bonus(tech)

func reset() -> void:
	_researched = {}
	_researching = {}
	# Reset tech bonuses applied to GameConfig
	GameConfig.tech_production_bonus = 0.0
	GameConfig.tech_consumption_reduction = 0.0
	GameConfig.tech_build_speed_bonus = 0.0
	GameConfig.tech_storage_bonus = 0
	GameConfig.market_spread = _base_market_spread
	GameConfig.morale_satisfied_recovery = _base_morale_recovery

# ── modos-de-juego ──

## Sandbox: todo investigado desde el principio, con sus bonos. Solo al empezar
## partida (GameManager._new_game): una carga ya trae la lista en el guardado.
## Sin avisos: una partida nueva no anuncia nada.
func unlock_all() -> void:
	_researching = {}
	for tech in get_all_techs():
		var tech_id: String = String(tech.get("id", ""))
		if tech_id == "" or _researched.has(tech_id):
			continue
		_researched[tech_id] = true
		_apply_tech_bonus(tech)
