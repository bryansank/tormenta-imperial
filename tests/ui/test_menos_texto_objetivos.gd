extends GdUnitTestSuite
## ¿QUE HACER? con menos texto (2026-10-04): el paso, su porque en una frase
## corta y lo que falta siguen a la vista; la mision del modo pasa al tooltip
## del titulo y la nota de 29 palabras se va.

const Objectives := preload("res://scripts/services/Objectives.gd")

func test_the_panel_still_says_the_step_why_and_mission() -> void:
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/ObjectivePanel.tscn").instantiate())
	add_child(panel)
	await await_idle_frame()
	panel.toggle()
	var shown: Dictionary = panel.get_now_text()
	var expected: Dictionary = Objectives.describe(Objectives.next_step())
	assert_str(String(shown["title"])).is_equal(String(expected["title"]))
	assert_str(String(shown["why"])).is_equal(String(expected["why"]))
	assert_str(panel.mode_text()).contains(Tr.t(GameMode.goal_key()))
	panel.toggle()

func test_every_why_fits_in_a_short_sentence() -> void:
	for locale in ["es", "en"]:
		var table: Dictionary = Tr._STRINGS[locale]
		for key in table:
			if not String(key).begins_with("OBJ_WHY_"):
				continue
			var words: int = String(table[key]).split(" ", false).size()
			assert_int(words).override_failure_message("%s/%s: %d palabras" % [locale, key, words]).is_less_equal(16)

func test_market_and_lab_steps_point_at_their_buildings() -> void:
	# Mercado y Laboratorio salieron del menu el 2026-09-28: el paso no puede
	# mandar a "MENU > MERCADO".
	for key in ["OBJ_DO_BUY", "OBJ_DO_SELL", "OBJ_DO_RESEARCH"]:
		assert_str(Tr._STRINGS["es"][key]).not_contains("MENÚ")
		assert_str(Tr._STRINGS["en"][key]).not_contains("MENU")
