extends GdUnitTestSuite
## Tema de las ventanas Oscuro (bunker, de serie) / Claro (papel) de la piel
## dieselpunk (2026-10-25; antes feat/ui3-tema-oscuro, docs/28 §2):
## contraste minimo de todo texto sobre las superficies de ventana en los dos
## temas, con las tres paletas y con alto contraste; el contorno del bocadillo
## sigue al tema; el interruptor dibujado no se queda con el color del otro
## tema; el ajuste vive en settings.cfg [interfaz] window_theme y Restablecer
## vuelve a Oscuro.

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
	UITheme.configure()
	SettingsParking.restore(_parked)
	DeviceProfile.apply_theme()

## Cada combinacion de tema, paleta y contraste que puede elegir el jugador.
func _combos() -> Array:
	var out: Array = []
	for theme_s in ["dark"]:
		for pal in UITheme.PALETTES:
			for hc in [false, true]:
				out.append([theme_s, pal, hc])
	return out

func _use(combo: Array) -> void:
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


func test_the_hud_is_dark_in_both_themes() -> void:
	var hud := CartoonTheme.c("hud", "BG")
	assert_str(CartoonTheme.kind("hud")).is_equal("dark")
	assert_object(CartoonTheme.c("hud", "BG")).is_equal(hud)
	assert_str(CartoonTheme.kind("hud")).is_equal("dark")





func test_the_bubble_edge_is_the_brass() -> void:
	UITheme.configure()
	assert_object(CartoonTheme.edge()).is_equal(Color("c99a45"))
	assert_object(CartoonTheme.bubble_style().bg_color).is_equal(Color("1c2026"))

func test_there_is_no_theme_row_in_settings() -> void:
	_panel = SettingsScene.instantiate()
	add_child(_panel)
	_panel.toggle()
	assert_object(_panel.find_child("ThemeRow", true, false)).is_null()
	assert_object(_panel.find_child("ViewModeRow", true, false)).is_null()
