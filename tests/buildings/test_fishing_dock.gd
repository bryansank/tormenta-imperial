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
	# El banco da comida y oro en la misma fuente (fix/peces-en-el-mar).
	assert_that(d.get_production()).is_equal({"food": 12, "gold": 3})
	assert_float(d.production_interval).is_equal(30.0)
	assert_object(d.model_scene).is_not_null()

func test_it_yields_less_per_minute_than_a_long_farm_crop() -> void:
	# Pesca sin esperar cultivo: por debajo del Trigo, por encima de la Lechuga.
	var d := _data()
	var per_min := float(d.produces_food) * 60.0 / d.production_interval
	# Su oro es una propina: menos de una quinta parte de lo que da una Mina.
	var mine: BuildingData = load("res://data/buildings/gold_mine.tres")
	assert_float(float(d.produces_gold) / d.production_interval).is_less(
		0.2 * float(mine.produces_gold) / mine.production_interval)
	var short: Dictionary = GameConfig.get_crop("crop_short")
	var long: Dictionary = GameConfig.get_crop("crop_long")
	assert_float(per_min).is_greater(float(short["food"]) * 60.0 / float(short["duration"]))
	assert_float(per_min).is_less(float(long["food"]) * 60.0 / float(long["duration"]))

func test_caps_rise_with_the_era_and_era_one_matches_the_flat_table() -> void:
	assert_array(GameConfig.building_limits_by_era[ID]).is_equal([3, 4, 6])
	assert_int(int(GameConfig.building_limits[ID])).is_equal(3)
	for era in [1, 2, 3]:
		assert_int(GameConfig.base_building_limit(ID, era)).is_equal([3, 4, 6][era - 1])

func test_it_has_lot_site_fx_and_stock_cap() -> void:
	assert_bool(GameConfig.building_lot_style.has(ID)).is_true()
	assert_bool(GameConfig.construction_style.has(ID)).is_true()
	assert_str(String(GameConfig.building_active_fx.get(ID, ""))).is_equal("smoke")
	assert_int(GameConfig.get_stock_cap(ID, 1)).is_equal(GameConfig.fishing_dock_stock_cap)
	assert_bool(GameConfig.upgrade_parts_buildings.has(ID)).is_true()
	# Sin requisitos: un banco de peces y una carretera bastan.
	assert_bool(GameConfig.get_prerequisites(ID).is_empty()).is_true()

func test_it_reaches_a_school_out_at_sea_from_the_coast() -> void:
	var rule: Dictionary = GameConfig.get_deposit_rule(ID)
	assert_str(String(rule["deposit"])).is_equal("fish_shoal")
	assert_int(int(rule["reach"])).is_equal(4)
	assert_int(int(rule["reach"])).is_equal(GameConfig.fishing_dock_reach)
	assert_bool(bool(rule["consumes"])).is_false()
	assert_bool(bool(rule["shore"])).is_true()
	assert_int(int(rule["per_deposit"])).is_equal(2)
	assert_str(String(rule["message"])).is_equal("LBL_NEEDS_FISH_NEAR")
	# Va en la costa por su propia regla ("shore"), con su frase, no la de las palmeras.
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
	var spots: Array = _map.buildable_spots_near("fish_shoal", Vector2i(2, 2), GameConfig.fishing_dock_reach)
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
	var spot: Dictionary = _map.buildable_spots_near("fish_shoal", Vector2i(2, 2), GameConfig.fishing_dock_reach)[0]
	assert_bool(Rules.has_its_deposit(_data(), GridManager.cells_for(spot["origin"], spot["size"]), _map)).is_true()

## Pone un muelle de verdad en la rejilla (sin vista) en `origin`.
func _put_dock(origin: Vector2i) -> Node3D:
	var node: Node3D = auto_free(Node3D.new())
	assert_bool(GridManager.place_building(origin, _data(), node)).is_true()
	return node

## Los sitios validos que alcanzan a `shoal` (y a ningun otro banco).
func _spots_only_for(shoal: Node) -> Array:
	var out: Array = []
	for o in Assist.valid_spots(ID, Vector2i(2, 2), _map):
		var near: Array = _map.find_deposits_near_cells("fish_shoal", GridManager.cells_for(o, Vector2i(2, 2)), GameConfig.fishing_dock_reach)
		if near.size() == 1 and near[0] == shoal:
			out.append(o)
	return out

func test_inland_within_reach_is_not_the_coast() -> void:
	# Al alcance del banco pero sin tocar el agua: no vale (va en la costa).
	for s in [42, 7, 99, 314]:
		_new_map(s)
		for spot in _map.buildable_spots_near("fish_shoal", Vector2i(2, 2), GameConfig.fishing_dock_reach):
			assert_bool(Rules.touches_shore(spot["origin"], spot["size"])).is_true()
		for y in range(GridManager.grid_height - 1):
			for x in range(GridManager.grid_width - 1):
				var o := Vector2i(x, y)
				if Rules.touches_shore(o, Vector2i(2, 2)) or not Rules.on_land(o, Vector2i(2, 2)):
					continue
				var v: Dictionary = Rules.evaluate_placement(ID, o, Vector2i(2, 2), _map)
				assert_bool(bool(v["ok"])).override_failure_message("semilla %d: muelle tierra adentro en %s" % [s, o]).is_false()

func test_a_school_feeds_two_docks_not_three() -> void:
	# Busca un banco con tres sitios suyos que no se pisen.
	for s in [42, 7, 99, 314, 2718, 4242]:
		_new_map(s)
		for d in _map.get_all_deposits():
			if String(d["id"]) != "fish_shoal":
				continue
			var shoal: Node = GridManager.get_building_at(Vector2i(d["cell_x"], d["cell_y"]))
			var picked: Array = []
			for o in _spots_only_for(shoal):
				var free := true
				for p in picked:
					if Rect2i(p, Vector2i(2, 2)).grow(1).intersects(Rect2i(o, Vector2i(2, 2))):
						free = false
				if free:
					picked.append(o)
				if picked.size() == 3:
					break
			if picked.size() < 3:
				continue
			_put_dock(picked[0])
			_put_dock(picked[1])
			var third: Dictionary = Rules.evaluate_placement(ID, picked[2], Vector2i(2, 2), _map)
			assert_bool(bool(third["ok"])).is_false()
			assert_str(String(third["reason"])).is_equal("deposit")
			# Moviendo uno de los dos, el sitio del tercero vale para el.
			var moving: Node = GridManager.get_building_at(picked[1])
			var moved: Dictionary = Rules.evaluate_placement(ID, picked[2], Vector2i(2, 2), _map, moving)
			assert_bool(moved["deposit"] == shoal).is_true()
			return
	fail("ningun banco con tres sitios suyos en las semillas probadas")

func test_the_pier_crosses_the_water_to_the_school() -> void:
	_new_map(42)
	var spot: Dictionary = _map.buildable_spots_near("fish_shoal", Vector2i(2, 2), GameConfig.fishing_dock_reach)[0]
	var cells: Array = GridManager.cells_for(spot["origin"], spot["size"])
	var path: Dictionary = _map.pier_path(cells)
	var pier: Array = path["cells"]
	assert_int(pier.size()).is_between(1, GameConfig.fishing_dock_reach - 1)
	for c in pier:
		assert_bool(GridManager.is_water_cell(c)).is_true()
		# No ocupa la rejilla: el agua sigue sin nada encima.
		assert_object(GridManager.get_building_at(c)).is_null()
	assert_bool(cells.has(path["from"])).is_true()
	var shoal: Node = GridManager.get_building_at(path["to"])
	assert_str(String(shoal.get_meta("deposit_id", ""))).is_equal("fish_shoal")

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
