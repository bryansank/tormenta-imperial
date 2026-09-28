extends GdUnitTestSuite
## Estado del edificio a la vista (A11): Zzz si esta parado, un obrero si
## trabaja. Generaliza el cartel rojo de "sin trabajadores" que pintaba
## PopulationManager.
##
## Dos capas: `derive()` es pura (hechos -> estado) y se fija con diccionarios;
## el badge real escucha EventBus y relee la meta del edificio. Las senales se
## emiten a mano sobre el EventBus real: monitor_signals() libera lo vigilado y
## sobre un autoload seria una catastrofe.

const Badge := preload("res://scripts/buildings/BuildingStatusBadge.gd")

var _building: Node3D = null
var _badge: Label3D = null
var _data: BuildingData = null

func before_test() -> void:
	_data = BuildingData.new()
	_data.id = "sawmill"
	_data.produces_wood = 6
	_data.workers_required = 2
	_data.mesh_height = 1.8
	_building = auto_free(Node3D.new())
	add_child(_building)
	_badge = Badge.new()
	_building.add_child(_badge)
	_badge.setup(_building, _data, 1.8)

func _facts(overrides: Dictionary = {}) -> Dictionary:
	var f := {
		"can_work": true, "under_construction": false, "ruined": false,
		"busy": false, "needs_workers": true, "staffed": true, "produces": true,
	}
	f.merge(overrides, true)
	return f

# ── La regla pura ────────────────────────────────────────────────────

func test_a_staffed_producer_is_working() -> void:
	assert_int(Badge.derive(_facts())["status"]).is_equal(Badge.Status.WORKING)

func test_without_workers_it_sleeps_and_says_why() -> void:
	var v: Dictionary = Badge.derive(_facts({"staffed": false}))
	assert_int(v["status"]).is_equal(Badge.Status.IDLE)
	assert_str(v["reason"]).is_equal("unstaffed")

func test_under_construction_it_sleeps_even_if_staffed() -> void:
	var v: Dictionary = Badge.derive(_facts({"under_construction": true}))
	assert_int(v["status"]).is_equal(Badge.Status.IDLE)
	assert_str(v["reason"]).is_equal("construction")

func test_in_ruins_it_sleeps_even_with_a_process_queued() -> void:
	var v: Dictionary = Badge.derive(_facts({"ruined": true, "busy": true}))
	assert_int(v["status"]).is_equal(Badge.Status.IDLE)
	assert_str(v["reason"]).is_equal("ruined")

func test_a_running_process_is_work_even_without_passive_production() -> void:
	# El Nucleo fabricando: no produce pasivamente ni tiene dotacion, pero trabaja.
	var v: Dictionary = Badge.derive(_facts({"produces": false, "needs_workers": false, "busy": true}))
	assert_int(v["status"]).is_equal(Badge.Status.WORKING)

func test_a_manual_only_building_with_nothing_running_sleeps() -> void:
	var v: Dictionary = Badge.derive(_facts({"produces": false, "needs_workers": false}))
	assert_int(v["status"]).is_equal(Badge.Status.IDLE)
	assert_str(v["reason"]).is_equal("idle")

func test_a_building_that_cannot_work_has_no_badge() -> void:
	assert_int(Badge.derive(_facts({"can_work": false}))["status"]).is_equal(Badge.Status.NONE)

func test_houses_and_decorations_cannot_work_but_the_nucleo_can() -> void:
	var house: BuildingData = load("res://data/buildings/house.tres")
	var garden: BuildingData = load("res://data/buildings/garden.tres")
	var road: BuildingData = load("res://data/buildings/road.tres")
	var nucleo: BuildingData = load("res://data/buildings/nucleo.tres")
	var warehouse: BuildingData = load("res://data/buildings/warehouse.tres")
	assert_bool(Badge.can_work(house)).is_false()
	assert_bool(Badge.can_work(garden)).is_false()
	assert_bool(Badge.can_work(road)).is_false()
	assert_bool(Badge.can_work(nucleo)).is_true()      # procesos manuales
	assert_bool(Badge.can_work(warehouse)).is_true()   # necesita dotacion
	assert_bool(Badge.can_work(null)).is_false()

# ── El badge real, movido por senales ────────────────────────────────

func test_it_starts_asleep_without_workers_in_the_old_red() -> void:
	assert_int(_badge.get_status()).is_equal(Badge.Status.IDLE)
	assert_str(_badge.get_reason()).is_equal("unstaffed")
	assert_bool(_badge.visible).is_true()
	assert_str(_badge.text).is_equal(Tr.t("LBL_STATUS_IDLE"))
	assert_that(_badge.modulate).is_equal(Badge.COLOR_UNSTAFFED)

func test_workers_changed_makes_it_reread_the_staffing() -> void:
	_building.set_meta("staffed", true)
	EventBus.workers_changed.emit(2, 5)
	assert_int(_badge.get_status()).is_equal(Badge.Status.WORKING)
	assert_str(_badge.text).is_equal("")
	assert_bool(_badge.get_node("WorkerIcon").visible).is_true()

func test_construction_started_and_completed_flip_it() -> void:
	_building.set_meta("staffed", true)
	_building.set_meta("under_construction", true)
	EventBus.construction_started.emit(_building)
	assert_str(_badge.get_reason()).is_equal("construction")
	assert_that(_badge.modulate).is_equal(Badge.COLOR_CONSTRUCTION)
	_building.remove_meta("under_construction")
	EventBus.construction_completed.emit(_building)
	assert_int(_badge.get_status()).is_equal(Badge.Status.WORKING)

func test_ruined_and_repaired_flip_it() -> void:
	_building.set_meta("staffed", true)
	_building.set_meta("health", 0)
	EventBus.building_ruined.emit(_building)
	assert_str(_badge.get_reason()).is_equal("ruined")
	_building.set_meta("health", 100)
	EventBus.building_repaired.emit(_building)
	assert_int(_badge.get_status()).is_equal(Badge.Status.WORKING)

func test_a_process_wakes_it_and_its_end_puts_it_back_to_sleep() -> void:
	# Sin dotacion dormiria; un proceso en marcha lo pone a trabajar igual.
	EventBus.process_started.emit(_building, "make_planks")
	assert_int(_badge.get_status()).is_equal(Badge.Status.WORKING)
	EventBus.process_completed.emit(_building, "make_planks")
	assert_int(_badge.get_status()).is_equal(Badge.Status.IDLE)
	EventBus.process_started.emit(_building, "make_planks")
	EventBus.process_cancelled.emit(_building, "make_planks", {})
	assert_int(_badge.get_status()).is_equal(Badge.Status.IDLE)

func test_mining_signals_count_as_a_process_too() -> void:
	EventBus.mining_started.emit(_building, "forest")
	assert_int(_badge.get_status()).is_equal(Badge.Status.WORKING)
	EventBus.mining_completed.emit(_building, "forest")
	assert_int(_badge.get_status()).is_equal(Badge.Status.IDLE)

func test_signals_about_other_buildings_are_ignored() -> void:
	var other: Node3D = auto_free(Node3D.new())
	add_child(other)
	EventBus.process_started.emit(other, "x")
	assert_int(_badge.get_status()).is_equal(Badge.Status.IDLE)

func test_a_production_tick_refreshes_without_changing_a_working_state() -> void:
	_building.set_meta("staffed", true)
	EventBus.production_tick.emit(_building)
	assert_int(_badge.get_status()).is_equal(Badge.Status.WORKING)

func test_a_building_with_nothing_to_do_hides_its_badge() -> void:
	var house: BuildingData = load("res://data/buildings/house.tres")
	var home: Node3D = auto_free(Node3D.new())
	add_child(home)
	var badge: Label3D = Badge.new()
	home.add_child(badge)
	badge.setup(home, house, 1.0)
	assert_int(badge.get_status()).is_equal(Badge.Status.NONE)
	assert_bool(badge.visible).is_false()

func test_it_floats_above_the_top_it_was_given() -> void:
	assert_float(_badge.position.y).is_equal_approx(1.8 + Badge.HEIGHT_MARGIN, 0.001)

func test_measure_top_sees_through_scale_and_ignores_labels() -> void:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1, 2, 1)
	mi.mesh = box
	mi.position.y = 1.0      # top at 2.0
	root.add_child(mi)
	root.scale = Vector3(1, 2.4, 1)
	var wrapper := Node3D.new()
	wrapper.add_child(root)
	var label := Label3D.new()
	label.position.y = 50.0  # rotulos no cuentan
	wrapper.add_child(label)
	assert_float(Badge.measure_top(wrapper)).is_equal_approx(4.8, 0.001)
	wrapper.free()

func test_the_worker_icon_is_a_real_drawn_texture() -> void:
	var tex: Texture2D = Badge.worker_texture()
	assert_object(tex).is_not_null()
	assert_int(tex.get_width()).is_equal(Badge.ICON_TEXTURE_SIZE)
	var img: Image = tex.get_image()
	var opaque := 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			if img.get_pixel(x, y).a > 0.5:
				opaque += 1
	assert_int(opaque).is_greater(100)
