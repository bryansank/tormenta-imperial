extends GdUnitTestSuite
## Aire y mar en la colonia (feat/aire-mar-reglas): cada unidad se entrena en su
## edificio (Cuartel, Astillero, Aerodromo), con un hueco por edificio solo para
## las suyas; la capacidad suma los tres; el Astillero va en la costa; y los
## barcos solo salen a misiones con agua. ArmyManager lee la escena actual
## (BuildingPlacer), asi que se aparca uno de mentira durante cada caso.

class FakePlacer extends Node:
	var counts: Dictionary = {}
	func count_building(building_id: String) -> int:
		return int(counts.get(building_id, 0))

const PlacementRules := preload("res://scripts/buildings/PlacementRules.gd")
const HelpCatalog := preload("res://scripts/ui/HelpCatalog.gd")

var _placer: FakePlacer
var _scene: Node
var _made_scene := false
var _saved_army: Dictionary = {}
var _saved_era := 1

func before_test() -> void:
	_saved_army = ArmyManager.get_save_data()
	_saved_era = ProgressionManager.current_era
	ArmyManager.reset()
	ProgressionManager.current_era = 3
	_scene = get_tree().current_scene
	if _scene == null:
		_scene = Node.new()
		_scene.name = "AirSeaArmyTestScene"
		get_tree().root.add_child(_scene)
		get_tree().current_scene = _scene
		_made_scene = true
	_placer = FakePlacer.new()
	_placer.name = "BuildingPlacer"
	_scene.add_child(_placer)

func after_test() -> void:
	_scene.remove_child(_placer)
	_placer.free()
	if _made_scene:
		get_tree().current_scene = null
		get_tree().root.remove_child(_scene)
		_scene.free()
	ProgressionManager.current_era = _saved_era
	ArmyManager.load_save_data(_saved_army)

# ── Donde se entrena cada una ────────────────────────────────────────

func test_ships_need_a_shipyard_and_planes_an_aerodrome() -> void:
	_placer.counts = {"barracks": 1}
	assert_str(String(ArmyManager.can_train("gunboat")["reason"])).is_equal("LBL_ARMY_NEED_SHIPYARD")
	assert_str(String(ArmyManager.can_train("fighter")["reason"])).is_equal("LBL_ARMY_NEED_AERODROME")
	_placer.counts = {"shipyard": 1}
	assert_str(String(ArmyManager.can_train("infantry")["reason"])).is_equal("LBL_ARMY_NEED_BARRACKS")
	assert_str(String(ArmyManager.can_train("gunboat")["reason"])).is_not_equal("LBL_ARMY_NEED_SHIPYARD")

func test_each_building_has_its_own_training_slots() -> void:
	_placer.counts = {"barracks": 1, "shipyard": 1}
	assert_int(ArmyManager.max_slots()).is_equal(2)
	assert_int(ArmyManager.max_slots("shipyard")).is_equal(1)
	# Un soldado en el Cuartel no ocupa el Astillero.
	ArmyManager._training.append({"id": "infantry", "remaining": 10.0, "duration": 10.0})
	assert_int(ArmyManager.training_in("barracks")).is_equal(1)
	assert_int(ArmyManager.training_in("shipyard")).is_equal(0)
	assert_str(String(ArmyManager.can_train("artillery")["reason"])).is_equal("LBL_ARMY_SLOTS_FULL")
	assert_str(String(ArmyManager.can_train("gunboat")["reason"])).is_not_equal("LBL_ARMY_SLOTS_FULL")
	ArmyManager._training.clear()

func test_capacity_adds_the_three_buildings() -> void:
	_placer.counts = {"barracks": 1, "shipyard": 1, "aerodrome": 1}
	var want: int = GameConfig.army_base_capacity + GameConfig.army_capacity_per_barracks \
		+ int(GameConfig.army_capacity_per_building["shipyard"]) + int(GameConfig.army_capacity_per_building["aerodrome"])
	assert_int(ArmyManager.get_capacity()).is_equal(want)
	# Solo con Cuarteles, lo de siempre.
	_placer.counts = {"barracks": 2}
	assert_int(ArmyManager.get_capacity()).is_equal(GameConfig.get_army_capacity(2))

func test_any_military_building_opens_the_army() -> void:
	_placer.counts = {}
	assert_bool(ArmyManager.has_military_building()).is_false()
	_placer.counts = {"shipyard": 1}
	assert_bool(ArmyManager.has_military_building()).is_true()

func test_an_old_save_without_ships_loads_as_before() -> void:
	ArmyManager.load_save_data({"units": {"infantry": 3, "artillery": 2}, "training": [{"id": "vehicle", "remaining": 5.0, "duration": 100.0}]})
	assert_int(ArmyManager.get_count("infantry")).is_equal(3)
	assert_int(ArmyManager.get_count("gunboat")).is_equal(0)
	assert_int(ArmyManager.training_in("barracks")).is_equal(1)

# ── Los edificios ────────────────────────────────────────────────────

func test_the_two_buildings_exist_with_their_rules() -> void:
	for id in ["shipyard", "aerodrome"]:
		var data: BuildingData = PlacementRules.load_building_data(id)
		assert_object(data).is_not_null()
		assert_that(data.grid_size).is_equal(Vector2i(2, 2))
		assert_int(data.workers_required).is_greater(0)
		assert_bool(GameConfig.construction_style.has(id)).is_true()
		assert_int(GameConfig.base_building_limit(id, 1)).is_equal(int(GameConfig.building_limits[id]))
	assert_array(GameConfig.get_prerequisites("shipyard")).contains(["foundry"])
	assert_array(GameConfig.get_prerequisites("aerodrome")).contains(["refinery"])
	assert_bool(PlacementRules.needs_shore("shipyard")).is_true()
	assert_bool(PlacementRules.needs_shore("aerodrome")).is_false()
	assert_bool((PlacementRules.load_building_data("aerodrome").cost_materials as Dictionary).has("fuel")).is_true()
	assert_bool((PlacementRules.load_building_data("shipyard").cost_materials as Dictionary).has("beams")).is_true()

# ── A donde salen los barcos ─────────────────────────────────────────

func test_ships_only_launch_to_a_mission_with_water() -> void:
	var party := {"gunboat": 1, "infantry": 1}
	assert_bool(CombatManager.party_has_ships(party)).is_true()
	assert_bool(CombatManager.party_has_ships({"infantry": 2, "fighter": 1})).is_false()
	var dock := {"id": 1, "kind": "expedition", "seed": 10, "era": 2, "blueprint": ""}
	var factory := {"id": 2, "kind": "expedition", "seed": 11, "era": 2, "blueprint": ""}
	assert_bool(CombatManager.offer_has_water(dock)).is_true()
	assert_bool(CombatManager.offer_has_water(factory)).is_false()
	assert_bool(CombatManager.offer_has_water({"kind": "first"})).is_false()

func test_home_boards_have_water_only_with_ships_in_the_garrison() -> void:
	var soldiers: Array = [CombatUnit.create(1, "infantry", 0), CombatUnit.create(2, "fighter", 0)]
	assert_dict(CombatManager.home_terrain(soldiers)).is_empty()
	var navy: Array = [CombatUnit.create(1, "infantry", 0), CombatUnit.create(2, "gunboat", 0)]
	assert_bool(CombatRules.has_water(CombatManager.home_terrain(navy))).is_true()
	# Los barcos enemigos no traen el agua a tu casa: la trae tu flota.
	var raiders: Array = [CombatUnit.create(1, "infantry", 0), CombatUnit.create(2, "gunboat", 1)]
	assert_dict(CombatManager.home_terrain(raiders)).is_empty()

# ── ¿QUE HACER? ──────────────────────────────────────────────────────

func test_the_fleet_tips_are_in_both_languages() -> void:
	for key in ["OBJ_WHY_SHIPYARD", "OBJ_WHY_AERODROME", "HELP_T_AIR_SEA", "HELP_B_AIR_SEA",
			"HELP_T_AIR_SEA_ADVANTAGE", "HELP_B_AIR_SEA_ADVANTAGE", "LBL_ARMY_NEED_SHIPYARD",
			"LBL_ARMY_NEED_AERODROME", "MSG_SHIPS_NEED_WATER", "LBL_SORTIE_COASTAL",
			"BLD_SHIPYARD_NAME", "BLD_AERODROME_NAME", "LBL_DOMAIN_SEA", "LBL_DOMAIN_AIR"]:
		for locale in ["es", "en"]:
			assert_bool(Tr._STRINGS[locale].has(key)).override_failure_message("%s/%s" % [locale, key]).is_true()
	assert_bool(HelpCatalog.has("air_sea")).is_true()
	assert_bool(HelpCatalog.has("guide_air_sea_advantage")).is_true()
	assert_bool(HelpCatalog.is_basic("guide_air_sea_advantage")).is_true()

func test_the_reasons_fit_in_a_line() -> void:
	for key in ["LBL_ARMY_NEED_SHIPYARD", "LBL_ARMY_NEED_AERODROME", "MSG_SHIPS_NEED_WATER"]:
		for locale in ["es", "en"]:
			var words: int = String(Tr._STRINGS[locale][key]).split(" ", false).size()
			assert_int(words).override_failure_message("%s/%s" % [locale, key]).is_less_equal(10)
