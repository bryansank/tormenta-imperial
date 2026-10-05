extends GdUnitTestSuite
## Menos texto en CONSTRUIR, el panel del edificio y sus procesos (2026-10-04):
## los datos que deciden siguen a la vista aunque cambie como se dicen. Coste
## (cifras y lo que falta en rojo), motivo de bloqueo, produccion y tiempo.

const MenuScript := preload("res://scripts/ui/ConstructionMenu.gd")
const InfoScript := preload("res://scripts/ui/BuildingInfoPanel.gd")
const TextKit := preload("res://scripts/ui/TextKit.gd")
const Rules := preload("res://scripts/buildings/PlacementRules.gd")

var _amounts_before: Dictionary = {}
var _unlock_before: Dictionary = {}

func before_test() -> void:
	_amounts_before = {}
	var all: Dictionary = ResourceManager.get_all()
	for type in all:
		_amounts_before[ResourceManager.get_type_name(type)] = int(all[type])
	_unlock_before = ResourceManager.get_unlock_state()

func after_test() -> void:
	ResourceManager.set_unlock_state(_unlock_before)
	ResourceManager.set_amounts(_amounts_before)

func _data(id: String) -> BuildingData:
	return load("res://data/buildings/%s.tres" % id)

# ── TextKit ──

func test_times_read_short() -> void:
	assert_str(TextKit.short_time(12.2)).is_equal("13 s")
	assert_str(TextKit.short_time(90.0)).is_equal("1:30")
	assert_str(TextKit.short_time(7200.0)).is_equal("2 h")
	assert_str(TextKit.short_time(8100.0)).is_equal("2 h 15")

func test_a_cost_row_shows_every_amount_and_marks_what_is_missing() -> void:
	var row := TextKit.cost_row({"gold": 50, "wood": 30, "beams": 20}, {"wood": 12})
	var shown := TextKit.row_amounts(row)
	assert_str(String(shown["gold"])).is_equal("50")
	assert_str(String(shown["wood"])).is_equal("30")
	# Sin icono, el material se escribe con su nombre.
	assert_str(String(shown["beams"])).contains(Tr.res_name("beams"))
	var wood: Label = row.find_child("Amount_wood", true, false)
	assert_that(wood.get_theme_color("font_color")).is_equal(UITheme.readable(UITheme.DANGER))
	var gold: Label = row.find_child("Amount_gold", true, false)
	assert_that(gold.get_theme_color("font_color")).is_not_equal(UITheme.readable(UITheme.DANGER))
	row.free()

# ── CONSTRUIR ──

func test_the_detail_shows_cost_and_why_it_cannot_be_built() -> void:
	var menu: CanvasLayer = load("res://scenes/ui/ConstructionMenu.tscn").instantiate()
	add_child(menu)
	await await_idle_frame()
	ResourceManager.set_amounts({"gold": 10, "wood": 0, "steel": 0, "oil": 0})
	menu.call("_open")
	var house := _data("house")
	menu.call("_select_building", house)
	var cost: Control = menu.find_child("DetailCost", true, false)
	var shown := TextKit.row_amounts(cost)
	assert_str(String(shown["gold"])).is_equal(str(house.cost_gold))
	assert_str(String(shown["wood"])).is_equal(str(house.cost_wood))
	var block: Label = menu.find_child("DetailBlock", true, false)
	assert_bool(block.visible).is_true()
	assert_str(block.text).contains(Tr.res_name("wood"))
	# El motivo, corto: ninguna linea pasa de seis palabras mas las cifras.
	for line in block.text.split("\n"):
		assert_int(line.split(" ", false).size()).is_less_equal(8)
	assert_bool(menu.detail_build_button().disabled).is_true()
	menu.call("_close")
	menu.free()

func test_the_detail_says_what_it_produces_and_how_often() -> void:
	var menu: CanvasLayer = load("res://scenes/ui/ConstructionMenu.tscn").instantiate()
	add_child(menu)
	await await_idle_frame()
	menu.call("_open")
	var sawmill := _data("sawmill")
	menu.call("_select_building", sawmill)
	var prod: Control = menu.find_child("DetailProduction", true, false)
	assert_bool(prod.visible).is_true()
	var row: Control = prod.find_child("CostRow", true, false)
	assert_str(String(TextKit.row_amounts(row)["wood"])).is_equal("+%d" % sawmill.produces_wood)
	var every := Tr.t("FMT_EVERY") % TextKit.short_time(sawmill.production_interval)
	var found := false
	for child in prod.get_children():
		if child is Label and (child as Label).text == every:
			found = true
	assert_bool(found).is_true()
	menu.call("_close")
	menu.free()

func test_the_card_cost_is_a_row_of_amounts() -> void:
	var menu: CanvasLayer = load("res://scenes/ui/ConstructionMenu.tscn").instantiate()
	add_child(menu)
	await await_idle_frame()
	menu.call("_open")
	var found := false
	for card in menu.find_children("*", "PanelContainer", true, false):
		if String(card.get_meta("building_id", "")) == "house":
			var row: Control = card.find_child("CardCost", true, false)
			assert_str(String(TextKit.row_amounts(row)["gold"])).is_equal(str(_data("house").cost_gold))
			found = true
	assert_bool(found).is_true()
	menu.call("_close")
	menu.free()

func test_extras_are_short_pieces() -> void:
	var parts: Array = MenuScript.extras_parts(_data("foundry"))
	assert_array(parts).contains([Tr.t("LBL_WORKERS_SHORT") % _data("foundry").workers_required])
	assert_str(" ".join(parts)).contains(_data("gold_mine").get_display_name())

func test_short_block_reasons_name_locked_resources_without_the_story() -> void:
	ResourceManager.set_unlock_state({"gold": true, "wood": true, "steel": false, "oil": false})
	ResourceManager.set_amounts({"gold": 0, "wood": 0, "steel": 0, "oil": 0})
	var hq := _data("headquarters")
	var short := "\n".join(Rules.block_reasons_short(hq))
	assert_str(short).contains(Tr.res_name("steel"))
	assert_str(short).not_contains(Tr.t("UNLOCK_HINT_STEEL"))
	# La version entera (tooltip) sigue diciendo como se desbloquea.
	assert_str(Rules.purchase_block_detail(hq)).contains(Tr.t("UNLOCK_HINT_STEEL"))

# ── Panel del edificio ──

func test_the_level_line_is_short() -> void:
	var line: String = InfoScript.level_line(_data("sawmill"), 2)
	assert_str(line).contains(Tr.t("LBL_LEVEL_SHORT") % 2)
	assert_str(line).contains(Tr.t("LBL_WORKERS_SHORT") % _data("sawmill").workers_required)

func test_production_follows_the_level() -> void:
	var data := _data("sawmill")
	var at2: Dictionary = InfoScript.production_amounts(data, 2)
	assert_int(int(at2["wood"])).is_equal(int(data.produces_wood * GameConfig.get_production_multiplier(2)))

func test_costs_by_type_turn_into_names_and_what_is_missing() -> void:
	ResourceManager.set_amounts({"gold": 100, "wood": 0, "steel": 0, "oil": 0})
	var cost := {ResourceManager.Type.GOLD: 150, ResourceManager.Type.WOOD: 20}
	assert_dict(InfoScript.by_name(cost)).is_equal({"gold": 150, "wood": 20})
	assert_dict(InfoScript.missing_by_name(cost)).is_equal({"gold": 50, "wood": 20})

# ── Procesos ──

func test_a_process_card_keeps_cost_output_and_time() -> void:
	var proc := {"name": "PROC_TEST", "cost": {"wood": 15}, "produces": {"wood": 25, "gold": 5}, "duration": 30}
	var text: String = ProcessActionsPanel.process_card_text(proc)
	assert_str(text).contains("15 " + Tr.res_name("wood"))
	assert_str(text).contains("+25 " + Tr.res_name("wood"))
	assert_str(text).contains("+5 " + Tr.res_name("gold"))
	assert_str(text).contains("30 s")
	assert_str(text).not_contains(Tr.t("FMT_COST") % "")

func test_a_mining_card_says_why_it_cannot_start() -> void:
	var mining := {"name": "PROC_TEST", "produces": {"wood": 20}, "duration": 8}
	var text: String = ProcessActionsPanel.mining_card_text(mining, "MINE_NEEDS_ROAD")
	assert_str(text).contains("+20 " + Tr.res_name("wood"))
	assert_str(text).contains("8 s")
	assert_str(text).contains(Tr.t("MINE_NEEDS_ROAD"))
	assert_int(Tr.t("MINE_NEEDS_ROAD").split(" ", false).size()).is_less_equal(6)
