extends GdUnitTestSuite
## La insignia del rango, su aviso al subir, la tarjeta de COLONIA (☰ MENU), el
## candado de CONSTRUIR y el color de la colonia en las fichas propias.

const ConstructionMenuScript := preload("res://scripts/ui/ConstructionMenu.gd")
const ColonyFlag3D := preload("res://scripts/buildings/ColonyFlag3D.gd")
const ColonyFlag2D := preload("res://scripts/view2d/ColonyFlag2D.gd")

var _rank_saved: Dictionary = {}
var _mode_saved: Dictionary = {}

func before_test() -> void:
	_rank_saved = RankManager.get_save_data()
	_mode_saved = GameMode.get_save_data()
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	RankManager.reset()

func after_test() -> void:
	UIManager.close_all_windows()
	CombatManager.reset()
	GameMode.load_save_data(_mode_saved)
	RankManager.reset()
	RankManager.load_save_data(_rank_saved)

func _panel() -> CanvasLayer:
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/RankPanel.tscn").instantiate())
	add_child(panel)
	return panel

func test_the_badge_shows_the_number_country_name_and_xp_bar() -> void:
	var panel := _panel()
	await await_idle_frame()
	var badge: Button = panel.badge()
	var number: Label = badge.find_child("RankNumber", true, false)
	var bar: ProgressBar = badge.find_child("RankXpBar", true, false)
	assert_str(number.text).is_equal("1")
	var t: Array = GameConfig.rank_xp_thresholds
	RankManager.add_xp((int(t[2]) + int(t[3])) / 2)
	assert_str(number.text).is_equal("3")
	assert_float(bar.value).is_between(0.3, 0.7)
	var colony: Label = badge.find_child("ColonyName", true, false)
	assert_str(colony.text).is_equal(RankManager.get_colony_name())
	# El titulo del rango sigue a mano, en el tooltip.
	assert_str(badge.tooltip_text).contains(Tr.t(GameConfig.rank_title_key(3)))

func test_the_badge_has_its_own_slot_and_is_registered() -> void:
	assert_str(String(UILayoutConfig.PANEL_SLOTS.get("RankPanel", ""))).is_equal("rank_badge")
	assert_bool(UILayoutConfig.SLOTS.has("rank_badge")).is_true()
	assert_bool(HudRegistry.ELEMENTS.has("RankPanel")).is_true()
	assert_bool("RankPanel" in HudRegistry.ORDER).is_true()

func test_ranking_up_shows_a_short_toast_with_what_it_opened() -> void:
	var panel := _panel()
	await await_idle_frame()
	RankManager.add_xp(RankManager.xp_for_rank(2))
	var toast: PanelContainer = panel.toast()
	assert_object(toast).is_not_null()
	var title: Label = toast.find_child("RankToastTitle", true, false)
	assert_str(title.text).contains("2")
	# Lo desbloqueado (el jardin), en una linea corta.
	var garden: BuildingData = load("res://data/buildings/garden.tres")
	var texts: Array = []
	for label in toast.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	assert_bool(texts.any(func(s): return String(s).contains(garden.get_display_name()))).is_true()

func test_the_colony_card_opens_the_editor_and_locks_what_is_not_earned() -> void:
	var panel := _panel()
	await await_idle_frame()
	panel.open()
	assert_bool(panel.is_open()).is_true()
	var card: PanelContainer = panel.card()
	assert_str((card.find_child("ColonyName", true, false) as Label).text).is_equal(RankManager.get_colony_name())
	(card.find_child("EditColony", true, false) as Button).pressed.emit()
	await await_idle_frame()
	var editor: CanvasLayer = panel.editor()
	assert_object(editor).is_not_null()
	assert_str(editor.get_mode()).is_equal("edit")
	var locked: Button = editor.find_child("Piece_checks", true, false)
	var open_one: Button = editor.find_child("Piece_bands_h", true, false)
	assert_bool(locked.disabled).is_true()
	assert_object(locked.find_child("RankLock", true, false)).is_not_null()
	assert_bool(open_one.disabled).is_false()
	editor.select_tab("colors")
	var locked_color: Button = editor.find_child("Color_0_gold", true, false)
	assert_bool(locked_color.disabled).is_true()
	# Elegir uno libre y LISTO lo aplica en RankManager.
	(editor.find_child("Color_0_crimson", true, false) as Button).pressed.emit()
	assert_bool(editor.confirm()).is_true()
	assert_str(RankManager.get_color_id()).is_equal("crimson")
	panel._close()
	assert_bool(panel.is_open()).is_false()

func test_the_pause_menu_lists_the_colony_entry() -> void:
	var found := false
	for entry in load("res://scripts/ui/PauseMenu.gd").COLONY_ENTRIES:
		if entry[2] == "RankPanel":
			found = true
	assert_bool(found).is_true()

func test_the_build_card_lock_reads_rank_n() -> void:
	var row: HBoxContainer = auto_free(ConstructionMenuScript.make_rank_lock_row(5))
	var label: Label = row.find_child("RankLockLabel", true, false)
	assert_str(label.text).is_equal(Tr.t("LBL_RANK_LOCK") % 5)
	# Corto: "Rango N", tres palabras como mucho.
	assert_int(label.text.split(" ", false).size()).is_less_equal(3)

func test_the_core_flag_follows_the_chosen_cosmetics_in_3d_and_2d() -> void:
	var flag3d: Node3D = auto_free(ColonyFlag3D.new())
	add_child(flag3d)
	flag3d.setup(Vector2(6, 6), 6.5)
	var flag2d: Node2D = auto_free(ColonyFlag2D.new())
	add_child(flag2d)
	flag2d.setup(Vector2(96, 96))
	var before: Texture2D = flag3d.flag_texture()
	var before_2d: String = flag2d.flag_spec_key()
	var spec := RankManager.get_flag_spec()
	spec["colors"][0] = "soot" if spec["colors"][0] != "soot" else "crimson"
	assert_bool(RankManager.set_colony(RankManager.get_colony_name(), spec)).is_true()
	assert_object(flag3d.flag_texture()).is_not_same(before)
	assert_str(flag2d.flag_spec_key()).is_not_equal(before_2d)

func test_own_board_tokens_wear_the_colony_colour() -> void:
	var spec := RankManager.get_flag_spec()
	spec["colors"][0] = "crimson"
	RankManager.set_colony(RankManager.get_colony_name(), spec)
	var screen: CanvasLayer = auto_free(load("res://scenes/ui/BattleScreen.tscn").instantiate())
	add_child(screen)
	screen._recalculate_cell_size()
	screen._build_grid()
	await await_idle_frame()
	var mark: Panel = screen.board_cell_mark(Vector2i(0, 0))
	screen._paint_side_mark(mark, CombatUnit.create(1, "infantry", 0, 1.0))
	var style: StyleBoxFlat = mark.get_theme_stylebox("panel")
	assert_bool(style.bg_color == GameConfig.colony_colors["crimson"]).is_true()
	assert_str(String(mark.get_meta("colony_color", ""))).is_equal("crimson")
	# El enemigo no lleva nuestro color.
	screen._paint_side_mark(mark, CombatUnit.create(2, "infantry", 1, 1.0))
	style = mark.get_theme_stylebox("panel")
	assert_bool(style.bg_color == GameConfig.colony_colors["crimson"]).is_false()

func test_the_3d_flag_hangs_from_the_model_flag_anchor_when_there_is_one() -> void:
	var building: Node3D = auto_free(Node3D.new())
	add_child(building)
	var model := Node3D.new()
	model.name = "Model"
	building.add_child(model)
	var marker := Marker3D.new()
	marker.name = "FlagAnchor"
	marker.position = Vector3(1.0, 5.0, -0.5)
	model.add_child(marker)
	var flag: Node3D = ColonyFlag3D.new()
	building.add_child(flag)
	flag.setup(Vector2(4, 4), 3.0, building, true)
	assert_bool(flag.is_anchored()).is_true()
	assert_vector(flag.position).is_equal_approx(Vector3(1.0, 5.0, -0.5), Vector3.ONE * 0.001)
	assert_bool((flag.get_node("Pole") as Node3D).visible).is_false()
	# Sin marcador: el mastil propio, en su esquina.
	var bare: Node3D = auto_free(Node3D.new())
	add_child(bare)
	bare.add_child(Node3D.new())
	var flag2: Node3D = ColonyFlag3D.new()
	bare.add_child(flag2)
	flag2.setup(Vector2(4, 4), 3.0, bare)
	assert_bool(flag2.is_anchored()).is_false()
	assert_bool((flag2.get_node("Pole") as Node3D).visible).is_true()
