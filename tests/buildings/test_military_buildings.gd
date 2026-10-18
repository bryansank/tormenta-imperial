extends GdUnitTestSuite
## Edificios militares de la 1.2 (feat/edificios-militares, doc 21 §6.3 n.º
## 8-10): Enfermeria (infirmary), Herreria militar (smithy) y Campo de tiro
## (firing_range). Fija la receta de "Adding a New Building" (datos, topes,
## requisitos, obra, parcela, textos, ayuda, modelo horneado y dibujo 2D) y su
## conexion con el ejercito: el -20 % al entrenar, la doctrina que vale con la
## Herreria en pie, el simulacro sin bajas y su premio de una sola vez, y la
## Enfermeria en el parte de un combate.
##
## Escrita sin correr (regla de Bryan: un solo pase de pruebas al final).
## Toca el GridManager real, ArmyManager, CombatManager, GameMode y GameConfig:
## cada prueba deja lo que cambia. Escribe el guardado (request_save): aparca el
## del jugador con save_parking.

const SaveParking := preload("res://tests/save/save_parking.gd")
const Military := preload("res://scripts/buildings/MilitaryBuildings.gd")
const Art := preload("res://scripts/view2d/BuildingArt2D.gd")
const HelpCat := preload("res://scripts/ui/HelpCatalog.gd")
const Section := preload("res://scripts/ui/MilitarySection.gd")
const BACKUP_PATH := "user://save_game.military.bak"
const IDS := ["infirmary", "smithy", "firing_range"]

func before(do_skip := SaveParking.in_player_dir(), skip_reason := "Carpeta de usuario del jugador: lanza los tests con tools/run_tests.sh") -> void:
	pass

var _army_saved: Dictionary = {}
var _mode_saved: Dictionary = {}
var _res_saved: Dictionary = {}
var _pop_saved: Dictionary = {}
var _rank_saved: Dictionary = {}
var _doctrine_saved := ""
var _nodes: Array = []

func before_test() -> void:
	SaveParking.park(BACKUP_PATH)
	_army_saved = ArmyManager.get_save_data()
	_mode_saved = GameMode.get_save_data()
	_res_saved = {}
	for type in ResourceManager.get_all():
		_res_saved[ResourceManager.get_type_name(type)] = ResourceManager.get_amount(type)
	_pop_saved = PopulationManager.get_save_data()
	_rank_saved = RankManager.get_save_data()
	_doctrine_saved = GameConfig.combat_active_doctrine
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	ArmyManager.reset()
	GridManager.clear_all()
	GridManager.reset_size()
	_nodes.clear()

func after_test() -> void:
	if CombatManager.is_in_encounter():
		CombatManager.end_encounter()
	GridManager.clear_all()
	GridManager.reset_size()
	GameMode.load_save_data(_mode_saved)
	ArmyManager.reset()
	ArmyManager.load_save_data(_army_saved)
	ResourceManager.set_amounts(_res_saved)
	PopulationManager.load_save_data(_pop_saved)
	RankManager.reset()
	RankManager.load_save_data(_rank_saved)
	GameConfig.combat_active_doctrine = _doctrine_saved
	SaveParking.restore(BACKUP_PATH)

func _data(id: String) -> BuildingData:
	return load("res://data/buildings/%s.tres" % id) as BuildingData

## Planta `id` en la rejilla, ya terminado, unido y con su gente.
func _place(id: String, cell: Vector2i) -> Node3D:
	var node: Node3D = auto_free(Node3D.new())
	assert_bool(GridManager.place_building(cell, _data(id), node)).is_true()
	node.set_meta("connected", true)
	node.set_meta("staffed", true)
	_nodes.append(node)
	return node

func _gold() -> int:
	return ResourceManager.get_amount(ResourceManager.Type.GOLD)

# ── Datos y receta ────────────────────────────────────────────────────

func test_the_three_buildings_load_with_their_model() -> void:
	for id in IDS:
		var d := _data(id)
		assert_object(d).is_not_null()
		assert_str(d.id).is_equal(id)
		assert_that(d.grid_size).is_equal(Vector2i(2, 2))
		assert_bool(d.is_decoration).is_false()
		assert_bool(d.is_producer()).is_false()
		# Era 2: piden acero y un material del taller.
		assert_int(d.cost_steel).is_greater(0)
		assert_int(d.cost_oil).is_equal(0)
		assert_bool(d.cost_materials.is_empty()).is_false()
		assert_int(d.workers_required).is_greater(0)
		assert_object(d.model_scene).is_not_null()

func test_they_are_unique_and_need_barracks_and_foundry() -> void:
	for id in IDS:
		assert_int(int(GameConfig.building_limits[id])).is_equal(1)
		assert_array(GameConfig.core_level_limits[id]).is_equal([1, 1, 1, 1, 1])
		var reqs: Array = GameConfig.get_prerequisites(id)
		assert_bool(reqs.has("barracks")).is_true()
		assert_bool(reqs.has("foundry")).is_true()
		assert_bool(id in GameConfig.MILITARY_SUPPORT_BUILDINGS).is_true()

func test_each_has_its_site_lot_and_texts() -> void:
	for id in IDS:
		assert_bool(GameConfig.construction_style.has(id)).is_true()
		assert_bool(GameConfig.building_lot_style.has(id)).is_true()
		for locale in ["es", "en"]:
			Tr.set_locale(locale)
			for key in ["BLD_%s_NAME" % id.to_upper(), "BLD_%s_DESC" % id.to_upper(),
					"TOPE_NO_UPGRADE_WHY_%s" % id.to_upper(), "HELP_T_%s" % id.to_upper(), "HELP_B_%s" % id.to_upper()]:
				assert_str(Tr.t(key)).is_not_equal(key)
	Tr.set_locale("es")
	assert_str(GameConfig.building_active_fx.get("smithy", "")).is_equal("smoke")

func test_each_has_a_help_card_and_a_tip() -> void:
	for id in IDS:
		assert_bool(HelpCat.ENTRIES.has(id)).is_true()
		assert_str(String(HelpCat.ENTRIES[id]["kind"])).is_equal("tip")
		assert_bool(TutorialManager.TIPS.has(id)).is_true()

func test_the_baked_models_exist() -> void:
	for id in IDS:
		assert_bool(ResourceLoader.exists("res://assets/models/toy/%s.tscn" % id)).is_true()
		assert_bool(ResourceLoader.exists("res://assets/models/toy/%s_mesh.res" % id)).is_true()
		var mesh: Mesh = load("res://assets/models/toy/%s_mesh.res" % id)
		var tris := 0
		for s in mesh.get_surface_count():
			tris += mesh.surface_get_array_len(s) / 3
		# Presupuesto de un edificio util 2x2 (doc 21 §6.6).
		assert_int(tris).is_less_equal(1500)

func test_the_2d_drawing_is_their_own() -> void:
	# Cada uno con su dibujo, no la caja de reserva: draw_building() lo
	# despacha a su funcion (dibujar de verdad solo vale dentro de _draw()).
	var src := FileAccess.get_file_as_string("res://scripts/view2d/BuildingArt2D.gd")
	for id in IDS:
		assert_bool(src.contains('"%s": _%s(ci, r)' % [id, id])).is_true()
		assert_bool(src.contains("static func _%s(ci: CanvasItem, r: Rect2)" % id)).is_true()
	assert_array(Art.fx_anchors("smithy")).is_not_equal(Art.fx_anchors("no_such_building"))

func test_they_are_military_in_build_menu_and_rank_xp_exists() -> void:
	assert_int(int(GameConfig.rank_xp_sources.get("practice_lesson", 0))).is_greater(0)
	for id in IDS:
		assert_bool(Section.handles(id)).is_true()
	assert_bool(Section.handles("barracks")).is_false()

# ── En marcha o no ────────────────────────────────────────────────────

func test_working_needs_finished_connected_and_staffed() -> void:
	var node := _place("infirmary", Vector2i(4, 4))
	assert_bool(Military.infirmary_working()).is_true()
	node.set_meta("staffed", false)
	assert_bool(Military.infirmary_working()).is_false()
	node.set_meta("staffed", true)
	node.set_meta("connected", false)
	assert_bool(Military.infirmary_working()).is_false()
	node.set_meta("connected", true)
	node.set_meta("under_construction", true)
	assert_bool(Military.infirmary_working()).is_false()
	assert_int(Military.built_count("infirmary")).is_equal(0)

func test_the_firing_range_trains_twenty_percent_faster() -> void:
	assert_float(Military.train_time_mult()).is_equal(1.0)
	_place("firing_range", Vector2i(4, 4))
	assert_float(Military.train_time_mult()).is_equal_approx(0.8, 0.0001)

func test_the_infirmary_softens_morale_and_heals_more() -> void:
	assert_float(Military.morale_per_casualty()).is_equal(-1.0)
	assert_float(Military.heal_mult()).is_equal(1.0)
	_place("infirmary", Vector2i(4, 4))
	assert_float(Military.morale_per_casualty()).is_equal(GameConfig.infirmary_morale_per_casualty)
	assert_float(Military.heal_mult()).is_equal_approx(1.3, 0.0001)

# ── Herreria: doctrinas ──────────────────────────────────────────────

func test_no_smithy_no_doctrine() -> void:
	var check := ArmyManager.can_choose_doctrine("assault")
	assert_bool(bool(check["ok"])).is_false()
	assert_str(String(check["reason"])).is_equal("DOC_WHY_NO_SMITHY")

func test_choosing_a_doctrine_costs_gold_and_time() -> void:
	_place("smithy", Vector2i(4, 4))
	ResourceManager.add(ResourceManager.Type.GOLD, 500)
	var before := _gold()
	assert_bool(ArmyManager.choose_doctrine("assault")).is_true()
	assert_int(_gold()).is_equal(before - int(GameConfig.smithy_doctrine_cost["gold"]))
	# Mientras se aprende, no hay doctrina y no se puede pedir otra.
	assert_str(ArmyManager.get_doctrine()).is_equal("")
	assert_str(ArmyManager.get_doctrine_pending()).is_equal("assault")
	assert_str(String(ArmyManager.can_choose_doctrine("trench")["reason"])).is_equal("DOC_WHY_SWITCHING")
	# Pasa el tiempo: ya vale, y las unidades nuevas la llevan.
	ArmyManager._advance_doctrine(ArmyManager.get_doctrine_left() + 1.0)
	assert_str(ArmyManager.get_doctrine()).is_equal("assault")
	assert_str(GameConfig.combat_active_doctrine).is_equal("assault")
	var u := CombatUnit.create(1, "infantry", 0, 1.0)
	assert_int(u.move_range()).is_equal(4)
	assert_str(String(ArmyManager.can_choose_doctrine("assault")["reason"])).is_equal("DOC_WHY_ACTIVE")

func test_the_doctrine_stops_counting_without_a_smithy() -> void:
	var node := _place("smithy", Vector2i(4, 4))
	ResourceManager.add(ResourceManager.Type.GOLD, 500)
	ArmyManager.choose_doctrine("trench")
	ArmyManager._advance_doctrine(ArmyManager.get_doctrine_left() + 1.0)
	assert_str(ArmyManager.effective_doctrine()).is_equal("trench")
	# En ruinas sigue valiendo (se aprendio); derribada, no.
	node.set_meta("health", 0)
	assert_str(ArmyManager.effective_doctrine()).is_equal("trench")
	GridManager.clear_all()
	ArmyManager._sync_doctrine()
	assert_str(ArmyManager.effective_doctrine()).is_equal("")
	assert_str(GameConfig.combat_active_doctrine).is_equal("")
	# La elegida no se olvida: vuelve con otra Herreria.
	assert_str(ArmyManager.get_doctrine()).is_equal("trench")

func test_doctrine_and_drill_travel_in_the_save_and_reset_clears_them() -> void:
	_place("smithy", Vector2i(4, 4))
	ResourceManager.add(ResourceManager.Type.GOLD, 500)
	ArmyManager.choose_doctrine("air_aces")
	ArmyManager._practice_done.append("move_attack")
	var data := ArmyManager.get_save_data()
	ArmyManager.reset()
	assert_str(ArmyManager.get_doctrine_pending()).is_equal("")
	assert_int(ArmyManager.practice_done_count()).is_equal(0)
	assert_str(GameConfig.combat_active_doctrine).is_equal("")
	# Cargar dos veces da lo mismo.
	ArmyManager.load_save_data(data)
	ArmyManager.load_save_data(data)
	assert_str(ArmyManager.get_doctrine_pending()).is_equal("air_aces")
	assert_float(ArmyManager.get_doctrine_left()).is_greater(0.0)
	assert_bool(ArmyManager.is_practice_done("move_attack")).is_true()
	assert_int(ArmyManager.practice_done_count()).is_equal(1)

func test_an_old_army_save_loads_without_doctrine() -> void:
	ArmyManager.load_save_data({"units": {"infantry": 2}})
	assert_str(ArmyManager.get_doctrine()).is_equal("")
	assert_int(ArmyManager.practice_done_count()).is_equal(0)

# ── Campo de tiro: simulacro ──────────────────────────────────────────

func test_three_lessons_with_texts_and_a_small_prize() -> void:
	assert_int(GameConfig.firing_range_lessons.size()).is_equal(3)
	for lesson in GameConfig.firing_range_lessons:
		assert_str(Tr.t(String(lesson["name"]))).is_not_equal(String(lesson["name"]))
		assert_str(Tr.t(String(lesson["desc"]))).is_not_equal(String(lesson["desc"]))
		assert_int(int(lesson["reward"].get("gold", 0))).is_between(1, 100)

func test_no_range_no_drill() -> void:
	assert_str(CombatManager.practice_block_reason()).is_equal("PRACTICE_WHY_NO_RANGE")
	assert_bool(CombatManager.start_practice("move_attack")).is_false()

func test_a_drill_costs_no_one_and_pays_once() -> void:
	_place("firing_range", Vector2i(4, 4))
	ArmyManager.load_save_data({"units": {"infantry": 1}})
	var morale_before: int = PopulationManager.get_morale()
	assert_bool(CombatManager.start_practice("move_attack")).is_true()
	assert_bool(CombatManager.is_practice()).is_true()
	assert_str(CombatManager.practice_lesson()).is_equal("move_attack")
	# Mata a toda la tropa de practica y da el combate por ganado igualmente:
	# lo que importa es la liquidacion.
	for unit in CombatManager.get_units():
		if unit.side == 0:
			unit.take_damage(unit.max_hp)
	var gold_before := _gold()
	CombatManager._apply_result(true, 3)
	var result := CombatManager.get_last_result()
	assert_bool(bool(result["practice"])).is_true()
	assert_dict(result["casualties"]).is_empty()
	assert_int(int(result["morale_delta"])).is_equal(0)
	assert_int(ArmyManager.get_count("infantry")).is_equal(1)
	assert_int(PopulationManager.get_morale()).is_equal(morale_before)
	assert_int(_gold()).is_equal(gold_before + 40)
	assert_bool(ArmyManager.is_practice_done("move_attack")).is_true()
	CombatManager.end_encounter()
	# La segunda vez, nada.
	assert_bool(CombatManager.start_practice("move_attack")).is_true()
	gold_before = _gold()
	CombatManager._apply_result(true, 2)
	assert_dict(CombatManager.get_last_result()["rewards"]).is_empty()
	assert_int(_gold()).is_equal(gold_before)

func test_a_drill_board_is_flagged_on_the_encounter() -> void:
	_place("firing_range", Vector2i(4, 4))
	CombatManager.start_practice("artillery")
	var enc: Encounter = CombatManager.get_encounter()
	assert_bool(enc.is_practice).is_true()
	assert_str(enc.practice_lesson).is_equal("artillery")
	assert_bool(enc.is_defense).is_false()
	assert_str(CombatManager.practice_block_reason()).is_equal("PRACTICE_WHY_BOARD")

# ── Enfermeria en el parte ───────────────────────────────────────────

func test_with_an_infirmary_one_in_three_fallen_comes_home() -> void:
	_place("infirmary", Vector2i(4, 4))
	ArmyManager.load_save_data({"units": {"infantry": 3}})
	CombatManager.start_encounter({"infantry": 3}, {"infantry": 1}, false, 0)
	for unit in CombatManager.get_units():
		if unit.side == 0:
			unit.take_damage(unit.max_hp)
	CombatManager._apply_result(true, 4)
	var result := CombatManager.get_last_result()
	assert_dict(result["recovered"]).is_equal({"infantry": 1})
	assert_dict(result["casualties"]).is_equal({"infantry": 2})
	assert_int(ArmyManager.get_count("infantry")).is_equal(1)

func test_without_it_all_fallen_are_lost() -> void:
	ArmyManager.load_save_data({"units": {"infantry": 3}})
	CombatManager.start_encounter({"infantry": 3}, {"infantry": 1}, false, 0)
	for unit in CombatManager.get_units():
		if unit.side == 0:
			unit.take_damage(unit.max_hp)
	CombatManager._apply_result(true, 4)
	var result := CombatManager.get_last_result()
	assert_dict(result["recovered"]).is_empty()
	assert_int(ArmyManager.get_count("infantry")).is_equal(0)
