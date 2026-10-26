extends GdUnitTestSuite
## Ronda de Bryan sobre la version previa de la fase 2 (2026-10-19):
##   - tema de las ventanas claro / oscuro (tokens de CartoonTheme);
##   - ENTRENAR en la ficha de los edificios militares;
##   - las muestras de PAIS Y BANDERA: placa del rango debajo, nunca encima;
##   - el boton Ejercito de la barra lleva al Cuartel.

const SettingsParking := preload("res://tests/save/settings_parking.gd")
const TrainingSectionScript := preload("res://scripts/ui/TrainingSection.gd")
var _parked: Dictionary = {}

func before_test() -> void:
	_parked = SettingsParking.park()

func after_test() -> void:
	SettingsParking.restore(_parked)
	DeviceProfile.apply_theme()

# ── Tema ─────────────────────────────────────────────────────────────

func test_the_dark_theme_paints_the_windows_and_keeps_the_hud() -> void:
	var hud_bg := CartoonTheme.c("hud", "BG")
	# Piel dieselpunk (2026-10-25): Pizarra, Placa y filo de laton.
	assert_object(CartoonTheme.c("window", "BG")).is_equal(Color("1c2026"))
	assert_object(CartoonTheme.c("window", "CARD")).is_equal(Color("252b32"))
	assert_object(CartoonTheme.c("window", "TRIM")).is_equal(Color("c99a45"))
	assert_object(CartoonTheme.c("hud", "BG")).is_equal(hud_bg)
	assert_bool(CartoonTheme.dark_windows()).is_true()
	for key in ["TEXT", "TEXT_DIM"]:
		for bg in ["BG", "CARD"]:
			assert_float(UITheme.contrast_ratio(CartoonTheme.c("window", key), CartoonTheme.c("window", bg))) \
				.override_failure_message("%s sobre %s" % [key, bg]).is_greater_equal(4.5)

func test_high_contrast_still_wins_in_the_dark_theme() -> void:
	UITheme.configure("default", true)
	assert_float(UITheme.contrast_ratio(CartoonTheme.c("window", "TEXT"), CartoonTheme.c("window", "BG"))).is_greater_equal(7.0)
	UITheme.configure()

## Ya no hay modo claro (0.9 beta): una clave window_theme vieja se ignora y se borra al guardar.
func test_an_old_window_theme_key_is_ignored_and_dropped() -> void:
	var cf := ConfigFile.new()
	cf.load(GameConfig.USER_SETTINGS_PATH)
	cf.set_value("interfaz", "window_theme", "light")
	cf.save(GameConfig.USER_SETTINGS_PATH)
	GameConfig.load_user_settings()
	assert_bool(CartoonTheme.dark_windows()).is_true()
	GameConfig.save_user_settings()
	cf = ConfigFile.new()
	cf.load(GameConfig.USER_SETTINGS_PATH)
	assert_bool(cf.has_section_key("interfaz", "window_theme")).is_false()

# ── ENTRENAR en el Cuartel ───────────────────────────────────────────

func test_the_training_section_lists_only_the_units_of_its_building() -> void:
	var section: VBoxContainer = auto_free(TrainingSectionScript.new())
	add_child(section)
	section.setup("barracks")
	var rows := section.find_child("TrainRows", true, false)
	assert_object(rows).is_not_null()
	assert_int(rows.get_child_count()).is_greater(0)
	for row in rows.get_children():
		var unit_id := String(row.name).trim_prefix("Unit_")
		assert_str(GameConfig.get_unit_building(unit_id)).is_equal("barracks")
		assert_object(row.find_child("TrainButton", true, false)).is_not_null()
	assert_object(section.find_child("SeeArmy", true, false)).is_not_null()

# ── PAIS Y BANDERA ───────────────────────────────────────────────────

func test_a_locked_piece_carries_its_plate_under_the_swatch() -> void:
	var plate: PanelContainer = auto_free(CartoonTheme.rank_plate(11))
	var label: Label = plate.find_child("RankLockLabel", true, false)
	assert_str(label.text).is_equal("11")
	var btn: Button = auto_free(Button.new())
	var box := VBoxContainer.new()
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(34, 34)
	box.add_child(swatch)
	box.add_child(CartoonTheme.rank_plate(3))
	CartoonTheme.fit_button_content(btn, box, 5.0)
	add_child(btn)
	await await_idle_frame()
	# El boton mide lo que su contenido: nada se corta por abajo.
	assert_float(btn.custom_minimum_size.y).is_greater_equal(box.get_combined_minimum_size().y)
	assert_float(btn.custom_minimum_size.y).is_greater(34.0 + 10.0)
