extends GdUnitTestSuite
## EJERCITO y ESCARAMUZAS con menos texto (2026-10-04): cada unidad sigue
## diciendo cuanto cuesta (en iconos), cuantas hay, su poder y su sueldo; los
## topes dicen de donde salen en el tooltip, y los motivos caben en una linea.

const TextKit := preload("res://scripts/ui/TextKit.gd")

func test_each_unit_row_keeps_cost_count_power_and_wage() -> void:
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/ArmyPanel.tscn").instantiate())
	add_child(panel)
	await await_idle_frame()
	panel._refresh()
	await await_idle_frame()
	var rows: Array = panel.find_children("Stats", "HFlowContainer", true, false).filter(
		func(n): return not n.is_queued_for_deletion())
	assert_int(rows.size()).is_equal(GameConfig.get_unit_ids().size())
	var i := 0
	for unit_id in GameConfig.get_unit_ids():
		var def := GameConfig.get_unit_def(unit_id)
		var row: Control = rows[i]
		var cost_row: Control = row.get_child(0)
		var shown := TextKit.row_amounts(cost_row)
		for res in def.get("cost", {}):
			assert_str(String(shown[res])).is_equal(str(int(def["cost"][res])))
		var power_text := Tr.t("LBL_ARMY_POWER_EACH") % int(def.get("power", 0))
		var has_power := false
		for child in row.get_children():
			if child is Label and (child as Label).text == power_text:
				has_power = true
		assert_bool(has_power).is_true()
		var upkeep: Control = row.find_child("Upkeep", true, false)
		assert_str(String(TextKit.row_amounts(upkeep)["gold"])).is_equal(str(int(def.get("upkeep_gold", 0))))
		i += 1

func test_the_caps_say_where_they_come_from_in_the_tooltip() -> void:
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/ArmyPanel.tscn").instantiate())
	add_child(panel)
	await await_idle_frame()
	panel._refresh()
	assert_str(panel._capacity_label.text).is_equal(
		Tr.t("LBL_ARMY_CAPACITY") % [ArmyManager.get_used_capacity(), ArmyManager.get_capacity()])
	assert_str(panel._capacity_label.tooltip_text).contains(str(GameConfig.army_capacity_per_barracks))
	assert_str(panel._slots_label.tooltip_text).is_not_empty()

func test_reasons_fit_in_a_line() -> void:
	for key in ["MSG_NO_UNITS", "LBL_ARMY_SLOTS_FULL", "LBL_ARMY_AT_CAP", "LBL_ARMY_LOCKED",
			"LBL_ARMY_NEED_BARRACKS", "MSG_AUDIT_BLOCKS_EXPEDITION", "MSG_EXPEDITION_ACTIVE"]:
		for locale in ["es", "en"]:
			var words: int = String(Tr._STRINGS[locale][key]).split(" ", false).size()
			assert_int(words).override_failure_message("%s/%s" % [locale, key]).is_less_equal(7)
	var resummon: String = "%s %s" % [Tr.t("AUDIT_RESUMMON_LOCKED") % 3, Tr.t("LBL_AUDIT_STANDING") % 1]
	assert_int(resummon.split(" ", false).size()).is_less_equal(8)
	assert_str(resummon).contains("3")
	assert_str(resummon).contains("1")
