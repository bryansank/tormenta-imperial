extends GdUnitTestSuite
## La Tasa de Corrupcion: arrepentirse cuesta, y con la Tormenta en marcha
## cuesta el doble.
##
## Lo que se prueba aqui no es la aritmetica por la aritmetica: es que el numero
## que la UI promete antes de confirmar sea exactamente el que se abona. Un
## reembolso que no coincide con lo anunciado es peor que no tener reembolso.

var _saved_phase: int = 0
var _saved_resources: Dictionary = {}
var _saved_army: Dictionary = {}
var _nodes: Array = []

func before_test() -> void:
	_saved_phase = StormManager.get_cycle().phase
	_saved_resources = _resource_snapshot()
	_saved_army = ArmyManager.get_save_data()
	ArmyManager.reset()
	_set_phase(StormCycle.Phase.CALM)

func after_test() -> void:
	# Cancelar antes de liberar: un nodo invalido con proceso activo se
	# completaria solo en el siguiente frame y regalaria recursos.
	for node in _nodes:
		if is_instance_valid(node):
			ProcessManager.cancel(node)
			node.free()
	_nodes.clear()
	_set_phase(_saved_phase)
	ArmyManager.load_save_data(_saved_army)
	ResourceManager.set_amounts(_saved_resources)

# ── Ayudas ───────────────────────────────────────────────────────────

func _resource_snapshot() -> Dictionary:
	var snap := {}
	for type in ResourceManager.get_all():
		snap[ResourceManager.get_type_name(type)] = ResourceManager.get_amount(type)
	return snap

func _set_phase(phase: int) -> void:
	StormManager.get_cycle().phase = phase

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

func _training_of(unit_id: String) -> void:
	ArmyManager.load_save_data({
		"units": {},
		"training": [{"id": unit_id, "remaining": 999.0, "duration": 999.0}],
		"upkeep_accum": 0.0,
	})

# ── La tasa ──────────────────────────────────────────────────────────

func test_the_storm_makes_regret_more_expensive() -> void:
	assert_float(GameConfig.cancel_refund_ratio_storm).is_less(GameConfig.cancel_refund_ratio)

func test_calm_refunds_the_calm_ratio() -> void:
	_set_phase(StormCycle.Phase.CALM)
	assert_float(GameConfig.get_cancel_refund_ratio()).is_equal(GameConfig.cancel_refund_ratio)
	var refund := GameConfig.get_cancel_refund({"wood": 100})
	assert_int(int(refund["wood"])).is_equal(int(100.0 * GameConfig.cancel_refund_ratio))

func test_a_storm_overhead_eats_the_difference() -> void:
	_set_phase(StormCycle.Phase.STORM)
	assert_float(GameConfig.get_cancel_refund_ratio()).is_equal(GameConfig.cancel_refund_ratio_storm)
	var refund := GameConfig.get_cancel_refund({"wood": 100})
	assert_int(int(refund["wood"])).is_equal(int(100.0 * GameConfig.cancel_refund_ratio_storm))

func test_the_assessors_on_the_road_already_hurt() -> void:
	# Avisada y cobrando cuentan igual que la tormenta encima: cancelar con los
	# Tasadores de camino es justo la fuga de capitales que se quiere castigar.
	_set_phase(StormCycle.Phase.WARNING)
	assert_float(GameConfig.get_cancel_refund_ratio()).is_equal(GameConfig.cancel_refund_ratio_storm)
	_set_phase(StormCycle.Phase.TITHE)
	assert_float(GameConfig.get_cancel_refund_ratio()).is_equal(GameConfig.cancel_refund_ratio_storm)

func test_the_house_never_loses_on_the_rounding() -> void:
	# Redondeo hacia abajo, y lo que se quedaria en cero no se anuncia siquiera.
	assert_bool(GameConfig.get_cancel_refund({"wood": 1}).has("wood")).is_false()
	assert_int(int(GameConfig.get_cancel_refund({"wood": 3})["wood"])).is_equal(2)

# ── Cancelar un proceso ──────────────────────────────────────────────

func test_cancelling_pays_exactly_what_the_panel_promised() -> void:
	var node := _node()
	ResourceManager.set_amounts({"wood": 200})
	var proc := _process_def("nucleo", "wood_planks")
	assert_bool(ProcessManager.start_process(node, proc)).is_true()

	var after_paying := _wood()
	var promised := ProcessManager.get_refund_preview(node)
	assert_bool(promised.has("wood")).is_true()

	var paid := ProcessManager.cancel(node)
	assert_int(int(paid["wood"])).is_equal(int(promised["wood"]))
	assert_int(_wood()).is_equal(after_paying + int(promised["wood"]))

func test_cancelling_never_returns_the_whole_cost() -> void:
	var node := _node()
	ResourceManager.set_amounts({"wood": 200})
	var proc := _process_def("nucleo", "wood_planks")
	var before := _wood()
	ProcessManager.start_process(node, proc)
	ProcessManager.cancel(node)
	assert_int(_wood()).is_less(before)

func test_a_storm_cancellation_returns_less_than_a_calm_one() -> void:
	var proc := _process_def("nucleo", "wood_planks")

	var calm_node := _node()
	ResourceManager.set_amounts({"wood": 200})
	ProcessManager.start_process(calm_node, proc)
	var calm_refund: int = int(ProcessManager.cancel(calm_node).get("wood", 0))

	_set_phase(StormCycle.Phase.STORM)
	var storm_node := _node()
	ResourceManager.set_amounts({"wood": 200})
	ProcessManager.start_process(storm_node, proc)
	var storm_refund: int = int(ProcessManager.cancel(storm_node).get("wood", 0))

	assert_int(storm_refund).is_less(calm_refund)

func test_the_building_is_free_again_after_cancelling() -> void:
	var node := _node()
	ResourceManager.set_amounts({"wood": 200})
	ProcessManager.start_process(node, _process_def("nucleo", "wood_planks"))
	assert_bool(ProcessManager.is_busy(node)).is_true()
	ProcessManager.cancel(node)
	assert_bool(ProcessManager.is_busy(node)).is_false()

func test_cancelling_an_idle_building_does_nothing() -> void:
	var node := _node()
	var before := _wood()
	assert_dict(ProcessManager.cancel(node)).is_empty()
	assert_int(_wood()).is_equal(before)

func test_mining_only_costs_the_time_it_took() -> void:
	# Minar no se paga con recursos, asi que cancelar no puede devolver ninguno.
	# El panel lo dice antes: "sin reembolso".
	var node := _node()
	assert_bool(ProcessManager.start_mining(node, "gold_vein")).is_true()
	assert_dict(ProcessManager.get_refund_preview(node)).is_empty()
	assert_dict(ProcessManager.cancel(node)).is_empty()
	assert_bool(ProcessManager.is_busy(node)).is_false()

# ── Cancelar un entrenamiento ────────────────────────────────────────

func test_cancelling_training_gives_back_its_share() -> void:
	_training_of("infantry")
	# La bolsa es compartida y en Era 1 son 600: 500+500 la dejaria llena y el
	# reembolso no tendria donde caer. Eso se prueba aparte, mas abajo.
	ResourceManager.set_amounts({"gold": 200, "wood": 200})
	var promised := ArmyManager.get_training_refund(0)
	assert_bool(promised.has("gold")).is_true()

	var gold_before := _gold()
	var wood_before := _wood()
	var paid := ArmyManager.cancel_training(0)

	assert_int(int(paid["gold"])).is_equal(int(promised["gold"]))
	assert_int(_gold()).is_equal(gold_before + int(promised["gold"]))
	assert_int(_wood()).is_equal(wood_before + int(promised.get("wood", 0)))
	assert_int(ArmyManager.get_training().size()).is_equal(0)

## Con la bolsa llena el reembolso no cabe, y el boton tiene que decirlo antes.
## Prometer un 70% que luego no se abona es peor que no ofrecer reembolso: el
## jugador cancela contando con un dinero que no va a ver.
func test_a_full_bag_promises_nothing_and_keeps_its_word() -> void:
	_training_of("infantry")
	var cap := ResourceManager.get_storage_cap()
	ResourceManager.set_amounts({"gold": cap, "wood": 0})
	assert_bool(ResourceManager.is_storage_full()).is_true()

	var promised := ArmyManager.get_training_refund(0)
	assert_bool(promised.is_empty()).is_true()

	var gold_before := _gold()
	var paid := ArmyManager.cancel_training(0)
	assert_bool(paid.is_empty()).is_true()
	assert_int(_gold()).is_equal(gold_before)
	assert_int(ArmyManager.get_training().size()).is_equal(0)

func test_a_cancelled_recruit_is_never_born() -> void:
	_training_of("infantry")
	ArmyManager.cancel_training(0)
	assert_int(ArmyManager.get_count("infantry")).is_equal(0)
	assert_int(ArmyManager.get_total_units()).is_equal(0)

func test_training_refund_also_shrinks_under_the_storm() -> void:
	_training_of("infantry")
	var calm := ArmyManager.get_training_refund(0)
	_set_phase(StormCycle.Phase.STORM)
	var stormy := ArmyManager.get_training_refund(0)
	assert_int(int(stormy["gold"])).is_less(int(calm["gold"]))

func test_cancelling_a_slot_that_does_not_exist_is_harmless() -> void:
	_training_of("infantry")
	var gold_before := _gold()
	assert_dict(ArmyManager.cancel_training(7)).is_empty()
	assert_dict(ArmyManager.cancel_training(-1)).is_empty()
	assert_int(ArmyManager.get_training().size()).is_equal(1)
	assert_int(_gold()).is_equal(gold_before)
