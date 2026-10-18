extends GdUnitTestSuite
## La VISTA de mar y aire (1.1, rama feat/aire-mar-vista; docs/15 §11): las
## piezas horneadas de las seis unidades nuevas, sus siluetas, el agua del
## tablero (3D y 2D) y las maquetas del Astillero y el Aerodromo.
##
## Solo vista: aqui no se mira ninguna regla (quien pisa que, quien pega a
## quien). El terreno se lee de forma defensiva (`encounter.get("terrain")`), asi
## que estas pruebas pasan con o sin la rama de reglas.

const Layout := preload("res://scripts/combat_view/BoardLayout3D.gd")
const Models := preload("res://scripts/combat_view/UnitModels3D.gd")
const Terrain := preload("res://scripts/combat_view/BoardTerrain3D.gd")
const UnitToy := preload("res://scripts/combat_view/UnitToy3D.gd")
const BoardScript := preload("res://scripts/combat_view/Board3D.gd")
const BattleScreenScript := preload("res://scripts/ui/BattleScreen.gd")
const Factory := preload("res://scripts/buildings/DieselpunkBuildingFactory.gd")

const NEW_UNITS := ["torpedo_boat", "gunboat", "dreadnought", "fighter", "bomber", "airship"]
const NEW_BUILDINGS := ["shipyard", "aerodrome"]
## Presupuesto de un edificio 2x2 de la maqueta (los de la 1.1 andan en 1.000-1.400).
const BUILDING_TRI_BUDGET := 1500

## Un encuentro de mentira con lo unico que la vista lee de el.
class FakeEncounter extends RefCounted:
	var terrain: Dictionary = {}
	var is_defense := false

func before_test() -> void:
	CombatManager.reset()

func after_test() -> void:
	CombatManager.end_encounter()
	CombatManager.reset()

## Dos columnas de agua a la izquierda y una de orilla.
func _coast() -> Dictionary:
	var t := {}
	for y in 8:
		t[Vector2i(0, y)] = Layout.TERRAIN_WATER
		t[Vector2i(1, y)] = Layout.TERRAIN_WATER
		t[Vector2i(2, y)] = Layout.TERRAIN_SHORE
	return t

# ── Las piezas ───────────────────────────────────────────────────────

func test_the_six_new_units_have_a_baked_toy_per_side_within_budget() -> void:
	assert_array(Models.SEA_IDS + Models.AIR_IDS).contains_exactly_in_any_order(NEW_UNITS)
	for unit_id in NEW_UNITS:
		for side in [0, 1]:
			var path := Models.scene_path(unit_id, side)
			assert_str(path).override_failure_message("falta %s del bando %d" % [unit_id, side]).is_not_empty()
			var node: MeshInstance3D = load(path).instantiate()
			assert_int(Models.tri_count(node.mesh)).override_failure_message(
				"%s del bando %d pasa de 800 triangulos" % [unit_id, side]).is_less_equal(800)
			# Color de la colonia en las nuestras; morado horneado en la Regencia.
			var team: int = node.mesh.surface_find_by_name(Models.TEAM_SURFACE)
			if side == 0:
				assert_int(team).is_greater_equal(0)
			else:
				assert_int(team).is_equal(-1)
			# De donde sale el disparo y donde va la barra.
			assert_object(node.get_node_or_null("Muzzle")).is_not_null()
			assert_object(node.get_node_or_null("Top")).is_not_null()
			node.free()

func test_one_material_per_surface_and_no_lights_in_the_new_toys() -> void:
	for unit_id in NEW_UNITS:
		var node: Node = load(Models.scene_path(unit_id, 0)).instantiate()
		# Una malla, sin hijos que no sean marcadores (nada de luces ni particulas).
		for child in node.get_children():
			assert_bool(child is Marker3D).override_failure_message("%s lleva %s" % [unit_id, child.name]).is_true()
		# Solido, quiza brillo y el del bando: como mucho tres superficies.
		assert_int((node as MeshInstance3D).mesh.get_surface_count()).is_less_equal(3)
		node.free()

func test_the_six_new_units_have_their_silhouette_at_every_scale() -> void:
	for unit_id in NEW_UNITS:
		assert_bool(FileAccess.file_exists(UITheme.unit_icon_path(unit_id))).override_failure_message(
			"falta el icono de %s" % unit_id).is_true()
		assert_object(UITheme.unit_icon(unit_id)).is_not_null()
		for s in UITheme.ICON_SCALES:
			var tex := UITheme.unit_icon(unit_id, int(s))
			assert_object(tex).is_not_null()
			assert_int(tex.get_width()).is_equal(int(s))

# ── Animaciones y colocacion por dominio ─────────────────────────────

func test_attack_animation_of_the_new_units() -> void:
	for unit_id in ["dreadnought", "bomber", "airship"]:
		assert_str(BoardScript.attack_kind(unit_id, 3)).is_equal("shell")
	for unit_id in ["torpedo_boat", "gunboat", "fighter"]:
		assert_str(BoardScript.attack_kind(unit_id, 1)).is_equal("shot")

func _toy(unit_id: String, domain: String, side := 0, calm := false) -> Node3D:
	var toy: Node3D = auto_free(UnitToy.new())
	add_child(toy)
	toy.setup({"uid": 7, "unit_id": unit_id, "side": side, "hp": 50, "max_hp": 50,
		"domain": domain, "team_color": Color(0.3, 0.45, 0.62), "calm": calm})
	return toy

func test_planes_cast_a_ground_shadow_shaped_by_their_side() -> void:
	var ours := _toy("fighter", "air", 0)
	var theirs := _toy("fighter", "air", 1)
	var a: MeshInstance3D = ours.get_node_or_null("GroundShadow")
	var b: MeshInstance3D = theirs.get_node_or_null("GroundShadow")
	assert_object(a).is_not_null()
	assert_object(b).is_not_null()
	# Redonda la nuestra, rombo la de la Regencia; una malla por forma.
	assert_int((a.mesh as CylinderMesh).radial_segments).is_equal(12)
	assert_int((b.mesh as CylinderMesh).radial_segments).is_equal(4)
	assert_object(a.mesh).is_same(UnitToy.shadow_mesh(0))
	assert_float(ours.get_node("Lift").position.y).is_equal_approx(Layout.domain_height("air"), 0.001)

func test_ships_float_without_a_shadow_on_the_water() -> void:
	var ship := _toy("gunboat", "sea")
	assert_object(ship.get_node_or_null("GroundShadow")).is_null()
	assert_float(ship.get_node("Lift").position.y).is_less(0.0)
	assert_bool(ship.is_bobbing()).is_true()

func test_calm_quality_keeps_ships_and_planes_still() -> void:
	assert_bool(_toy("gunboat", "sea", 0, true).is_bobbing()).is_false()
	assert_bool(_toy("fighter", "air", 0, true).is_bobbing()).is_false()
	assert_bool(_toy("infantry", "land").is_bobbing()).is_false()

func test_a_plane_flies_straight_to_where_the_model_says() -> void:
	var plane := _toy("fighter", "air")
	plane.position = Vector3.ZERO
	var goal := Vector3(4, 0, -2)
	var tw: Tween = plane.move_along([Vector3(2, 0, 0), Vector3(2, 0, -2), goal], 0.01)
	await tw.finished
	assert_vector(plane.position).is_equal_approx(goal, Vector3(0.01, 0.01, 0.01))
	assert_float(plane.get_node("Lift/Body").position.y).is_equal_approx(0.0, 0.01)

func test_a_ship_sails_cell_by_cell_and_ends_level() -> void:
	var ship := _toy("torpedo_boat", "sea")
	ship.position = Vector3.ZERO
	var tw: Tween = ship.move_along([Vector3(2, 0, 0), Vector3(4, 0, 0)], 0.01)
	await tw.finished
	assert_vector(ship.position).is_equal_approx(Vector3(4, 0, 0), Vector3(0.01, 0.01, 0.01))
	assert_vector(ship.get_node("Lift/Body").rotation).is_equal_approx(Vector3.ZERO, Vector3(0.01, 0.01, 0.01))

# ── El terreno ───────────────────────────────────────────────────────

func test_terrain_is_read_defensively() -> void:
	assert_dict(Layout.terrain_of(null)).is_empty()
	# Un objeto sin `terrain` (un Encounter de antes de la rama de reglas) = todo tierra.
	assert_dict(Layout.terrain_of(RefCounted.new())).is_empty()
	var fake := FakeEncounter.new()
	fake.terrain = _coast()
	var t := Layout.terrain_of(fake)
	assert_bool(Layout.has_water(t)).is_true()
	assert_str(Layout.cell_kind(t, Vector2i(0, 3))).is_equal("water")
	assert_str(Layout.cell_kind(t, Vector2i(2, 3))).is_equal("shore")
	assert_str(Layout.cell_kind(t, Vector2i(5, 3))).is_equal("land")
	assert_float(Layout.ground_y(t, Vector2i(0, 0))).is_less(0.0)
	assert_float(Layout.ground_y(t, Vector2i(5, 0))).is_equal(0.0)

func test_a_ship_never_draws_its_route_across_land() -> void:
	var t := _coast()
	var board := Vector2i(8, 8)
	var blocked := Layout.route_blocked(t, "sea", board)
	assert_bool(blocked.has(Vector2i(5, 5))).is_true()
	assert_bool(blocked.has(Vector2i(0, 5))).is_false()
	assert_bool(blocked.has(Vector2i(2, 5))).is_false()
	# Tierra y aire no evitan nada; sin agua, nadie.
	assert_dict(Layout.route_blocked(t, "land", board)).is_empty()
	assert_dict(Layout.route_blocked(t, "air", board)).is_empty()
	assert_dict(Layout.route_blocked({}, "sea", board)).is_empty()
	var route: Array = Layout.path(Vector2i(0, 0), Vector2i(1, 6), blocked, board)
	for c in route:
		assert_str(Layout.cell_kind(t, c)).is_not_equal("land")

func test_water_costs_about_the_same_as_grass() -> void:
	# Mismo terreno, con y sin agua, en las dos vistas y las dos calidades: el
	# mar va en la misma malla y no debe pasar de un 10 % mas de triangulos.
	for front in [false, true]:
		for simple in [false, true]:
			var dry: Mesh = Terrain.build(Vector2i(8, 8), 7, simple, Terrain.SCENE_BEACH, front, {})
			var wet: Mesh = Terrain.build(Vector2i(8, 8), 7, simple, Terrain.SCENE_BEACH, front, _coast())
			assert_int(Models.tri_count(wet)).is_less_equal(int(Models.tri_count(dry) * 1.1))
			# Una sola malla: la superficie solida (y la de brillo como mucho).
			assert_int(wet.get_surface_count()).is_less_equal(2)

func test_a_board_with_water_opens_on_the_beach() -> void:
	var fake := FakeEncounter.new()
	fake.terrain = _coast()
	assert_str(BattleScreenScript.board_scene_for(fake, 3)).is_equal(Terrain.SCENE_BEACH)
	var dry := FakeEncounter.new()
	assert_str(BattleScreenScript.board_scene_for(dry, 3)).is_equal(Terrain.pick_scene(3, false))

# ── Tablero 2D ───────────────────────────────────────────────────────

func test_water_and_shore_have_their_own_board_tokens_in_every_palette() -> void:
	for palette in UITheme.PALETTES:
		for hc in [false, true]:
			var d: Dictionary = UITheme.resolve_tokens(palette, hc, 1.0)
			assert_bool(d["BOARD_WATER"] != d["BOARD_EMPTY"]).is_true()
			assert_bool(d["BOARD_WATER"] != d["BOARD_MOVE"]).is_true()
			assert_bool(d["BOARD_SHORE"] != d["BOARD_EMPTY"]).is_true()

func test_the_2d_board_paints_empty_water_cells_blue() -> void:
	var screen: CanvasLayer = auto_free(load("res://scenes/ui/BattleScreen.tscn").instantiate())
	add_child(screen)
	screen._recalculate_cell_size()
	screen._build_grid()
	screen._terrain_now = {Vector2i(0, 0): Layout.TERRAIN_WATER, Vector2i(1, 0): Layout.TERRAIN_SHORE}
	screen._style_cell(screen._cells[0], screen._cell_bars[0], screen._cell_icons[0],
		Vector2i(0, 0), null, null, [], [], -1)
	assert_object((screen._cells[0].get_theme_stylebox("normal") as StyleBoxFlat).bg_color).is_equal(UITheme.BOARD_WATER)
	screen._style_cell(screen._cells[1], screen._cell_bars[1], screen._cell_icons[1],
		Vector2i(1, 0), null, null, [], [], -1)
	assert_object((screen._cells[1].get_theme_stylebox("normal") as StyleBoxFlat).bg_color).is_equal(UITheme.BOARD_SHORE)
	# A donde se puede ir manda sobre el agua (lo que diga la regla se ve).
	screen._style_cell(screen._cells[0], screen._cell_bars[0], screen._cell_icons[0],
		Vector2i(0, 0), null, null, [Vector2i(0, 0)], [], -1)
	assert_object((screen._cells[0].get_theme_stylebox("normal") as StyleBoxFlat).bg_color).is_equal(UITheme.BOARD_MOVE)

# ── Astillero y Aerodromo ────────────────────────────────────────────

func test_shipyard_and_aerodrome_are_baked_within_budget() -> void:
	for id in NEW_BUILDINGS:
		var path := "res://assets/models/toy/%s.tscn" % id
		assert_bool(ResourceLoader.exists(path)).override_failure_message("falta " + path).is_true()
		var node: MeshInstance3D = load(path).instantiate()
		assert_int(Models.tri_count(node.mesh)).is_less_equal(BUILDING_TRI_BUDGET)
		# De ahi sale el efecto de "trabajando" (humo del taller, faro del mastil).
		assert_object(node.get_node_or_null("FxAnchor")).is_not_null()
		node.free()

func test_without_model_scene_the_factory_still_gives_their_toy() -> void:
	for id in NEW_BUILDINGS:
		var node: Node3D = Factory.create(id, 2.0, Vector2i(2, 2))
		assert_object(node).is_not_null()
		node.free()

func test_the_2d_art_draws_both_buildings() -> void:
	# Se pintan sin errores en un Control (el mismo camino que el icono del menu).
	for id in NEW_BUILDINGS:
		var c: Control = auto_free(Control.new())
		c.size = Vector2(128, 128)
		c.draw.connect(func(): BuildingArt2D_draw(c, id))
		add_child(c)
		c.queue_redraw()
	await await_idle_frame()

static func BuildingArt2D_draw(ci: CanvasItem, id: String) -> void:
	ci.draw_set_transform(Vector2(64, 64), 0.0, Vector2.ONE)
	preload("res://scripts/view2d/BuildingArt2D.gd").draw_building(ci, id, Vector2(128, 128), {"inset": 10.0})
