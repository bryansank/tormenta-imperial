extends GdUnitTestSuite
## Topes de edificios que suben con la era (feat/topes-por-era, decision D1 de
## Bryan del 14-10-2026): la tabla GameConfig.building_limits_by_era, el unico
## lector GameConfig.get_building_limit(id) (era en curso + rango), las
## decoraciones sin tope, los huecos del rango encima y Sandbox sin topes.
## Sin escena: estado de autoloads, que se deja como estaba en after_test().
##
## Escrito sin ejecutar (regla de Bryan: un solo pase de pruebas al final).

const Menu := preload("res://scripts/ui/ConstructionMenu.gd")
const Rules := preload("res://scripts/buildings/PlacementRules.gd")

var _era_before := 1
var _rank_bonus_before: Dictionary = {}

func before_test() -> void:
	_era_before = ProgressionManager.current_era
	_rank_bonus_before = GameConfig.rank_limit_bonus.duplicate()
	GameConfig.rank_limit_bonus = {}
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)

func after_test() -> void:
	ProgressionManager.current_era = _era_before
	GameConfig.rank_limit_bonus = _rank_bonus_before
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)

func _at_era(era: int) -> void:
	ProgressionManager.current_era = era

# ── La tabla ─────────────────────────────────────────────────────────

func test_era_one_keeps_the_old_caps() -> void:
	# Una partida guardada nunca queda por encima de su tope: la era 1 es la de
	# siempre, y lo que no esta en la tabla por era sigue en building_limits.
	for id in GameConfig.building_limits_by_era:
		var row: Array = GameConfig.building_limits_by_era[id]
		assert_int(int(row[0])).override_failure_message("%s: era 1 = %d, building_limits = %d" % [
			id, int(row[0]), int(GameConfig.building_limits.get(id, -1))]) \
			.is_equal(int(GameConfig.building_limits.get(id, -1)))

func test_every_row_has_three_eras_and_never_goes_down() -> void:
	for id in GameConfig.building_limits_by_era:
		var row: Array = GameConfig.building_limits_by_era[id]
		assert_int(row.size()).is_equal(GameConfig.max_era())
		for i in range(1, row.size()):
			assert_int(int(row[i])).override_failure_message("%s baja de la era %d a la %d" % [id, i, i + 1]) \
				.is_greater_equal(int(row[i - 1]))

func test_caps_rise_with_the_current_era() -> void:
	_at_era(1)
	assert_int(GameConfig.get_building_limit("sawmill")).is_equal(5)
	assert_int(GameConfig.get_building_limit("house")).is_equal(10)
	_at_era(2)
	assert_int(GameConfig.get_building_limit("sawmill")).is_equal(8)
	assert_int(GameConfig.get_building_limit("house")).is_equal(15)
	_at_era(3)
	assert_int(GameConfig.get_building_limit("sawmill")).is_equal(10)
	assert_int(GameConfig.get_building_limit("house")).is_equal(20)

func test_the_rule_of_thumb_is_about_one_and_a_half_then_double() -> void:
	# ≈ ×1,5 en la era 2 y ×2 en la era 3 para los que suben del todo.
	for id in ["sawmill", "gold_mine", "house", "farm"]:
		var base := GameConfig.base_building_limit(id, 1)
		assert_int(GameConfig.base_building_limit(id, 2)).is_equal(int(ceil(base * 1.5)))
		assert_int(GameConfig.base_building_limit(id, 3)).is_equal(base * 2)

func test_an_era_out_of_range_is_clamped() -> void:
	assert_int(GameConfig.get_building_limit_for_era("sawmill", 0)).is_equal(5)
	assert_int(GameConfig.get_building_limit_for_era("sawmill", 9)).is_equal(10)

func test_unique_buildings_stay_one_in_every_era() -> void:
	for era in [1, 2, 3]:
		for id in ["market", "laboratory", "headquarters"]:
			assert_int(GameConfig.get_building_limit_for_era(id, era)).is_equal(1)

func test_the_warehouse_does_not_rise_so_the_hq_price_still_fits() -> void:
	# 1000 + 5×500 = 3500 = CG nivel 3 (sin materiales): ver test_storage_pool.
	for era in [1, 2, 3]:
		assert_int(GameConfig.get_building_limit_for_era("warehouse", era)).is_equal(5)

func test_an_unknown_building_has_no_cap() -> void:
	assert_int(GameConfig.get_building_limit("edificio_de_2031")).is_equal(-1)

# ── Decoraciones ─────────────────────────────────────────────────────

func test_decorations_have_no_cap_in_any_era() -> void:
	var seen := 0
	for data in BuildingData.load_all():
		if not (data as BuildingData).is_decoration:
			continue
		seen += 1
		for era in [1, 2, 3]:
			assert_int(GameConfig.get_building_limit_for_era(data.id, era)) \
				.override_failure_message("%s tiene tope en la era %d" % [data.id, era]).is_equal(-1)
	assert_int(seen).is_greater(0)

func test_a_decoration_listed_in_building_limits_is_still_uncapped() -> void:
	# La estatua y la fuente siguen en building_limits (5) y otras ramas pueden
	# anadir entradas: la regla mira is_decoration, no la tabla.
	var had := GameConfig.building_limits.has("statue")
	var old_value: Variant = GameConfig.building_limits.get("statue")
	GameConfig.building_limits["statue"] = 5
	assert_int(GameConfig.get_building_limit("statue")).is_equal(-1)
	if had:
		GameConfig.building_limits["statue"] = old_value
	else:
		GameConfig.building_limits.erase("statue")
	assert_int(GameConfig.get_building_limit("fountain")).is_equal(-1)
	assert_int(GameConfig.get_building_limit("garden")).is_equal(-1)
	assert_int(GameConfig.get_building_limit("road")).is_equal(-1)

# ── Rango ────────────────────────────────────────────────────────────

func test_the_rank_slots_add_on_top_of_the_era_cap() -> void:
	GameConfig.rank_limit_bonus = {"house": 2, "tower": 1}
	_at_era(1)
	assert_int(GameConfig.get_building_limit("house")).is_equal(12)
	_at_era(3)
	assert_int(GameConfig.get_building_limit("house")).is_equal(22)
	assert_int(GameConfig.get_building_limit("tower")).is_equal(7)

func test_rank_slots_on_a_decoration_change_nothing() -> void:
	GameConfig.rank_limit_bonus = {"statue": 2, "fountain": 2}
	assert_int(GameConfig.get_building_limit("statue")).is_equal(-1)
	assert_int(GameConfig.get_building_limit("fountain")).is_equal(-1)

# ── Sandbox ──────────────────────────────────────────────────────────

func test_sandbox_has_no_caps_in_any_era() -> void:
	GameMode.begin_run(GameMode.Mode.SANDBOX)
	GameConfig.rank_limit_bonus = {"house": 2}
	for era in [1, 2, 3]:
		for id in ["sawmill", "house", "warehouse", "headquarters", "market"]:
			assert_int(GameConfig.get_building_limit_for_era(id, era)).is_equal(-1)
	assert_dict(GameConfig.next_building_limit("sawmill")).is_empty()

# ── Lo que dice CONSTRUIR ────────────────────────────────────────────

func test_next_limit_names_the_next_era_that_raises_it() -> void:
	_at_era(1)
	assert_dict(GameConfig.next_building_limit("sawmill")).is_equal({"era": 2, "limit": 8})
	_at_era(2)
	assert_dict(GameConfig.next_building_limit("sawmill")).is_equal({"era": 3, "limit": 10})
	_at_era(3)
	assert_dict(GameConfig.next_building_limit("sawmill")).is_empty()
	assert_dict(GameConfig.next_building_limit("warehouse")).is_empty()
	assert_dict(GameConfig.next_building_limit("garden")).is_empty()

func test_the_menu_line_reads_count_cap_and_next_era() -> void:
	_at_era(1)
	var have := Rules.count_building("sawmill")
	assert_str(Menu.limit_text("sawmill")).is_equal(
		Tr.t("FMT_LIMIT_COUNT") % [have, 5] + " · " + Tr.t("FMT_LIMIT_NEXT_ERA") % [2, 8])
	_at_era(3)
	assert_str(Menu.limit_text("sawmill")).is_equal(Tr.t("FMT_LIMIT_COUNT") % [have, 10])

func test_the_menu_says_nothing_for_uncapped_buildings() -> void:
	assert_str(Menu.limit_text("garden")).is_empty()
	assert_dict(Menu.limit_info("road")).is_empty()
	GameMode.begin_run(GameMode.Mode.SANDBOX)
	assert_str(Menu.limit_text("sawmill")).is_empty()

func test_the_limit_is_derived_not_saved() -> void:
	# Nada nuevo en el save: el tope sale de la era (progression) y del rango.
	var data: Dictionary = ProgressionManager.get_save_data()
	assert_bool(data.has("building_limits")).is_false()
	assert_bool(data.has("current_era")).is_true()

func test_the_rank_toast_does_not_announce_slots_of_uncapped_buildings() -> void:
	# El rango 13 daba +2 estatuas y +2 fuentes: sin tope, no se anuncian.
	var RankPanelScript := load("res://scripts/ui/RankPanel.gd")
	var lines: Array = RankPanelScript.reward_lines({"limit": {"statue": 2, "fountain": 2, "house": 2}})
	assert_int(lines.size()).is_equal(1)
