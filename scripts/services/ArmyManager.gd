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

## Cae ceniza y la Tormenta todavia no ha roto: la ultima ventana para sacar del
## cuartel lo que haya dentro. Se lleva por señal y no preguntandole la fase a
## StormManager, para que este servicio no dependa de aquel.
var _ash_overhead: bool = false

var _type_map := {
	"gold": ResourceManager.Type.GOLD,
	"steel": ResourceManager.Type.STEEL,
	"oil": ResourceManager.Type.OIL,
	"wood": ResourceManager.Type.WOOD,
}

func _ready() -> void:
	EventBus.storm_ash_started.connect(_on_ash_started)
	EventBus.storm_started.connect(_on_storm_started)
	EventBus.storm_ended.connect(_on_storm_ended)
	# Al cargar partida, el estado de ceniza se reconstruye preguntando la fase.
	# Es transitorio y no viaja en el guardado: sin esto, quien guarda con la
	# ceniza encima recarga creyendo que no pasa nada y pierde la cola sin haber
	# visto un solo aviso en esa sesion.
	EventBus.game_load_completed.connect(_resync_storm_phase)

func _resync_storm_phase() -> void:
	_ash_overhead = StormManager.is_ashfall()

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
	# El cuartel no se cierra durante la ceniza, pero tampoco se deja que el
	# jugador meta ahi el almacen sin saber lo que arriesga.
	_warn_if_ash()
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

# ── La Tormenta arruina el cuartel ──
#
# Igual que la cola de procesos: el cuartel no se cierra en ninguna fase —
# vaciar el almacen en reclutas es una decision legitima— pero lo que siga a
# medio entrenar cuando rompa la TORMENTA se pierde con su coste. Sin esto, el
# cuartel sigue siendo el mismo escondite que los procesos: el coste se paga al
# pulsar ENTRENAR, y los Tasadores auditan lo que queda en la bolsa, no lo que
# hay dentro de un uniforme a medio coser.

## Lo que el cuartel se lleva por delante si rompe ahora: la suma de lo pagado
## por cada recluta. Es el COSTE, no el reembolso de cancelar — la Tormenta no
## devuelve nada, asi que esto no se recorta al hueco libre de la bolsa. Anunciar
## el reembolso con el almacen lleno diria "vas a perder 0" y seria falso.
func get_training_at_risk() -> Dictionary:
	var at_risk := {}
	for entry in _training:
		var cost: Dictionary = GameConfig.get_unit_def(str(entry.get("id", ""))).get("cost", {})
		for res_name in cost:
			at_risk[res_name] = int(at_risk.get(res_name, 0)) + int(cost[res_name])
	return at_risk

## Empieza la ceniza: la ultima ventana para sacar del cuartel lo que haya dentro.
func _on_ash_started() -> void:
	_ash_overhead = true
	_warn_if_ash()

## El aviso. Al entrar en la ceniza y otra vez con cada recluta nuevo mientras
## cae, porque quien entrena durante la ceniza es justo quien va a perderlo. Una
## regla dura que nadie te conto es una regla injusta.
func _warn_if_ash() -> void:
	if not _ash_overhead or _training.is_empty():
		return
	EventBus.notification_posted.emit(
		Tr.t("STORM_ASH_TRAINING_WARNING") % [_training.size(), Tr.amount_list(get_training_at_risk())],
		"warning", UITheme.WARNING)

## Rompe la Tormenta. Ningun recluta a medio hacer llega al otro lado, y se dice
## uno por uno: un resumen deja al jugador sin saber que perdio, y saberlo es lo
## que le ensena a vaciar el cuartel antes de la proxima.
func _on_storm_started(_severity: int) -> void:
	_ash_overhead = false
	if _training.is_empty():
		return
	var lost: Array = _training.duplicate()
	# Se vacia de golpe y se avisa despues: si se notificara mientras se recorre,
	# quien escuche la notificacion veria una cola a medio deshacer.
	_training.clear()
	for entry in lost:
		var unit_id := str(entry.get("id", ""))
		var def := GameConfig.get_unit_def(unit_id)
		EventBus.notification_posted.emit(
			Tr.t("NOTIF_STORM_ATE_TRAINING") % [
				Tr.t(str(def.get("name", unit_id))),
				Tr.amount_list(def.get("cost", {}))],
			"danger", UITheme.DANGER)
		# Mismo canal que cancelar, con el reembolso real: ninguno. Asi la UI que
		# sigue la cola se entera sin tener que conocer la Tormenta.
		EventBus.unit_training_cancelled.emit(unit_id, {})
	EventBus.army_changed.emit()

## Pasa la tormenta. Lo que entre al cuartel a partir de aqui ya no corre peligro
## hasta la siguiente ceniza.
func _on_storm_ended(_severity: int) -> void:
	_ash_overhead = false

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
##
## Solo puede desertar quien esta en casa. Una unidad de expedicion no se larga
## del cuartel porque no esta en el cuartel: si lo hiciera, el total seguiria
## cuadrando —la columna se liquida entera al volver— pero la identidad no. Un
## caido en campana desertaria en casa y, al liquidar la expedicion, quien se
## borraria del recuento seria un superviviente. Es la misma regla que bloquea a
## la columna para cualquier otra cosa, aplicada al impago.
##
## Con toda la tropa fuera no deserta nadie: el aviso de impago ya se emitio
## antes de llegar aqui, que es lo unico que el jugador necesita ver.
func _desert() -> void:
	var at_home := _units_at_home()
	var unit_id := _costliest_unit(at_home)
	if unit_id.is_empty():
		return
	# Nunca mas de los que quedan en casa: pedir de mas volveria a morder a la
	# columna, que es justo lo que este camino existe para evitar.
	var quota: int = mini(GameConfig.desertion_units_per_tick, int(at_home[unit_id]))
	var removed := remove_units({unit_id: quota})
	var gone: int = int(removed.get(unit_id, 0))
	if gone <= 0:
		return
	var def := GameConfig.get_unit_def(unit_id)
	EventBus.army_deserted.emit(unit_id, gone)
	EventBus.notification_posted.emit(
		Tr.t("NOTIF_DESERTION") % [gone, Tr.t(def.get("name", unit_id))],
		"danger", UITheme.DANGER)

## El ejercito menos la columna que esta fuera, unit_id -> cuantos hay en casa.
## Las entradas a cero no salen: quien consulte esto pregunta por quien queda.
##
## CombatManager se carga DESPUES que este servicio (project.godot), asi que solo
## se le pregunta en caliente, nunca durante _ready — exactamente igual que este
## mismo archivo ya hace con StormManager, que tambien va detras.
func _units_at_home() -> Dictionary:
	var away: Dictionary = CombatManager.get_units_on_expedition()
	var home: Dictionary = {}
	for id in _units:
		var count: int = int(_units[id]) - int(away.get(id, 0))
		if count > 0:
			home[id] = count
	return home

## La mas cara de mantener dentro de `pool` (unit_id -> cantidad). En empate gana
## la mas antigua del diccionario, que basta para que el resultado sea siempre el
## mismo. Recibe el conjunto en vez de mirar `_units` porque quien deserta no es
## el ejercito entero: es la parte que sigue en casa.
func _costliest_unit(pool: Dictionary) -> String:
	var worst := ""
	var worst_upkeep := -1
	for id in pool:
		if int(pool[id]) <= 0:
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
	# Partida nueva: el cielo tambien empieza limpio.
	_ash_overhead = false
	EventBus.army_changed.emit()
