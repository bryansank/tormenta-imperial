extends GdUnitTestSuite
## FABRICAR como tarjetas grandes (feat/recetas-tarjetas, 2026-10-25): cada
## edificio ensena TODAS sus recetas (las cerradas, con candado y el porque),
## el Nucleo las separa en pestanas por taller, el selector ×1 / ×5 / MAX elige
## cuantas suma cada toque del verbo y la cola acumula desde la tarjeta.

const ProcessCard := preload("res://scripts/ui/ProcessCard.gd")
const CT := preload("res://scripts/ui/CartoonTheme.gd")

var _saved_resources: Dictionary = {}
var _saved_unlocked: Dictionary = {}
var _saved_phase: int = 0
var _saved_phone := false
var _nodes: Array = []

func before_test() -> void:
	_saved_resources = {}
	for type in ResourceManager.get_all():
		_saved_resources[ResourceManager.get_type_name(type)] = ResourceManager.get_amount(type)
	_saved_unlocked = ResourceManager._unlocked.duplicate()
	_saved_phase = StormManager.get_cycle().phase
	StormManager.get_cycle().phase = StormCycle.Phase.CALM
	_saved_phone = CT.phone
	for res_name in ["gold", "wood", "planks", "ingots"]:
		_unlock(res_name)

func after_test() -> void:
	for node in _nodes:
		if is_instance_valid(node):
			ProcessManager.cancel(node)
			node.free()
	_nodes.clear()
	ResourceManager._unlocked = _saved_unlocked
	ResourceManager.set_amounts(_saved_resources)
	StormManager.get_cycle().phase = _saved_phase
	CT.phone = _saved_phone

func _node() -> Node3D:
	var node := Node3D.new()
	_nodes.append(node)
	return node

func _data(id: String) -> BuildingData:
	return load("res://data/buildings/%s.tres" % id) as BuildingData

## Una seccion FABRICAR montada en el arbol, con las recetas de `id`.
func _section(id: String, node: Node = null) -> ProcessActionsPanel:
	var host: VBoxContainer = auto_free(VBoxContainer.new())
	host.size = Vector2(640, 600)
	add_child(host)
	var panel := ProcessActionsPanel.new(host)
	panel.populate_building(node if node != null else _node(), _data(id), false)
	return panel

func _lock(res_name: String) -> void:
	ResourceManager._unlocked[ResourceManager.name_to_type(res_name)] = false

func _unlock(res_name: String) -> void:
	ResourceManager._unlocked[ResourceManager.name_to_type(res_name)] = true

func _card_by_id(panel: ProcessActionsPanel, pid: String) -> Node:
	for card in panel.cards():
		if String(card._proc.get("id", "")) == pid:
			return card
	return null

# ── Recetas visibles por edificio ──

func test_every_workshop_shows_all_its_recipes_even_the_locked_ones() -> void:
	_lock("steel")
	_lock("oil")
	for id in ["sawmill", "gold_mine", "foundry", "refinery", "carpentry"]:
		var panel := _section(id)
		assert_int(panel.action_count()).override_failure_message("recetas de " + id) \
			.is_equal(GameConfig.get_processes_for(id).size())

func test_the_section_is_called_make_and_each_card_has_icons_time_and_its_verb() -> void:
	ResourceManager.set_amounts({"wood": 200})
	var panel := _section("sawmill")
	var title: Label = panel._host.find_child("RecipeTitle", true, false)
	assert_str(title.text).is_equal(Tr.t("RCP_SECTION"))
	var card := _card_by_id(panel, "make_planks")
	assert_object(card).is_not_null()
	assert_object(card.find_child("Cost", true, false)).is_not_null()
	assert_object(card.find_child("Produces", true, false)).is_not_null()
	assert_object(card.find_child("Time", true, false)).is_not_null()
	var amount: Label = card.find_child("Amount_wood", true, false)
	assert_str(amount.text).is_equal("×20")
	# El verbo del edificio en el boton grande.
	assert_str(card.verb_button().text).contains(Tr.t("UI3F_VERB_MAKE_PLANKS"))
	# El detalle (lo que es, por minuto) va al mantener pulsado.
	assert_str(card.tooltip_text).contains(Tr.t("RCP_LORE_MAKE_PLANKS"))
	assert_str(card.tooltip_text).contains(Tr.t("RCP_PER_MIN") % "")

func test_materials_have_a_drawn_icon_for_the_big_cards() -> void:
	for mat in ["planks", "ingots", "beams", "fuel"]:
		var g: Control = CT.res_glyph(mat, 44)
		assert_object(g).override_failure_message("sin icono: " + mat).is_not_null()
		g.free()

# ── Bloqueadas con su porque ──

func test_a_locked_recipe_says_why_and_offers_no_buttons() -> void:
	_lock("steel")
	ResourceManager.set_amounts({"wood": 200, "gold": 200})
	var panel := _section("gold_mine")
	var card := _card_by_id(panel, "deep_mining")
	assert_bool(card.is_locked()).is_true()
	var expected := Tr.t("RCP_LOCKED_WITH") % [Tr.res_name("steel"), Tr.t("RCP_WITH_FOUNDRY")]
	assert_str(card.why_text()).is_equal(expected)
	assert_bool((card.find_child("Controls", true, false) as Control).visible).is_false()
	assert_bool((card.find_child("Lock", true, false) as Control).visible).is_true()
	# Las abiertas van delante de las cerradas.
	assert_bool(panel.cards()[0].is_locked()).is_false()

func test_a_locked_material_names_the_building_that_brings_it() -> void:
	assert_str(ProcessCard.locked_text("beams")).is_equal(
		Tr.t("RCP_LOCKED_WITH") % [Tr.res_name("beams"), Tr.t("RCP_WITH_FOUNDRY")])
	assert_str(ProcessCard.locked_text("oil")).contains(Tr.t("RCP_WITH_REFINERY"))

func test_without_resources_the_verb_is_grey_and_says_what_is_missing() -> void:
	ResourceManager.set_amounts({"wood": 15})
	var panel := _section("sawmill")
	var card := _card_by_id(panel, "make_planks")
	assert_bool(card.verb_button().disabled).is_true()
	assert_str(card.why_text()).is_equal(Tr.t("RCP_SHORT") % ("5 " + Tr.res_name("wood")))
	# La ficha de entrada, en rojo con lo que falta.
	var chip: Control = card.find_child("Chip_wood", true, false)
	assert_str(chip.tooltip_text).contains(Tr.t("OBJ_MISSING") % "5")

# ── La cola acumula desde la tarjeta ──

func test_the_queue_adds_up_from_the_card() -> void:
	ResourceManager.set_amounts({"wood": 600})
	var node := _node()
	var panel := _section("sawmill", node)
	var card := _card_by_id(panel, "make_planks")
	var verb: Button = card.verb_button()
	verb.pressed.emit()
	assert_int(ProcessManager.get_batch_left(node)).is_equal(1)
	verb.pressed.emit()
	assert_int(ProcessManager.get_batch_left(node)).is_equal(2)
	(card.find_child("Batch_5", true, false) as Button).pressed.emit()
	assert_int(card.picked()).is_equal(5)
	verb.pressed.emit()
	assert_int(ProcessManager.get_batch_left(node)).is_equal(7)
	# Se cobra al encolar: 7 tandas de 20 de madera.
	assert_int(ResourceManager.get_amount(ResourceManager.Type.WOOD)).is_equal(600 - 7 * 20)
	panel._refresh_cards(true, "make_planks")
	assert_str(card.queue_text()).is_equal(Tr.t("UI2F_QUEUE_N") % 7)
	# −1 devuelve una tanda sin empezar; las otras recetas dicen que esta ocupado.
	(card.find_child("QueueMinus", true, false) as Button).pressed.emit()
	assert_int(ProcessManager.get_batch_left(node)).is_equal(6)
	var other := _card_by_id(panel, "refined_lumber")
	assert_str(other.why_text()).contains(Tr.t("UI2F_BUSY_WITH") % Tr.t("PROC_MAKE_PLANKS"))
	assert_bool(other.verb_button().disabled).is_true()

func test_max_adds_what_can_be_paid() -> void:
	ResourceManager.set_amounts({"wood": 70})
	var node := _node()
	var panel := _section("sawmill", node)
	var card := _card_by_id(panel, "make_planks")
	var mx: Button = card.find_child("BatchMax", true, false)
	assert_str(mx.text).contains("3")
	mx.pressed.emit()
	card.verb_button().pressed.emit()
	assert_int(ProcessManager.get_batch_left(node)).is_equal(3)

# ── El Nucleo, en pestanas; la rejilla, por dispositivo ──

func test_the_core_groups_its_workshops_in_tabs() -> void:
	_unlock("planks")
	var panel := _section("nucleo")
	var tabs: Array = panel.tab_ids()
	assert_array(tabs).contains(["own", "sawmill", "hand"])
	assert_str(tabs[0]).is_equal("own")
	assert_str(tabs[tabs.size() - 1]).is_equal("hand")
	var tab_btn: Button = panel._host.find_child("Tab_sawmill", true, false)
	tab_btn.pressed.emit()
	# Las pestanas viejas se liberan al acabar el fotograma (se pulso una).
	await await_idle_frame()
	assert_str(panel.current_tab()).is_equal("sawmill")
	assert_int(panel.action_count()).is_equal(GameConfig.get_processes_for("sawmill").size())
	ProcessActionsPanel._core_tab_memory = ""

func test_phone_is_one_column_and_desktop_two_when_they_fit() -> void:
	CT.phone = true
	assert_int(CT.recipe_columns(2000.0)).is_equal(1)
	CT.phone = false
	var w := CT.recipe_card_min_w()
	assert_int(CT.recipe_columns(w * 2.0 + CT.recipe_gap())).is_equal(2)
	assert_int(CT.recipe_columns(w * 1.5)).is_equal(1)

func test_new_texts_exist_in_both_languages() -> void:
	var saved := Tr.get_locale()
	for loc in ["es", "en"]:
		Tr.set_locale(loc)
		for key in ["RCP_SECTION", "RCP_SECTION_DEPOSIT", "RCP_TAB_OWN", "RCP_TAB_HAND",
				"RCP_LOCKED_WITH", "RCP_LOCKED", "RCP_SHORT", "RCP_QUEUE_FULL", "RCP_NO_USES", "RCP_NO_ROOM",
				"RCP_IN_CONSTRUCTION", "RCP_PROGRESS", "RCP_PER_MIN", "RCP_PICK_TIP",
				"RCP_WITH_FOUNDRY", "RCP_WITH_REFINERY", "RCP_WITH_SAWMILL", "RCP_WITH_GOLD_MINE"]:
			assert_str(Tr.t(key)).override_failure_message(loc + " " + key).is_not_equal(key)
		for building_id in GameConfig.building_processes:
			for proc in GameConfig.building_processes[building_id]:
				var k := "RCP_LORE_" + String(proc["id"]).to_upper()
				assert_str(Tr.t(k)).override_failure_message(loc + " " + k).is_not_equal(k)
	Tr.set_locale(saved)
