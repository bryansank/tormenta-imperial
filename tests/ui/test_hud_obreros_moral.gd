extends GdUnitTestSuite
## Obreros y moral en la fila de recursos (2026-10). Bryan: "trabajadores que
## se vuelva un icono mas al lado de los recursos; 'en su puesto' y moral no me
## sirven; solo moral cuando empiecen las tormentas".
##
## - La ficha de obreros ensena los LIBRES y sigue a workers_changed; se pone
##   en alerta (UITheme.WARNING) si algun edificio se queda sin obreros.
## - La ficha de moral no esta antes de armar la Tormenta y si despues, tambien
##   tras cargar una partida.
## - La tarjeta de estado de NotificationPanel ya no existe, y un settings.cfg
##   que la nombra (oculta o movida) carga sin ella y sin error.
##
## Toca PopulationManager, StormManager, ProgressionManager y GameMode (autoloads
## y estatico): todo vuelve como estaba. settings.cfg se aparca byte a byte.

const SettingsParking := preload("res://tests/save/settings_parking.gd")
const HudScript := preload("res://scripts/ui/ResourceHUD.gd")
const HelpCatalog := preload("res://scripts/ui/HelpCatalog.gd")

var _pop := {}
var _storm: Dictionary = {}
var _progression: Dictionary = {}
var _mode := 0
var _parked: Dictionary = {}

func before_test() -> void:
	_pop = {
		"population": PopulationManager._population,
		"max": PopulationManager._max_population,
		"used": PopulationManager._used_workers,
		"short": PopulationManager._understaffed,
		"retired": PopulationManager._retired_workers,
		"morale": PopulationManager._morale,
	}
	_storm = StormManager.get_save_data()
	_progression = ProgressionManager.get_save_data()
	_mode = GameMode.current
	GameMode.current = GameMode.Mode.CAMPAIGN
	_parked = SettingsParking.park()

func after_test() -> void:
	PopulationManager._population = _pop["population"]
	PopulationManager._max_population = _pop["max"]
	PopulationManager._used_workers = _pop["used"]
	PopulationManager._understaffed = _pop["short"]
	PopulationManager._retired_workers = _pop["retired"]
	PopulationManager._morale = _pop["morale"]
	GameMode.current = _mode
	StormManager.load_save_data(_storm)
	ProgressionManager.load_save_data(_progression)
	SettingsParking.restore(_parked)

func _hud() -> CanvasLayer:
	var hud: CanvasLayer = auto_free(load("res://scenes/ui/ResourceHUD.tscn").instantiate())
	add_child(hud)
	return hud

func _storm_save(armed: bool) -> Dictionary:
	var data: Dictionary = StormCycle.create(3).to_dict()
	data["armed"] = armed
	data["halted"] = false
	data["on_demand"] = false
	return data

func _people(population: int, max_pop: int, used: int, short: int = 0) -> void:
	PopulationManager._population = population
	PopulationManager._max_population = max_pop
	PopulationManager._used_workers = used
	PopulationManager._understaffed = short
	EventBus.workers_changed.emit(used, population)

func _color_for(token: Color) -> Color:
	var probe: Label = auto_free(Label.new())
	UITheme.set_label_color(probe, token)
	return probe.get_theme_color("font_color")

# ── Obreros ──────────────────────────────────────────────────────────

func test_the_workers_icon_shows_the_free_workers_and_follows_the_signal() -> void:
	var hud := _hud()
	var chip: HBoxContainer = hud.workers_chip()
	assert_object(chip).is_not_null()
	assert_str(String(chip.name)).is_equal("Chip_workers")
	# En la misma fila que los recursos (cada ficha en su celda con su palabra,
	# feat/hud-y-tutorial).
	var row: Node = hud.find_child("ChipsRow", true, false)
	assert_bool(row.is_ancestor_of(chip)).is_true()
	assert_object(chip.get_parent().get_parent()).is_same(hud.find_child("Chip_gold", true, false).get_parent().get_parent())
	_people(12, 18, 9)
	assert_str(UITheme.chip_amount(chip).text).is_equal("3")
	_people(12, 18, 4)
	assert_str(UITheme.chip_amount(chip).text).is_equal("8")
	# El detalle va al tooltip: habitantes, tope y ocupados.
	assert_str(chip.tooltip_text).is_equal(Tr.t("HINT_HUD_WORKERS") % [8, 12, 18, 4])

func test_the_workers_number_turns_to_warning_when_a_building_lacks_workers() -> void:
	var hud := _hud()
	var amount: Label = UITheme.chip_amount(hud.workers_chip())
	_people(5, 6, 5, 0)
	assert_object(amount.get_theme_color("font_color")).is_equal(_color_for(UITheme.TEXT_BRIGHT))
	_people(5, 6, 5, 1)
	assert_object(amount.get_theme_color("font_color")).is_equal(_color_for(UITheme.WARNING))
	assert_str(hud.workers_chip().tooltip_text).contains(Tr.t("HINT_HUD_WORKERS_SHORT") % 1)

func test_population_counts_buildings_left_without_workers() -> void:
	# El recuento real: sin edificios en la rejilla del test no hay ninguno
	# parado; el contador existe y reset() lo pone a cero.
	PopulationManager._understaffed = 4
	PopulationManager._retired_workers = 2
	PopulationManager.reset()
	assert_int(PopulationManager.get_understaffed_count()).is_equal(0)
	assert_int(PopulationManager.get_retired_workers()).is_equal(0)

func test_a_tap_on_the_workers_icon_unfolds_the_words() -> void:
	var hud := _hud()
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	hud.workers_chip().gui_input.emit(ev)
	assert_bool(hud.is_expanded()).is_true()
	var detail: Label = hud.find_child("WorkersDetail", true, false)
	assert_bool(detail.is_visible_in_tree()).is_true()
	assert_str(detail.text).is_equal(hud.workers_chip().tooltip_text)

# ── Moral ────────────────────────────────────────────────────────────

func test_morale_is_hidden_before_the_storm_is_armed_and_shown_after() -> void:
	StormManager.load_save_data(_storm_save(false))
	ProgressionManager.current_phase = GameConfig.Phase.SETTLEMENT
	var hud := _hud()
	assert_bool(HudScript.morale_visible()).is_false()
	assert_bool(hud.morale_chip().visible).is_false()
	# La fase que arma la Tormenta: StormManager se arma con la senal y la
	# ficha aparece en diferido.
	ProgressionManager.current_phase = GameConfig.storm_arm_phase
	EventBus.phase_advanced.emit(GameConfig.storm_arm_phase)
	await await_idle_frame()
	assert_bool(StormManager.is_armed()).is_true()
	assert_bool(hud.morale_chip().visible).is_true()

func test_morale_shows_its_number_with_the_threshold_colour() -> void:
	StormManager.load_save_data(_storm_save(true))
	var hud := _hud()
	var amount: Label = UITheme.chip_amount(hud.morale_chip())
	for case in [[80, UITheme.POSITIVE], [45, UITheme.WARNING], [20, UITheme.DANGER]]:
		PopulationManager._morale = int(case[0])
		EventBus.morale_changed.emit(int(case[0]))
		assert_str(amount.text).is_equal(str(case[0]))
		assert_object(amount.get_theme_color("font_color")).is_equal(_color_for(case[1]))
	assert_str(hud.morale_chip().tooltip_text).contains("x")

func test_morale_is_rederived_after_loading_a_game() -> void:
	ProgressionManager.current_phase = GameConfig.Phase.SETTLEMENT
	StormManager.load_save_data(_storm_save(false))
	var hud := _hud()
	assert_bool(hud.morale_chip().visible).is_false()
	# Se carga una partida con la Tormenta armada.
	StormManager.load_save_data(_storm_save(true))
	EventBus.game_load_completed.emit()
	await await_idle_frame()
	assert_bool(hud.morale_chip().visible).is_true()
	# Y otra sin armar (una partida nueva cargada encima): se vuelve a ocultar.
	StormManager.load_save_data(_storm_save(false))
	EventBus.game_load_completed.emit()
	await await_idle_frame()
	assert_bool(hud.morale_chip().visible).is_false()

func test_builder_mode_never_shows_morale() -> void:
	# Sin Tormenta en Constructor: armada o no, no corre, y la moral no sale.
	GameMode.current = GameMode.Mode.BUILDER
	StormManager.load_save_data(_storm_save(true))
	var hud := _hud()
	assert_bool(hud.morale_chip().visible).is_false()

# ── La tarjeta vieja ─────────────────────────────────────────────────

func test_the_old_status_card_is_gone() -> void:
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/NotificationPanel.tscn").instantiate())
	add_child(panel)
	assert_object(panel.find_child("StatusHint", true, false)).is_null()
	assert_bool("_status_panel" in panel).is_false()
	assert_bool(HudRegistry.ELEMENTS.has("NotificationPanel.status")).is_false()
	assert_bool(UILayoutConfig.PANEL_SLOTS.has("NotificationPanel.status")).is_false()
	assert_bool(UILayoutConfig.SLOTS.has("status_bar")).is_false()
	# La ayuda de "la gente come" senala ahora el icono de obreros.
	assert_str(String(HelpCatalog.ENTRIES["consumption"]["target"])).is_equal("workers")
	for slot_name in UILayoutConfig.SLOTS:
		assert_str(String(UILayoutConfig.SLOTS[slot_name].get("stack_after", ""))).is_not_equal("NotificationPanel.status")
	for slot_name in UILayoutConfig.NARROW_SLOTS:
		assert_str(String(UILayoutConfig.NARROW_SLOTS[slot_name].get("stack_after", ""))).is_not_equal("NotificationPanel.status")

func test_an_old_settings_file_that_names_the_card_loads_without_it() -> void:
	var cf := ConfigFile.new()
	cf.set_value("interfaz", "hud_hidden", ["NotificationPanel.status", "StormHUD"])
	cf.set_value("interfaz", "layout", {
		"pc|16:9": {"NotificationPanel.status": [40, 80], "StormHUD": [8, 8]},
		"tablet|4:3": {"NotificationPanel.status": [0, 120]},
	})
	assert_int(cf.save(GameConfig.USER_SETTINGS_PATH)).is_equal(OK)
	GameConfig.load_user_settings()
	assert_array(GameConfig.ui_hud_hidden).is_equal(["StormHUD"])
	assert_bool(GameConfig.ui_layout.has("pc|16:9")).is_true()
	assert_bool((GameConfig.ui_layout["pc|16:9"] as Dictionary).has("NotificationPanel.status")).is_false()
	assert_bool(GameConfig.ui_layout.has("tablet|4:3")).is_false()
	# Y el registro sigue funcionando con lo que quedo.
	assert_bool(HudRegistry.is_hidden("StormHUD")).is_true()
	assert_bool(HudRegistry.is_hidden("NotificationPanel.status")).is_false()
