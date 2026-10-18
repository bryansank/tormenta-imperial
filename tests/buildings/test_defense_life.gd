extends GdUnitTestSuite
## Defensa y vida (feat/edificios-defensa-vida, doc 21 §6.3 n.º 11, 12, 18 y
## §6.4): Bastion, Chatarreria, Telegrafo y la belleza del barrio. Fija que cada
## edificio siga la receta de "Adding a New Building", que las reglas puras
## (cobertura del tablero, "detras del muro", belleza, hilo del Telegrafo)
## digan lo que dicen los docs y que un tablero sin bastion siga igual.
##
## Escrita sin correr (regla de Bryan: un solo pase de pruebas al final).
## Toca GameConfig de verdad: cada prueba deja lo que cambia.

const Toys := preload("res://scripts/buildings/DefenseToys.gd")
const Effects := preload("res://scripts/buildings/DefenseLifeEffects.gd")
const Trim := preload("res://scripts/buildings/BeautyTrim.gd")
const Kit := preload("res://scripts/buildings/LotMesh.gd")
const Rules := preload("res://scripts/combat/CombatRules.gd")
const EncounterScript := preload("res://scripts/combat/Encounter.gd")
const UnitScript := preload("res://scripts/combat/CombatUnit.gd")
const Board := preload("res://scripts/economy/ContractBoard.gd")

const IDS := ["bastion", "scrapyard", "telegraph"]
const TRI_BUDGET := 1500

var _saved_cover := 0
var _saved_slots := 0
var _saved_mult := 1.0

func before_test() -> void:
	_saved_cover = GameConfig.defense_cover_cells
	_saved_slots = GameConfig.contract_extra_slots
	_saved_mult = GameConfig.contract_duration_mult

func after_test() -> void:
	GameConfig.defense_cover_cells = _saved_cover
	GameConfig.contract_extra_slots = _saved_slots
	GameConfig.contract_duration_mult = _saved_mult

func _data(id: String) -> BuildingData:
	return load("res://data/buildings/%s.tres" % id) as BuildingData

# ── Catalogo ──────────────────────────────────────────────────────────

func test_the_three_exist_with_their_footprints() -> void:
	for id in IDS:
		var d := _data(id)
		assert_object(d).override_failure_message(id).is_not_null()
		assert_str(d.id).is_equal(id)
		assert_bool(d.is_decoration).is_false()
	# El muro es la otra excepcion, como la carretera: 2x1.
	assert_that(_data("bastion").grid_size).is_equal(Vector2i(2, 1))
	assert_that(_data("scrapyard").grid_size).is_equal(Vector2i(2, 2))
	assert_that(_data("telegraph").grid_size).is_equal(Vector2i(2, 2))

func test_every_one_has_names_and_help_in_both_languages() -> void:
	var before := Tr.get_locale()
	for locale in ["es", "en"]:
		Tr.set_locale(locale)
		for id in IDS:
			for suffix in ["_NAME", "_DESC"]:
				var key := "BLD_%s%s" % [id.to_upper(), suffix]
				assert_str(Tr.t(key)).override_failure_message(key).is_not_equal(key)
			for prefix in ["HELP_T_", "HELP_B_"]:
				var hk: String = prefix + id.to_upper()
				assert_str(Tr.t(hk)).override_failure_message(hk).is_not_equal(hk)
		for key in ["HELP_T_BEAUTY", "HELP_B_BEAUTY", "CONTRACT_SRC_TELEGRAPH",
				"CONTRACT_SRC_TELEGRAPH_TIP", "LBL_COVER_CELL_TIP", "NOTIF_SCRAP_SALVAGED",
				"LBL_BEAUTY_PLAIN", "LBL_BEAUTY_PRETTY", "LBL_BEAUTY_ELEGANT", "LBL_BEAUTY_NEXT",
				"LBL_BASTION_INFO", "LBL_SCRAPYARD_INFO", "LBL_TELEGRAPH_INFO", "LBL_BEHIND_BASTION"]:
			assert_str(Tr.t(key)).override_failure_message(key).is_not_equal(key)
	Tr.set_locale(before)

func test_every_one_has_cap_lot_site_and_prerequisite() -> void:
	for id in IDS:
		assert_bool(GameConfig.core_level_limits.has(id)).override_failure_message(id).is_true()
		assert_int(int(GameConfig.building_limits[id])).is_equal(int(GameConfig.core_level_limits[id][0]))
		assert_bool(GameConfig.building_lot_style.has(id)).override_failure_message(id).is_true()
		assert_bool(GameConfig.construction_style.has(id)).override_failure_message(id).is_true()
		# Los tres son de la era 2: piden la Fundicion.
		assert_array(GameConfig.building_prerequisites[id]).contains(["foundry"])

func test_the_telegraph_is_unique() -> void:
	for era in [1, 2, 3]:
		assert_int(GameConfig.base_building_limit("telegraph", era)).is_equal(1)

func test_the_help_catalog_knows_them() -> void:
	var cat := preload("res://scripts/ui/HelpCatalog.gd")
	for id in ["bastion", "scrapyard", "telegraph", "beauty"]:
		assert_bool(cat.ENTRIES.has(id)).override_failure_message(id).is_true()

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
			var mat := m.surface_get_material(s)
			assert_bool(mat == Kit.solid_material() or mat == Kit.glow_material()).is_true()
		assert_int(tris).override_failure_message("%s: %d tri" % [id, tris]).is_less_equal(TRI_BUDGET)

func test_the_bastion_is_a_long_low_wall() -> void:
	var a := Toys.mesh("bastion").get_aabb()
	assert_float(a.size.x).is_greater(a.size.z * 1.8)
	assert_float(a.size.x).is_less_equal(3.9)

func test_the_factory_gives_them_a_model() -> void:
	for id in IDS:
		var node := DieselpunkBuildingFactory.create(id, 2.0, _data(id).grid_size)
		assert_object(node).override_failure_message(id).is_not_null()
		node.free()

func test_beauty_trim_is_cached_per_level_and_size() -> void:
	var a := Trim.trim_mesh(2, Vector3(2.8, 2.0, 2.8))
	assert_object(Trim.trim_mesh(2, Vector3(2.8, 2.0, 2.8))).is_same(a)
	var b := Trim.trim_mesh(3, Vector3(2.8, 2.0, 2.8))
	assert_object(b).is_not_same(a)
	# El elegante lleva mas piezas (hiedra, farolas, banderines).
	var va := (a.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var vb := (b.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	assert_int(vb).is_greater(va)

# ── Belleza ───────────────────────────────────────────────────────────

func test_beauty_values_and_levels() -> void:
	assert_int(GameConfig.beauty_of(_data("statue"))).is_equal(10)
	assert_int(GameConfig.beauty_of(_data("garden"))).is_equal(4)
	# La carretera no da belleza aunque sea "decoracion".
	assert_int(GameConfig.beauty_of(_data("road"))).is_equal(0)
	# Un edificio que no es decoracion ni esta en la tabla, tampoco.
	assert_int(GameConfig.beauty_of(_data("sawmill"))).is_equal(0)
	# Mejorada, vale mas.
	assert_int(GameConfig.beauty_of(_data("garden"), 3)).is_greater(GameConfig.beauty_of(_data("garden"), 1))
	assert_int(GameConfig.beauty_level_for(0)).is_equal(1)
	assert_int(GameConfig.beauty_level_for(9)).is_equal(1)
	assert_int(GameConfig.beauty_level_for(10)).is_equal(2)
	assert_int(GameConfig.beauty_level_for(25)).is_equal(3)
	assert_int(GameConfig.beauty_level_for(999)).is_equal(3)
	assert_int(GameConfig.beauty_room_for(1)).is_equal(0)
	assert_int(GameConfig.beauty_room_for(2)).is_equal(1)
	assert_int(GameConfig.beauty_room_for(3)).is_equal(2)
	assert_int(GameConfig.beauty_morale_for(3)).is_greater(GameConfig.beauty_morale_for(2))

# ── Bastion: detras del muro ──────────────────────────────────────────

func _info(cells: Array) -> Dictionary:
	return {"cells": cells, "node": null}

func test_behind_the_wall_means_towards_the_middle_of_the_island() -> void:
	# Isla con centro en (20, 20); muro al norte (y = 5), mirando al mar (y < 5).
	var center := Vector2(20, 20)
	var wall := _info([Vector2i(19, 5), Vector2i(20, 5)])
	var inside := _info([Vector2i(19, 7), Vector2i(20, 7), Vector2i(19, 8), Vector2i(20, 8)])
	var outside := _info([Vector2i(19, 2), Vector2i(20, 2), Vector2i(19, 3), Vector2i(20, 3)])
	var far := _info([Vector2i(19, 12), Vector2i(20, 12), Vector2i(19, 13), Vector2i(20, 13)])
	assert_bool(Effects.is_behind(inside, wall, center, 3)).is_true()
	assert_bool(Effects.is_behind(outside, wall, center, 3)).is_false()
	assert_bool(Effects.is_behind(far, wall, center, 3)).is_false()

func test_a_wall_in_the_very_middle_covers_its_whole_radius() -> void:
	var center := Vector2(20, 20)
	var wall := _info([Vector2i(19, 20), Vector2i(20, 20)])
	var north := _info([Vector2i(19, 17), Vector2i(20, 17)])
	assert_bool(Effects.is_behind(north, wall, center, 3)).is_true()

func test_cover_cells_follow_the_number_of_bastions() -> void:
	assert_int(GameConfig.bastion_cover_cells_for(0)).is_equal(0)
	assert_int(GameConfig.bastion_cover_cells_for(1)).is_equal(1)
	assert_int(GameConfig.bastion_cover_cells_for(3)).is_equal(1)
	assert_int(GameConfig.bastion_cover_cells_for(4)).is_equal(2)
	assert_int(GameConfig.bastion_cover_cells_for(99)).is_equal(GameConfig.bastion_board_cover_max)

# ── Cobertura en el tablero (modelo puro) ─────────────────────────────

func test_cover_cells_are_land_in_the_back_row_from_the_middle_out() -> void:
	var board := Vector2i(8, 8)
	var cells := Rules.cover_cells(board, {}, 2, 7)
	assert_array(cells).contains_exactly([Vector2i(4, 7), Vector2i(3, 7)])
	assert_array(Rules.cover_cells(board, {}, 0, 7)).is_empty()
	# Sin tierra en el centro, busca hacia fuera.
	var terrain := {Vector2i(4, 7): "water", Vector2i(3, 7): "shore"}
	var land := Rules.cover_cells(board, terrain, 1, 7)
	assert_array(land).contains_exactly([Vector2i(5, 7)])

func _units() -> Array:
	var a = UnitScript.create(1, "infantry", EncounterScript.PLAYER, 1.0)
	var b = UnitScript.create(2, "infantry", EncounterScript.ENEMY, 1.0)
	return [a, b]

func test_cover_lowers_the_damage_on_whoever_stands_there() -> void:
	var units := _units()
	var e = EncounterScript.create(units, 0, false, true)
	var me = units[0]
	var them = units[1]
	var plain: int = e.damage_between(them, me)
	# Sin cobertura, la formula de siempre.
	assert_int(plain).is_equal(Rules.damage(them, me))
	e.set_cover([me.position], 2)
	assert_int(e.cover_for(me)).is_equal(2)
	assert_int(e.damage_between(them, me)).is_equal(maxi(1, plain - 2))
	# El atacante no gana nada por estar el defensor a cubierto.
	assert_int(e.damage_between(me, them)).is_equal(Rules.damage(me, them))

func test_a_board_without_bastions_has_no_cover() -> void:
	GameConfig.defense_cover_cells = 0
	var units := _units()
	var e = EncounterScript.create(units, 0, false, true)
	CombatManager.apply_home_cover(e)
	assert_bool(e.cover.is_empty()).is_true()

func test_home_cover_only_goes_on_defensive_boards() -> void:
	GameConfig.defense_cover_cells = 1
	var units := _units()
	var away = EncounterScript.create(units, 0, false, false)
	CombatManager.apply_home_cover(away)
	assert_bool(away.cover.is_empty()).is_true()
	var home = EncounterScript.create(_units(), 0, false, true)
	CombatManager.apply_home_cover(home)
	assert_int(home.cover.size()).is_equal(1)
	assert_int(int(home.cover.values()[0])).is_equal(GameConfig.bastion_cover_defense)

func test_preview_damage_counts_the_cover() -> void:
	var units := _units()
	var p0 := Rules.preview_damage(units[1], units[0])
	var p2 := Rules.preview_damage(units[1], units[0], 2)
	assert_int(int(p2["damage"])).is_equal(maxi(1, int(p0["damage"]) - 2))

# ── Telegrafo: el hilo del tablon ─────────────────────────────────────

func _ctx(extra: int, mult := 1.0) -> Dictionary:
	return {"era": 2, "unlocked": ["gold", "wood", "steel", "planks", "ingots", "beams", "food"],
		"colonists_ok": true, "morale_ok": true, "tithe_discount_ok": false,
		"reputation": false, "extra_slots": extra, "duration_mult": mult}

func test_the_wire_stays_closed_without_a_telegraph() -> void:
	var board = Board.create(7)
	assert_bool(Board.slot_open(Board.WIRE, 2, _ctx(0))).is_false()
	board.advance(10000.0, _ctx(0))
	assert_bool(board.get_contract(Board.WIRE).is_empty()).is_true()

func test_the_wire_brings_an_order_from_a_real_source() -> void:
	var board = Board.create(7)
	assert_bool(Board.slot_open(Board.WIRE, 2, _ctx(1))).is_true()
	var events: Array = board.advance(10000.0, _ctx(1))
	var c: Dictionary = board.get_contract(Board.WIRE)
	assert_bool(c.is_empty()).is_false()
	assert_str(String(c["source"])).is_equal(Board.WIRE)
	assert_array(Board.SOURCES).contains([String(c["from"])])
	var offered := events.filter(func(ev): return String(ev.get("source", "")) == Board.WIRE)
	assert_int(offered.size()).is_equal(1)

func test_a_telegraph_makes_new_orders_last_half_again() -> void:
	var a = Board.create(3)
	var b = Board.create(3)
	var template: Dictionary = GameConfig.contract_templates["neighbors"][0]
	var plain: Dictionary = a.build_contract("neighbors", template, _ctx(0, 1.0))
	var longer: Dictionary = b.build_contract("neighbors", template, _ctx(1, 1.5))
	assert_float(float(longer["seconds_total"])).is_equal_approx(float(plain["seconds_total"]) * 1.5, 0.01)

func test_the_wire_order_survives_save_and_load() -> void:
	var board = Board.create(11)
	board.advance(10000.0, _ctx(1))
	var c: Dictionary = board.get_contract(Board.WIRE)
	var back = Board.from_dict(JSON.parse_string(JSON.stringify(board.to_dict())))
	var again: Dictionary = back.get_contract(Board.WIRE)
	assert_bool(again.is_empty()).is_false()
	assert_str(String(again["from"])).is_equal(String(c["from"]))

func test_an_old_board_without_the_wire_loads_empty() -> void:
	var board = Board.from_dict({"slots": {"regency": {}, "neighbors": {}, "smuggler": {}}})
	assert_bool(board.get_contract(Board.WIRE).is_empty()).is_true()

# ── Runtime: partida nueva ────────────────────────────────────────────

func test_clear_resets_the_runtime_values() -> void:
	GameConfig.defense_cover_cells = 2
	GameConfig.contract_extra_slots = 1
	GameConfig.contract_duration_mult = 1.5
	Effects.clear()
	assert_int(GameConfig.defense_cover_cells).is_equal(0)
	assert_int(GameConfig.contract_extra_slots).is_equal(0)
	assert_float(GameConfig.contract_duration_mult).is_equal(1.0)
