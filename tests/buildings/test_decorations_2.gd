extends GdUnitTestSuite
## Las dieciocho decoraciones restantes del catalogo (feat/decoraciones-y-trafico,
## doc 21 §6.4-6.5): cada una carga, es decoracion sin tope, tiene textos ES/EN,
## obra, parcela, dibujo 2D, una malla 3D de la paleta dentro del presupuesto,
## su rango o su hazana, y las de costa piden la costa. Escritas sin correr
## (regla de Bryan: un pase de pruebas al final).

const Decor := preload("res://scripts/buildings/DecorMesh.gd")
const Decor2 := preload("res://scripts/buildings/DecorMesh2.gd")
const Art := preload("res://scripts/view2d/BuildingArt2D.gd")
const Rules := preload("res://scripts/buildings/PlacementRules.gd")
const Kit := preload("res://tools/toy_kit.gd")

## Rango que abre cada una (doc 21 §6.5); 0 = por hazana.
const RANKS := {"flower_stall": 4, "community_garden": 4, "small_fountain": 5,
	"entrance_arch": 6, "bandstand": 6, "beached_boat": 7, "gear_garden": 7,
	"fair_stage": 8, "fair_tent": 9, "pond_bridge": 10, "water_mill": 10,
	"museum_cannon": 0, "container_mural": 11, "clock_tower": 12, "wreck_monument": 13,
	"storm_column": 0, "moored_airship": 14, "governor_plaza": 18}
const SHORE := ["beached_boat", "wreck_monument"]
## Las que cuestan acero (era 2) y petroleo (era 3).
const ERA3 := ["storm_column", "moored_airship", "governor_plaza"]

func _data(id: String) -> BuildingData:
	return load("res://data/buildings/%s.tres" % id)

func test_the_catalogue_is_complete() -> void:
	assert_int(Decor2.IDS.size()).is_equal(18)
	for id in Decor2.IDS:
		assert_bool(RANKS.has(id)).override_failure_message(id).is_true()
		assert_bool(Decor.handles(id)).override_failure_message(id).is_true()

func test_every_decoration_loads_as_a_decoration() -> void:
	for id in Decor2.IDS:
		var d := _data(id)
		assert_object(d).override_failure_message(id).is_not_null()
		assert_str(d.id).is_equal(id)
		assert_bool(d.is_decoration).override_failure_message(id).is_true()
		assert_int(d.workers_required).is_equal(0)
		assert_bool(d.is_producer()).is_false()
		assert_int(d.morale_bonus).override_failure_message(id).is_between(4, 18)
		var side := 3 if id == "governor_plaza" else 2
		assert_vector(Vector2(d.grid_size)).override_failure_message(id).is_equal(Vector2(side, side))
		if id in ERA3:
			assert_int(d.cost_oil).override_failure_message(id).is_greater(0)
		else:
			assert_int(d.cost_oil).override_failure_message(id).is_equal(0)

func test_decorations_have_no_cap() -> void:
	for id in Decor2.IDS:
		assert_int(GameConfig.get_building_limit(id)).override_failure_message(id).is_equal(-1)

func test_every_decoration_has_its_texts_in_both_languages() -> void:
	for locale in ["es", "en"]:
		Tr.set_locale(locale)
		for id in Decor2.IDS:
			for key in ["BLD_%s_NAME" % id.to_upper(), "BLD_%s_DESC" % id.to_upper()]:
				assert_str(Tr.t(key)).override_failure_message("falta %s en %s" % [key, locale]).is_not_equal(key)
		assert_str(Tr.t("LBL_DEED_TITHES")).is_not_equal("LBL_DEED_TITHES")
	Tr.set_locale("es")

func test_every_decoration_has_its_site_and_lot() -> void:
	for id in Decor2.IDS:
		assert_bool(GameConfig.construction_style.has(id)).override_failure_message(id).is_true()
		assert_bool(GameConfig.building_lot_style.has(id)).override_failure_message(id).is_true()

func test_rank_unlocks_follow_the_plan() -> void:
	for id in Decor2.IDS:
		var want: int = RANKS[id]
		var found := 0
		for r in GameConfig.rank_rewards:
			if id in GameConfig.rank_rewards[r].get("buildings", []):
				found = int(r)
		assert_int(found).override_failure_message(id).is_equal(want)

func test_the_register_keeps_the_old_rank_rows() -> void:
	# Las filas de antes siguen ahi: se anade, no se reescribe.
	assert_array(GameConfig.rank_rewards[2]["buildings"]).contains(["garden", "flower_planter", "hay_cart"])
	assert_array(GameConfig.rank_rewards[5]["buildings"]).contains(["fountain", "flagpole", "small_fountain"])
	assert_array(GameConfig.rank_rewards[13]["buildings"]).contains(["palm_trees", "wreck_monument"])
	assert_float(float(GameConfig.rank_rewards[12]["production"])).is_equal(0.01)

func test_deed_decorations_open_with_refused_taxes() -> void:
	assert_bool(GameConfig.decor_deed_met("museum_cannon", 0)).is_false()
	assert_bool(GameConfig.decor_deed_met("museum_cannon", 1)).is_true()
	assert_bool(GameConfig.decor_deed_met("storm_column", 4)).is_false()
	assert_bool(GameConfig.decor_deed_met("storm_column", 5)).is_true()
	# Lo que no tiene hazana, siempre.
	assert_bool(GameConfig.decor_deed_met("clock_tower", 0)).is_true()

func test_a_deed_lock_says_what_is_missing() -> void:
	if StormManager.tithes_repelled() >= 1:
		return
	assert_bool(Rules.check_rank("museum_cannon")).is_false()
	assert_str(Rules.rank_lock_text("museum_cannon")).contains("0/1")

func test_coast_decorations_need_the_shore() -> void:
	for id in SHORE:
		assert_bool(Rules.needs_shore(id)).override_failure_message(id).is_true()
	assert_bool(Rules.needs_shore("clock_tower")).is_false()
	assert_bool(Rules.needs_shore("palm_trees")).is_true()

func test_every_decoration_has_a_2d_drawing() -> void:
	var names: Array = []
	for m in (Art as GDScript).get_script_method_list():
		names.append(String(m["name"]))
	for id in Decor2.IDS:
		assert_array(names).override_failure_message("sin dibujo 2D: %s" % id).contains(["_d2_" + id])

func test_the_2d_drawing_runs() -> void:
	var canvas: Node2D = auto_free(Node2D.new())
	add_child(canvas)
	var drawn := [0]
	canvas.draw.connect(func():
		for id in Decor2.IDS:
			for rot in 4:
				Art.draw_building(canvas, id, Vector2(64, 64), {"rot": rot, "inset": 8.0, "level": 1 + rot % 3})
				drawn[0] += 1)
	canvas.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(drawn[0]).is_equal(Decor2.IDS.size() * 4)

func test_every_decoration_has_a_shared_palette_mesh_within_budget() -> void:
	for id in Decor2.IDS:
		var mesh := Decor.procedural(id)
		assert_object(mesh).override_failure_message(id).is_not_null()
		var budget := 1500 if id == "governor_plaza" else Decor.TRI_BUDGET
		assert_int(Kit.tri_count(mesh)).override_failure_message(id).is_less_equal(budget)
		assert_object(mesh.surface_get_material(0)).is_same(Decor.MeshKit.solid_material())
		# Al ras del suelo, salvo lo que se hunde a proposito (el bote y el pecio
		# medio enterrados en la arena, el puente y la rueda del molino en el
		# agua del estanque): eso puede bajar hasta 0,4 (el terreno lo tapa).
		var a := mesh.get_aabb()
		var floor_y := -0.4 if id in ["beached_boat", "wreck_monument", "pond_bridge", "water_mill"] else -0.01
		assert_float(a.position.y).override_failure_message(id).is_greater_equal(floor_y)
		var one: MeshInstance3D = auto_free(Decor.instantiate(id))
		var two: MeshInstance3D = auto_free(Decor.instantiate(id))
		assert_object(one.mesh).is_same(two.mesh)

func test_the_baked_meshes_are_within_budget() -> void:
	for id in Decor2.IDS:
		var path := "res://assets/models/toy/%s_mesh.res" % id
		assert_bool(ResourceLoader.exists(path)).override_failure_message("sin hornear: " + id).is_true()
		var mesh: Mesh = load(path)
		var budget := 1500 if id == "governor_plaza" else Decor.TRI_BUDGET
		assert_int(Kit.tri_count(mesh)).override_failure_message(id).is_less_equal(budget)

func test_the_factory_hands_out_the_decoration_mesh() -> void:
	for id in Decor2.IDS:
		var node: Node3D = auto_free(DieselpunkBuildingFactory.create(id, 2.0, _data(id).grid_size))
		assert_object(node).override_failure_message(id).is_instanceof(MeshInstance3D)
		assert_object((node as MeshInstance3D).mesh).is_same(Decor.mesh_for(id))
