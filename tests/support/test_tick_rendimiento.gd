extends GdUnitTestSuite
## Rendimiento "en una papa" (2026-10-26, QA de tablet): ProductionManager y
## ContractManager trabajan por tic, no por fotograma; en la vista 2D un reloj
## unico (Building2DClock) revisa los edificios y los badges no tienen _process.

const SawmillData := preload("res://data/buildings/sawmill.tres")
const Building2D := preload("res://scripts/view2d/Building2D.gd")
const Clock := preload("res://scripts/view2d/Building2DClock.gd")

var _nodes: Array = []

func before_test() -> void:
	GameConfig.set_game_speed(1.0)
	ProductionManager._tick_acc = 0.0
	_nodes = []

func after_test() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			ProductionManager.unregister(n)
			n.free()
	ProductionManager._tick_acc = 0.0

func _node() -> Node3D:
	var n := Node3D.new()
	add_child(n)
	_nodes.append(n)
	return n

func test_production_manager_waits_for_a_whole_tick_and_loses_no_time() -> void:
	var n := _node()
	n.add_child(MeshInstance3D.new())
	ProductionManager.register_building(n, SawmillData, 30.0)
	var start := ProductionManager.get_construction_remaining(n)
	ProductionManager._process(ProductionManager.TICK_SECONDS * 0.5)
	# Medio tic: aun no se ha tocado.
	assert_float(ProductionManager.get_construction_remaining(n)).is_equal(start)
	ProductionManager._process(ProductionManager.TICK_SECONDS * 0.6)
	# El tic entero lleva los dos trozos: no se pierde tiempo.
	assert_float(start - ProductionManager.get_construction_remaining(n)) \
		.is_equal_approx(ProductionManager.TICK_SECONDS * 1.1, 0.0001)

func test_contract_manager_advances_by_tick() -> void:
	ContractManager._tick_acc = 0.0
	ContractManager._process(ContractManager.TICK_SECONDS * 0.4)
	assert_float(ContractManager._tick_acc).is_equal_approx(ContractManager.TICK_SECONDS * 0.4, 0.0001)
	ContractManager._process(ContractManager.TICK_SECONDS * 0.7)
	assert_float(ContractManager._tick_acc).is_equal(0.0)

func test_a_2d_building_at_rest_has_no_process_of_its_own() -> void:
	var b: Node2D = Building2D.new()
	b.setup(load("res://data/buildings/house.tres"))
	add_child(b)
	_nodes.append(b)
	for i in Building2D.BOOT_FRAMES + 3:
		await get_tree().process_frame
	assert_bool(b.is_processing()).is_false()
	var badge: Node = b.get_node("StatusBadge")
	assert_bool(badge.is_processing()).is_false()
	# Lo revisa el reloj unico.
	assert_bool(is_instance_valid(Clock._instance)).is_true()
	assert_bool(Clock._instance.is_inside_tree()).is_true()
	assert_bool((Clock._instance._buckets[b._slot % Clock.CHECK_FRAMES] as Array).has(b)).is_true()
	# Seleccionado pulsa cada fotograma; al soltarlo se apaga solo.
	b.set_selected(true)
	assert_bool(b.is_processing()).is_true()
	b.set_selected(false)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(b.is_processing()).is_false()
	# Al salir del arbol se da de baja.
	remove_child(b)
	assert_bool((Clock._instance._buckets[b._slot % Clock.CHECK_FRAMES] as Array).has(b)).is_false()

func test_the_clock_and_the_building_agree_on_the_bucket_count() -> void:
	assert_int(Clock.CHECK_FRAMES).is_equal(Building2D.CHECK_FRAMES)
