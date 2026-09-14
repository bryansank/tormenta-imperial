extends GdUnitTestSuite
## La cola queda abierta, la Tormenta la arruina.
##
## El agujero que esto cierra no era cancelar colas: era llenarlas. El coste se
## paga al arrancar, asi que meter el almacen en la cola hacia que los Tasadores
## auditaran ceros — y con el margen de 1,5x de los procesos, esconder ahi no
## solo salvaba los recursos, los multiplicaba. Era la jugada dominante.
##
## Lo que se prueba aqui son las tres mitades de la regla, porque sin las tres
## no es una regla sino un castigo: que la cola NUNCA se bloquee, que solo la
## TORMENTA la arruine (ni la Advertencia ni la Ceniza), y que el jugador se
## entere — un aviso durante la Ceniza y una notificacion por cada cosa perdida.

var _saved_phase: int = 0
var _saved_resources: Dictionary = {}
var _saved_army: Dictionary = {}
var _nodes: Array = []
## Notificaciones vistas: [{msg, category}]. Se conecta a mano a proposito —
## `monitor_signals()` LIBERA el objeto que vigila, y pasarle EventBus mata el
## bus para todas las suites que vengan detras.
var _notices: Array = []

func before_test() -> void:
	_saved_phase = StormManager.get_cycle().phase
	_saved_resources = _resource_snapshot()
	_saved_army = ArmyManager.get_save_data()
	ArmyManager.reset()
	_notices.clear()
	EventBus.notification_posted.connect(_on_notification)
	# Se entra y se sale de la tormenta en cada prueba, asi que el cielo tiene
	# que empezar despejado o el aviso de la ceniza se arrastraria entre casos.
	EventBus.storm_ended.emit(1)

func after_test() -> void:
	EventBus.storm_ended.emit(1)
	if EventBus.notification_posted.is_connected(_on_notification):
		EventBus.notification_posted.disconnect(_on_notification)
	# Cancelar antes de liberar: un nodo invalido con proceso activo se
	# completaria solo en el siguiente frame y regalaria recursos.
	for node in _nodes:
		if is_instance_valid(node):
			ProcessManager.cancel(node)
			node.free()
	_nodes.clear()
	StormManager.get_cycle().phase = _saved_phase
	ArmyManager.load_save_data(_saved_army)
	ResourceManager.set_amounts(_saved_resources)

# ── Ayudas ───────────────────────────────────────────────────────────

func _on_notification(message: String, category: String, _color: Color) -> void:
	_notices.append({"msg": message, "category": category})

func _of_category(category: String) -> Array:
	var found: Array = []
	for notice in _notices:
		if notice["category"] == category:
			found.append(notice)
	return found

func _resource_snapshot() -> Dictionary:
	var snap := {}
	for type in ResourceManager.get_all():
		snap[ResourceManager.get_type_name(type)] = ResourceManager.get_amount(type)
	return snap

func _node() -> Node3D:
	var node := Node3D.new()
	_nodes.append(node)
	return node

func _wood() -> int:
	return ResourceManager.get_amount(ResourceManager.Type.WOOD)

func _gold() -> int:
	return ResourceManager.get_amount(ResourceManager.Type.GOLD)

func _process_def(building_id: String, process_id: String) -> Dictionary:
	for proc in ProcessManager.get_processes_for(building_id):
		if proc["id"] == process_id:
			return proc
	return {}

## Un proceso del nucleo, ya arrancado y pagado, en un nodo nuevo.
func _started_process() -> Node3D:
	var node := _node()
	assert_bool(ProcessManager.start_process(node, _process_def("nucleo", "wood_planks"))).is_true()
	return node

func _training_of(unit_id: String) -> void:
	ArmyManager.load_save_data({
		"units": {},
		"training": [{"id": unit_id, "remaining": 999.0, "duration": 999.0}],
		"upkeep_accum": 0.0,
	})

# ── La cola no se bloquea en ninguna fase ────────────────────────────

func test_the_ash_does_not_close_the_queue() -> void:
	# Gastar el almacen durante la ceniza es una decision legitima: si se
	# prohibiera, se le estaria quitando al jugador su unica palanca.
	ResourceManager.set_amounts({"wood": 300})
	EventBus.storm_ash_started.emit()
	assert_bool(ProcessManager.start_process(_node(), _process_def("nucleo", "wood_planks"))).is_true()

func test_even_the_storm_overhead_does_not_close_the_queue() -> void:
	ResourceManager.set_amounts({"wood": 300})
	EventBus.storm_started.emit(3)
	assert_bool(ProcessManager.start_process(_node(), _process_def("nucleo", "wood_planks"))).is_true()

func test_what_is_queued_after_the_storm_broke_survives_it() -> void:
	# La Tormenta arruina lo que encuentra al entrar, no lo que llegue despues.
	ResourceManager.set_amounts({"wood": 300})
	EventBus.storm_started.emit(3)
	var node := _started_process()
	assert_bool(ProcessManager.is_busy(node)).is_true()

# ── Solo la TORMENTA arruina ─────────────────────────────────────────

func test_the_warning_costs_nothing() -> void:
	ResourceManager.set_amounts({"wood": 300})
	var node := _started_process()
	EventBus.storm_incoming.emit(45.0)
	assert_bool(ProcessManager.is_busy(node)).is_true()

func test_the_ash_dirties_but_does_not_destroy() -> void:
	# Si la ceniza ya destruyera, el aviso que se da durante la ceniza llegaria
	# tarde por definicion y la regla seria injusta.
	ResourceManager.set_amounts({"wood": 300})
	var node := _started_process()
	EventBus.storm_ash_started.emit()
	assert_bool(ProcessManager.is_busy(node)).is_true()

func test_the_ash_spares_the_barracks_too() -> void:
	_training_of("infantry")
	EventBus.storm_ash_started.emit()
	assert_int(ArmyManager.get_training().size()).is_equal(1)

func test_the_storm_takes_the_process_in_flight() -> void:
	ResourceManager.set_amounts({"wood": 300})
	var node := _started_process()
	EventBus.storm_started.emit(2)
	assert_bool(ProcessManager.is_busy(node)).is_false()

func test_the_storm_takes_the_mining_in_flight() -> void:
	var node := _node()
	assert_bool(ProcessManager.start_mining(node, "gold_vein")).is_true()
	EventBus.storm_started.emit(2)
	assert_bool(ProcessManager.is_busy(node)).is_false()

func test_the_storm_takes_every_process_at_once() -> void:
	ResourceManager.set_amounts({"wood": 300})
	var first := _started_process()
	var second := _started_process()
	EventBus.storm_started.emit(2)
	assert_bool(ProcessManager.is_busy(first)).is_false()
	assert_bool(ProcessManager.is_busy(second)).is_false()

func test_the_storm_takes_the_recruit_in_training() -> void:
	_training_of("infantry")
	EventBus.storm_started.emit(2)
	assert_int(ArmyManager.get_training().size()).is_equal(0)

func test_a_recruit_lost_to_the_storm_is_never_born() -> void:
	# Perderlo no es terminarlo: no puede aparecer en la tropa por la puerta de
	# atras, o la Tormenta seria una forma barata de acelerar el entrenamiento.
	_training_of("infantry")
	EventBus.storm_started.emit(2)
	assert_int(ArmyManager.get_count("infantry")).is_equal(0)
	assert_int(ArmyManager.get_total_units()).is_equal(0)

func test_the_storm_does_not_touch_units_already_standing() -> void:
	ArmyManager.load_save_data({
		"units": {"infantry": 2},
		"training": [{"id": "infantry", "remaining": 999.0, "duration": 999.0}],
		"upkeep_accum": 0.0,
	})
	EventBus.storm_started.emit(2)
	assert_int(ArmyManager.get_count("infantry")).is_equal(2)
	assert_int(ArmyManager.get_training().size()).is_equal(0)

# ── Se pierde CON SU COSTE ───────────────────────────────────────────

func test_the_storm_gives_nothing_back_for_a_process() -> void:
	ResourceManager.set_amounts({"wood": 300})
	var node := _started_process()
	var after_paying := _wood()
	EventBus.storm_started.emit(2)
	assert_int(_wood()).is_equal(after_paying)

func test_the_storm_gives_nothing_back_for_a_recruit() -> void:
	_training_of("infantry")
	ResourceManager.set_amounts({"gold": 500, "wood": 500})
	var gold_before := _gold()
	var wood_before := _wood()
	EventBus.storm_started.emit(2)
	assert_int(_gold()).is_equal(gold_before)
	assert_int(_wood()).is_equal(wood_before)

func test_losing_it_to_the_storm_is_strictly_worse_than_cancelling() -> void:
	# Si perderlo devolviera aunque fuese poco, la cola seguiria siendo una caja
	# fuerte mas barata que el Diezmo, que como mucho se lleva el 37,5%.
	var proc := _process_def("nucleo", "wood_planks")

	ResourceManager.set_amounts({"wood": 300})
	var cancelled := _node()
	ProcessManager.start_process(cancelled, proc)
	var after_cancel: int = ProcessManager.cancel(cancelled).get("wood", 0)

	ResourceManager.set_amounts({"wood": 300})
	var doomed := _node()
	ProcessManager.start_process(doomed, proc)
	var paid := _wood()
	EventBus.storm_started.emit(2)

	assert_int(after_cancel).is_greater(0)
	assert_int(_wood() - paid).is_equal(0)

func test_the_refund_ratio_for_a_storm_loss_is_zero() -> void:
	assert_float(GameConfig.storm_queue_loss_refund_ratio).is_equal(0.0)
	assert_dict(GameConfig.get_storm_loss_refund({"wood": 1000})).is_empty()

func test_only_the_storm_phase_ruins_the_queue() -> void:
	assert_bool(GameConfig.storm_phase_ruins_queue(StormCycle.Phase.STORM)).is_true()
	assert_bool(GameConfig.storm_phase_ruins_queue(StormCycle.Phase.ASH)).is_false()
	assert_bool(GameConfig.storm_phase_ruins_queue(StormCycle.Phase.WARNING)).is_false()
	assert_bool(GameConfig.storm_phase_ruins_queue(StormCycle.Phase.CALM)).is_false()

# ── Una notificacion por cada cosa perdida ───────────────────────────

func test_one_notice_for_each_process_lost() -> void:
	ResourceManager.set_amounts({"wood": 300})
	_started_process()
	_started_process()
	_started_process()
	_notices.clear()
	EventBus.storm_started.emit(2)
	assert_int(_of_category("danger").size()).is_equal(3)

func test_one_notice_for_each_recruit_lost() -> void:
	ArmyManager.load_save_data({
		"units": {},
		"training": [
			{"id": "infantry", "remaining": 999.0, "duration": 999.0},
			{"id": "infantry", "remaining": 999.0, "duration": 999.0},
		],
		"upkeep_accum": 0.0,
	})
	_notices.clear()
	EventBus.storm_started.emit(2)
	assert_int(_of_category("danger").size()).is_equal(2)

func test_a_storm_over_an_empty_queue_says_nothing() -> void:
	# Ni ruido ni falsos positivos: sin nada en curso no se ha perdido nada.
	_notices.clear()
	EventBus.storm_started.emit(2)
	assert_int(_of_category("danger").size()).is_equal(0)

func test_the_notice_names_what_was_lost() -> void:
	ResourceManager.set_amounts({"wood": 300})
	var proc := _process_def("nucleo", "wood_planks")
	_started_process()
	_notices.clear()
	EventBus.storm_started.emit(2)
	var lost: Array = _of_category("danger")
	assert_int(lost.size()).is_equal(1)
	assert_str(str(lost[0]["msg"])).contains(Tr.t(proc["name"]))

# ── El aviso durante la Ceniza ───────────────────────────────────────

func test_the_ash_warns_about_the_queue_before_it_bites() -> void:
	# Esto no es opcional: es la diferencia entre una regla dura y una injusta.
	ResourceManager.set_amounts({"wood": 300})
	_started_process()
	_notices.clear()
	EventBus.storm_ash_started.emit()
	assert_int(_of_category("warning").size()).is_greater(0)

func test_the_ash_warns_about_the_barracks_too() -> void:
	_training_of("infantry")
	_notices.clear()
	EventBus.storm_ash_started.emit()
	assert_int(_of_category("warning").size()).is_greater(0)

func test_the_ash_keeps_quiet_when_there_is_nothing_to_lose() -> void:
	_notices.clear()
	EventBus.storm_ash_started.emit()
	assert_int(_of_category("warning").size()).is_equal(0)

func test_queueing_during_the_ash_gets_its_own_warning() -> void:
	# Quien encola durante la ceniza es justo quien va a perderlo, y llego tarde
	# al aviso de entrada porque entonces no tenia nada dentro.
	ResourceManager.set_amounts({"wood": 300})
	EventBus.storm_ash_started.emit()
	_notices.clear()
	_started_process()
	assert_int(_of_category("warning").size()).is_greater(0)

func test_the_warning_speaks_of_the_cost_not_of_the_refund() -> void:
	# Con la bolsa llena el reembolso de cancelar es 0, pero lo que la Tormenta
	# quita sigue siendo el coste entero. Anunciar el reembolso diria "vas a
	# perder 0" justo antes de quitarle la madera: peor que no avisar.
	ResourceManager.set_amounts({"wood": 300})
	var node := _started_process()
	var cost: Dictionary = ProcessManager.get_active(node).get("cost", {})
	assert_int(int(ProcessManager.get_queue_at_risk().get("wood", 0))).is_equal(int(cost["wood"]))
	assert_dict(ProcessManager.get_storm_loss_preview(node)).is_empty()

func test_the_barracks_warning_also_speaks_of_the_cost() -> void:
	_training_of("infantry")
	var cost: Dictionary = GameConfig.get_unit_def("infantry").get("cost", {})
	assert_int(int(ArmyManager.get_training_at_risk().get("gold", 0))).is_equal(int(cost["gold"]))

# ── Partida nueva: la otra forma de dejar la cola colgando ───────────

func test_a_new_game_empties_the_queue() -> void:
	ResourceManager.set_amounts({"wood": 300})
	var node := _started_process()
	ProcessManager.reset()
	assert_bool(ProcessManager.is_busy(node)).is_false()

func test_a_new_game_pays_nothing_for_what_was_in_the_queue() -> void:
	# Reiniciar no es ni una entrega ni un reembolso: si abonara algo, empezar
	# partida nueva con la cola llena seria una forma de empezar rico.
	ResourceManager.set_amounts({"wood": 300})
	_started_process()
	var after_paying := _wood()
	ProcessManager.reset()
	assert_int(_wood()).is_equal(after_paying)

func test_a_new_game_says_nothing_about_the_queue() -> void:
	# Nadie quiere leer "has perdido tu proceso" al empezar una partida.
	ResourceManager.set_amounts({"wood": 300})
	_started_process()
	_notices.clear()
	ProcessManager.reset()
	assert_int(_notices.size()).is_equal(0)

func test_a_process_whose_building_is_gone_delivers_nothing() -> void:
	# El guard vive donde se paga, no en quien llama: asi no puede volver el
	# fallo por una puerta nueva. Antes, un nodo liberado con proceso en curso
	# se completaba solo al frame siguiente y abonaba la produccion igual.
	ResourceManager.set_amounts({"wood": 300})
	var orphan := Node3D.new()
	ProcessManager.start_process(orphan, _process_def("nucleo", "wood_planks"))
	var after_paying := _wood()
	orphan.free()
	await get_tree().process_frame
	await get_tree().process_frame
	# No puede SUBIR: el fallo era un regalo, y pasan frames de por medio en los
	# que el consumo de la poblacion si puede bajar la madera legitimamente.
	# No se pregunta por el nodo: a `is_busy(node: Node3D)` no se le puede pasar
	# uno liberado, que es la mitad del fallo que esto fija.
	assert_int(_wood()).is_less_equal(after_paying)

func test_no_more_warnings_once_the_sky_clears() -> void:
	ResourceManager.set_amounts({"wood": 300})
	EventBus.storm_ash_started.emit()
	EventBus.storm_ended.emit(2)
	_notices.clear()
	_started_process()
	assert_int(_of_category("warning").size()).is_equal(0)
