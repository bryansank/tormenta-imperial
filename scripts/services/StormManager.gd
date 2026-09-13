extends Node
## Drives the Imperial Storm: runs the clock, republishes its events on the
## EventBus, and applies what the storm does to the base.
##
## The clock itself lives in `scripts/storm/StormCycle.gd` as a pure RefCounted,
## so this node only owns what needs a scene tree: signals, timing and the
## handful of systems the storm reaches into (constitution, principles I and IV).
##
## The storm is the game's metronome. Everything else — building, trading,
## training, fighting — is measured against the next one.

const StormCycleScript := preload("res://scripts/storm/StormCycle.gd")

var _cycle: StormCycle = null
## The storm stays asleep until the base is real enough to be noticed. In the
## fiction, a province that does not show up in the ledger is not worth a storm.
var _armed: bool = false

func _ready() -> void:
	_cycle = StormCycleScript.create()
	EventBus.phase_advanced.connect(_on_phase_advanced)
	EventBus.game_load_completed.connect(_check_arming)
	EventBus.encounter_ended.connect(_on_encounter_ended)
	_check_arming()

func _process(delta: float) -> void:
	if not _armed or _cycle == null:
		return
	_publish(_cycle.advance(delta))

# ── Queries ──────────────────────────────────────────────────────────

func get_cycle() -> StormCycle:
	return _cycle

func is_armed() -> bool:
	return _armed

func get_phase() -> int:
	return _cycle.phase if _cycle != null else StormCycle.Phase.CALM

func get_severity() -> int:
	return _cycle.severity if _cycle != null else 1

func is_storming() -> bool:
	return _cycle != null and _cycle.is_storming()

## Seconds until the ash lands. This is the number the player plans around.
func seconds_until_impact() -> float:
	return _cycle.seconds_until_impact() if _cycle != null else 0.0

func storms_survived() -> int:
	return _cycle.storms_survived if _cycle != null else 0

# ── Arming ───────────────────────────────────────────────────────────

## The clock only starts once the base has grown past the Foundation phase —
## the same threshold at which consumption and events wake up. Before that the
## player is still invisible, and that is exactly the point.
func _check_arming() -> void:
	if _armed:
		return
	if ProgressionManager.current_phase >= GameConfig.Phase.SETTLEMENT:
		_armed = true

func _on_phase_advanced(_phase: int) -> void:
	_check_arming()

# ── Event translation ────────────────────────────────────────────────

func _publish(events: Array) -> void:
	for event in events:
		match event.get("e", ""):
			"phase":
				_on_phase_entered(int(event["phase"]))
				EventBus.storm_phase_changed.emit(int(event["phase"]), float(event["left"]))
			"incoming":
				EventBus.storm_incoming.emit(float(event["seconds"]), int(event["severity"]))
				# The first one reads as bad weather. The second one gives the game
				# away by being punctual — that is how the player finds out it has
				# a sender, without a single line of exposition.
				var key: String = "STORM_INCOMING_FIRST" if storms_survived() == 0 else "STORM_INCOMING"
				EventBus.notification_posted.emit(Tr.t(key), "warning", UITheme.WARNING)
			"storm_started":
				EventBus.storm_started.emit(int(event["severity"]))
				EventBus.notification_posted.emit(
					Tr.t("STORM_STARTED"), "danger", UITheme.DANGER)
			"storm_tick":
				_apply_storm_tick()
				EventBus.storm_tick.emit(float(event["left"]))
			"storm_ended":
				EventBus.storm_ended.emit(int(event["severity"]))
				EventBus.notification_posted.emit(
					Tr.t("STORM_ENDED"), "info", UITheme.TEXT_DIM)
			"tithe":
				EventBus.tithe_demanded.emit(int(event["severity"]))
				_begin_tithe(int(event["severity"]))

## Production only crawls while the ash is overhead; everything else keeps its
## own pace. The multiplier is lifted the moment the storm passes, whatever
## happens next.
func _on_phase_entered(phase: int) -> void:
	GameConfig.event_production_multiplier = \
		GameConfig.storm_production_multiplier if phase == StormCycle.Phase.STORM else 1.0

## Every bite of the storm costs morale. Building damage lands here too once the
## health system exists (see the design doc) — for now the town just suffers.
func _apply_storm_tick() -> void:
	var bite: float = GameConfig.storm_morale_per_tick * float(get_severity())
	PopulationManager.adjust_morale(-roundi(bite))

# ── The Tithe ────────────────────────────────────────────────────────

## The Assessors arrive. If there is a garrison at home, they have to get through
## it first; with nobody to stand, they simply help themselves.
func _begin_tithe(severity: int) -> void:
	if CombatManager.start_defense(assessor_roster(severity)):
		return
	EventBus.notification_posted.emit(Tr.t("STORM_TITHE_UNDEFENDED"), "danger", UITheme.DANGER)
	_pay_tithe(severity)

## The force that comes to collect. A line of Assessors with guns behind it,
## growing with severity — the more you are worth, the more they send.
func assessor_roster(severity: int) -> Dictionary:
	var force: int = clampi(
		GameConfig.storm_tithe_base_force + severity - 1, 1, GameConfig.combat_deploy_cap)
	var guns: int = force / 3
	var line: int = maxi(1, force - guns)
	var roster: Dictionary = {"infantry": line}
	if guns > 0:
		roster["artillery"] = guns
	return roster

## Settles the collection once the board is done with it.
func _on_encounter_ended(victory: bool, _turns: int) -> void:
	if _cycle == null or not _cycle.is_collecting():
		return
	if not CombatManager.is_defending():
		return
	if victory:
		repel_tithe()
	else:
		EventBus.notification_posted.emit(Tr.t("STORM_TITHE_PAID"), "danger", UITheme.DANGER)
		_pay_tithe(get_severity())

func _pay_tithe(severity: int) -> void:
	var taken: Dictionary = _collect_tithe(severity)
	EventBus.tithe_resolved.emit(false, taken)
	_settle()

## Takes a share of everything in store. A percentage and not a flat sum on
## purpose: walking into a storm with full warehouses is the mistake the player
## has to learn, and spending beforehand is the correct answer.
func _collect_tithe(severity: int) -> Dictionary:
	var ratio: float = clampf(
		GameConfig.storm_tithe_ratio * (float(severity) / float(maxi(1, GameConfig.storm_severity_max)) + 0.5),
		0.0, 0.9)
	var taken: Dictionary = {}
	for type in [ResourceManager.Type.GOLD, ResourceManager.Type.STEEL,
			ResourceManager.Type.OIL, ResourceManager.Type.WOOD]:
		var held: int = ResourceManager.get_amount(type)
		var bite: int = int(float(held) * ratio)
		if bite > 0:
			ResourceManager.spend(type, bite)
			taken[_resource_name(type)] = bite
	return taken

## Repelling them costs nothing but the fight. Called when the board is won.
func repel_tithe() -> void:
	if _cycle == null or not _cycle.is_collecting():
		return
	EventBus.tithe_resolved.emit(true, {})
	EventBus.notification_posted.emit(Tr.t("STORM_TITHE_REPELLED"), "success", UITheme.POSITIVE)
	_settle()

func _settle() -> void:
	if _cycle == null:
		return
	_publish(_cycle.settle_tithe(_industrial_footprint(), ProgressionManager.current_era))

## How much smoke the base makes. This is what the Regency actually measures, and
## what decides how hard the next storm hits.
func _industrial_footprint() -> int:
	var count := 0
	for info in GridManager.get_all_buildings():
		var data: BuildingData = info["data"]
		if data.produces_gold > 0 or data.produces_steel > 0 \
				or data.produces_oil > 0 or data.produces_wood > 0:
			count += 1
	return count

func _resource_name(type: int) -> String:
	match type:
		ResourceManager.Type.STEEL:
			return "steel"
		ResourceManager.Type.OIL:
			return "oil"
		ResourceManager.Type.WOOD:
			return "wood"
		_:
			return "gold"

# ── Persistence ──────────────────────────────────────────────────────

func get_save_data() -> Dictionary:
	if _cycle == null:
		return {}
	var data: Dictionary = _cycle.to_dict()
	data["armed"] = _armed
	return data

func load_save_data(data: Dictionary) -> void:
	_cycle = StormCycleScript.from_dict(data)
	_armed = bool(data.get("armed", false))
	GameConfig.event_production_multiplier = 1.0

func reset() -> void:
	_cycle = StormCycleScript.create()
	_armed = false
	GameConfig.event_production_multiplier = 1.0
