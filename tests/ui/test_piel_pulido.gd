extends GdUnitTestSuite
## Pulido de la piel dieselpunk (rama feat/piel-dieselpunk-pulido, docs/21
## §17): iconos de linea, la X neutra, la Orden de la
## Regencia que espera a la tarjeta del tutorial, esquinas de la piel, botones
## en mayusculas sin tocar su texto y el sello en los momentos grandes.

const Icon := preload("res://scripts/ui/CartoonIcon.gd")
const SettingsParking := preload("res://tests/save/settings_parking.gd")

var _parked: Dictionary
var _phone := false
var _mode_saved: Dictionary = {}

func before_test() -> void:
	_parked = SettingsParking.park()
	_phone = CartoonTheme.phone
	_mode_saved = GameMode.get_save_data()
	UITheme.use_style(UITheme.STYLE_DEFAULT, "mixed", CartoonTheme.DEFAULT_COMBO)
	CartoonTheme.window_theme = CartoonTheme.WINDOW_THEME_DEFAULT
	UITheme.configure()

func after_test() -> void:
	CartoonTheme.phone = _phone
	GameMode.load_save_data(_mode_saved)
	CartoonTheme.window_theme = CartoonTheme.WINDOW_THEME_DEFAULT
	UITheme.configure()
	SettingsParking.restore(_parked)

# ── 1. Iconos de linea ───────────────────────────────────────────────

func test_every_glyph_keeps_its_id_and_draws() -> void:
	# Los ids de siempre (las llamadas no se rompen), materiales incluidos.
	for id in ["build", "army", "missions", "close", "lock", "storm", "sun", "wrench",
			"mat_planks", "mat_ingots", "mat_beams", "mat_fuel"]:
		assert_bool(Icon.GLYPHS.has(id)).override_failure_message(id).is_true()
	for id in Icon.GLYPHS:
		var ic: Control = Icon.make(id, 32)
		add_child(ic)
		auto_free(ic)
	await await_idle_frame()

func test_line_icons_take_the_text_colour_not_toy_colours() -> void:
	var plain: Control = auto_free(Icon.make("build", 24))
	assert_object(Icon.default_ink("window")).is_equal(CartoonTheme.text("window"))
	assert_float(plain.get("tint").a).is_equal(0.0)
	# Sobre el laton de la accion principal, el icono va en la tinta del boton.
	var pri: Button = auto_free(CartoonTheme.pill_button("CONSTRUIR", "build", "primary"))
	var glyphs := pri.find_children("*", "Control", true, false).filter(func(n): return n.get("glyph") == "build")
	assert_int(glyphs.size()).is_equal(1)
	var fill := CartoonTheme.kind_fill("primary", "window")
	assert_object(glyphs[0].get("tint")).is_equal(CartoonTheme.pill_text("primary", fill, "window")["color"])

func test_hud_icons_use_the_hud_ink() -> void:
	var ic: Control = auto_free(CartoonTheme.make_glyph("sun", 30, Color(0, 0, 0, 0), "hud"))
	assert_str(String(ic.get("role"))).is_equal("hud")

# ── 3. Cerrar no es destruir ─────────────────────────────────────────

func test_the_close_button_is_never_red() -> void:
	var x: Button = auto_free(UITheme.make_close_button(func(): pass))
	var sb := x.get_theme_stylebox("normal") as StyleBoxFlat
	assert_object(sb.bg_color).is_not_equal(CartoonTheme.kind_fill("danger", "window"))
	assert_object(sb.bg_color).is_equal(CartoonTheme.kind_fill("secondary", "window"))
	var glyphs := x.find_children("*", "Control", true, false).filter(func(n): return n.get("glyph") == "close")
	assert_int(glyphs.size()).is_equal(1)

# ── 4. La Orden espera a la tarjeta del tutorial ─────────────────────

func test_the_order_card_folds_under_the_tutorial_card_on_a_phone() -> void:
	var hud: CanvasLayer = auto_free(load("res://scenes/ui/StormHUD.tscn").instantiate())
	add_child(hud)
	await await_idle_frame()
	assert_bool(hud._tutorial_blocks()).is_false()
	var card: PanelContainer = auto_free(PanelContainer.new())
	card.add_to_group("tutorial_card")
	card.size = Vector2(200, 100)
	add_child(card)
	CartoonTheme.phone = true
	assert_bool(hud._tutorial_blocks()).is_true()
	card.visible = false
	assert_bool(hud._tutorial_blocks()).is_false()
	card.visible = true
	# En PC solo si cae encima del sitio de la Orden abierta.
	CartoonTheme.phone = false
	if not UILayoutManager.is_column_narrow():
		hud._open_rect = Rect2(Vector2(900, 80), Vector2(320, 340))
		card.position = Vector2(100, 300)
		assert_bool(hud._tutorial_blocks()).is_false()
		card.position = Vector2(950, 200)
		assert_bool(hud._tutorial_blocks()).is_true()

func test_the_tutorial_card_is_in_the_group() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/ui/TutorialPanel.gd")
	assert_bool(src.contains("add_to_group(\"tutorial_card\")")).is_true()

# ── 5. Esquinas de la piel ───────────────────────────────────────────

func test_hand_written_corners_use_the_skin_tokens() -> void:
	for path in ["res://scripts/ui/BuildingInfoPanel.gd", "res://scripts/ui/RegimentCard.gd",
			"res://scripts/ui/TutorialPanel.gd", "res://scripts/ui/SkirmishButton.gd",
			"res://scripts/ui/HelperPanel.gd", "res://scripts/ui/ObjectivePanel.gd"]:
		var src := FileAccess.get_file_as_string(path)
		for bad in [", 12, 8)", "radius_all(12)", "radius_all(30)", "int(DOT), 0)", ", 2, 12, 0)"]:
			assert_bool(src.contains(bad)).override_failure_message("%s: %s" % [path, bad]).is_false()
	var host: Control = auto_free(Control.new())
	var dot := CartoonTheme.red_dot(host)
	assert_int((dot.get_theme_stylebox("panel") as StyleBoxFlat).corner_radius_top_left).is_less_equal(4)

# ── 6. Botones en mayusculas sin tocar su texto ──────────────────────

func test_button_words_show_in_caps_but_keep_their_text() -> void:
	var b := Button.new()
	b.text = "Entregar madera"
	CartoonTheme.style_pill(b, "secondary")
	add_child(b)
	auto_free(b)
	await await_idle_frame()
	assert_str(b.text).is_equal("Entregar madera")
	assert_bool(CartoonTheme.is_caps_button(b)).is_true()
	assert_str(b.atr(b.text)).is_equal("ENTREGAR MADERA")
	# Lo que no es una palabra se queda igual ("x2"), y la ayuda no cambia.
	assert_str(b.atr("x2")).is_equal("x2")
	assert_int(b.tooltip_auto_translate_mode).is_equal(Node.AUTO_TRANSLATE_MODE_DISABLED)
	# Las pastillas con etiqueta, en mayusculas aunque pidan letra pequena.
	var p: Button = auto_free(CartoonTheme.pill_button("Ver", "", "open", CartoonTheme.BTN, "window", "small"))
	var l: Label = p.find_children("*", "Label", true, false)[0]
	assert_bool(l.uppercase).is_true()
	assert_str(l.text).is_equal("Ver")
	# Los de UITheme.style_button tambien.
	var u := Button.new()
	u.text = "Menu principal"
	UITheme.style_button(u)
	auto_free(u)
	assert_bool(CartoonTheme.is_caps_button(u)).is_true()

# ── 7. El sello en los momentos grandes ──────────────────────────────

func test_the_victory_carries_the_official_stamp() -> void:
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	var screen: CanvasLayer = auto_free(load("res://scenes/ui/VictoryScreen.tscn").instantiate())
	add_child(screen)
	screen._on_victory_achieved({"time_played": 60.0})
	var seal: Control = screen.find_child("VictoryStamp", true, false)
	assert_object(seal).is_not_null()
	assert_str(String(seal.get_meta("stamp_text"))).is_equal(Tr.t("STAMP_VICTORY_AUDIT"))
	screen._close()

func test_a_rank_up_stamps_the_badge_for_a_moment() -> void:
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/RankPanel.tscn").instantiate())
	add_child(panel)
	await await_idle_frame()
	assert_object(panel.rank_stamp()).is_null()
	panel.show_rank_stamp()
	var st: Control = panel.rank_stamp()
	assert_object(st).is_not_null()
	assert_str(String(st.get_meta("stamp_text"))).is_equal(Tr.t("STAMP_RANK_UP"))
	# Otro ascenso no apila dos sellos.
	panel.show_rank_stamp()
	assert_int(panel._dock.find_children("RankStamp", "", false, false).size()).is_equal(1)

func test_the_stamp_texts_exist_in_both_languages() -> void:
	var was := Tr.get_locale()
	for locale in ["es", "en"]:
		Tr.set_locale(locale)
		for k in ["STAMP_VICTORY_AUDIT", "STAMP_VICTORY_BUILDER", "STAMP_RANK_UP"]:
			assert_str(Tr.t(k)).override_failure_message(k).is_not_equal(k)
	Tr.set_locale(was)
