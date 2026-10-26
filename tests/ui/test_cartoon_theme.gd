extends GdUnitTestSuite
## El estilo "maqueta" del rediseno (docs/28-guia-ui.md): variante de UITheme
## que se activa y se desactiva sin dejar rastro, letra legible en sus dos
## superficies (tambien en alto contraste y con las paletas de daltonismo),
## tamanos de telefono con su suelo y lado tactil, y la orientacion de pantalla
## (horizontal de serie, vertical opcional) guardada en settings.cfg.
## Cada prueba deja UITheme y CartoonTheme como los encontro.

const SettingsParking := preload("res://tests/save/settings_parking.gd")

var _parked: Dictionary

func before_test() -> void:
	_parked = SettingsParking.park()

func after_test() -> void:
	CartoonTheme.phone = false
	CartoonTheme.show_caption_never = false
	# Se vuelve al estilo de serie (desde la fase 2, "cartoon"): dejar "classic"
	# contagiaba a las suites que vinieran detras.
	UITheme.use_style(UITheme.STYLE_DEFAULT, "mixed", CartoonTheme.DEFAULT_COMBO)
	UITheme.configure()
	SettingsParking.restore(_parked)

## Fase 2 (feat/ui2-hud, 2026-10-18): el estilo maqueta es el de serie; el
## clasico queda como respaldo interno y sigue aplicando sus tokens.
func test_cartoon_is_the_default_and_classic_stays_available() -> void:
	assert_str(UITheme.STYLE_DEFAULT).is_equal("cartoon")
	assert_bool(UITheme.is_cartoon()).is_true()
	UITheme.use_style("classic")
	assert_bool(UITheme.is_cartoon()).is_false()
	var tokens := UITheme.resolve_tokens("default", false, 1.0)
	assert_object(UITheme.SURFACE).is_equal(tokens["SURFACE"])

func test_switching_to_cartoon_and_back_restores_the_classic_tokens() -> void:
	UITheme.use_style("classic")
	var before := UITheme.SURFACE
	UITheme.use_style("cartoon", "mixed", CartoonTheme.DEFAULT_COMBO)
	assert_bool(UITheme.is_cartoon()).is_true()
	# La superficie de los tokens viejos es la de las ventanas (bunker o papel).
	assert_object(UITheme.SURFACE).is_equal(CartoonTheme.c("window", "BG"))
	UITheme.use_style("classic")
	assert_object(UITheme.SURFACE).is_equal(before)

## Piel dieselpunk (2026-10-25): Big Shoulders Display + IBM Plex Sans Condensed.
func test_chosen_pair_is_big_shoulders_and_plex() -> void:
	assert_str(CartoonTheme.DEFAULT_COMBO).is_equal("bigshoulders_plex")
	UITheme.use_style("cartoon", "mixed", "bigshoulders_plex")
	assert_object(CartoonTheme.title_font()).is_not_null()
	assert_object(CartoonTheme.body_font()).is_not_null()
	assert_object(UITheme.title_font()).is_equal(CartoonTheme.title_font())

func test_every_combo_has_its_font_files_and_licence() -> void:
	for id in CartoonTheme.COMBO_ORDER:
		var c: Dictionary = CartoonTheme.COMBOS[id]
		for key in ["title", "body", "bold"]:
			if not c.has(key):
				continue
			var path: String = c[key]
			assert_bool(FileAccess.file_exists(path)).override_failure_message("falta " + path).is_true()
			assert_bool(FileAccess.file_exists(path.get_base_dir() + "/OFL.txt")) \
				.override_failure_message("sin OFL.txt junto a " + path).is_true()

func test_text_reads_on_both_surfaces_in_every_palette_and_contrast() -> void:
	for surface in CartoonTheme.SURFACES:
		for pal in UITheme.PALETTES:
			for hc in [false, true]:
				UITheme.configure(pal, hc)
				UITheme.use_style("cartoon", surface)
				var need := 7.0 if hc else 4.5
				for role in ["hud", "window"]:
					var bg := CartoonTheme.c(role, "BG")
					var msg := "%s/%s/%s/%s" % [surface, pal, hc, role]
					assert_float(UITheme.contrast_ratio(CartoonTheme.text(role), bg)) \
						.override_failure_message("texto " + msg).is_greater_equal(need)
					assert_float(UITheme.contrast_ratio(CartoonTheme.text(role, true), bg)) \
						.override_failure_message("texto tenue " + msg).is_greater_equal(4.5)

func test_old_panels_get_dark_text_on_the_cream_windows() -> void:
	UITheme.use_style("cartoon", "mixed")
	CartoonTheme.window_theme = "light"
	UITheme.configure()
	# Un panel viejo que pide texto claro: readable() lo oscurece sobre el papel.
	var fixed := UITheme.readable(Color(0.95, 0.9, 0.8))
	assert_float(UITheme.contrast_ratio(fixed, CartoonTheme.c("window", "BG"))).is_greater_equal(4.5)
	CartoonTheme.window_theme = CartoonTheme.WINDOW_THEME_DEFAULT
	UITheme.configure()

func test_phone_sizes_keep_their_floor_and_touch_side() -> void:
	CartoonTheme.phone = true
	for level in CartoonTheme.SIZES_PHONE:
		assert_int(CartoonTheme.fs(level)).is_greater_equal(int(CartoonTheme.SIZE_FLOOR_PHONE[level]))
	for h in ["big", "btn", "small"]:
		assert_int(CartoonTheme.h(h)).is_greater_equal(CartoonTheme.TOUCH_MIN)
	CartoonTheme.phone = false
	assert_int(CartoonTheme.fs("body")).is_equal(int(CartoonTheme.SIZES["body"]))

func test_buttons_follow_intent_colours() -> void:
	UITheme.use_style("cartoon", "mixed")
	# Piel dieselpunk: la accion principal es laton (con su luz piloto).
	assert_object(CartoonTheme.kind_fill("primary")).is_equal(CartoonTheme.sem("ACCENT"))
	assert_object(CartoonTheme.kind_fill("open")).is_equal(CartoonTheme.sem("INFO"))
	assert_object(CartoonTheme.kind_fill("warn")).is_equal(CartoonTheme.sem("WARNING"))
	assert_object(CartoonTheme.kind_fill("danger")).is_equal(CartoonTheme.sem("DANGER"))

func test_notice_has_icon_text_and_close() -> void:
	UITheme.use_style("cartoon", "mixed")
	var n := CartoonTheme.notice("Falta comida", "res:food", "warning", 3)
	auto_free(n)
	var row := n.get_child(0)
	# icono, frase, "x3" y la X
	assert_int(row.get_child_count()).is_equal(4)
	assert_str((row.get_child(1) as Label).text).is_equal("Falta comida")

func test_orientation_defaults_to_landscape_and_is_saved() -> void:
	assert_str(GameConfig.ui_orientation).is_equal("landscape")
	GameConfig.set_orientation("portrait")
	var cf := ConfigFile.new()
	cf.load("user://settings.cfg")
	assert_str(String(cf.get_value("ui", "orientation", ""))).is_equal("portrait")
	GameConfig.set_orientation("sideways")
	assert_str(GameConfig.ui_orientation).is_equal("landscape")
