extends GdUnitTestSuite
## Las diez decoraciones baratas (feat/decoraciones-1, doc 21 §6.4): cada una
## carga, es decoracion 2x2 sin tope, tiene textos ES/EN, obra, parcela, dibujo
## 2D y una malla 3D de la paleta dentro del presupuesto.

const Decor := preload("res://scripts/buildings/DecorMesh.gd")
const Art := preload("res://scripts/view2d/BuildingArt2D.gd")
const Kit := preload("res://tools/toy_kit.gd")

const IDS := ["lamp_post", "park_bench", "hedge", "avenue_tree", "flower_planter",
	"colony_sign", "hay_cart", "bonfire", "flagpole", "palm_trees"]

## Rango que abre cada una (doc 21 §6.5; 1 = libre).
const RANKS := {"lamp_post": 1, "park_bench": 1, "hedge": 1, "avenue_tree": 1,
	"flower_planter": 2, "colony_sign": 1, "hay_cart": 2, "bonfire": 3, "flagpole": 5,
	"palm_trees": 13}

func _data(id: String) -> BuildingData:
	return load("res://data/buildings/%s.tres" % id)

func test_every_decoration_loads_as_a_cheap_2x2_decoration() -> void:
	for id in IDS:
		var d := _data(id)
		assert_object(d).override_failure_message(id).is_not_null()
		assert_str(d.id).is_equal(id)
		assert_bool(d.is_decoration).override_failure_message(id).is_true()
		assert_vector(Vector2(d.grid_size)).is_equal(Vector2(2, 2))
		assert_int(d.workers_required).is_equal(0)
		assert_int(d.morale_bonus).is_between(1, 3)
		# Solo oro y madera: se pueden poner desde la era 1.
		assert_int(d.cost_steel + d.cost_oil).is_equal(0)
		assert_int(d.cost_gold + d.cost_wood).is_between(1, 80)
		assert_bool(d.is_producer()).is_false()

func test_decorations_have_no_cap() -> void:
	for id in IDS:
		assert_int(GameConfig.get_building_limit(id)).override_failure_message(id).is_equal(-1)

func test_every_decoration_has_its_texts_in_both_languages() -> void:
	for locale in ["es", "en"]:
		Tr.set_locale(locale)
		for id in IDS:
			for key in ["BLD_%s_NAME" % id.to_upper(), "BLD_%s_DESC" % id.to_upper()]:
				assert_str(Tr.t(key)).override_failure_message("falta %s en %s" % [key, locale]).is_not_equal(key)
	Tr.set_locale("es")

func test_every_decoration_has_its_site_and_lot() -> void:
	for id in IDS:
		assert_bool(GameConfig.construction_style.has(id)).override_failure_message(id).is_true()
		assert_bool(GameConfig.building_lot_style.has(id)).override_failure_message(id).is_true()

func test_rank_unlocks_follow_the_plan() -> void:
	for id in IDS:
		var want: int = RANKS[id]
		var found := 1
		for r in GameConfig.rank_rewards:
			if id in GameConfig.rank_rewards[r].get("buildings", []):
				found = int(r)
		assert_int(found).override_failure_message(id).is_equal(want)

func test_no_rank_gives_slots_to_decorations() -> void:
	# Sin tope no hay huecos que dar (feat/topes-por-era).
	for r in GameConfig.rank_rewards:
		var limit: Dictionary = GameConfig.rank_rewards[r].get("limit", {})
		for id in limit:
			assert_bool(_data(String(id)).is_decoration).override_failure_message("rango %d da huecos a %s" % [r, id]).is_false()

func test_every_decoration_has_a_2d_drawing() -> void:
	var names: Array = []
	for m in (Art as GDScript).get_script_method_list():
		names.append(String(m["name"]))
	for id in IDS:
		assert_array(names).override_failure_message("sin dibujo 2D: %s" % id).contains(["_" + id])

func test_the_2d_drawing_runs() -> void:
	var canvas: Node2D = auto_free(Node2D.new())
	add_child(canvas)
	var drawn := [0]
	canvas.draw.connect(func():
		for id in IDS:
			for rot in 4:
				Art.draw_building(canvas, id, Vector2(64, 64), {"rot": rot, "inset": 8.0})
				drawn[0] += 1)
	canvas.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(drawn[0]).is_equal(IDS.size() * 4)

func test_every_decoration_has_a_shared_palette_mesh_within_budget() -> void:
	for id in IDS:
		var mesh := Decor.procedural(id)
		assert_object(mesh).override_failure_message(id).is_not_null()
		assert_int(Kit.tri_count(mesh)).override_failure_message(id).is_less_equal(Decor.TRI_BUDGET)
		assert_object(mesh.surface_get_material(0)).is_same(Decor.MeshKit.solid_material())
		var a := mesh.get_aabb()
		assert_float(a.position.y).is_greater_equal(-0.01)
		assert_float(a.size.y).is_greater(0.3)
		# Una malla por tipo para todo el mapa.
		var one: MeshInstance3D = auto_free(Decor.instantiate(id))
		var two: MeshInstance3D = auto_free(Decor.instantiate(id))
		assert_object(one.mesh).is_same(two.mesh)

func test_the_factory_hands_out_the_decoration_mesh() -> void:
	for id in IDS:
		var node: Node3D = auto_free(DieselpunkBuildingFactory.create(id, 2.0, Vector2i(2, 2)))
		assert_object(node).override_failure_message(id).is_instanceof(MeshInstance3D)
		assert_object((node as MeshInstance3D).mesh).is_same(Decor.mesh_for(id))

func test_lamp_and_bonfire_glow_without_lights() -> void:
	for id in ["lamp_post", "bonfire"]:
		var mesh := Decor.procedural(id)
		assert_int(mesh.get_surface_count()).is_equal(2)
		assert_object(mesh.surface_get_material(1)).is_same(Decor.MeshKit.glow_material())
