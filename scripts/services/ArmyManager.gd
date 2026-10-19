extends Node
## Trains and maintains the player's army — the management → combat bridge.
## Units are produced at Barracks over time, cost resources, consume gold upkeep,
## and contribute to Military Power. Combat (planned) will consume this army.
##
## Training model: one unit trains per Barracks at a time (parallel slots =
## barracks count, up to GameConfig.army_training_slots_max). Army size is
## capped by GameConfig.get_army_capacity() (diminishing per barracks, with a
## ceiling: the Barracks has no building cap since 2026-10-18).

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

const RegimentLook := preload("res://scripts/ui/RegimentLook.gd")
const ColonyIdentity := preload("res://scripts/services/ColonyIdentity.gd")
const ColonyFlag := preload("res://scripts/ui/ColonyFlag.gd")

## El regimiento: nombre, color, emblema, pintura y combates ganados. SOLO
## COSMETICO (docs/15 §12): nada del combate lo lee. Viaja en el guardado
## dentro de "army" como "regiment"; lo que se pinta es get_regiment_look().
var _regiment: Dictionary = RegimentLook.defaults()
## El aspecto ya resuelto, rehecho solo cuando cambia el regimiento, el rango,
## el modo o la bandera (`_look_key`): el tablero 2D lo pide por casilla.
var _look_cache: Dictionary = {}
var _look_key := ""

var _type_map := {
	"gold": ResourceManager.Type.GOLD,
	"steel": ResourceManager.Type.STEEL,
	"oil": ResourceManager.Type.OIL,
	"wood": ResourceManager.Type.WOOD,
	"planks": ResourceManager.Type.PLANKS,
	"ingots": ResourceManager.Type.INGOTS,
	"beams": ResourceManager.Type.BEAMS,
	"fuel": ResourceManager.Type.FUEL,
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
	# Las estrellas: combates ganados, como cuenta la XP del rango.
	EventBus.encounter_ended.connect(_on_encounter_ended)
	EventBus.defense_auto_resolved.connect(func(victory, _r, _s): _on_encounter_ended(victory, 0))

func _resync_storm_phase() -> void:
	_ash_overhead = StormManager.is_ashfall() and not StormManager.is_trial_running()

func _process(delta: float) -> void:
	# x2: la simulacion avanza al doble (GameConfig.sim_delta).
	delta = GameConfig.sim_delta(delta)
	_advance_training(delta)
	_advance_upkeep(delta)

# ── Regimiento (cosmetico) ──

## Lo guardado, en copia.
func get_regiment() -> Dictionary:
	return _regiment.duplicate()

## Lo que se pinta: nombre para ensenar, color, emblema, pintura y estrellas,
## con las piezas que el rango no abre cambiadas por las de la bandera.
func get_regiment_look() -> Dictionary:
	var flag := RankManager.get_flag_spec()
	var key := "%d|%s|%s" % [RankManager.get_rank(), str(GameMode.all_unlocked()), ColonyFlag.spec_key(flag)]
	if _look_cache.is_empty() or key != _look_key:
		_look_cache = RegimentLook.resolve(_regiment, RankManager.get_rank(), GameMode.all_unlocked(), flag)
		_look_key = key
	return _look_cache.duplicate()

## Cambia nombre, color, emblema y pintura. "" en nombre = el de serie; "" en
## color o emblema = los de la bandera. Falla (false, sin tocar nada) si el
## nombre no pasa el filtro del pais o alguna pieza no esta abierta por rango.
## Avisa y guarda solo si algo cambio. No toca las victorias.
func set_regiment(reg_name: String, color_id: String, emblem: String, paint: String) -> bool:
	var rank := RankManager.get_rank()
	var all := GameMode.all_unlocked()
	var clean := ColonyIdentity.clean_name(reg_name)
	if not clean.is_empty() and not ColonyIdentity.is_name_allowed(clean):
		return false
	if color_id != "" and not RegimentLook.is_open("colors", color_id, rank, all):
		return false
	if emblem != "" and not RegimentLook.is_open("emblems", emblem, rank, all):
		return false
	if not RegimentLook.is_paint_open(paint, rank, all):
		return false
	var next := RegimentLook.normalized({"name": clean, "color": color_id, "emblem": emblem,
		"paint": paint, "wins": _regiment.get("wins", 0)})
	if next == _regiment:
		return true
	_regiment = next
	_invalidate_look()
	EventBus.regiment_changed.emit()
	GameManager.request_save()
	return true

func _on_encounter_ended(victory: bool, _turns: int) -> void:
	if victory:
		_record_regiment_win()

func _record_regiment_win() -> void:
	var before := RegimentLook.stars_for(int(_regiment.get("wins", 0)))
	_regiment["wins"] = int(_regiment.get("wins", 0)) + 1
	_invalidate_look()
	if RegimentLook.stars_for(int(_regiment["wins"])) != before:
		EventBus.regiment_changed.emit()

func _invalidate_look() -> void:
	_look_cache = {}

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
	return building_count("barracks")

## Cuantos edificios `building_id` hay en el mapa (BuildingPlacer de la escena).
## Lo usan el Cuartel, el Astillero y el Aerodromo (aire y mar).
func building_count(building_id: String) -> int:
	var scene := get_tree().current_scene
	if scene:
		var placer := scene.get_node_or_null("BuildingPlacer")
		if placer and placer.has_method("count_building"):
			return placer.count_building(building_id)
	return 0

## Hay al menos un edificio que entrena tropa (Cuartel, Astillero o Aerodromo):
## con el se ensenan el panel del ejercito y las escaramuzas.
func has_military_building() -> bool:
	for building_id in GameConfig.MILITARY_BUILDINGS:
		if building_count(String(building_id)) > 0:
			return true
	return false

## Edificio militar -> cuantos hay.
func military_building_counts() -> Dictionary:
	var counts: Dictionary = {}
	for building_id in GameConfig.MILITARY_BUILDINGS:
		counts[String(building_id)] = building_count(String(building_id))
	return counts

func get_capacity() -> int:
	return GameConfig.get_army_capacity_for(military_building_counts())

## Units owned + units currently training (both occupy capacity).
func get_used_capacity() -> int:
	return get_total_units() + _training.size()

## Parallel training slots = one per military building, up to the ceiling of
## its kind (GameConfig.get_training_slots_for). Con `building_id`, solo los de
## ese edificio (cada Astillero entrena barcos, no soldados).
func max_slots(building_id: String = "") -> int:
	if building_id != "":
		return GameConfig.get_training_slots_for(building_id, building_count(building_id))
	var total := 0
	for id in GameConfig.MILITARY_BUILDINGS:
		total += GameConfig.get_training_slots_for(String(id), building_count(String(id)))
	return total

## Cuantas unidades se entrenan ahora mismo en los edificios `building_id`.
func training_in(building_id: String) -> int:
	var busy := 0
	for entry in _training:
		if GameConfig.get_unit_building(str(entry.get("id", ""))) == building_id:
			busy += 1
	return busy

func is_unlocked(unit_id: String) -> bool:
	var def := GameConfig.get_unit_def(unit_id)
	if def.is_empty():
		return false
	return ProgressionManager.current_era >= int(def.get("era", 1))

## La clave de Tr de "Necesitas un <edificio>" para entrenar `unit_id`.
static func need_building_key(unit_id: String) -> String:
	match GameConfig.get_unit_building(unit_id):
		"shipyard":
			return "LBL_ARMY_NEED_SHIPYARD"
		"aerodrome":
			return "LBL_ARMY_NEED_AERODROME"
	return "LBL_ARMY_NEED_BARRACKS"

## Returns {ok: bool, reason: String}. `reason` is a translation key when not ok.
##
## Aire y mar: cada unidad se entrena en SU edificio (unit_types[...]["building"])
## y ocupa un hueco de los de ese edificio; la capacidad es una sola para todo el
## ejercito (GameConfig.get_army_capacity_for).
func can_train(unit_id: String) -> Dictionary:
	var def := GameConfig.get_unit_def(unit_id)
	if def.is_empty():
		return {"ok": false, "reason": "LBL_ARMY_NO_UNIT"}
	var building_id: String = GameConfig.get_unit_building(unit_id)
	if building_count(building_id) <= 0:
		return {"ok": false, "reason": need_building_key(unit_id)}
	if not is_unlocked(unit_id):
		return {"ok": false, "reason": "LBL_ARMY_LOCKED"}
	if training_in(building_id) >= max_slots(building_id):
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
	# La tormenta de prueba de la era 1 no se lleva la cola: es un ensayo.
	if StormManager.is_trial_running():
		return
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
	# La tormenta de prueba de la era 1 no se lleva la cola: es un ensayo.
	if StormManager.is_trial_running():
		return
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

## El ejercito menos la columna que esta fuera y quien pelea en el tablero
## abierto, unit_id -> cuantos hay en casa. Las entradas a cero no salen: quien
## consulte esto pregunta por quien queda. Un soldado en pleno combate tampoco
## deserta: si lo hiciera, su baja posterior se cobraria sobre otro.
##
## CombatManager se carga DESPUES que este servicio (project.godot), asi que solo
## se le pregunta en caliente, nunca durante _ready — exactamente igual que este
## mismo archivo ya hace con StormManager, que tambien va detras.
func _units_at_home() -> Dictionary:
	var away: Dictionary = CombatManager.get_units_away()
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
		"regiment": _regiment.duplicate(),
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
	# Sin "regiment" (guardado viejo): el de serie. Se deriva de lo guardado,
	# no se suma: cargar dos veces da lo mismo. Las piezas no se recortan aqui
	# (el rango carga despues): lo hace get_regiment_look() al pintar.
	_regiment = RegimentLook.normalized(data.get("regiment", {}))
	_invalidate_look()
	EventBus.army_changed.emit()
	EventBus.regiment_changed.emit()

func reset() -> void:
	_units.clear()
	_training.clear()
	_upkeep_accum = 0.0
	_unpaid_ticks = 0
	_regiment = RegimentLook.defaults()
	_invalidate_look()
	# Partida nueva: el cielo tambien empieza limpio.
	_ash_overhead = false
	EventBus.army_changed.emit()
