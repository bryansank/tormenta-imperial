extends GdUnitTestSuite
## Bug 11: "el HUD es bastante inentendible". Numeros sin nombre, una barra
## de almacen sin leyenda, "Trabajadores 0/5" ambiguo, "Zzz" sin explicar,
## CONSTRUIR escondido tras ☰ y avisos de hito y era pisandose.

const NotificationScript := preload("res://scripts/ui/NotificationPanel.gd")
const Badge := preload("res://scripts/buildings/BuildingStatusBadge.gd")

func _click() -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	return e

func test_every_resource_number_says_what_it_is() -> void:
	var hud: CanvasLayer = auto_free(load("res://scenes/ui/ResourceHUD.tscn").instantiate())
	add_child(hud)
	for res in ["gold", "wood", "steel", "oil"]:
		var chip: Control = hud.find_child("Chip_" + res, true, false)
		assert_object(chip).override_failure_message(res).is_not_null()
		assert_str(chip.tooltip_text).contains(Tr.res_cap(res))
		assert_int(chip.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)

func test_a_tap_on_a_resource_unfolds_the_names() -> void:
	var hud: CanvasLayer = auto_free(load("res://scenes/ui/ResourceHUD.tscn").instantiate())
	add_child(hud)
	var chip: Control = hud.find_child("Chip_gold", true, false)
	assert_bool(hud.is_expanded()).is_false()
	chip.gui_input.emit(_click())
	assert_bool(hud.is_expanded()).is_true()

func test_the_storage_bar_has_a_legend() -> void:
	var hud: CanvasLayer = auto_free(load("res://scenes/ui/ResourceHUD.tscn").instantiate())
	add_child(hud)
	var row: Control = hud.find_child("StorageRow", true, false)
	assert_str(row.tooltip_text).is_equal(Tr.t("HINT_HUD_STORAGE"))
	var labels: Array = row.find_children("*", "Label", true, false)
	assert_str((labels[0] as Label).text).is_equal(Tr.t("LBL_HUD_STORAGE"))
	assert_str((labels[1] as Label).text).contains("/")
	row.gui_input.emit(_click())
	var legend: Label = hud.find_child("StorageLegend", true, false)
	assert_bool(legend.is_visible_in_tree()).is_true()

func test_workers_and_morale_are_said_in_words() -> void:
	var w: String = NotificationScript.workers_text(3, 5)
	assert_str(w).is_equal(Tr.t("LBL_HUD_WORKERS") % [3, 2])
	assert_str(NotificationScript.workers_text(5, 3)).is_equal(Tr.t("LBL_HUD_WORKERS") % [5, 0])
	assert_str(NotificationScript.morale_text(100)).contains("1.2")
	assert_str(NotificationScript.morale_text(50)).contains("1.0")

func test_the_population_card_explains_itself_on_tap() -> void:
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/NotificationPanel.tscn").instantiate())
	add_child(panel)
	assert_bool(panel.is_status_hint_shown()).is_false()
	var hint: Label = panel.find_child("StatusHint", true, false)
	var row: Control = hint.get_parent().get_child(0)
	assert_str(row.tooltip_text).is_equal(Tr.t("HINT_HUD_POPULATION"))
	row.gui_input.emit(_click())
	assert_bool(panel.is_status_hint_shown()).is_true()

func test_zzz_says_why() -> void:
	assert_str(Badge.reason_text("unstaffed")).is_equal(Tr.t("LBL_STATUS_WHY_UNSTAFFED"))
	assert_str(Badge.reason_text("ruined")).is_equal(Tr.t("LBL_STATUS_WHY_RUINED"))
	assert_str(Badge.reason_text("idle")).is_equal(Tr.t("LBL_STATUS_IDLE_WHY"))
	for lang in ["es", "en"]:
		for key in ["LBL_STATUS_WHY_UNSTAFFED", "LBL_STATUS_IDLE_WHY", "LBL_HUD_STORAGE", "BTN_GAME_MENU"]:
			assert_bool(Tr._STRINGS[lang].has(key)).override_failure_message("%s/%s" % [lang, key]).is_true()

func test_build_is_always_on_screen() -> void:
	var menu: CanvasLayer = auto_free(load("res://scenes/ui/ConstructionMenu.tscn").instantiate())
	add_child(menu)
	var btn: Button = menu.build_button()
	assert_bool(btn.visible).is_true()
	# Ningun ☰ lo esconde ya.
	EventBus.sidebar_toggled.emit(false)
	assert_bool(btn.visible).is_true()
	assert_float(btn.custom_minimum_size.y).is_greater_equal(56.0)
	assert_float(btn.custom_minimum_size.x).is_greater_equal(200.0)

func test_milestone_and_era_toasts_queue_up() -> void:
	var progress: CanvasLayer = auto_free(load("res://scenes/ui/ProgressPanel.tscn").instantiate())
	add_child(progress)
	progress._show_toast("uno", UITheme.ACCENT)
	progress._show_toast("dos", UITheme.INFO)
	progress._show_toast("tres", UITheme.INFO)
	var on_screen := progress.find_children("MilestoneToast*", "PanelContainer", false, false).size()
	assert_int(on_screen).is_equal(1)
	assert_int(progress.pending_toasts()).is_equal(3)
