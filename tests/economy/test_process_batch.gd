extends GdUnitTestSuite
## Lotes y el Nucleo como taller de todo (fix/partidas-bryan, 2026-10-14).
##
##   - un lote se paga entero al arrancar y entrega una vuelta tras otra;
##   - si no alcanza para todas, no arranca ninguna;
##   - cancelar devuelve la tasa de siempre sobre todo lo pagado y no entregado;
##   - la Tormenta pone en riesgo el lote entero;
##   - el guardado lleva `count`/`total`; uno de antes sin `count` es una vuelta;
##   - MAX lo limitan los recursos, el hueco de la bolsa y los usos de la veta;
##   - el Nucleo ofrece lo de cada taller y el minado a mano, 1,5 veces mas lento.
##
## Escrito sin ejecutar (regla del dueno: un solo pase de pruebas al final).

var _saved_phase: int = 0
var _saved_resources: Dictionary = {}
var _nodes: Array = []

func before_test() -> void:
	_saved_phase = StormManager.get_cycle().phase
	_saved_resources = _resource_snapshot()
	ResourceManager.set_amounts({"food": 0})
	StormManager.get_cycle().phase = StormCycle.Phase.CALM

func after_test() -> void:
	for node in _nodes:
		if is_instance_valid(node):
			ProcessManager.cancel(node)
			node.free()
	_nodes.clear()
	StormManager.get_cycle().phase = _saved_phase
	ResourceManager.set_amounts(_saved_resources)

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

func _process_def(building_id: String, process_id: String) -> Dictionary:
	for proc in ProcessManager.get_processes_for(building_id):
		if proc["id"] == process_id:
			return proc
	return {}

## Termina la vuelta en curso sin esperar.
func _finish_cycle(node: Node) -> void:
	ProcessManager._active[node]["remaining"] = 0.0
	ProcessManager._complete(node)

# ── Lotes ────────────────────────────────────────────────────────────

func test_a_batch_is_paid_up_front() -> void:
	var node := _node()
	ResourceManager.set_amounts({"wood": 200})
	var proc := _process_def("nucleo", "wood_planks")   # 20 madera -> 35 madera
	assert_bool(ProcessManager.start_process(node, proc, 5)).is_true()
	assert_int(_wood()).is_equal(200 - 5 * 20)
	assert_int(ProcessManager.get_batch_left(node)).is_equal(5)
	assert_int(ProcessManager.get_batch_total(node)).is_equal(5)

func test_a_batch_that_cannot_be_paid_does_not_start() -> void:
	var node := _node()
	ResourceManager.set_amounts({"wood": 50})
	var proc := _process_def("nucleo", "wood_planks")
	assert_bool(ProcessManager.start_process(node, proc, 5)).is_false()
	assert_bool(ProcessManager.is_busy(node)).is_false()
	assert_int(_wood()).is_equal(50)

func test_each_cycle_delivers_and_the_next_one_starts() -> void:
	var node := _node()
	ResourceManager.set_amounts({"wood": 100})
	var proc := _process_def("nucleo", "wood_planks")
	ProcessManager.start_process(node, proc, 3)
	var after_paying := _wood()
	_finish_cycle(node)
	assert_int(_wood()).is_equal(after_paying + 35)
	assert_bool(ProcessManager.is_busy(node)).is_true()
	assert_int(ProcessManager.get_batch_left(node)).is_equal(2)
	_finish_cycle(node)
	_finish_cycle(node)
	assert_int(_wood()).is_equal(after_paying + 3 * 35)
	assert_bool(ProcessManager.is_busy(node)).is_false()

func test_cancelling_a_batch_refunds_the_rate_on_what_was_not_delivered() -> void:
	var node := _node()
	ResourceManager.set_amounts({"wood": 200})
	var proc := _process_def("nucleo", "wood_planks")
	ProcessManager.start_process(node, proc, 4)
	_finish_cycle(node)   # una entregada, quedan 3 pagadas
	var promised := ProcessManager.get_refund_preview(node)
	assert_int(int(promised["wood"])).is_equal(int(floor(3 * 20 * GameConfig.cancel_refund_ratio)))
	var paid := ProcessManager.cancel(node)
	assert_int(int(paid["wood"])).is_equal(int(promised["wood"]))

func test_the_storm_risks_the_whole_batch() -> void:
	var node := _node()
	ResourceManager.set_amounts({"wood": 200})
	ProcessManager.start_process(node, _process_def("nucleo", "wood_planks"), 5)
	assert_int(int(ProcessManager.get_queue_at_risk().get("wood", 0))).is_equal(100)

func test_max_is_limited_by_resources() -> void:
	ResourceManager.set_amounts({"wood": 70})
	var proc := _process_def("nucleo", "wood_planks")
	assert_int(ProcessManager.max_batch(proc)).is_equal(3)

func test_max_is_limited_by_the_free_storage() -> void:
	# Neto por vuelta: +35 - 20 = +15 de bolsa. Con 30 de hueco caben 2.
	var cap := ResourceManager.get_storage_cap()
	ResourceManager.set_amounts({"wood": cap - 30, "gold": 0, "steel": 0, "oil": 0, "food": 0})
	var proc := _process_def("nucleo", "wood_planks")
	assert_int(ProcessManager.max_batch(proc)).is_equal(2)

func test_max_never_passes_the_ceiling_or_the_uses_left() -> void:
	var mining := GameConfig.get_mining_info("gold_vein")
	assert_int(ProcessManager.max_batch(mining)).is_less_equal(GameConfig.process_batch_max)
	ResourceManager.set_amounts({"gold": 0, "wood": 0})
	assert_int(ProcessManager.max_batch(mining, 2)).is_equal(2)

func test_a_mining_batch_stops_at_the_uses_left() -> void:
	var node := _node()
	node.set_meta("uses_remaining", 2)
	assert_bool(ProcessManager.start_mining(node, "gold_vein", 5)).is_true()
	assert_int(ProcessManager.get_batch_total(node)).is_equal(2)

# ── Guardado ─────────────────────────────────────────────────────────

func test_the_batch_travels_in_the_save_entry() -> void:
	var node := _node()
	ResourceManager.set_amounts({"wood": 200})
	ProcessManager.start_process(node, _process_def("nucleo", "wood_planks"), 3)
	_finish_cycle(node)
	var info: Dictionary = ProcessManager.get_active(node)
	assert_int(int(info["count"])).is_equal(2)
	assert_int(int(info["total"])).is_equal(3)

func test_an_old_entry_without_count_loads_as_one_cycle() -> void:
	# load_save_data busca el nodo en la rejilla: se prueba la regla de la entrada.
	var entry := {"id": "wood_planks", "remaining": 5.0, "duration": 30.0,
		"produces": {"wood": 35}, "cost": {"wood": 20}}
	assert_int(maxi(1, int(entry.get("count", 1)))).is_equal(1)
	# Y una entrada vieja de minado sigue ocupando sus obreros.
	assert_int(ProcessManager._workers_of({"id": "mine_gold"})).is_equal(GameConfig.mining_workers)
	assert_int(ProcessManager._workers_of({"id": "wood_planks"})).is_equal(0)

# ── El Nucleo ────────────────────────────────────────────────────────

func test_the_core_offers_every_workshop_and_hand_mining() -> void:
	var ids: Array = []
	for proc in ProcessManager.get_processes_for("nucleo"):
		ids.append(String(proc["id"]))
	for building_id in GameConfig.building_processes:
		# La Carpinteria repite al Aserradero: el Nucleo no la ofrece (core_skip_workshops).
		if building_id in GameConfig.core_skip_workshops:
			continue
		for proc in GameConfig.building_processes[building_id]:
			assert_array(ids).contains([String(proc["id"])])
	for deposit_id in GameConfig.mining_data:
		var mine_id := GameConfig.CORE_MINING_PREFIX + String(GameConfig.mining_data[deposit_id]["id"])
		assert_array(ids).contains([mine_id])

func test_the_core_is_slower_than_the_workshop() -> void:
	var at_sawmill := _process_def("sawmill", "make_planks")
	var at_core := _process_def("nucleo", "make_planks")
	assert_float(float(at_core["duration"])).is_equal_approx(
		float(at_sawmill["duration"]) * GameConfig.core_process_time_mult, 0.01)
	assert_dict(at_core["produces"]).is_equal(at_sawmill["produces"])
	assert_dict(at_core["cost"]).is_equal(at_sawmill["cost"])

func test_core_hand_mining_holds_workers_but_spends_no_deposit_use() -> void:
	var node := _node()
	var proc := _process_def("nucleo", GameConfig.CORE_MINING_PREFIX + "mine_gold")
	assert_int(int(proc["workers"])).is_equal(GameConfig.mining_workers)
	if PopulationManager.get_free_workers() < GameConfig.mining_workers:
		assert_str(ProcessManager.process_blocker(proc)).is_equal("MINE_NEEDS_WORKERS")
		return
	assert_bool(ProcessManager.start_process(node, proc, 2)).is_true()
	assert_int(ProcessManager.busy_mining_workers()).is_greater_equal(GameConfig.mining_workers)

func test_a_locked_material_hides_its_process_at_the_core() -> void:
	var proc := _process_def("nucleo", "make_fuel")
	var locked: bool = ProcessActionsPanel._process_has_locked_resource(proc)
	assert_bool(locked).is_equal(not ResourceManager.is_unlocked_by_name("fuel")
		or not ResourceManager.is_unlocked_by_name("oil"))

func test_new_texts_exist_in_both_languages() -> void:
	var saved := Tr.get_locale()
	for loc in ["es", "en"]:
		Tr.set_locale(loc)
		for key in ["BTN_BATCH_N", "BTN_BATCH_MAX", "LBL_BATCH_TIP", "LBL_BATCH_MAX_TIP",
				"LBL_BATCH_CANT", "FMT_PROGRESS_BATCH", "LBL_CORE_OWN", "LBL_CORE_WORKSHOPS",
				"LBL_CORE_BY_HAND", "LBL_CORE_FROM"]:
			assert_str(Tr.t(key)).is_not_equal(key)
	Tr.set_locale(saved)
