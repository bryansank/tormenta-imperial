extends GdUnitTestSuite
## La barra de abajo del rediseno (docs/28 §12, feat/ui2-hud): CONSTRUIR en el
## centro (de ConstructionMenu, la barra solo le deja el hueco) y a los lados
## Ejercito, Misiones, Mercado, Investigar y Ayuda. Mercado e Investigar abren
## su panel solo con su edificio terminado y con carretera; si no, gris con
## candado y el porque al mantener. Ejercito y Misiones piden un edificio que
## entrene tropa. Ayuda abre el indice de ayuda (grupo "help_index").
##
## No toca la partida ni el guardado: escena falsa con paneles de mentira.

const BarScript := preload("res://scripts/ui/BottomBar.gd")

var _root: Node
var _saved_phone := false

func before_test() -> void:
	_saved_phone = CartoonTheme.phone
	_root = Node.new()
	_root.name = "FakeMain"
	add_child(_root)

func after_test() -> void:
	CartoonTheme.phone = _saved_phone
	if is_instance_valid(_root):
		_root.free()
	UIManager.reset()

func _bar() -> CanvasLayer:
	var bar: CanvasLayer = load("res://scenes/ui/BottomBar.tscn").instantiate()
	bar.name = "BottomBar"
	_root.add_child(bar)
	return bar

## Un panel de mentira con open() / is_open().
func _stub(node_name: String, group: String = "") -> CanvasLayer:
	var script := GDScript.new()
	script.source_code = "extends CanvasLayer\nvar opened := 0\nvar _is_open := false\nfunc open():\n\topened += 1\n\t_is_open = true\nfunc toggle():\n\t_is_open = not _is_open\nfunc is_open() -> bool:\n\treturn _is_open\n"
	script.reload()
	var n := CanvasLayer.new()
	n.set_script(script)
	n.name = node_name
	if group != "":
		n.add_to_group(group)
	_root.add_child(n)
	return n

func test_the_bar_has_five_round_buttons_around_build() -> void:
	var bar := _bar()
	for id in ["army", "missions", "market", "research", "help"]:
		assert_object(bar.button(id)).override_failure_message(id).is_not_null()
		assert_bool(bar.button(id).is_in_group("hud_bar_" + id)).is_true()
	# Dos a la izquierda, tres a la derecha, el hueco de CONSTRUIR en medio.
	var dock: Control = bar.find_child("BarDock", true, false)
	assert_object(dock.find_child("BuildGap", false, false)).is_not_null()
	assert_int((dock.find_child("Left", false, false) as Control).get_child_count()).is_equal(2)
	assert_int((dock.find_child("Right", false, false) as Control).get_child_count()).is_equal(3)

func test_the_bar_has_its_own_slot_and_is_movable() -> void:
	assert_str(String(UILayoutConfig.PANEL_SLOTS.get("BottomBar", ""))).is_equal("bottom_bar")
	assert_bool(UILayoutConfig.SLOTS.has("bottom_bar")).is_true()
	assert_bool("BottomBar" in HudRegistry.movable_ids()).is_true()
	assert_bool("BottomBar" in HudRegistry.hideable_ids()).is_false()
	for key in ["HUD_BAR_ARMY", "HUD_BAR_MISSIONS", "HUD_BAR_MARKET", "HUD_BAR_RESEARCH",
			"HUD_BAR_HELP", "HUD_BAR_LOCK_ARMY", "HUD_BAR_LOCK_MARKET", "HUD_BAR_LOCK_LAB",
			"HUD_BAR_LOCK_ROAD", "HUD_BAR_LOCK_BUILDING", "HUD_BOTTOM_BAR"]:
		assert_str(Tr.t(key)).override_failure_message(key).is_not_equal(key)

func test_without_a_market_the_market_button_is_locked_with_its_reason() -> void:
	if GridManager.count_by_id("market") > 0:
		return
	var bar := _bar()
	bar.refresh()
	assert_bool(bar.is_open_for("market")).is_false()
	assert_str(bar.reason_for("market")).is_equal(Tr.t("HUD_BAR_LOCK_MARKET"))
	assert_bool(bar.button("market").disabled).is_true()
	assert_str(bar.button("market").tooltip_text).contains(Tr.t("HUD_BAR_LOCK_MARKET"))

func test_a_locked_button_opens_nothing() -> void:
	if GridManager.count_by_id("market") > 0:
		return
	var market := _stub("MarketPanel")
	var bar := _bar()
	bar.refresh()
	bar._on_pressed("market")
	assert_int(market.get("opened")).is_equal(0)

func test_army_and_missions_need_a_training_building() -> void:
	var bar := _bar()
	bar.refresh()
	var military: bool = ArmyManager.has_military_building()
	assert_bool(bar.is_open_for("army")).is_equal(military)
	assert_bool(bar.is_open_for("missions")).is_equal(military)
	if not military:
		assert_bool(bar.has_missions_dot()).is_false()

func test_help_opens_the_help_index() -> void:
	var help := _stub("HelpIndexPanel", "help_index")
	var bar := _bar()
	bar.refresh()
	assert_bool(bar.is_open_for("help")).is_true()
	bar.button("help").pressed.emit()
	assert_int(help.get("opened")).is_equal(1)

func test_help_is_locked_without_the_help_index() -> void:
	var bar := _bar()
	bar.refresh()
	assert_bool(bar.is_open_for("help")).is_false()

func test_the_old_skirmish_button_is_hidden() -> void:
	var old := CanvasLayer.new()
	old.name = "SkirmishButton"
	_root.add_child(old)
	_bar()
	await await_idle_frame()
	assert_bool(old.visible).is_false()

func test_captions_on_pc_and_icons_only_on_a_phone() -> void:
	CartoonTheme.phone = false
	assert_bool(BarScript.shows_captions()).is_true()
	CartoonTheme.phone = true
	assert_bool(BarScript.shows_captions()).is_false()
	var bar := _bar()
	# En telefono el redondo va solo (sin columna de nombre) y el nombre al mantener.
	var btn: Button = bar.button("army")
	assert_str(btn.tooltip_text).contains(Tr.t("HUD_BAR_ARMY"))
	assert_float(btn.custom_minimum_size.y).is_equal(float(CartoonTheme.bar_round()))
	assert_int(CartoonTheme.bar_round()).is_greater_equal(CartoonTheme.TOUCH_MIN)

func test_building_lock_reason_without_any_building() -> void:
	if GridManager.count_by_id("laboratory") > 0:
		return
	assert_str(BarScript.building_lock_reason("laboratory")).is_equal(Tr.t("HUD_BAR_LOCK_LAB"))
