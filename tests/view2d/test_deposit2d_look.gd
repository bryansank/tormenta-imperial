extends GdUnitTestSuite
## Los yacimientos de la vista 2D en maqueta (BuildingArt2D.draw_deposit y
## Deposit2D): cada tipo, tamano y etapa se dibuja sin error; Deposit2D no
## gasta nada por fotograma salvo seleccionado; la etapa la pone
## MapGenerator2D al minar, con la misma regla que la 3D.

const Art := preload("res://scripts/view2d/BuildingArt2D.gd")
const Deposit2D := preload("res://scripts/view2d/Deposit2D.gd")
const MapGen2D := preload("res://scripts/view2d/MapGenerator2D.gd")
const DepositMesh := preload("res://scripts/map/DepositMesh.gd")

var _drawn := 0
var _canvas: Node2D = null
var _calls: Array = []

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

func test_every_type_size_and_stage_draws() -> void:
	var calls: Array = []
	for id in ["forest", "gold_vein", "iron_deposit", "oil_well"]:
		for size in [Vector2(64, 64), Vector2(96, 64), Vector2(64, 96), Vector2(128, 128)]:
			for stage in [4, 3, 2, 1]:
				var s: Vector2 = size
				var st: int = stage
				var i: String = id
				calls.append(func(ci): Art.draw_deposit(ci, i, s, 3, st))
	await _draw_on_canvas(calls)
	assert_int(_drawn).is_greater(0)

func test_deposit2d_idles_unless_selected() -> void:
	var dep: Node2D = auto_free(Deposit2D.new())
	dep.setup("forest", "Bosque", Vector2i(3, 3))
	add_child(dep)
	await get_tree().process_frame
	assert_bool(dep.is_processing()).is_false()
	dep.set_selected(true)
	assert_bool(dep.is_processing()).is_true()
	dep.set_selected(false)
	assert_bool(dep.is_processing()).is_false()

func test_mining_sets_the_stage_in_2d() -> void:
	GridManager.clear_all()
	GridManager.reset_size()
	var map: Node = auto_free(MapGen2D.new())
	add_child(map)
	var node: Node2D = map.spawn_deposit("gold_vein", Vector2i(6, 6), -1, Vector2i(2, 2))
	assert_int(int(node.get("stage"))).is_equal(4)
	for i in 5:
		map._on_mining_completed(node, "gold_vein")
	var expected := DepositMesh.stage_of(int(node.get_meta("uses_remaining")), int(node.get_meta("max_uses")))
	assert_int(int(node.get("stage"))).is_equal(expected)
	assert_int(expected).is_less(4)
	map.clear_all_deposits()
	GridManager.clear_all()
