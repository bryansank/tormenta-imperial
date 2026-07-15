extends Node
## Trains and maintains the player's army — the management → combat bridge.
## Units are produced at Barracks over time, cost resources, consume gold upkeep,
## and contribute to Military Power. Combat (planned) will consume this army.
##
## Training model: one unit trains per Barracks at a time (parallel slots =
## barracks count). Army size is capped by GameConfig.get_army_capacity().

var _units: Dictionary = {}   # unit_id (String) -> count (int)
var _training: Array = []     # [{id: String, remaining: float, duration: float}]
var _upkeep_accum := 0.0

var _type_map := {
	"gold": ResourceManager.Type.GOLD,
	"steel": ResourceManager.Type.STEEL,
	"oil": ResourceManager.Type.OIL,
	"wood": ResourceManager.Type.WOOD,
}

func _process(delta: float) -> void:
	_advance_training(delta)
	_advance_upkeep(delta)

# ── Queries ──

func get_count(unit_id: String) -> int:
	return _units.get(unit_id, 0)

func get_total_units() -> int:
	var total := 0
	for id in _units:
		total += _units[id]
	return total

func get_training() -> Array:
	return _training

func get_power() -> int:
	var power := 0
	for id in _units:
		var def := GameConfig.get_unit_def(id)
		power += _units[id] * int(def.get("power", 0))
	return power

## Number of Barracks currently placed (queried from the scene's BuildingPlacer).
func barracks_count() -> int:
	var scene := get_tree().current_scene
	if scene:
		var placer := scene.get_node_or_null("BuildingPlacer")
		if placer and placer.has_method("count_building"):
			return placer.count_building("barracks")
	return 0

func get_capacity() -> int:
	return GameConfig.get_army_capacity(barracks_count())

## Units owned + units currently training (both occupy capacity).
func get_used_capacity() -> int:
	return get_total_units() + _training.size()

## Parallel training slots = one per Barracks.
func max_slots() -> int:
	return barracks_count()

func is_unlocked(unit_id: String) -> bool:
	var def := GameConfig.get_unit_def(unit_id)
	if def.is_empty():
		return false
	return ProgressionManager.current_era >= int(def.get("era", 1))

## Returns {ok: bool, reason: String}. `reason` is a translation key when not ok.
func can_train(unit_id: String) -> Dictionary:
	var def := GameConfig.get_unit_def(unit_id)
	if def.is_empty():
		return {"ok": false, "reason": "LBL_ARMY_NO_UNIT"}
	if barracks_count() <= 0:
		return {"ok": false, "reason": "LBL_ARMY_NEED_BARRACKS"}
	if not is_unlocked(unit_id):
		return {"ok": false, "reason": "LBL_ARMY_LOCKED"}
	if _training.size() >= max_slots():
		return {"ok": false, "reason": "LBL_ARMY_SLOTS_FULL"}
	if get_used_capacity() >= get_capacity():
		return {"ok": false, "reason": "LBL_ARMY_AT_CAP"}
	if not ResourceManager.can_afford(_convert_cost(def.get("cost", {}))):
		return {"ok": false, "reason": "LBL_NOT_ENOUGH_RESOURCES"}
	return {"ok": true, "reason": ""}

# ── Actions ──

func train(unit_id: String) -> bool:
	var check := can_train(unit_id)
	if not check["ok"]:
		return false
	var def := GameConfig.get_unit_def(unit_id)
	ResourceManager.spend_cost(_convert_cost(def.get("cost", {})))
	var dur := GameConfig.get_duration(float(def.get("train_time", 20.0)))
	_training.append({"id": unit_id, "remaining": dur, "duration": dur})
	EventBus.unit_training_started.emit(unit_id, dur)
	EventBus.army_changed.emit()
	return true

# ── Internal ──

func _advance_training(delta: float) -> void:
	if _training.is_empty():
		return
	var completed: Array = []
	for i in range(_training.size()):
		_training[i]["remaining"] -= delta
		if _training[i]["remaining"] <= 0.0:
			completed.append(i)
	# Remove from the back so earlier indices stay valid.
	completed.reverse()
	for i in completed:
		var unit_id: String = _training[i]["id"]
		_training.remove_at(i)
		_units[unit_id] = _units.get(unit_id, 0) + 1
		EventBus.unit_trained.emit(unit_id)
	if not completed.is_empty():
		EventBus.army_changed.emit()

func _advance_upkeep(delta: float) -> void:
	if get_total_units() <= 0:
		_upkeep_accum = 0.0
		return
	var interval := GameConfig.get_army_upkeep_interval()
	if interval <= 0.0:
		return
	_upkeep_accum += delta
	while _upkeep_accum >= interval:
		_upkeep_accum -= interval
		_pay_upkeep()

func _pay_upkeep() -> void:
	var due := 0
	for id in _units:
		var def := GameConfig.get_unit_def(id)
		due += _units[id] * int(def.get("upkeep_gold", 0))
	if due <= 0:
		return
	var have := ResourceManager.get_amount(ResourceManager.Type.GOLD)
	if have >= due:
		ResourceManager.spend(ResourceManager.Type.GOLD, due)
	else:
		if have > 0:
			ResourceManager.spend(ResourceManager.Type.GOLD, have)
		EventBus.army_upkeep_unpaid.emit(due - have)

func _convert_cost(cost_dict: Dictionary) -> Dictionary:
	var result := {}
	for res_name in cost_dict:
		if _type_map.has(res_name):
			result[_type_map[res_name]] = cost_dict[res_name]
	return result

# ── Save / Load ──

func get_save_data() -> Dictionary:
	return {
		"units": _units.duplicate(),
		"training": _training.duplicate(true),
		"upkeep_accum": _upkeep_accum,
	}

func load_save_data(data: Dictionary) -> void:
	_units.clear()
	var saved_units: Dictionary = data.get("units", {})
	for id in saved_units:
		_units[id] = int(saved_units[id])
	_training.clear()
	for t in data.get("training", []):
		_training.append({
			"id": str(t.get("id", "")),
			"remaining": float(t.get("remaining", 0.0)),
			"duration": float(t.get("duration", 1.0)),
		})
	_upkeep_accum = float(data.get("upkeep_accum", 0.0))
	EventBus.army_changed.emit()

func reset() -> void:
	_units.clear()
	_training.clear()
	_upkeep_accum = 0.0
	EventBus.army_changed.emit()
