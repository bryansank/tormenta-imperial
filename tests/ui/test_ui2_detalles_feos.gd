extends GdUnitTestSuite
## Los cinco detalles feos que quedaron del rediseno (2026-10-19):
##   1. las miniaturas de CONSTRUIR se recortan a lo que ocupa el modelo;
##   2. el Mercado rehace sus filas al cargar (antes: solo comida y madera);
##   3. el ☰ se esconde mientras se ve la Victoria;
##   4. el selector paso a paso de Ajustes no corta con puntos;
##   5. la cifra de la cola del Cuartel deja margen por la derecha.

const ConstructionMenuScript := preload("res://scripts/ui/ConstructionMenu.gd")
const TrainingSectionScript := preload("res://scripts/ui/TrainingSection.gd")

var _unlocks: Dictionary = {}

func before_test() -> void:
	_unlocks = ResourceManager.get_unlock_state()

func after_test() -> void:
	ResourceManager.set_unlock_state(_unlocks)

# ── 1. Miniaturas ────────────────────────────────────────────────────

func test_the_thumbnail_is_cropped_to_the_model_in_the_slot_format() -> void:
	# Una foto de 256 con el modelo pequeno en medio (60x40 opacos).
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.fill_rect(Rect2i(100, 110, 60, 40), Color.RED)
	var out: Image = ConstructionMenuScript._crop_to_model(img, 4.0 / 3.0)
	assert_float(float(out.get_width()) / float(out.get_height())).is_equal_approx(4.0 / 3.0, 0.05)
	# El modelo ocupa casi toda la miniatura, no un tercio como antes.
	assert_int(out.get_width()).is_less(80)
	assert_int(out.get_width()).is_greater_equal(60)

func test_an_empty_thumbnail_is_left_alone() -> void:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var out: Image = ConstructionMenuScript._crop_to_model(img)
	assert_vector(Vector2(out.get_size())).is_equal(Vector2(64, 64))

# ── 2. Mercado ───────────────────────────────────────────────────────

func test_the_market_rows_follow_a_loaded_unlock_state() -> void:
	ResourceManager.set_unlock_state({"steel": false, "oil": false})
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/MarketPanel.tscn").instantiate())
	add_child(panel)
	await await_idle_frame()
	assert_bool(panel._rows.has("steel")).is_false()
	# Cargar una partida abre recursos sin emitir resource_unlocked.
	ResourceManager.set_unlock_state({"steel": true, "oil": true})
	panel.open()
	await await_idle_frame()
	assert_bool(panel._rows.has("steel")).is_true()
	assert_bool(panel._rows.has("oil")).is_true()
	panel._toggle_panel()

# ── 3. Victoria ──────────────────────────────────────────────────────

func test_the_menu_button_hides_while_the_victory_shows() -> void:
	var btn: Button = auto_free(Button.new())
	btn.add_to_group("hud_menu_button")
	add_child(btn)
	var screen: CanvasLayer = auto_free(load("res://scenes/ui/VictoryScreen.tscn").instantiate())
	add_child(screen)
	screen._on_victory_achieved({"time_played": 60.0})
	assert_bool(btn.visible).is_false()
	screen._close()
	assert_bool(btn.visible).is_true()

# ── 4. Selector ──────────────────────────────────────────────────────

func test_the_stepper_never_trims_its_value_with_dots() -> void:
	var p: HBoxContainer = auto_free(CartoonTheme.picker(
		["Del perfil (100 %)", "75 %", "90 %", "110 %", "130 %"], 0))
	add_child(p)
	assert_bool(p.is_stepper()).is_true()
	var value: Label = p.find_child("Value", true, false)
	assert_int(value.text_overrun_behavior).is_equal(TextServer.OVERRUN_NO_TRIMMING)
	assert_int(value.autowrap_mode).is_not_equal(TextServer.AUTOWRAP_OFF)
	# El hueco pide el ancho del texto mas largo (hasta el tope).
	var font: Font = value.get_theme_font("font")
	var need := font.get_string_size("Del perfil (100 %)", HORIZONTAL_ALIGNMENT_LEFT, -1,
		value.get_theme_font_size("font_size")).x
	assert_float(value.custom_minimum_size.x).is_greater_equal(minf(need, p.VALUE_MAX_W))

# ── 5. Cola del Cuartel ──────────────────────────────────────────────

func test_the_training_header_keeps_room_on_the_right() -> void:
	var section: VBoxContainer = auto_free(TrainingSectionScript.new())
	add_child(section)
	section.setup("barracks")
	var pad := section.get_child(0) as MarginContainer
	assert_object(pad).is_not_null()
	assert_int(pad.get_theme_constant("margin_right")).is_greater_equal(20)
