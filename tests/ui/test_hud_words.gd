extends GdUnitTestSuite
## Bug 11: "el HUD es bastante inentendible". Numeros sin nombre, una barra
## de almacen sin leyenda, "Trabajadores 0/5" ambiguo, "Zzz" sin explicar,
## CONSTRUIR escondido tras ☰ y avisos de hito y era pisandose.

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

## Sin rotulo "ALMACEN COMPARTIDO" (2026-10): la barra y "usado/tope" en una
## linea; lo que es, en el tooltip y, con un toque, en el detalle.
func test_the_storage_bar_explains_itself_without_a_fixed_title() -> void:
	var hud: CanvasLayer = auto_free(load("res://scenes/ui/ResourceHUD.tscn").instantiate())
	add_child(hud)
	var row: Control = hud.find_child("StorageRow", true, false)
	# Con el estilo maqueta la cifra va delante, en la misma ayuda emergente.
	assert_str(row.tooltip_text).ends_with(Tr.t("HINT_HUD_STORAGE"))
	var labels: Array = row.find_children("*", "Label", true, false)
	assert_int(labels.size()).is_equal(1)
	assert_str((labels[0] as Label).text).contains("/")
	row.gui_input.emit(_click())
	var legend: Label = hud.find_child("StorageLegend", true, false)
	assert_bool(legend.is_visible_in_tree()).is_true()

## Con "Nombres junto a los iconos" en Nunca: solo iconos y numeros en la fila.
## (Con Siempre, o en "auto" para un jugador nuevo, van las palabras debajo:
## tests/ui/test_hud_y_tutorial.gd.)
func test_the_chip_row_has_no_words() -> void:
	var saved := GameConfig.ui_hud_words
	GameConfig.ui_hud_words = "never"
	var hud: CanvasLayer = auto_free(load("res://scenes/ui/ResourceHUD.tscn").instantiate())
	add_child(hud)
	var row: Control = hud.find_child("ChipsRow", true, false)
	GameConfig.ui_hud_words = saved
	for node in row.find_children("*", "Label", true, false):
		var text := (node as Label).text
		if (node as Label).is_visible_in_tree() and text != "":
			assert_bool(text.is_valid_int()).override_failure_message("texto en la fila: '%s'" % text).is_true()

func test_zzz_says_why() -> void:
	assert_str(Badge.reason_text("unstaffed")).is_equal(Tr.t("LBL_STATUS_WHY_UNSTAFFED"))
	assert_str(Badge.reason_text("ruined")).is_equal(Tr.t("LBL_STATUS_WHY_RUINED"))
	assert_str(Badge.reason_text("idle")).is_equal(Tr.t("LBL_STATUS_IDLE_WHY"))
	for lang in ["es", "en"]:
		for key in ["LBL_STATUS_WHY_UNSTAFFED", "LBL_STATUS_IDLE_WHY", "HINT_HUD_STORAGE", "BTN_GAME_MENU"]:
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

## Hitos y eras ya no pintan placa propia: van a la columna de avisos como
## "achievement" (NotificationPanel, 2026-10-18) y alli hacen cola.
func test_milestone_and_era_toasts_queue_up() -> void:
	var progress: CanvasLayer = auto_free(load("res://scenes/ui/ProgressPanel.tscn").instantiate())
	add_child(progress)
	var notes: CanvasLayer = auto_free(load("res://scenes/ui/NotificationPanel.tscn").instantiate())
	add_child(notes)
	await await_idle_frame()
	progress._show_toast("uno", UITheme.ACCENT)
	progress._show_toast("dos", UITheme.INFO)
	progress._show_toast("tres", UITheme.INFO)
	assert_int(progress.find_children("MilestoneToast*", "PanelContainer", true, false).size()).is_equal(0)
	assert_int(notes.shown_toasts().size()).is_less_equal(notes.MAX_TOASTS)
	assert_int(notes.shown_toasts().size() + notes.held_count()).is_equal(3)
