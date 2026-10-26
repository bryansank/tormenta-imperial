extends GdUnitTestSuite
## feat/hud-y-tutorial (1.1): lo que la ronda de pruebas de la 1.0 pedia del HUD
## y del tutorial.
## - Nombres bajo los iconos del HUD ("Oro", "Trabajadores", "Moral"): auto /
##   siempre / nunca en Ajustes > Interfaz, en settings.cfg [interfaz] hud_words.
##   En "auto": tableta y movil siempre; PC, la primera hora de las primeras
##   partidas. Con palabras la fila se parte antes de empujar la columna central.
## - Tarjeta "consigue lo que falta": el "arrastra el mapa" al final, como mucho
##   cinco lineas, sin las cifras del edificio.
## - Solo falta otra Casa (el Laboratorio tras el Cuartel temprano): una frase
##   natural, no "aun no puedes" + lista.
## - La tarjeta del combate guiado se aparta de los avisos y de la ficha.
## - Textos de la ronda: musica sin repetir, SEGUIR en la partida en juego,
##   "5/5" una sola vez, ficha de unidad sin "x1,5" suelto.
##
## settings.cfg se aparca byte a byte; GameConfig, poblacion y recursos vuelven.

const SettingsParking := preload("res://tests/save/settings_parking.gd")
const TP := preload("res://scripts/ui/TutorialPanel.gd")
const UnitCardScript := preload("res://scripts/ui/UnitCard.gd")
const Objectives := preload("res://scripts/services/Objectives.gd")
const LAB := preload("res://data/buildings/laboratory.tres")
const HOUSE := preload("res://data/buildings/house.tres")

var _parked: Dictionary = {}
var _pop: Dictionary = {}
var _res: Dictionary = {}
var _runs := 0
var _played := 0.0
var _locale := "es"

func before_test() -> void:
	_parked = SettingsParking.park()
	_pop = {
		"population": PopulationManager._population,
		"max": PopulationManager._max_population,
		"used": PopulationManager._used_workers,
	}
	_res = {
		"gold": ResourceManager.get_amount(ResourceManager.Type.GOLD),
		"wood": ResourceManager.get_amount(ResourceManager.Type.WOOD),
	}
	_runs = GameConfig.profile_runs_finished
	_played = ProgressionManager._played_seconds
	_locale = Tr.get_locale()

func after_test() -> void:
	PopulationManager._population = _pop["population"]
	PopulationManager._max_population = _pop["max"]
	PopulationManager._used_workers = _pop["used"]
	ResourceManager.set_amounts(_res)
	GameConfig.profile_runs_finished = _runs
	ProgressionManager._played_seconds = _played
	Tr.set_locale(_locale)
	SettingsParking.restore(_parked)

func _hud() -> CanvasLayer:
	var hud: CanvasLayer = auto_free(load("res://scenes/ui/ResourceHUD.tscn").instantiate())
	add_child(hud)
	return hud

# ── 1. Nombres bajo los iconos ───────────────────────────────────────

func test_auto_shows_words_on_touch_and_for_new_players_on_pc() -> void:
	GameConfig.ui_hud_words = "auto"
	GameConfig.profile_runs_finished = 0
	# Tableta / movil: siempre, aunque lleve horas.
	assert_bool(GameConfig.hud_words_enabled(99999.0, 1)).is_true()
	# PC: la primera hora de las primeras partidas.
	assert_bool(GameConfig.hud_words_enabled(0.0, 0)).is_true()
	assert_bool(GameConfig.hud_words_enabled(GameConfig.hud_words_first_seconds - 1.0, 0)).is_true()
	assert_bool(GameConfig.hud_words_enabled(GameConfig.hud_words_first_seconds + 1.0, 0)).is_false()
	# Un jugador con partidas acabadas ya no las necesita en PC.
	GameConfig.profile_runs_finished = GameConfig.hud_words_new_runs
	assert_bool(GameConfig.hud_words_enabled(0.0, 0)).is_false()
	assert_bool(GameConfig.hud_words_enabled(0.0, 1)).is_true()

func test_always_and_never_force_it() -> void:
	GameConfig.ui_hud_words = "always"
	assert_bool(GameConfig.hud_words_enabled(99999.0, 0)).is_true()
	GameConfig.ui_hud_words = "never"
	assert_bool(GameConfig.hud_words_enabled(0.0, 1)).is_false()

func test_the_hud_writes_the_word_under_each_icon() -> void:
	GameConfig.ui_hud_words = "always"
	var hud := _hud()
	assert_bool(hud.words_shown()).is_true()
	var gold: HBoxContainer = hud.find_child("Chip_gold", true, false)
	var word: Label = hud.word_of(gold)
	assert_object(word).is_not_null()
	assert_bool(word.visible).is_true()
	assert_str(word.text).is_equal(Tr.res_cap("gold"))
	assert_str(hud.word_of(hud.workers_chip()).text).is_equal(Tr.t("HUD_WORD_WORKERS"))
	assert_str(hud.word_of(hud.morale_chip()).text).is_equal(Tr.t("HUD_WORD_MORALE"))
	# La palabra va en la celda de la ficha, debajo.
	assert_object(word.get_parent()).is_same(gold.get_parent())
	assert_int(word.get_index()).is_greater(gold.get_index())

func test_never_leaves_only_icons_and_numbers() -> void:
	GameConfig.ui_hud_words = "never"
	var hud := _hud()
	assert_bool(hud.words_shown()).is_false()
	for chip in hud.tap_targets():
		assert_bool(hud.word_of(chip).visible).is_false()

func test_changing_the_setting_updates_the_hud_at_once_and_saves_it() -> void:
	GameConfig.ui_hud_words = "never"
	var hud := _hud()
	GameConfig.set_hud_words("always")
	assert_bool(hud.words_shown()).is_true()
	var cf := ConfigFile.new()
	assert_int(cf.load(GameConfig.USER_SETTINGS_PATH)).is_equal(OK)
	assert_str(str(cf.get_value("interfaz", "hud_words", ""))).is_equal("always")
	GameConfig.set_hud_words("never")
	assert_bool(hud.words_shown()).is_false()

func test_an_unknown_value_in_settings_goes_back_to_auto() -> void:
	var cf := ConfigFile.new()
	cf.set_value("interfaz", "hud_words", "a_veces")
	assert_int(cf.save(GameConfig.USER_SETTINGS_PATH)).is_equal(OK)
	GameConfig.ui_hud_words = "never"
	GameConfig.load_user_settings()
	assert_str(GameConfig.ui_hud_words).is_equal("auto")

## Preferencia del dispositivo: nada de la partida la escribe ni la lee.
func test_the_words_never_travel_in_the_save() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/services/GameManager.gd")
	assert_str(src).not_contains("hud_words")

## Con palabras, la fila no pasa de WORDS_ROW_MAX: se parte en dos filas y la
## columna central (1280x720) no se mueve por ella.
func test_with_words_the_row_wraps_instead_of_growing() -> void:
	GameConfig.ui_hud_words = "always"
	var unlock := ResourceManager.get_unlock_state()
	ResourceManager.set_unlock_state({"gold": true, "wood": true, "food": true, "steel": true, "oil": true})
	var hud := _hud()
	hud._fit_row()
	await await_idle_frame()
	var row: Control = hud.find_child("ChipsRow", true, false)
	ResourceManager.set_unlock_state(unlock)
	assert_float(row.custom_minimum_size.x).is_less_equal(hud.WORDS_ROW_MAX)

func test_settings_has_the_names_row_and_reset_puts_it_on_auto() -> void:
	var p: CanvasLayer = auto_free(load("res://scenes/ui/SettingsPanel.tscn").instantiate())
	add_child(p)
	var row: Node = p.find_child("HudWordsRow", true, false)
	assert_object(row).is_not_null()
	row.find_child("Picker", true, false).item_selected.emit(2)
	assert_str(GameConfig.ui_hud_words).is_equal("never")
	p.reset_interface()
	assert_str(GameConfig.ui_hud_words).is_equal("auto")

# ── 3. Tarjeta "consigue lo que falta" ───────────────────────────────

func test_the_move_the_map_line_goes_last() -> void:
	var text := TP.compose_card_text("Paso", "Te falta: 20 madera", "Mas madera: toca el icono", true)
	var lines := text.split("\n")
	assert_str(lines[lines.size() - 1]).is_equal(Tr.ti("GUIDE_MOVE_CAMERA"))
	assert_str(lines[0]).is_equal("Paso")

func test_the_card_keeps_to_five_lines() -> void:
	var how := "uno\ndos\ntres\ncuatro"
	var text := TP.compose_card_text("Paso", "Faltan trabajadores: 1 mas.\nTe falta: 20 madera", how, true)
	assert_int(text.split("\n").size()).is_less_equal(TP.CARD_MAX_LINES)
	# Siempre queda al menos una linea de como conseguirlo.
	assert_str(text).contains("uno")
	# Sin el aviso de la camara cabe una linea mas.
	var text2 := TP.compose_card_text("Paso", "Te falta: 20 madera", how, false)
	assert_int(text2.split("\n").size()).is_equal(TP.CARD_MAX_LINES)

func test_need_steps_hide_the_building_figures() -> void:
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/TutorialPanel.tscn").instantiate())
	add_child(panel)
	panel._on_step_changed("open_build")
	assert_str(panel.facts_text()).is_not_empty()
	panel._on_step_changed("need_sawmill")
	assert_str(panel.facts_text()).is_empty()

# ── 2. El Laboratorio y la otra Casa ─────────────────────────────────

func test_only_short_of_room_the_step_asks_for_another_house_naturally() -> void:
	ResourceManager.set_amounts({"gold": 300, "wood": 200})
	# Casas llenas y le falta un trabajador a la Mina de oro (11 de 11, usa 9;
	# el Laboratorio ya no es del tutorial corto, 2026-10-24).
	PopulationManager._population = 11
	PopulationManager._max_population = 11
	PopulationManager._used_workers = 9
	assert_bool(TutorialManager.needs_house_only("gold_mine")).is_true()
	# El objetivo en verbo (2026-10-19) y, como paso de ahora, la otra Casa.
	var text := TutorialManager.step_text("need_gold_mine")
	assert_str(text).is_equal(Objectives.goal_title({"kind": "build", "id": "gold_mine"}))
	assert_str(text).not_contains("%")
	assert_str(text).not_contains(load("res://data/buildings/gold_mine.tres").get_display_name() + ":")
	# El paso de ahora es una Casa: "otra" si ya hay, o la que pide el
	# Laboratorio antes (esta prueba no planta ninguna en la rejilla).
	var hint := TutorialManager.step_hint("need_gold_mine")
	assert_bool(hint.contains("● " + Tr.t("OBJ_STEP_HOUSE") % HOUSE.population_capacity)
		or hint.contains("● " + Tr.t("OBJ_DO_BUILD") % Objectives.building_a("house"))).override_failure_message(hint).is_true()
	# Con sitio en las casas la gente llega sola: esperar es el paso.
	PopulationManager._max_population = 17
	assert_bool(TutorialManager.needs_house_only("gold_mine")).is_false()
	assert_str(TutorialManager.step_hint("need_gold_mine")).contains(Tr.t("OBJ_STEP_WORKERS_WAIT") % 1)
	# Si ademas faltan recursos, no es "solo una Casa".
	PopulationManager._max_population = 11
	ResourceManager.set_amounts({"gold": 0, "wood": 0})
	assert_bool(TutorialManager.needs_house_only("gold_mine")).is_false()

func test_the_house_sentence_exists_in_both_languages() -> void:
	for lang in ["es", "en"]:
		Tr.set_locale(lang)
		var s := Tr.t("GUIDE_NEED_HOUSE") % ["X", 6]
		assert_str(s).contains("X")
		assert_str(s).contains("6")

# ── 2. Combate guiado: la tarjeta no tapa los avisos ─────────────────

func test_the_combat_card_moves_off_the_notices_on_the_left() -> void:
	var vp := Vector2(1280, 720)
	var size := Vector2(460, 140)
	var toasts := Rect2(10, 300, 344, 210)
	# Sin foco, la tarjeta va arriba al centro; ponla a mano encima de los avisos.
	var pos := TP.clear_of(Vector2(20, 320), size, [toasts], vp, Rect2())
	assert_bool(Rect2(pos, size).intersects(toasts.grow(TP.AVOID_GAP))).is_false()
	assert_bool(Rect2(Vector2(TP.EDGE, TP.EDGE), vp - Vector2(TP.EDGE, TP.EDGE) * 2.0).encloses(Rect2(pos, size))).is_true()
	# Lo que no pisa nada se queda donde esta.
	assert_vector(TP.clear_of(Vector2(600, 40), size, [toasts], vp, Rect2())).is_equal(Vector2(600, 40))

func test_the_combat_card_does_not_cover_the_target_while_dodging() -> void:
	var vp := Vector2(1280, 720)
	var size := Vector2(460, 140)
	var card_at_left := Rect2(16, 200, 300, 260)
	var focus := Rect2(380, 200, 80, 80)
	var pos := TP.clear_of(Vector2(20, 220), size, [card_at_left], vp, focus)
	if pos != Vector2(20, 220):
		assert_bool(Rect2(pos, size).intersects(focus)).is_false()

# ── 4. Textos de la ronda ────────────────────────────────────────────

func test_music_is_not_named_twice_in_audio() -> void:
	for lang in ["es", "en"]:
		Tr.set_locale(lang)
		assert_str(Tr.t("LBL_MUSIC_ENABLED")).is_not_equal(Tr.t("LBL_VOL_MUSIC"))

func test_the_unit_card_says_the_advantage_in_words() -> void:
	Tr.set_locale("es")
	assert_str(UnitCardScript.mult_words(true, 1.5)).is_equal(Tr.t("LBL_CARD_STRONG_MULT") % "1,5")
	assert_str(UnitCardScript.mult_words(true, 1.5)).not_contains("×")
	assert_str(UnitCardScript.mult_words(false, 0.75)).is_equal(Tr.t("LBL_CARD_WEAK_MULT"))

func test_new_keys_exist_in_both_languages() -> void:
	for lang in ["es", "en"]:
		for key in ["HUD_WORD_WORKERS", "HUD_WORD_MORALE", "LBL_HUD_WORDS", "OPT_HUD_WORDS_AUTO",
				"OPT_HUD_WORDS_ALWAYS", "OPT_HUD_WORDS_NEVER", "LBL_HUD_WORDS_HINT", "GUIDE_NEED_HOUSE",
				"LBL_SAVES_FULL_ROOM", "BTN_SAVE_CONTINUE", "LBL_CARD_STRONG_MULT", "LBL_CARD_WEAK_MULT"]:
			assert_bool(Tr._STRINGS[lang].has(key)).override_failure_message("%s/%s" % [lang, key]).is_true()
	# "5/5" una sola vez: el aviso de lista llena ya no lleva la cifra.
	assert_str(Tr._STRINGS["es"]["LBL_SAVES_FULL_ROOM"]).not_contains("%")
