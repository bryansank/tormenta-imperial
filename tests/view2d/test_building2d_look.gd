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
	ProductionManager.set_process(true)
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
		func(ci): Art.draw_damage(ci, Vector2(64, 64), 0.2, false, 5, 2),
		func(ci): Art.draw_damage(ci, Vector2(64, 64), 0.9, false, 5, 2),
		func(ci): Art.draw_damage_marks(ci, Vector2(96, 96), LookRule.DAMAGE_HEAVY, 4, 3),
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

## Building2D mira su estado cada CHECK_FRAMES fotogramas (repartidos entre
## edificios): se espera algo mas que eso.
func _settle() -> void:
	for i in Building2D.CHECK_FRAMES + 2:
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

# ── Obra por edificio y por instancia ────────────────────────────────

const ALL_IDS := ["nucleo", "house", "sawmill", "gold_mine", "warehouse", "foundry", "barracks",
	"refinery", "tower", "headquarters", "market", "laboratory", "garden", "fountain", "statue", "road"]

func test_every_building_draws_its_three_phases_with_two_seeds() -> void:
	var calls: Array = []
	for id in ALL_IDS:
		var data: BuildingData = load("res://data/buildings/%s.tres" % id)
		var n := LookRule.footprint_class(data.grid_size)
		var size: Vector2 = Vector2(data.grid_size) * 32.0
		for phase in 3:
			for seed_val in [LookRule.site_seed(id, Vector2i(4, 4)), LookRule.site_seed(id, Vector2i(6, 4))]:
				calls.append(func(ci): Art.draw_construction_phase(ci, size, phase, 0.5, n, id, seed_val))
	await _draw_on_canvas(calls)
	assert_int(_drawn).is_greater(0)

func test_anchors_follow_the_instance() -> void:
	var style := LookRule.site_style("foundry")
	var a := LookRule.site_layout(LookRule.site_seed("foundry", Vector2i(4, 4)), style, 2)
	var b := LookRule.site_layout(LookRule.site_seed("foundry", Vector2i(6, 4)), style, 2)
	var size := Vector2(64, 64)
	assert_dict(Art.site_anchors(size, 2, 2, style, a)).is_equal(Art.site_anchors(size, 2, 2, style, a))
	assert_dict(Art.site_anchors(size, 2, 2, style, a)).is_not_equal(Art.site_anchors(size, 2, 2, style, b))
	# Grua solo con estructura y desde 2x2; chispas solo cuando ya hay acero.
	assert_dict(Art.site_anchors(size, 2, 2, style, a)["crane"]).is_not_empty()
	assert_dict(Art.site_anchors(size, 1, 2, style, a)["crane"]).is_empty()
	assert_dict(Art.site_anchors(Vector2(32, 32), 2, 1, style, a)["crane"]).is_empty()
	assert_str(String(Art.site_anchors(size, 0, 2, style, a)["fx_kind"])).is_empty()
	assert_str(String(Art.site_anchors(size, 2, 2, style, a)["fx_kind"])).is_equal("sparks")

func _spawn_building(id: String, done: float) -> Node2D:
	var data: BuildingData = load("res://data/buildings/%s.tres" % id)
	var b: Node2D = Building2D.new()
	b.setup(data)
	add_child(b)
	var total := GameConfig.get_build_time(maxf(1.0, data.build_time))
	ProductionManager.register_building(b, data, total * (1.0 - done))
	# En modo dev la obra dura 2 s: con el 10 % que queda, los fotogramas de
	# _settle() la podian terminar (segun lo rapido que fuera la maquina). El
	# reloj de la obra se para; after_test() lo vuelve a poner.
	ProductionManager.set_process(false)
	return b

func test_a_site_in_frame_phase_animates_crane_and_flag() -> void:
	var b := _spawn_building("foundry", 0.9)
	await _settle()
	assert_int(b.get_look()["phase"]).is_equal(LookRule.PHASE_FRAME)
	var fx: Node2D = b.get_site_fx()
	assert_object(fx).is_not_null()
	var jib: Line2D = fx.get_node("CraneJib")
	assert_bool(jib.material is ShaderMaterial).is_true()
	assert_object(fx.get_node_or_null("SiteFlag")).is_not_null()
	assert_object(fx.get_node_or_null("Fx_sparks")).is_not_null()
	# Sin _process por la animacion: lo mueve el shader.
	assert_array(fx.find_children("*", "Timer", true, false)).is_empty()
	assert_array(fx.find_children("*", "AnimationPlayer", true, false)).is_empty()
	# Al terminar la obra, las piezas se van.
	ProductionManager.unregister(b)
	b.remove_meta("under_construction")
	await _settle()
	assert_object(b.get_site_fx()).is_null()
	b.queue_free()

func test_two_sites_of_the_same_building_get_their_own_seed() -> void:
	var a := _spawn_building("house", 0.1)
	var b := _spawn_building("house", 0.1)
	a.position = Vector2(100, 100)
	b.position = Vector2(164, 100)
	await _settle()
	assert_int(a.get_site_seed()).is_not_equal(b.get_site_seed())
	assert_int(a.get_site_seed()).is_equal(LookRule.seed_of(a, a.data))
	# Estable entre frames: no se rehace sola.
	var site: Node2D = a.get_site_fx()
	await _settle()
	assert_object(a.get_site_fx()).is_same(site)
	for n in [a, b]:
		ProductionManager.unregister(n)
		n.queue_free()
