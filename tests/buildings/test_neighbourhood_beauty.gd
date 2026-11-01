extends GdUnitTestSuite
## Belleza del barrio (feat/belleza-barrio, doc 21 §6.4; nacio en
## feat/edificios-defensa-vida y se saco de la 1.2): cada decoracion da a las
## Casas cercanas tanta belleza como moral; con 10 la casa es bonita (+1 sitio,
## +moral) y con 25 elegante (+2). Fija los valores y umbrales, el reparto sobre
## la rejilla (radio, en pie, con carretera), la zona del fantasma, la ficha y
## los adornos de las dos vistas. Sin Nucleo 1-5 ni planos: nada lo pide.
##
## Escrita sin correr (regla de Bryan: un solo pase de pruebas al final).
## Toca la rejilla de verdad: cada prueba quita lo que pone.

const Effects := preload("res://scripts/buildings/DefenseLifeEffects.gd")
const Trim := preload("res://scripts/buildings/BeautyTrim.gd")
const Info := preload("res://scripts/ui/BuildingInfoPanel.gd")
const Icon := preload("res://scripts/ui/CartoonIcon.gd")

var _placed: Array = []

func before_test() -> void:
	_placed = []

func after_test() -> void:
	for node in _placed:
		GridManager.remove_building(node)
		if is_instance_valid(node):
			node.free()
	_placed = []
	Effects.refresh()

func _data(id: String) -> BuildingData:
	return load("res://data/buildings/%s.tres" % id) as BuildingData

## Un edificio de mentira en la rejilla, en pie y con carretera.
func _put(id: String, origin: Vector2i) -> Node3D:
	var node := Node3D.new()
	add_child(node)
	node.set_meta("connected", true)
	var ok := GridManager.place_building(origin, _data(id), node)
	assert_bool(ok).override_failure_message("no cabe %s en %s" % [id, origin]).is_true()
	_placed.append(node)
	return node

## Un hueco libre de tierra de `w` x `h` casillas cerca del centro.
func _free_area(w: int, h: int) -> Vector2i:
	var cx: int = GridManager.grid_width / 2
	var cy: int = GridManager.grid_height / 2
	for dy in range(-14, 10, 2):
		for dx in range(-14, 6, 2):
			var o := Vector2i(cx + dx, cy + dy)
			if GridManager.can_place(o, Vector2i(w, h)):
				return o
	return Vector2i(-1, -1)

# ── Valores ───────────────────────────────────────────────────────────

func test_a_decoration_gives_as_much_beauty_as_morale() -> void:
	for id in ["garden", "fountain", "statue", "hedge", "governor_plaza"]:
		var d := _data(id)
		assert_int(GameConfig.beauty_of(d)).override_failure_message(id).is_equal(d.morale_bonus)
	# La carretera no da belleza aunque sea "decoracion"; un taller, tampoco.
	assert_int(GameConfig.beauty_of(_data("road"))).is_equal(0)
	assert_int(GameConfig.beauty_of(_data("sawmill"))).is_equal(0)
	assert_int(GameConfig.beauty_of(_data("house"))).is_equal(0)
	# Mejorada, vale mas.
	assert_int(GameConfig.beauty_of(_data("garden"), 3)).is_greater(GameConfig.beauty_of(_data("garden"), 1))

func test_every_decoration_counts_without_touching_the_table() -> void:
	var dir := DirAccess.open("res://data/buildings")
	for file in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var d := load("res://data/buildings/" + file) as BuildingData
		if d != null and d.is_decoration and d.id != "road":
			assert_int(GameConfig.beauty_of(d)).override_failure_message(d.id).is_greater(0)
			assert_bool(Effects.takes_part(d)).override_failure_message(d.id).is_true()

func test_levels_room_and_morale() -> void:
	assert_int(GameConfig.beauty_level_for(0)).is_equal(1)
	assert_int(GameConfig.beauty_level_for(9)).is_equal(1)
	assert_int(GameConfig.beauty_level_for(10)).is_equal(2)
	assert_int(GameConfig.beauty_level_for(24)).is_equal(2)
	assert_int(GameConfig.beauty_level_for(25)).is_equal(3)
	assert_int(GameConfig.beauty_level_for(999)).is_equal(3)
	assert_int(GameConfig.beauty_room_for(1)).is_equal(0)
	assert_int(GameConfig.beauty_room_for(2)).is_equal(1)
	assert_int(GameConfig.beauty_room_for(3)).is_equal(2)
	assert_int(GameConfig.beauty_morale_for(1)).is_equal(0)
	assert_int(GameConfig.beauty_morale_for(3)).is_greater(GameConfig.beauty_morale_for(2))

# ── Reparto sobre la rejilla ──────────────────────────────────────────

func test_a_garden_and_a_fountain_next_door_make_a_pretty_house() -> void:
	var o := _free_area(6, 2)
	if o.x < 0:
		return
	var house := _put("house", o)
	_put("garden", o + Vector2i(2, 0))
	_put("fountain", o + Vector2i(4, 0))
	var out := Effects.refresh()
	var expected := _data("garden").morale_bonus + _data("fountain").morale_bonus
	assert_int(Effects.beauty_points(house)).is_equal(expected)
	assert_int(Effects.beauty_level(house)).is_equal(GameConfig.beauty_level_for(expected))
	assert_bool(bool(out["beauty_changed"])).is_true()
	assert_int(int(house.get_meta(Effects.BEAUTY_ROOM_META, 0))).is_equal(GameConfig.beauty_room_for(Effects.beauty_level(house)))
	# Un segundo recuento sin cambios no avisa (nada de bucles con la gente).
	assert_bool(bool(Effects.refresh()["beauty_changed"])).is_false()

func test_beyond_the_radius_it_does_not_count() -> void:
	var r := GameConfig.beauty_radius
	var o := _free_area(4 + r + 1, 2)
	if o.x < 0:
		return
	var house := _put("house", o)
	_put("statue", o + Vector2i(2 + r + 1, 0))
	Effects.refresh()
	assert_int(Effects.beauty_points(house)).is_equal(0)
	assert_int(Effects.beauty_level(house)).is_equal(1)
	assert_bool(house.has_meta(Effects.BEAUTY_LEVEL_META)).is_false()

func test_a_house_without_a_road_gets_no_beauty() -> void:
	var o := _free_area(4, 2)
	if o.x < 0:
		return
	var house := _put("house", o)
	house.set_meta("connected", false)
	_put("statue", o + Vector2i(2, 0))
	Effects.refresh()
	assert_int(Effects.beauty_points(house)).is_equal(0)

func test_a_decoration_under_construction_gives_nothing() -> void:
	var o := _free_area(4, 2)
	if o.x < 0:
		return
	var house := _put("house", o)
	var statue := _put("statue", o + Vector2i(2, 0))
	statue.set_meta("under_construction", true)
	Effects.refresh()
	assert_int(Effects.beauty_points(house)).is_equal(0)

func test_demolishing_the_decoration_takes_the_beauty_away() -> void:
	var o := _free_area(4, 2)
	if o.x < 0:
		return
	var house := _put("house", o)
	var statue := _put("statue", o + Vector2i(2, 0))
	Effects.refresh()
	assert_int(Effects.beauty_points(house)).is_greater(0)
	GridManager.remove_building(statue)
	_placed.erase(statue)
	statue.free()
	assert_bool(bool(Effects.refresh()["beauty_changed"])).is_true()
	assert_int(Effects.beauty_points(house)).is_equal(0)

# ── Zona del fantasma ─────────────────────────────────────────────────

func test_the_zone_is_the_radius_around_the_footprint() -> void:
	var r := GameConfig.beauty_radius
	var o := Vector2i(GridManager.grid_width / 2, GridManager.grid_height / 2)
	var rect := Effects.zone_rect(o, Vector2i(2, 2))
	assert_that(rect.position).is_equal(o - Vector2i(r, r))
	assert_that(rect.size).is_equal(Vector2i(2 + 2 * r, 2 + 2 * r))
	# El contorno: solo el borde.
	var ring := Effects.ring_cells(rect)
	assert_int(ring.size()).is_equal(2 * rect.size.x + 2 * rect.size.y - 4)
	# En la esquina de la rejilla se recorta.
	var corner := Effects.zone_rect(Vector2i.ZERO, Vector2i(2, 2))
	assert_that(corner.position).is_equal(Vector2i.ZERO)

func test_a_decoration_ghost_finds_the_houses_it_reaches() -> void:
	var o := _free_area(6, 2)
	if o.x < 0:
		return
	var house := _put("house", o)
	var z := Effects.zone_partners(_data("fountain"), o + Vector2i(4, 0), Vector2i(2, 2))
	assert_array(z["nodes"]).contains([house])
	assert_int(int(z["points"])).is_equal(_data("fountain").morale_bonus)
	assert_int((z["cells"] as Array).size()).is_equal(4)

func test_a_house_ghost_adds_up_what_it_would_get() -> void:
	var o := _free_area(6, 2)
	if o.x < 0:
		return
	_put("garden", o)
	_put("statue", o + Vector2i(2, 0))
	var z := Effects.zone_partners(_data("house"), o + Vector2i(4, 0), Vector2i(2, 2))
	assert_int(int(z["points"])).is_equal(_data("garden").morale_bonus + _data("statue").morale_bonus)
	assert_int((z["nodes"] as Array).size()).is_equal(2)

func test_a_workshop_has_no_zone() -> void:
	var z := Effects.zone_partners(_data("sawmill"), Vector2i(4, 4), Vector2i(2, 2))
	assert_array(z["nodes"]).is_empty()
	assert_bool(Effects.takes_part(_data("sawmill"))).is_false()

# ── Ficha ─────────────────────────────────────────────────────────────

func test_the_chip_is_a_flower_and_a_number_with_the_detail_on_hold() -> void:
	assert_bool(Icon.GLYPHS.has("flower")).is_true()
	var o := _free_area(4, 2)
	if o.x < 0:
		return
	var house := _put("house", o)
	var statue := _put("statue", o + Vector2i(2, 0))
	Effects.refresh()
	var chip: Control = Info.beauty_chip(house, _data("house"))
	assert_object(chip).is_not_null()
	assert_str(chip.tooltip_text).is_not_empty()
	chip.free()
	var deco_chip: Control = Info.beauty_chip(statue, _data("statue"))
	assert_object(deco_chip).is_not_null()
	assert_str(deco_chip.tooltip_text).is_not_empty()
	deco_chip.free()
	# En obras, o en un taller, no hay ficha.
	assert_object(Info.beauty_chip(house, _data("house"), true)).is_null()

func test_texts_in_both_languages() -> void:
	var before := Tr.get_locale()
	for locale in ["es", "en"]:
		Tr.set_locale(locale)
		for key in ["UI2C_CHIP_BEAUTY", "LBL_BEAUTY_WORD_PLAIN", "LBL_BEAUTY_WORD_PRETTY",
				"LBL_BEAUTY_WORD_ELEGANT", "LBL_BEAUTY_PLAIN", "LBL_BEAUTY_PRETTY", "LBL_BEAUTY_ELEGANT",
				"LBL_BEAUTY_NEXT", "LBL_BEAUTY_DECO", "HELP_T_BEAUTY", "HELP_B_BEAUTY"]:
			assert_str(Tr.t(key)).override_failure_message(key).is_not_equal(key)
	Tr.set_locale(before)

func test_the_help_knows_it() -> void:
	assert_bool(preload("res://scripts/ui/HelpCatalog.gd").ENTRIES.has("beauty")).is_true()
	assert_bool(TutorialManager.TIPS.has("beauty")).is_true()
	assert_bool(EventBus.has_signal("beauty_changed")).is_true()

# ── Adornos ───────────────────────────────────────────────────────────

func test_beauty_trim_is_cached_per_level_and_size() -> void:
	var a := Trim.trim_mesh(2, Vector3(2.8, 2.0, 2.8))
	assert_object(Trim.trim_mesh(2, Vector3(2.8, 2.0, 2.8))).is_same(a)
	var b := Trim.trim_mesh(3, Vector3(2.8, 2.0, 2.8))
	assert_object(b).is_not_same(a)
	# El elegante lleva mas piezas (hiedra, farolas, banderines).
	var va := (a.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var vb := (b.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	assert_int(vb).is_greater(va)
