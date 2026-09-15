extends Node
## Tracks era progression, milestones, and victory conditions.
## Listens to EventBus signals and advances the game state accordingly.
##
## Victory no longer belongs to a building. Headquarters level 3 summons the
## Regency's final audit; surviving the siege is what wins the game. This service
## owns the siege model and is the only thing that publishes it on the EventBus —
## FinalAudit itself never emits (constitution, principles I and IV).

const FinalAuditScript := preload("res://scripts/combat/FinalAudit.gd")

var current_era := 1
var current_phase: int = GameConfig.Phase.FOUNDATION
var milestones_completed: Dictionary = {}
## The siege, once it has been summoned. Null before that and in any save that
## predates it.
var final_audit: FinalAudit = null
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
	_check_phase_advance(milestone_id)
	# The capstone no longer wins: it calls the Regency down on you.
	if milestone_id == "hq_max":
		summon_final_audit()

func _check_phase_advance(milestone_id: String) -> void:
	for phase in GameConfig.phase_triggers:
		if GameConfig.phase_triggers[phase] == milestone_id and current_phase < phase:
			current_phase = phase
			EventBus.phase_advanced.emit(current_phase)

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

# ── The Final Audit ──
## The climax. A headquarters at level 3 used to end the game with an animation;
## it now summons the Regency's last audit — 3 to 5 defensive waves in a row,
## fought by whatever garrison is at home, with no retraining in between.
##
## Everything here is thin on purpose: the rules live in FinalAudit, this service
## only drives it and republishes what it returns.

## Calls the audit down. Whatever is at home right now is what will stand for the
## whole siege — sending the army out just before the capstone lands is a real
## and deliberate way to lose.
func summon_final_audit() -> bool:
	# A siege that already stands is never summoned twice, and a lost one is
	# answered by resummoning it — which has a price of its own, and is not the
	# same thing as calling the Regency down for the first time.
	if final_audit != null:
		return resummon_final_audit()
	final_audit = FinalAuditScript.create(
		_audit_seed(), CombatManager.get_garrison(), current_era, _read_morale()
	)
	_publish_audit([{
		"e": "final_audit_summoned",
		"waves": final_audit.wave_count(),
		"summons": final_audit.summons,
	}])
	return true

## Opens the siege and announces the first formation.
func begin_final_audit() -> bool:
	if final_audit == null or not final_audit.is_pending():
		return false
	_publish_audit(final_audit.begin())
	_announce_wave()
	return true

## What the board reports back after one wave. A win rolls the siege forward and
## announces the next formation; a loss ends the siege without ending the game.
func report_audit_wave(victory: bool) -> void:
	if final_audit == null or not final_audit.is_active():
		return
	_publish_audit(final_audit.clear_wave() if victory else final_audit.lose())
	_announce_wave()

func can_resummon_final_audit() -> bool:
	return final_audit != null and final_audit.can_resummon(CombatManager.get_garrison())

## Losing is not a Game Over: once the army is rebuilt the Regency can be called
## back down, on a new seed and a new siege.
func resummon_final_audit() -> bool:
	if not can_resummon_final_audit():
		return false
	_publish_audit(final_audit.resummon(
		_audit_seed(), CombatManager.get_garrison(), current_era, _read_morale()
	))
	return true

func is_final_audit_active() -> bool:
	return final_audit != null and final_audit.is_active()

## Convocada y esperando a que el jugador entre. Es el estado que enseña el boton
## de "QUE BAJEN": la UI pregunta aqui y no a la var publica, para que el modelo
## pueda cambiar de forma sin arrastrar a ninguna pantalla.
func is_final_audit_pending() -> bool:
	return final_audit != null and final_audit.is_pending()

## Perdida y a la espera de reconvocatoria. La UI lo usa para ofrecer volver a
## intentarlo; si ademas se puede, lo dice `can_resummon_final_audit()`.
func is_final_audit_lost() -> bool:
	return final_audit != null and final_audit.is_lost()

## Announces the wave that should be on the board now. **This is the seam:**
## nothing here calls CombatManager.start_defense(). The model says which wave it
## is and who comes down; whoever drives the board listens and puts it there.
func _announce_wave() -> void:
	if final_audit == null or not final_audit.is_active():
		return
	var wave: Dictionary = final_audit.current_wave_data()
	if wave.is_empty():
		return
	EventBus.final_audit_wave_ready.emit(
		int(wave["index"]), wave["roster"].duplicate(), float(wave["scale"])
	)

## Translates the siege's plain event list onto the EventBus. Same contract
## CombatManager uses for encounters: the model never emits, this does.
func _publish_audit(events: Array) -> void:
	for event in events:
		match event.get("e", ""):
			"final_audit_summoned":
				EventBus.final_audit_summoned.emit(int(event["waves"]), int(event["summons"]))
			"final_audit_started":
				EventBus.final_audit_started.emit(int(event["waves"]))
			"final_audit_wave_cleared":
				EventBus.final_audit_wave_cleared.emit(int(event["wave"]), int(event["remaining"]))
			"final_audit_lost":
				EventBus.final_audit_lost.emit(int(event["wave"]))
			"final_audit_won":
				# The Storm stops for good, and only then is the game won. The
				# order matters: the world goes quiet before the screen says so.
				EventBus.storm_halted_forever.emit()
				_trigger_victory()

## One siege, one number. Not seeded from the save on purpose: a lost audit that
## is summoned again has to be a different night, or reloading would be a way to
## shop for an easier one.
func _audit_seed() -> int:
	return randi()

func _read_morale() -> float:
	if PopulationManager.has_method("get_morale"):
		return float(PopulationManager.get_morale())
	return 50.0

# ── Victory ──

## Reached only through the final audit now. Nothing else emits it.
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
		"current_phase": current_phase,
		"milestones": milestones_completed.duplicate(),
		"trade_count": _trade_count,
		"stats": _stats.duplicate(),
		"start_time": _start_time,
		"final_audit": final_audit.to_dict() if final_audit != null else {},
	}

func load_save_data(data: Dictionary) -> void:
	current_era = data.get("current_era", 1)
	current_phase = data.get("current_phase", GameConfig.Phase.FOUNDATION)
	milestones_completed = data.get("milestones", {})
	_trade_count = data.get("trade_count", 0)
	_stats = data.get("stats", {"buildings_built": 0, "resources_gathered": 0, "trades_completed": 0})
	_start_time = data.get("start_time", Time.get_unix_time_from_system())
	# A save older than the audit has no key, which simply means "never summoned"
	# and is not something to migrate (constitution, principle V).
	final_audit = FinalAuditScript.from_dict(data.get("final_audit", {}), current_era)
	# Restore resource unlocks based on era
	if current_era >= 2:
		ResourceManager.unlock(ResourceManager.Type.STEEL)
	if current_era >= 3:
		ResourceManager.unlock(ResourceManager.Type.OIL)
	# Recalculate phase from milestones if not saved (backwards compat)
	if not data.has("current_phase"):
		_recalculate_phase()

func _recalculate_phase() -> void:
	current_phase = GameConfig.Phase.FOUNDATION
	for phase in GameConfig.phase_triggers:
		var milestone_id: String = GameConfig.phase_triggers[phase]
		if milestones_completed.has(milestone_id):
			current_phase = maxi(current_phase, phase)

func reset() -> void:
	current_era = 1
	current_phase = GameConfig.Phase.FOUNDATION
	milestones_completed = {}
	final_audit = null
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
