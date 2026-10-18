extends GdUnitTestSuite
## Muelle de pesca (feat/muelle-pesca, doc 21 §6.3 n.º 7): era 1, 2x2, comida
## desde el agua, en la orilla tocando un banco de peces. Fija la receta de
## "Adding a New Building" (datos, topes, regla, taller, obra, parcela, textos,
## ayuda, modelo horneado y dibujo 2D) y sus reglas propias (el Nucleo no repite
## su proceso, el pescado fresco se estropea antes en Gobernador).
##
## Escrita sin correr (regla de Bryan: un solo pase de pruebas al final).
## Toca el GridManager real y GameConfig: cada prueba deja lo que cambia.

const MapGen := preload("res://scripts/map/MapGenerator.gd")
const Rules := preload("res://scripts/buildings/PlacementRules.gd")
const Assist := preload("res://scripts/buildings/PlacementAssist.gd")
const Art := preload("res://scripts/view2d/BuildingArt2D.gd")
const HelpCat := preload("res://scripts/ui/HelpCatalog.gd")
const ID := "fishing_dock"

var _map: Node = null
var _nucleo: Node3D = null
var _saved_spoil := 1.0

func before_test() -> void:
	GridManager.clear_all()
	GridManager.reset_size()
	_map = auto_free(MapGen.new())
	add_child(_map)
	_nucleo = auto_free(Node3D.new())
	_saved_spoil = GameConfig.food_spoil_delay_mult

func after_test() -> void:
	if is_instance_valid(_map):
		_map.clear_all_deposits()
	GridManager.clear_all()
	GridManager.reset_size()
	GameConfig.food_spoil_delay_mult = _saved_spoil

func _data() -> BuildingData:
	return load("res://data/buildings/%s.tres" % ID) as BuildingData

func _new_map(map_seed: int) -> void:
	_map.clear_all_deposits()
	GridManager.clear_all()
	seed(map_seed)
	GridManager.roll_new_map()
	GridManager.place_obstacle(_map.core_origin(), _nucleo, Vector2i(3, 3))
	_map.generate_new_map()

# ── Datos ─────────────────────────────────────────────────────────────

func test_the_building_is_a_cheap_era_one_food_producer() -> void:
	var d := _data()
	assert_object(d).is_not_null()
	assert_str(d.id).is_equal(ID)
	assert_that(d.grid_size).is_equal(Vector2i(2, 2))
	assert_bool(d.is_decoration).is_false()
	assert_int(d.cost_gold).is_equal(60)
	assert_int(d.cost_wood).is_equal(40)
	assert_int(d.cost_steel + d.cost_oil).is_equal(0)
	assert_bool(d.cost_materials.is_empty()).is_true()
	assert_int(d.workers_required).is_equal(2)
	assert_that(d.get_production()).is_equal({"food": 12})
	assert_float(d.production_interval).is_equal(30.0)
	assert_object(d.model_scene).is_not_null()

func test_it_yields_less_per_minute_than_a_long_farm_crop() -> void:
	# Pesca sin esperar cultivo: por debajo del Trigo, por encima de la Lechuga.
	var d := _data()
	var per_min := float(d.produces_food) * 60.0 / d.production_interval
	var short: Dictionary = GameConfig.get_crop("crop_short")
	var long: Dictionary = GameConfig.get_crop("crop_long")
	assert_float(per_min).is_greater(float(short["food"]) * 60.0 / float(short["duration"]))
	assert_float(per_min).is_less(float(long["food"]) * 60.0 / float(long["duration"]))

func test_caps_rise_with_the_core_and_level_one_matches_the_flat_table() -> void:
	# 1.2 (feat/nucleo-y-planos): los topes van con el Nucleo, y lo abre el 2.
	assert_array(GameConfig.core_level_limits[ID]).is_equal([3, 3, 4, 6, 6])
	assert_int(int(GameConfig.building_limits[ID])).is_equal(3)
	for lv in range(1, GameConfig.core_level_max + 1):
		assert_int(GameConfig.base_building_limit(ID, lv)).is_equal([3, 3, 4, 6, 6][lv - 1])
	assert_int(GameConfig.core_level_unlock(ID)).is_equal(2)

func test_it_has_lot_site_fx_and_stock_cap() -> void:
	assert_bool(GameConfig.building_lot_style.has(ID)).is_true()
	assert_bool(GameConfig.construction_style.has(ID)).is_true()
	assert_str(String(GameConfig.building_active_fx.get(ID, ""))).is_equal("smoke")
	assert_int(GameConfig.get_stock_cap(ID, 1)).is_equal(GameConfig.fishing_dock_stock_cap)
	assert_bool(GameConfig.upgrade_parts_buildings.has(ID)).is_true()
	# Sin requisitos: un banco de peces y una carretera bastan.
	assert_bool(GameConfig.get_prerequisites(ID).is_empty()).is_true()

func test_it_must_touch_a_school_of_fish() -> void:
	var rule: Dictionary = GameConfig.get_deposit_rule(ID)
	assert_str(String(rule["deposit"])).is_equal("fish_shoal")
	assert_int(int(rule["reach"])).is_equal(1)
	assert_bool(bool(rule["consumes"])).is_false()
	assert_str(String(rule["message"])).is_equal("LBL_NEEDS_FISH_NEAR")
	# La regla del banco ya pone el muelle en la costa: no hace falta la de las palmeras.
	assert_bool(Rules.needs_shore(ID)).is_false()
	assert_str(Assist.rule_text(ID)).is_equal(Tr.t("LBL_NEEDS_FISH_NEAR"))

# ── Taller ────────────────────────────────────────────────────────────

func test_smoking_fish_turns_wood_into_food_and_the_core_does_not_repeat_it() -> void:
	var procs: Array = GameConfig.get_processes_for(ID)
	assert_int(procs.size()).is_equal(1)
	assert_str(String(procs[0]["id"])).is_equal("smoke_fish")
	assert_that(procs[0]["cost"]).is_equal({"wood": 15})
	assert_that(procs[0]["produces"]).is_equal({"food": 25})
	assert_bool(GameConfig.core_skip_workshops.has(ID)).is_true()
	for p in GameConfig.get_core_extra_processes():
		assert_str(String(p.get("from", ""))).is_not_equal(ID)

func test_fresh_fish_spoils_in_half_the_time_and_the_silo_helps() -> void:
	GameConfig.food_spoil_delay_mult = 1.0
	assert_float(GameConfig.spoil_after_for(ID)).is_equal(GameConfig.spoil_after_seconds * GameConfig.fishing_dock_spoil_mult)
	GameConfig.food_spoil_delay_mult = GameConfig.silo_spoil_delay_mult
	assert_float(GameConfig.spoil_after_for(ID)).is_equal(
		GameConfig.spoil_after_seconds * GameConfig.fishing_dock_spoil_mult * GameConfig.silo_spoil_delay_mult)
	# Lo de los demas no cambia.
	assert_float(GameConfig.spoil_after_for("sawmill")).is_equal(GameConfig.spoil_after_seconds)

# ── Colocar ───────────────────────────────────────────────────────────

func test_it_goes_on_the_shore_next_to_a_school_and_nowhere_else() -> void:
	_new_map(42)
	var spots: Array = _map.buildable_spots_near("fish_shoal", Vector2i(2, 2), 1)
	assert_bool(spots.is_empty()).is_false()
	var spot: Dictionary = spots[0]
	var ok: Dictionary = Rules.evaluate_placement(ID, spot["origin"], spot["size"], _map)
	assert_bool(bool(ok["ok"])).is_true()
	assert_str(String((ok["deposit"] as Node).get_meta("deposit_id", ""))).is_equal("fish_shoal")
	# Tocar el banco es tocar el agua.
	assert_bool(Rules.touches_shore(spot["origin"], spot["size"])).is_true()
	# Tierra adentro, junto al Nucleo: no hay banco.
	var inland: Vector2i = _map.core_origin() + Vector2i(5, 0)
	var bad: Dictionary = Rules.evaluate_placement(ID, inland, Vector2i(2, 2), _map)
	assert_bool(bool(bad["ok"])).is_false()
	assert_str(String(bad["reason"])).is_equal("deposit")

func test_touch_placement_offers_spots_around_the_schools() -> void:
	_new_map(42)
	var origins: Array = Assist.valid_spots(ID, Vector2i(2, 2), _map)
	assert_bool(origins.is_empty()).is_false()
	for o in origins:
		assert_bool(Rules.touches_shore(o, Vector2i(2, 2))).is_true()

func test_the_dock_has_its_vein_while_the_school_is_there() -> void:
	_new_map(42)
	var spot: Dictionary = _map.buildable_spots_near("fish_shoal", Vector2i(2, 2), 1)[0]
	assert_bool(Rules.has_its_deposit(_data(), GridManager.cells_for(spot["origin"], spot["size"]), _map)).is_true()

# ── Aspecto, textos y ayuda ───────────────────────────────────────────

func test_the_baked_model_has_its_smoke_anchor() -> void:
	var scene: PackedScene = load("res://assets/models/toy/fishing_dock.tscn")
	assert_object(scene).is_not_null()
	var root := scene.instantiate()
	assert_bool(root is MeshInstance3D).is_true()
	assert_object(root.get_node_or_null("FxAnchor")).is_not_null()
	var a: AABB = (root as MeshInstance3D).mesh.get_aabb()
	assert_float(a.size.x).is_less_equal(3.0)
	assert_float(a.size.z).is_less_equal(3.0)
	root.free()

func test_the_2d_drawing_has_its_own_chimney() -> void:
	assert_array(Art.fx_anchors(ID)).is_equal([Vector2(0.2, 0.08)])

func test_texts_exist_in_both_languages() -> void:
	var before := Tr.get_locale()
	for locale in ["es", "en"]:
		Tr.set_locale(locale)
		for key in ["BLD_FISHING_DOCK_NAME", "BLD_FISHING_DOCK_DESC", "LBL_NEEDS_FISH_NEAR",
				"PROC_SMOKE_FISH", "HELP_T_FISHING_DOCK", "HELP_B_FISHING_DOCK", "OBJ_WHY_FISHING_DOCK"]:
			assert_str(Tr.t(key)).override_failure_message(key).is_not_equal(key)
	Tr.set_locale(before)

func test_its_tip_is_in_the_help_index_and_in_the_tutorial() -> void:
	assert_bool(HelpCat.ENTRIES.has(ID)).is_true()
	assert_str(String(HelpCat.ENTRIES[ID]["kind"])).is_equal("tip")
	assert_bool(TutorialManager.TIPS.has(ID)).is_true()
