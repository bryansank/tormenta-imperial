extends Node
## El "jugador razonable" de tools/line_probe.gd. Juega una colonia entera por
## semilla con los servicios REALES (BuildingPlacer y MapGenerator de verdad,
## mismo `_try_place()` que un clic), pero con el reloj en la mano: los autoloads
## dejan de procesar solos y se les da el tiempo a pasos fijos. Asi una partida de
## tres horas se juega en segundos y con tiempos reales (dev_mode apagado).
##
## Lo que decide el jugador, por orden de prioridad en cada vistazo (cada 2 s):
##   1. reparar lo roto (produccion y torres primero), fuera de la Tormenta;
##   2. no quedarse sin oro ni madera: otra mina / otro aserradero si el saldo
##      por segundo no llega;
##   3. casas cuando faltan obreros para lo siguiente;
##   4. almacenes cuando la bolsa se llena o lo siguiente no cabe;
##   5. el siguiente paso del camino recomendado (Objectives.next_step, la misma
##      cuenta que ensena el panel ¿QUE HACER?);
##   6. tropa: guarnicion para el Diezmo y, para el final, blindados;
##   7. mercado: vender lo que sobra para cerrar lo que falta (y las 10 operaciones);
##   8. el asedio cuando la guarnicion esta lista.
##
## Las peleas (Diezmo y oleadas) las juega AutoResolver con la IA a los dos
## lados, que es peor que una persona: el resultado del asedio es un suelo. El
## tiempo de cada pelea se estima con la formula de tools/balance_probe.gd y la
## base sigue corriendo mientras tanto (el juego no se pausa en el tablero).

signal finished(code: int)

const Placer := preload("res://scripts/buildings/BuildingPlacer.gd")
const MapGen := preload("res://scripts/map/MapGenerator.gd")
const AutoResolverScript := preload("res://scripts/combat/AutoResolver.gd")
const Rules := preload("res://scripts/buildings/PlacementRules.gd")
const Objectives := preload("res://scripts/services/Objectives.gd")

const DT := 1.0
const DECIDE_EVERY := 2.0
const SAMPLE_EVERY := 60.0
## Un hueco sin progreso mayor que esto cuenta como "espera muerta".
const DEAD_WAIT := 120.0
## Guarnicion que el jugador razonable quiere en casa antes de bajar a la Regencia.
const SIEGE_TARGET := {"vehicle": 6}
## Ciclos de consumo que el jugador razonable deja siempre en la caja.
const RESERVE_TICKS := 2.0

var options: Dictionary = {}

var _scene: Node = null
var _placer: Node3D = null
var _map: Node = null
var _clock_probe: Object = null
var _clock := 0.0
var _decide_accum := 0.0
var _sample_accum := 0.0

# ── Registro de la partida ──
var _r: Dictionary = {}

func run() -> void:
	GameConfig.dev_mode = false
	GameConfig.time_multiplier = 1.0
	# `--cfg.clave=valor` pisa un numero de GameConfig solo en esta corrida, para
	# medir un cambio antes de escribirlo (ej. --cfg.storm_morale_per_tick=0.25).
	for key in options:
		if String(key).begins_with("cfg."):
			var prop: String = String(key).substr(4)
			GameConfig.set(prop, str_to_var(String(options[key])))
			print("override %s = %s" % [prop, str(GameConfig.get(prop))])
	_clock_probe = load("res://tools/balance_probe.gd").new()
	_connect_probes()
	var results: Array = []
	for s in options.get("seeds", [1]):
		var result: Dictionary = await _play_seed(int(s))
		results.append(result)
		_print_run(result)
	_print_table(results)
	finished.emit(0)

# ══════════════════════════════════════════════════════════════════════
# Montaje
# ══════════════════════════════════════════════════════════════════════

func _open_colony(map_seed: int) -> void:
	if FileAccess.file_exists("user://save_game.json"):
		DirAccess.remove_absolute(OS.get_user_data_dir().path_join("save_game.json"))
	seed(map_seed)
	_scene = Node.new()
	_scene.name = "LineScene"
	get_tree().root.add_child(_scene)
	get_tree().current_scene = _scene
	GridManager.clear_all()
	GameManager._placer = null
	GameManager._map_gen = null
	GameManager._started = false
	_map = MapGen.new()
	_map.name = "MapGenerator"
	_scene.add_child(_map)
	_placer = Placer.new()
	_placer.name = "BuildingPlacer"
	_scene.add_child(_placer)
	# Reloj de la Tormenta con la misma semilla que el mapa: la partida entera se
	# repite igual con la misma semilla.
	StormManager.get_cycle().seed_rng(map_seed)
	for node in get_tree().root.get_children():
		if node != self and node != _scene:
			node.set_process(false)

func _close_colony() -> void:
	CombatManager.reset()
	for info in GridManager.get_all_buildings():
		ProductionManager.unregister(info["node"])
	_placer.clear_all_buildings()
	_map.clear_all_deposits()
	GridManager.clear_all()
	get_tree().current_scene = null
	get_tree().root.remove_child(_scene)
	_scene.free()
	_scene = null
	GameManager._placer = null
	GameManager._map_gen = null
	GameManager._started = false

# ══════════════════════════════════════════════════════════════════════
# Una partida
# ══════════════════════════════════════════════════════════════════════

func _play_seed(map_seed: int) -> Dictionary:
	_r = {
		"seed": map_seed, "milestones": {}, "actions": [], "progress_times": [0.0],
		"storms": [], "tithes": [], "ruined": 0, "overflow": 0, "samples": [],
		"deaths_starve": 0, "deserted": 0, "units_lost": 0, "units_trained": 0,
		"sieges": [], "victory_at": -1.0, "stuck": "", "deposits": {},
		"full_time": 0.0, "false_alarms": 0, "repairs": 0, "trades": 0,
		"board_minutes": 0.0, "events": 0, "step_time": {},
	}
	_clock = 0.0
	_decide_accum = 0.0
	_sample_accum = 0.0
	_open_colony(map_seed)
	for dep in _map.get_all_deposits():
		_r["deposits"][dep["id"]] = int(_r["deposits"].get(dep["id"], 0)) + 1

	var limit: float = float(options.get("hours", 8.0)) * 3600.0
	var frame_budget := 0.0
	while _clock < limit and _r["victory_at"] < 0.0:
		_tick(DT)
		_decide_accum += DT
		if _decide_accum >= DECIDE_EVERY:
			_decide_accum = 0.0
			_decide()
		if CombatManager.is_board_open():
			await _fight_open_board()
		frame_budget += DT
		if frame_budget >= 300.0:
			frame_budget = 0.0
			_sweep_labels()
			await get_tree().process_frame
	if _r["victory_at"] < 0.0:
		_r["stuck"] = _describe_state()
	_r["end"] = _snapshot()
	_close_colony()
	return _r

func _tick(dt: float) -> void:
	ProductionManager._process(dt)
	PopulationManager._process(dt)
	ProcessManager._process(dt)
	ArmyManager._process(dt)
	MarketManager._process(dt)
	RandomEventManager._process(dt)
	StormManager._process(dt)
	TechTreeManager._process(dt)
	ProgressionManager._process(dt)
	_clock += dt
	_sample_accum += dt
	if ResourceManager.get_free_space() <= int(ResourceManager.get_storage_cap() * 0.02):
		_r["full_time"] += dt
	if _sample_accum >= SAMPLE_EVERY:
		_sample_accum = 0.0
		var snap: Dictionary = _snapshot()
		_r["samples"].append(snap)
		if bool(options.get("log", false)):
			print("  %6.1f min  · moral %d pob %d/%d oro %d madera %d acero %d petroleo %d bolsa %d/%d fase %d ejercito %s" % [
				_clock / 60.0, snap["morale"], snap["pop"], snap["max_pop"], snap["gold"], snap["wood"],
				snap["steel"], snap["oil"], snap["stored"], snap["cap"], StormManager.get_phase(), str(snap["army"])])

## Las etiquetas flotantes necesitan fotogramas reales para morirse; con el reloj
## en la mano se amontonarian por miles.
func _sweep_labels() -> void:
	for child in _scene.get_children():
		if child is Label3D:
			child.free()

# ══════════════════════════════════════════════════════════════════════
# El tablero
# ══════════════════════════════════════════════════════════════════════

func _fight_open_board() -> void:
	var guard := 0
	while CombatManager.is_board_open() and guard < 12:
		guard += 1
		var board: Encounter = CombatManager.get_encounter()
		if board == null:
			CombatManager.end_encounter()
			break
		var audit_wave: bool = ProgressionManager.is_final_audit_active()
		var outcome: Dictionary = AutoResolverScript.resolve(board)
		var timing: Dictionary = _clock_probe._timing_of(outcome["events"], board.units)
		var seconds: float = _clock_probe._minutes(timing, _clock_probe.PLAYER_SECONDS_PER_TURN) * 60.0
		_r["board_minutes"] += seconds / 60.0
		# El jugador esta en el tablero: la base sigue, el jugador no decide nada.
		var passed := 0.0
		while passed < seconds:
			_tick(DT)
			passed += DT
		CombatManager._emit_events(outcome["events"])
		if audit_wave:
			var last: Dictionary = _r["sieges"][-1] if not _r["sieges"].is_empty() else {}
			if not last.is_empty():
				last["waves_fought"] = int(last.get("waves_fought", 0)) + 1
				last["minutes"] = float(last.get("minutes", 0.0)) + seconds / 60.0
		CombatManager.end_encounter()
		await get_tree().process_frame

# ══════════════════════════════════════════════════════════════════════
# Decisiones
# ══════════════════════════════════════════════════════════════════════

func _decide() -> void:
	if CombatManager.is_board_open():
		return
	_feed_with_market()
	if _repair():
		return
	if _siege():
		return
	var step: Dictionary = Objectives.next_step()
	_r["last_step"] = step
	# Cuanto tiempo pasa el panel diciendo lo mismo: es donde se espera.
	var key: String = "%s:%s%s" % [step.get("kind", ""), step.get("id", ""),
		(":L%d" % int(step["level"])) if step.has("level") else ""]
	_r["step_time"][key] = float(_r["step_time"].get(key, 0.0)) + DECIDE_EVERY
	match String(step.get("kind", "")):
		"build":
			_try_build(String(step["id"]), step)
		"upgrade":
			_try_upgrade(step)
		"train", "rebuild":
			_try_train(String(step["id"]))
		"trade":
			_do_trades()
		"research":
			if TechTreeManager.start_research(String(step["id"])):
				_act("research %s" % String(step["id"]), true)
			elif not TechTreeManager.is_researching():
				_cover_with_market(Objectives.step_cost(step))
		"buy":
			if MarketManager.buy(String(step["id"]), int(step["amount"])):
				_r["trades"] += 1
				_act("buy %d %s (bolsa llena)" % [int(step["amount"]), String(step["id"])], false)
		"sell":
			if MarketManager.sell(String(step["id"]), int(step["amount"])):
				_r["trades"] += 1
				_act("sell %d %s (bolsa llena)" % [int(step["amount"]), String(step["id"])], false)
		_:
			pass
	_army_upkeep_guard()
	if bool(options.get("active", false)):
		_run_processes()

## Lo que haria cualquiera: lo roto se arregla en cuanto se puede, empezando por
## lo que da de comer. Nunca con la Tormenta encima (la volveria a romper).
func _repair() -> bool:
	if StormManager.is_storming() or StormManager.is_ashfall():
		return false
	var best: Node = null
	var best_rank := 99
	for info in GridManager.get_all_buildings():
		var node: Node = info["node"]
		if not BuildingHealth.is_damaged(node):
			continue
		var id: String = (info["data"] as BuildingData).id
		var ruined: bool = BuildingHealth.is_ruined(node)
		var rank := 5
		if id in ["sawmill", "gold_mine", "foundry", "refinery"]:
			rank = 0 if ruined else 3
		elif id in ["tower", "barracks", "headquarters"]:
			rank = 1 if ruined else 4
		elif id in ["house", "warehouse"]:
			rank = 2 if ruined else 4
		# Un rasguño en una estatua no se paga antes que una mina.
		if not ruined and BuildingHealth.get_health_ratio(node) > 0.6:
			rank += 2
		if rank < best_rank and bool(BuildingHealth.can_repair(node)["ok"]):
			best = node
			best_rank = rank
	if best == null:
		return false
	if BuildingHealth.repair(best):
		_r["repairs"] += 1
		_act("repair %s" % (GridManager.get_building_info(best)["data"] as BuildingData).id, false)
		return true
	return false

func _try_build(building_id: String, step: Dictionary) -> void:
	var data: BuildingData = Rules.load_building_data(building_id)
	if data == null:
		return
	var block: String = Rules.purchase_block_message(data)
	if block != "":
		if not ResourceManager.can_afford(data.get_cost()):
			_cover_with_market(data.get_cost())
		return
	if not String(step.get("why", "")).begins_with("OBJ_WHY_FEED") and not _keeps_reserve(data.get_cost()):
		return
	var spot: Dictionary = _spot_for(building_id, data)
	if spot.is_empty():
		_r["stuck"] = "sin hueco para %s" % building_id
		return
	var before: int = Rules.count_building(building_id)
	_placer._current_data = data
	_placer._rotation_steps = int(spot.get("rotation", 0))
	_placer._try_place(spot["origin"] as Vector2i)
	_placer._current_data = null
	_placer._rotation_steps = 0
	if Rules.count_building(building_id) > before:
		_act("build %s" % building_id, true)

func _try_upgrade(step: Dictionary) -> void:
	var building_id: String = String(step["id"])
	var level: int = int(step["level"])
	var node: Node = Objectives.upgrade_node(step)
	if node == null or ProductionManager.is_constructing(node):
		return
	var data: BuildingData = GridManager.get_building_info(node)["data"]
	var cost: Dictionary = GameConfig.get_upgrade_cost(data, level)
	if not ResourceManager.can_afford(cost):
		_cover_with_market(cost)
		return
	# La mejora final no se aplaza por el colchon: con la victoria a un clic nadie
	# se guarda la madera de la cena (y la bolsa llena ya no deja juntar mas).
	if building_id != "headquarters" and not _keeps_reserve(cost):
		return
	ProductionManager.start_upgrade(node, data, level)
	if ProductionManager.is_constructing(node):
		_act("upgrade %s L%d" % [building_id, level], true)

func _try_train(unit_id: String) -> void:
	# Con la ceniza encima lo que se entrena se pierde: el jugador espera.
	if StormManager.is_ashfall() or StormManager.is_storming():
		return
	if not bool(ArmyManager.can_train(unit_id)["ok"]):
		var cost: Dictionary = ArmyManager._convert_cost(GameConfig.get_unit_def(unit_id).get("cost", {}))
		if not ResourceManager.can_afford(cost):
			_cover_with_market(cost)
		return
	if not _keeps_reserve(ArmyManager._convert_cost(GameConfig.get_unit_def(unit_id).get("cost", {}))):
		return
	if ArmyManager.train(unit_id):
		_r["units_trained"] += 1
		_act("train %s" % unit_id, true)

## El colchon: lo que come la gente y cobra la tropa en RESERVE_TICKS ciclos (el
## doble con la Tormenta a la vista, que corta la produccion). Un jugador que ya
## vio el consejo "La gente come" no deja la caja a cero; el de la sonda tampoco.
## `--reserve=0` juega sin colchon (el jugador que se lo gasta todo).
func _keeps_reserve(cost: Dictionary) -> bool:
	var ticks: float = float(options.get("reserve", RESERVE_TICKS))
	if ticks <= 0.0:
		return true
	if StormManager.get_phase() != StormCycle.Phase.CALM:
		ticks *= 2.0
	var pop: float = float(PopulationManager.get_population())
	var upkeep := 0
	for unit_id in GameConfig.get_unit_ids():
		upkeep += ArmyManager.get_count(unit_id) * int(GameConfig.get_unit_def(unit_id).get("upkeep_gold", 0))
	var gold_left: int = ResourceManager.get_amount(ResourceManager.Type.GOLD) - int(cost.get(ResourceManager.Type.GOLD, 0))
	var wood_left: int = ResourceManager.get_amount(ResourceManager.Type.WOOD) - int(cost.get(ResourceManager.Type.WOOD, 0))
	return float(gold_left) >= (pop + float(upkeep)) * ticks and float(wood_left) >= pop * ticks

## Si la tropa ya no se puede pagar, no se entrena mas: lo decide el paso de
## Objectives. Aqui solo se mira que no quede nada entrenandose con la ceniza.
func _army_upkeep_guard() -> void:
	pass

## Cierra con el mercado lo que falta para `cost`, si lo que sobra alcanza. Sin
## vender lo que el propio coste pide ni bajar el oro de una reserva minima.
func _cover_with_market(cost: Dictionary) -> void:
	var need := {}
	for type in cost:
		var missing: int = int(cost[type]) - ResourceManager.get_amount(type)
		if missing > 0:
			need[ResourceManager.get_type_name(type)] = missing
	if need.is_empty():
		return
	var reserve := 60
	# Falta oro: vender lo que no pide el coste.
	if need.has("gold") and need.size() == 1:
		var gold_needed: int = int(need["gold"])
		for res in ["wood", "steel", "oil"]:
			if gold_needed <= 0:
				break
			var type: int = ResourceManager.name_to_type(res)
			if not ResourceManager.is_unlocked(type):
				continue
			var keep: int = int(cost.get(type, 0)) + (reserve if res == "wood" else 0)
			var spare: int = ResourceManager.get_amount(type) - keep
			if spare <= 0:
				continue
			var price: int = maxi(1, MarketManager.get_sell_price(res))
			var units: int = mini(spare, int(ceil(float(gold_needed) / float(price))))
			if units > 0 and MarketManager.sell(res, units):
				_r["trades"] += 1
				gold_needed -= units * price
				_act("sell %d %s" % [units, res], false)
		return
	# Falta otra cosa: comprarla si el oro sobra de verdad.
	if not need.has("gold"):
		var gold_left: int = ResourceManager.get_amount(ResourceManager.Type.GOLD) \
			- int(cost.get(ResourceManager.Type.GOLD, 0)) - reserve
		var total_price := 0
		for res in need:
			total_price += MarketManager.get_buy_price(res) * int(need[res])
		if total_price > gold_left or ResourceManager.get_free_space() < _sum(need):
			return
		for res in need:
			if MarketManager.buy(res, int(need[res])):
				_r["trades"] += 1
				_act("buy %d %s" % [int(need[res]), res], false)

## Sin oro para la comida de este ciclo, se vende lo que sobre: es lo que dice el
## consejo "La gente come" y lo que hace cualquiera antes de ver morir a su gente.
func _feed_with_market() -> void:
	var upkeep := 0
	for unit_id in GameConfig.get_unit_ids():
		upkeep += ArmyManager.get_count(unit_id) * int(GameConfig.get_unit_def(unit_id).get("upkeep_gold", 0))
	var due: int = PopulationManager.get_population() + upkeep
	var gold: int = ResourceManager.get_amount(ResourceManager.Type.GOLD)
	if gold >= due:
		return
	_cover_with_market({ResourceManager.Type.GOLD: due * 2})

func _do_trades() -> void:
	# Diez operaciones minimas y baratas: comprar y vender cinco de madera.
	if MarketManager.buy("wood", 5):
		_r["trades"] += 1
		_act("buy 5 wood", false)
	if MarketManager.sell("wood", 5):
		_r["trades"] += 1
		_act("sell 5 wood", false)

## La Regencia: se baja cuando la guarnicion es la que el jugador queria, las
## torres estan enteras y la moral no esta por los suelos.
func _siege() -> bool:
	if ProgressionManager.is_final_audit_lost():
		if ProgressionManager.can_resummon_final_audit() and _garrison_ready():
			if ProgressionManager.summon_final_audit():
				_act("resummon", true)
				return true
		return false
	if not ProgressionManager.is_final_audit_pending():
		return false
	if not _garrison_ready():
		return false
	if not _towers_whole():
		return false
	if StormManager.get_phase() != StormCycle.Phase.CALM:
		return false
	var garrison: Dictionary = CombatManager.get_garrison()
	if ProgressionManager.begin_final_audit():
		_r["sieges"].append({"t": _clock, "garrison": garrison,
			"waves": ProgressionManager.final_audit.wave_count(),
			"morale": PopulationManager.get_morale()})
		_act("siege", true)
		return true
	return false

func _garrison_ready() -> bool:
	var home: Dictionary = CombatManager.get_deployable_units()
	for unit_id in SIEGE_TARGET:
		if int(home.get(unit_id, 0)) < int(SIEGE_TARGET[unit_id]):
			return false
	return true

func _towers_whole() -> bool:
	for info in GridManager.get_all_buildings():
		if (info["data"] as BuildingData).id == "tower" and BuildingHealth.is_damaged(info["node"]):
			return false
	return true

## Jugador activo: el Nucleo convierte madera en mas madera y la mina oro en mas
## oro mientras no haya otra cosa que hacer, y mina a mano un yacimiento a la vez
## (gratis: 20 de madera cada 8 s o 20 de oro cada 12 s, hasta agotarlo). Nunca el
## ultimo bosque ni la ultima veta: sin ellos no se levanta otro extractor.
func _run_processes() -> void:
	_mine_by_hand()
	_run_recipes()

func _mine_by_hand() -> void:
	if StormManager.is_ashfall() or StormManager.is_storming():
		return
	if ResourceManager.get_free_space() < 40:
		return
	var busy := false
	var counts := {}
	for entry in _map._deposit_cells:
		if is_instance_valid(entry["node"]):
			counts[entry["id"]] = int(counts.get(entry["id"], 0)) + 1
			if ProcessManager.is_busy(entry["node"]):
				busy = true
	if busy:
		return
	var want: String = "gold_vein" if ResourceManager.get_amount(ResourceManager.Type.GOLD) \
		<= ResourceManager.get_amount(ResourceManager.Type.WOOD) else "forest"
	for entry in _map._deposit_cells:
		if entry["id"] != want or not is_instance_valid(entry["node"]) or int(counts.get(want, 0)) <= 1:
			continue
		if ProcessManager.start_mining(entry["node"], want):
			_act("mine %s" % want, false)
			return

func _run_recipes() -> void:
	for info in GridManager.get_all_buildings():
		var node: Node = info["node"]
		var id: String = (info["data"] as BuildingData).id
		if ProcessManager.is_busy(node) or ProductionManager.is_constructing(node):
			continue
		if StormManager.is_ashfall() or StormManager.is_storming():
			return
		var procs: Array = GameConfig.get_processes_for(id)
		for proc in procs:
			var pid: String = String(proc["id"])
			if not pid in ["wood_planks", "gem_extraction", "refined_lumber"]:
				continue
			if ResourceManager.get_free_space() < 80:
				continue
			if ProcessManager.start_process(node, proc):
				_act("process %s" % pid, false)
				break

# ══════════════════════════════════════════════════════════════════════
# Huecos
# ══════════════════════════════════════════════════════════════════════

func _spot_for(building_id: String, data: BuildingData) -> Dictionary:
	var center := Vector2i(GridManager.grid_width / 2, GridManager.grid_height / 2)
	if building_id == "refinery":
		for dep in _map.get_all_deposits():
			if dep["id"] != "oil_well":
				continue
			for ox in range(int(dep["cell_x"]), int(dep["cell_x"]) + int(dep["size_x"])):
				for oy in range(int(dep["cell_y"]), int(dep["cell_y"]) + int(dep["size_y"])):
					var origin := Vector2i(ox, oy)
					if bool(Rules.evaluate_placement("refinery", origin, data.grid_size, _map)["ok"]):
						return {"origin": origin, "rotation": 0}
		return {}
	var rule: Dictionary = GameConfig.get_deposit_rule(building_id)
	if not rule.is_empty():
		var spots: Array = _map.buildable_spots_near(String(rule["deposit"]), data.grid_size, int(rule["reach"]), 0)
		if spots.is_empty():
			return {}
		spots.sort_custom(func(a, b): return _dist(a["origin"], center) < _dist(b["origin"], center))
		var spot: Dictionary = spots[0]
		return {"origin": spot["origin"], "rotation": 1 if (spot["size"] as Vector2i) != data.grid_size else 0}
	# Construye donde quiera: lo mas cerca del Nucleo sin pisar la orla de ningun
	# yacimiento, que es donde iran los extractores.
	var reserved: Dictionary = {}
	for dep in _map.get_all_deposits():
		for x in range(int(dep["cell_x"]) - 1, int(dep["cell_x"]) + int(dep["size_x"]) + 1):
			for y in range(int(dep["cell_y"]) - 1, int(dep["cell_y"]) + int(dep["size_y"]) + 1):
				reserved[Vector2i(x, y)] = true
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for x in range(GridManager.grid_width - data.grid_size.x + 1):
		for y in range(GridManager.grid_height - data.grid_size.y + 1):
			var origin := Vector2i(x, y)
			var d: int = _dist(origin, center)
			if d >= best_d or not GridManager.can_place(origin, data.grid_size):
				continue
			var clash := false
			for c in GridManager.cells_for(origin, data.grid_size):
				if reserved.has(c):
					clash = true
					break
			if clash:
				continue
			best = origin
			best_d = d
	if best == Vector2i(-1, -1):
		return {}
	return {"origin": best, "rotation": 0}

func _dist(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func _first(building_id: String) -> Node:
	for info in GridManager.get_all_buildings():
		if (info["data"] as BuildingData).id == building_id:
			return info["node"]
	return null

func _sum(d: Dictionary) -> int:
	var total := 0
	for k in d:
		total += int(d[k])
	return total

# ══════════════════════════════════════════════════════════════════════
# Registro
# ══════════════════════════════════════════════════════════════════════

func _act(what: String, progress: bool) -> void:
	_r["actions"].append([_clock, what])
	if progress:
		_r["progress_times"].append(_clock)
	if bool(options.get("log", false)):
		print("  %6.1f min  %s" % [_clock / 60.0, what])

func _connect_probes() -> void:
	EventBus.milestone_completed.connect(func(id: String) -> void:
		if not _r["milestones"].has(id):
			_r["milestones"][id] = _clock)
	EventBus.storm_started.connect(func(sev: int) -> void:
		_r["storms"].append({"t": _clock, "severity": sev, "ruined": 0,
			"morale_before": PopulationManager.get_morale(), "towers": CombatManager.count_standing_towers(),
			"stored": ResourceManager.get_total_stored()}))
	EventBus.storm_false_alarm.connect(func(_d: int) -> void: _r["false_alarms"] += 1)
	EventBus.building_ruined.connect(func(_n: Node) -> void:
		_r["ruined"] += 1
		if not _r["storms"].is_empty():
			_r["storms"][-1]["ruined"] += 1)
	EventBus.tithe_resolved.connect(func(repelled: bool, taken: Dictionary) -> void:
		var entry := {"t": _clock, "repelled": repelled, "taken": taken.duplicate(),
			"garrison": CombatManager.roster_size(CombatManager.get_garrison()),
			"morale_after": PopulationManager.get_morale()}
		_r["tithes"].append(entry)
		if not _r["storms"].is_empty():
			_r["storms"][-1]["tithe"] = entry)
	EventBus.storage_overflow.connect(func(_res: String, lost: int, _cap: int) -> void: _r["overflow"] += lost)
	EventBus.population_starved.connect(func(deaths: int, _pop: int) -> void: _r["deaths_starve"] += deaths)
	EventBus.army_deserted.connect(func(_id: String, count: int) -> void: _r["deserted"] += count)
	EventBus.unit_died.connect(func(_uid: int, side: int) -> void:
		if side == Encounter.PLAYER:
			_r["units_lost"] += 1)
	EventBus.final_audit_lost.connect(func(wave: int) -> void:
		if not _r["sieges"].is_empty():
			_r["sieges"][-1]["lost_at"] = wave)
	EventBus.victory_achieved.connect(func(_stats: Dictionary) -> void:
		_r["victory_at"] = _clock
		_r["victory_stats"] = _stats.duplicate())
	EventBus.random_event_started.connect(func(id: String, _d: Dictionary) -> void:
		_r["events"] += 1
		if bool(options.get("log", false)):
			print("  %6.1f min  ! evento %s" % [_clock / 60.0, id]))
	EventBus.storm_phase_changed.connect(func(phase: int, _left: float) -> void:
		if bool(options.get("log", false)):
			print("  %6.1f min  ~ tormenta fase %d sev %d moral %d" % [_clock / 60.0, phase, StormManager.get_severity(), PopulationManager.get_morale()]))
	EventBus.tithe_resolved.connect(func(repelled: bool, taken: Dictionary) -> void:
		if bool(options.get("log", false)):
			print("  %6.1f min  $ diezmo %s %s moral %d" % [_clock / 60.0, "REPELIDO" if repelled else "cobrado", str(taken), PopulationManager.get_morale()]))

func _snapshot() -> Dictionary:
	return {
		"t": _clock,
		"gold": ResourceManager.get_amount(ResourceManager.Type.GOLD),
		"wood": ResourceManager.get_amount(ResourceManager.Type.WOOD),
		"steel": ResourceManager.get_amount(ResourceManager.Type.STEEL),
		"oil": ResourceManager.get_amount(ResourceManager.Type.OIL),
		"stored": ResourceManager.get_total_stored(),
		"cap": ResourceManager.get_storage_cap(),
		"pop": PopulationManager.get_population(),
		"max_pop": PopulationManager.get_max_population(),
		"morale": PopulationManager.get_morale(),
		"army": ArmyManager.get_save_data()["units"].duplicate(),
		"era": ProgressionManager.current_era,
	}

func _describe_state() -> String:
	var s: Dictionary = _snapshot()
	return "paso=%s era=%d oro=%d madera=%d acero=%d petroleo=%d bolsa=%d/%d pob=%d/%d moral=%d ejercito=%s" % [
		str(_r.get("last_step", {})), s["era"], s["gold"], s["wood"], s["steel"], s["oil"],
		s["stored"], s["cap"], s["pop"], s["max_pop"], s["morale"], str(s["army"])]

# ══════════════════════════════════════════════════════════════════════
# Salida
# ══════════════════════════════════════════════════════════════════════

const MILESTONE_ORDER := ["first_sawmill", "first_gold_mine", "first_warehouse", "era_2",
	"era_3", "military_ready", "market_10_trades", "hq_built", "hq_max"]

func _gaps(r: Dictionary) -> Dictionary:
	var times: Array = r["progress_times"].duplicate()
	var end_t: float = float(r["victory_at"]) if float(r["victory_at"]) >= 0.0 else float(r["end"]["t"])
	times.append(end_t)
	var dead := 0.0
	var longest := 0.0
	var count := 0
	var early_longest := 0.0
	var era2: float = float(r["milestones"].get("era_2", end_t))
	for i in range(1, times.size()):
		var gap: float = float(times[i]) - float(times[i - 1])
		longest = maxf(longest, gap)
		if float(times[i - 1]) < era2:
			early_longest = maxf(early_longest, gap)
		if gap > DEAD_WAIT:
			dead += gap
			count += 1
	return {"dead": dead, "longest": longest, "count": count, "early_longest": early_longest}

func _print_run(r: Dictionary) -> void:
	print("")
	print("=== semilla %d === yacimientos %s" % [r["seed"], str(r["deposits"])])
	var line := ""
	for id in MILESTONE_ORDER:
		line += "%s=%s " % [id, _mins(r["milestones"].get(id, -1.0))]
	print("hitos (min): " + line)
	for st in r["storms"]:
		var tithe: Dictionary = st.get("tithe", {})
		print("  tormenta %5s sev %d torres %d ruinas %d moral %d->%s bolsa %d | diezmo %s %s" % [
			_mins(st["t"]), st["severity"], st["towers"], st["ruined"], st["morale_before"],
			str(tithe.get("morale_after", "?")), st["stored"],
			"REPELIDO" if bool(tithe.get("repelled", false)) else "cobrado",
			str(tithe.get("taken", {}))])
	for sg in r["sieges"]:
		print("  asedio %s guarnicion %s oleadas %d/%d moral %d %s (%.1f min de tablero)" % [
			_mins(sg["t"]), str(sg["garrison"]), int(sg.get("waves_fought", 0)), sg["waves"],
			sg["morale"], "PERDIDO en %d" % int(sg["lost_at"]) if sg.has("lost_at") else "GANADO",
			float(sg.get("minutes", 0.0))])
	var g: Dictionary = _gaps(r)
	print("victoria %s | esperas>2min %d (%.0f min) | hueco mas largo %.1f min (antes de era 2: %.1f) | bolsa llena %.0f min | desbordado %d | hambre %d | desercion %d | bajas %d | entrenadas %d | reparaciones %d | falsas alarmas %d | eventos %d | tablero %.0f min" % [
		_mins(r["victory_at"]), g["count"], g["dead"] / 60.0, g["longest"] / 60.0, g["early_longest"] / 60.0,
		r["full_time"] / 60.0, r["overflow"], r["deaths_starve"], r["deserted"], r["units_lost"],
		r["units_trained"], r["repairs"], r["false_alarms"], r["events"], r["board_minutes"]])
	var waits: Array = []
	for key in r["step_time"]:
		waits.append([float(r["step_time"][key]), key])
	waits.sort_custom(func(a, b): return a[0] > b[0])
	var top := ""
	for i in range(mini(8, waits.size())):
		top += "%s=%.0f " % [waits[i][1], waits[i][0] / 60.0]
	print("  espera por paso (min): " + top)
	if r["stuck"] != "":
		print("  ATASCO: " + String(r["stuck"]))
	print("  final: " + str(r["end"]))

func _print_table(results: Array) -> void:
	print("")
	print("| semilla | serreria | mina | almacen | era 2 | era 3 | comandante | CG | CG nv3 | asedio | victoria | tormentas | diezmos repelidos | esperas>2min | hueco max | bolsa llena |")
	print("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
	for r in results:
		var m: Dictionary = r["milestones"]
		var repelled := 0
		for t in r["tithes"]:
			if bool(t["repelled"]):
				repelled += 1
		var g: Dictionary = _gaps(r)
		var siege_t: float = float(r["sieges"][0]["t"]) if not r["sieges"].is_empty() else -1.0
		print("| %d | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %d | %d/%d | %d (%.0f min) | %.1f min | %.0f min |" % [
			r["seed"], _mins(m.get("first_sawmill", -1.0)), _mins(m.get("first_gold_mine", -1.0)),
			_mins(m.get("first_warehouse", -1.0)), _mins(m.get("era_2", -1.0)), _mins(m.get("era_3", -1.0)),
			_mins(m.get("military_ready", -1.0)), _mins(m.get("hq_built", -1.0)), _mins(m.get("hq_max", -1.0)),
			_mins(siege_t), _mins(r["victory_at"]), r["storms"].size(), repelled, r["tithes"].size(),
			g["count"], g["dead"] / 60.0, g["longest"] / 60.0, r["full_time"] / 60.0])

func _mins(t) -> String:
	var f: float = float(t)
	if f < 0.0:
		return "—"
	return "%.0f" % (f / 60.0)
