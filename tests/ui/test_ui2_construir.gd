extends GdUnitTestSuite
## Rediseno de la interfaz, fase 2 (docs/28-guia-ui.md): CONSTRUIR, la ficha
## del edificio, el Mercado e Investigar con CartoonTheme. Lo que se vigila:
## filas de una linea con el coste en fichas (en rojo lo que falta), el porque
## corto de lo bloqueado, los botones por intencion con los ganchos del
## tutorial, y textos en los dos idiomas.
## Escrito sin ejecutar (regla del dueno: un solo pase de pruebas al final).

const MenuScript := preload("res://scripts/ui/ConstructionMenu.gd")
const TechScript := preload("res://scripts/ui/TechTreePanel.gd")
const CT := preload("res://scripts/ui/CartoonTheme.gd")
const TextKit := preload("res://scripts/ui/TextKit.gd")
const Rules := preload("res://scripts/buildings/PlacementRules.gd")

var _amounts_before: Dictionary = {}

func before_test() -> void:
	_amounts_before = {}
	var all: Dictionary = ResourceManager.get_all()
	for type in all:
		_amounts_before[ResourceManager.get_type_name(type)] = int(all[type])

func after_test() -> void:
	ResourceManager.set_amounts(_amounts_before)

func _data(id: String) -> BuildingData:
	return load("res://data/buildings/%s.tres" % id)

# ── Piezas de CartoonTheme ──

func test_a_cost_strip_reads_like_a_textkit_row_and_marks_what_is_missing() -> void:
	var row := CT.cost_strip({"gold": 50, "wood": 30, "beams": 4}, {"wood": 12})
	var shown := TextKit.row_amounts(row)
	assert_str(String(shown["gold"])).is_equal("50")
	assert_str(String(shown["wood"])).is_equal("30")
	assert_str(String(shown["beams"])).contains(Tr.res_name("beams"))
	var wood: Label = row.find_child("Amount_wood", true, false)
	assert_that(wood.get_theme_color("font_color")).is_equal(CT.danger_text())
	var gold: Label = row.find_child("Amount_gold", true, false)
	assert_that(gold.get_theme_color("font_color")).is_not_equal(CT.danger_text())
	row.free()

func test_a_cost_strip_is_not_rebuilt_when_nothing_changed() -> void:
	var row := CT.cost_strip({"gold": 5})
	var chip := row.get_child(0)
	CT.fill_cost_strip(row, {"gold": 5})
	assert_object(row.get_child(0)).is_same(chip)
	row.free()

func test_phone_canvas_is_the_short_one() -> void:
	var saved := CT.phone
	CT.phone = false
	assert_bool(CT.is_phone(Vector2(640, 360))).is_true()
	assert_bool(CT.is_phone(Vector2(800, 360))).is_true()
	assert_bool(CT.is_phone(Vector2(1280, 720))).is_false()
	CT.phone = saved

func test_text_pills_keep_their_text_and_finger_size() -> void:
	var b := CT.text_pill("COMPRAR", "primary", 48)
	assert_str(b.text).is_equal("COMPRAR")
	assert_float(b.custom_minimum_size.y).is_greater_equal(48.0)
	b.free()

# ── CONSTRUIR ──

func test_one_sentence_at_most() -> void:
	assert_str(MenuScript.first_sentence("Corta madera. Casi todo se hace con madera.")).is_equal("Corta madera.")
	assert_str(MenuScript.first_sentence("Sin punto")).is_equal("Sin punto")

func test_the_row_tooltip_carries_the_description() -> void:
	var house := _data("house")
	assert_str(MenuScript.row_tooltip(house)).contains(house.get_description())

func test_a_free_building_has_no_lock_reason() -> void:
	# La Casa es de la era 1 y no pide nada antes.
	if not Rules.check_rank("house"):
		return
	assert_str(MenuScript.lock_reason(_data("house"))).is_empty()

func test_rows_are_one_line_with_a_hammer_or_a_lock() -> void:
	var menu: CanvasLayer = auto_free(load("res://scenes/ui/ConstructionMenu.tscn").instantiate())
	add_child(menu)
	await await_idle_frame()
	menu.call("_open")
	for card in menu._grid_container.get_children():
		var id := String(card.get_meta("building_id", ""))
		var locked: bool = bool(card.get_meta("locked", false))
		var hammer: Control = card.find_child("RowBuild", true, false)
		if locked:
			assert_object(hammer).override_failure_message("%s bloqueado con martillo" % id).is_null()
			var why: Label = card.find_child("*LockLabel", true, false)
			assert_object(why).is_not_null()
			assert_int(why.text.split(" ", false).size()).is_less_equal(4)
		else:
			assert_object(hammer).override_failure_message("%s sin martillo" % id).is_not_null()
			assert_object(card.find_child("CardCost", true, false)).is_not_null()
	menu.call("_close")

func test_the_hammer_starts_placing_what_can_be_paid() -> void:
	ResourceManager.set_amounts({"gold": 9999, "wood": 9999})
	var menu: CanvasLayer = auto_free(load("res://scenes/ui/ConstructionMenu.tscn").instantiate())
	add_child(menu)
	await await_idle_frame()
	menu.call("_open")
	var card: Control = menu.card_for("road")
	if card == null:
		menu.call("_close")
		return
	var hammer: Button = card.find_child("RowBuild", true, false)
	var picked: Array = []
	var cb := func(d): picked.append(d)
	EventBus.building_selected_for_placement.connect(cb)
	hammer.pressed.emit()
	EventBus.building_selected_for_placement.disconnect(cb)
	assert_int(picked.size()).is_equal(1)
	assert_str(String((picked[0] as BuildingData).id)).is_equal("road")

# ── Ficha del edificio ──

func test_the_sheet_keeps_the_tutorial_hooks() -> void:
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/BuildingInfoPanel.tscn").instantiate())
	add_child(panel)
	for group in ["hud_info_repair", "hud_info_move", "hud_info_demolish", "hud_info_demolish_confirm"]:
		var found := false
		for n in get_tree().get_nodes_in_group(group):
			if panel.is_ancestor_of(n):
				found = true
		assert_bool(found).override_failure_message("falta el grupo %s" % group).is_true()

# ── Investigar ──

func test_a_tech_card_says_two_short_lines() -> void:
	for tech in GameConfig.tech_definitions:
		var text: String = TechScript.tech_card_short(tech)
		assert_int(text.split("\n").size()).is_less_equal(2)

# ── Textos ──

func test_the_new_texts_exist_in_both_languages() -> void:
	var keys := ["UI2C_BUILD_TITLE", "UI2C_CLOSE", "UI2C_BTN_BUILD_TIP", "UI2C_BTN_UPGRADE_ONE_SHORT",
		"UI2C_BLD_ERA", "UI2C_BLD_NEEDS", "UI2C_BLD_LOCKED", "UI2C_WORKERS", "UI2C_CHIP_WORK",
		"UI2C_CHIP_ROOM", "UI2C_CHIP_MORALE", "UI2C_BTN_UPGRADE", "UI2C_BTN_REPAIR", "UI2C_BTN_MOVE",
		"UI2C_BTN_DEMOLISH", "UI2C_BTN_COLLECT", "UI2C_TIP_REPAIR", "UI2C_TIP_ROTATE", "UI2C_TIP_DEMOLISH",
		"UI2C_STATUS_NO_ROAD", "UI2C_MARKET_TITLE", "UI2C_MARKET_BUY_PRICE", "UI2C_MARKET_SELL_PRICE",
		"UI2C_BTN_BUY", "UI2C_BTN_SELL", "UI2C_MARKET_NO_GOLD", "UI2C_MARKET_NO_STOCK", "UI2C_TECH_TITLE"]
	for locale in Tr.LOCALES:
		for key in keys:
			assert_bool(Tr._STRINGS[locale].has(key)).override_failure_message("%s/%s" % [locale, key]).is_true()

func test_buttons_say_one_or_two_words() -> void:
	for locale in Tr.LOCALES:
		for key in ["UI2C_BTN_UPGRADE", "UI2C_BTN_REPAIR", "UI2C_BTN_MOVE", "UI2C_BTN_DEMOLISH",
				"UI2C_BTN_COLLECT", "UI2C_BTN_BUY", "UI2C_BTN_SELL", "UI2C_BUILD_TITLE", "UI2C_TECH_TITLE"]:
			assert_int(String(Tr._STRINGS[locale][key]).split(" ", false).size()).is_less_equal(2)
