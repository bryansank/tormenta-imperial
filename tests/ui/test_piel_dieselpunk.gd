extends GdUnitTestSuite
## La piel dieselpunk "D · Mezcla sobria" (Bryan, 2026-10-25; docs/21 §17 y
## docs/24): paleta de bunker, fuentes con ñ y tildes, las cinco intenciones de
## boton (con la luz piloto y el candado), esquinas casi rectas, el alto
## contraste y el daltonismo cambiando pocos tokens.
## Cada prueba deja UITheme y CartoonTheme como los encontro.

const SettingsParking := preload("res://tests/save/settings_parking.gd")

var _parked: Dictionary

func before_test() -> void:
	_parked = SettingsParking.park()
	UITheme.use_style(UITheme.STYLE_DEFAULT, "mixed", CartoonTheme.DEFAULT_COMBO)
	CartoonTheme.window_theme = CartoonTheme.WINDOW_THEME_DEFAULT
	UITheme.configure()

func after_test() -> void:
	CartoonTheme.window_theme = CartoonTheme.WINDOW_THEME_DEFAULT
	UITheme.configure()
	SettingsParking.restore(_parked)

# ── Paleta ───────────────────────────────────────────────────────────

func test_the_palette_is_the_one_bryan_chose() -> void:
	var want := {"SURFACE": "1c2026", "NEUTRAL": "252b32", "ACCENT": "c99a45", "INFO": "2e4a5e",
		"WARNING": "e5ae3e", "DANGER": "c9503a", "POSITIVE": "86c27a"}
	for k in want:
		assert_object(UITheme._BASE[k]).override_failure_message(k).is_equal(Color(want[k]))
	# El bunker es la Pizarra y la Placa; el filo, el laton.
	assert_str(CartoonTheme.window_theme).is_equal("dark")
	assert_object(CartoonTheme.c("window", "BG")).is_equal(Color("1c2026"))
	assert_object(CartoonTheme.c("window", "CARD")).is_equal(Color("252b32"))
	assert_object(CartoonTheme.c("hud", "BG")).is_equal(Color("1c2026"))
	assert_object(CartoonTheme.c("window", "TRIM")).is_equal(Color("c99a45"))

func test_colour_blind_palettes_change_at_most_four_tokens() -> void:
	for pal in UITheme.PALETTES:
		var changed := 0
		var tokens: Dictionary = UITheme._PALETTE_TOKENS[pal]
		for k in ["POSITIVE", "DANGER", "WARNING", "INFO", "ACCENT"]:
			if tokens.has(k):
				changed += 1
		assert_int(changed).override_failure_message(pal).is_less_equal(4)

func test_high_contrast_reads_at_seven_to_one_on_every_surface() -> void:
	for theme_s in CartoonTheme.WINDOW_THEMES:
		for pal in UITheme.PALETTES:
			CartoonTheme.window_theme = theme_s
			UITheme.configure(pal, true)
			for role in ["hud", "window"]:
				for bg in ["BG", "CARD", "CARD_ALT"]:
					var msg := "%s/%s/%s/%s" % [theme_s, pal, role, bg]
					assert_float(UITheme.contrast_ratio(CartoonTheme.text(role), CartoonTheme.c(role, bg))) \
						.override_failure_message(msg).is_greater_equal(7.0)
				# El filo de laton se ve sobre el fondo (los bordes son la forma).
				assert_float(UITheme.contrast_ratio(CartoonTheme.c(role, "TRIM"), CartoonTheme.c(role, "BG"))) \
					.override_failure_message("filo %s/%s/%s" % [theme_s, pal, role]).is_greater_equal(4.5)

## Las palabras de boton son letra grande y gruesa (22 px, peso 800): 3:1 de
## serie (WCAG, texto grande) y 4,5:1 con alto contraste.
func test_button_text_reads_on_every_intent() -> void:
	for theme_s in CartoonTheme.WINDOW_THEMES:
		for pal in UITheme.PALETTES:
			for hc in [false, true]:
				CartoonTheme.window_theme = theme_s
				UITheme.configure(pal, hc)
				for k in ["primary", "accent", "open", "warning", "danger", "disabled", "secondary"]:
					var fill := CartoonTheme.kind_fill(k)
					var tc: Dictionary = CartoonTheme.pill_text(k, fill)
					assert_float(UITheme.contrast_ratio(tc["color"], fill)) \
						.override_failure_message("%s %s/%s/%s" % [k, theme_s, pal, hc]).is_greater_equal(4.5 if hc else 3.0)

# ── Fuentes ──────────────────────────────────────────────────────────

func test_the_fonts_carry_spanish_letters() -> void:
	var fonts := [CartoonTheme.title_font(), CartoonTheme.body_font(), CartoonTheme.bold_font(), CartoonTheme.number_font()]
	for f in fonts:
		assert_object(f).is_not_null()
		for ch in "ñÑáéíóúÁÉÍÓÚüÜ¿¡0123456789":
			assert_bool((f as Font).has_char(ch.unicode_at(0))) \
				.override_failure_message("%s sin '%s'" % [f, ch]).is_true()

func test_titles_are_art_deco_and_figures_condensed() -> void:
	var title := CartoonTheme.label("Construir", "title", Color.WHITE)
	var number := CartoonTheme.label("1.240", "number", Color.WHITE)
	var body := CartoonTheme.label("Texto", "body", Color.WHITE)
	auto_free(title)
	auto_free(number)
	auto_free(body)
	assert_object(title.get_theme_font("font")).is_equal(CartoonTheme.title_font())
	assert_bool(title.uppercase).is_true()
	assert_str(title.text).is_equal("Construir")
	assert_object(number.get_theme_font("font")).is_equal(CartoonTheme.bold_font())
	assert_object(body.get_theme_font("font")).is_equal(CartoonTheme.body_font())
	assert_bool(body.uppercase).is_false()
	# Texto sobre liso: sin contorno.
	assert_int(title.get_theme_constant("outline_size")).is_equal(0)

# ── Botones ──────────────────────────────────────────────────────────

func test_the_five_intents_have_their_colours() -> void:
	assert_object(CartoonTheme.kind_fill("primary")).is_equal(CartoonTheme.sem("ACCENT"))
	assert_object(CartoonTheme.kind_fill("open")).is_equal(CartoonTheme.sem("INFO"))
	assert_object(CartoonTheme.kind_fill("warning")).is_equal(CartoonTheme.sem("WARNING"))
	assert_object(CartoonTheme.kind_fill("danger")).is_equal(CartoonTheme.sem("DANGER"))
	assert_object(CartoonTheme.kind_fill("disabled")).is_equal(CartoonTheme.c("window", "OFF"))

func test_the_main_action_carries_its_pilot_light() -> void:
	var pri: Button = auto_free(CartoonTheme.pill_button("CONSTRUIR", "build", "primary"))
	assert_int(pri.find_children("PilotLight", "Panel", true, false).size()).is_equal(1)
	var open: Button = auto_free(CartoonTheme.pill_button("ABRIR", "", "open"))
	assert_int(open.find_children("PilotLight", "Panel", true, false).size()).is_equal(0)
	# Cambiar de clase pone o quita la luz.
	CartoonTheme.set_pill_kind(open, "primary", CartoonTheme.BTN)
	assert_int(open.find_children("PilotLight", "Panel", true, false).size()).is_equal(1)
	CartoonTheme.set_pill_kind(open, "secondary", CartoonTheme.BTN)
	await await_idle_frame()
	assert_int(open.find_children("PilotLight", "Panel", true, false).size()).is_equal(0)
	# Los botones de texto (Button.text) tambien.
	var tp: Button = auto_free(CartoonTheme.text_pill("COMPRAR", "primary"))
	assert_object(tp.get_node_or_null("PilotLight")).is_not_null()

func test_an_unavailable_button_shows_its_lock_and_dims_its_text() -> void:
	var off: Button = auto_free(CartoonTheme.pill_button("FALTA ACERO", "", "disabled"))
	var glyphs := off.find_children("*", "Control", true, false).filter(func(n): return n.get("glyph") == "lock")
	assert_int(glyphs.size()).is_equal(1)
	# Un boton que se desactiva apaga su texto (al redibujarse).
	var btn: Button = CartoonTheme.pill_button("MEJORAR", "", "primary")
	add_child(btn)
	auto_free(btn)
	var l: Label = btn.find_children("*", "Label", true, false)[0]
	var on_color := l.get_theme_color("font_color")
	btn.disabled = true
	await await_idle_frame()
	assert_object(l.get_theme_color("font_color")).is_equal(CartoonTheme.c("window", "OFF_INK"))
	btn.disabled = false
	await await_idle_frame()
	assert_object(l.get_theme_color("font_color")).is_equal(on_color)

func test_corners_are_almost_square() -> void:
	var styles := [CartoonTheme.window_style(), CartoonTheme.card_style(), CartoonTheme.hud_style(),
		CartoonTheme.well_style("window", 14)]
	var btn: Button = auto_free(CartoonTheme.pill_button("VER", "", "open"))
	styles.append(btn.get_theme_stylebox("normal"))
	var close: Button = auto_free(CartoonTheme.close_button())
	styles.append(close.get_theme_stylebox("normal"))
	for st in styles:
		assert_int((st as StyleBoxFlat).corner_radius_top_left).is_less_equal(4)
	# El filo de laton de arriba, mas grueso que los lados.
	var w := CartoonTheme.window_style()
	assert_int(w.border_width_top).is_greater(w.border_width_left)
	assert_object(w.border_color).is_equal(CartoonTheme.c("window", "TRIM"))

func test_the_window_draws_a_double_brass_edge() -> void:
	var w := CartoonTheme.window("AJUSTES")
	auto_free(w["root"])
	assert_bool((w["panel"] as Control).has_meta("trim_line")).is_true()
	# La placa del titulo: texto claro sobre el hueco, nunca sobre el color.
	var ribbon: PanelContainer = w["ribbon"]
	var l := ribbon.get_child(0) as Label
	assert_object(l.get_theme_color("font_color")).is_equal(CartoonTheme.c("window", "TEXT"))
