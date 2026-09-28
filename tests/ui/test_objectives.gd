extends GdUnitTestSuite
## El panel ¿QUE HACER? y la cuenta que lo alimenta (scripts/services/Objectives.gd).
##
## Antes el panel eran cinco pasos fijos y tres eran falsos: construir un Nucleo
## (ya esta puesto y no se construye), "conectar" edificios con almacenes (no se
## conecta nada) y desbloquear edificios con el arbol tecnologico (los
## desbloquean otros edificios). Ahora dice el paso de la partida tal como esta, y
## estos casos vigilan que ese paso sea siempre algo que el jugador puede hacer,
## en todas las etapas: de la primera obra al asedio, despues de perderlo y
## despues de ganarlo. docs/22-linea-jugable.md.

const Objectives := preload("res://scripts/services/Objectives.gd")
const Rules := preload("res://scripts/buildings/PlacementRules.gd")

var _placed: Array = []
var _next_cell := 0
var _saved: Dictionary = {}
var _scene: Node = null
var _made_scene := false
var _placer: Node = null

## ArmyManager.barracks_count() pregunta al "BuildingPlacer" de la escena actual;
## este cuenta en la rejilla, como el de verdad (PlacementRules.count_building).
class GridPlacer extends Node:
	func count_building(building_id: String) -> int:
		return load("res://scripts/buildings/PlacementRules.gd").count_building(building_id)

func before_test() -> void:
	_placed = []
	_next_cell = 0
	_saved = {
		"resources": ResourceManager.get_all(),
		"unlock": ResourceManager.get_unlock_state(),
		"era": ResourceManager.get_era(),
		"warehouses": ResourceManager.get_warehouse_count(),
		"progression": ProgressionManager.get_save_data(),
		"final_audit": ProgressionManager.final_audit,
		"population": PopulationManager.get_save_data(),
		"army": ArmyManager.get_save_data(),
		"storm": StormManager.get_save_data(),
		"tech": TechTreeManager.get_save_data(),
	}
	TechTreeManager.reset()
	_scene = get_tree().current_scene
	if _scene == null:
		_scene = Node.new()
		_scene.name = "ObjectivesTestScene"
		get_tree().root.add_child(_scene)
		get_tree().current_scene = _scene
		_made_scene = true
	_placer = GridPlacer.new()
	_placer.name = "BuildingPlacer"
	_scene.add_child(_placer)
	GridManager.clear_all()
	ProgressionManager.reset()
	ArmyManager.reset()
	StormManager.reset()
	ResourceManager.set_era(1)
	ResourceManager.set_warehouse_count(0)
	# La colonia nueva de verdad trae su Nucleo (+5 de aforo): sin el no habria ni
	# los obreros del primer aserradero.
	_build("nucleo")

func after_test() -> void:
	for node in _placed:
		if is_instance_valid(node):
			GridManager.remove_building(node)
			node.free()
	_placed.clear()
	GridManager.clear_all()
	_scene.remove_child(_placer)
	_placer.free()
	if _made_scene:
		get_tree().current_scene = null
		get_tree().root.remove_child(_scene)
		_scene.free()
		_made_scene = false
	ProgressionManager.load_save_data(_saved["progression"])
	ProgressionManager.final_audit = _saved["final_audit"]
	StormManager.load_save_data(_saved["storm"])
	TechTreeManager.load_save_data(_saved["tech"])
	ArmyManager.load_save_data(_saved["army"])
	ResourceManager.set_unlock_state(_saved["unlock"])
	ResourceManager.set_era(int(_saved["era"]))
	ResourceManager.set_warehouse_count(int(_saved["warehouses"]))
	var amounts := {}
	for type in _saved["resources"]:
		amounts[ResourceManager.get_type_name(type)] = _saved["resources"][type]
	ResourceManager.set_amounts(amounts)
	PopulationManager.load_save_data(_saved["population"])

# ── Utilleria ────────────────────────────────────────────────────────

## Planta un edificio en la rejilla (sin placer ni mapa: Objectives solo cuenta
## por GridManager) y reparte obreros como en partida.
func _build(building_id: String) -> Node3D:
	var data: BuildingData = Rules.load_building_data(building_id)
	var node := Node3D.new()
	node.set_meta("level", 1)
	var origin := Vector2i((_next_cell % 9) * 4 + 1, (_next_cell / 9) * 4 + 1)
	_next_cell += 1
	assert_bool(GridManager.place_building(origin, data, node)).override_failure_message(
		"no cupo %s en %s" % [building_id, origin]).is_true()
	_placed.append(node)
	if building_id == "warehouse":
		ResourceManager.set_warehouse_count(Rules.count_building("warehouse"))
	# Las fases avanzan con los mismos edificios que en partida
	# (GameConfig.phase_triggers): el consumo despierta con el aserradero.
	var phase_by := {"sawmill": GameConfig.Phase.SETTLEMENT, "gold_mine": GameConfig.Phase.ECONOMY,
		"warehouse": GameConfig.Phase.SURVIVAL, "foundry": GameConfig.Phase.EXPANSION}
	if phase_by.has(building_id):
		ProgressionManager.current_phase = maxi(ProgressionManager.current_phase, int(phase_by[building_id]))
	if building_id == "foundry" and ProgressionManager.current_era < 2:
		ProgressionManager.current_era = 2
		ResourceManager.set_era(2)
		ResourceManager.unlock(ResourceManager.Type.STEEL)
	if building_id == "refinery" and ProgressionManager.current_era < 3:
		ProgressionManager.current_era = 3
		ResourceManager.set_era(3)
		ResourceManager.unlock(ResourceManager.Type.OIL)
	_staff_everyone()
	return node

## Tanta gente como quepa, y moral de sobra: aqui se prueba el camino, no el hambre.
func _staff_everyone() -> void:
	PopulationManager.load_save_data({"population": 999, "morale": 90})

func _give(step: Dictionary) -> void:
	# Justo lo que cuesta el paso: con la bolsa a rebosar el paso seria siempre
	# "otro almacen", que es verdad pero no es lo que se prueba aqui.
	var amounts := {"gold": 0, "wood": 0, "steel": 0, "oil": 0}
	var cost: Dictionary = Objectives.step_cost(step)
	for type in cost:
		amounts[ResourceManager.get_type_name(type)] = int(cost[type])
	ResourceManager.set_amounts(amounts)

func _add_unit(unit_id: String) -> void:
	var units: Dictionary = (ArmyManager.get_save_data()["units"] as Dictionary).duplicate()
	units[unit_id] = int(units.get(unit_id, 0)) + 1
	ArmyManager.load_save_data({"units": units, "training": [], "upkeep_accum": 0.0})

func _first(building_id: String) -> Node:
	for info in GridManager.get_all_buildings():
		if (info["data"] as BuildingData).id == building_id:
			return info["node"]
	return null

## Da el paso como lo daria el jugador.
func _take(step: Dictionary) -> void:
	match String(step["kind"]):
		"build":
			_build(String(step["id"]))
		"upgrade":
			Objectives.upgrade_node(step).set_meta("level", int(step["level"]))
		"train", "rebuild":
			_add_unit(String(step["id"]))
		"repair":
			var node: Node = Objectives._ruined_producer()
			node.set_meta("health", BuildingHealth.get_max_health(node))
		"research":
			TechTreeManager._researched[String(step["id"])] = true
			TechTreeManager._apply_tech_bonus(TechTreeManager.get_tech(String(step["id"])))
		"sell":
			MarketManager.sell(String(step["id"]), int(step["amount"]))

func _assert_readable(step: Dictionary, where: String) -> void:
	var text: Dictionary = Objectives.describe(step)
	assert_str(String(text["title"])).override_failure_message(
		"%s: paso sin titulo %s" % [where, str(step)]).is_not_empty()
	assert_bool(String(text["title"]).begins_with("OBJ_")).override_failure_message(
		"%s: titulo sin traducir %s" % [where, text["title"]]).is_false()
	assert_bool(String(text["why"]).begins_with("OBJ_") or String(text["why"]) == "").override_failure_message(
		"%s: porque sin traducir '%s'" % [where, text["why"]]).is_false()

# ── La linea entera ──────────────────────────────────────────────────

## De la colonia vacia al asedio, dando cada paso que el panel pide y con justo
## lo que cuesta: el panel nunca se atasca, nunca pide algo imposible, y el orden
## de la linea es el de la guia.
func test_following_the_panel_walks_the_whole_line_to_the_siege() -> void:
	var visited: Array = []
	var guard := 0
	while not ProgressionManager.is_final_audit_pending():
		guard += 1
		if guard > 120:
			assert_bool(false).override_failure_message(
				"el panel dio vueltas sin llegar al asedio; ultimos pasos: %s" % str(visited.slice(-8))).is_true()
			return
		var step: Dictionary = Objectives.next_step()
		assert_str(String(step.get("kind", ""))).is_not_equal("sandbox")
		_assert_readable(step, "paso %d" % guard)
		_give(step)
		assert_str(Objectives.blocker(step)).override_failure_message(
			"con lo que cuesta en la bolsa, el paso %s sigue bloqueado: %s" % [
				str(step), Objectives.blocker(step)]).is_empty()
		visited.append("%s:%s" % [step["kind"], step.get("id", "")])
		_take(step)
		if String(step["kind"]) == "upgrade" and String(step["id"]) == "headquarters" and int(step["level"]) == 3:
			ProgressionManager.summon_final_audit()

	# El orden de la linea, en la secuencia visitada (con lo que haya en medio).
	var expected: Array = ["build:sawmill", "build:gold_mine", "build:house", "build:sawmill",
		"build:warehouse", "build:foundry", "build:barracks", "train:artillery", "train:artillery",
		"build:refinery", "build:tower", "build:tower", "build:headquarters",
		"upgrade:headquarters", "train:vehicle", "upgrade:headquarters"]
	var cursor := 0
	for entry in visited:
		if cursor < expected.size() and entry == expected[cursor]:
			cursor += 1
	assert_int(cursor).override_failure_message(
		"el panel se salto '%s'. Visitados: %s" % [
			expected[mini(cursor, expected.size() - 1)], str(visited)]).is_equal(expected.size())

## El primer paso de una colonia nueva es el que dice la intro: el aserradero.
func test_a_new_colony_is_told_to_build_a_sawmill() -> void:
	var step: Dictionary = Objectives.next_step()
	assert_str(String(step["kind"])).is_equal("build")
	assert_str(String(step["id"])).is_equal("sawmill")

## Lo que da de comer en ruinas va antes que levantar otro igual.
func test_a_ruined_producer_is_repaired_before_anything_else() -> void:
	ProgressionManager.current_phase = GameConfig.Phase.SURVIVAL
	var sawmill := _build("sawmill")
	_build("gold_mine")
	BuildingHealth.damage_building(sawmill, BuildingHealth.get_max_health(sawmill))
	var step: Dictionary = Objectives.next_step()
	assert_str(String(step["kind"])).is_equal("repair")
	assert_str(String(step["id"])).is_equal("sawmill")
	_assert_readable(step, "reparar")

## La mejora que no cabe en la bolsa no se pide a ciegas: primero el almacen.
func test_an_upgrade_that_does_not_fit_asks_for_a_warehouse_first() -> void:
	ProgressionManager.current_phase = GameConfig.Phase.EXPANSION
	for id in ["sawmill", "gold_mine", "house", "house", "house", "house", "sawmill", "warehouse", "foundry", "barracks",
			"refinery", "tower", "tower", "headquarters"]:
		_build(id)
	for i in range(Objectives.GARRISON_UNITS):
		_add_unit("artillery")
	# Era 3 con un almacen: 1000 + 500 = 1500, y la mejora a nivel 2 cuesta 2000.
	var step: Dictionary = Objectives.next_step()
	assert_str(String(step["kind"])).is_equal("build")
	assert_str(String(step["id"])).is_equal("warehouse")
	assert_str(String(step["why"])).is_equal("OBJ_WHY_BAG_TOO_SMALL")

# ── El final y lo que viene despues ──────────────────────────────────

## Una base de era 3 que ya produce de todo y con la bolsa sana: lo que se
## prueba despues es el asedio, no la economia.
func _a_running_base() -> void:
	for id in ["sawmill", "gold_mine", "house", "foundry", "barracks", "refinery"]:
		_build(id)
	ResourceManager.set_amounts({"gold": 400, "wood": 100, "steel": 200, "oil": 100})

func _summon_with(units: Dictionary) -> void:
	_a_running_base()
	for id in units:
		for i in int(units[id]):
			_add_unit(String(id))
	ProgressionManager.current_era = 3
	assert_bool(ProgressionManager.summon_final_audit()).is_true()

func test_a_summoned_siege_with_a_full_garrison_says_let_them_come() -> void:
	_summon_with({"vehicle": Objectives.SIEGE_VEHICLES})
	var step: Dictionary = Objectives.next_step()
	assert_str(String(step["kind"])).is_equal("siege")
	_assert_readable(step, "asedio")

func test_a_summoned_siege_short_of_armour_asks_for_vehicles_first() -> void:
	_summon_with({"vehicle": 2})
	var step: Dictionary = Objectives.next_step()
	assert_str(String(step["kind"])).is_equal("train")
	assert_str(String(step["id"])).is_equal("vehicle")

## Perder el asedio no deja el panel mudo ni le miente: con tres unidades se puede
## reconvocar, pero con tres no se gana (docs/17-balance-asedio.md), asi que lo
## que pide es la guarnicion que si gana, y despues volver a llamarlos.
func test_after_a_lost_siege_the_panel_rebuilds_then_resummons() -> void:
	_summon_with({"infantry": 3})
	ProgressionManager.final_audit.begin({"infantry": 3})
	ProgressionManager.final_audit.lose()
	ArmyManager.reset()
	var step: Dictionary = Objectives.next_step()
	assert_str(String(step["kind"])).is_equal("rebuild")
	assert_str(String(step["id"])).is_equal("vehicle")
	_assert_readable(step, "tras perder")
	for i in range(Objectives.SIEGE_VEHICLES):
		_add_unit("vehicle")
	step = Objectives.next_step()
	assert_str(String(step["kind"])).is_equal("resummon")
	_assert_readable(step, "reconvocar")

## Ganada la partida y pulsado "Seguir jugando", el panel no vuelve a pedir el
## Cuartel General ni el asedio: la isla es del jugador.
func test_after_victory_the_panel_is_a_sandbox() -> void:
	EventBus.storm_halted_forever.emit()
	var step: Dictionary = Objectives.next_step()
	assert_str(String(step["kind"])).is_equal("sandbox")
	_assert_readable(step, "tras ganar")
	var final_row: Dictionary = Objectives.route()[Objectives.LINE.size()]
	assert_bool(bool(final_row["done"])).is_true()

# ── El panel ─────────────────────────────────────────────────────────

func test_the_panel_shows_the_live_step_and_not_the_old_fixed_list() -> void:
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/ObjectivePanel.tscn").instantiate())
	add_child(panel)
	panel.refresh()
	var shown: Dictionary = panel.get_now_text()
	var expected: Dictionary = Objectives.describe(Objectives.next_step())
	assert_str(String(shown["title"])).is_equal(String(expected["title"]))
	assert_str(String(shown["why"])).is_equal(String(expected["why"]))
	# Las frases falsas de antes no estan en ninguna parte del panel.
	for key in ["LBL_OBJ_STEP_1", "LBL_OBJ_STEP_4", "LBL_OBJ_STEP_5", "LBL_OBJ_MISSION_DESC"]:
		assert_bool(_panel_says(panel, Tr.t(key))).override_failure_message(
			"el panel sigue diciendo '%s'" % Tr.t(key)).is_false()

func _panel_says(node: Node, text: String) -> bool:
	if node is Label and (node as Label).text == text:
		return true
	for child in node.get_children():
		if _panel_says(child, text):
			return true
	return false

## La mejora final cuesta exactamente la bolsa maxima sin tecnologia. Con los
## cinco almacenes en pie, el panel manda al arbol a por holgura en vez de dejar al
## jugador cuadrando los cuatro recursos al centimo.
func test_the_last_upgrade_sends_you_to_the_storage_techs_first() -> void:
	ProgressionManager.current_phase = GameConfig.Phase.EXPANSION
	for id in ["sawmill", "gold_mine", "gold_mine", "gold_mine", "house", "house", "house", "house", "house", "sawmill",
			"warehouse", "warehouse", "warehouse", "warehouse", "warehouse", "foundry", "barracks",
			"refinery", "tower", "tower", "headquarters"]:
		_build(id)
	_first("headquarters").set_meta("level", 2)
	for i in range(Objectives.SIEGE_VEHICLES):
		_add_unit("vehicle")
	# Lo que haga falta por el camino (casas para los obreros, etc.) se da; lo que
	# se vigila es que antes de la mejora final aparezca la tecnologia de almacen.
	var research: Array = []
	var step: Dictionary = {}
	for i in range(30):
		step = Objectives.next_step()
		if String(step["kind"]) == "upgrade" and int(step.get("level", 0)) == 3:
			break
		_assert_readable(step, "antes de la mejora final")
		if String(step["kind"]) == "research":
			research.append(String(step["id"]))
		_give(step)
		_take(step)
	assert_array(research).override_failure_message(
		"la mejora final se pidio sin pasar por las tecnologias de almacen").is_not_empty()
	assert_str(String(research[0])).is_equal("log_1")
	assert_str(String(step["kind"])).is_equal("upgrade")
	assert_int(int(step["level"])).is_equal(3)
	# Y con la holgura, la mejora ya no es el 100% de la bolsa.
	assert_int(Objectives._cost_total(Objectives.step_cost(step))).is_less(ResourceManager.get_storage_cap())
