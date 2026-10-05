extends GdUnitTestSuite
## El arbol tecnologico se explica solo: cada tecnologia dice su ventaja con los
## numeros de GameConfig y tiene su linea de lore en los dos idiomas, y el panel
## cuenta arriba que es el arbol y que hace cada rama.

const TechTreePanelScript := preload("res://scripts/ui/TechTreePanel.gd")

var _locale_saved := "es"

func before_test() -> void:
	_locale_saved = Tr.get_locale()

func after_test() -> void:
	Tr.set_locale(_locale_saved)

func test_every_tech_has_its_lore_in_both_languages() -> void:
	for tech in GameConfig.tech_definitions:
		var key: String = "TECH_LORE_" + String(tech["id"])
		for locale in Tr.LOCALES:
			var table: Dictionary = Tr._STRINGS[locale]
			assert_bool(table.has(key)).override_failure_message("%s falta en %s" % [key, locale]).is_true()
			assert_str(String(table.get(key, ""))).is_not_empty()

func test_every_tech_states_a_non_empty_advantage() -> void:
	for locale in Tr.LOCALES:
		Tr.set_locale(locale)
		for tech in GameConfig.tech_definitions:
			var text: String = TechTreePanelScript.advantage_text(tech)
			assert_str(text).override_failure_message("%s sin ventaja en %s" % [tech["id"], locale]).is_not_empty()
			# Una clave sin traducir se veria tal cual.
			assert_str(text).not_contains("TECH_ADV_")

func test_the_advantage_uses_the_real_numbers() -> void:
	Tr.set_locale("es")
	for tech in GameConfig.tech_definitions:
		var text: String = TechTreePanelScript.advantage_text(tech)
		var bonus: Dictionary = tech.get("bonus", {})
		for key in bonus:
			var val = bonus[key]
			var shown: int = int(val) if key in ["storage_bonus", "morale_bonus"] else roundi(float(val) * 100.0)
			assert_str(text).contains(str(shown))

func test_intro_and_branch_descriptions_exist_in_both_languages() -> void:
	var keys := ["LBL_TECH_INTRO", "LBL_TECH_ADVANTAGE"]
	for branch in ["INDUSTRIAL", "MILITARY", "LOGISTICS"]:
		keys.append("TECH_BRANCH_%s_DESC" % branch)
	for locale in Tr.LOCALES:
		for key in keys:
			assert_bool(Tr._STRINGS[locale].has(key)).override_failure_message("%s falta en %s" % [key, locale]).is_true()

## Menos texto (2026-10-04): la ventaja y el coste en el boton; el lore en su
## tooltip; la intro en una linea con el parrafo entero de tooltip; la rama
## explicada en el tooltip de su cabecera.
func test_the_panel_shows_the_advantage_and_the_lore() -> void:
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/TechTreePanel.tscn").instantiate())
	add_child(panel)
	panel._refresh_tech_states()
	var tech: Dictionary = GameConfig.tech_definitions[0]
	var btn: Button = panel._tech_buttons[tech["id"]]
	assert_str(btn.text).contains(TechTreePanelScript.advantage_text(tech))
	for res in tech.get("cost", {}):
		assert_str(btn.text).contains("%d %s" % [int(tech["cost"][res]), Tr.res_name(res)])
	assert_str(btn.tooltip_text).contains(TechTreePanelScript.lore_text(tech["id"]))
	var intro: Label = panel.find_child("Intro", true, false)
	assert_str(intro.text).is_equal(Tr.t("LBL_TECH_INTRO_SHORT"))
	assert_str(intro.tooltip_text).is_equal(Tr.t("LBL_TECH_INTRO"))
	var branch: Label = panel.find_child("Branch_industrial", true, false)
	assert_str(branch.tooltip_text).is_equal(Tr.t("TECH_BRANCH_INDUSTRIAL_DESC"))

func test_a_tech_card_is_three_short_lines_at_most() -> void:
	for tech in GameConfig.tech_definitions:
		var text: String = TechTreePanelScript.tech_card_text(tech)
		assert_int(text.split("\n").size()).is_less_equal(3)
		assert_str(text).not_contains(Tr.t("FMT_COST") % "")
