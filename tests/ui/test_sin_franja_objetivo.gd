extends GdUnitTestSuite
## La franja de objetivo del HUD ("Avanza hacia la Victoria Imperial. Construye
## el Cuartel General y mejoralo.") se quito el 2026-10-05: repetia, peor, lo que
## dice ¿QUE HACER? (Objectives.next_step), que es el unico sitio del siguiente
## paso. Como la tarjeta de estado antes que ella:
##
## - ya no existe en NotificationPanel, ni en HudRegistry, ni tiene slot;
## - un settings.cfg viejo que la oculta o la mueve carga sin ella y sin error;
## - las ayudas que la senalaban senalan ¿QUE HACER? (su entrada del menu ☰ o,
##   con el menu cerrado, el boton ☰ MENU), y no dicen "el objetivo de arriba".
##
## settings.cfg se aparca byte a byte (SettingsParking).

const SettingsParking := preload("res://tests/save/settings_parking.gd")
const HelpTargets := preload("res://scripts/ui/HelpTargets.gd")
const HelperPanelScript := preload("res://scripts/ui/HelperPanel.gd")

var _parked: Dictionary = {}

func before_test() -> void:
	_parked = SettingsParking.park()

func after_test() -> void:
	SettingsParking.restore(_parked)

func test_the_strip_is_gone() -> void:
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/NotificationPanel.tscn").instantiate())
	add_child(panel)
	assert_bool("_objective_label" in panel).is_false()
	assert_object(panel.find_child("Hud_NotificationPanel_objective", true, false)).is_null()
	assert_bool(HudRegistry.ELEMENTS.has("NotificationPanel.objective")).is_false()
	assert_bool(HudRegistry.ORDER.has("NotificationPanel.objective")).is_false()
	assert_bool(HudRegistry.RETIRED.has("NotificationPanel.objective")).is_true()
	assert_bool(UILayoutConfig.PANEL_SLOTS.has("NotificationPanel.objective")).is_false()
	assert_object(HudRegistry.control_of("NotificationPanel.objective")).is_null()

func test_an_old_settings_file_that_names_the_strip_loads_without_it() -> void:
	var cf := ConfigFile.new()
	cf.set_value("interfaz", "hud_hidden", ["NotificationPanel.objective", "StormHUD"])
	cf.set_value("interfaz", "layout", {
		"pc|16:9": {"NotificationPanel.objective": [0, 520], "StormHUD": [8, 8]},
		"tablet|4:3": {"NotificationPanel.objective": [0, 120]},
	})
	assert_int(cf.save(GameConfig.USER_SETTINGS_PATH)).is_equal(OK)
	GameConfig.load_user_settings()
	assert_array(GameConfig.ui_hud_hidden).is_equal(["StormHUD"])
	assert_bool((GameConfig.ui_layout["pc|16:9"] as Dictionary).has("NotificationPanel.objective")).is_false()
	assert_bool(GameConfig.ui_layout.has("tablet|4:3")).is_false()
	assert_bool(HudRegistry.is_hidden("StormHUD")).is_true()
	# Ajustes > Interfaz no la lista: no se puede ocultar lo que no existe.
	assert_bool(HudRegistry.hideable_ids().has("NotificationPanel.objective")).is_false()

func test_the_objective_help_points_at_what_to_do() -> void:
	# Sin menu en la escena, el boton del grupo "hud_menu_button".
	var btn := Button.new()
	btn.text = "☰ MENÚ"
	btn.add_to_group(HelpTargets.MENU_GROUP)
	var layer: CanvasLayer = auto_free(CanvasLayer.new())
	add_child(layer)
	layer.add_child(btn)
	await await_idle_frame()
	assert_object(HelpTargets.control(get_tree(), "objective")).is_same(btn)
	# El globo sale junto al menu, no bajo una franja que ya no existe.
	var slot_id: String = HelperPanelScript.CALLOUT_SLOTS["callout_objective"]
	assert_str(String(UILayoutConfig.PANEL_SLOTS[slot_id])).is_equal("tip_top_right")

func test_no_help_text_talks_about_the_objective_up_top() -> void:
	for locale in Tr.LOCALES:
		var table: Dictionary = Tr._STRINGS[locale]
		assert_str(String(table["GUIDE_DONE"])).contains(String(table["BTN_OBJECTIVES"]))
		assert_str(String(table["HELP_T_OBJECTIVE"])).is_equal(String(table["BTN_OBJECTIVES"]))
		assert_bool(table.has("HUD_OBJECTIVE")).is_false()
		assert_bool(table.has("OBJ_PHASE_4")).is_false()
	assert_str(Tr._STRINGS["es"]["GUIDE_DONE"]).not_contains("de arriba")
	assert_str(Tr._STRINGS["en"]["GUIDE_DONE"]).not_contains("up top")
