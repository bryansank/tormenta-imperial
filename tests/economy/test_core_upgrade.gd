extends GdUnitTestSuite
## Subir el Nucleo (1.2, feat/nucleo-y-planos): lo que pide cada nivel, lo que
## cuesta, la obra (que no para el Nucleo), lo que dice la ficha, el guardado
## (idempotente, con la obra a medias), los guardados viejos (nivel derivado de
## la era y los edificios), el reset y ¿QUE HACER? cuando un tope frena.
## Sin escena: GridManager con nodos sueltos y el estado de los autoloads se
## deja como estaba en after_test(). No escribe user://.
##
## Escrito sin ejecutar (regla de Bryan: un solo pase de pruebas al final).

const CoreLevel := preload("res://scripts/services/CoreLevel.gd")
const CoreTrim := preload("res://scripts/buildings/CoreTrim.gd")
const Rules := preload("res://scripts/buildings/PlacementRules.gd")
const Objectives := preload("res://scripts/services/Objectives.gd")
const InfoPanel := preload("res://scripts/ui/BuildingInfoPanel.gd")

var _saved: Dictionary = {}
var _requirements: Dictionary = {}
var _nodes: Array = []
var _next := 0

func before_test() -> void:
	_saved = {
		"progression": ProgressionManager.get_save_data(),
		"resources": ResourceManager.get_all(),
		"unlock": ResourceManager.get_unlock_state(),
		"mode": GameMode.current,
	}
	_requirements = GameConfig.core_level_requirements.duplicate(true)
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	GridManager.clear_all()
	ProgressionManager.reset()
	_nodes.clear()
	_next = 0

func after_test() -> void:
	GridManager.clear_all()
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	GameConfig.core_level_requirements = _requirements
	GameMode.current = _saved["mode"]
	ProgressionManager.load_save_data(_saved["progression"])
	ResourceManager.set_unlock_state(_saved["unlock"])
	var amounts := {}
	for type in _saved["resources"]:
		amounts[ResourceManager.get_type_name(type)] = _saved["resources"][type]
	ResourceManager.set_amounts(amounts)

func _place(id: String) -> Node3D:
	var data: BuildingData = Rules.load_building_data(id)
	var node := Node3D.new()
	node.set_meta("level", 1)
	var origin := Vector2i((_next % 8) * 5 + 1, (_next / 8) * 5 + 1)
	_next += 1
	assert_bool(GridManager.place_building(origin, data, node)).is_true()
	_nodes.append(node)
	return node

## Lo justo para pagar `to_level`, nada mas.
func _give_cost(to_level: int) -> void:
	var amounts := {}
	for t in ResourceManager.get_all():
		amounts[ResourceManager.get_type_name(t)] = 0
	var cost: Dictionary = GameConfig.get_core_upgrade_cost(to_level)
	for type in cost:
		ResourceManager.unlock(type)
		amounts[ResourceManager.get_type_name(type)] = int(cost[type])
	ResourceManager.set_amounts(amounts)

# ── La tabla ─────────────────────────────────────────────────────────

func test_every_level_above_one_has_cost_time_and_requirements() -> void:
	for lv in range(2, GameConfig.core_level_max + 1):
		assert_bool(GameConfig.core_level_costs.has(lv)).override_failure_message(str(lv)).is_true()
		assert_bool(GameConfig.core_level_durations.has(lv)).override_failure_message(str(lv)).is_true()
		assert_bool(GameConfig.core_level_requirements.has(lv)).override_failure_message(str(lv)).is_true()
		for res in GameConfig.core_level_costs[lv]:
			assert_int(ResourceManager.name_to_type(String(res))).override_failure_message(String(res)).is_not_equal(-1)

func test_the_requirements_follow_the_eras() -> void:
	assert_int(int(GameConfig.core_level_requirements[2]["era"])).is_equal(1)
	assert_int(int(GameConfig.core_level_requirements[3]["era"])).is_equal(2)
	assert_int(int(GameConfig.core_level_requirements[4]["era"])).is_equal(3)
	assert_int(int(GameConfig.core_level_requirements[5]["era"])).is_equal(3)

func test_the_bag_part_of_each_level_fits_its_era() -> void:
	# N2 en la bolsa de la era 1 con 3 almacenes; N3 era 2 con 5; N4-N5 era 3 con 5.
	var fits := {2: GameConfig.get_storage_cap(3, 1), 3: GameConfig.get_storage_cap(5, 2),
		4: GameConfig.get_storage_cap(5, 3), 5: GameConfig.get_storage_cap(5, 3)}
	for lv in fits:
		var bag := 0
		var cost: Dictionary = GameConfig.get_core_upgrade_cost(lv)
		for type in cost:
			if not ResourceManager.is_material(type):
				bag += int(cost[type])
		assert_int(bag).override_failure_message("Nucleo %d: %d en la bolsa" % [lv, bag]).is_less_equal(int(fits[lv]))

func test_levels_four_and_five_ask_for_parts() -> void:
	assert_int(int(GameConfig.get_core_upgrade_cost(4).get(ResourceManager.Type.PARTS, 0))).is_greater(0)
	assert_int(int(GameConfig.get_core_upgrade_cost(5).get(ResourceManager.Type.PARTS, 0))).is_greater(0)

# ── Requisitos ───────────────────────────────────────────────────────

func test_level_two_waits_for_the_first_era_buildings() -> void:
	assert_bool(CoreLevel.requirements_met(2)).is_false()
	assert_bool(CoreLevel.can_start()).is_false()
	for id in ["sawmill", "gold_mine", "house", "warehouse"]:
		_place(id)
	assert_bool(CoreLevel.requirements_met(2)).is_true()

func test_level_three_waits_for_era_two() -> void:
	ProgressionManager.core_level = 2
	_place("barracks")
	ProgressionManager.current_era = 1
	assert_bool(CoreLevel.requirements_met(3)).is_false()
	ProgressionManager.current_era = 2
	assert_bool(CoreLevel.requirements_met(3)).is_true()

# ── La obra ──────────────────────────────────────────────────────────

func test_starting_charges_and_finishing_raises_the_level() -> void:
	GameConfig.core_level_requirements[2] = {"era": 1, "buildings": []}
	_give_cost(2)
	assert_bool(CoreLevel.can_start()).is_true()
	assert_bool(ProgressionManager.start_core_upgrade()).is_true()
	assert_bool(ProgressionManager.is_core_upgrading()).is_true()
	assert_int(ProgressionManager.core_upgrade_target()).is_equal(2)
	assert_int(ProgressionManager.core_level).is_equal(1)
	assert_int(ResourceManager.get_amount(ResourceManager.Type.GOLD)).is_equal(0)
	# Un segundo toque no cobra otra vez.
	assert_bool(ProgressionManager.start_core_upgrade()).is_false()
	ProgressionManager._tick_core_upgrade(GameConfig.get_core_upgrade_duration(2) + 1.0)
	assert_bool(ProgressionManager.is_core_upgrading()).is_false()
	assert_int(ProgressionManager.core_level).is_equal(2)
	assert_int(GameConfig.current_core_level()).is_equal(2)

func test_without_the_price_nothing_is_charged() -> void:
	GameConfig.core_level_requirements[2] = {"era": 1, "buildings": []}
	_give_cost(2)
	ResourceManager.set_amounts({"gold": 0})
	assert_bool(ProgressionManager.start_core_upgrade()).is_false()
	assert_bool(ProgressionManager.is_core_upgrading()).is_false()
	assert_int(ResourceManager.get_amount(ResourceManager.Type.WOOD)).is_greater(0)

func test_the_core_node_carries_the_level() -> void:
	var core := _place("nucleo")
	GameConfig.core_level_requirements[2] = {"era": 1, "buildings": []}
	_give_cost(2)
	ProgressionManager.start_core_upgrade()
	ProgressionManager._tick_core_upgrade(9999.0)
	assert_int(int(core.get_meta("level", 1))).is_equal(2)

func test_offline_time_counts_for_the_work() -> void:
	GameConfig.core_level_requirements[2] = {"era": 1, "buildings": []}
	_give_cost(2)
	ProgressionManager.start_core_upgrade()
	ProgressionManager.apply_offline_core(GameConfig.max_offline_seconds)
	assert_int(ProgressionManager.core_level).is_equal(2)

func test_the_top_level_does_not_go_further() -> void:
	ProgressionManager.core_level = GameConfig.core_level_max
	assert_bool(CoreLevel.is_max()).is_true()
	assert_array(CoreLevel.block_lines()).is_equal([Tr.t("CORE_MAX")])
	assert_bool(ProgressionManager.start_core_upgrade()).is_false()

# ── Guardado ─────────────────────────────────────────────────────────

func test_the_save_keeps_level_and_work_and_loads_twice_the_same() -> void:
	GameConfig.core_level_requirements[2] = {"era": 1, "buildings": []}
	_give_cost(2)
	ProgressionManager.start_core_upgrade()
	ProgressionManager._tick_core_upgrade(1.0)
	var data: Dictionary = ProgressionManager.get_save_data()
	assert_int(int(data["core"]["level"])).is_equal(1)
	assert_int(int(data["core"]["upgrade"]["to"])).is_equal(2)
	var left: float = ProgressionManager.core_upgrade_remaining()
	ProgressionManager.reset()
	ProgressionManager.load_save_data(data)
	ProgressionManager.load_save_data(data)
	assert_int(ProgressionManager.core_level).is_equal(1)
	assert_int(ProgressionManager.core_upgrade_target()).is_equal(2)
	assert_float(ProgressionManager.core_upgrade_remaining()).is_equal_approx(left, 0.01)

func test_an_old_save_derives_the_level_from_era_and_buildings() -> void:
	# Sin la clave "core": era 1 sin nada = 1; con la base de la era 1 = 2;
	# era 3 = 4 (los topes de la era 3 de antes); nunca el 5.
	var old: Dictionary = ProgressionManager.get_save_data()
	old.erase("core")
	old["current_era"] = 1
	ProgressionManager.load_save_data(old)
	assert_int(ProgressionManager.core_level).is_equal(1)
	for id in ["sawmill", "gold_mine", "house", "warehouse"]:
		_place(id)
	ProgressionManager.load_save_data(old)
	assert_int(ProgressionManager.core_level).is_equal(2)
	_place("barracks")
	_place("headquarters")
	old["current_era"] = 3
	ProgressionManager.load_save_data(old)
	assert_int(ProgressionManager.core_level).is_equal(4)

func test_a_bad_saved_level_is_clamped() -> void:
	var data: Dictionary = ProgressionManager.get_save_data()
	data["core"] = {"level": 99, "upgrade": {"to": 120, "remaining": -5.0, "duration": 10.0}}
	ProgressionManager.load_save_data(data)
	assert_int(ProgressionManager.core_level).is_equal(GameConfig.core_level_max)
	assert_bool(ProgressionManager.is_core_upgrading()).is_false()

func test_reset_throws_the_work_away_and_gives_nothing_back() -> void:
	GameConfig.core_level_requirements[2] = {"era": 1, "buildings": []}
	_give_cost(2)
	ProgressionManager.start_core_upgrade()
	ProgressionManager.reset()
	assert_int(ProgressionManager.core_level).is_equal(1)
	assert_bool(ProgressionManager.is_core_upgrading()).is_false()
	assert_int(ResourceManager.get_amount(ResourceManager.Type.GOLD)).is_equal(0)

func test_sandbox_starts_at_the_top_level() -> void:
	GameMode.begin_run(GameMode.Mode.SANDBOX)
	ProgressionManager.reset()
	assert_int(ProgressionManager.core_level).is_equal(GameConfig.core_level_max)

# ── Lo que dice la ficha ─────────────────────────────────────────────

func test_the_gains_list_the_caps_that_rise_and_what_opens() -> void:
	var lines: Array = CoreLevel.gains_lines(2)
	var saw: BuildingData = Rules.load_building_data("sawmill")
	assert_array(lines).contains([Tr.t("CORE_GAIN_LIMIT") % [saw.get_display_name(),
		GameConfig.base_building_limit("sawmill", 2), GameConfig.base_building_limit("sawmill", 1)]])
	if CoreLevel.opened_names(2) != "":
		assert_array(lines).contains([Tr.t("CORE_GAIN_OPENS") % CoreLevel.opened_names(2)])

func test_the_level_text_reads_n_of_five() -> void:
	ProgressionManager.core_level = 2
	assert_str(CoreLevel.level_text()).is_equal(Tr.t("TOPE_LEVEL_OF") % [2, GameConfig.core_level_max])

func test_missing_requirements_are_said_in_words() -> void:
	var lines: Array = CoreLevel.block_lines()
	var saw: BuildingData = Rules.load_building_data("sawmill")
	var found := false
	for l in lines:
		if String(l).contains(saw.get_display_name()):
			found = true
	assert_bool(found).override_failure_message(str(lines)).is_true()

# ── ¿QUE HACER? ──────────────────────────────────────────────────────

func test_a_full_cap_asks_for_the_core_when_it_can_be_raised() -> void:
	for id in ["sawmill", "gold_mine", "house", "warehouse"]:
		_place(id)
	while Rules.count_building("sawmill") < GameConfig.get_building_limit("sawmill"):
		_place("sawmill")
	var step: Dictionary = Objectives.core_step_for_limit("sawmill")
	assert_str(String(step.get("kind", ""))).is_equal("core")
	assert_int(int(step["level"])).is_equal(2)
	assert_str(String(Objectives.describe(step)["title"])).is_equal(Tr.t("OBJ_DO_CORE") % 2)
	assert_dict(Objectives.step_cost(step)).is_equal(GameConfig.get_core_upgrade_cost(2))

func test_no_core_step_while_there_is_room_or_it_cannot_be_raised_yet() -> void:
	assert_dict(Objectives.core_step_for_limit("sawmill")).is_empty()
	# Lleno pero sin la base de la era 1: el Nucleo 2 aun no se puede pedir.
	while Rules.count_building("sawmill") < GameConfig.get_building_limit("sawmill"):
		_place("sawmill")
	assert_dict(Objectives.core_step_for_limit("sawmill")).is_empty()

# ── El modelo ────────────────────────────────────────────────────────

func test_the_3d_pieces_exist_for_every_level_and_are_cached() -> void:
	var size := Vector3(5.0, 6.0, 5.0)
	for lv in range(2, GameConfig.core_level_max + 1):
		var mesh: ArrayMesh = CoreTrim.trim_mesh(lv, size)
		assert_object(mesh).is_not_null()
		assert_object(CoreTrim.trim_mesh(lv, size)).is_same(mesh)
	assert_float(CoreTrim.level_scale(5).y).is_greater(CoreTrim.level_scale(1).y)

func test_the_2d_drawing_does_not_grow_the_core() -> void:
	var Art = load("res://scripts/view2d/BuildingArt2D.gd")
	assert_int(Art.growth_level("nucleo", 5)).is_equal(1)
	assert_int(Art.growth_level("house", 3)).is_equal(3)
