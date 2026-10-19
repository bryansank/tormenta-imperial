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
	# Cuatro folios: la firma, la Tormenta, quienes somos y la hoja final.
	assert_int(s.page_count()).is_equal(4)
	# Encima del menu de pausa y del principal (capa 30).
	assert_int(s.layer).is_greater(30)

func test_back_is_disabled_on_the_first_folio_and_does_nothing() -> void:
	var s := _screen()
	assert_bool(s.back_button().disabled).is_true()
	s.prev_page()
	assert_int(s.current_page()).is_equal(0)

func test_next_twice_then_back_lands_on_folio_two() -> void:
	# El caso de docs/07 bug 2 (Siguiente + Atras vuelve un folio), con los
	# folios de ahora: Siguiente x2 + Atras -> folio 2 (indice 1).
	var s := _screen()
	for i in 2:
		# Con el texto ya escrito, Siguiente pasa folio (si no, lo completaria).
		s.call("_finish_typing")
		s.next_button().pressed.emit()
	assert_int(s.current_page()).is_equal(2)
	s.back_button().pressed.emit()
	assert_int(s.current_page()).is_equal(1)
	assert_bool(s.back_button().disabled).is_false()

## Sin animacion (docs/28 §0.6): el folio sale entero y Siguiente pasa de
## folio al primer toque.
func test_the_folio_comes_out_whole_and_next_turns_it() -> void:
	var s := _screen()
	assert_bool(s.is_typing()).is_false()
	assert_float((s.find_child("Body", true, false) as Label).visible_ratio).is_equal(1.0)
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
	var last: int = s.page_count() - 1
	s.go_to_page(last)
	s.handle_swipe(Vector2(-300, 0))
	assert_bool(s.is_open()).is_true()
	assert_int(s.current_page()).is_equal(last)

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
		for key in ["PRO_1_STAMP", "PRO_3_STAMP", "PRO_B_STAMP", "BTN_PROLOGUE_BACK", "BTN_PROLOGUE_NEXT", "BTN_PROLOGUE_SKIP", "PRO_HINT_TOUCH"]:
			assert_str(Tr.t(key)).is_not_equal(key)
	Tr.set_locale(saved)

func test_it_does_not_look_like_the_tutorial() -> void:
	# El prologo no usa la tarjeta de metal del tutorial ni sus botones: papel,
	# tinta y lacre. Se mira que haya sello y fuente de maquina de escribir.
	var s := _screen()
	assert_object(s.find_child("Seal", true, false)).is_not_null()
	var body: Label = s.find_child("Body", true, false)
	# Letra del estilo nuevo (docs/28 §3) sobre el folio crema.
	assert_object(body.get_theme_font("font")).is_equal(CartoonTheme.body_font())
	assert_that(body.get_theme_color("font_color")).is_equal(CartoonTheme.text("window"))

# ── La hoja final (2026-10-04) ───────────────────────────────────────

func test_the_last_folio_before_playing_is_the_plan() -> void:
	# Construir desde cero, economia, soldados, pelear contra el Imperio. Es la
	# ultima del prologo completo y su boton es Empezar.
	var s := _screen()
	s.go_to_page(s.page_count() - 1)
	assert_str(s.title_text()).is_equal(Tr.t("PRO_4_TITLE"))
	assert_str(CartoonTheme.button_text(s.next_button())).contains(Tr.t("BTN_PROLOGUE_START"))
	assert_bool(s.skip_button().visible).is_true()

func test_the_last_folio_says_the_plan_in_plain_words_in_both_languages() -> void:
	var saved := Tr.get_locale()
	var words := {"es": ["cero", "economía", "soldados", "Imperio", "opriman"],
		"en": ["scratch", "economy", "soldiers", "Empire", "oppresses"]}
	for loc in ["es", "en"]:
		Tr.set_locale(loc)
		var body := Tr.t("PRO_4_BODY")
		for w in words[loc]:
			assert_str(body).contains(w)
		# Sin instrucciones de botones: eso es del tutorial.
		for b in ["CONSTRUIR", "BUILD", "clic", "click", "Toca", "Tap", "☰"]:
			assert_str(body).not_contains(b)
		# 4-6 lineas de hoja: dos parrafos cortos, frases de 15 palabras o menos.
		assert_int(body.split("\n\n").size()).is_equal(2)
		for sentence in body.replace("\n", " ").split(".", false):
			assert_int(sentence.strip_edges().split(" ", false).size()).is_less_equal(15)
		assert_int(Tr.t("PRO_4_NOTE").split(" ", false).size()).is_less_equal(12)
	Tr.set_locale(saved)

func test_the_last_folio_turns_with_keys_and_swipes_like_the_others() -> void:
	var s := _screen()
	var last: int = s.page_count() - 1
	s.go_to_page(last - 1)
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_RIGHT
	s._input(key)
	assert_int(s.current_page()).is_equal(last)
	assert_bool(s.handle_swipe(Vector2(220, 0))).is_true()
	assert_int(s.current_page()).is_equal(last - 1)
	assert_bool(s.handle_swipe(Vector2(-220, 0))).is_true()
	assert_int(s.current_page()).is_equal(last)

# ── La lamina de cada folio (2026-10-18, feat/vista2d-y-prologo) ─────
# El folio dejaba dos tercios del papel vacios (ronda 1.0, mejora 8): cada uno
# lleva ahora un grabado a tinta dibujado en codigo (PrologueEngraving).

const Engraving := preload("res://scripts/ui/PrologueEngraving.gd")
const ScreenScript := preload("res://scripts/ui/PrologueScreen.gd")

func test_every_folio_of_every_variant_has_its_engraving() -> void:
	for v in ScreenScript.VARIANTS:
		for id in ScreenScript.VARIANTS[v]:
			assert_bool(Engraving.has_scene(String(id))).override_failure_message("folio %s sin lamina" % id).is_true()

func test_the_engraving_follows_the_folio() -> void:
	var s := _screen()
	assert_str(String(s.art().get("folio"))).is_equal("1")
	s.go_to_page(2)
	assert_str(String(s.art().get("folio"))).is_equal("3")
	s.prev_page()
	assert_str(String(s.art().get("folio"))).is_equal("2")

func test_the_engraving_shows_once_the_typing_is_done() -> void:
	var s := _screen()
	s.next_page()
	assert_float(s.art().modulate.a).is_equal(1.0)

func test_wide_sheets_put_the_engraving_beside_the_text_and_narrow_ones_on_top() -> void:
	var pc: Dictionary = ScreenScript.layout_for(Vector2(860, 640))
	assert_str(String(pc["mode"])).is_equal("side")
	assert_float(float(pc["art"])).is_between(170.0, 320.0)
	# Telefono en horizontal: folio ancho pero bajo, sigue al lado.
	assert_str(String(ScreenScript.layout_for(Vector2(700, 260))["mode"])).is_equal("side")
	# Estrecho y alto: encima del texto, una franja.
	var tall: Dictionary = ScreenScript.layout_for(Vector2(420, 600))
	assert_str(String(tall["mode"])).is_equal("top")
	assert_float(float(tall["art"])).is_between(90.0, 150.0)
	# Estrecho y bajo: solo texto.
	assert_str(String(ScreenScript.layout_for(Vector2(420, 280))["mode"])).is_equal("none")

func test_the_stamp_lands_on_the_engraving_when_it_fits() -> void:
	var sheet := Vector2(860, 640)
	var stamp := Vector2(180, 50)
	var art := Rect2(520, 80, 300, 420)
	var on_art: Vector2 = ScreenScript.stamp_position(sheet, stamp, art)
	assert_bool(art.encloses(Rect2(on_art, stamp))).is_true()
	# Sin lamina (o demasiado pequena), el sitio de siempre.
	var old: Vector2 = ScreenScript.stamp_position(sheet, stamp, Rect2())
	assert_that(old).is_equal(Vector2(sheet.x - stamp.x - 150.0, sheet.y - stamp.y - 52.0))

func test_every_engraving_draws_at_pc_tablet_and_phone_sizes() -> void:
	var drawn := [0]
	var plates: Array = []
	var canvas := Control.new()
	canvas.size = Vector2(400, 400)
	canvas.draw.connect(func():
		for id in Engraving.SCENES:
			for area in [Rect2(0, 0, 320, 480), Rect2(0, 0, 230, 260), Rect2(0, 0, 150, 120)]:
				plates.append(Engraving.draw_plate(canvas, area, String(id)))
		drawn[0] += 1)
	add_child(canvas)
	canvas.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(drawn[0]).is_greater(0)
	for p in plates:
		assert_bool((p as Rect2).has_area()).is_true()
	canvas.queue_free()

func test_a_too_small_area_draws_no_plate() -> void:
	var drawn := [Rect2(1, 1, 1, 1)]
	var canvas := Control.new()
	canvas.draw.connect(func(): drawn[0] = Engraving.draw_plate(canvas, Rect2(0, 0, 30, 30), "1"))
	add_child(canvas)
	canvas.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(drawn[0].has_area()).is_false()
	canvas.queue_free()
