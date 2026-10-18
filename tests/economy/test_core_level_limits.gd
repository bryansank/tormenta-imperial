extends GdUnitTestSuite
## Topes de edificios que suben con el NIVEL DEL NUCLEO (1.2, feat/nucleo-y-planos;
## decision de Bryan del 18-10-2026, sustituye a los topes por era): la tabla
## GameConfig.core_level_limits, el unico lector GameConfig.get_building_limit(id)
## (nivel del Nucleo + rango), los edificios que abre el Nucleo
## (core_level_unlocks), las decoraciones sin tope, los huecos del rango encima,
## Sandbox sin topes y el puente de las filas por era de otras ramas.
## Sin escena: estado de autoloads, que se deja como estaba en after_test().
##
## Escrito sin ejecutar (regla de Bryan: un solo pase de pruebas al final).

const Menu := preload("res://scripts/ui/ConstructionMenu.gd")
const Rules := preload("res://scripts/buildings/PlacementRules.gd")

var _core_before := 1
var _rank_bonus_before: Dictionary = {}
var _bridge_before: Dictionary = {}

func before_test() -> void:
	_core_before = ProgressionManager.core_level
	_rank_bonus_before = GameConfig.rank_limit_bonus.duplicate()
	_bridge_before = GameConfig.building_limits_by_era.duplicate(true)
	GameConfig.rank_limit_bonus = {}
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)

func after_test() -> void:
	ProgressionManager.core_level = _core_before
	GameConfig.rank_limit_bonus = _rank_bonus_before
	GameConfig.building_limits_by_era = _bridge_before
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)

func _at_core(level: int) -> void:
	ProgressionManager.core_level = level

# ── La tabla ─────────────────────────────────────────────────────────

func test_level_one_matches_building_limits() -> void:
	# La primera cifra de cada fila es la de building_limits: lo que leen las
	# herramientas y las pruebas que miran "el tope de salida".
	for id in GameConfig.core_level_limits:
		var row: Array = GameConfig.core_level_limits[id]
		assert_int(int(row[0])).override_failure_message("%s: N1 = %d, building_limits = %d" % [
			id, int(row[0]), int(GameConfig.building_limits.get(id, -1))]) \
			.is_equal(int(GameConfig.building_limits.get(id, -1)))

func test_every_row_has_five_levels_and_never_goes_down() -> void:
	for id in GameConfig.core_level_limits:
		var row: Array = GameConfig.core_level_limits[id]
		assert_int(row.size()).override_failure_message(id).is_equal(GameConfig.core_level_max)
		for i in range(1, row.size()):
			assert_int(int(row[i])).override_failure_message("%s baja del Nucleo %d al %d" % [id, i, i + 1]) \
				.is_greater_equal(int(row[i - 1]))

func test_caps_rise_with_the_core_level() -> void:
	_at_core(1)
	assert_int(GameConfig.get_building_limit("sawmill")).is_equal(4)
	assert_int(GameConfig.get_building_limit("house")).is_equal(8)
	_at_core(2)
	assert_int(GameConfig.get_building_limit("sawmill")).is_equal(5)
	assert_int(GameConfig.get_building_limit("house")).is_equal(10)
	_at_core(4)
	assert_int(GameConfig.get_building_limit("sawmill")).is_equal(10)
	assert_int(GameConfig.get_building_limit("house")).is_equal(20)
	_at_core(5)
	assert_int(GameConfig.get_building_limit("sawmill")).is_equal(11)
	assert_int(GameConfig.get_building_limit("house")).is_equal(22)

func test_the_era_does_not_move_the_caps_any_more() -> void:
	_at_core(1)
	var era_before: int = ProgressionManager.current_era
	ProgressionManager.current_era = 3
	assert_int(GameConfig.get_building_limit("sawmill")).is_equal(4)
	ProgressionManager.current_era = era_before

func test_levels_two_three_and_four_are_the_old_era_caps() -> void:
	# La regla de la tabla: N2 ≈ era 1 de la 1.1, N3 ≈ era 2, N4 ≈ era 3.
	assert_int(GameConfig.base_building_limit("sawmill", 2)).is_equal(5)
	assert_int(GameConfig.base_building_limit("sawmill", 3)).is_equal(8)
	assert_int(GameConfig.base_building_limit("sawmill", 4)).is_equal(10)
	assert_int(GameConfig.base_building_limit("farm", 3)).is_equal(9)
	assert_int(GameConfig.base_building_limit("farm", 4)).is_equal(12)

func test_a_level_out_of_range_is_clamped() -> void:
	assert_int(GameConfig.get_building_limit_at("sawmill", 0)).is_equal(4)
	assert_int(GameConfig.get_building_limit_at("sawmill", 9)).is_equal(11)

func test_unique_buildings_stay_one_at_every_level() -> void:
	for lv in range(1, GameConfig.core_level_max + 1):
		for id in ["market", "laboratory", "headquarters", "lighthouse"]:
			assert_int(GameConfig.get_building_limit_at(id, lv)).is_equal(1)

func test_five_warehouses_arrive_with_core_two_so_the_hq_never_waits() -> void:
	# 1000 + 5×500 = 3500 = CG nivel 3 (sin materiales): ver test_storage_pool.
	assert_int(GameConfig.get_building_limit_at("warehouse", 2)).is_equal(5)
	assert_int(GameConfig.get_building_limit_at("warehouse", GameConfig.core_level_max)).is_equal(5)

func test_the_era_gates_are_never_capped_out_at_level_one() -> void:
	# La Fundicion, la Refineria, el Mercado, el Laboratorio y el CG caben con
	# el Nucleo 1: el Nucleo nunca frena el paso de era.
	for id in ["foundry", "refinery", "market", "laboratory", "headquarters"]:
		assert_int(GameConfig.get_building_limit_at(id, 1)).override_failure_message(id).is_greater_equal(1)
	# Y dos torres para el hito de Comandante.
	assert_int(GameConfig.get_building_limit_at("tower", 1)).is_greater_equal(2)

func test_an_unknown_building_has_no_cap() -> void:
	assert_int(GameConfig.get_building_limit("edificio_de_2031")).is_equal(-1)

func test_barracks_shipyards_and_aerodromes_stay_uncapped() -> void:
	for lv in range(1, GameConfig.core_level_max + 1):
		for id in ["barracks", "shipyard", "aerodrome"]:
			assert_int(GameConfig.get_building_limit_at(id, lv)).is_equal(-1)

# ── El puente de las filas por era ───────────────────────────────────

func test_an_era_row_from_another_branch_maps_to_core_levels() -> void:
	# Una rama que aun no conoce el Nucleo mete [e1, e2, e3]: se lee como
	# [e1, e1, e2, e3, e3] hasta que el integrador lo pase a core_level_limits.
	GameConfig.building_limits_by_era["edificio_puente"] = [2, 4, 6]
	assert_int(GameConfig.base_building_limit("edificio_puente", 1)).is_equal(2)
	assert_int(GameConfig.base_building_limit("edificio_puente", 2)).is_equal(2)
	assert_int(GameConfig.base_building_limit("edificio_puente", 3)).is_equal(4)
	assert_int(GameConfig.base_building_limit("edificio_puente", 4)).is_equal(6)
	assert_int(GameConfig.base_building_limit("edificio_puente", 5)).is_equal(6)

# ── Lo que abre el Nucleo ────────────────────────────────────────────

func test_core_unlocks_are_valid_levels() -> void:
	for id in GameConfig.core_level_unlocks:
		var lv: int = int(GameConfig.core_level_unlocks[id])
		assert_int(lv).override_failure_message(id).is_between(1, GameConfig.core_level_max)

func test_a_building_opened_by_the_core_is_locked_below_its_level() -> void:
	_at_core(1)
	assert_bool(Rules.check_core_level("tavern")).is_false()
	assert_str(Rules.lock_kind("tavern")).is_equal("core")
	assert_str(Rules.core_lock_text("tavern")).is_equal(Tr.t("LBL_CORE_NEEDED") % 2)
	_at_core(2)
	assert_bool(Rules.check_core_level("tavern")).is_true()
	assert_str(Rules.lock_kind("tavern")).is_equal("")

func test_a_core_lock_is_the_first_reason_and_the_only_one() -> void:
	_at_core(1)
	var data: BuildingData = Rules.load_building_data("tavern")
	if data == null:
		return
	var reasons: Array = Rules.block_reasons(data)
	assert_array(reasons).is_equal([Rules.core_lock_text("tavern")])
	assert_str(Rules.purchase_block_message(data)).is_equal(Rules.core_lock_text("tavern"))

func test_sandbox_opens_every_core_lock() -> void:
	GameMode.begin_run(GameMode.Mode.SANDBOX)
	_at_core(1)
	assert_bool(Rules.check_core_level("fuel_depot")).is_true()
	assert_int(GameConfig.core_level_unlock("fuel_depot")).is_equal(1)

# ── Decoraciones ─────────────────────────────────────────────────────

func test_decorations_have_no_cap_at_any_level() -> void:
	var seen := 0
	for data in BuildingData.load_all():
		if not (data as BuildingData).is_decoration:
			continue
		seen += 1
		for lv in range(1, GameConfig.core_level_max + 1):
			assert_int(GameConfig.get_building_limit_at(data.id, lv)) \
				.override_failure_message("%s tiene tope con el Nucleo %d" % [data.id, lv]).is_equal(-1)
	assert_int(seen).is_greater(0)

func test_a_decoration_listed_in_building_limits_is_still_uncapped() -> void:
	var had := GameConfig.building_limits.has("statue")
	var old_value: Variant = GameConfig.building_limits.get("statue")
	GameConfig.building_limits["statue"] = 5
	assert_int(GameConfig.get_building_limit("statue")).is_equal(-1)
	if had:
		GameConfig.building_limits["statue"] = old_value
	else:
		GameConfig.building_limits.erase("statue")
	assert_int(GameConfig.get_building_limit("garden")).is_equal(-1)
	assert_int(GameConfig.get_building_limit("road")).is_equal(-1)

# ── Rango ────────────────────────────────────────────────────────────

func test_the_rank_slots_add_on_top_of_the_core_cap() -> void:
	GameConfig.rank_limit_bonus = {"house": 2, "tower": 1}
	_at_core(1)
	assert_int(GameConfig.get_building_limit("house")).is_equal(10)
	_at_core(4)
	assert_int(GameConfig.get_building_limit("house")).is_equal(22)
	assert_int(GameConfig.get_building_limit("tower")).is_equal(7)

# ── Sandbox ──────────────────────────────────────────────────────────

func test_sandbox_has_no_caps_at_any_level() -> void:
	GameMode.begin_run(GameMode.Mode.SANDBOX)
	GameConfig.rank_limit_bonus = {"house": 2}
	for lv in range(1, GameConfig.core_level_max + 1):
		for id in ["sawmill", "house", "warehouse", "headquarters", "market"]:
			assert_int(GameConfig.get_building_limit_at(id, lv)).is_equal(-1)
	assert_dict(GameConfig.next_building_limit("sawmill")).is_empty()

# ── Lo que dice CONSTRUIR ────────────────────────────────────────────

func test_next_limit_names_the_next_core_level_that_raises_it() -> void:
	_at_core(1)
	assert_dict(GameConfig.next_building_limit("sawmill")).is_equal({"core_level": 2, "limit": 5})
	_at_core(4)
	assert_dict(GameConfig.next_building_limit("sawmill")).is_equal({"core_level": 5, "limit": 11})
	_at_core(5)
	assert_dict(GameConfig.next_building_limit("sawmill")).is_empty()
	_at_core(2)
	# El almacen ya no sube despues del 2: nada que anunciar.
	assert_dict(GameConfig.next_building_limit("warehouse")).is_empty()
	assert_dict(GameConfig.next_building_limit("garden")).is_empty()

func test_the_menu_line_reads_count_cap_and_next_core_level() -> void:
	_at_core(1)
	var have := Rules.count_building("sawmill")
	assert_str(Menu.limit_text("sawmill")).is_equal(
		Tr.t("FMT_LIMIT_COUNT") % [have, 4] + " · " + Tr.t("FMT_LIMIT_NEXT_CORE") % [2, 5])
	_at_core(5)
	assert_str(Menu.limit_text("sawmill")).is_equal(Tr.t("FMT_LIMIT_COUNT") % [have, 11])

func test_the_full_card_says_which_core_level_to_reach() -> void:
	_at_core(1)
	GameConfig.rank_limit_bonus = {"sawmill": -GameConfig.base_building_limit("sawmill", 1) + Rules.count_building("sawmill")}
	# Lleno a proposito: el tope de ahora es lo que ya hay (0 si no hay ninguno).
	var info: Dictionary = Menu.limit_info("sawmill")
	if not bool(info.get("full", false)):
		return
	assert_str(Menu.card_full_text("sawmill")).contains(Tr.t("TOPE_CARD_FULL_CORE") % int(info["next_core"]))

func test_the_menu_says_nothing_for_uncapped_buildings() -> void:
	assert_str(Menu.limit_text("garden")).is_empty()
	assert_dict(Menu.limit_info("road")).is_empty()
	GameMode.begin_run(GameMode.Mode.SANDBOX)
	assert_str(Menu.limit_text("sawmill")).is_empty()

func test_the_limit_is_derived_from_the_saved_core_level() -> void:
	# El tope no se guarda: sale del nivel del Nucleo (progression.core) y del rango.
	var data: Dictionary = ProgressionManager.get_save_data()
	assert_bool(data.has("building_limits")).is_false()
	assert_bool(data.has("core")).is_true()

func test_the_rank_toast_does_not_announce_slots_of_uncapped_buildings() -> void:
	var RankPanelScript = load("res://scripts/ui/RankPanel.gd")
	var lines: Array = RankPanelScript.reward_lines({"limit": {"statue": 2, "fountain": 2, "house": 2}})
	assert_int(lines.size()).is_equal(1)
