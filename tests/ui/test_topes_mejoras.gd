extends GdUnitTestSuite
## Topes y mejoras explicados (rama feat/topes-mejoras-ayuda, 2026-10-17):
## la frase del tope lleno en CONSTRUIR y "Mejorar uno", lo que llega con una
## era, la ficha del edificio (nivel N de 3, por que no se mejora, por que
## MEJORAR esta apagado, repuestos), las paginas de AYUDA con numeros de
## GameConfig, la guia de edificios y los textos corregidos.
##
## Escrito sin ejecutar (regla de Bryan: un solo pase de pruebas al final).
## Toca la rejilla y los recursos: lo deja todo como estaba en after_test().

const HelpText := preload("res://scripts/ui/BuildingHelpText.gd")
const HelpCatalog := preload("res://scripts/ui/HelpCatalog.gd")
const Menu := preload("res://scripts/ui/ConstructionMenu.gd")
const Rules := preload("res://scripts/buildings/PlacementRules.gd")
const IndexScene := preload("res://scenes/ui/HelpIndexPanel.tscn")
const InfoScene := preload("res://scenes/ui/BuildingInfoPanel.tscn")

var _amounts := {}
var _unlocks := {}
var _nodes: Array = []
var _mode := 0
var _era := 1
var _core := 1
var _rank_bonus: Dictionary = {}
var _locale := "es"
var _tutorial: Dictionary = {}

func before_test() -> void:
	_mode = GameMode.current
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	_era = ProgressionManager.current_era
	ProgressionManager.current_era = 1
	# Los topes van con el Nucleo (1.2): estos casos empiezan con el Nucleo 1.
	_core = ProgressionManager.core_level
	ProgressionManager.core_level = 1
	_rank_bonus = GameConfig.rank_limit_bonus.duplicate()
	GameConfig.rank_limit_bonus = {}
	_amounts = {}
	for t in ResourceManager.get_all():
		_amounts[ResourceManager.get_type_name(t)] = ResourceManager.get_amount(t)
	_unlocks = ResourceManager.get_unlock_state()
	_locale = Tr.get_locale()
	_tutorial = TutorialManager.get_save_data()
	GridManager.clear_all()
	_nodes.clear()
	_rows.clear()
	_used.clear()

func after_test() -> void:
	GridManager.clear_all()
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	ResourceManager.set_amounts(_amounts)
	ResourceManager.set_unlock_state(_unlocks)
	GameConfig.rank_limit_bonus = _rank_bonus
	ProgressionManager.current_era = _era
	ProgressionManager.core_level = _core
	GameMode.current = _mode
	Tr.set_locale(_locale)
	TutorialManager.load_save_data(_tutorial)

func _data(id: String) -> BuildingData:
	return load("res://data/buildings/%s.tres" % id)

## `count` edificios `id` en la rejilla, separados, con el nivel dado.
func _place(id: String, count: int, level: int = 1) -> Array:
	var placed: Array = []
	var data := _data(id)
	# Seguido de lo que ya hay de ese tipo: una segunda llamada con el mismo id
	# (otro nivel) no cae encima de la primera.
	var first := int(_used.get(id, 0))
	_used[id] = first + count
	for k in count:
		var i := first + k
		var n := Node3D.new()
		n.set_meta("level", level)
		_nodes.append(n)
		# Ocho por fila, y un bloque de filas propio por tipo para que no se pisen.
		var cell := Vector2i(1 + (i % 8) * 4, 1 + int(i / 8.0) * 4 + _row_for(id) * 12)
		assert_bool(GridManager.place_building(cell, data, n)).override_failure_message(
			"no cupo %s en %s" % [id, cell]).is_true()
		placed.append(n)
	return placed

var _rows: Dictionary = {}
var _used: Dictionary = {}
func _row_for(id: String) -> int:
	if not _rows.has(id):
		_rows[id] = _rows.size()
	return int(_rows[id])

# ── La frase del tope lleno ──────────────────────────────────────────

func test_nothing_is_said_while_there_is_room() -> void:
	_place("sawmill", 2)
	assert_str(HelpText.limit_full_text("sawmill")).is_empty()
	assert_array(Menu.explain_lines(_data("sawmill"))).is_empty()

func test_a_full_card_says_the_cap_and_the_next_core_level() -> void:
	_place("sawmill", GameConfig.get_building_limit("sawmill"))
	var next := GameConfig.next_building_limit("sawmill")
	assert_str(HelpText.limit_full_text("sawmill")).is_equal(Tr.t("TOPE_FULL_NEXT_CORE") % [
		GameConfig.get_building_limit("sawmill"), int(next["core_level"]), int(next["limit"])])
	assert_str(Menu.card_full_text("sawmill")).contains(Tr.t("TOPE_CARD_FULL_CORE") % int(next["core_level"]))

func test_a_cap_that_does_not_rise_says_you_have_the_most() -> void:
	# Desde el Nucleo 2 el almacen ya no sube (5: el precio del CG nivel 3).
	ProgressionManager.core_level = 2
	_place("warehouse", GameConfig.get_building_limit("warehouse"))
	assert_str(HelpText.limit_full_text("warehouse")).is_equal(
		Tr.t("TOPE_FULL_MAX") % GameConfig.get_building_limit("warehouse"))

func test_a_unique_building_says_there_is_only_one() -> void:
	_place("market", 1)
	assert_bool(HelpText.is_unique("market")).is_true()
	assert_str(HelpText.limit_full_text("market")).is_equal(Tr.t("TOPE_FULL_UNIQUE"))

func test_full_and_upgradable_points_at_upgrading() -> void:
	_place("sawmill", GameConfig.get_building_limit("sawmill"))
	assert_str(HelpText.limit_full_advice("sawmill")).is_equal(Tr.t("TOPE_FULL_UPGRADE"))
	var lines: Array = Menu.explain_lines(_data("sawmill"))
	assert_array(lines).contains([HelpText.limit_full_text("sawmill"), Tr.t("TOPE_FULL_UPGRADE")])

func test_full_and_all_at_top_level_says_so() -> void:
	_place("sawmill", GameConfig.get_building_limit("sawmill"), GameConfig.max_building_level)
	assert_object(HelpText.lowest_upgradable("sawmill")).is_null()
	assert_str(HelpText.limit_full_advice("sawmill")).is_equal(Tr.t("TOPE_FULL_ALL_MAX"))

func test_a_full_building_that_has_no_upgrades_gives_no_advice() -> void:
	_place("tower", GameConfig.get_building_limit("tower"))
	assert_str(HelpText.limit_full_advice("tower")).is_empty()

func test_upgrade_one_picks_the_lowest_level() -> void:
	var a: Array = _place("sawmill", 1, 3)
	var b: Array = _place("gold_mine", 1, 1)
	var c: Array = _place("sawmill", 1, 2)
	assert_object(HelpText.lowest_upgradable("sawmill")).is_same(c[0])
	assert_object(HelpText.lowest_upgradable("gold_mine")).is_same(b[0])
	assert_object(a[0]).is_not_null()

func test_the_short_reasons_drop_what_the_sentence_already_says() -> void:
	_place("sawmill", GameConfig.get_building_limit("sawmill"))
	var limit_line: String = Tr.t("LBL_LIMIT_REACHED") % [
		Rules.count_building("sawmill"), GameConfig.get_building_limit("sawmill")]
	assert_array(Rules.block_reasons_short(_data("sawmill"))).contains([limit_line])
	assert_array(Menu.block_lines_without_explained(_data("sawmill"), true)).not_contains([limit_line])

# ── Lo que llega con una era ─────────────────────────────────────────

func test_steel_not_yet_in_the_game_says_which_era_brings_it() -> void:
	ResourceManager.set_unlock_state({"gold": true, "wood": true, "steel": false, "oil": false})
	ResourceManager.set_amounts({"steel": 0, "oil": 0})
	var lines: Array = HelpText.locked_lines(_data("fountain"))
	assert_array(lines).contains([Tr.t("TOPE_LOCK_ERA") % [2, _data("foundry").get_display_name()]])

func test_oil_says_era_three_once() -> void:
	ResourceManager.set_unlock_state({"gold": true, "wood": true, "steel": false, "oil": false})
	ResourceManager.set_amounts({"steel": 0, "oil": 0})
	var lines: Array = HelpText.locked_lines(_data("headquarters"))
	var era3: String = Tr.t("TOPE_LOCK_ERA") % [3, _data("refinery").get_display_name()]
	assert_int(lines.count(era3)).is_equal(1)

func test_a_locked_material_says_where_it_is_made() -> void:
	ResourceManager.set_unlock_state({"gold": true, "wood": true, "steel": true, "oil": false,
		"planks": false})
	ResourceManager.set_amounts({"planks": 0})
	var lines: Array = HelpText.locked_lines(_data("barracks"))
	assert_array(lines).contains([Tr.t("TOPE_LOCK_MATERIAL") % [Tr.res_name("planks"),
		_data("sawmill").get_display_name()]])

func test_nothing_locked_when_everything_is_unlocked() -> void:
	ResourceManager.set_unlock_state({"gold": true, "wood": true, "steel": true, "oil": true,
		"planks": true, "ingots": true, "beams": true, "fuel": true})
	assert_array(HelpText.locked_lines(_data("headquarters"))).is_empty()

# ── La ficha: nivel, sin mejora, por que esta apagado, repuestos ─────

func test_level_of_reads_n_of_three() -> void:
	assert_str(HelpText.level_of_text(1)).is_equal(Tr.t("TOPE_LEVEL_OF") % [1, GameConfig.max_building_level])

func test_buildings_without_upgrades_say_why() -> void:
	for id in ["barracks", "tower", "market", "laboratory"]:
		var text := HelpText.no_upgrade_text(_data(id))
		assert_str(text).override_failure_message(id).is_not_empty()
		assert_str(text).contains(Tr.t("TOPE_NO_UPGRADE_WHY_" + id.to_upper()))
	assert_str(HelpText.no_upgrade_text(_data("sawmill"))).is_empty()
	assert_str(HelpText.no_upgrade_text(_data("house"))).is_empty()

func test_the_parts_warning_comes_only_where_parts_are_asked() -> void:
	var parts := GameConfig.upgrade_parts_needed("sawmill", 3)
	if parts > 0:
		assert_str(HelpText.parts_note(_data("sawmill"), 3)).is_equal(Tr.t("TOPE_PARTS_NOTE") % [3, parts])
	assert_str(HelpText.parts_note(_data("sawmill"), 2)).is_empty()
	assert_str(HelpText.parts_note(_data("house"), 3)).is_empty()

func test_top_level_blocks_with_its_own_sentence() -> void:
	var n: Array = _place("sawmill", 1, GameConfig.max_building_level)
	assert_array(HelpText.upgrade_block_lines(_data("sawmill"), n[0])).contains_exactly([Tr.t("TOPE_MAX_LEVEL")])

func test_missing_parts_say_where_they_come_from() -> void:
	if GameConfig.upgrade_parts_needed("sawmill", 3) <= 0:
		return
	var n: Array = _place("sawmill", 1, 2)
	ResourceManager.set_amounts({"gold": 99999, "wood": 99999, "parts": 0})
	var lines: Array = HelpText.upgrade_block_lines(_data("sawmill"), n[0])
	assert_array(lines).contains([Tr.t("TOPE_HOW_PARTS")])

func test_nothing_blocks_when_it_can_be_paid() -> void:
	var n: Array = _place("house", 1, 1)
	ResourceManager.set_amounts({"gold": 5000, "wood": 5000})
	assert_array(HelpText.upgrade_block_lines(_data("house"), n[0])).is_empty()

func test_the_hq_says_when_it_does_not_fit_in_storage() -> void:
	var n: Array = _place("headquarters", 1, 2)
	var cap: int = ResourceManager.get_storage_cap()
	if HelpText.hq_bag_cost(3) <= cap:
		return
	var lines: Array = HelpText.upgrade_block_lines(_data("headquarters"), n[0])
	assert_array(lines).contains([Tr.t("TOPE_BAG_SMALL") % [HelpText._num(HelpText.hq_bag_cost(3)), HelpText._num(cap)]])

func test_the_panel_says_a_barracks_has_no_upgrades() -> void:
	var panel: CanvasLayer = auto_free(InfoScene.instantiate())
	add_child(panel)
	var n: Array = _place("barracks", 1)
	EventBus.building_clicked.emit(n[0], _data("barracks"))
	var label: Label = panel.find_child("NoUpgrade", true, false)
	assert_object(label).is_not_null()
	assert_bool(label.visible).is_true()
	assert_str(label.text).is_equal(HelpText.no_upgrade_text(_data("barracks")))

func test_the_panel_shows_level_n_of_three() -> void:
	var panel: CanvasLayer = auto_free(InfoScene.instantiate())
	add_child(panel)
	var n: Array = _place("house", 1, 2)
	EventBus.building_clicked.emit(n[0], _data("house"))
	var label: Label = panel.find_child("UpgradeLevel", true, false)
	assert_str(label.text).is_equal(HelpText.level_of_text(2))

# ── Cifras vivas en ¿QUE HACER? ──────────────────────────────────────

func test_the_hq_why_carries_the_real_cost() -> void:
	for loc in ["es", "en"]:
		Tr.set_locale(loc)
		var raw := Tr.t("OBJ_WHY_HQ_2")
		assert_str(raw).contains("{HQ2_COST}")
		var live := HelpText.live_text(raw)
		assert_str(live).not_contains("{")
		assert_str(live).contains(HelpText._num(HelpText.hq_bag_cost(2)))
		assert_str(HelpText.live_text(Tr.t("OBJ_WHY_HQ_3"))).contains(HelpText._num(HelpText.hq_bag_cost(3)))

func test_numbers_use_the_locale_separator() -> void:
	Tr.set_locale("es")
	assert_str(HelpText._num(3500)).is_equal("3.500")
	Tr.set_locale("en")
	assert_str(HelpText._num(3500)).is_equal("3,500")
	assert_str(HelpText._num(800)).is_equal("800")

# ── Paginas de AYUDA ────────────────────────────────────────────────

func test_every_page_is_in_the_catalog_and_written_in_both_languages() -> void:
	for id in HelpText.PAGES:
		assert_bool(HelpCatalog.has(id)).override_failure_message(id).is_true()
		assert_bool(HelpCatalog.is_page(id)).is_true()
		for loc in ["es", "en"]:
			Tr.set_locale(loc)
			var body := HelpCatalog.body(id)
			assert_str(body).override_failure_message("%s %s" % [id, loc]).is_not_empty()
			# Ninguna clave cruda ni hueco de formato sin rellenar.
			assert_str(body).override_failure_message("%s %s" % [id, loc]).not_contains("TOPE_")
			assert_str(body).not_contains("%d")
			assert_str(body).not_contains("%s")

func test_the_limits_page_reads_the_table() -> void:
	var body := HelpText.limits_page()
	var row: Array = []
	for lv in range(1, GameConfig.core_level_max + 1):
		row.append(str(GameConfig.base_building_limit("sawmill", lv)))
	assert_str(body).contains(" · ".join(row))
	assert_str(body).contains(_data("market").get_display_name())

func test_the_upgrades_page_has_the_hq_cost_and_the_audit() -> void:
	var body := HelpText.upgrades_page()
	assert_str(body).contains(HelpText._num(HelpText.hq_bag_cost(3)))
	assert_str(body).contains(_data("barracks").get_display_name())

func test_the_towers_page_reads_the_crew_cap() -> void:
	var body := HelpText.towers_page()
	assert_str(body).contains(str(GameConfig.storm_tower_garrison_max))
	assert_str(body).contains(str(roundi(GameConfig.storm_tower_mitigation_max * 100.0)))

func test_the_workshop_page_lists_every_material() -> void:
	var body := HelpText.workshop_page()
	for mat in GameConfig.material_sources:
		assert_str(body).contains(Tr.res_cap(String(mat)))

func test_the_index_opens_a_page_in_place_and_comes_back() -> void:
	TutorialManager.load_save_data({"intro_seen": true, "guide_state": "done"})
	var idx: CanvasLayer = auto_free(IndexScene.instantiate())
	add_child(idx)
	idx.open()
	var btn: Button = idx.find_child("Help_guide_limits", true, false)
	assert_object(btn).is_not_null()
	btn.pressed.emit()
	assert_bool(idx.is_open()).is_true()
	assert_str(idx.current_page()).is_equal("guide_limits")
	assert_str(idx.page_text()).is_equal(HelpCatalog.body("guide_limits"))
	assert_bool(TutorialManager.has_seen_help("guide_limits")).is_true()
	var back: Button = idx.find_child("PageBack", true, false)
	back.pressed.emit()
	assert_str(idx.current_page()).is_empty()
	idx.close()

func test_the_index_offers_the_quick_guide() -> void:
	var idx: CanvasLayer = auto_free(IndexScene.instantiate())
	add_child(idx)
	assert_object(idx.find_child("QuickGuideOpen", true, false)).is_not_null()

# ── Guia de edificios ───────────────────────────────────────────────

func test_the_building_guide_says_caps_needs_and_upgrades() -> void:
	var line := HelpText.guide_rules_line(_data("sawmill"))
	assert_str(line).contains(Tr.t("TOPE_GUIDE_UPGRADES") % GameConfig.max_building_level)
	assert_str(HelpText.guide_rules_line(_data("barracks"))).contains(Tr.t("TOPE_GUIDE_NO_UPGRADE"))
	assert_str(HelpText.guide_rules_line(_data("market"))).contains(Tr.t("TOPE_GUIDE_UNIQUE"))
	assert_str(HelpText.guide_rules_line(_data("garden"))).contains(Tr.t("TOPE_GUIDE_NO_LIMIT"))
	var reqs := Rules.prerequisite_names("foundry")
	assert_str(HelpText.guide_rules_line(_data("foundry"))).contains(reqs)

# ── Textos corregidos ───────────────────────────────────────────────

func test_the_shared_bag_texts_count_food() -> void:
	Tr.set_locale("es")
	assert_str(Tr.t("TUT_TIP_OVERFLOW_BODY")).contains("comida")
	assert_str(Tr.t("TUT_PLAY_2_BODY")).contains("comida")
	assert_str(Tr.t("TUT_TIP_OVERFLOW_BODY")).not_contains("cuatro recursos")
	Tr.set_locale("en")
	assert_str(Tr.t("TUT_TIP_OVERFLOW_BODY")).contains("food")
	assert_str(Tr.t("TUT_PLAY_2_BODY")).not_contains("four resources")

# ── Los edificios de la 1.1 en las paginas (merge 1.0 -> 1.1, 2026-10-17) ──

func test_the_pages_include_the_buildings_of_one_point_one() -> void:
	var limits := HelpText.limits_page()
	for id in ["shipyard", "aerodrome", "fishing_dock", "windmill", "lighthouse"]:
		assert_str(limits).override_failure_message(id).contains(_data(id).get_display_name())
	# Astillero y Aerodromo sin tope (2026-10-18): la pagina los nombra como tales.
	for id in ["shipyard", "aerodrome"]:
		for lv in range(1, GameConfig.core_level_max + 1):
			assert_int(GameConfig.get_building_limit_at(id, lv)).is_equal(-1)
	assert_str(limits).contains(Tr.t("TOPE_PAGE_LIMITS_FREE_BUILDINGS").get_slice("%s", 0))
	# El Muelle sube con el Nucleo: su fila sale con las cinco cifras.
	var row: Array = []
	for lv in range(1, GameConfig.core_level_max + 1):
		row.append(str(GameConfig.base_building_limit("fishing_dock", lv)))
	assert_str(limits).contains("%s: %s" % [_data("fishing_dock").get_display_name(), " · ".join(row)])
	# El Astillero y el Aerodromo no se mejoran, y la ficha dice por que.
	var upg := HelpText.upgrades_page()
	assert_str(upg).contains(_data("shipyard").get_display_name())
	assert_str(HelpText.no_upgrade_text(_data("shipyard"))).contains(_data("shipyard").get_display_name())
	assert_str(HelpText.no_upgrade_text(_data("aerodrome"))).contains(_data("aerodrome").get_display_name())

func test_the_eras_page_puts_each_new_building_in_its_era() -> void:
	# Por requisitos, no solo por coste: el Aerodromo y el Deposito de
	# combustible piden la Refineria; el Astillero, la Fundicion.
	assert_int(HelpText.build_era(_data("shipyard"))).is_equal(2)
	assert_int(HelpText.build_era(_data("aerodrome"))).is_equal(3)
	assert_int(HelpText.build_era(_data("fuel_depot"))).is_equal(3)
	assert_int(HelpText.build_era(_data("foundry"))).is_equal(2)
	assert_int(HelpText.build_era(_data("barracks"))).is_equal(1)
	var body := HelpText.eras_page()
	var e2 := body.find("Era 2")
	var e3 := body.find("Era 3")
	assert_int(e2).is_greater(0)
	assert_int(e3).is_greater(e2)
	var shipyard := body.find(_data("shipyard").get_display_name())
	assert_int(shipyard).is_greater(e2)
	assert_int(shipyard).is_less(e3)
	assert_int(body.rfind(_data("aerodrome").get_display_name())).is_greater(e3)
	# Las tropas dicen donde se entrenan.
	assert_str(body).contains("(%s)" % _data("shipyard").get_display_name())
	assert_str(body).contains("(%s)" % _data("barracks").get_display_name())
