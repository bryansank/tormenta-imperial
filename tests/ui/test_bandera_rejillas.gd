extends GdUnitTestSuite
## Las rejillas de piezas de PAIS Y BANDERA (ColonyIdentityPanel) y de
## REGIMIENTO (RegimentCard), tras la queja de Bryan (2026-10-19): el candado y
## el rango iban pintados encima del color y cortados por abajo, las filas se
## cortaban y una muestra llevaba una raya confusa. Ahora (CartoonTheme.piece_tile):
## la pieza arriba, entera; debajo, dentro de la ficha, la placa [candado] N o la
## de "no se leeria"; todas las fichas de una rejilla igual de anchas; la
## elegida con borde grueso; "ninguno" con el simbolo de prohibido.

const SaveParking := preload("res://tests/save/save_parking.gd")
const IdentityPanel := preload("res://scripts/ui/ColonyIdentityPanel.gd")
const RegimentCard := preload("res://scripts/ui/RegimentCard.gd")
const CT := preload("res://scripts/ui/CartoonTheme.gd")
const ColonyFlag := preload("res://scripts/ui/ColonyFlag.gd")
const BACKUP_PATH := "user://save_game.bandera_rejillas.bak"

func before(do_skip := SaveParking.in_player_dir(), skip_reason := "Carpeta de usuario del jugador: lanza los tests con tools/run_tests.sh") -> void:
	pass

var _rank_saved: Dictionary = {}
var _mode_saved: Dictionary = {}
var _army_saved: Dictionary = {}

func before_test() -> void:
	SaveParking.park(BACKUP_PATH)
	_rank_saved = RankManager.get_save_data()
	_mode_saved = GameMode.get_save_data()
	_army_saved = ArmyManager.get_save_data()
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	RankManager.reset()
	ArmyManager.reset()
	RankManager.add_xp(RankManager.xp_for_rank(5))

func after_test() -> void:
	GameMode.load_save_data(_mode_saved)
	RankManager.reset()
	RankManager.load_save_data(_rank_saved)
	ArmyManager.reset()
	ArmyManager.load_save_data(_army_saved)
	SaveParking.restore(BACKUP_PATH)

func _editor() -> CanvasLayer:
	var panel: CanvasLayer = IdentityPanel.new()
	panel.auto_free = false
	add_child(panel)
	auto_free(panel)
	return panel

func _settle() -> void:
	for i in 4:
		await await_idle_frame()

func _rect(c: Control) -> Rect2:
	return c.get_global_rect()

## La placa va debajo de la pieza (sin tocarla) y dentro de la ficha.
func _assert_plate_below(btn: Button, piece: Control, plate: Control) -> void:
	var b := _rect(btn)
	var p := _rect(piece)
	var l := _rect(plate)
	assert_float(l.position.y).is_greater_equal(p.end.y)
	assert_bool(b.grow(0.5).encloses(l)).is_true()
	assert_bool(b.grow(0.5).encloses(p)).is_true()

func test_locked_colours_carry_the_plate_under_the_swatch_never_on_it() -> void:
	var panel := _editor()
	await await_idle_frame()
	panel.open("edit", "Monte Biela", {"pattern": "bands_h", "emblem": "gear", "colors": ["steel", "ivory", "crimson"]})
	panel.select_tab("colors")
	await _settle()
	var row: Control = panel.find_child("Colors_0", true, false)
	var locked := 0
	for btn in row.get_children():
		var swatch: ColorRect = btn.find_child("Swatch", true, false)
		var plate: Control = btn.find_child("RankLock", true, false)
		# La muestra se ve entera y opaca, aunque este cerrada.
		assert_float(swatch.color.a).is_equal(1.0)
		if btn.disabled and plate != null:
			locked += 1
			_assert_plate_below(btn, swatch, plate)
			var lbl: Label = plate.find_child("RankLockLabel", true, false)
			assert_int(int(lbl.text)).is_greater(5)
			assert_int(int(btn.get_meta("lock_rank"))).is_equal(int(lbl.text))
		else:
			assert_object(plate).is_null()
	assert_int(locked).is_greater(0)

func test_every_tile_in_a_grid_has_the_same_width() -> void:
	var panel := _editor()
	await await_idle_frame()
	panel.open("edit")
	for tab in ["patterns", "emblems", "colors"]:
		panel.select_tab(tab)
		await _settle()
		var grid_name: String = "Colors_0" if tab == "colors" else "Grid_" + tab
		var grid: Control = panel.find_child(grid_name, true, false)
		var widths := {}
		for btn in grid.get_children():
			widths[roundi((btn as Control).size.x)] = true
			# Nada se sale de la ficha: mide al menos lo que pide su contenido.
			var box: Control = btn.get_node("Box")
			assert_float((btn as Control).size.y + 0.5).is_greater_equal(box.get_combined_minimum_size().y)
		assert_int(widths.size()).override_failure_message("%s: %s" % [tab, widths.keys()]).is_equal(1)

func test_an_unreadable_colour_says_so_below_without_a_stripe_on_it() -> void:
	var panel := _editor()
	await await_idle_frame()
	panel.open("edit", "Monte Biela", {"pattern": "bands_h", "emblem": "gear", "colors": ["brass", "ivory", "crimson"]})
	panel.select_tab("colors")
	await _settle()
	var btn: Button = panel.find_child("Color_1_brass", true, false)
	assert_bool(btn.disabled).is_true()
	var mark: Control = btn.find_child("Unreadable", true, false)
	assert_object(mark).is_not_null()
	_assert_plate_below(btn, btn.find_child("Swatch", true, false), mark)
	assert_object(btn.find_child("RankLock", true, false)).is_null()
	# Una que si vale no lleva marca.
	var ok: Button = panel.find_child("Color_1_soot", true, false)
	assert_bool(ok.disabled).is_false()
	assert_object(ok.find_child("Unreadable", true, false)).is_null()

func test_the_no_emblem_piece_shows_the_none_symbol() -> void:
	var panel := _editor()
	await await_idle_frame()
	panel.open("edit")
	panel.select_tab("emblems")
	await _settle()
	var none: Button = panel.find_child("Piece_none", true, false)
	assert_object(none.find_child("NonePiece", true, false)).is_not_null()
	assert_object(none.find_child("NoneIcon", true, false)).is_not_null()

func test_the_chosen_tile_has_the_thick_brass_border() -> void:
	var panel := _editor()
	await await_idle_frame()
	panel.open("edit", "Monte Biela", {"pattern": "bands_h", "emblem": "gear", "colors": ["steel", "ivory", "crimson"]})
	await _settle()
	var chosen: Button = panel.find_child("Piece_bands_h", true, false)
	var other: Button = panel.find_child("Piece_plain", true, false)
	assert_bool(bool(chosen.get_meta("selected"))).is_true()
	var cs := chosen.get_theme_stylebox("normal") as StyleBoxFlat
	var os := other.get_theme_stylebox("normal") as StyleBoxFlat
	assert_int(cs.border_width_left).is_greater(os.border_width_left + 2)
	assert_that(cs.border_color).is_equal(CT.sem("ACCENT"))

func test_the_regiment_galleries_use_the_same_tiles() -> void:
	var card: PanelContainer = auto_free(RegimentCard.new())
	add_child(card)
	await await_idle_frame()
	card.toggle_editor()
	await _settle()
	# Pintura cerrada: placa debajo de la miniatura.
	var stripes_rank := 0
	for paint in GameConfig.REGIMENT_PAINTS:
		var btn: Button = card.find_child("Paint_" + paint, true, false)
		var plate: Control = btn.find_child("RankLock", true, false)
		if btn.disabled:
			assert_object(plate).is_not_null()
			var pic: Control = btn.get_node("Box").get_child(0)
			_assert_plate_below(btn, pic, plate)
			stripes_rank += 1
		else:
			assert_object(plate).is_null()
	assert_int(stripes_rank).is_greater(0)
	# "Sin emblema": el simbolo, no un disco liso.
	var none: Button = card.find_child("Emblem_none", true, false)
	assert_object(none.find_child("NonePiece", true, false)).is_not_null()
	# Mismo ancho en toda la fila de colores.
	var widths := {}
	for btn in card.find_child("RegimentColors", true, false).get_children():
		widths[roundi((btn as Control).size.x)] = true
	assert_int(widths.size()).is_equal(1)
