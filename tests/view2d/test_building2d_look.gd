extends GdUnitTestSuite
## El aspecto de los edificios en la vista 2D (docs/18): las tres fases de obra
## por huella, la ruina y la animacion de "trabajando". Building2D sigue la
## misma regla que la 3D (BuildingLook) y BuildingArt2D dibuja cada estado sin
## error.

const Building2D := preload("res://scripts/view2d/Building2D.gd")
const Art := preload("res://scripts/view2d/BuildingArt2D.gd")
const LookRule := preload("res://scripts/buildings/BuildingLook.gd")

var _drawn := 0
var _canvas: Node2D = null
var _calls: Array = []

func after_test() -> void:
	if is_instance_valid(_canvas):
		_canvas.queue_free()
	_canvas = null

## Un lienzo en el arbol que ejecuta `_calls` en su _draw y cuenta las pasadas.
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

func test_every_phase_draws_for_every_footprint() -> void:
	var calls: Array = []
	for n in [1, 2, 3]:
		for phase in 3:
			var size: Vector2 = Vector2(32, 32) * n
			calls.append(func(ci): Art.draw_construction_phase(ci, size, phase, 0.5, n))
	await _draw_on_canvas(calls)
	assert_int(_drawn).is_greater(0)

func test_ruin_and_damage_draw() -> void:
	await _draw_on_canvas([
		func(ci): Art.draw_ruin(ci, Vector2(64, 64), 3, 2),
		func(ci): Art.draw_ruin(ci, Vector2(96, 96), 9, 3),
		func(ci): Art.draw_damage(ci, Vector2(64, 64), 0.0, true, 5, 2),
		func(ci): Art.draw_damage(ci, Vector2(64, 64), 0.5, false, 5, 2),
	])
	assert_int(_drawn).is_greater(0)

func test_every_effect_building_has_anchors_inside_its_footprint() -> void:
	for id in GameConfig.building_active_fx:
		for a in Art.fx_anchors(id):
			assert_bool(Rect2(0, 0, 1, 1).has_point(a)).is_true()

# ── Building2D ───────────────────────────────────────────────────────

func _spawn(id: String) -> Node2D:
	var b: Node2D = Building2D.new()
	b.setup(load("res://data/buildings/%s.tres" % id))
	add_child(b)
	return b

func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func test_construction_shows_the_phase_of_its_progress() -> void:
	var data: BuildingData = load("res://data/buildings/foundry.tres")
	var b: Node2D = Building2D.new()
	b.setup(data)
	add_child(b)
	# 10 % hecho: fase de valla.
	ProductionManager.register_building(b, data, GameConfig.get_build_time(data.build_time) * 0.9)
	await _settle()
	assert_int(b.get_look()["look"]).is_equal(LookRule.Look.CONSTRUCTION)
	assert_int(b.get_look()["phase"]).is_equal(LookRule.PHASE_FENCE)
	ProductionManager.unregister(b)
	b.remove_meta("under_construction")
	await _settle()
	assert_int(b.get_look()["look"]).is_not_equal(LookRule.Look.CONSTRUCTION)
	b.queue_free()

func test_ruin_shows_black_smoke_and_repair_hides_it() -> void:
	var b := _spawn("barracks")
	b.set_meta("health", 0)
	await _settle()
	assert_int(b.get_look()["look"]).is_equal(LookRule.Look.RUIN)
	assert_object(b.get_ruin_fx()).is_not_null()
	assert_bool(b.get_ruin_fx().visible).is_true()
	b.remove_meta("health")
	await _settle()
	assert_bool(b.get_ruin_fx().visible).is_false()
	b.queue_free()

func test_a_working_producer_smokes_and_a_stopped_one_does_not() -> void:
	var b := _spawn("foundry")
	# Dos chimeneas en el dibujo: dos columnas de humo.
	b.set_meta("staffed", true)
	b.get_node("StatusBadge").refresh()
	await _settle()
	assert_int(b.get_look()["look"]).is_equal(LookRule.Look.ACTIVE)
	assert_object(b.get_active_fx()).is_not_null()
	assert_int(b.get_active_fx().get_child_count()).is_equal(2)
	assert_bool(b.get_active_fx().visible).is_true()
	b.set_meta("staffed", false)
	b.get_node("StatusBadge").refresh()
	await _settle()
	assert_bool(b.get_active_fx().visible).is_false()
	b.queue_free()

func test_a_house_never_animates() -> void:
	var b := _spawn("house")
	await _settle()
	assert_int(b.get_look()["look"]).is_equal(LookRule.Look.IDLE)
	assert_object(b.get_active_fx()).is_null()
	b.queue_free()
