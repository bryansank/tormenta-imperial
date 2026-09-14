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
## Tics de mantenimiento seguidos sin poder pagar. Se reinicia en cuanto se paga
## uno entero. Viaja en el guardado: la deuda no se perdona al cerrar el juego.
var _unpaid_ticks := 0

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

## Tics seguidos de mantenimiento impagado. Cero significa al corriente.
func get_unpaid_ticks() -> int:
	return _unpaid_ticks

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

## Lo que devolveria cancelar ese entrenamiento ahora mismo, sin cancelarlo.
## La UI lo ensena junto al boton: nadie deberia descubrir la tasa perdiendola.
func get_training_refund(index: int) -> Dictionary:
	if index < 0 or index >= _training.size():
		return {}
	var def := GameConfig.get_unit_def(str(_training[index].get("id", "")))
	# Recortado al hueco que queda: con la bolsa compartida, prometer un 70% que
	# no cabe es mentirle al jugador en el propio boton.
	return ResourceManager.fit_into_storage(GameConfig.get_cancel_refund(def.get("cost", {})))

## Cancela una unidad en entrenamiento y devuelve parte de lo pagado.
## Hasta ahora entrenar era irreversible: pulsar ENTRENAR por error costaba la
## unidad entera y no habia forma de deshacerlo. Devuelve el reembolso abonado.
func cancel_training(index: int) -> Dictionary:
	if index < 0 or index >= _training.size():
		return {}
	var unit_id := str(_training[index].get("id", ""))
	var refund := get_training_refund(index)
	_training.remove_at(index)
	for res_name in refund:
		if _type_map.has(res_name):
			ResourceManager.add(_type_map[res_name], refund[res_name])
	EventBus.unit_training_cancelled.emit(unit_id, refund)
	EventBus.army_changed.emit()
	return refund

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
		# Sin tropa no hay deuda que arrastrar.
		_unpaid_ticks = 0
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
		_unpaid_ticks = 0
		return
	var have := ResourceManager.get_amount(ResourceManager.Type.GOLD)
	if have >= due:
		ResourceManager.spend(ResourceManager.Type.GOLD, due)
		# Una nomina pagada entera borra la deuda: el contador no se arrastra.
		_unpaid_ticks = 0
		return
	if have > 0:
		ResourceManager.spend(ResourceManager.Type.GOLD, have)
	_unpaid_ticks += 1
	EventBus.army_upkeep_unpaid.emit(due - have)
	# Dos tics de gracia. Al tercero la tropa deja de creerse las promesas.
	if GameConfig.unpaid_hurts(_unpaid_ticks):
		_desert()

## Un ejercito sin paga se deshace por arriba: se va primero la unidad mas cara
## de mantener, que es justo la que el jugador no queria perder. Es la
## consecuencia la que ensena a no sobrepasarse, no el aviso.
func _desert() -> void:
	var unit_id := _costliest_unit()
	if unit_id.is_empty():
		return
	var removed := remove_units({unit_id: GameConfig.desertion_units_per_tick})
	var gone: int = int(removed.get(unit_id, 0))
	if gone <= 0:
		return
	var def := GameConfig.get_unit_def(unit_id)
	EventBus.army_deserted.emit(unit_id, gone)
	EventBus.notification_posted.emit(
		Tr.t("NOTIF_DESERTION") % [gone, Tr.t(def.get("name", unit_id))],
		"danger", UITheme.DANGER)

## La mas cara de mantener entre las que quedan. En empate gana la mas antigua
## del diccionario, que basta para que el resultado sea siempre el mismo.
func _costliest_unit() -> String:
	var worst := ""
	var worst_upkeep := -1
	for id in _units:
		if _units[id] <= 0:
			continue
		var upkeep := int(GameConfig.get_unit_def(id).get("upkeep_gold", 0))
		if upkeep > worst_upkeep:
			worst_upkeep = upkeep
			worst = id
	return worst

func _convert_cost(cost_dict: Dictionary) -> Dictionary:
	var result := {}
	for res_name in cost_dict:
		if _type_map.has(res_name):
			result[_type_map[res_name]] = cost_dict[res_name]
	return result

# ── Casualties ──

## Removes units for good. This is the only way the army ever shrinks: training
## adds, combat subtracts, and nothing else touches the roster.
##
## You cannot lose more than you had — a caller asking for 3 infantry when 2 are
## left removes 2. The returned dictionary says what actually died, which is what
## callers should report to the player, not what they asked for.
func remove_units(losses: Dictionary) -> Dictionary:
	var removed: Dictionary = {}
	for unit_id in losses.keys():
		var wanted: int = int(losses[unit_id])
		var owned: int = int(_units.get(unit_id, 0))
		var gone: int = mini(maxi(0, wanted), owned)
		if gone <= 0:
			continue
		_units[unit_id] = owned - gone
		if _units[unit_id] <= 0:
			_units.erase(unit_id)
		removed[unit_id] = gone
	if not removed.is_empty():
		EventBus.army_changed.emit()
	return removed

# ── Save / Load ──

func get_save_data() -> Dictionary:
	return {
		"units": _units.duplicate(),
		"training": _training.duplicate(true),
		"upkeep_accum": _upkeep_accum,
		"unpaid_ticks": _unpaid_ticks,
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
	# Un guardado anterior a la desercion no trae contador: empieza a cero.
	_unpaid_ticks = int(data.get("unpaid_ticks", 0))
	EventBus.army_changed.emit()

func reset() -> void:
	_units.clear()
	_training.clear()
	_upkeep_accum = 0.0
	_unpaid_ticks = 0
	EventBus.army_changed.emit()
