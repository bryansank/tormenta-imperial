extends GdUnitTestSuite
## Tema de las ventanas Claro / Oscuro (feat/ui3-tema-oscuro, docs/28 §2):
## contraste minimo de todo texto sobre las superficies de ventana en los dos
## temas, con las tres paletas y con alto contraste; el contorno del bocadillo
## sigue al tema; el interruptor dibujado no se queda con el color del otro
## tema; el ajuste vive en settings.cfg [interfaz] ui_theme y Restablecer
## vuelve a Claro.

const SettingsParking := preload("res://tests/save/settings_parking.gd")
const SettingsScene := preload("res://scenes/ui/SettingsPanel.tscn")

var _parked: Dictionary
var _panel

func before_test() -> void:
	_parked = SettingsParking.park()

func after_test() -> void:
	if is_instance_valid(_panel):
		if _panel.is_open():
			_panel._needs_rebuild = false
			_panel.toggle()
		_panel.free()
	CartoonTheme.window_theme = "light"
	UITheme.configure()
	SettingsParking.restore(_parked)
	DeviceProfile.apply_theme()

## Cada combinacion de tema, paleta y contraste que puede elegir el jugador.
func _combos() -> Array:
	var out: Array = []
	for theme_s in CartoonTheme.WINDOW_THEMES:
		for pal in UITheme.PALETTES:
			for hc in [false, true]:
				out.append([theme_s, pal, hc])
	return out

func _use(combo: Array) -> void:
	CartoonTheme.window_theme = combo[0]
	UITheme.configure(combo[1], combo[2])

func _worst(col: Color, keys: Array) -> float:
	var worst := 99.0
	for key in keys:
		worst = minf(worst, UITheme.contrast_ratio(col, CartoonTheme.c("window", key)))
	return worst

func test_the_text_reads_on_every_window_surface() -> void:
	for combo in _combos():
		_use(combo)
		var need := UITheme.MIN_CONTRAST
		assert_float(_worst(CartoonTheme.text("window"), ["BG", "CARD", "CARD_ALT", "NEUTRAL"])) \
			.override_failure_message("TEXT %s" % [combo]).is_greater_equal(need)
		assert_float(_worst(CartoonTheme.text("window", true), ["BG", "CARD"])) \
			.override_failure_message("TEXT_DIM %s" % [combo]).is_greater_equal(need)

func test_the_meaning_colours_read_in_both_themes() -> void:
	# Rojo de lo que falta, verde de lo que se gana y los tonos de aviso: con
	# las dos superficies, las tres paletas y alto contraste (antes, en Oscuro,
	# el rojo daba 3:1 y el ambar oscurecido 1,7:1).
	for combo in _combos():
		_use(combo)
		var need := UITheme.MIN_CONTRAST
		var cols := {"danger_text": CartoonTheme.danger_text(), "positive_text": CartoonTheme.positive_text()}
		for tone in ["positive", "warning", "danger", "info", "accent"]:
			cols["tone_" + tone] = CartoonTheme.tone_color(tone)
		for k in cols:
			assert_float(_worst(cols[k], ["BG", "CARD", "CARD_ALT"])) \
				.override_failure_message("%s %s" % [k, combo]).is_greater_equal(need)

func test_readable_keeps_a_colour_that_already_reads() -> void:
	CartoonTheme.window_theme = "light"
	UITheme.configure()
	var ink := CartoonTheme.text("window")
	assert_object(CartoonTheme.readable(ink)).is_equal(ink)
	CartoonTheme.window_theme = "dark"
	var white := CartoonTheme.text("window")
	assert_object(CartoonTheme.readable(white)).is_equal(white)

func test_the_bubble_edge_follows_the_theme() -> void:
	CartoonTheme.window_theme = "light"
	UITheme.configure()
	assert_object(CartoonTheme.edge()).is_equal(CartoonTheme.INK)
	assert_object(CartoonTheme.bubble_style().border_color).is_equal(CartoonTheme.INK)
	CartoonTheme.window_theme = "dark"
	assert_object(CartoonTheme.edge()).is_equal(Color("4fa3e0"))
	assert_object(CartoonTheme.bubble_style().bg_color).is_equal(Color("243241"))
	assert_object(CartoonTheme.bubble_style().border_color).is_equal(Color("4fa3e0"))

func test_the_drawn_switch_is_redrawn_for_each_theme() -> void:
	CartoonTheme.window_theme = "light"
	UITheme.configure()
	var light_tex := CartoonTheme.switch_texture(false, false)
	CartoonTheme.window_theme = "dark"
	var dark_tex := CartoonTheme.switch_texture(false, false)
	assert_bool(light_tex == dark_tex).is_false()
	# El carril apagado es el hueco de la superficie: el del tema elegido.
	var px := dark_tex.get_image().get_pixel(38, 8)
	assert_float(absf(px.r - CartoonTheme.c("window", "WELL").r)).is_less(0.02)

func test_the_hud_is_dark_in_both_themes() -> void:
	CartoonTheme.window_theme = "light"
	var hud := CartoonTheme.c("hud", "BG")
	assert_str(CartoonTheme.kind("hud")).is_equal("dark")
	CartoonTheme.window_theme = "dark"
	assert_object(CartoonTheme.c("hud", "BG")).is_equal(hud)
	assert_str(CartoonTheme.kind("hud")).is_equal("dark")

func test_an_unknown_theme_in_settings_loads_as_light() -> void:
	GameConfig.ui_theme = "dark"
	GameConfig.save_user_settings()
	var cf := ConfigFile.new()
	cf.load(GameConfig.USER_SETTINGS_PATH)
	assert_str(str(cf.get_value("interfaz", "ui_theme", ""))).is_equal("dark")
	cf.set_value("interfaz", "ui_theme", "violeta")
	cf.save(GameConfig.USER_SETTINGS_PATH)
	GameConfig.load_user_settings()
	assert_str(GameConfig.ui_theme).is_equal("light")

func test_the_settings_row_saves_and_reset_goes_back_to_light() -> void:
	_panel = SettingsScene.instantiate()
	add_child(_panel)
	_panel.toggle()
	assert_object(_panel.find_child("ThemeRow", true, false)).is_not_null()
	_panel.set_ui_theme("dark")
	assert_str(GameConfig.ui_theme).is_equal("dark")
	assert_str(CartoonTheme.window_theme).is_equal("dark")
	var cf := ConfigFile.new()
	cf.load(GameConfig.USER_SETTINGS_PATH)
	assert_str(str(cf.get_value("interfaz", "ui_theme", ""))).is_equal("dark")
	_panel.reset_interface()
	assert_str(GameConfig.ui_theme).is_equal("light")
	cf.load(GameConfig.USER_SETTINGS_PATH)
	assert_str(str(cf.get_value("interfaz", "ui_theme", ""))).is_equal("light")

func test_locked_pieces_and_thumbnails_are_not_lost_in_the_dark() -> void:
	# Claro como siempre: la pieza cerrada en el hueco. Oscuro: CARD_ALT y la
	# miniatura del edificio sobre un hueco claro.
	CartoonTheme.window_theme = "light"
	UITheme.configure()
	assert_object(CartoonTheme.pick_fill(false)).is_equal(CartoonTheme.c("window", "WELL"))
	var light_thumb: PanelContainer = auto_free(CartoonTheme.thumb_frame(Control.new(), Vector2(40, 40)))
	assert_object((light_thumb.get_theme_stylebox("panel") as StyleBoxFlat).bg_color).is_equal(CartoonTheme.c("window", "WELL"))
	CartoonTheme.window_theme = "dark"
	assert_object(CartoonTheme.pick_fill(false)).is_equal(CartoonTheme.c("window", "CARD_ALT"))
	var dark_thumb: PanelContainer = auto_free(CartoonTheme.thumb_frame(Control.new(), Vector2(40, 40)))
	var bg := (dark_thumb.get_theme_stylebox("panel") as StyleBoxFlat).bg_color
	assert_float(UITheme.contrast_ratio(bg, CartoonTheme.c("window", "CARD"))).is_greater_equal(3.0)
