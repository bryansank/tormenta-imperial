extends GdUnitTestSuite
## Un boton apagado sin motivo parece un fallo. Aqui se vigilan los dos que no
## decian nada:
##
##   * las tecnologias que no se pueden investigar (TechTreePanel), que ahora
##     dicen si falta el nivel anterior, si faltan recursos o si hay otra en curso;
##   * "VOLVER A CONVOCARLOS" (SkirmishPanel), que dice cuantas unidades hacen
##     falta en pie y no falla en silencio al pulsarlo.

var _tech_saved: Dictionary = {}
var _res_saved: Dictionary = {}
var _audit_saved = null
var _army_saved: Dictionary = {}
var _notes: Array = []

func before_test() -> void:
	_tech_saved = TechTreeManager.get_save_data()
	_res_saved = {}
	var all: Dictionary = ResourceManager.get_all()
	for type in all:
		_res_saved[ResourceManager.get_type_name(type)] = all[type]
	_audit_saved = ProgressionManager.final_audit
	_army_saved = ArmyManager._units.duplicate()
	_notes.clear()
	TechTreeManager.reset()
	EventBus.notification_posted.connect(_grab_note)

func after_test() -> void:
	EventBus.notification_posted.disconnect(_grab_note)
	TechTreeManager.reset()
	TechTreeManager.load_save_data(_tech_saved)
	ResourceManager.set_amounts(_res_saved)
	ProgressionManager.final_audit = _audit_saved
	ArmyManager._units = _army_saved

func _grab_note(message: String, _category: String, _color: Color) -> void:
	_notes.append(message)

func _branch() -> Array:
	var techs: Array = TechTreeManager.get_branch_techs("industrial")
	techs.sort_custom(func(a, b): return a["tier"] < b["tier"])
	return techs

func _rich() -> void:
	ResourceManager.set_amounts({"gold": 5000, "wood": 5000, "steel": 5000, "oil": 5000})

func _broke() -> void:
	ResourceManager.set_amounts({"gold": 0, "wood": 0, "steel": 0, "oil": 0})

# ── Arbol tecnologico: el manager ────────────────────────────────────

func test_a_tier_two_tech_is_blocked_by_its_prerequisite() -> void:
	_rich()
	var tier2: Dictionary = _branch()[1]
	assert_str(TechTreeManager.get_research_blocker(tier2["id"])).is_equal("TECH_BLOCK_PREREQ")
	assert_array(TechTreeManager.get_missing_prerequisites(tier2["id"])).contains([_branch()[0]["id"]])

func test_a_tech_without_the_money_says_what_is_missing() -> void:
	_broke()
	var tier1: Dictionary = _branch()[0]
	assert_str(TechTreeManager.get_research_blocker(tier1["id"])).is_equal("TECH_BLOCK_COST")
	var missing: Dictionary = TechTreeManager.get_missing_cost(tier1["id"])
	for res_name in tier1.get("cost", {}):
		assert_int(int(missing.get(res_name, 0))).is_equal(int(tier1["cost"][res_name]))

func test_research_under_way_blocks_the_rest() -> void:
	_rich()
	var branch := _branch()
	assert_bool(TechTreeManager.start_research(branch[0]["id"])).is_true()
	var other: Dictionary = TechTreeManager.get_branch_techs("military")[0]
	assert_str(TechTreeManager.get_research_blocker(other["id"])).is_equal("TECH_BLOCK_RESEARCHING")

func test_nothing_blocks_an_affordable_first_tier() -> void:
	_rich()
	var tier1: Dictionary = _branch()[0]
	assert_str(TechTreeManager.get_research_blocker(tier1["id"])).is_empty()
	assert_bool(TechTreeManager.can_research(tier1["id"])).is_true()

func test_the_blocker_agrees_with_can_research() -> void:
	# El motivo no puede decir "nada te para" de algo que no se puede investigar.
	for amounts in [{"gold": 0, "wood": 0, "steel": 0, "oil": 0}, {"gold": 5000, "wood": 5000, "steel": 5000, "oil": 5000}]:
		ResourceManager.set_amounts(amounts)
		for tech in TechTreeManager.get_all_techs():
			var blocked: bool = TechTreeManager.get_research_blocker(tech["id"]) != ""
			assert_bool(blocked).is_equal(not TechTreeManager.can_research(tech["id"]))

# ── Arbol tecnologico: el panel ──────────────────────────────────────

func test_the_panel_writes_the_reason_under_a_blocked_tech() -> void:
	_rich()
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/TechTreePanel.tscn").instantiate())
	add_child(panel)
	var tier1: Dictionary = _branch()[0]
	var tier2: Dictionary = _branch()[1]
	panel._refresh_tech_states()
	var btn: Button = panel._tech_buttons[tier2["id"]]
	assert_str(btn.text).contains(Tr.t("TECH_BLOCK_PREREQ") % Tr.t(tier1["name"]))
	assert_str(panel._tech_buttons[tier1["id"]].text).not_contains(Tr.t("TECH_BLOCK_PREREQ").split("%")[0])

func test_the_reason_is_rewritten_not_piled_up() -> void:
	_broke()
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/TechTreePanel.tscn").instantiate())
	add_child(panel)
	var tier1: Dictionary = _branch()[0]
	for i in 3:
		panel._refresh_tech_states()
	var btn: Button = panel._tech_buttons[tier1["id"]]
	var prefix: String = Tr.t("TECH_BLOCK_COST").split("%")[0]
	assert_int(btn.text.count(prefix)).is_equal(1)
	_rich()
	panel._refresh_tech_states()
	assert_int(btn.text.count(prefix)).is_equal(0)

# ── Volver a convocar a la Regencia ──────────────────────────────────

func _lost_audit() -> void:
	var audit := FinalAudit.create(21, {"infantry": 2}, 1, 50.0)
	audit.begin()
	audit.lose()
	ProgressionManager.final_audit = audit

func _panel() -> CanvasLayer:
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/SkirmishPanel.tscn").instantiate())
	add_child(panel)
	return panel

func test_the_resummon_button_says_how_many_units_it_needs() -> void:
	_lost_audit()
	ArmyManager._units = {"infantry": 1}
	var panel := _panel()
	panel._refresh()
	assert_bool(panel._audit_btn.visible).is_true()
	assert_bool(panel._audit_btn.disabled).is_true()
	assert_bool(panel._audit_reason.visible).is_true()
	assert_str(panel._audit_reason.text).contains(Tr.t("AUDIT_RESUMMON_LOCKED") % GameConfig.final_audit_resummon_min_units)
	assert_str(panel._audit_reason.text).contains(Tr.t("LBL_AUDIT_STANDING") % 1)

func test_with_enough_units_there_is_no_reason_to_show() -> void:
	_lost_audit()
	ArmyManager._units = {"infantry": GameConfig.final_audit_resummon_min_units}
	var panel := _panel()
	panel._refresh()
	assert_bool(panel._audit_btn.disabled).is_false()
	assert_bool(panel._audit_reason.visible).is_false()
	assert_str(panel.audit_block_reason()).is_empty()

func test_pressing_it_anyway_is_never_silent() -> void:
	_lost_audit()
	ArmyManager._units = {"infantry": 1}
	var panel := _panel()
	panel._on_audit_pressed()
	assert_bool(ProgressionManager.is_final_audit_lost()).is_true()
	assert_array(_notes).is_not_empty()
	assert_str(String(_notes.back())).contains(Tr.t("AUDIT_RESUMMON_LOCKED") % GameConfig.final_audit_resummon_min_units)
