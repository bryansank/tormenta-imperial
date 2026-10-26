extends GdUnitTestSuite
## Rediseno de interfaz, fase 2 (feat/ui2-ejercito, docs/28): Ejercito,
## Misiones, combate y partes con las piezas de CartoonTheme. Comprueba las
## piezas nuevas (seccion "EJÉRCITO" de CartoonTheme), los textos cortos en los
## dos idiomas y la estructura que leen la UI y las pruebas.
##
## Escrito SIN EJECUTAR (regla de Bryan: un solo pase de pruebas al final).

const CT := preload("res://scripts/ui/CartoonTheme.gd")

const NEW_KEYS := ["ARMY2_TAB_LAND", "ARMY2_TAB_SEA", "ARMY2_TAB_AIR", "ARMY2_TAB_RAIDS",
	"ARMY2_BTN_ATTACK", "ARMY2_TROOP", "ARMY2_HOME_N", "ARMY2_AWAY_N", "ARMY2_ENEMY_TIP",
	"ARMY2_LOOT_TIP", "ARMY2_FIGHTS_N", "ARMY2_MISSION_N", "ARMY2_GATE", "ARMY2_GATE_HQ",
	"ARMY2_POWER", "ARMY2_TROOPS", "ARMY2_QUEUE", "ARMY2_TRAIN_TIP", "ARMY2_CARD_TIP",
	"ARMY2_PICK_TROOPS", "ARMY2_GOING_OUT", "ARMY2_REPORT", "ARMY2_DRAFT", "ARMY2_SIEGE",
	"ARMY2_MAP", "ARMY2_RESULT", "ARMY2_STARS_N", "ARMY2_ROUND", "ARMY2_ROUND_TIP"]

func test_every_new_text_exists_in_both_languages_and_is_short() -> void:
	for locale in ["es", "en"]:
		for key in NEW_KEYS:
			var text: String = String(Tr._STRINGS[locale].get(key, ""))
			assert_str(text).override_failure_message("%s falta en %s" % [key, locale]).is_not_empty()
			# docs/28 §9: una frase de 8 palabras como mucho.
			assert_int(text.split(" ", false).size()).override_failure_message(key).is_less_equal(8)
	assert_str(Tr._STRINGS["es"]["ARMY2_BTN_ATTACK"]).is_equal("¡AL ATAQUE!")

func test_the_cost_row_names_each_amount_like_text_kit() -> void:
	var row := CT.cost_row({"gold": 40, "wood": 20}, {"wood": 5})
	add_child(row)
	var shown := CT.row_amounts(row)
	assert_str(String(shown["gold"])).is_equal("40")
	assert_str(String(shown["wood"])).is_equal("20")
	assert_object(row.find_child("Cost_wood", true, false)).is_not_null()
	var plus := CT.row_amounts(CT.cost_row({"gold": 30}, {}, "+"))
	assert_str(String(plus["gold"])).is_equal("+30")
	row.queue_free()

func test_the_campaign_track_marks_done_now_and_boss() -> void:
	var track := CT.campaign_track(2, 6, false, "jefe")
	var states: Array = []
	for child in track.get_children():
		if child.has_meta("state"):
			states.append(String(child.get_meta("state")))
	assert_array(states).is_equal(["done", "done", "now", "next", "next", "boss"])
	assert_str((track.get_child(track.get_child_count() - 1) as Control).tooltip_text).is_equal("jefe")
	track.free()
	# Con la campana en el jefe, el jefe es "la que toca".
	var at_boss := CT.campaign_track(5, 6, true)
	var last: Control = at_boss.get_child(at_boss.get_child_count() - 1)
	assert_str(String(last.get_meta("state"))).is_equal("boss")
	at_boss.free()

func test_the_odds_badge_is_named_for_the_ui() -> void:
	var b := CT.odds_badge("favorable", "Favorable")
	assert_str(String(b.name)).is_equal("OddsLabel")
	b.free()

func test_style_pill_keeps_the_button_text() -> void:
	var btn := Button.new()
	btn.text = "Defender"
	CT.style_pill(btn, "secondary", 48, "hud", "army")
	assert_str(btn.text).is_equal("Defender")
	assert_object(btn.get_node_or_null("PillGlyph")).is_not_null()
	# Se puede volver a vestir: el icono viejo se quita.
	CT.style_pill(btn, "warn", 48, "hud", "clock")
	var glyphs := 0
	for child in btn.get_children():
		if String(child.name).begins_with("PillGlyph") and not child.is_queued_for_deletion():
			glyphs += 1
	assert_int(glyphs).is_equal(1)
	btn.free()

func test_the_army_panel_has_one_tab_per_military_building() -> void:
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/ArmyPanel.tscn").instantiate())
	add_child(panel)
	await await_idle_frame()
	panel.open()
	for building_id in GameConfig.MILITARY_BUILDINGS:
		var domain := String(GameConfig.MILITARY_BUILDING_DOMAIN.get(building_id, "land"))
		assert_object(panel.find_child("ArmyTab_" + domain, true, false)).override_failure_message(domain).is_not_null()
	panel.select_tab("sea")
	assert_str(panel.current_tab()).is_equal("sea")
	panel._toggle_panel()
	assert_bool(panel.is_open()).is_false()

func test_the_missions_panel_says_attack_and_keeps_its_footer() -> void:
	var saved_first: bool = TutorialManager.first_sortie_done
	TutorialManager.first_sortie_done = true
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/SkirmishPanel.tscn").instantiate())
	add_child(panel)
	await await_idle_frame()
	panel.open()
	var shown := CT._army_first_label(panel._launch_btn)
	assert_str(shown.text).is_equal(Tr.t("ARMY2_BTN_ATTACK"))
	# La mision y la tropa, lado a lado, dentro del selector.
	assert_object(panel._sortie_box.find_child("SortieDetail", true, false)).is_not_null()
	assert_object(panel._sortie_box.find_child("TroopCard", true, false)).is_not_null()
	panel._close()
	TutorialManager.first_sortie_done = saved_first

func test_the_gate_checklist_names_what_is_missing() -> void:
	var saved_first: bool = TutorialManager.first_sortie_done
	TutorialManager.first_sortie_done = true
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/SkirmishPanel.tscn").instantiate())
	add_child(panel)
	await await_idle_frame()
	panel.open()
	var gate: Node = panel._sortie_box.find_child("AuditGateLine", true, false)
	var gate_text: String = preload("res://scripts/services/Objectives.gd").final_gate_text()
	if gate_text == "":
		assert_object(gate).is_null()
	else:
		assert_object(gate).is_not_null()
		assert_str((gate as Control).tooltip_text).is_equal(gate_text)
	panel._close()
	TutorialManager.first_sortie_done = saved_first

func test_the_wave_banner_hides_without_a_tween() -> void:
	var banner: CanvasLayer = auto_free(load("res://scenes/ui/AuditWaveBanner.tscn").instantiate())
	add_child(banner)
	await await_idle_frame()
	banner.show_wave(0, 3)
	assert_bool(banner.is_showing()).is_true()
	assert_str(banner.note_text()).is_equal(Tr.t("AUDIT_ATTRITION"))
	banner.hide_banner()
	assert_bool(banner.is_showing()).is_false()
	assert_bool(banner.get("_tween") == null).is_true()
