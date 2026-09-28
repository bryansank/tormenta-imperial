extends GdUnitTestSuite
## El prologo es un documento que se lee: Atras, Siguiente y Saltar siempre a la
## vista, deslizar el dedo pasa folio, y no se confunde con el tutorial (docs/07
## bugs 2 y 12). Se prueba la pantalla sola, sin partida.

const PrologueScene := preload("res://scenes/ui/PrologueScreen.tscn")

var _closed := 0

func before_test() -> void:
	_closed = 0

func after_test() -> void:
	get_tree().paused = false

func _screen(variant: String = "full") -> CanvasLayer:
	var s: CanvasLayer = auto_free(PrologueScene.instantiate())
	add_child(s)
	s.closed.connect(func(): _closed += 1)
	s.open(variant)
	return s

func test_it_opens_at_the_first_folio_on_top_of_everything() -> void:
	var s := _screen()
	assert_bool(s.is_open()).is_true()
	assert_int(s.current_page()).is_equal(0)
	assert_int(s.page_count()).is_equal(6)
	# Encima del menu de pausa y del principal (capa 30).
	assert_int(s.layer).is_greater(30)

func test_back_is_disabled_on_the_first_folio_and_does_nothing() -> void:
	var s := _screen()
	assert_bool(s.back_button().disabled).is_true()
	s.prev_page()
	assert_int(s.current_page()).is_equal(0)

func test_next_three_times_then_back_lands_on_folio_two() -> void:
	# El caso de docs/07 bug 2: Siguiente x3 + Atras -> pagina 2 (indice).
	var s := _screen()
	for i in 3:
		# Con el texto ya escrito, Siguiente pasa folio (si no, lo completaria).
		s.call("_finish_typing")
		s.next_button().pressed.emit()
	assert_int(s.current_page()).is_equal(3)
	s.back_button().pressed.emit()
	assert_int(s.current_page()).is_equal(2)
	assert_bool(s.back_button().disabled).is_false()

func test_next_first_finishes_the_typing_then_turns_the_folio() -> void:
	var s := _screen()
	assert_bool(s.is_typing()).is_true()
	s.next_button().pressed.emit()
	assert_bool(s.is_typing()).is_false()
	assert_int(s.current_page()).is_equal(0)
	s.next_button().pressed.emit()
	assert_int(s.current_page()).is_equal(1)

func test_next_on_the_last_folio_closes_it() -> void:
	var s := _screen()
	s.go_to_page(5)
	s.next_page()
	assert_bool(s.is_open()).is_false()
	assert_int(_closed).is_equal(1)

func test_skip_closes_from_any_folio() -> void:
	var s := _screen()
	s.go_to_page(2)
	s.skip_button().pressed.emit()
	assert_bool(s.is_open()).is_false()
	assert_int(_closed).is_equal(1)

func test_a_left_swipe_turns_forward_and_a_right_swipe_goes_back() -> void:
	var s := _screen()
	assert_bool(s.handle_swipe(Vector2(-200, 10))).is_true()
	assert_int(s.current_page()).is_equal(1)
	assert_bool(s.handle_swipe(Vector2(-200, 0))).is_true()
	assert_int(s.current_page()).is_equal(2)
	assert_bool(s.handle_swipe(Vector2(220, -8))).is_true()
	assert_int(s.current_page()).is_equal(1)

func test_a_short_or_vertical_drag_is_not_a_swipe() -> void:
	var s := _screen()
	assert_bool(s.handle_swipe(Vector2(-30, 0))).is_false()
	assert_bool(s.handle_swipe(Vector2(-120, 200))).is_false()
	assert_int(s.current_page()).is_equal(0)

func test_a_swipe_never_closes_it_on_the_last_folio() -> void:
	# Cerrar es una decision (Empezar / Saltar), no un gesto que se escapa.
	var s := _screen()
	s.go_to_page(5)
	s.handle_swipe(Vector2(-300, 0))
	assert_bool(s.is_open()).is_true()
	assert_int(s.current_page()).is_equal(5)

func test_it_pauses_the_game_and_gives_the_pause_back() -> void:
	get_tree().paused = false
	var s := _screen()
	var paused_open: bool = get_tree().paused
	var mode: int = s.process_mode
	s.close()
	assert_bool(paused_open).is_true()
	assert_int(mode).is_equal(Node.PROCESS_MODE_ALWAYS)
	assert_bool(get_tree().paused).is_false()

func test_it_does_not_release_a_pause_it_did_not_take() -> void:
	# Reabierto desde el menu de pausa: el arbol ya estaba parado.
	get_tree().paused = true
	var s := _screen()
	s.close()
	assert_bool(get_tree().paused).is_true()
	get_tree().paused = false

func test_the_builder_variant_is_short_and_has_its_own_ending() -> void:
	var s := _screen("short")
	assert_int(s.page_count()).is_equal(2)
	s.go_to_page(1)
	assert_str(s.title_text()).is_equal(Tr.t("PRO_B_TITLE"))

func test_every_folio_has_title_body_and_note_in_both_languages() -> void:
	var saved := Tr.get_locale()
	var ids: Array = []
	for v in ["full", "short"]:
		for id in (load("res://scripts/ui/PrologueScreen.gd") as GDScript).get_script_constant_map()["VARIANTS"][v]:
			if not id in ids:
				ids.append(id)
	for loc in ["es", "en"]:
		Tr.set_locale(loc)
		for id in ids:
			for part in ["TITLE", "BODY", "NOTE"]:
				var key := "PRO_%s_%s" % [id, part]
				assert_str(Tr.t(key)).is_not_equal(key)
		for key in ["PRO_1_STAMP", "PRO_6_STAMP", "PRO_B_STAMP", "BTN_PROLOGUE_BACK", "BTN_PROLOGUE_NEXT", "BTN_PROLOGUE_SKIP", "PRO_HINT_TOUCH"]:
			assert_str(Tr.t(key)).is_not_equal(key)
	Tr.set_locale(saved)

func test_it_does_not_look_like_the_tutorial() -> void:
	# El prologo no usa la tarjeta de metal del tutorial ni sus botones: papel,
	# tinta y lacre. Se mira que haya sello y fuente de maquina de escribir.
	var s := _screen()
	assert_object(s.find_child("Seal", true, false)).is_not_null()
	var body: Label = s.find_child("Body", true, false)
	assert_object(body.get_theme_font("font")).is_equal(UITheme.typewriter_font())
	assert_that(body.get_theme_color("font_color")).is_equal(UITheme.INK)
