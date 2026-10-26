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
		"tutorial": TutorialManager.get_save_data(),
		"campaigns": CombatManager.get_campaigns_save_data(),
	}
	TechTreeManager.reset()
	# Ninguna campana empezada (feat/ritmo-colono: sus piezas cierran capitulos).
	CombatManager.load_campaigns_save_data({"seed": 11})
	# La primera escaramuza ya ganada: estos casos prueban la linea de siempre. Los
	# que hablan de ella la vuelven a abrir (test_first_sortie_*).
	TutorialManager.first_sortie_done = true
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
	# Comida de sobra para unos ciclos (2026-10-04): lo que dejo la suite anterior
	# no puede convertir cada paso en "compra comida".
	ResourceManager.set_amounts({"food": 400})
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
	TutorialManager.load_save_data(_saved["tutorial"])
	CombatManager.load_campaigns_save_data(_saved["campaigns"])

# ── Utilleria ────────────────────────────────────────────────────────

## Las tres campanas ganadas: sus piezas del CG nivel 3 en casa (feat/ritmo-colono).
func _with_all_pieces() -> void:
	var progress := {}
	for d in GameConfig.CAMPAIGN_DOMAINS:
		progress[d] = GameConfig.campaign_base_count(String(d))
	CombatManager.load_campaigns_save_data({"seed": 11, "progress": progress})

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
	# Su carretera hasta el Nucleo, como la tenderia el juego: sin ella el
	# edificio no recibe gente ni produce (PopulationManager, meta `connected`).
	if not data.is_core and building_id != "road":
		var route: Variant = Rules.road_route(origin, data.grid_size)
		if route != null:
			var road: BuildingData = Rules.load_building_data("road")
			for c in route:
				var tile := Node3D.new()
				if GridManager.place_building(c, road, tile):
					_placed.append(tile)
				else:
					tile.free()
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
		"buy":
			# Comprar comida con el oro que sobra (paso de hambre, 2026-10-12). El
			# paso no tiene coste propio (step_cost), asi que _give ya vacio la
			# bolsa: entra lo comprado, que es lo que hace pasar pagina.
			ResourceManager.add(ResourceManager.name_to_type(String(step["id"])), int(step["amount"]))
		"sortie":
			# Sale y la gana: lo que cuenta aqui es que el panel pase pagina.
			assert_bool(bool(CombatManager.can_launch({String(step["id"]): 1})["ok"])).is_true()
			EventBus.expedition_ended.emit(Expedition.RESULT_WON, {}, {})
		"campaign":
			# La mision que toca, ganada (feat/ritmo-colono: los capitulos piden las
			# piezas de los jefes antes del CG nivel 3). Sin descanso: aqui se
			# prueba el camino, no el reloj.
			var domain: String = String(step["id"])
			var book: CampaignBook = CombatManager.get_campaign_book()
			CombatManager._publish_campaign_events(book.finish(domain, book.next_mission(domain), true, 0.0, 0.0))
		"make":
			# Como entrenar: el taller termina al instante. Se paga la receta que
			# _give puso en la bolsa y entra lo que el paso pide (el jugador repetiria
			# la receta hasta juntarlo; aqui se prueba el camino, no el reloj).
			assert_bool(_first(String(step["building"])) != null).override_failure_message(
				"el paso %s pide un taller que no esta en pie" % str(step)).is_true()
			ResourceManager.spend_cost(Objectives.step_cost(step))
			ResourceManager.add(ResourceManager.name_to_type(String(step["id"])), int(step["amount"]))

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
	# Partida nueva de verdad: la primera escaramuza esta por hacer.
	TutorialManager.first_sortie_done = false
	# La bolsa de una partida nueva (con la comida de salida, 2026-10-04).
	var start := {"gold": 0, "wood": 0, "steel": 0, "oil": 0, "food": 0}
	start.merge(GameConfig.starting_resources, true)
	ResourceManager.set_amounts(start)
	var visited: Array = []
	var guard := 0
	while not ProgressionManager.is_final_audit_pending():
		guard += 1
		if guard > 260:
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
	# La Granja ocupa dos obreros: la primera casa puede llegar antes que la mina,
	# como paso de apoyo, asi que aqui no se exige su sitio (2026-10-04).
	# Cuartel temprano (2026-10-17): el Cuartel, un soldado y su primera mision;
	# la guarnicion de la era 2 empieza ya por la artilleria. Aqui la bolsa es
	# siempre "justo lo del paso anterior", asi que el Cuartel nunca se puede
	# pagar al decidir y los apoyos (Granja, Casa, Mina) le pasan delante: que
	# va justo detras del aserradero con la bolsa de verdad lo vigila
	# test_with_the_real_bag_the_barracks_comes_right_after_the_planks.
	var expected: Array = ["build:sawmill", "build:barracks", "train:infantry", "sortie:infantry",
		"build:market",
		"build:warehouse", "build:foundry", "train:artillery", "train:artillery",
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
	# La bolsa de una partida nueva (no la que dejo otra suite).
	var bag := {"gold": 0, "wood": 0, "steel": 0, "oil": 0, "food": 0, "planks": 0}
	bag.merge(GameConfig.starting_resources, true)
	ResourceManager.set_amounts(bag)
	PopulationManager.load_save_data({"population": 5, "morale": 75})
	var step: Dictionary = Objectives.next_step()
	assert_str(String(step["kind"])).is_equal("build")
	assert_str(String(step["id"])).is_equal("sawmill")

## Cuartel temprano (2026-10-17): en la linea, el Cuartel va justo detras del
## aserradero, despues la Granja y un soldado, y solo entonces la Mina.
func test_the_early_line_is_sawmill_barracks_farm_soldier_then_mine() -> void:
	var saved_mode: int = GameMode.current
	GameMode.current = GameMode.Mode.CAMPAIGN
	_build("sawmill")
	assert_str(String(Objectives._first_open_line_step()["id"])).is_equal("barracks")
	_build("barracks")
	assert_str(String(Objectives._first_open_line_step()["id"])).is_equal("farm")
	_build("farm")
	var soldier: Dictionary = Objectives._first_open_line_step()
	assert_str(String(soldier["kind"])).is_equal("train")
	assert_str(String(soldier["id"])).is_equal("infantry")
	_assert_readable(soldier, "primer soldado")
	_add_unit("infantry")
	assert_str(String(Objectives._first_open_line_step()["id"])).is_equal("gold_mine")
	# El Cuartel no sale dos veces en EL CAMINO.
	var barracks_rows := 0
	for row in Objectives.route():
		if String(row["text"]) == Rules.load_building_data("barracks").get_display_name():
			barracks_rows += 1
	assert_int(barracks_rows).is_equal(1)
	GameMode.current = saved_mode

## Con la bolsa de una partida nueva de verdad: aserradero, tablones y el
## Cuartel, sin que la Granja, una Casa o la Mina se cuelen (los apoyos esperan
## a que falte algo). Ronda de pruebas de la 1.0, 2026-10-17.
func test_with_the_real_bag_the_barracks_comes_right_after_the_planks() -> void:
	var saved_mode: int = GameMode.current
	GameMode.current = GameMode.Mode.CAMPAIGN
	TutorialManager.first_sortie_done = false
	var bag := {"gold": 0, "wood": 0, "steel": 0, "oil": 0, "food": 0, "planks": 0}
	bag.merge(GameConfig.starting_resources, true)
	ResourceManager.set_amounts(bag)
	PopulationManager.load_save_data({"population": 5, "morale": 75})
	var first: Dictionary = Objectives.next_step()
	assert_str("%s:%s" % [first["kind"], first["id"]]).is_equal("build:sawmill")
	ResourceManager.spend_cost(Objectives.step_cost(first))
	_build("sawmill")
	PopulationManager.load_save_data({"population": 5, "morale": 75})
	var planks: Dictionary = Objectives.next_step()
	assert_str("%s:%s" % [planks["kind"], planks["id"]]).is_equal("make:planks")
	for i in runs_needed(planks):
		var recipe: Dictionary = Objectives.material_recipe("planks")
		var cost := {}
		for res_name in recipe["cost"]:
			cost[ResourceManager.name_to_type(String(res_name))] = int(recipe["cost"][res_name])
		ResourceManager.spend_cost(cost)
		ResourceManager.add(ResourceManager.Type.PLANKS, int(recipe["produces"]["planks"]))
	var step: Dictionary = Objectives.next_step()
	assert_str("%s:%s" % [step["kind"], step["id"]]).is_equal("build:barracks")
	GameMode.current = saved_mode

func runs_needed(step: Dictionary) -> int:
	return Objectives.runs_for(step)

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
	for id in ["sawmill", "farm", "farm", "farm", "gold_mine", "market", "house", "house", "house", "house", "sawmill", "warehouse", "foundry", "barracks",
			"refinery", "tower", "tower", "headquarters"]:
		_build(id)
	for i in range(Objectives.GARRISON_UNITS):
		_add_unit("artillery")
	# Comida para unos ciclos: sin ella el paso seria comprarla (2026-10-04).
	ResourceManager.set_amounts({"gold": 0, "wood": 0, "steel": 0, "oil": 0, "food": 400})
	# Las piezas de las campanas (feat/ritmo-colono) ya en casa: lo que se prueba
	# es la bolsa del CG nivel 2, no las campanas que van antes en la linea.
	_with_all_pieces()
	# Era 3 con un almacen: 1000 + 500 = 1500, y la mejora a nivel 2 cuesta 2000.
	var step: Dictionary = Objectives.next_step()
	assert_str(String(step["kind"])).is_equal("build")
	assert_str(String(step["id"])).is_equal("warehouse")
	assert_str(String(step["why"])).is_equal("OBJ_WHY_BAG_TOO_SMALL")

# ── El final y lo que viene despues ──────────────────────────────────

## Una base de era 3 que ya produce de todo y con la bolsa sana: lo que se
## prueba despues es el asedio, no la economia.
func _a_running_base() -> void:
	for id in ["sawmill", "farm", "farm", "farm", "gold_mine", "market", "house", "foundry", "barracks", "refinery"]:
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
	# El blindado pide 8 vigas desde balance/huecos: aqui estan, o el paso seria
	# hacerlas (make, que tambien sirve al blindado). Y sin madera de sobra: con
	# la gente al tope el panel gastaria lo que sobra en otra casa
	# (house_room_step), que es otro caso.
	ResourceManager.set_amounts({"wood": 0, "beams": 40})
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
	# Las vigas del blindado (balance/huecos), como en el caso de arriba.
	ResourceManager.set_amounts({"wood": 0, "beams": 40})
	var step: Dictionary = Objectives.next_step()
	assert_str(String(step["kind"])).is_equal("rebuild")
	assert_str(String(step["id"])).is_equal("vehicle")
	_assert_readable(step, "tras perder")
	for i in range(Objectives.SIEGE_VEHICLES):
		_add_unit("vehicle")
	step = Objectives.next_step()
	assert_str(String(step["kind"])).is_equal("resummon")
	_assert_readable(step, "reconvocar")

## La espera muerta de la era 3 (docs/22 §11): bolsa casi llena, el paso espera
## acero que llega despacio y sobra oro y madera que el paso no pide. El panel no
## dice "espera": gasta lo que sobra en subir la Fundicion, sin tocar lo del paso.
func test_a_full_bag_waiting_on_a_slow_resource_upgrades_its_producer_with_the_surplus() -> void:
	_a_running_base()
	ResourceManager.set_warehouse_count(3)
	# Las vigas del blindado (balance/huecos) ya hechas: lo que falta es solo el
	# acero lento. Un material que falta no tiene productor que subir (sale del
	# taller, paso "make").
	ResourceManager.set_amounts({"beams": 40})
	var target := {"kind": "train", "id": "vehicle", "count": Objectives.SIEGE_VEHICLES}
	var upgrade := {"kind": "upgrade", "id": "foundry", "level": 2, "pick": "lowest"}
	var need: Dictionary = Objectives.step_cost(target)
	var up: Dictionary = Objectives.step_cost(upgrade)
	# La mejora de la Fundicion no pide acero (si lo pidiera, no habria sobrante).
	assert_int(int(up.get(ResourceManager.Type.STEEL, 0))).is_equal(0)
	var gold: int = int(need.get(ResourceManager.Type.GOLD, 0)) + int(up.get(ResourceManager.Type.GOLD, 0))
	var oil: int = int(need.get(ResourceManager.Type.OIL, 0)) + int(up.get(ResourceManager.Type.OIL, 0))
	var cap: int = ResourceManager.get_storage_cap()
	var wood: int = int(float(cap) * 0.85) - gold - oil
	assert_int(wood).is_greater_equal(int(up.get(ResourceManager.Type.WOOD, 0)))
	ResourceManager.set_amounts({"gold": gold, "wood": wood, "steel": 0, "oil": oil, "food": 0})
	# Acero a 0,1 por segundo: los 180 del blindado tardan media hora.
	var net := {"gold": 5.0, "wood": 5.0, "steel": 0.1, "oil": 5.0, "food": 5.0}
	var step: Dictionary = Objectives._surplus_upgrade_step(target, net)
	assert_str(String(step.get("kind", ""))).is_equal("upgrade")
	assert_str(String(step.get("id", ""))).is_equal("foundry")
	assert_str(String(step.get("why", ""))).is_equal("OBJ_WHY_SURPLUS_UPGRADE")
	_assert_readable(step, "mejora con lo que sobra")
	# Sin oro de sobra, la mejora retrasaria el paso: no se pide.
	ResourceManager.set_amounts({"gold": int(need.get(ResourceManager.Type.GOLD, 0)), "wood": wood,
		"steel": 0, "oil": oil, "food": 0})
	assert_bool(Objectives._surplus_upgrade_step(target, net).is_empty()).is_true()
	# Con la bolsa holgada manda el productor nuevo de siempre, no esta mejora.
	ResourceManager.set_amounts({"gold": gold, "wood": 0, "steel": 0, "oil": oil, "food": 0})
	assert_bool(Objectives._surplus_upgrade_step(target, net).is_empty()).is_true()

## Ganada la partida y pulsado "Seguir jugando", el panel no vuelve a pedir el
## Cuartel General ni el asedio: la isla es del jugador.
func test_after_victory_the_panel_is_a_sandbox() -> void:
	EventBus.storm_halted_forever.emit()
	var step: Dictionary = Objectives.next_step()
	assert_str(String(step["kind"])).is_equal("sandbox")
	_assert_readable(step, "tras ganar")
	var final_row: Dictionary = {}
	for row in Objectives.route():
		if String(row["text"]) == Tr.t("OBJ_ROUTE_FINAL"):
			final_row = row
	assert_bool(bool(final_row.get("done", false))).is_true()

# ── El panel ─────────────────────────────────────────────────────────

func test_the_panel_shows_the_live_step_and_not_the_old_fixed_list() -> void:
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/ObjectivePanel.tscn").instantiate())
	add_child(panel)
	panel.refresh()
	var shown: Dictionary = panel.get_now_text()
	# El titulo es el objetivo (2026-10-19); debajo, sus pasos.
	var plan: Dictionary = Objectives.plan()
	var expected: Dictionary = Objectives.describe(plan["goal"])
	assert_str(String(shown["title"])).is_equal(String(plan["title"]))
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
	for id in ["sawmill", "farm", "farm", "farm", "gold_mine", "market", "gold_mine", "gold_mine", "house", "house", "house", "house", "house", "sawmill",
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
	var seen: Array = []
	# Con la bolsa a cero tras cada paso (_give) el acero va lento y el panel pide
	# antes fundiciones, refinerias y sus mejoras hasta los topes por era: el
	# camino es largo, no un bucle (60 vueltas se quedaban cortas desde el 14-10).
	for i in range(250):
		step = Objectives.next_step()
		seen.append("%s:%s" % [step.get("kind", ""), step.get("id", "")])
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
	assert_str(String(step["kind"])).override_failure_message(str(seen)).is_equal("upgrade")
	assert_int(int(step.get("level", 0))).override_failure_message(str(seen) + str(step)).is_equal(3)
	# Y con la holgura, la mejora ya no es el 100% de la bolsa.
	assert_int(Objectives._cost_total(Objectives.step_cost(step))).is_less(ResourceManager.get_storage_cap())

# ── Los modos ────────────────────────────────────────────────────────

## En Constructor no hay Diezmo ni asedio: el panel no pide guarnicion ni
## blindados, y el nivel 3 del Cuartel General es la meta. En Sandbox no hay
## objetivo. docs/20-modos-de-juego.md.
func test_the_builder_skips_the_army_and_the_sandbox_has_no_goal() -> void:
	var saved_mode: int = GameMode.current
	var saved_result: String = GameMode.run_result
	GameMode.begin_run(GameMode.Mode.BUILDER)
	var visited: Array = []
	for i in range(160):
		var step: Dictionary = Objectives.next_step()
		if String(step["kind"]) == "sandbox":
			break
		visited.append("%s:%s" % [step["kind"], step.get("id", "")])
		if String(step["kind"]) == "upgrade" and String(step["id"]) == "headquarters" \
				and int(step["level"]) == 3:
			assert_str(String(Objectives.describe(step)["why"])).is_equal(Tr.t("OBJ_WHY_HQ_3_BUILDER"))
			ProgressionManager.milestones_completed["hq_max"] = true
			continue
		_give(step)
		_take(step)
	assert_bool(visited.has("train:vehicle")).override_failure_message(
		"el Constructor pidio blindados: %s" % str(visited)).is_false()
	assert_bool(visited.has("train:artillery") or visited.has("train:infantry")).override_failure_message(
		"el Constructor pidio guarnicion: %s" % str(visited)).is_false()
	# Sin Tormenta las torres no son un paso (el Cuartel General no las pide), y el
	# cuartel se explica por el Cuartel General, no por el Diezmo.
	assert_bool(visited.has("build:tower")).override_failure_message(
		"el Constructor pidio torres: %s" % str(visited)).is_false()
	assert_str(String(Objectives.describe({"kind": "build", "id": "barracks", "why": "OBJ_WHY_BARRACKS"})["why"])) \
		.is_equal(Tr.t("OBJ_WHY_BARRACKS_BUILDER"))
	assert_str(String(Objectives.next_step()["why"])).is_equal("OBJ_WHY_SANDBOX_BUILT")
	GameMode.begin_run(GameMode.Mode.SANDBOX)
	assert_str(String(Objectives.next_step()["why"])).is_equal("OBJ_WHY_SANDBOX_MODE")
	GameMode.current = saved_mode
	GameMode.run_result = saved_result

# ── La primera escaramuza ────────────────────────────────────────────

## Una base de era 1 con el cuartel en pie, sin tropa.
func _a_base_with_barracks() -> void:
	for id in ["sawmill", "farm", "farm", "farm", "gold_mine", "market", "house", "sawmill", "warehouse", "foundry", "barracks"]:
		_build(id)
	ResourceManager.set_amounts({"gold": 300, "wood": 200, "steel": 50})

## Con el cuartel y sin tropa, el panel pide entrenar; en cuanto sale la primera
## unidad, pide la escaramuza ANTES de seguir con la guarnicion de cinco.
func test_first_sortie_is_asked_as_soon_as_the_first_unit_stands() -> void:
	TutorialManager.first_sortie_done = false
	_a_base_with_barracks()
	var before: Dictionary = Objectives.next_step()
	assert_str(String(before["kind"])).is_not_equal("sortie")
	_add_unit("infantry")
	var step: Dictionary = Objectives.next_step()
	assert_str(String(step["kind"])).is_equal("sortie")
	assert_str(String(step["id"])).is_equal("infantry")
	assert_str(String(step["why"])).is_equal("OBJ_WHY_FIRST_SORTIE")
	_assert_readable(step, "primera escaramuza")
	assert_str(Objectives.blocker(step)).is_empty()
	# En el camino va justo antes de la guarnicion, y es la fila de ahora.
	var rows: Array = Objectives.route()
	var sortie_at := -1
	for i in rows.size():
		if String(rows[i]["text"]) == Tr.t("OBJ_ROUTE_FIRST_SORTIE"):
			sortie_at = i
	assert_int(sortie_at).is_greater(0)
	assert_bool(bool(rows[sortie_at]["current"])).is_true()
	# Con el Cuartel temprano (2026-10-17) la mision va DETRAS del primer soldado:
	# sin soldado no hay mision.
	assert_str(String(rows[sortie_at - 1]["text"])).contains(Tr.t(String(GameConfig.get_unit_def("infantry")["name"])))
	assert_bool(bool(rows[sortie_at - 1]["done"])).is_true()
	# Y sale una sola vez en EL CAMINO.
	var sorties := 0
	for row in rows:
		if String(row["text"]) == Tr.t("OBJ_ROUTE_FIRST_SORTIE"):
			sorties += 1
	assert_int(sorties).is_equal(1)

## Ganada la primera, el panel vuelve a la linea: la guarnicion de cinco.
func test_first_sortie_goes_away_once_won() -> void:
	TutorialManager.first_sortie_done = false
	_a_base_with_barracks()
	_add_unit("infantry")
	assert_str(String(Objectives.next_step()["kind"])).is_equal("sortie")
	EventBus.expedition_ended.emit(Expedition.RESULT_WON, {}, {})
	assert_bool(TutorialManager.is_first_sortie_done()).is_true()
	var step: Dictionary = Objectives.next_step()
	assert_str(String(step["kind"])).is_not_equal("sortie")
	var garrison_or_support: bool = String(step["kind"]) in ["train", "build", "make", "sell", "buy"]
	assert_bool(garrison_or_support).override_failure_message("tras la primera: %s" % str(step)).is_true()

## Perderla o abandonarla no la gasta: se vuelve a pedir.
func test_a_lost_or_abandoned_first_sortie_is_asked_again() -> void:
	TutorialManager.first_sortie_done = false
	_a_base_with_barracks()
	_add_unit("infantry")
	EventBus.expedition_ended.emit(Expedition.RESULT_LOST, {}, {})
	EventBus.expedition_ended.emit(Expedition.RESULT_ABANDONED, {}, {})
	assert_bool(TutorialManager.is_first_sortie_done()).is_false()
	assert_str(String(Objectives.next_step()["kind"])).is_equal("sortie")

## Con la Regencia convocada nadie sale: el paso no se pide.
func test_first_sortie_is_not_asked_with_the_audit_summoned() -> void:
	TutorialManager.first_sortie_done = false
	_summon_with({"vehicle": Objectives.SIEGE_VEHICLES})
	assert_str(String(Objectives.next_step()["kind"])).is_equal("siege")

## Ya hecha (o en una partida que ya salio de expedicion), el flujo es el de
## siempre: con una unidad en casa se sigue pidiendo la guarnicion.
func test_with_the_first_sortie_done_the_flow_is_unchanged() -> void:
	_a_base_with_barracks()
	_add_unit("infantry")
	var step: Dictionary = Objectives.next_step()
	assert_str(String(step["kind"])).is_not_equal("sortie")
	for row in Objectives.route():
		if String(row["text"]) == Tr.t("OBJ_ROUTE_FIRST_SORTIE"):
			assert_bool(bool(row["done"])).is_true()

# ── Requisitos y torres del asedio (2026-10-12) ──────────────────────

## Un paso cuyo edificio pide otro en pie antes (building_prerequisites) no se
## propone a ciegas: primero el requisito, y el requisito del requisito.
func test_a_step_with_missing_prerequisites_asks_for_them_first() -> void:
	var step: Dictionary = Objectives.prerequisite_step({"kind": "build", "id": "refinery"})
	# Sin nada en pie: Refineria -> Fundicion -> Aserradero.
	assert_str(String(step.get("id", ""))).is_equal("sawmill")
	assert_str(String(step.get("why", ""))).is_equal("OBJ_WHY_PREREQUISITE")
	_assert_readable(step, "requisito")

func test_a_step_with_its_prerequisites_standing_is_left_alone() -> void:
	for id in ["sawmill", "gold_mine", "house", "warehouse", "foundry", "barracks"]:
		_build(id)
	var saved: Array = GameConfig.building_prerequisites["refinery"].duplicate()
	GameConfig.building_prerequisites["refinery"] = ["foundry", "barracks"]
	assert_bool(Objectives.prerequisite_step({"kind": "build", "id": "refinery"}).is_empty()).is_true()
	GameConfig.building_prerequisites["refinery"] = saved

## La linea pide para el asedio tantas torres como dotaciones caben a la vez.
func test_the_siege_towers_follow_the_crew_cap() -> void:
	var entry := {"kind": "build", "id": "tower", "count_from": "audit_towers"}
	var saved: int = GameConfig.storm_tower_garrison_max
	GameConfig.storm_tower_garrison_max = 4
	assert_int(Objectives.entry_count(entry)).is_equal(4)
	GameConfig.storm_tower_garrison_max = saved

# ── Lo que falta, y como conseguirlo (2026-10-17, fix/tutorial-materiales) ──

func test_the_build_blocker_lists_everything_missing_not_just_the_first_thing() -> void:
	# Sin trabajadores libres y sin oro: antes solo salia "Sin trabajadores
	# disponibles" y lo que faltaba de recursos quedaba escondido.
	PopulationManager._population = 0
	PopulationManager._used_workers = 0
	ResourceManager.set_amounts({"gold": 0, "wood": 0})
	var block: String = Objectives.blocker({"kind": "build", "id": "market"})
	assert_str(block).contains(Tr.t("LBL_NEEDS_WORKERS") % [1, PopulationManager.get_free_workers()])
	assert_str(block).contains(Tr.t("OBJ_MISSING") % Tr.amount_list(Rules.missing_cost(Rules.load_building_data("market"))))

func test_a_missing_workshop_material_says_where_to_make_it() -> void:
	_build("sawmill")
	ResourceManager.unlock(ResourceManager.name_to_type("planks"))
	ResourceManager.set_amounts({"planks": 0})
	var how: String = Objectives.how_to_get("planks")
	# Sin "Tablones:" delante (2026-10-19): donde y que boton.
	assert_str(how).contains(Objectives.your_building("sawmill"))
	assert_str(how).contains(Tr.t("PROC_MAKE_PLANKS"))
	assert_str(how).contains(Rules.load_building_data("sawmill").get_display_name())

func test_a_material_without_its_workshop_says_to_build_it_first() -> void:
	assert_int(Rules.count_building("foundry")).is_equal(0)
	var how: String = Objectives.how_to_get("beams")
	var foundry: String = Rules.load_building_data("foundry").get_display_name()
	assert_str(how).is_equal(Tr.t("GUIDE_HOW_MAKE_FIRST") % Objectives.building_a("foundry"))
	assert_str(how).contains(foundry)

func test_every_resource_and_material_has_a_way_to_get_it() -> void:
	for res in ["wood", "gold", "food", "planks", "ingots", "beams", "fuel"]:
		assert_str(Objectives.how_to_get(res)).override_failure_message(
			"sin como conseguir %s" % res).is_not_empty()

func test_the_panel_says_what_is_missing_and_how_to_get_it() -> void:
	_build("sawmill")
	ResourceManager.unlock(ResourceManager.name_to_type("planks"))
	ResourceManager.set_amounts({"gold": 0, "wood": 0, "planks": 0})
	var text: Dictionary = Objectives.describe({"kind": "build", "id": "barracks", "why": "OBJ_WHY_BARRACKS"})
	var block: String = String(text["blocker"])
	assert_str(block).contains(Tr.res_name("planks"))
	assert_str(block).contains(Tr.t("PROC_MAKE_PLANKS"))
	assert_str(block).contains(Tr.ti("GUIDE_HOW_WOOD"))

# ── Tres campanas (feat/tres-campanas) ───────────────────────────────

## Las piezas en la linea (feat/ritmo-colono): con el Cuartel General en pie, lo
## siguiente son las campanas (Tierra primero: es lo que le queda al capitulo II).
## Aqui, sin tropa en casa, el panel pide tropa de su medio; la ruta tiene la fila
## de la pieza y la puerta dice que piezas faltan.
func test_with_the_hq_standing_the_panel_asks_for_the_pieces() -> void:
	var saved_mode: int = GameMode.current
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	ProgressionManager.current_phase = GameConfig.Phase.EXPANSION
	for id in ["sawmill", "farm", "farm", "farm", "gold_mine", "market", "house", "house", "house", "house",
			"warehouse", "foundry", "barracks", "refinery", "tower", "tower", "headquarters"]:
		_build(id)
	for i in range(Objectives.GARRISON_UNITS):
		_add_unit("artillery")
	ResourceManager.set_amounts({"gold": 2000, "wood": 500, "steel": 500, "oil": 300, "food": 400})
	assert_str(String(Objectives._first_open_line_step().get("kind", ""))).is_equal("campaign")
	assert_array(Objectives.gate_domains()).is_equal(["land", "sea", "air"])
	var gate: Dictionary = Objectives.campaign_gate_step()
	assert_dict(gate).is_not_empty()
	assert_str(String(Objectives.next_step()["kind"])).is_not_equal("sandbox")
	var want: String = Tr.t("OBJ_ROUTE_PIECE") % (Tr.t("PIECE_FROM_BOSS") % [CombatManager.piece_name("land"),
		Tr.t("CAMP_NAME_LAND")])
	var found := false
	for row in Objectives.route():
		if String(row["text"]) == want:
			found = true
			assert_bool(bool(row["current"])).is_true()
	assert_bool(found).is_true()
	assert_str(Objectives.final_gate_text()).contains(Tr.t("PIECE_SHORT_SEA"))
	# Con las tres piezas, la linea sigue por el CG nivel 2.
	_with_all_pieces()
	assert_str(String(Objectives._first_open_line_step().get("kind", ""))).is_equal("upgrade")
	GameMode.current = saved_mode

## Con las tres piezas la puerta no pide nada mas que el CG nivel 3.
func test_with_the_three_campaigns_done_only_the_hq_is_missing() -> void:
	var saved_campaigns: Dictionary = CombatManager.get_campaigns_save_data()
	CombatManager.load_campaigns_save_data({"progress": {
		"land": GameConfig.campaign_base_count("land"),
		"sea": GameConfig.campaign_base_count("sea"),
		"air": GameConfig.campaign_base_count("air")}})
	var missing: Array = ProgressionManager.final_audit_missing()
	assert_array(missing).contains_exactly([Tr.t("AUDIT_NEEDS_HQ3")])
	assert_dict(Objectives.campaign_gate_step()).is_empty()
	CombatManager.load_campaigns_save_data(saved_campaigns)

# ── El objetivo, paso a paso (2026-10-19, feat/objetivo-paso-a-paso) ──
#
# Queja de Bryan: "siempre me dices EDIFICIO: OBJETIVO; coloca el OBJETIVO y ya,
# y explica PASO A PASO que se necesita". Y su bug: "cuando me pide oro, si no
# esta contado al oro, todo queda bugueado" (lo que espera en la Mina no contaba).

func _lines(p: Dictionary) -> Array:
	return Objectives.plan_lines(p["items"])

func _current_count(items: Array) -> int:
	var n := 0
	for item in items:
		if String(item["state"]) == "current":
			n += 1
	return n

func test_goal_titles_never_put_the_building_name_in_front() -> void:
	var saved := Tr.get_locale()
	for lang in ["es", "en"]:
		Tr.set_locale(lang)
		var verb: String = Tr.t("OBJ_DO_BUILD").split("%s")[0]
		for entry in Objectives.LINE:
			if String(entry["kind"]) != "build":
				continue
			var id: String = String(entry["id"])
			var bname: String = Rules.load_building_data(id).get_display_name()
			var title: String = Objectives.goal_title({"kind": "build", "id": id})
			assert_str(title).override_failure_message("%s: '%s'" % [lang, title]).starts_with(verb)
			assert_str(title).not_contains(bname + ":")
			assert_str(title).not_contains(": " + bname)
			assert_str(title).contains(bname)
	Tr.set_locale(saved)

func test_articles_follow_the_building() -> void:
	var saved := Tr.get_locale()
	Tr.set_locale("es")
	assert_str(Objectives.building_a("barracks")).is_equal("un " + Rules.load_building_data("barracks").get_display_name())
	assert_str(Objectives.building_a("house")).is_equal("una " + Rules.load_building_data("house").get_display_name())
	assert_str(Objectives.building_the("farm")).is_equal("la " + Rules.load_building_data("farm").get_display_name())
	Tr.set_locale("en")
	assert_str(Objectives.building_a("sawmill")).is_equal("a Sawmill")
	assert_str(Objectives.building_the("market")).is_equal("the Market")
	Tr.set_locale(saved)

func test_the_barracks_goal_lists_the_sawmill_the_planks_and_placing_it() -> void:
	_build("sawmill")
	ResourceManager.unlock(ResourceManager.name_to_type("planks"))
	var data: BuildingData = Rules.load_building_data("barracks")
	var need: int = int(data.get_cost().get(ResourceManager.name_to_type("planks"), 0))
	assert_int(need).override_failure_message("el Cuartel ya no pide tablones").is_greater(0)
	ResourceManager.set_amounts({"gold": 2000, "wood": 2000, "food": 400, "planks": need - 4})
	var p: Dictionary = Objectives.plan_for({"kind": "build", "id": "barracks", "count": 1})
	assert_str(String(p["title"])).is_equal(Tr.t("OBJ_DO_BUILD") % Objectives.building_a("barracks"))
	var lines: Array = _lines(p)
	var have: int = lines.find("✓ " + Rules.load_building_data("sawmill").get_display_name())
	var make: int = lines.find("● " + Tr.t("OBJ_STEP_MAKE") % [need, Tr.res_name("planks"), need - 4, need])
	var place: int = lines.find("○ " + Tr.t("OBJ_STEP_PLACE") % Objectives.building_the("barracks"))
	assert_int(have).override_failure_message(str(lines)).is_greater_equal(0)
	assert_int(make).override_failure_message(str(lines)).is_greater(have)
	assert_int(place).override_failure_message(str(lines)).is_greater(make)
	assert_int(lines.size()).is_between(2, Objectives.PLAN_MAX_ITEMS)
	# El paso de ahora dice como darlo, en una frase.
	assert_str(String(p["current"]["how"])).contains(Tr.t("PROC_MAKE_PLANKS"))
	# La linea plegada: el objetivo y el paso de ahora, cortos.
	assert_str(Objectives.plan_line(p)).is_equal("%s · %s" % [p["title"],
		Tr.t("OBJ_STEP_MAKE_SHORT") % [Tr.res_name("planks"), need - 4, need]])

func test_with_everything_paid_the_step_is_to_place_it() -> void:
	ResourceManager.set_amounts({"gold": 2000, "wood": 2000, "food": 400})
	var p: Dictionary = Objectives.plan_for({"kind": "build", "id": "sawmill", "count": 1})
	var cur: Dictionary = p["current"]
	assert_str(String(cur["kind"])).is_equal("place")
	assert_str(String(cur["text"])).is_equal(Tr.t("OBJ_STEP_PLACE") % Objectives.building_the("sawmill"))
	assert_dict(cur["go"]).is_equal({"build": "sawmill"})
	# Sin nada mas que decir, la linea es solo el objetivo.
	assert_str(Objectives.plan_line(p)).is_equal(String(p["title"]))

func test_gold_waiting_in_the_mine_is_the_step_and_counts() -> void:
	var mine: Node = _build("gold_mine")
	ResourceManager.set_amounts({"gold": 20, "wood": 100, "food": 100, "steel": 0, "oil": 0})
	ProductionManager._stock[mine] = {"res": {"gold": 45}, "age": 0.0}
	var cost: int = int(Rules.load_building_data("sawmill").get_cost()[ResourceManager.Type.GOLD])
	var p: Dictionary = Objectives.plan_for({"kind": "build", "id": "sawmill", "count": 1})
	var cur: Dictionary = p["current"]
	ProductionManager._stock.erase(mine)
	assert_str(String(cur["kind"])).is_equal("collect")
	assert_str(String(cur["text"])).is_equal(Tr.t("OBJ_STEP_COLLECT") % [Tr.res_name("gold"), Objectives.building_the("gold_mine"), 45])
	assert_str(String(cur["how"])).is_equal(Tr.t("OBJ_STEP_BAG_COUNT") % [20, 45, cost])
	assert_object(cur["go"]["node"]).is_same(mine)
	assert_str(Objectives.plan_line(p)).contains(Tr.t("OBJ_STEP_COLLECT_SHORT") % [Tr.res_name("gold"), 45])
	# Recogido, el paso avanza solo: ya no hay nada que recoger, queda juntar.
	ResourceManager.set_amounts({"gold": 65})
	var after: Dictionary = Objectives.plan_for({"kind": "build", "id": "sawmill", "count": 1})
	for item in after["items"]:
		assert_str(String(item["kind"])).is_not_equal("collect")
	assert_str(String(after["current"]["kind"])).is_equal("gather")
	assert_str(String(after["current"]["text"])).contains("65")

func test_the_tutorial_points_at_the_building_with_something_to_collect() -> void:
	var mine: Node = _build("gold_mine")
	ResourceManager.set_amounts({"gold": 0, "wood": 100, "food": 100, "steel": 0, "oil": 0})
	ProductionManager._stock[mine] = {"res": {"gold": 45}, "age": 0.0}
	var target: String = TutorialManager.need_target("sawmill")
	var hint: String = TutorialManager.step_hint("need_sawmill")
	ProductionManager._stock.erase(mine)
	assert_str(target).contains("gold_mine")
	assert_str(hint).contains("● " + Tr.t("OBJ_STEP_COLLECT") % [Tr.res_name("gold"), Objectives.building_the("gold_mine"), 45])

func test_a_full_bag_asks_to_make_room_instead_of_waiting_blind() -> void:
	var mine: Node = _build("gold_mine")
	var cap: int = ResourceManager.get_storage_cap()
	ResourceManager.set_amounts({"gold": 0, "wood": cap, "food": 0})
	ProductionManager._stock[mine] = {"res": {"gold": 45}, "age": 0.0}
	var p: Dictionary = Objectives.plan_for({"kind": "build", "id": "sawmill", "count": 1})
	ProductionManager._stock.erase(mine)
	var kinds: Array = []
	for item in p["items"]:
		kinds.append(String(item["kind"]))
	assert_array(kinds).contains(["room"])
	# Recoger no cabe: no se pide.
	assert_array(kinds).not_contains(["collect"])

func test_short_of_hands_with_full_houses_asks_for_another_house() -> void:
	ResourceManager.set_amounts({"gold": 2000, "wood": 2000, "food": 400})
	PopulationManager._population = PopulationManager._max_population
	PopulationManager._used_workers = PopulationManager._population
	var p: Dictionary = Objectives.plan_for({"kind": "build", "id": "sawmill", "count": 1})
	var house := Rules.load_building_data("house")
	assert_array(_lines(p)).contains(["● " + Tr.t("OBJ_STEP_HOUSE") % house.population_capacity])

func test_a_support_step_goes_first_as_the_current_one() -> void:
	ResourceManager.set_amounts({"gold": 0, "wood": 0, "food": 400})
	var action := {"kind": "build", "id": "farm", "count": 1, "why": "OBJ_WHY_FEED_FOOD"}
	var p: Dictionary = Objectives.plan_for({"kind": "build", "id": "barracks", "count": 1}, action)
	var first: Dictionary = p["items"][0]
	assert_str(String(first["state"])).is_equal("current")
	assert_str(String(first["text"])).is_equal(String(Objectives.describe(action)["title"]))
	assert_int(_current_count(p["items"])).is_equal(1)

func test_every_step_of_the_line_has_a_short_list_with_one_current() -> void:
	ResourceManager.set_amounts({"gold": 0, "wood": 0, "food": 400})
	for entry in Objectives.LINE:
		var goal: Dictionary = entry.duplicate()
		var p: Dictionary = Objectives.plan_for(goal, goal)
		var items: Array = p["items"]
		var label := "%s:%s" % [entry["kind"], entry["id"]]
		assert_int(items.size()).override_failure_message(label).is_between(1, Objectives.PLAN_MAX_ITEMS)
		assert_int(_current_count(items)).override_failure_message(label).is_equal(1)
		assert_str(String(p["title"])).override_failure_message(label).is_not_empty()

func test_next_step_is_not_touched_by_the_plan() -> void:
	# La sonda de linea lee next_step(): el plan solo lo lee.
	_build("sawmill")
	var before: Dictionary = Objectives.next_step()
	Objectives.plan()
	assert_dict(Objectives.next_step()).is_equal(before)
	assert_dict(Objectives.goal_step()).is_not_empty()

func test_the_panel_lists_the_steps_and_the_hud_line_shows_goal_and_step() -> void:
	_build("sawmill")
	ResourceManager.unlock(ResourceManager.name_to_type("planks"))
	ResourceManager.set_amounts({"gold": 2000, "wood": 2000, "food": 400, "planks": 0})
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/ObjectivePanel.tscn").instantiate())
	add_child(panel)
	panel.refresh()
	var p: Dictionary = Objectives.plan()
	var shown: Dictionary = panel.get_now_text()
	assert_str(String(shown["title"])).is_equal(String(p["title"]))
	assert_array(shown["steps"]).is_equal(Objectives.plan_lines(p["items"]))
	assert_array(shown["steps"]).is_not_empty()
	if panel.line() != null:
		panel.refresh_line()
		assert_str(panel.line_text()).is_equal(Objectives.plan_line(p))
