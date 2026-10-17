extends GdUnitTestSuite
## La parcela en la vista 2D (docs/18, "Como se pinta un edificio"): el mismo
## plan que la 3D (LotPlan) dibujado por BuildingArt2D. Los 24 edificios se
## pintan sin error en pie, en obra y en ruina, y el edificio deja libre su patio.

const Building2D := preload("res://scripts/view2d/Building2D.gd")
const Art := preload("res://scripts/view2d/BuildingArt2D.gd")
const Plan := preload("res://scripts/buildings/LotPlan.gd")
const View2D := preload("res://scripts/view2d/View2D.gd")

var _canvas: Node2D = null
var _calls: Array = []
var _drawn := 0

func after_test() -> void:
	if is_instance_valid(_canvas):
		_canvas.queue_free()
	_canvas = null

func _draw_on_canvas(calls: Array) -> void:
	_calls = calls
	_drawn = 0
	_canvas = Node2D.new()
	_canvas.draw.connect(func():
		for c in _calls:
			(c as Callable).call(_canvas)
		_drawn += 1)
	add_child(_canvas)
	_canvas.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame

## Building2D mira su estado cada CHECK_FRAMES fotogramas (repartidos entre
## edificios): se espera algo mas que eso.
func _settle() -> void:
	for i in Building2D.CHECK_FRAMES + 2:
		await get_tree().process_frame

func test_every_lot_draws_in_every_state() -> void:
	var calls: Array = []
	for d in BuildingData.load_all():
		var data := d as BuildingData
		var size := Vector2(data.grid_size) * View2D.cell_px()
		for state in ["idle", "construction", "ruin"]:
			var plan := Plan.plan(data.id, data.grid_size, Plan.seed_for(Vector2i(4, 6), data.id), Plan.SIDE_S, state, 1)
			if plan.is_empty():
				assert_str(data.id).is_equal("road")
				continue
			calls.append(func(ci): Art.draw_lot_ground(ci, plan, size))
			calls.append(func(ci): Art.draw_lot_props(ci, plan, size))
		calls.append(func(ci): Art.draw_building(ci, data.id, size, {"inset": Plan.yard_of(data.id) * View2D.cell_px()}))
	await _draw_on_canvas(calls)
	assert_int(_drawn).is_greater(0)

func test_every_building2d_paints_with_its_lot() -> void:
	var nodes: Array = []
	for d in BuildingData.load_all():
		var b: Node2D = Building2D.new()
		b.setup(d)
		add_child(b)
		nodes.append(b)
	await get_tree().process_frame
	await get_tree().process_frame
	for b in nodes:
		var id: String = b.data.id
		if id == "road":
			assert_bool(b.get_lot_plan().is_empty()).is_true()
		else:
			assert_bool(b.get_lot_plan().is_empty()).override_failure_message(id).is_false()
			assert_float(b.yard_px()).is_greater(0.0)
		b.queue_free()

func test_ruin_and_construction_change_the_2d_lot() -> void:
	var data: BuildingData = load("res://data/buildings/warehouse.tres")
	var b: Node2D = Building2D.new()
	b.setup(data)
	add_child(b)
	await get_tree().process_frame
	assert_str(String(b.get_lot_plan()["state"])).is_equal("idle")
	b.set_meta("health", 0)
	await _settle()
	assert_str(String(b.get_lot_plan()["state"])).is_equal("ruin")
	b.remove_meta("health")
	ProductionManager.register_building(b, data, GameConfig.get_build_time(data.build_time) * 0.5)
	await _settle()
	assert_str(String(b.get_lot_plan()["state"])).is_equal("construction")
	ProductionManager.unregister(b)
	b.remove_meta("under_construction")
	b.queue_free()

func test_sawmill_dust_sits_on_the_saw_blade() -> void:
	# El serrin sale de la sierra: el ancla del dibujo es la hoja, dentro del
	# rectangulo del edificio (la huella menos el patio).
	var anchors := Art.fx_anchors("sawmill")
	assert_int(anchors.size()).is_equal(1)
	assert_vector(anchors[0] as Vector2).is_equal(Vector2(0.5, 0.63))
