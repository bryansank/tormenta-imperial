extends GdUnitTestSuite
## Menos texto en el menu, los partes de guerra, los avisos, los globos de ayuda
## y la barra del tablero (2026-10-04). Lo que se movio sigue a mano (tooltip) y
## lo que decide sigue a la vista.

const WarReport := preload("res://scripts/ui/WarReportScreen.gd")
const HelpCatalog := preload("res://scripts/ui/HelpCatalog.gd")

var _mode_saved: int = 0

func before_test() -> void:
	_mode_saved = GameMode.current

func after_test() -> void:
	GameMode.current = _mode_saved
	if not UITheme.is_cartoon():
		UITheme.use_style(UITheme.STYLE_DEFAULT, "mixed", CartoonTheme.DEFAULT_COMBO)
		UITheme.configure()

func _words(text: String) -> int:
	return text.split(" ", false).size()

# ── ☰ MENU ──

func test_the_menu_groups_keep_their_sentence_in_the_tooltip() -> void:
	# Los grupos COLONIA / PARTIDA son del menu clasico (respaldo interno): el
	# ☰ del rediseno no los tiene (Encargos, Progreso... van en la tarjeta de la
	# colonia). Se comprueba el clasico.
	UITheme.use_style("classic")
	var menu: CanvasLayer = auto_free(load("res://scenes/ui/PauseMenu.tscn").instantiate())
	add_child(menu)
	GameMode.current = GameMode.Mode.CAMPAIGN
	menu.open_pause()
	var colony: Label = menu.find_child("ColonyGroup", true, false).find_child("Header", true, false)
	var game: Label = menu.find_child("GameGroup", true, false).find_child("Header", true, false)
	assert_str(colony.tooltip_text).is_equal(Tr.t("LBL_MENU_GROUP_COLONY_HINT"))
	assert_str(game.tooltip_text).is_equal(Tr.t("LBL_PAUSE_SUBTITLE"))
	# Ninguna etiqueta visible repite la frase.
	for label in menu.find_children("*", "Label", true, false):
		assert_str((label as Label).text).is_not_equal(Tr.t("LBL_PAUSE_SUBTITLE"))
	# "Modo: Campana" no se ensena: es el unico modo que se juega.
	assert_bool((menu.find_child("ModeLabel", true, false) as Label).visible).is_false()
	menu.resume()
	UITheme.use_style(UITheme.STYLE_DEFAULT, "mixed", CartoonTheme.DEFAULT_COMBO)
	UITheme.configure()

func test_another_mode_is_still_named() -> void:
	var menu: CanvasLayer = auto_free(load("res://scenes/ui/PauseMenu.tscn").instantiate())
	add_child(menu)
	GameMode.current = GameMode.Mode.BUILDER
	menu.open_pause()
	var label: Label = menu.find_child("ModeLabel", true, false)
	assert_bool(label.visible).is_true()
	assert_str(label.text).contains(GameMode.display_name())
	menu.resume()

# ── Partes de guerra ──

func test_a_repelled_tithe_says_it_in_a_few_words() -> void:
	var lines: Array = WarReport.tithe_lines(true, {})
	assert_int(lines.size()).is_equal(1)
	assert_int(_words(String(lines[0]))).is_less_equal(5)

func test_a_collected_tithe_still_lists_what_was_taken() -> void:
	var text := "\n".join(WarReport.tithe_lines(false, {"gold": 120, "buildings": 1, "workers": 2}))
	assert_str(text).contains("120 " + Tr.res_name("gold"))
	assert_str(text).contains(Tr.t("LBL_TITHE_SEIZED_N") % 1)
	assert_str(text).contains(Tr.t("LBL_TITHE_WORKERS_N") % 2)

func test_report_lines_are_short() -> void:
	for key in ["LBL_REPORT_DEFENSE_KICKER", "LBL_REPORT_TOWER_CREWS", "LBL_TITHE_SEIZED_N",
			"LBL_TITHE_WORKERS_N", "LBL_TITHE_NOTHING", "LBL_TITHE_NOTHING_TAKEN"]:
		for locale in ["es", "en"]:
			assert_int(_words(String(Tr._STRINGS[locale][key]))).override_failure_message(
				"%s/%s" % [locale, key]).is_less_equal(7)

# ── Avisos (toasts) ──

func test_warning_toasts_read_in_one_glance() -> void:
	for key in ["NOTIF_NO_WOOD", "NOTIF_NO_GOLD", "NOTIF_LOW_MORALE", "NOTIF_STORAGE_TRIMMED",
			"NOTIF_UPKEEP_UNPAID", "STORM_ASH_QUEUE_WARNING", "STORM_ASH_QUEUE_WARNING_FREE",
			"STORM_ASH_TRAINING_WARNING", "STORM_TITHE_RESUMED", "STORM_TITHE_TOWER_CREWS",
			"STORM_TITHE_DURING_AUDIT", "MSG_AUDIT_AWAITING"]:
		for locale in ["es", "en"]:
			assert_int(_words(String(Tr._STRINGS[locale][key]))).override_failure_message(
				"%s/%s" % [locale, key]).is_less_equal(10)

# ── Globos de ayuda ──

func test_callouts_are_one_short_sentence_or_two() -> void:
	for id in HelpCatalog.ENTRIES:
		if HelpCatalog.kind(id) != "callout":
			continue
		var key := String(HelpCatalog.entry(id)["body"])
		for locale in ["es", "en"]:
			var table: Dictionary = Tr._STRINGS[locale]
			for k in [key, key + "_TOUCH"]:
				if table.has(k):
					assert_int(_words(String(table[k]))).override_failure_message(
						"%s/%s" % [locale, k]).is_less_equal(14)

# ── Tablero ──

func test_the_turn_sits_in_the_board_header() -> void:
	var screen: CanvasLayer = auto_free(load("res://scenes/ui/BattleScreen.tscn").instantiate())
	add_child(screen)
	await await_idle_frame()
	var header: Node = screen.find_child("BoardHeader", true, false)
	assert_object(header).is_not_null()
	assert_object(screen._turn_label.get_parent()).is_same(header)
	assert_object(screen._round_label.get_parent()).is_same(header)

func test_map_hints_are_short() -> void:
	for key in ["LBL_NODE_PICK_TOUCH", "LBL_NODE_PICK_MOUSE"]:
		for locale in ["es", "en"]:
			assert_int(_words(String(Tr._STRINGS[locale][key]))).is_less_equal(9)
