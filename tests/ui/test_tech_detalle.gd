extends GdUnitTestSuite
## Ficha de la tecnologia elegida (TechTreePanel, decision de Bryan del
## 2026-10-05): las tarjetas siguen cortas; tocar una la ELIGE y la ficha dice
## nombre, lore, la frase de su rama, coste en iconos, tiempo, ventaja y
## requisito, con el boton INVESTIGAR. El lore y la rama ya no viven solo en un
## tooltip.
##
## Toca TechTreeManager y ResourceManager (autoloads): vuelven como estaban.

const TechTreePanelScript := preload("res://scripts/ui/TechTreePanel.gd")
const TextKit := preload("res://scripts/ui/TextKit.gd")

var _tech_saved: Dictionary = {}
var _res_saved: Dictionary = {}

func before_test() -> void:
	_tech_saved = TechTreeManager.get_save_data()
	_res_saved = {}
	var all: Dictionary = ResourceManager.get_all()
	for type in all:
		_res_saved[ResourceManager.get_type_name(type)] = all[type]
	TechTreeManager.reset()

func after_test() -> void:
	TechTreeManager.reset()
	TechTreeManager.load_save_data(_tech_saved)
	ResourceManager.set_amounts(_res_saved)

func _panel() -> CanvasLayer:
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/TechTreePanel.tscn").instantiate())
	add_child(panel)
	return panel

func _branch(branch: String = "industrial") -> Array:
	var techs: Array = TechTreeManager.get_branch_techs(branch)
	techs.sort_custom(func(a, b): return a["tier"] < b["tier"])
	return techs

func _label(panel: Node, node_name: String) -> Label:
	return panel.find_child(node_name, true, false) as Label

func test_the_detail_tells_lore_branch_cost_time_effect_and_requirement() -> void:
	ResourceManager.set_amounts({"gold": 5000, "wood": 5000})
	var panel := _panel()
	var tier1: Dictionary = _branch()[0]
	var tier2: Dictionary = _branch()[1]
	panel.select(tier1["id"])
	assert_str(panel.selected_tech()).is_equal(tier1["id"])
	assert_bool(panel.detail_panel().visible).is_true()
	assert_str(_label(panel, "DetailName").text).is_equal(Tr.t(tier1["name"]))
	assert_str(_label(panel, "DetailLore").text).is_equal(TechTreePanelScript.lore_text(tier1["id"]))
	assert_str(_label(panel, "DetailBranch").text).is_equal(Tr.t("TECH_BRANCH_INDUSTRIAL_DESC"))
	assert_str(_label(panel, "DetailEffect").text).is_equal(TechTreePanelScript.advantage_text(tier1))
	assert_str(_label(panel, "DetailRequires").text).is_equal(Tr.t("LBL_TECH_NO_REQ"))
	var secs := GameConfig.get_duration(float(tier1["duration"]))
	assert_str(_label(panel, "DetailTime").text).contains(TextKit.short_time(secs))
	# El coste, en iconos con su cifra: lo que de verdad ve el jugador.
	var shown: Dictionary = TextKit.row_amounts(panel.find_child("DetailCost", true, false))
	var cost: Dictionary = tier1["cost"]
	assert_int(shown.size()).is_equal(cost.size())
	for res in cost:
		assert_str(String(shown[res])).is_equal(str(int(cost[res])))
	# El nivel 2 dice lo que pide.
	panel.select(tier2["id"])
	assert_str(_label(panel, "DetailRequires").text).is_equal(Tr.t("LBL_REQUIRES") % Tr.t(tier1["name"]))
	assert_str(_label(panel, "DetailLore").text).is_equal(TechTreePanelScript.lore_text(tier2["id"]))

func test_the_branch_phrase_follows_the_chosen_tech() -> void:
	var panel := _panel()
	panel.select(_branch("logistics")[0]["id"])
	assert_str(_label(panel, "DetailBranch").text).is_equal(Tr.t("TECH_BRANCH_LOGISTICS_DESC"))

func test_tapping_a_card_chooses_it_and_does_not_research() -> void:
	ResourceManager.set_amounts({"gold": 5000, "wood": 5000})
	var panel := _panel()
	var tier1: Dictionary = _branch("military")[0]
	var card: Button = panel._tech_buttons[tier1["id"]]
	card.pressed.emit()
	assert_str(panel.selected_tech()).is_equal(tier1["id"])
	assert_bool(TechTreeManager.is_researching()).is_false()

func test_the_research_button_starts_the_chosen_tech() -> void:
	ResourceManager.set_amounts({"gold": 5000, "wood": 5000})
	var panel := _panel()
	var tier1: Dictionary = _branch()[0]
	panel.select(tier1["id"])
	var btn: Button = panel.research_button()
	assert_str(btn.text).is_equal(Tr.t("BTN_RESEARCH"))
	assert_bool(btn.disabled).is_false()
	btn.pressed.emit()
	assert_bool(TechTreeManager.is_researching()).is_true()
	assert_str(String(TechTreeManager.get_current_research()["tech_id"])).is_equal(tier1["id"])
	# Ya en curso: la ficha lo dice y el boton se va.
	assert_bool(btn.visible).is_false()
	assert_str(_label(panel, "DetailReason").text).is_equal(Tr.t("LBL_TECH_IN_PROGRESS"))

func test_a_blocked_tech_can_be_read_but_not_researched() -> void:
	ResourceManager.set_amounts({"gold": 5000, "wood": 5000})
	var panel := _panel()
	var tier2: Dictionary = _branch()[1]
	var card: Button = panel._tech_buttons[tier2["id"]]
	# La tarjeta no se apaga: se toca para leerla.
	assert_bool(card.disabled).is_false()
	card.pressed.emit()
	assert_bool(panel.research_button().disabled).is_true()
	assert_str(_label(panel, "DetailReason").text).is_equal(panel.blocker_text(tier2["id"]))
	panel.research_button().pressed.emit()
	assert_bool(TechTreeManager.is_researching()).is_false()

func test_missing_resources_show_in_red_in_the_detail() -> void:
	ResourceManager.set_amounts({"gold": 0, "wood": 0})
	var panel := _panel()
	var tier1: Dictionary = _branch()[0]
	panel.select(tier1["id"])
	var row: Control = panel.find_child("DetailCost", true, false)
	var gold_label: Label = row.find_child("Amount_gold", true, false)
	assert_object(gold_label).is_not_null()
	assert_that(gold_label.get_theme_color("font_color")).is_equal(UITheme.readable(UITheme.DANGER))

func test_the_detail_opens_with_something_to_read() -> void:
	var panel := _panel()
	assert_str(panel.selected_tech()).is_not_empty()
	assert_str(_label(panel, "DetailName").text).is_not_empty()

func test_the_detail_goes_below_on_a_narrow_screen() -> void:
	assert_bool(TechTreePanelScript.detail_below(480.0)).is_true()
	assert_bool(TechTreePanelScript.detail_below(1280.0)).is_false()

func test_the_new_texts_exist_in_both_languages() -> void:
	for locale in Tr.LOCALES:
		for key in ["BTN_RESEARCH", "FMT_TECH_TIER", "FMT_TECH_TIME", "LBL_TECH_NO_REQ",
				"LBL_TECH_RESEARCHED", "LBL_TECH_IN_PROGRESS"]:
			assert_bool(Tr._STRINGS[locale].has(key)).override_failure_message("%s/%s" % [locale, key]).is_true()
