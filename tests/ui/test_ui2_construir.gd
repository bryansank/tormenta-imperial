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

func test_is_phone_reads_the_flag_device_profile_sets() -> void:
	# Una sola pregunta para todas las pantallas: la bandera que fija DeviceProfile.
	var saved := CT.phone
	CT.phone = true
	assert_bool(CT.is_phone()).is_true()
	CT.phone = false
	assert_bool(CT.is_phone()).is_false()
	assert_bool(DeviceProfile.is_phone_canvas(Vector2(800, 360))).is_true()
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

func test_rows_have_a_hammer_or_a_lock() -> void:
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

# ── CONSTRUIR3 (feat/ui3-construir): nombres enteros, franja del telefono, la X ──

func _menu() -> CanvasLayer:
	var menu: CanvasLayer = auto_free(load("res://scenes/ui/ConstructionMenu.tscn").instantiate())
	add_child(menu)
	return menu

func test_names_are_whole_and_big_enough_on_a_phone() -> void:
	var saved := CT.phone
	CT.phone = true
	var l := CT.name_label("Depósito de combustible", "small")
	assert_int(l.get_theme_font_size("font_size")).is_greater_equal(CT.NAME_MIN_PHONE)
	assert_bool(l.clip_text).is_false()
	assert_int(l.text_overrun_behavior).is_equal(TextServer.OVERRUN_NO_TRIMMING)
	assert_int(l.autowrap_mode).is_not_equal(TextServer.AUTOWRAP_OFF)
	assert_object(l.get_theme_font("font")).is_same(CT.title_font())
	l.free()
	CT.phone = saved

func test_every_row_name_is_whole_and_not_dimmed() -> void:
	var menu := _menu()
	await await_idle_frame()
	menu.call("_open")
	for card in menu._grid_container.get_children():
		var name_l: Label = card.find_child("RowName", true, false)
		assert_object(name_l).is_not_null()
		assert_int(name_l.text_overrun_behavior).is_equal(TextServer.OVERRUN_NO_TRIMMING)
		assert_bool(name_l.clip_text).is_false()
		assert_int(name_l.autowrap_mode).is_not_equal(TextServer.AUTOWRAP_OFF)
		# Bloqueado o no, el nombre con el color normal (contraste).
		assert_that(name_l.get_theme_color("font_color")).is_equal(CT.text("window"))
		assert_int(name_l.get_theme_font_size("font_size")).is_greater_equal(CT.name_size("button"))
	menu.call("_close")

func test_the_hold_bubble_starts_with_the_whole_name() -> void:
	var data := _data("fuel_depot")
	assert_str(MenuScript.row_tooltip(data).get_slice("\n", 0)).is_equal(data.get_display_name())

func test_on_a_phone_the_chosen_one_shows_in_a_strip_with_its_build_button() -> void:
	var saved := CT.phone
	CT.phone = true
	ResourceManager.set_amounts({"gold": 9999, "wood": 9999})
	var menu := _menu()
	await await_idle_frame()
	menu.call("_fit_layout")
	menu.call("_open")
	var strip: Control = menu.find_child("PhoneStrip", true, false)
	assert_bool(strip.visible).is_false()
	menu.call("_select_building", _data("road"))
	assert_bool(strip.visible).is_true()
	assert_str((strip.find_child("StripName", true, false) as Label).text).is_equal(_data("road").get_display_name())
	# El tutorial senala el CONSTRUIR de la franja: la ficha no sale en telefono.
	assert_object(menu.detail_build_button()).is_same(strip.find_child("StripBuildButton", true, false))
	menu.call("_close")
	assert_bool(strip.visible).is_false()
	CT.phone = saved
	menu.call("_fit_layout")

func test_the_strip_never_shows_on_pc() -> void:
	var saved := CT.phone
	CT.phone = false
	var menu := _menu()
	await await_idle_frame()
	menu.call("_fit_layout")
	menu.call("_open")
	menu.call("_select_building", _data("house"))
	assert_bool((menu.find_child("PhoneStrip", true, false) as Control).visible).is_false()
	assert_object(menu.detail_build_button()).is_same(menu.find_child("DetailBuildButton", true, false))
	menu.call("_close")
	CT.phone = saved

func test_the_close_x_steps_left_of_the_menu_button() -> void:
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(host)
	var btn := Control.new()
	btn.add_to_group("hud_menu_button")
	btn.position = Vector2(500, 0)
	btn.size = Vector2(60, 60)
	host.add_child(btn)
	var x := Control.new()
	x.position = Vector2(520, 10)
	x.size = Vector2(48, 48)
	host.add_child(x)
	await await_idle_frame()
	CT.dodge_menu_button(x)
	assert_bool(x.get_global_rect().intersects(btn.get_global_rect().grow(8.0))).is_false()
	# Llamarlo otra vez no lo corre mas: deshace el corrimiento anterior.
	var once := x.position.x
	CT.dodge_menu_button(x)
	assert_float(x.position.x).is_equal_approx(once, 0.5)
	host.free()

func test_the_building_guide_names_the_materials_and_the_whole_name() -> void:
	var helper: CanvasLayer = auto_free(load("res://scenes/ui/HelperPanel.tscn").instantiate())
	add_child(helper)
	await await_idle_frame()
	var hq := _data("headquarters")
	var card: Control = helper.call("_make_building_entry", hq)
	var cost: Control = card.find_child("GuideCost", true, false)
	var shown := TextKit.row_amounts(cost)
	for mat in hq.cost_materials:
		if int(hq.cost_materials[mat]) > 0:
			assert_str(String(shown[String(mat)])).contains(Tr.res_name(String(mat)))
	var name_l: Label = card.find_child("GuideName", true, false)
	assert_str(name_l.text).is_equal(hq.get_display_name())
	assert_int(name_l.text_overrun_behavior).is_equal(TextServer.OVERRUN_NO_TRIMMING)
	assert_str(card.tooltip_text.get_slice("\n", 0)).is_equal(hq.get_display_name())
	card.free()
