extends GdUnitTestSuite
## El Cuartel temprano (decision de Bryan, 2026-10-17, rama feat/cuartel-temprano).
##
## El Cuartel pasa a la era 1 y sin acero: 120 oro + 80 madera + 10 tablones,
## un trabajador, y solo pide el Aserradero (de donde salen sus tablones). Entrena
## Infanteria ya; la Artilleria y el Tanque siguen con su era, y el panel de
## EJERCITO dice que los abre. En ¿QUE HACER? va justo despues del aserradero.
## Detalle y cifras en docs/03, docs/14 y docs/22.

const Objectives := preload("res://scripts/services/Objectives.gd")
const ArmyPanelScript := preload("res://scripts/ui/ArmyPanel.gd")
const BARRACKS := preload("res://data/buildings/barracks.tres")
const PlacementRules := preload("res://scripts/buildings/PlacementRules.gd")

var _saved_mode: int = GameMode.DEFAULT
var _saved_era: int = 1

func before_test() -> void:
	_saved_mode = GameMode.current
	_saved_era = ProgressionManager.current_era

func after_test() -> void:
	GameMode.begin_run(_saved_mode)
	ProgressionManager.current_era = _saved_era

# ── El edificio ──────────────────────────────────────────────────────

func test_the_barracks_costs_no_steel() -> void:
	assert_int(BARRACKS.cost_gold).is_equal(120)
	assert_int(BARRACKS.cost_steel).is_equal(0)
	assert_int(BARRACKS.cost_oil).is_equal(0)
	assert_int(BARRACKS.cost_wood).is_equal(80)
	assert_int(int(BARRACKS.cost_materials.get("planks", 0))).is_equal(10)
	assert_bool(BARRACKS.get_cost().has(ResourceManager.Type.STEEL)).is_false()

## Aserradero (2) + Cuartel + Granja (2) caben en los 5 del Nucleo: el Cuartel
## no deja a la Granja sin gente al principio.
func test_the_barracks_fits_with_the_first_sawmill_and_farm() -> void:
	var sawmill: BuildingData = load("res://data/buildings/sawmill.tres")
	var farm: BuildingData = load("res://data/buildings/farm.tres")
	var used: int = sawmill.workers_required + BARRACKS.workers_required + farm.workers_required
	assert_int(used).is_less_equal(GameConfig.population_start)

func test_it_only_needs_the_sawmill() -> void:
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	assert_array(GameConfig.get_prerequisites("barracks")).contains_exactly(["sawmill"])
	# La Torre pide acero y vigas: sin Fundicion no tiene sentido pedirla.
	assert_array(GameConfig.get_prerequisites("tower")).contains(["barracks", "foundry"])
	# La Refineria sigue pidiendo el Cuartel.
	assert_array(GameConfig.get_prerequisites("refinery")).contains(["barracks"])

func test_barracks_have_no_cap_in_any_era() -> void:
	# Sin tope de Cuarteles (Bryan, 18-10-2026): el freno es el del ejercito.
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	for era in range(1, GameConfig.max_era() + 1):
		assert_int(GameConfig.get_building_limit_for_era("barracks", era)).is_equal(-1)
	assert_bool(GameConfig.building_limits_by_era.has("barracks")).is_false()
	assert_dict(GameConfig.next_building_limit("barracks")).is_empty()

# ── Las unidades ─────────────────────────────────────────────────────

func test_only_infantry_trains_in_era_one() -> void:
	ProgressionManager.current_era = 1
	assert_bool(ArmyManager.is_unlocked("infantry")).is_true()
	assert_bool(ArmyManager.is_unlocked("artillery")).is_false()
	assert_bool(ArmyManager.is_unlocked("vehicle")).is_false()
	ProgressionManager.current_era = 2
	assert_bool(ArmyManager.is_unlocked("artillery")).is_true()
	assert_bool(ArmyManager.is_unlocked("vehicle")).is_false()

## La fila apagada de EJERCITO dice que la abre, no "era superior".
func test_the_army_panel_says_what_unlocks_each_unit() -> void:
	var saved := Tr.get_locale()
	for loc in ["es", "en"]:
		Tr.set_locale(loc)
		var art: String = ArmyPanelScript.blocked_text("artillery", "LBL_ARMY_LOCKED")
		var tank: String = ArmyPanelScript.blocked_text("vehicle", "LBL_ARMY_LOCKED")
		assert_str(art).is_equal(Tr.t("LBL_ARMY_LOCKED_ERA_2"))
		assert_str(tank).is_equal(Tr.t("LBL_ARMY_LOCKED_ERA_3"))
		assert_str(art).is_not_equal("LBL_ARMY_LOCKED_ERA_2")
		assert_str(art).contains(PlacementRules.load_building_data("foundry").get_display_name())
		assert_str(tank).contains(PlacementRules.load_building_data("refinery").get_display_name())
		# En una linea, como el resto de motivos (test_menos_texto_ejercito).
		assert_int(art.split(" ", false).size()).is_less_equal(7)
		assert_int(tank.split(" ", false).size()).is_less_equal(7)
		# Cualquier otro motivo, tal cual.
		assert_str(ArmyPanelScript.blocked_text("infantry", "LBL_ARMY_SLOTS_FULL")).is_equal(Tr.t("LBL_ARMY_SLOTS_FULL"))
	Tr.set_locale(saved)

# ── ¿QUE HACER? ──────────────────────────────────────────────────────

func _line_index(kind: String, id: String, needs: String = "") -> int:
	for i in Objectives.LINE.size():
		var e: Dictionary = Objectives.LINE[i]
		if String(e["kind"]) == kind and String(e["id"]) == id and String(e.get("needs", "")) == needs:
			return i
	return -1

func test_the_barracks_comes_right_after_the_sawmill() -> void:
	var sawmill := _line_index("build", "sawmill")
	var barracks := _line_index("build", "barracks", "tithe")
	assert_int(sawmill).is_equal(0)
	assert_int(barracks).is_equal(sawmill + 1)
	# Antes de la Granja, la Mina y la Fundicion.
	assert_int(barracks).is_less(_line_index("build", "farm"))
	assert_int(barracks).is_less(_line_index("build", "gold_mine"))
	assert_int(barracks).is_less(_line_index("build", "foundry"))
	# Y un soldado antes de la Mina (la tormenta de prueba llega hacia el min 5).
	var soldier := -1
	for i in Objectives.LINE.size():
		var e: Dictionary = Objectives.LINE[i]
		if String(e["kind"]) == "train" and String(e.get("why", "")) == "OBJ_WHY_FIRST_SOLDIERS":
			soldier = i
	assert_int(soldier).is_greater(barracks)
	assert_int(soldier).is_less(_line_index("build", "gold_mine"))

func test_the_early_barracks_is_only_asked_where_there_is_a_tax() -> void:
	var early: Dictionary = Objectives.LINE[_line_index("build", "barracks", "tithe")]
	var late: Dictionary = Objectives.LINE[_line_index("build", "barracks", "no_tithe")]
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	assert_bool(Objectives._entry_applies(early)).is_true()
	assert_bool(Objectives._entry_applies(late)).is_false()
	GameMode.begin_run(GameMode.Mode.BUILDER)
	assert_bool(Objectives._entry_applies(early)).is_false()
	assert_bool(Objectives._entry_applies(late)).is_true()

func test_the_barracks_is_not_waiting_for_steel_any_more() -> void:
	assert_str(Objectives._needs_unlocked("barracks")).is_equal("gold")
	assert_str(Objectives._needs_unlocked("tower")).is_equal("oil")

func test_why_the_barracks_is_wanted_early_is_said_plainly() -> void:
	# Por que pronto: los Cobradores del Impuesto (y las misiones con botin).
	assert_str(Tr._STRINGS["es"]["OBJ_WHY_BARRACKS"]).contains("Cobradores")
	assert_str(Tr._STRINGS["en"]["OBJ_WHY_BARRACKS"]).contains("Collectors")
	for loc in ["es", "en"]:
		var tip: String = Tr._STRINGS[loc]["HELP_TIP_BARRACKS_BODY"]
		# Donde se entrena de verdad: ☰ MENU > COLONIA > EJERCITO.
		assert_str(tip).contains(Tr._STRINGS[loc]["LBL_MENU_GROUP_COLONY"])
		assert_str(tip).contains(Tr._STRINGS[loc]["BTN_ARMY"])
		assert_str(Tr._STRINGS[loc]["TUT_TIP_BARRACKS_BODY"]).contains(Tr._STRINGS[loc]["BTN_ARMY"])
		# Ya no dice "infanteria (era 1)" como si el Cuartel fuera de la era 2.
		assert_str(tip.to_lower()).not_contains("(era 1)")

# ── El freno del ejercito sin tope de Cuarteles (2026-10-18) ─────────

func test_army_capacity_grows_less_after_the_first_barracks_and_has_a_ceiling() -> void:
	var full := GameConfig.army_full_capacity_barracks
	# Los primeros, +8 cada uno, como siempre.
	assert_int(GameConfig.get_army_capacity(0)).is_equal(GameConfig.army_base_capacity)
	assert_int(GameConfig.get_army_capacity(full)).is_equal(
		GameConfig.army_base_capacity + GameConfig.army_capacity_per_barracks * full)
	# Los siguientes, menos.
	assert_int(GameConfig.army_capacity_gain(full)).is_equal(GameConfig.army_capacity_per_extra_barracks)
	assert_int(GameConfig.army_capacity_per_extra_barracks).is_less(GameConfig.army_capacity_per_barracks)
	# Y un techo que no se pasa con ningun numero de cuarteles.
	for n in [10, 25, 100]:
		assert_int(GameConfig.get_army_capacity(n)).is_equal(GameConfig.army_capacity_max)
	assert_int(GameConfig.army_capacity_gain(100)).is_equal(0)
	# Nunca menos de lo que daban 5 cuarteles con el tope de antes (3/4/5).
	assert_int(GameConfig.army_capacity_max).is_greater_equal(GameConfig.get_army_capacity(5))

func test_training_slots_are_one_per_barracks_up_to_a_ceiling() -> void:
	assert_int(GameConfig.get_army_training_slots(0)).is_equal(0)
	assert_int(GameConfig.get_army_training_slots(2)).is_equal(2)
	assert_int(GameConfig.get_army_training_slots(50)).is_equal(GameConfig.army_training_slots_max)

func test_the_army_tooltips_say_the_ceilings() -> void:
	for loc in ["es", "en"]:
		var cap: String = Tr._STRINGS[loc]["LBL_ARMY_CAPACITY_HINT"] % [GameConfig.army_base_capacity,
			GameConfig.army_capacity_per_barracks, GameConfig.army_full_capacity_barracks,
			GameConfig.army_capacity_per_extra_barracks, GameConfig.army_capacity_max]
		assert_str(cap).contains(str(GameConfig.army_capacity_max))
		var slots: String = Tr._STRINGS[loc]["LBL_ARMY_SLOTS_HINT"] % GameConfig.army_training_slots_max
		assert_str(slots).contains(str(GameConfig.army_training_slots_max))
