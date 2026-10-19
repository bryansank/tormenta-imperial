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
##   9. las tres campanas (feat/tres-campanas): la mision que ¿QUE HACER? propone
##      en su segunda linea (campaign_step), en calma y lejos del Aviso, con lo
##      mas fuerte de su medio; y, con el CG a nivel 3, lo que pida la linea
##      (edificio, tropa o mision) hasta tener las tres. `--campaigns=0` juega
##      solo las que pida la linea (tras el CG nv3).
##
## Desde 2026-10-04 lo producido espera en los edificios: el jugador RECOGE
## (todo, cada `--collect=N` segundos, 60 por defecto, y en cuanto algo se
## llena) y CULTIVA (cultivo corto mientras la comida va justa, largo cuando
## sobra para diez minutos). La gente come comida, no madera ni oro.
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
## Cada cuanto pasa a recoger (segundos de juego), si nada se llena antes.
const COLLECT_EVERY := 60.0
## Minutos de comida por delante a partir de los que planta el cultivo medio y
## el largo. El largo llega de golpe cada 20 min: sin colchon, la gente pasa
## hambre esperandolo (medido en la semilla 1, 2026-10-04).
const MEDIUM_CROP_MINUTES := 8.0
const LONG_CROP_MINUTES := 25.0

var options: Dictionary = {}

var _scene: Node = null
var _placer: Node3D = null
var _map: Node = null
var _clock_probe: Object = null
var _clock := 0.0
var _decide_accum := 0.0
var _sample_accum := 0.0
var _collect_accum := 0.0
## Desbordamientos aun sin origen (se le pone el de la accion que se anota justo despues).
var _ov_pending: Array = []

# ── Registro de la partida ──
var _r: Dictionary = {}

func run() -> void:
	GameConfig.dev_mode = false
	GameConfig.time_multiplier = 1.0
	# Velocidad x1 siempre (la x2 de la partida vive en settings.cfg).
	if "game_speed" in GameConfig:
		GameConfig.set("game_speed", 1.0)
	# `--cfg.clave=valor` pisa un numero de GameConfig solo en esta corrida, para
	# medir un cambio antes de escribirlo (ej. --cfg.storm_morale_per_tick=0.25).
	for key in options:
		if String(key).begins_with("cfg."):
			var prop: String = String(key).substr(4)
			GameConfig.set(prop, str_to_var(String(options[key])))
			print("override %s = %s" % [prop, str(GameConfig.get(prop))])
	_clock_probe = load("res://tools/balance_probe.gd").new()
	_connect_probes()
	_connect_extra_probes()
	if _extras_on():
		print("jugador completo: extras de la 1.1 activados (--extras=1)")
	var results: Array = []
	for s in options.get("seeds", [1]):
		var result: Dictionary = await _play_seed(int(s))
		results.append(result)
		_print_run(result)
	_print_table(results)
	_print_extras_table(results)
	finished.emit(0)

# ══════════════════════════════════════════════════════════════════════
# Montaje
# ══════════════════════════════════════════════════════════════════════

func _open_colony(map_seed: int) -> void:
	# Cada colonia empieza de cero: ni partidas guardadas ni el guardado viejo.
	if FileAccess.file_exists("user://save_game.json"):
		DirAccess.remove_absolute(OS.get_user_data_dir().path_join("save_game.json"))
	var slots := preload("res://scripts/services/SaveSlots.gd")
	slots.remove_dir_recursive(slots.DIR)
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
	# La sonda juega como quien ya acabo el tutorial antes de empezar: con el
	# tutorial en marcha la tormenta de prueba y los eventos esperan (2026-10-19,
	# TutorialManager.blocks_interruptions) y la sonda no hace sus pasos. Asi la
	# prueba sigue llegando a su hora (storm_trial_at), como antes.
	TutorialManager.intro_seen = true
	TutorialManager.guide_state = TutorialManager.GUIDE_DONE
	TutorialManager.guide_finished_at = -1.0
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
		"collects": 0, "collected": {}, "crop_changes": 0, "full_stop": 0.0,
		"activity_times": [0.0], "after": {}, "overflow_by": {}, "step_log": [],
		# Extras de la 1.1 (se apuntan tambien sin --extras=1, para comparar).
		"extra_first": {}, "extra_builds": {}, "extra_no_spot": {}, "extra_units": {},
		"dock_food": 0, "dock_spoiled": 0, "coast_launched": 0, "coast_won": 0,
		"coast_lost": 0, "coast_abandoned": 0, "coast_skipped": 0, "coast_pending": false,
		# Tres campanas: minuto de cada mision ganada por medio, intentos fallidos.
		"campaign_won": {"land": [], "sea": [], "air": []}, "campaign_setbacks": 0,
		"campaign_done": {},
	}
	_extras_accum = 0.0
	_last_coast = -INF
	_clock = 0.0
	_decide_accum = 0.0
	_sample_accum = 0.0
	_collect_accum = 0.0
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
	if _r["victory_at"] >= 0.0 and float(options.get("after", 0.0)) > 0.0:
		await _play_after_victory(float(options.get("after", 0.0)) * 60.0)
	_r["farms"] = Rules.count_building("farm")
	# Consumo al final: casas, gente y comida que se come por minuto.
	_r["houses"] = Rules.count_building("house")
	_r["parts_end"] = ResourceManager.get_amount(ResourceManager.Type.PARTS)
	_r["food_per_min"] = float(PopulationManager.food_due()) * 60.0 		/ maxf(1.0, GameConfig.get_duration(GameConfig.consumption_interval))
	_close_colony()
	return _r

## Tras ganar se sigue jugando la colonia ("Continuar" de VictoryScreen): la
## mitad del tiempo pedido, un guardado y su carga de los servicios que llevan
## el final (Tormenta, Auditoria, modo), y la otra mitad. Cuenta lo que no
## deberia volver: tormentas, Diezmos, convocatorias.
func _play_after_victory(seconds: float) -> void:
	var a: Dictionary = {"storms": 0, "tithes": 0, "summons": 0, "phases": 0, "victories": 0}
	var on_storm := func(_s: int) -> void: a["storms"] += 1
	var on_tithe := func(_d: int) -> void: a["tithes"] += 1
	var on_summon := func(_w: int, _n: int) -> void: a["summons"] += 1
	var on_phase := func(p: int, _l: float) -> void:
		if p != StormCycle.Phase.CALM:
			a["phases"] += 1
	var on_victory := func(_st: Dictionary) -> void: a["victories"] += 1
	EventBus.storm_started.connect(on_storm)
	EventBus.tithe_demanded.connect(on_tithe)
	EventBus.final_audit_summoned.connect(on_summon)
	EventBus.storm_phase_changed.connect(on_phase)
	EventBus.victory_achieved.connect(on_victory)
	var before: Dictionary = _snapshot()
	a["step_before"] = String(Objectives.next_step().get("why", ""))
	var t := 0.0
	var reloaded := false
	while t < seconds:
		_tick(DT)
		t += DT
		_decide_accum += DT
		if _decide_accum >= DECIDE_EVERY:
			_decide_accum = 0.0
			_collect()
			_tend_farms()
			_feed_with_market()
		if not reloaded and t >= seconds / 2.0:
			reloaded = true
			var storm: Dictionary = StormManager.get_save_data()
			var prog: Dictionary = ProgressionManager.get_save_data()
			var mode: Dictionary = GameMode.get_save_data()
			var json: String = JSON.stringify({"storm": storm, "progression": prog, "game_mode": mode})
			var back: Dictionary = JSON.parse_string(json)
			StormManager.reset()
			GameMode.load_save_data(back["game_mode"])
			ProgressionManager.load_save_data(back["progression"])
			StormManager.load_save_data(back["storm"])
			ProgressionManager.migrate_legacy_capstone()
			a["halted_after_load"] = StormManager.is_halted()
			a["audit_after_load"] = ProgressionManager.final_audit.to_dict().get("state", "?") 				if ProgressionManager.final_audit != null else "none"
		if frame_ready(t):
			_sweep_labels()
			await get_tree().process_frame
	a["minutes"] = seconds / 60.0
	a["halted"] = StormManager.is_halted()
	a["step_after"] = String(Objectives.next_step().get("why", ""))
	a["resummon_possible"] = ProgressionManager.can_resummon_final_audit()
	a["gold_delta"] = int(_snapshot()["gold"]) - int(before["gold"])
	a["stored_before"] = int(before["stored"])
	a["stored_after"] = int(_snapshot()["stored"])
	EventBus.storm_started.disconnect(on_storm)
	EventBus.tithe_demanded.disconnect(on_tithe)
	EventBus.final_audit_summoned.disconnect(on_summon)
	EventBus.storm_phase_changed.disconnect(on_phase)
	EventBus.victory_achieved.disconnect(on_victory)
	_r["after"] = a

func frame_ready(t: float) -> bool:
	return int(t) % 300 == 0

func _tick(dt: float) -> void:
	if not _ov_pending.is_empty():
		_drain_overflow("produccion/combate")
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
	_collect_accum += dt
	if ResourceManager.get_free_space() <= int(ResourceManager.get_storage_cap() * 0.02):
		_r["full_time"] += dt
	# Tiempo-edificio parado por lleno (suma de todos los productores llenos).
	for node in ProductionManager._producing:
		if is_instance_valid(node) and ProductionManager.is_full(node):
			_r["full_stop"] += dt
	if _sample_accum >= SAMPLE_EVERY:
		_sample_accum = 0.0
		var snap: Dictionary = _snapshot()
		_r["samples"].append(snap)
		if bool(options.get("log", false)):
			print("  %6.1f min  · moral %d pob %d/%d oro %d madera %d comida %d acero %d petroleo %d bolsa %d/%d fase %d ejercito %s" % [
				_clock / 60.0, snap["morale"], snap["pop"], snap["max_pop"], snap["gold"], snap["wood"], snap["food"],
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
		# El jugador esta en el tablero: la base sigue, el jugador no decide nada
		# de la base, pero esta jugando (cuenta como actividad cada minuto).
		var passed := 0.0
		var since_mark := 0.0
		_r["activity_times"].append(_clock)
		while passed < seconds:
			_tick(DT)
			passed += DT
			since_mark += DT
			if since_mark >= 60.0:
				since_mark = 0.0
				_r["activity_times"].append(_clock)
		_r["activity_times"].append(_clock)
		CombatManager._emit_events(outcome["events"])
		if audit_wave:
			var last: Dictionary = _r["sieges"][-1] if not _r["sieges"].is_empty() else {}
			if not last.is_empty():
				last["waves_fought"] = int(last.get("waves_fought", 0)) + 1
				last["minutes"] = float(last.get("minutes", 0.0)) + seconds / 60.0
		CombatManager.end_encounter()
		# Entre un tablero y el siguiente (las oleadas del asedio) el jugador
		# vuelve un momento a la base: recoge y da de comer. Sin esto, 25 min de
		# asedio con todo esperando en los edificios mataban de hambre a la
		# colonia (medido 2026-10-12), cosa que una persona no dejaria pasar.
		_collect_accum = INF
		_collect()
		_tend_farms()
		_feed_with_market()
		await get_tree().process_frame

# ══════════════════════════════════════════════════════════════════════
# Decisiones
# ══════════════════════════════════════════════════════════════════════

func _decide() -> void:
	if CombatManager.is_board_open():
		return
	_collect()
	_tend_farms()
	_feed_with_market()
	if _repair():
		return
	if _siege():
		return
	_tidy_expedition()
	if _campaign_mission():
		return
	if _raid():
		return
	var step: Dictionary = Objectives.next_step()
	# El tutorial guiado (2026-10-16) pide el Laboratorio justo despues del
	# Almacen, antes de la Fundicion: el jugador que lo sigue lo levanta en la
	# era 1. `--tutorial=0` juega sin el (solo la linea de ¿QUE HACER?).
	if String(options.get("tutorial", "1")) != "0" and ProgressionManager.current_era == 1 \
			and String(step.get("kind", "")) == "build" and String(step.get("id", "")) == "foundry" \
			and Rules.count_building("laboratory") == 0:
		step = {"kind": "build", "id": "laboratory", "count": 1, "why": "OBJ_WHY_LABORATORY"}
	_r["last_step"] = step
	var skey: String = "%s:%s" % [step.get("kind", ""), step.get("id", "")]
	if _r["step_log"].is_empty() or String(_r["step_log"][-1][1]) != skey:
		_r["step_log"].append([_clock, skey])
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
		"make":
			_try_make(step)
		"campaign":
			# Tres campanas: la linea la pide (CG nv3 hecho y faltan campanas).
			_launch_campaign(String(step["id"]), true)
		"sortie":
			# La primera escaramuza: la columna que propone el panel. El tablero
			# lo juega el bucle de arriba como cualquier otro.
			var party: Dictionary = Objectives.first_sortie_party()
			if not party.is_empty() and CombatManager.launch_expedition(party, 0, CombatManager.is_first_sortie_due()):
				_act("first sortie", true)
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
	if _extras_on():
		_extras(step)
	_army_upkeep_guard()
	if bool(options.get("active", false)):
		_run_processes()

## Escaramuzas (2026-10-14): cuando la segunda linea de ¿QUE HACER?
## (Objectives.sortie_step) dice que conviene salir -repuestos para el nivel 3
## de un productor, el puesto avanzado que rebaja el Diezmo, una oferta nueva-,
## el jugador sale a una INCURSION (un combate), solo con la Tormenta en calma y
## sin asedio convocado, con lo mas fuerte de casa. "Resolver solo" si se puede.
## Las expediciones de tres combates no las juega (mapa y draft).
func _raid() -> bool:
	if Objectives.sortie_step().is_empty():
		return false
	if StormManager.get_phase() != StormCycle.Phase.CALM:
		return false
	# Lejos del siguiente Aviso: la columna fuera no defiende el Diezmo.
	var cycle: StormCycle = StormManager.get_cycle()
	if StormManager.is_armed() and cycle != null and float(cycle.seconds_left) < 240.0:
		return false
	var home: Dictionary = CombatManager.get_deployable_units()
	var party: Dictionary = {}
	var room: int = GameConfig.combat_deploy_cap
	for unit_id in ["vehicle", "artillery", "infantry"]:
		var n: int = mini(int(home.get(unit_id, 0)), room)
		if n > 0:
			party[unit_id] = n
			room -= n
	if party.is_empty():
		return false
	for offer in CombatManager.get_sortie_offers():
		if String(offer.get("kind", "")) != "raid":
			continue
		var preview: Dictionary = CombatManager.sortie_preview(offer, party)
		if float(preview.get("player_power", 0.0)) < float(preview.get("enemy_power", 0.0)):
			continue
		var parts_before: int = ResourceManager.get_amount(ResourceManager.Type.PARTS)
		if CombatManager.launch_sortie(int(offer.get("id", -1)), party, bool(preview.get("can_auto", false))):
			_r["raids"] = int(_r.get("raids", 0)) + 1
			_r["parts_before_raid"] = parts_before
			_act("raid (%s)" % String(Objectives.sortie_step().get("why", "")), true)
			return true
	return false

## Tres campanas: la segunda linea de ¿QUE HACER? (Objectives.campaign_step)
## propone una mision. El jugador razonable sale en calma, lejos del Aviso (la
## columna fuera no defiende el Impuesto) y si su columna no es mas floja que el
## enemigo mas duro de la mision.
func _campaign_mission() -> bool:
	if String(options.get("campaigns", "1")) == "0":
		return false
	var camp: Dictionary = Objectives.campaign_step()
	# El Leviatan sin acorazados devuelve un paso de entrenar, no la mision.
	if camp.is_empty() or String(camp.get("kind", "")) != "campaign":
		return false
	if StormManager.get_phase() != StormCycle.Phase.CALM:
		return false
	var cycle: StormCycle = StormManager.get_cycle()
	if StormManager.is_armed() and cycle != null and float(cycle.seconds_left) < 300.0:
		return false
	return _launch_campaign(String(camp["id"]), false)

## Lanza la mision que toca de `domain` con lo mas fuerte de su medio que haya en
## casa (hasta el tope del tablero). En tierra deja en casa la mitad de la
## guarnicion salvo que la linea la pida (`forced`, tras el CG nv3). Sin
## `forced`, solo si la fuerza no es menor que la del enemigo.
func _launch_campaign(domain: String, forced: bool) -> bool:
	if CombatManager.campaign_lock_reason(domain) != "":
		return false
	var home: Dictionary = CombatManager.campaign_units_home(domain)
	var ids: Array = home.keys()
	ids.sort_custom(func(a, b) -> bool:
		return int(GameConfig.get_unit_def(a).get("power", 0)) > int(GameConfig.get_unit_def(b).get("power", 0)))
	var total := 0
	for unit_id in ids:
		total += int(home[unit_id])
	var room: int = GameConfig.combat_deploy_cap
	if domain == "land" and not forced:
		room = mini(room, maxi(1, total - maxi(HOME_LAND_MIN, int(ceil(total / 2.0)))))
	var party: Dictionary = {}
	for unit_id in ids:
		var n: int = mini(int(home[unit_id]), room)
		if n > 0:
			party[unit_id] = n
			room -= n
	if party.is_empty():
		return false
	if not forced:
		var preview: Dictionary = CombatManager.sortie_preview(CombatManager.campaign_offer(domain), party)
		if float(preview.get("player_power", 0.0)) < float(preview.get("enemy_power", 0.0)):
			return false
	if CombatManager.launch_campaign_mission(domain, party):
		_act("campaign %s m%d %s" % [domain, CombatManager.campaign_won(domain) + 1, str(party)], true)
		return true
	return false

## Una columna que volvio (o una expedicion que pide elegir camino) no se queda
## colgada: sin esto el asedio esperaria para siempre a "la columna fuera".
func _tidy_expedition() -> void:
	if not CombatManager.has_active_expedition() or CombatManager.is_board_open():
		return
	# El jugador completo elige la primera carta del draft y sigue la ruta (una
	# mision de costa puede ser de varios combates); el normal abandona como antes.
	# Las misiones de campana son de varios combates: siempre la primera carta.
	var run: Expedition = CombatManager.get_expedition()
	if CombatManager.has_pending_draft() and (_extras_on() or (run != null and run.is_campaign())):
		CombatManager.apply_draft(0)
	for i in range(4):
		if CombatManager.select_node(i):
			return
	CombatManager.abandon_expedition()

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
		if id in ["farm", "sawmill", "gold_mine", "foundry", "refinery"]:
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
		elif id == "tower":
			_make_for_repair(node)
	if best == null:
		return false
	if BuildingHealth.repair(best):
		_r["repairs"] += 1
		_act("repair %s" % (GridManager.get_building_info(best)["data"] as BuildingData).id, false)
		return true
	return false

## Una torre pide vigas para repararse; sin ellas no se repara nunca y el
## asedio espera para siempre (las torres tienen que estar enteras). Se fabrican.
func _make_for_repair(node: Node) -> void:
	var cost: Dictionary = BuildingHealth.repair_cost(node)
	for type in cost:
		if not ResourceManager.is_material(int(type)):
			continue
		var short: int = int(cost[type]) - ResourceManager.get_amount(type)
		if short <= 0:
			continue
		var mat: String = ResourceManager.get_type_name(type)
		_try_make({"kind": "make", "id": mat, "building": GameConfig.get_material_source(mat), "amount": short})

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
	_pave_to(spot["origin"] as Vector2i, spot.get("size", data.grid_size) as Vector2i)
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
	var upkeep := 0
	for unit_id in GameConfig.get_unit_ids():
		upkeep += ArmyManager.get_count(unit_id) * int(GameConfig.get_unit_def(unit_id).get("upkeep_gold", 0))
	# La gente come comida (2026-10-04): el oro de la caja es para la tropa, y
	# ninguna obra cuesta comida, asi que la reserva de comida no la toca nadie.
	var gold_left: int = ResourceManager.get_amount(ResourceManager.Type.GOLD) - int(cost.get(ResourceManager.Type.GOLD, 0))
	return float(gold_left) >= float(upkeep) * ticks

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
			# El oro de la venta tiene que caber: con la bolsa llena se tiraria.
			if price > 1:
				units = mini(units, ResourceManager.get_free_space() / (price - 1))
			if units < 5:
				continue
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
		# Comprar paga con oro que sale de la bolsa: hace sitio, no lo pide.
		if total_price > gold_left or ResourceManager.get_free_space() + total_price < _sum(need):
			return
		for res in need:
			if MarketManager.buy(res, int(need[res])):
				_r["trades"] += 1
				_act("buy %d %s" % [int(need[res]), res], false)

## Sin comida para este ciclo, se compra (con Mercado); sin oro para el sueldo
## de la tropa, se vende lo que sobre: lo que dice el consejo "La gente come" y lo
## que hace cualquiera antes de ver morir a su gente.
func _feed_with_market() -> void:
	var upkeep := 0
	for unit_id in GameConfig.get_unit_ids():
		upkeep += ArmyManager.get_count(unit_id) * int(GameConfig.get_unit_def(unit_id).get("upkeep_gold", 0))
	var food_due: int = PopulationManager.food_due()
	# Con la Tormenta a la vista las granjas van a rendir el 15%: se hace acopio
	# para diez ciclos (cinco minutos), como haria quien ya paso hambre una vez.
	var cycles: int = 2 if StormManager.get_phase() == StormCycle.Phase.CALM else 10
	if ProgressionManager.current_phase >= GameConfig.Phase.SETTLEMENT \
			and ResourceManager.get_amount(ResourceManager.Type.FOOD) < food_due * cycles / 2 \
			and Rules.count_building("market") > 0:
		var want: int = food_due * cycles - ResourceManager.get_amount(ResourceManager.Type.FOOD)
		var price: int = maxi(1, MarketManager.get_buy_price("food"))
		var can: int = mini(want, (ResourceManager.get_amount(ResourceManager.Type.GOLD) - upkeep) / price)
		if can > 0 and MarketManager.buy("food", can):
			_r["trades"] += 1
			_act("buy %d food (hambre)" % can, false)
	var gold: int = ResourceManager.get_amount(ResourceManager.Type.GOLD)
	if upkeep <= 0 or gold >= upkeep:
		return
	_cover_with_market({ResourceManager.Type.GOLD: upkeep * 2})

## Recoger: todo, cada COLLECT_EVERY segundos o en cuanto algo se llena. Lo que
## no cabe en la bolsa se queda en el edificio (nada se tira).
func _collect() -> void:
	var due: bool = _collect_accum >= float(options.get("collect", COLLECT_EVERY))
	if not due:
		for node in ProductionManager._producing:
			if is_instance_valid(node) and ProductionManager.is_full(node):
				due = true
				break
	if not due:
		return
	_collect_accum = 0.0
	# Con sitio de sobra se recoge todo. Con la bolsa por encima del 75%, solo lo
	# que hace falta: lo que le falta al paso (y a su receta), comida si va justa y
	# oro si no llega para la tropa. Lo demas espera en su edificio (parado).
	var got: Dictionary = {}
	if ResourceManager.get_total_stored() < int(float(ResourceManager.get_storage_cap()) * 0.75):
		got = ProductionManager.collect_all()
	else:
		var wanted: Dictionary = {}
		var step: Dictionary = _r.get("last_step", {})
		for res in Objectives.missing_for(step):
			wanted[String(res)] = true
			if ResourceManager.is_material_name(String(res)):
				for input in Objectives.material_recipe(String(res)).get("cost", {}):
					wanted[String(input)] = true
		if String(step.get("kind", "")) == "make":
			for input in Objectives.material_recipe(String(step["id"])).get("cost", {}):
				wanted[String(input)] = true
		if ResourceManager.get_amount(ResourceManager.Type.FOOD) < PopulationManager.food_due() * 12:
			wanted["food"] = true
		if ResourceManager.get_amount(ResourceManager.Type.GOLD) < 200:
			wanted["gold"] = true
		for node in ProductionManager._stock.keys():
			if not is_instance_valid(node):
				continue
			var hit := false
			for res in ProductionManager.get_stock(node):
				if wanted.has(res):
					hit = true
			if not hit:
				continue
			var part: Dictionary = ProductionManager.collect(node)
			for res in part:
				got[res] = int(got.get(res, 0)) + int(part[res])
	if got.is_empty():
		return
	_r["collects"] += 1
	for res in got:
		_r["collected"][res] = int(_r["collected"].get(res, 0)) + int(got[res])

## Cultivar: el corto mientras la comida va justa (da enseguida), el largo
## cuando hay para LONG_CROP_MINUTES (rinde mas por minuto). Solo se cambia con
## el campo recien cosechado, para no tirar lo que esta creciendo.
func _tend_farms() -> void:
	var due_per_min: float = float(PopulationManager.food_due()) * 60.0 \
		/ maxf(1.0, GameConfig.get_duration(GameConfig.consumption_interval))
	var food_ahead: float = float(ResourceManager.get_amount(ResourceManager.Type.FOOD)) \
		+ float(ProductionManager.get_all_stock().get("food", 0))
	var want: String = "crop_short"
	if food_ahead >= due_per_min * LONG_CROP_MINUTES:
		want = "crop_long"
	elif food_ahead >= due_per_min * MEDIUM_CROP_MINUTES:
		want = "crop_medium"
	for info in GridManager.get_all_buildings():
		if (info["data"] as BuildingData).id != ProductionManager.FARM_ID:
			continue
		var node: Node = info["node"]
		if ProductionManager.get_crop(node) == want:
			continue
		if ProductionManager.get_cycle_progress(node) > 0.05:
			continue
		if ProductionManager.plant_crop(node, want):
			_r["crop_changes"] += 1

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
## Fabrica el material que pide el paso en el primer edificio libre que lo haga;
## si falta el recurso de la receta, se cubre en el mercado como cualquier coste.
func _try_make(step: Dictionary) -> void:
	var recipe: Dictionary = Objectives.material_recipe(String(step["id"]))
	if recipe.is_empty():
		return
	# Lotes (2026-10-14): tantas vueltas como pide el paso y caben (max_batch),
	# en su taller y, si los talleres estan ocupados, tambien en el Nucleo (que
	# hace las recetas de todos, x1.5 mas lento).
	var per_run: int = int((recipe.get("produces", {}) as Dictionary).get(String(step["id"]), 1))
	var runs_wanted: int = maxi(1, int(ceil(float(int(step.get("amount", 1))) / float(maxi(1, per_run)))))
	var started := false
	for pass_core in [false, true]:
		for info in GridManager.get_all_buildings():
			var node: Node = info["node"]
			var bid: String = (info["data"] as BuildingData).id
			if pass_core and bid != "nucleo":
				continue
			if not pass_core and bid != String(step.get("building", "")):
				continue
			if ProcessManager.is_busy(node) or ProductionManager.is_constructing(node):
				continue
			var proc: Dictionary = recipe
			if pass_core:
				proc = {}
				for extra in GameConfig.get_core_extra_processes():
					if String(extra.get("id", "")) == String(recipe.get("id", "")):
						proc = extra
				if proc.is_empty():
					continue
			var n: int = clampi(mini(runs_wanted, ProcessManager.max_batch(proc)), 1, GameConfig.process_batch_max)
			if ProcessManager.start_process(node, proc, n):
				_act("make %s x%d%s" % [String(step["id"]), n, " (nucleo)" if pass_core else ""], false)
				runs_wanted -= n
				started = true
				if runs_wanted <= 0:
					return
	if not started:
		_cover_with_market(Objectives.step_cost(step))

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
		# Desde 2026-09-28 minar pide carretera hasta la veta y dos obreros
		# libres. Sin esto el jugador activo no minaba nunca (todas las vetas
		# daban MINE_NEEDS_ROAD) y la sonda no podia medir el minado a mano: una
		# persona tiende la carretera. Solo si es corta (<= 4 tramos).
		var node: Node = entry["node"]
		if ProcessManager.mining_blocker(node) == "MINE_NEEDS_ROAD":
			var route: Variant = Rules.road_route(node.get_meta("cell", Vector2i(-1, -1)),
				node.get_meta("deposit_size", Vector2i(2, 2)))
			if route == null or (route as Array).size() > 4:
				continue
			_pave_to(node.get_meta("cell", Vector2i(-1, -1)), node.get_meta("deposit_size", Vector2i(2, 2)))
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
# Extras de la 1.1 (`--extras=1` o `--player=completo`)
# ══════════════════════════════════════════════════════════════════════
#
# El jugador "completo": ademas de seguir ¿QUE HACER?, levanta lo nuevo de la
# 1.1 cuando aporta (Muelle de pesca, edificios utiles, Astillero, Aerodromo),
# entrena algo de mar y aire y lo saca a las misiones de costa. Una accion de
# extras como mucho por vistazo, con las mismas reglas que un clic
# (rango, tope, requisitos, obreros, coste, evaluate_placement, carretera
# automatica pagada a 1 oro el tramo). Sin la opcion nada de esto corre y la
# sonda juega exactamente como antes.

## Los edificios nuevos de la 1.1 cuyo primer minuto se apunta.
const EXTRA_BUILDINGS := ["fishing_dock", "windmill", "silo", "tavern", "carpentry", "well",
	"lighthouse", "fuel_depot", "shipyard", "aerodrome"]
## Las unidades de mar y aire.
const EXTRA_UNITS := ["torpedo_boat", "gunboat", "dreadnought", "fighter", "bomber", "airship"]
const LAND_UNITS := ["vehicle", "artillery", "infantry"]
## Flota que quiere tener el jugador completo (por era): pocas y caras.
const FLEET_TARGET := {
	2: {"gunboat": 1, "torpedo_boat": 1},
	3: {"gunboat": 2, "torpedo_boat": 1, "fighter": 2, "bomber": 1},
}
## Segundos entre dos misiones de costa.
const COAST_EVERY := 6.0 * 60.0
## Unidades de tierra que se quedan siempre en casa (guarnicion del Diezmo) al
## sacar una columna de costa; como minimo tambien la mitad de las que hay.
const HOME_LAND_MIN := 2
## Cada cuanto (s) mira el jugador si le falta un edificio util.
const UTILITY_EVERY := 20.0

var _extras_accum := 0.0
var _last_coast := -INF

func _extras_on() -> bool:
	return String(options.get("extras", "0")) == "1" or String(options.get("player", "")) == "completo"

## Una decision de extras por vistazo (las prioridades, de arriba abajo).
func _extras(step: Dictionary) -> void:
	if CombatManager.is_board_open():
		return
	if _coast_mission():
		return
	if _extra_dock(step):
		return
	if _extra_fleet_building(step):
		return
	if _extra_utility(step):
		return
	_extra_train()

## ¿Se puede pagar `cost` sin robarle al paso principal? Si el paso se puede
## pagar tambien despues del extra, si; si no, solo cuando el extra no pasa del
## 25 % de lo que hay de cada recurso que pide (lo barato no retrasa la linea).
## `urgent` (hambre) se salta la regla del 25 %. Siempre con el colchon de la tropa.
func _extra_affordable(cost: Dictionary, step: Dictionary, urgent: bool = false) -> bool:
	if not ResourceManager.can_afford(cost) or not _keeps_reserve(cost):
		return false
	if urgent:
		return true
	var step_cost: Dictionary = Objectives.step_cost(step) if not step.is_empty() else {}
	var both_ok := true
	for type in step_cost:
		if ResourceManager.get_amount(type) < int(step_cost[type]) + int(cost.get(type, 0)):
			both_ok = false
			break
	if both_ok:
		return true
	for type in cost:
		if ResourceManager.is_material(int(type)):
			continue
		if int(cost[type]) > int(ResourceManager.get_amount(type) * 0.25):
			return false
	return true

## Lo que falta de materiales en `cost` se manda a fabricar (taller libre o
## Nucleo). Devuelve true si faltaba algo.
func _make_missing_materials(cost: Dictionary) -> bool:
	var short_any := false
	for type in cost:
		if not ResourceManager.is_material(int(type)):
			continue
		var short: int = int(cost[type]) - ResourceManager.get_amount(type)
		if short <= 0:
			continue
		short_any = true
		var mat: String = ResourceManager.get_type_name(type)
		var src: String = GameConfig.get_material_source(mat)
		if src != "" and Rules.count_building(src) > 0:
			_try_make({"kind": "make", "id": mat, "building": src, "amount": short})
	return short_any

## Levanta un extra: comprueba lo mismo que el panel CONSTRUIR, busca hueco con
## las reglas del juego, paga la carretera y coloca con _try_place (girado al
## agua si es el Astillero, como el fantasma del juego).
func _build_extra(building_id: String, step: Dictionary, urgent: bool = false) -> bool:
	var data: BuildingData = Rules.load_building_data(building_id)
	if data == null:
		return false
	if not Rules.check_rank(building_id) or not Rules.check_building_limit(building_id) \
			or not Rules.check_prerequisites(building_id):
		return false
	if data.workers_required > 0 and PopulationManager.get_free_workers() < data.workers_required:
		return false
	var cost: Dictionary = data.get_cost()
	if _make_missing_materials(cost):
		return false
	if not _extra_affordable(cost, step, urgent):
		return false
	var spot: Dictionary = _extra_spot(building_id, data)
	if spot.is_empty():
		_r["extra_no_spot"][building_id] = int(_r["extra_no_spot"].get(building_id, 0)) + 1
		return false
	var origin: Vector2i = spot["origin"]
	var size: Vector2i = spot.get("size", data.grid_size)
	# La carretera sale de la caja como en el juego (1 oro por tramo).
	var route: Variant = Rules.road_route(origin, size)
	if route != null and (route as Array).size() > 0:
		var with_route: Dictionary = cost.duplicate()
		with_route[ResourceManager.Type.GOLD] = int(with_route.get(ResourceManager.Type.GOLD, 0)) + (route as Array).size()
		if not ResourceManager.can_afford(with_route):
			return false
	_pave_to(origin, size)
	var before: int = Rules.count_building(building_id)
	_placer._current_data = data
	_placer._rotation_steps = int(spot.get("rotation", 0))
	_placer._try_place(origin)
	_placer._current_data = null
	_placer._rotation_steps = 0
	if Rules.count_building(building_id) > before:
		_r["extra_builds"][building_id] = int(_r["extra_builds"].get(building_id, 0)) + 1
		_act("extra %s" % building_id, true)
		return true
	return false

## Hueco para un extra: el Muelle por la regla de su banco de peces; el Astillero
## en la costa, mirando al agua; el Molino junto a las Granjas; la Taberna junto
## a las casas; el Pozo junto a la produccion; el Faro en la costa si cabe; el
## resto donde el jugador construye siempre (cerca del Nucleo, sin orlas).
func _extra_spot(building_id: String, data: BuildingData) -> Dictionary:
	var on_coast := func(o: Vector2i) -> bool: return Rules.touches_shore(o, data.grid_size)
	match building_id:
		"fishing_dock":
			return _spot_for(building_id, data)
		"shipyard":
			return _spot_scan(data, on_coast, [], 0, true)
		"windmill":
			return _spot_scan(data, Callable(), ["farm"], GameConfig.windmill_radius, false, 2)
		"tavern":
			return _spot_scan(data, Callable(), ["house"], GameConfig.tavern_radius, false, 2)
		"well":
			return _spot_scan(data, Callable(), ["farm", "sawmill", "gold_mine", "foundry", "refinery", "house"],
				GameConfig.well_radius, false, 3)
		"lighthouse":
			var s: Dictionary = _spot_scan(data, on_coast, [], 0, false)
			return s if not s.is_empty() else _spot_for(building_id, data)
		_:
			return _spot_for(building_id, data)

## Recorre la rejilla buscando el mejor origen: `filter` (opcional) lo acepta;
## `near_ids` + `radius` piden al menos `min_near` edificios de esos tipos a esa
## distancia (Chebyshev de borde a borde, como UtilityEffects, con una casilla
## de margen). Gana el que mas cubre y, a igualdad, el mas cercano al Nucleo.
## `face_water`: el giro que pone la darsena al agua (Rules.steps_facing_water,
## el mismo que el fantasma). Siempre termina en evaluate_placement.
func _spot_scan(data: BuildingData, filter: Callable, near_ids: Array, radius: int,
		face_water: bool, min_near: int = 1) -> Dictionary:
	var center := Vector2i(GridManager.grid_width / 2, GridManager.grid_height / 2)
	var reserved: Dictionary = {}
	for dep in _map.get_all_deposits():
		for x in range(int(dep["cell_x"]) - 1, int(dep["cell_x"]) + int(dep["size_x"]) + 1):
			for y in range(int(dep["cell_y"]) - 1, int(dep["cell_y"]) + int(dep["size_y"]) + 1):
				reserved[Vector2i(x, y)] = true
	var targets: Array = []
	if not near_ids.is_empty():
		for info in GridManager.get_all_buildings():
			if (info["data"] as BuildingData).id in near_ids:
				targets.append([info["origin_cell"] as Vector2i, (info["data"] as BuildingData).grid_size])
		if targets.size() < min_near:
			return {}
	var cands: Array = []
	for x in range(GridManager.grid_width - data.grid_size.x + 1):
		for y in range(GridManager.grid_height - data.grid_size.y + 1):
			var origin := Vector2i(x, y)
			if not GridManager.can_place(origin, data.grid_size):
				continue
			var clash := false
			for c in GridManager.cells_for(origin, data.grid_size):
				if reserved.has(c):
					clash = true
					break
			if clash:
				continue
			if filter.is_valid() and not bool(filter.call(origin)):
				continue
			var covered := 0
			for t in targets:
				if _gap(origin, data.grid_size, t[0], t[1]) <= maxi(1, radius - 1):
					covered += 1
			if not near_ids.is_empty() and covered < min_near:
				continue
			cands.append([-covered, _dist(origin, center), origin])
	cands.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var tries := 0
	for c in cands:
		tries += 1
		if tries > 60:
			break
		var origin: Vector2i = c[2]
		if not bool(Rules.evaluate_placement(data.id, origin, data.grid_size, _map)["ok"]):
			continue
		var rot := 0
		if face_water:
			rot = maxi(0, Rules.steps_facing_water(data.id, origin, data.grid_size, false))
		return {"origin": origin, "rotation": rot, "size": data.grid_size}
	return {}

## Distancia de borde a borde entre dos huellas (Chebyshev; 1 = pegadas).
func _gap(o1: Vector2i, s1: Vector2i, o2: Vector2i, s2: Vector2i) -> int:
	var dx: int = maxi(0, maxi(o2.x - (o1.x + s1.x - 1), o1.x - (o2.x + s2.x - 1)))
	var dy: int = maxi(0, maxi(o2.y - (o1.y + s1.y - 1), o1.y - (o2.y + s2.y - 1)))
	return maxi(dx, dy)

## Comida por delante en minutos (en caja y esperando en los edificios).
func _food_minutes() -> float:
	var due_per_min: float = float(PopulationManager.food_due()) * 60.0 \
		/ maxf(1.0, GameConfig.get_duration(GameConfig.consumption_interval))
	var ahead: float = float(ResourceManager.get_amount(ResourceManager.Type.FOOD)) \
		+ float(ProductionManager.get_all_stock().get("food", 0))
	return ahead / maxf(0.1, due_per_min)

## Muelle de pesca: en cuanto la comida va justa (menos de MEDIUM_CROP_MINUTES
## por delante), aunque cueste; si no, hasta dos mientras sea barato (cabe).
func _extra_dock(step: Dictionary) -> bool:
	var docks: int = Rules.count_building("fishing_dock")
	var hungry: bool = _food_minutes() < MEDIUM_CROP_MINUTES
	if not hungry and docks >= 2:
		return false
	return _build_extra("fishing_dock", step, hungry)

## Astillero (era 2) y Aerodromo (era 3): lo que propone la segunda linea de
## ¿QUE HACER? (Objectives.fleet_step), en calma.
func _extra_fleet_building(step: Dictionary) -> bool:
	if StormManager.get_phase() != StormCycle.Phase.CALM:
		return false
	var fleet: Dictionary = Objectives.fleet_step()
	if fleet.is_empty():
		return false
	return _build_extra(String(fleet["id"]), step)

## Edificios utiles cuando aportan, uno a la vez y cada UTILITY_EVERY segundos.
func _extra_utility(step: Dictionary) -> bool:
	_extras_accum += DECIDE_EVERY
	if _extras_accum < UTILITY_EVERY:
		return false
	_extras_accum = 0.0
	var farms: int = Rules.count_building("farm")
	var houses: int = Rules.count_building("house")
	var cap: int = ResourceManager.get_storage_cap()
	var tight: bool = ResourceManager.get_total_stored() > int(cap * 0.8)
	var wants: Array = []
	# Molino: un molino por cada dos Granjas (+20 % a las que cubre), hasta dos.
	if farms >= 2 and Rules.count_building("windmill") < mini(2, farms / 2):
		wants.append("windmill")
	# Silo: la bolsa aprieta y hay comida que sacar de ella.
	if tight and farms >= 1 and ResourceManager.get_amount(ResourceManager.Type.FOOD) > 150 \
			and Rules.count_building("silo") < 2:
		wants.append("silo")
	# Deposito de combustible: la bolsa aprieta y el petroleo pesa en ella.
	if tight and ResourceManager.get_amount(ResourceManager.Type.OIL) > 200 \
			and Rules.count_building("fuel_depot") < 2:
		wants.append("fuel_depot")
	# Taberna: casas que crecer y comida de sobra para pagarla (diez minutos).
	if houses >= 2 and farms >= 1 and _food_minutes() > 10.0 and Rules.count_building("tavern") < 1:
		wants.append("tavern")
	# Pozo y Faro: cuando la Tormenta de verdad ya esta armada.
	if StormManager.is_armed():
		if Rules.count_building("well") < 2:
			wants.append("well")
		if Rules.count_building("lighthouse") < 1:
			wants.append("lighthouse")
	# Carpinteria: tablones sin parar el Aserradero, desde la era 2.
	if ProgressionManager.current_era >= 2 and Rules.count_building("carpentry") < 1:
		wants.append("carpentry")
	for id in wants:
		if _build_extra(String(id), step):
			return true
	return false

## Flota de mar y aire: la de FLEET_TARGET de la era, en calma, sin pasar del
## tope de tropa (can_train) ni del colchon. El material que pida se fabrica antes.
func _extra_train() -> void:
	if StormManager.get_phase() != StormCycle.Phase.CALM:
		return
	if ProgressionManager.is_final_audit_active():
		return
	var target: Dictionary = FLEET_TARGET.get(mini(3, ProgressionManager.current_era), {})
	for unit_id in target:
		if ArmyManager.get_count(unit_id) + _in_training(unit_id) >= int(target[unit_id]):
			continue
		if not ArmyManager.is_unlocked(unit_id):
			continue
		var cost: Dictionary = ArmyManager._convert_cost(GameConfig.get_unit_def(unit_id).get("cost", {}))
		if not bool(ArmyManager.can_train(unit_id)["ok"]) and ResourceManager.can_afford(cost):
			continue
		if _make_missing_materials(cost):
			return
		if not bool(ArmyManager.can_train(unit_id)["ok"]):
			continue
		if not _extra_affordable(cost, _r.get("last_step", {})):
			continue
		if ArmyManager.train(unit_id):
			_r["units_trained"] += 1
			_act("extra train %s" % unit_id, true)
			return

func _in_training(unit_id: String) -> int:
	var n := 0
	for t in ArmyManager.get_training():
		if String((t as Dictionary).get("id", "")) == unit_id:
			n += 1
	return n

## Mision de costa: una oferta del tablon con agua, cada COAST_EVERY, en calma y
## lejos del siguiente Aviso, con barcos y aviones al frente y la tierra que
## sobre de la guarnicion (en casa quedan al menos HOME_LAND_MIN de tierra y la
## mitad). Solo si la columna no es mas floja que el enemigo; "resolver solo" si
## el juego lo deja (incursion con el doble de fuerza).
func _coast_mission() -> bool:
	if _clock - _last_coast < COAST_EVERY:
		return false
	if CombatManager.has_active_expedition() or StormManager.get_phase() != StormCycle.Phase.CALM:
		return false
	if ProgressionManager.is_final_audit_pending() or ProgressionManager.is_final_audit_active():
		return false
	var cycle: StormCycle = StormManager.get_cycle()
	if StormManager.is_armed() and cycle != null and float(cycle.seconds_left) < 300.0:
		return false
	var home: Dictionary = CombatManager.get_deployable_units()
	var party: Dictionary = {}
	var room: int = GameConfig.combat_deploy_cap
	for unit_id in EXTRA_UNITS:
		var n: int = mini(int(home.get(unit_id, 0)), room)
		if n > 0:
			party[unit_id] = n
			room -= n
	if party.is_empty():
		return false
	var land_total := 0
	for unit_id in LAND_UNITS:
		land_total += int(home.get(unit_id, 0))
	var land_free: int = maxi(0, land_total - maxi(HOME_LAND_MIN, int(ceil(land_total / 2.0))))
	for unit_id in LAND_UNITS:
		var n2: int = mini(mini(int(home.get(unit_id, 0)), room), land_free)
		if n2 > 0:
			party[unit_id] = n2
			room -= n2
			land_free -= n2
	for offer in CombatManager.get_sortie_offers():
		if not CombatManager.offer_has_water(offer):
			continue
		if not bool(CombatManager.can_launch_to(party, offer).get("ok", false)):
			continue
		var preview: Dictionary = CombatManager.sortie_preview(offer, party)
		if float(preview.get("player_power", 0.0)) < float(preview.get("enemy_power", 0.0)):
			_r["coast_skipped"] += 1
			continue
		if CombatManager.launch_sortie(int(offer.get("id", -1)), party, bool(preview.get("can_auto", false))):
			_last_coast = _clock
			_r["coast_launched"] += 1
			_r["coast_pending"] = true
			_act("extra coast %s %s" % [String(offer.get("kind", "")), str(party)], true)
			return true
	return false

## Lo que se apunta de los extras (siempre conectado; sin extras casi todo
## queda a cero, y asi las dos tablas se comparan columna a columna).
func _connect_extra_probes() -> void:
	EventBus.construction_completed.connect(func(node: Node) -> void:
		var info: Dictionary = GridManager.get_building_info(node)
		if info.is_empty():
			return
		var id: String = (info["data"] as BuildingData).id
		if id in EXTRA_BUILDINGS and not (_r["extra_first"] as Dictionary).has(id):
			_r["extra_first"][id] = _clock)
	EventBus.production_collected.connect(func(node: Node, got: Dictionary) -> void:
		var info: Dictionary = GridManager.get_building_info(node)
		if not info.is_empty() and (info["data"] as BuildingData).id == "fishing_dock":
			_r["dock_food"] += int(got.get("food", 0)))
	EventBus.stock_spoiled.connect(func(node: Node, lost: Dictionary) -> void:
		var info: Dictionary = GridManager.get_building_info(node)
		if not info.is_empty() and (info["data"] as BuildingData).id == "fishing_dock":
			_r["dock_spoiled"] += int(lost.get("food", 0)))
	EventBus.unit_trained.connect(func(id: String) -> void:
		if id in EXTRA_UNITS:
			_r["extra_units"][id] = int(_r["extra_units"].get(id, 0)) + 1)
	EventBus.expedition_ended.connect(func(result: int, _rw: Dictionary, _c: Dictionary) -> void:
		if not bool(_r.get("coast_pending", false)):
			return
		_r["coast_pending"] = false
		if result == Expedition.RESULT_WON:
			_r["coast_won"] += 1
		elif result == Expedition.RESULT_LOST:
			_r["coast_lost"] += 1
		else:
			_r["coast_abandoned"] += 1)

func _print_extras(r: Dictionary) -> void:
	var firsts := ""
	for id in EXTRA_BUILDINGS:
		firsts += "%s=%s " % [id, _min1((r["extra_first"] as Dictionary).get(id, -1.0))]
	print("  1.1 primer edificio (min): " + firsts)
	print("  1.1 muelle: comida recogida %d (estropeada %d) | flota entrenada %s | costa lanzadas %d ganadas %d perdidas %d abandonadas %d (descartadas por floja %d) | sin hueco %s" % [
		int(r["dock_food"]), int(r["dock_spoiled"]), str(r["extra_units"]), int(r["coast_launched"]),
		int(r["coast_won"]), int(r["coast_lost"]), int(r["coast_abandoned"]), int(r["coast_skipped"]),
		str(r["extra_no_spot"])])

func _print_extras_table(results: Array) -> void:
	print("")
	print("| semilla | muelle | molino | silo | taberna | carpinteria | pozo | faro | deposito | astillero | aerodromo | comida muelle | flota | costa G/P/A | era 1 | era 2 | era 3 | victoria | huecos>3min |")
	print("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
	for r in results:
		var f: Dictionary = r["extra_first"]
		var cells := ""
		for id in EXTRA_BUILDINGS:
			cells += "%s | " % _min1(f.get(id, -1.0))
		var fleet := 0
		for id in r["extra_units"]:
			fleet += int(r["extra_units"][id])
		var g: Dictionary = _gaps(r)
		print("| %d | %s%d | %d | %d/%d/%d | %.1f | %.0f | %.0f | %s | %d |" % [
			r["seed"], cells, int(r["dock_food"]), fleet, int(r["coast_won"]), int(r["coast_lost"]),
			int(r["coast_abandoned"]), _era_len(r, 1), _era_len(r, 2), _era_len(r, 3),
			_mins(r["victory_at"]), int(g["idle_count"])])

# ══════════════════════════════════════════════════════════════════════
# Huecos
# ══════════════════════════════════════════════════════════════════════

func _spot_for(building_id: String, data: BuildingData) -> Dictionary:
	var center := Vector2i(GridManager.grid_width / 2, GridManager.grid_height / 2)
	# Tres campanas: la linea pide el Astillero (Campana de Mar) tras el CG nv3.
	# Va en la costa, como lo coloca el jugador completo (_extra_spot).
	if building_id == "shipyard":
		return _extra_spot(building_id, data)
	if building_id == "refinery":
		for dep in _map.get_all_deposits():
			if dep["id"] != "oil_well":
				continue
			for ox in range(int(dep["cell_x"]), int(dep["cell_x"]) + int(dep["size_x"])):
				for oy in range(int(dep["cell_y"]), int(dep["cell_y"]) + int(dep["size_y"])):
					var origin := Vector2i(ox, oy)
					if Rules.road_route(origin, data.grid_size) == null:
						continue
					if bool(Rules.evaluate_placement("refinery", origin, data.grid_size, _map)["ok"]):
						return {"origin": origin, "rotation": 0}
		return {}
	var rule: Dictionary = GameConfig.get_deposit_rule(building_id)
	if not rule.is_empty():
		var spots: Array = _map.buildable_spots_near(String(rule["deposit"]), data.grid_size, int(rule["reach"]), 0)
		if spots.is_empty():
			return {}
		spots.sort_custom(func(a, b): return _dist(a["origin"], center) < _dist(b["origin"], center))
		for spot in spots:
			if Rules.road_route(spot["origin"], spot["size"]) == null:
				continue
			return {"origin": spot["origin"], "rotation": 1 if (spot["size"] as Vector2i) != data.grid_size else 0, "size": spot["size"]}
		return {}
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
			if Rules.road_route(origin, data.grid_size) == null:
				continue
			best = origin
			best_d = d
	if best == Vector2i(-1, -1):
		return {}
	return {"origin": best, "rotation": 0}

## Tiende la carretera que une la huella a la red, cobrando cada tramo (1 oro).
func _pave_to(origin: Vector2i, size: Vector2i) -> void:
	var route: Variant = Rules.road_route(origin, size)
	if route == null:
		return
	var road: BuildingData = Rules.load_building_data("road")
	for c in route:
		if not ResourceManager.can_afford(road.get_cost()):
			return
		ResourceManager.spend_cost(road.get_cost())
		_placer.place_building_at(road, c)

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
	# Cualquier decision del jugador (obra, taller, compra, reparacion...) cuenta
	# como "algo que hacer"; recoger y cultivar no (son rutina).
	_r["activity_times"].append(_clock)
	_drain_overflow(what.get_slice(" ", 0))
	if progress:
		_r["progress_times"].append(_clock)
	if bool(options.get("log", false)):
		print("  %6.1f min  %s" % [_clock / 60.0, what])

func _drain_overflow(what: String) -> void:
	for p in _ov_pending:
		var src: String = String(p[3]) if String(p[3]) != "" else what
		var key: String = "%s<-%s" % [String(p[1]), src]
		_r["overflow_by"][key] = int(_r["overflow_by"].get(key, 0)) + int(p[2])
	_ov_pending.clear()

func _connect_probes() -> void:
	EventBus.building_upgrade_completed.connect(func(node: Node, lvl: int) -> void:
		var info: Dictionary = GridManager.get_building_info(node)
		if not info.is_empty() and (info["data"] as BuildingData).id == "headquarters":
			_r["hq%d_at" % lvl] = _clock)
	EventBus.milestone_completed.connect(func(id: String) -> void:
		if not _r["milestones"].has(id):
			_r["milestones"][id] = _clock)
	EventBus.storm_started.connect(func(sev: int) -> void:
		# La tormenta de prueba de la era 1 no cuenta como tormenta: se anota aparte.
		if StormManager.is_trial_running():
			_r["trial_at"] = _clock
			return
		_r["storms"].append({"t": _clock, "severity": sev, "ruined": 0,
			"morale_before": PopulationManager.get_morale(), "towers": CombatManager.count_standing_towers(),
			"stored": ResourceManager.get_total_stored()}))
	# Cuartel temprano (2026-10-17): primer Cuartel en pie, primer soldado, primera
	# mision ganada y el Impuesto de juguete de la tormenta de prueba.
	EventBus.construction_completed.connect(func(node: Node) -> void:
		var info: Dictionary = GridManager.get_building_info(node)
		if not info.is_empty() and (info["data"] as BuildingData).id == "barracks" and not _r.has("barracks_at"):
			_r["barracks_at"] = _clock)
	EventBus.unit_trained.connect(func(_id: String) -> void:
		if not _r.has("soldier_at"):
			_r["soldier_at"] = _clock)
	EventBus.expedition_ended.connect(func(result: int, _rw: Dictionary, _c: Dictionary) -> void:
		if result == Expedition.RESULT_WON and not _r.has("sortie_at"):
			_r["sortie_at"] = _clock)
	# Tres campanas: cuando se gana cada mision y cuando se completa cada campana.
	EventBus.campaign_mission_won.connect(func(domain: String, _m: int, _boss: bool) -> void:
		(_r["campaign_won"][domain] as Array).append(_clock))
	EventBus.campaign_completed.connect(func(domain: String) -> void:
		_r["campaign_done"][domain] = _clock)
	EventBus.expedition_ended.connect(func(result: int, _rw: Dictionary, _c: Dictionary) -> void:
		if result != Expedition.RESULT_WON and not CombatManager.get_last_result().get("campaign_domain", "").is_empty():
			_r["campaign_setbacks"] = int(_r["campaign_setbacks"]) + 1)
	EventBus.trial_tithe_resolved.connect(func(repelled: bool, taken: Dictionary) -> void:
		_r["trial_tithe"] = {"t": _clock, "repelled": repelled, "taken": taken.duplicate(),
			"home": CombatManager.roster_size(CombatManager.get_garrison())})
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
	EventBus.storage_overflow.connect(func(res: String, lost: int, _cap: int) -> void:
		_r["overflow"] += lost
		# De donde viene: la accion que se anota justo despues (vender anota
		# despues de cobrar), o el evento de este segundo, o "?".
		var src := ""
		if float(_r.get("last_event_t", -10.0)) >= _clock - 1.0:
			src = "evento " + String(_r.get("last_event", ""))
		_ov_pending.append([_clock, res, lost, src]))
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
		_r["last_event"] = id
		_r["last_event_t"] = _clock
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
		"food": ResourceManager.get_amount(ResourceManager.Type.FOOD),
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
	return "paso=%s era=%d oro=%d madera=%d comida=%d acero=%d petroleo=%d bolsa=%d/%d pob=%d/%d moral=%d ejercito=%s" % [
		str(_r.get("last_step", {})), s["era"], s["gold"], s["wood"], s["food"], s["steel"], s["oil"],
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
	# Huecos sin NINGUNA decision (cualquier _act), mayores de 3 min.
	var acts: Array = r["activity_times"].duplicate()
	acts.append(end_t)
	var idle_count := 0
	var idle_longest := 0.0
	for i in range(1, acts.size()):
		var gap2: float = float(acts[i]) - float(acts[i - 1])
		idle_longest = maxf(idle_longest, gap2)
		if gap2 > 180.0:
			idle_count += 1
	return {"dead": dead, "longest": longest, "count": count, "early_longest": early_longest,
		"idle_count": idle_count, "idle_longest": idle_longest}

func _print_run(r: Dictionary) -> void:
	print("")
	print("=== semilla %d === yacimientos %s" % [r["seed"], str(r["deposits"])])
	var line := ""
	for id in MILESTONE_ORDER:
		line += "%s=%s " % [id, _mins(r["milestones"].get(id, -1.0))]
	print("hitos (min): " + line)
	print("era 1: era 2 en el minuto %.1f | tormenta de prueba en el %s" % [
		float(r["milestones"].get("era_2", -60.0)) / 60.0,
		"%.1f" % (float(r["trial_at"]) / 60.0) if r.has("trial_at") else "—"])
	var tt: Dictionary = r.get("trial_tithe", {})
	print("cuartel temprano: Cuartel en el minuto %s | 1.er soldado %s | 1.a mision ganada %s | impuesto de juguete %s" % [
		_min1(r.get("barracks_at", -1.0)), _min1(r.get("soldier_at", -1.0)),
		_min1(r.get("sortie_at", -1.0)),
		("—" if tt.is_empty() else "%s en el %s con %d en casa, %s" % ["REPELIDO" if bool(tt["repelled"]) else "cobrado",
			_min1(tt["t"]), int(tt["home"]), str(tt["taken"])])])
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
	print("  sin ninguna decision: huecos>3min %d | el mas largo %.1f min | era1 %.1f min | era2 %.1f min | era3 %.1f min | intentos de asedio %d" % [
		int(g["idle_count"]), float(g["idle_longest"]) / 60.0, _era_len(r, 1), _era_len(r, 2), _era_len(r, 3), r["sieges"].size()])
	print("  incursiones %d | repuestos al final %d" % [int(r.get("raids", 0)), int(r.get("parts_end", 0))])
	var camps := ""
	for domain in ["land", "sea", "air"]:
		var wins: Array = r["campaign_won"][domain]
		var times: Array = []
		for t in wins:
			times.append(_mins(t))
		camps += "%s %d/%d [%s] completa %s | " % [domain, wins.size(), GameConfig.campaign_mission_count(domain),
			",".join(times), _mins(r["campaign_done"].get(domain, -1.0))]
	print("  campanas: %sfallidas %d" % [camps, int(r["campaign_setbacks"])])
	print("  CG nv2 en el minuto %s | CG nv3 (convocatoria) en el %s | casas %d | granjas %d | gente %d | comida %.0f/min" % [
		_mins(r.get("hq2_at", -1.0)), _mins(r.get("hq3_at", -1.0)), int(r.get("houses", 0)), int(r.get("farms", 0)),
		int(r["end"]["pop"]), float(r.get("food_per_min", 0.0))])
	if int(r["overflow"]) > 0:
		print("  desbordado por origen: " + str(r["overflow_by"]))
	# Donde caen los huecos de mas de 3 min sin decidir nada, y que pedia el panel.
	var acts: Array = r["activity_times"]
	var idle := ""
	for i in range(1, acts.size()):
		var gap: float = float(acts[i]) - float(acts[i - 1])
		if gap > 180.0:
			idle += "%.0f(+%.1f %s) " % [float(acts[i - 1]) / 60.0, gap / 60.0, _step_at(r, float(acts[i - 1]) + 1.0)]
	if idle != "":
		print("  huecos>3min: " + idle)
	if not (r["after"] as Dictionary).is_empty():
		print("  TRAS GANAR: " + str(r["after"]))
	print("  recoger: %d veces %s | cambios de cultivo %d | edificio-minutos parado por lleno %.0f | granjas %d" % [
		int(r["collects"]), str(r["collected"]), int(r["crop_changes"]), float(r["full_stop"]) / 60.0,
		int(r.get("farms", 0))])
	_print_extras(r)
	if r["stuck"] != "":
		print("  ATASCO: " + String(r["stuck"]))
	print("  final: " + str(r["end"]))

func _print_table(results: Array) -> void:
	print("")
	print("| semilla | era 2 | era 3 | CG | CG nv3 | tierra | mar | aire | asedio | victoria | era 1 | era 2 dura | era 3 dura | tormentas | diezmos repelidos | asedios | esperas>2min | hueco max | huecos>3min sin decidir | mayor sin decidir | bolsa llena | desbordado |")
	print("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
	for r in results:
		var m: Dictionary = r["milestones"]
		var repelled := 0
		for t in r["tithes"]:
			if bool(t["repelled"]):
				repelled += 1
		var g: Dictionary = _gaps(r)
		var siege_t: float = float(r["sieges"][0]["t"]) if not r["sieges"].is_empty() else -1.0
		print("| %d | %s | %s | %s | %s | %s | %s | %s | %s | %s | %.1f | %.0f | %.0f | %d | %d/%d | %d | %d (%.0f min) | %.1f min | %d | %.1f min | %.0f min | %d |" % [
			r["seed"], _mins(m.get("era_2", -1.0)), _mins(m.get("era_3", -1.0)),
			_mins(m.get("hq_built", -1.0)), _mins(m.get("hq_max", -1.0)),
			_mins(r["campaign_done"].get("land", -1.0)), _mins(r["campaign_done"].get("sea", -1.0)),
			_mins(r["campaign_done"].get("air", -1.0)),
			_mins(siege_t), _mins(r["victory_at"]), _era_len(r, 1), _era_len(r, 2), _era_len(r, 3),
			r["storms"].size(), repelled, r["tithes"].size(), r["sieges"].size(),
			g["count"], g["dead"] / 60.0, g["longest"] / 60.0, int(g["idle_count"]), float(g["idle_longest"]) / 60.0,
			r["full_time"] / 60.0, r["overflow"]])

## El paso que pedia el panel en el segundo `t`.
func _step_at(r: Dictionary, t: float) -> String:
	var out := ""
	for e in r["step_log"]:
		if float(e[0]) > t:
			break
		out = String(e[1])
	return out

## Duracion de una era en minutos (la 3, hasta la victoria o el final).
func _era_len(r: Dictionary, era: int) -> float:
	var m: Dictionary = r["milestones"]
	var end_t: float = float(r["victory_at"]) if float(r["victory_at"]) >= 0.0 else float(r["end"]["t"])
	var starts := [0.0, float(m.get("era_2", end_t)), float(m.get("era_3", end_t)), end_t]
	return (float(starts[era]) - float(starts[era - 1])) / 60.0

func _min1(t) -> String:
	var f: float = float(t)
	return "—" if f < 0.0 else "%.1f" % (f / 60.0)

func _mins(t) -> String:
	var f: float = float(t)
	if f < 0.0:
		return "—"
	return "%.0f" % (f / 60.0)
