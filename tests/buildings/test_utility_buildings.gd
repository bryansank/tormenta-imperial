extends GdUnitTestSuite
## Los siete edificios utiles de la 1.1 (doc 21 §6.3, fila 2.6): Molino, Silo,
## Taberna, Carpinteria, Pozo, Faro y Deposito de combustible. Fija que cada uno
## siga la receta de "Adding a New Building" y que sus efectos pasen por los
## servicios sin tocar el balance de lo de antes.
##
## Escrita sin correr (regla de Bryan: un solo pase de pruebas al final).
## Toca ResourceManager y GameConfig de verdad: cada prueba deja lo que cambia.

const Toys := preload("res://scripts/buildings/UtilityToys.gd")
const Effects := preload("res://scripts/buildings/UtilityEffects.gd")
const Kit := preload("res://scripts/buildings/LotMesh.gd")

const IDS := ["windmill", "silo", "tavern", "carpentry", "well", "lighthouse", "fuel_depot"]
## Presupuesto de un edificio util 2x2 (doc 21 §6.6).
const TRI_BUDGET := 1500

var _saved_amounts: Dictionary = {}
var _saved_warning := 0.0
var _saved_spoil := 1.0

func before_test() -> void:
	_saved_amounts = {}
	for type in ResourceManager.get_all():
		_saved_amounts[ResourceManager.get_type_name(type)] = ResourceManager.get_amount(type)
	_saved_warning = GameConfig.storm_warning_bonus
	_saved_spoil = GameConfig.food_spoil_delay_mult

func after_test() -> void:
	ResourceManager.set_side_storage({})
	ResourceManager.set_amounts(_saved_amounts)
	GameConfig.storm_warning_bonus = _saved_warning
	GameConfig.food_spoil_delay_mult = _saved_spoil

func _data(id: String) -> BuildingData:
	return load("res://data/buildings/%s.tres" % id) as BuildingData

# ── Catalogo ──────────────────────────────────────────────────────────

func test_the_seven_exist_and_are_at_least_2x2() -> void:
	for id in IDS:
		var d := _data(id)
		assert_object(d).override_failure_message(id).is_not_null()
		assert_str(d.id).is_equal(id)
		assert_bool(d.grid_size.x >= 2 and d.grid_size.y >= 2).override_failure_message(id).is_true()
		assert_bool(d.is_decoration).is_false()

func test_every_one_has_names_in_both_languages() -> void:
	var before := Tr.get_locale()
	for locale in ["es", "en"]:
		Tr.set_locale(locale)
		for id in IDS:
			for suffix in ["_NAME", "_DESC"]:
				var key := "BLD_%s%s" % [id.to_upper(), suffix]
				assert_str(Tr.t(key)).override_failure_message(key).is_not_equal(key)
		for key in ["PROC_CARPENTRY_PLANKS", "PROC_CARPENTRY_FURNITURE"]:
			assert_str(Tr.t(key)).is_not_equal(key)
	Tr.set_locale(before)

func test_every_one_has_cap_lot_site_and_prerequisite() -> void:
	for id in IDS:
		assert_bool(GameConfig.core_level_limits.has(id)).override_failure_message(id).is_true()
		assert_bool(GameConfig.building_limits.has(id)).override_failure_message(id).is_true()
		assert_bool(GameConfig.building_lot_style.has(id)).override_failure_message(id).is_true()
		assert_bool(GameConfig.construction_style.has(id)).override_failure_message(id).is_true()
		assert_bool(GameConfig.building_prerequisites.has(id)).override_failure_message(id).is_true()

func test_the_lighthouse_is_unique() -> void:
	for lv in range(1, GameConfig.core_level_max + 1):
		assert_int(GameConfig.base_building_limit("lighthouse", lv)).is_equal(1)

func test_well_and_windmill_open_with_the_rank() -> void:
	assert_int(RankManager.building_rank("well")).is_equal(2)
	assert_int(RankManager.building_rank("windmill")).is_equal(3)

func test_carpentry_makes_planks_and_the_core_does_not_repeat_it() -> void:
	var procs: Array = GameConfig.get_processes_for("carpentry")
	assert_int(procs.size()).is_equal(2)
	assert_bool((procs[0]["produces"] as Dictionary).has("planks")).is_true()
	for p in GameConfig.get_core_extra_processes():
		assert_str(String(p.get("from", ""))).is_not_equal("carpentry")

# ── Malla 3D ──────────────────────────────────────────────────────────

func test_every_procedural_mesh_is_one_shared_mesh_within_budget() -> void:
	for id in IDS:
		var m: ArrayMesh = Toys.mesh(id)
		assert_object(m).override_failure_message(id).is_not_null()
		assert_object(Toys.mesh(id)).is_same(m)
		assert_int(m.get_surface_count()).is_less_equal(2)
		var tris := 0
		for s in m.get_surface_count():
			tris += (m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
			# Los dos materiales comunes de la maqueta, nada propio.
			var mat := m.surface_get_material(s)
			assert_bool(mat == Kit.solid_material() or mat == Kit.glow_material()).is_true()
		assert_int(tris).override_failure_message("%s: %d tri" % [id, tris]).is_less_equal(TRI_BUDGET)
		# Cabe en el rectangulo del modelo (2,8 m con patio 0,3) con holgura.
		var a := m.get_aabb()
		assert_float(a.size.x).override_failure_message(id).is_less_equal(3.0)
		assert_float(a.size.z).override_failure_message(id).is_less_equal(3.0)

func test_the_factory_gives_them_a_model() -> void:
	for id in IDS:
		var node := DieselpunkBuildingFactory.create(id, 2.0, Vector2i(2, 2))
		assert_object(node).override_failure_message(id).is_not_null()
		node.free()

# ── Areas ─────────────────────────────────────────────────────────────

func test_footprint_gap_counts_free_cells_between() -> void:
	var a := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
	var touching := [Vector2i(2, 0), Vector2i(3, 0), Vector2i(2, 1), Vector2i(3, 1)]
	var four_away := [Vector2i(6, 1), Vector2i(7, 1), Vector2i(6, 2), Vector2i(7, 2)]
	assert_int(Effects.footprint_gap(a, touching)).is_equal(0)
	assert_int(Effects.footprint_gap(a, four_away)).is_equal(4)
	assert_int(Effects.footprint_gap(four_away, a)).is_equal(4)

# ── Bolsas aparte (Silo, Deposito de combustible) ─────────────────────

func test_side_storage_keeps_food_out_of_the_shared_bag() -> void:
	ResourceManager.set_amounts({"gold": 0, "wood": 0, "steel": 0, "oil": 0, "food": 200})
	var counted := ResourceManager.get_total_stored()
	ResourceManager.set_side_storage({ResourceManager.Type.FOOD: GameConfig.silo_food_storage})
	assert_int(ResourceManager.get_total_stored()).is_equal(counted - 200)
	# Lo que pasa del silo vuelve a contar.
	ResourceManager.set_amounts({"food": GameConfig.silo_food_storage + 50})
	assert_int(ResourceManager.get_total_stored()).is_equal(50)

func test_free_space_for_a_type_adds_what_its_side_bag_still_holds() -> void:
	ResourceManager.set_amounts({"gold": 0, "wood": 0, "steel": 0, "oil": 100, "food": 0})
	ResourceManager.set_side_storage({ResourceManager.Type.OIL: GameConfig.fuel_depot_oil_storage})
	var free := ResourceManager.get_free_space()
	assert_int(ResourceManager.get_free_space_for(ResourceManager.Type.OIL)).is_equal(free + GameConfig.fuel_depot_oil_storage - 100)
	assert_int(ResourceManager.get_free_space_for(ResourceManager.Type.GOLD)).is_equal(free)

# ── Faro y Silo en GameConfig ─────────────────────────────────────────

func test_the_lighthouse_bonus_lengthens_the_warning() -> void:
	GameConfig.storm_warning_bonus = 0.0
	var base := GameConfig.get_storm_warning()
	GameConfig.storm_warning_bonus = GameConfig.lighthouse_warning_bonus
	assert_float(GameConfig.get_storm_warning()).is_greater(base)

func test_the_silo_delays_spoilage_only_on_farms() -> void:
	GameConfig.food_spoil_delay_mult = GameConfig.silo_spoil_delay_mult
	assert_float(GameConfig.spoil_after_for("farm")).is_equal(GameConfig.spoil_after_seconds * GameConfig.silo_spoil_delay_mult)
	assert_float(GameConfig.spoil_after_for("sawmill")).is_equal(GameConfig.spoil_after_seconds)

func test_clear_puts_everything_back() -> void:
	GameConfig.storm_warning_bonus = 20.0
	GameConfig.food_spoil_delay_mult = 1.5
	ResourceManager.set_side_storage({ResourceManager.Type.FOOD: 300})
	Effects.clear()
	assert_float(GameConfig.storm_warning_bonus).is_equal(0.0)
	assert_float(GameConfig.food_spoil_delay_mult).is_equal(1.0)
	assert_int(ResourceManager.get_side_storage(ResourceManager.Type.FOOD)).is_equal(0)

# ── Pozo ──────────────────────────────────────────────────────────────

func test_heal_never_lifts_a_ruin() -> void:
	var node := Node3D.new()
	add_child(node)
	node.set_meta("health", 0)
	assert_int(BuildingHealth.heal(node, 50)).is_equal(0)
	node.queue_free()
