extends GdUnitTestSuite
## Los retratos del tablero: cada tipo de unidad se pinta con su silueta en vez
## de con la inicial del nombre, tenida con el color de su bando, apagada si ya
## gasto el turno, y con marco de laton si es el jefe.
##
## Casi todo se prueba llamando directamente al pintor de la celda con unidades
## hechas a mano: es lo que hace la pantalla en partida, solo que sin depender de
## que el enemigo haya movido ya. Lo que si necesita el manager (quien es el jefe,
## la franja de iniciativa) va aparte, dejando CombatManager como se encontro.
##
## Se tocan miembros privados a proposito, igual que en test_expedition_ui.gd: lo
## que se quiere vigilar es justo el dibujo.

const UNIT_IDS := ["infantry", "artillery", "vehicle"]

## El movil mas estrecho que el tablero tiene que aguantar (quickstart E9).
const PHONE := Vector2i(400, 720)

func before_test() -> void:
	CombatManager.reset()

func after_test() -> void:
	CombatManager.end_encounter()
	CombatManager.reset()

# ── Utilidades ───────────────────────────────────────────────────────

func _screen() -> CanvasLayer:
	var screen: CanvasLayer = auto_free(load("res://scenes/ui/BattleScreen.tscn").instantiate())
	add_child(screen)
	return screen

## La pantalla con el 8x8 ya montado. En partida lo monta `encounter_started`;
## aqui se pide a mano para poder pintar una casilla sin abrir una pelea.
func _board() -> CanvasLayer:
	var screen := _screen()
	screen._recalculate_cell_size()
	screen._build_grid()
	return screen

## La misma pantalla, mirando una resolucion de movil. En headless la ventana
## real no baja de 1280 de ancho, asi que el telefono se monta con un SubViewport:
## para la pantalla es su viewport, que es lo unico que mira para dimensionarse.
func _phone_board(size: Vector2i) -> CanvasLayer:
	var sub: SubViewport = auto_free(SubViewport.new())
	sub.size = size
	sub.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(sub)
	var screen: CanvasLayer = load("res://scenes/ui/BattleScreen.tscn").instantiate()
	sub.add_child(screen)
	return screen

func _unit(unit_id: String, side: int, uid: int = 1) -> CombatUnit:
	return CombatUnit.create(uid, unit_id, side, 1.0)

## Pinta una unidad en la casilla (0, 0) y devuelve la pantalla ya lista para
## interrogar. `boss` es el uid que lleva marco, o -1 si no hay jefe.
func _paint(screen: CanvasLayer, unit, boss: int = -1) -> void:
	screen._style_cell(
		screen._cells[0], screen._cell_bars[0], screen._cell_icons[0],
		Vector2i(0, 0), unit, null, [], [], boss)

func _cell_style(screen: CanvasLayer) -> StyleBoxFlat:
	return screen._cells[0].get_theme_stylebox("normal")

# ── Los ficheros ─────────────────────────────────────────────────────

func test_every_unit_type_has_its_icon_on_disk() -> void:
	# Sin PNG no hay silueta, y sin silueta el tablero vuelve a las iniciales.
	for unit_id in GameConfig.get_unit_ids():
		var path: String = UITheme.unit_icon_path(unit_id)
		assert_bool(FileAccess.file_exists(path)).override_failure_message(
			"falta el icono de %s en %s" % [unit_id, path]).is_true()

func test_the_three_unit_types_of_the_game_are_the_three_that_have_an_icon() -> void:
	assert_array(GameConfig.get_unit_ids()).contains_exactly_in_any_order(UNIT_IDS)
	for unit_id in UNIT_IDS:
		assert_object(UITheme.unit_icon(unit_id)).override_failure_message(
			"el icono de %s no esta importado" % unit_id).is_not_null()

func test_a_unit_type_without_a_file_has_no_icon() -> void:
	assert_bool(FileAccess.file_exists(UITheme.unit_icon_path("ghost"))).is_false()
	assert_object(UITheme.unit_icon("ghost")).is_null()
	assert_object(UITheme.unit_icon("")).is_null()

# ── La celda ─────────────────────────────────────────────────────────

func test_the_cell_draws_the_silhouette_instead_of_the_initial() -> void:
	var screen := _board()
	await await_idle_frame()
	for unit_id in UNIT_IDS:
		_paint(screen, _unit(unit_id, 0))
		var icon: TextureRect = screen.board_cell_icon(Vector2i(0, 0))
		assert_object(icon.texture).override_failure_message(
			"la celda no cogio el icono de %s" % unit_id).is_not_null()
		assert_bool(icon.visible).is_true()
		assert_str(screen.board_cell(Vector2i(0, 0)).text).is_empty()

func test_an_empty_cell_shows_neither_icon_nor_letter() -> void:
	var screen := _board()
	await await_idle_frame()
	_paint(screen, _unit("infantry", 0))
	_paint(screen, null)
	var icon: TextureRect = screen.board_cell_icon(Vector2i(0, 0))
	assert_bool(icon.visible).is_false()
	assert_object(icon.texture).is_null()
	assert_str(screen.board_cell(Vector2i(0, 0)).text).is_empty()
	assert_bool(screen._cell_bars[0].visible).is_false()

func test_the_tint_tells_the_two_sides_apart() -> void:
	var screen := _board()
	await await_idle_frame()
	_paint(screen, _unit("infantry", 0))
	var mine: Color = screen.board_cell_icon(Vector2i(0, 0)).modulate
	_paint(screen, _unit("infantry", 1, 2))
	var theirs: Color = screen.board_cell_icon(Vector2i(0, 0)).modulate

	assert_bool(mine.is_equal_approx(theirs)).override_failure_message(
		"los dos bandos se pintan del mismo color").is_false()
	assert_bool(mine.is_equal_approx(UITheme.unit_icon_tint(true))).is_true()
	assert_bool(theirs.is_equal_approx(UITheme.unit_icon_tint(false))).is_true()
	# Y no es solo el brillo: el tono cambia de verde a oxido.
	assert_bool(mine.g > mine.r).is_true()
	assert_bool(theirs.r > theirs.g).is_true()

func test_a_unit_that_already_acted_is_painted_dimmed() -> void:
	var screen := _board()
	await await_idle_frame()
	var unit := _unit("artillery", 0)
	_paint(screen, unit)
	var fresh: float = screen.board_cell_icon(Vector2i(0, 0)).modulate.a

	unit.has_acted = true
	_paint(screen, unit)
	var spent: float = screen.board_cell_icon(Vector2i(0, 0)).modulate.a

	assert_float(fresh).is_equal_approx(1.0, 0.001)
	assert_float(spent).is_equal_approx(UITheme.UNIT_ICON_SPENT_ALPHA, 0.001)
	assert_float(spent).is_less(fresh)

func test_the_health_bar_survives_the_icon() -> void:
	# El icono ocupa el hueco de arriba; la barra sigue siendo la de siempre.
	var screen := _board()
	await await_idle_frame()
	var unit := _unit("vehicle", 1)
	unit.take_damage(int(unit.max_hp / 2))
	_paint(screen, unit)
	var bar: ProgressBar = screen._cell_bars[0]
	assert_bool(bar.visible).is_true()
	assert_float(bar.value).is_equal_approx(float(unit.hp) / float(unit.max_hp), 0.01)

# ── El repuesto ──────────────────────────────────────────────────────

func test_without_the_icon_file_the_cell_falls_back_to_the_initial() -> void:
	# Una unidad cuyo PNG no existe no puede dejar la casilla en blanco: se pinta
	# la inicial, como antes de que hubiera iconos, y no salta nada.
	var screen := _board()
	await await_idle_frame()
	var unit := _unit("ghost", 1)
	_paint(screen, unit)
	var cell: Button = screen.board_cell(Vector2i(0, 0))
	assert_object(screen.board_cell_icon(Vector2i(0, 0)).texture).is_null()
	assert_bool(screen.board_cell_icon(Vector2i(0, 0)).visible).is_false()
	assert_str(cell.text).is_not_empty()
	# La inicial tambien distingue bando, que es lo que el icono habria hecho.
	var color: Color = cell.get_theme_color("font_color")
	assert_bool(color.is_equal_approx(UITheme.unit_icon_tint(false))).is_true()

func test_the_fallback_letter_dims_too_when_the_unit_has_acted() -> void:
	var screen := _board()
	await await_idle_frame()
	var unit := _unit("ghost", 0)
	unit.has_acted = true
	_paint(screen, unit)
	assert_float(screen.board_cell(Vector2i(0, 0)).get_theme_color("font_color").a) \
		.is_equal_approx(UITheme.UNIT_ICON_SPENT_ALPHA, 0.001)

# ── El jefe ──────────────────────────────────────────────────────────

func test_the_boss_wears_a_frame_that_a_normal_unit_does_not() -> void:
	var screen := _board()
	await await_idle_frame()
	var unit := _unit("vehicle", 1, 7)

	_paint(screen, unit, -1)
	var plain := _cell_style(screen)
	assert_int(plain.shadow_size).is_equal(0)

	_paint(screen, unit, 7)
	var boss := _cell_style(screen)
	assert_int(boss.shadow_size).is_equal(UITheme.BOSS_GLOW_SIZE)
	assert_int(boss.border_width_top).is_greater_equal(UITheme.BOSS_BORDER_MIN)
	assert_bool(boss.shadow_color.is_equal_approx(plain.shadow_color)).is_false()

func test_the_boss_frame_only_lands_on_the_boss() -> void:
	var screen := _board()
	await await_idle_frame()
	# Mismo tipo de unidad, distinto uid: lo que marca es quien es, no que es.
	_paint(screen, _unit("vehicle", 1, 3), 7)
	assert_int(_cell_style(screen).shadow_size).is_equal(0)

func test_the_boss_of_a_boss_encounter_is_the_heaviest_enemy() -> void:
	var screen := _board()
	await await_idle_frame()
	var mine: Array = [_unit("infantry", Encounter.PLAYER, 1)]
	CombatManager.start_encounter_with_units(mine, {"infantry": 2, "vehicle": 1}, true, 0, false, [1])
	await await_idle_frame()

	var boss: int = screen.boss_uid()
	assert_int(boss).is_greater(0)
	var champion: CombatUnit = CombatManager.get_unit(boss)
	assert_str(champion.unit_id).is_equal("vehicle")
	assert_int(champion.side).is_equal(Encounter.ENEMY)

func test_a_plain_encounter_has_no_boss_at_all() -> void:
	var screen := _board()
	await await_idle_frame()
	var mine: Array = [_unit("infantry", Encounter.PLAYER, 1)]
	CombatManager.start_encounter_with_units(mine, {"infantry": 2}, false, 0, false, [1])
	await await_idle_frame()
	assert_int(screen.boss_uid()).is_equal(-1)

# ── La franja de iniciativa ──────────────────────────────────────────

func test_the_initiative_chip_wears_the_same_silhouette() -> void:
	var screen := _board()
	await await_idle_frame()
	var chip: Label = auto_free(Label.new())
	screen._paint_order_face(chip, _unit("artillery", 1), true)
	assert_str(chip.text).is_empty()
	assert_int(chip.get_child_count()).is_equal(1)
	var icon: TextureRect = chip.get_child(0)
	assert_object(icon.texture).is_same(UITheme.unit_icon("artillery"))
	assert_bool(icon.texture.get_size().x > 0.0).is_true()

func test_the_initiative_chip_falls_back_to_the_initial_too() -> void:
	var screen := _board()
	await await_idle_frame()
	var chip: Label = auto_free(Label.new())
	screen._paint_order_face(chip, _unit("ghost", 0), false)
	assert_str(chip.text).is_not_empty()
	assert_int(chip.get_child_count()).is_equal(0)

func test_the_initiative_strip_draws_one_chip_per_living_unit() -> void:
	var screen := _board()
	await await_idle_frame()
	var mine: Array = [_unit("infantry", Encounter.PLAYER, 1)]
	CombatManager.start_encounter_with_units(mine, {"infantry": 2}, false, 0, false, [1])
	await await_idle_frame()

	var chips: Array = screen.order_chips()
	assert_array(chips).is_not_empty()
	for chip in chips:
		# Cada ficha lleva retrato: silueta dentro o inicial escrita, nunca vacia.
		assert_bool(chip.get_child_count() > 0 or chip.text != "").override_failure_message(
			"una ficha de la franja quedo sin retrato").is_true()
		assert_float(chip.custom_minimum_size.x).is_greater_equal(24.0)
		assert_float(chip.custom_minimum_size.y).is_greater_equal(24.0)

# ── Legibilidad en un movil (400x720) ────────────────────────────────

func test_the_cell_still_fits_on_a_phone_screen() -> void:
	var screen := _phone_board(PHONE)
	await await_idle_frame()

	var mine: Array = [_unit("infantry", Encounter.PLAYER, 1)]
	CombatManager.start_encounter_with_units(mine, {"infantry": 2, "artillery": 1}, false, 0, false, [1])
	await await_idle_frame()
	await await_idle_frame()

	# El tablero recalcula la celda al abrirse: ni se sale ni se vuelve un punto.
	var viewport: Vector2 = screen.get_viewport().get_visible_rect().size
	assert_vector(viewport).is_equal(Vector2(PHONE))
	assert_int(screen._cell_size).is_greater_equal(34)
	assert_float(float(screen._cell_size * 8)).is_less_equal(viewport.x)
	for y in range(8):
		for x in range(8):
			var cell: Button = screen.board_cell(Vector2i(x, y))
			assert_float(cell.global_position.x).is_greater_equal(-1.0)
			assert_float(cell.global_position.x + cell.size.x).is_less_equal(viewport.x + 1.0)
			assert_float(cell.global_position.y).is_greater_equal(-1.0)
			assert_float(cell.global_position.y + cell.size.y).is_less_equal(viewport.y + 1.0)

			# Icono y barra viven dentro de su casilla y no se pisan.
			var icon: TextureRect = screen.board_cell_icon(Vector2i(x, y))
			var bar: ProgressBar = screen._cell_bars[y * 8 + x]
			assert_float(icon.size.x).is_greater(0.0)
			assert_float(icon.size.y).is_greater(0.0)
			assert_float(icon.position.y + icon.size.y).is_less_equal(bar.position.y + 0.5)
			assert_float(icon.position.x + icon.size.x).is_less_equal(cell.size.x + 0.5)
			assert_float(bar.position.y + bar.size.y).is_less_equal(cell.size.y + 0.5)
