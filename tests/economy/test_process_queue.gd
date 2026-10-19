extends GdUnitTestSuite
## Tandas que acumulan (decision de Bryan, 2026-10-19): x1 + x1 + x5 = 7 en la
## cola del mismo proceso; se cobra al encolar; quitar tandas sin empezar las
## devuelve enteras; nunca mas de process_batch_max; otro proceso no se encola.

var _saved_phase: int = 0
var _saved_resources: Dictionary = {}
var _nodes: Array = []

func before_test() -> void:
	_saved_phase = StormManager.get_cycle().phase
	_saved_resources = {}
	for type in ResourceManager.get_all():
		_saved_resources[ResourceManager.get_type_name(type)] = ResourceManager.get_amount(type)
	StormManager.get_cycle().phase = StormCycle.Phase.CALM

func after_test() -> void:
	for node in _nodes:
		if is_instance_valid(node):
			ProcessManager.cancel(node)
			node.free()
	_nodes.clear()
	StormManager.get_cycle().phase = _saved_phase
	ResourceManager.set_amounts(_saved_resources)

func _node() -> Node3D:
	var node := Node3D.new()
	_nodes.append(node)
	return node

func _wood() -> int:
	return ResourceManager.get_amount(ResourceManager.Type.WOOD)

func _proc(building_id: String, process_id: String) -> Dictionary:
	for p in ProcessManager.get_processes_for(building_id):
		if p["id"] == process_id:
			return p
	return {}

func test_batches_add_up_in_the_queue_and_are_paid_when_queued() -> void:
	var node := _node()
	ResourceManager.set_amounts({"wood": 400})
	var proc := _proc("nucleo", "wood_planks")
	var per: int = int(proc["cost"]["wood"])
	assert_bool(ProcessManager.enqueue_process(node, proc, 1)).is_true()
	assert_bool(ProcessManager.enqueue_process(node, proc, 1)).is_true()
	assert_bool(ProcessManager.enqueue_process(node, proc, 5)).is_true()
	assert_int(ProcessManager.get_batch_left(node)).is_equal(7)
	assert_int(_wood()).is_equal(400 - 7 * per)

func test_the_queue_never_goes_over_the_batch_max() -> void:
	var node := _node()
	ResourceManager.set_amounts({"wood": 99999})
	var proc := _proc("nucleo", "wood_planks")
	ProcessManager.enqueue_process(node, proc, GameConfig.process_batch_max - 2)
	ProcessManager.enqueue_process(node, proc, 5)
	assert_int(ProcessManager.get_batch_left(node)).is_equal(GameConfig.process_batch_max)
	assert_bool(ProcessManager.enqueue_process(node, proc, 1)).is_false()
	assert_int(ProcessManager.room_for(node, proc)).is_equal(0)

func test_another_process_is_not_queued_while_one_runs() -> void:
	var node := _node()
	ResourceManager.set_amounts({"wood": 400, "gold": 400})
	var procs: Array = ProcessManager.get_processes_for("nucleo")
	var first: Dictionary = procs[0]
	var other: Dictionary = {}
	for p in procs:
		if p["id"] != first["id"]:
			other = p
			break
	assert_bool(ProcessManager.enqueue_process(node, first, 1)).is_true()
	if other.is_empty():
		return
	assert_bool(ProcessManager.enqueue_process(node, other, 1)).is_false()
	assert_int(ProcessManager.room_for(node, other)).is_equal(0)

func test_removing_batches_not_started_refunds_them_in_full() -> void:
	var node := _node()
	# Bolsa con sitio: el reembolso se recorta al hueco libre.
	ResourceManager.set_amounts({"wood": 400, "gold": 0, "steel": 0, "oil": 0})
	var proc := _proc("nucleo", "wood_planks")
	var per: int = int(proc["cost"]["wood"])
	ProcessManager.enqueue_process(node, proc, 5)
	var before := _wood()
	ProcessManager.dequeue(node, 1)
	assert_int(ProcessManager.get_batch_left(node)).is_equal(4)
	assert_int(_wood()).is_equal(before + per)
	# Vaciar: solo lo que no ha empezado; la tanda de ahora sigue.
	ProcessManager.dequeue(node, ProcessManager.queued_not_started(node))
	assert_int(ProcessManager.get_batch_left(node)).is_equal(1)
	assert_int(_wood()).is_equal(400 - per)
	assert_bool(ProcessManager.is_busy(node)).is_true()

func test_a_queued_process_still_saves_as_one_entry_with_its_count() -> void:
	var node := _node()
	ResourceManager.set_amounts({"wood": 400})
	var proc := _proc("nucleo", "wood_planks")
	ProcessManager.enqueue_process(node, proc, 2)
	ProcessManager.enqueue_process(node, proc, 3)
	var info: Dictionary = ProcessManager.get_active(node)
	assert_int(int(info["count"])).is_equal(5)
	assert_int(int(info["total"])).is_equal(5)
