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
	# El titulo es el objetivo (2026-10-19, feat/objetivo-paso-a-paso).
	var plan: Dictionary = Objectives.plan()
	var expected: Dictionary = Objectives.describe(plan["goal"])
	assert_str(String(shown["title"])).is_equal(String(plan["title"]))
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

## Ningun texto del objetivo ni del tutorial empieza por "Edificio:" (queja de
## Bryan, 2026-10-19): las frases que llevan un nombre lo llevan dentro.
func test_no_objective_or_tutorial_text_starts_with_a_name_and_a_colon() -> void:
	var prefixes := ["OBJ_DO_", "OBJ_STEP_", "OBJ_GOAL_", "GUIDE_NEED", "GUIDE_SKIP_", "GUIDE_HOW_", "TOPE_HOW_MATERIAL"]
	for locale in ["es", "en"]:
		var table: Dictionary = Tr._STRINGS[locale]
		for key in table:
			var k := String(key)
			var hit := false
			for pre in prefixes:
				if k.begins_with(pre):
					hit = true
			if not hit:
				continue
			assert_bool(String(table[key]).begins_with("%s:")).override_failure_message("%s/%s" % [locale, k]).is_false()
