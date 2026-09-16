extends GdUnitTestSuite
## La partida entera, sin interfaz: de colonia nueva a Victoria Imperial.
##
## Es la unica prueba del repositorio que demuestra que el juego se puede
## **terminar**. Los cuatro fallos mas graves encontrados hasta hoy no los vio
## ningun test unitario porque ninguno vivia dentro de un sistema: vivian en la
## costura entre dos —el tablero y la pantalla, el reloj de la Tormenta y el
## asedio, la expedicion y el ejercito—. Esto recorre esas costuras en el orden
## en que las recorre un jugador.
##
## ── Como esta partido ────────────────────────────────────────────────
## Seis casos vivos, cada uno una fase del recorrido, cada uno arrancando de una
## colonia recien fundada. No es un unico test kilometrico a proposito: cuando
## algo se rompe, el nombre del caso ya dice en que tramo de la partida fue, y
## una fase rota no esconde a las siguientes. El precio es que las fases tardias
## vuelven a jugar las tempranas por el mismo camino (`_open_the_frontier()`,
## `_industrialise()`), que es exactamente lo que se quiere probar: que ese
## camino sigue llevando donde dice el diseño.
##
##   1. `test_a_new_colony_starts_exactly_where_the_design_says`
##   2. `test_each_era_opens_because_of_the_building_the_design_says`
##   3. `test_a_whole_storm_cycle_bites_the_base_and_settles_its_tithe`
##   4. `test_an_expedition_comes_home_with_its_survivors_and_its_loot_once`
##   5. `test_the_capstone_summons_the_audit_and_surviving_it_wins_the_game`
##   6. `test_losing_the_siege_ruins_the_base_but_never_ends_the_game`
##
## Otros tres nacieron en rojo y destaparon tres fallos reales que ningun test
## unitario veia, porque los tres vivian en una costura entre servicios. Ya estan
## arreglados; los casos se quedan de guardia, con el diagnostico en su cabecera:
##
##   · `test_the_building_limit_actually_limits` — ningun tope limitaba nada: se
##     levantaban 8 Almacenes con el tope en 5, y DOS Cuarteles Generales con el
##     tope en 1, que es el edificio que convoca el final.
##   · `test_the_siege_is_hard_but_winnable_with_a_full_garrison` y el de la
##     guarnicion minima — la Auditoria Final no se podia ganar ni con la
##     guarnicion maxima, asi que la partida no tenia final.
##   · `test_a_damaged_building_can_be_repaired` — reparar era imposible: el
##     boton REPARAR no se dejaba pulsar nunca, con la Tormenta rompiendo cosas.
##
## El guardado y la carga (punto 7 del encargo) no tienen caso propio: se
## comprueban **dentro** del recorrido, en los dos momentos en que mas duele
## perder algo —a mitad de expedicion y con el asedio convocado sin empezar—,
## desde `_assert_a_save_and_load_puts_everything_back()`.
##
## ── Como se juega sin interfaz ───────────────────────────────────────
## · Se levantan el BuildingPlacer y el MapGenerator **reales** bajo la escena
##   actual y se les registra en GameManager, asi que colocar pasa por las
##   mismas comprobaciones que un clic: yacimiento, prerrequisitos, limite,
##   obreros y coste. Nada de plantar nodos a mano en la rejilla.
## · Los relojes no se esperan: se les da el tiempo a mano (`_finish_building()`,
##   `StormManager._process(delta)`), y `GameConfig.dev_time_scale` se sube
##   mucho para que los `_process` reales del motor no muevan nada por su cuenta
##   entre fotograma y fotograma.
## · Las peleas las juega `AutoResolver` con la misma IA a los dos lados, y sus
##   eventos se le entregan a `CombatManager._emit_events()`, que es el unico
##   camino por el que ese servicio se entera de nada. Asi la expedicion avanza,
##   el Diezmo se salda y las oleadas del asedio se relevan como en partida.
##
## ── Y como no depende del azar ───────────────────────────────────────
## Los yacimientos se plantan a mano en celdas fijas; la semilla de la
## expedicion y la del asedio se fijan; y donde el resultado de una pelea no es
## algo que este test deba decidir, no se afirma quien gana: se afirman las
## invariantes (el ejercito cuadra con los supervivientes, el botin se cobra una
## vez, el Nucleo sigue en pie, nadie se queda atascado). Todo recorrido lleva
## guarda, y un guarda que salta **falla diciendo donde se atasco**.
##
## Toca todos los autoloads que hay. Cada caso los deja como estaban, incluido
## el fichero de guardado del jugador, que se aparta y se devuelve.

const Placer := preload("res://scripts/buildings/BuildingPlacer.gd")
const MapGen := preload("res://scripts/map/MapGenerator.gd")
const AutoResolverScript := preload("res://scripts/combat/AutoResolver.gd")

const SAVE_PATH := "user://save_game.json"
const BACKUP_PATH := "user://save_game.full_campaign.bak"

## Los yacimientos, en celdas fijas y lejos del Nucleo (3x3 en el centro de una
## rejilla de 40x40). Plantarlos a mano en vez de dejar que MapGenerator los
## sortee es lo que hace que este recorrido sea el mismo todas las veces.
const DEPOSITS := [
	["forest", Vector2i(4, 4)],
	["gold_vein", Vector2i(10, 4)],
	["iron_deposit", Vector2i(16, 4)],
	["oil_well", Vector2i(4, 12)],
]
const DEPOSIT_SIZE := Vector2i(2, 2)
## La Refineria se planta **encima** del pozo y se lo come (alcance 0), asi que
## no hay "hueco libre" que buscarle: su sitio es el pozo.
const OIL_WELL_CELL := Vector2i(4, 12)

## Casas que se levantan antes que nada. 5 de aforo del Nucleo + 6 por casa = 29,
## y la base completa pide 23 obreros.
const HOUSES := 4

const EXPEDITION_SEED := 20260915
## Semilla global antes de convocar: `ProgressionManager._audit_seed()` llama a
## `randi()`, asi que fijarla aqui fija el asedio entero, oleada por oleada.
const AUDIT_SEED := 7727
## Asedios que se juegan para medir. Cinco bastan para separar "la mayoria gana"
## (82% medido) de "casi nunca gana" (0-6%), y siguen costando poco porque las
## peleas las resuelve la IA en memoria.
const SIEGE_SAMPLES := 5

# ── Estado guardado de los autoloads ──────────────────────────────────

var _saved_resources: Dictionary = {}
var _saved_era: int = 1
var _saved_warehouses: int = 0
var _saved_progression: Dictionary = {}
var _saved_population: Dictionary = {}
var _saved_army: Dictionary = {}
var _saved_storm: Dictionary = {}
var _saved_market: Dictionary = {}
var _saved_events: Dictionary = {}
var _saved_tech: Dictionary = {}
var _saved_dev_mode: bool = true
var _saved_time_scale: float = 0.2
var _saved_production_mult: float = 1.0
var _saved_audit_scales: Array = []
var _saved_placer: Node = null
var _saved_map_gen: Node = null
var _saved_started: bool = false
var _saved_camera: Camera3D = null

var _placer: Node3D = null
var _map: Node = null
var _scene: Node = null
var _made_scene: bool = false

# ── Sondas del EventBus (a mano, nunca monitor_signals) ───────────────

var _milestones: Array = []
var _eras: Array = []
var _tithes: Array = []            ## [repelida, cobrado] por emision
var _victories: Array = []
var _halts: int = 0
var _audit_lost: int = 0
var _expedition_ends: Array = []   ## [resultado, botin, bajas]
var _ruined: Array = []
var _incoming: int = 0

# ══════════════════════════════════════════════════════════════════════
# Montaje y desmontaje
# ══════════════════════════════════════════════════════════════════════

func before_test() -> void:
	_saved_resources = _resource_amounts()
	_saved_era = ResourceManager.get_era()
	_saved_warehouses = ResourceManager.get_warehouse_count()
	_saved_progression = ProgressionManager.get_save_data()
	_saved_population = PopulationManager.get_save_data()
	_saved_army = ArmyManager.get_save_data()
	_saved_storm = StormManager.get_save_data()
	_saved_market = MarketManager.get_save_data()
	_saved_events = RandomEventManager.get_save_data()
	_saved_tech = TechTreeManager.get_save_data()
	_saved_dev_mode = GameConfig.dev_mode
	_saved_time_scale = GameConfig.dev_time_scale
	_saved_production_mult = GameConfig.event_production_multiplier
	_saved_audit_scales = [
		GameConfig.final_audit_scale_per_wave,
		GameConfig.final_audit_scale_per_era,
		GameConfig.final_audit_last_wave_multiplier,
	]
	_saved_placer = GameManager._placer
	_saved_map_gen = GameManager._map_gen
	_saved_started = GameManager._started
	_saved_camera = GameManager._camera

	# Construir y producir siguen siendo rapidos (dev_mode los fija en 2 s y 4 s),
	# pero todo lo que corre sobre `get_duration()` —Tormenta, entrenamiento,
	# consumo, eventos, mantenimiento— se estira tanto que los fotogramas que el
	# test deja pasar para que la IA suelte el hilo no pueden mover nada.
	GameConfig.dev_mode = true
	GameConfig.dev_time_scale = 60.0
	GameConfig.event_production_multiplier = 1.0

	_park_player_save()
	_connect_probes()
	_open_new_colony()

func after_test() -> void:
	_close_colony()
	_disconnect_probes()

	GameManager._placer = _saved_placer
	GameManager._map_gen = _saved_map_gen
	GameManager._started = _saved_started
	GameManager._camera = _saved_camera
	GameManager._warehouse_count = 0

	CombatManager.reset()
	ProgressionManager.final_audit = null
	ProgressionManager.load_save_data(_saved_progression)
	StormManager.load_save_data(_saved_storm)
	ArmyManager.load_save_data(_saved_army)
	PopulationManager.load_save_data(_saved_population)
	MarketManager.load_save_data(_saved_market)
	RandomEventManager.load_save_data(_saved_events)
	TechTreeManager.load_save_data(_saved_tech)
	ResourceManager.set_era(_saved_era)
	ResourceManager.set_warehouse_count(_saved_warehouses)
	ResourceManager.set_amounts(_saved_resources)

	GameConfig.dev_mode = _saved_dev_mode
	GameConfig.dev_time_scale = _saved_time_scale
	GameConfig.event_production_multiplier = _saved_production_mult
	GameConfig.final_audit_scale_per_wave = float(_saved_audit_scales[0])
	GameConfig.final_audit_scale_per_era = float(_saved_audit_scales[1])
	GameConfig.final_audit_last_wave_multiplier = float(_saved_audit_scales[2])

	_restore_player_save()

## GameManager guarda en `user://save_game.json`, que es la partida de verdad de
## quien tenga el juego instalado. Se aparta antes y se devuelve despues: una
## suite de pruebas no puede cobrarse la partida de nadie.
func _park_player_save() -> void:
	if FileAccess.file_exists(BACKUP_PATH):
		DirAccess.remove_absolute(BACKUP_PATH)
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.rename_absolute(SAVE_PATH, BACKUP_PATH)

func _restore_player_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	if FileAccess.file_exists(BACKUP_PATH):
		DirAccess.rename_absolute(BACKUP_PATH, SAVE_PATH)

## Una colonia nueva de verdad: el BuildingPlacer y el MapGenerator reales bajo
## la escena actual (de ahi los lee `GameManager`, `ArmyManager.barracks_count()`
## y `BuildingPlacer._map_generator()`), y `GameManager._new_game()` corriendo
## por su propio camino porque no hay guardado en disco.
func _open_new_colony() -> void:
	_scene = get_tree().current_scene
	if _scene == null:
		_scene = Node.new()
		_scene.name = "FullCampaignScene"
		get_tree().root.add_child(_scene)
		get_tree().current_scene = _scene
		_made_scene = true

	GridManager.clear_all()
	GameManager._placer = null
	GameManager._map_gen = null
	GameManager._started = false
	GameManager._warehouse_count = 0

	_map = MapGen.new()
	_map.name = "MapGenerator"
	_scene.add_child(_map)
	_placer = Placer.new()
	_placer.name = "BuildingPlacer"
	_scene.add_child(_placer)   # _ready() registra y dispara _new_game()

	assert_bool(GameManager._started).override_failure_message(
		"GameManager no arranco la partida nueva: el placer o el mapa no se registraron"
	).is_true()

	# El mapa que sortea la partida nueva se cambia por uno fijo: mismos
	# yacimientos, mismas celdas, mismo recorrido todas las veces.
	_map.clear_all_deposits()
	for entry in DEPOSITS:
		_map.spawn_deposit(String(entry[0]), entry[1] as Vector2i, -1, DEPOSIT_SIZE)

func _close_colony() -> void:
	if is_instance_valid(_placer):
		for info in GridManager.get_all_buildings():
			ProductionManager.unregister(info["node"])
		_placer.clear_all_buildings()
		_scene.remove_child(_placer)
		_placer.free()
	if is_instance_valid(_map):
		_map.clear_all_deposits()
		_scene.remove_child(_map)
		_map.free()
	GridManager.clear_all()
	_placer = null
	_map = null
	if _made_scene and is_instance_valid(_scene):
		get_tree().current_scene = null
		get_tree().root.remove_child(_scene)
		_scene.free()
		_made_scene = false
	_scene = null

func _connect_probes() -> void:
	_milestones = []
	_eras = []
	_tithes = []
	_victories = []
	_halts = 0
	_audit_lost = 0
	_expedition_ends = []
	_ruined = []
	_incoming = 0
	EventBus.milestone_completed.connect(_on_milestone)
	EventBus.era_advanced.connect(_on_era)
	EventBus.tithe_resolved.connect(_on_tithe)
	EventBus.victory_achieved.connect(_on_victory)
	EventBus.storm_halted_forever.connect(_on_halt)
	EventBus.final_audit_lost.connect(_on_audit_lost)
	EventBus.expedition_ended.connect(_on_expedition_ended)
	EventBus.building_ruined.connect(_on_ruined)
	EventBus.storm_incoming.connect(_on_incoming)

func _disconnect_probes() -> void:
	EventBus.milestone_completed.disconnect(_on_milestone)
	EventBus.era_advanced.disconnect(_on_era)
	EventBus.tithe_resolved.disconnect(_on_tithe)
	EventBus.victory_achieved.disconnect(_on_victory)
	EventBus.storm_halted_forever.disconnect(_on_halt)
	EventBus.final_audit_lost.disconnect(_on_audit_lost)
	EventBus.expedition_ended.disconnect(_on_expedition_ended)
	EventBus.building_ruined.disconnect(_on_ruined)
	EventBus.storm_incoming.disconnect(_on_incoming)

func _on_milestone(id: String) -> void:
	_milestones.append(id)

func _on_era(era: int) -> void:
	_eras.append(era)

func _on_tithe(repelled: bool, taken: Dictionary) -> void:
	_tithes.append([repelled, taken])

func _on_victory(stats: Dictionary) -> void:
	_victories.append(stats)

func _on_halt() -> void:
	_halts += 1

func _on_audit_lost(_wave: int) -> void:
	_audit_lost += 1

func _on_expedition_ended(result: int, rewards: Dictionary, losses: Dictionary) -> void:
	_expedition_ends.append([result, rewards.duplicate(), losses.duplicate()])

func _on_ruined(node: Node3D) -> void:
	_ruined.append(node)

func _on_incoming(_seconds: float) -> void:
	_incoming += 1

# ══════════════════════════════════════════════════════════════════════
# Utilleria: construir, poblar, entrenar, pelear
# ══════════════════════════════════════════════════════════════════════

func _resource_amounts() -> Dictionary:
	return {
		"gold": ResourceManager.get_amount(ResourceManager.Type.GOLD),
		"steel": ResourceManager.get_amount(ResourceManager.Type.STEEL),
		"oil": ResourceManager.get_amount(ResourceManager.Type.OIL),
		"wood": ResourceManager.get_amount(ResourceManager.Type.WOOD),
	}

## Dinero para seguir jugando. Inyectar recursos esta permitido y es lo unico que
## se salta: lo que se prueba es que construir lo correcto abre la era correcta,
## no cuantos minutos cuesta juntar el oro.
func _bankroll(gold: int = 4000, wood: int = 4000, steel: int = 2000, oil: int = 2000) -> void:
	ResourceManager.set_amounts({"gold": gold, "wood": wood, "steel": steel, "oil": oil})

func _count(building_id: String) -> int:
	var total := 0
	for info in GridManager.get_all_buildings():
		if (info["data"] as BuildingData).id == building_id:
			total += 1
	return total

func _buildings_by_id() -> Dictionary:
	var tally: Dictionary = {}
	for info in GridManager.get_all_buildings():
		var key: String = "%s@%d" % [
			(info["data"] as BuildingData).id, int(info["node"].get_meta("level", 1))]
		tally[key] = int(tally.get(key, 0)) + 1
	return tally

## Primer hueco legal, barrido desde la esquina lejana para no comerse las
## celdas que los extractores necesitan junto a sus yacimientos.
func _free_origin(size: Vector2i) -> Vector2i:
	for y in range(GridManager.grid_height - size.y, -1, -1):
		for x in range(GridManager.grid_width - size.x, -1, -1):
			var origin := Vector2i(x, y)
			if GridManager.can_place(origin, size):
				return origin
	return Vector2i(-1, -1)

## Donde va este edificio: junto a su yacimiento si lo pide la regla, encima del
## pozo si es la Refineria, y en el primer hueco libre si construye donde quiera.
func _spot_for(building_id: String, data: BuildingData) -> Dictionary:
	if building_id == "refinery":
		return {"origin": OIL_WELL_CELL, "rotation": 0}
	var rule: Dictionary = GameConfig.get_deposit_rule(building_id)
	if rule.is_empty():
		return {"origin": _free_origin(data.grid_size), "rotation": 0}
	var spots: Array = _map.buildable_spots_near(
		String(rule["deposit"]), data.grid_size, int(rule["reach"]), 1)
	if spots.is_empty():
		return {}
	var spot: Dictionary = spots[0]
	var rotated: bool = (spot["size"] as Vector2i) != data.grid_size
	return {"origin": spot["origin"], "rotation": 1 if rotated else 0}

## Coloca como colocaria el jugador: el mismo `_try_place()` que responde al
## clic, con sus comprobaciones de yacimiento, prerrequisitos, limite, obreros y
## coste. Devuelve el nodo, todavia en obras.
func _place(building_id: String) -> Node3D:
	var data: BuildingData = load("res://data/buildings/%s.tres" % building_id)
	assert_object(data).override_failure_message(
		"no existe data/buildings/%s.tres" % building_id).is_not_null()
	var spot: Dictionary = _spot_for(building_id, data)
	assert_bool(spot.has("origin") and spot["origin"] != Vector2i(-1, -1)).override_failure_message(
		"no queda hueco legal donde levantar %s" % building_id).is_true()
	if not spot.has("origin"):
		return null

	var before: int = _count(building_id)
	_placer._current_data = data
	_placer._rotation_steps = int(spot.get("rotation", 0))
	_placer._try_place(spot["origin"] as Vector2i)
	_placer._current_data = null
	_placer._rotation_steps = 0

	assert_int(_count(building_id)).override_failure_message(
		"el juego rechazo levantar %s en %s (oro %d, madera %d, obreros libres %d)" % [
			building_id, spot["origin"], ResourceManager.get_amount(ResourceManager.Type.GOLD),
			ResourceManager.get_amount(ResourceManager.Type.WOOD),
			PopulationManager.get_free_workers()]
	).is_equal(before + 1)
	return GridManager.get_building_at(spot["origin"] as Vector2i)

## El mismo intento, sin exigir que salga bien: para los casos que comprueban
## precisamente que el juego diga que no.
func _try_to_place(building_id: String) -> void:
	var data: BuildingData = load("res://data/buildings/%s.tres" % building_id)
	var spot: Dictionary = _spot_for(building_id, data)
	if not spot.has("origin") or spot["origin"] == Vector2i(-1, -1):
		return
	_placer._current_data = data
	_placer._rotation_steps = int(spot.get("rotation", 0))
	_placer._try_place(spot["origin"] as Vector2i)
	_placer._current_data = null
	_placer._rotation_steps = 0

## Le da a las obras todo el tiempo que necesiten de una vez. Es el mismo
## `_tick_construction()` que corre en partida, con el reloj en la mano.
func _finish_building() -> void:
	ProductionManager._tick_construction(1_000_000.0)

## Coloca y termina.
func _build(building_id: String) -> Node3D:
	var node := _place(building_id)
	_finish_building()
	return node

## Hace crecer al pueblo por el mismo camino que el reloj (`_tick_growth()`).
func _grow_population_to(target: int) -> void:
	var guard := 0
	while PopulationManager.get_population() < target:
		guard += 1
		if guard > 200:
			assert_bool(false).override_failure_message(
				"la poblacion se atasco en %d de %d (aforo %d, moral %d)" % [
					PopulationManager.get_population(), target,
					PopulationManager.get_max_population(), PopulationManager.get_morale()]
			).is_true()
			return
		PopulationManager._tick_growth()

## Entrena `count` unidades una detras de otra: un cuartel es una sola plaza, asi
## que se encadenan igual que en partida.
func _train(unit_id: String, count: int) -> void:
	for i in range(count):
		var before: int = ArmyManager.get_count(unit_id)
		assert_bool(ArmyManager.train(unit_id)).override_failure_message(
			"no se pudo entrenar %s (%s)" % [unit_id, ArmyManager.can_train(unit_id)["reason"]]
		).is_true()
		ArmyManager._advance_training(1_000_000.0)
		assert_int(ArmyManager.get_count(unit_id)).override_failure_message(
			"el entrenamiento de %s no llego a termino" % unit_id).is_equal(before + 1)

## Juega el tablero abierto con la IA a los dos lados y **entrega los eventos al
## servicio**: `AutoResolver` es puro y no emite nada, asi que sin este paso
## CombatManager no se enteraria de que la pelea acabo y ni la expedicion
## avanzaria ni la oleada del asedio se reportaria. `_emit_events()` es el mismo
## camino por el que el servicio publica cualquier otro encuentro.
func _play_open_board_with_the_ai() -> Dictionary:
	var board: Encounter = CombatManager.get_encounter()
	assert_object(board).override_failure_message(
		"se pidio jugar un tablero y no hay ninguno abierto").is_not_null()
	if board == null:
		return {}
	var outcome: Dictionary = AutoResolverScript.resolve(board)
	CombatManager._emit_events(outcome["events"])
	return outcome

## El hilo de la IA enemiga arranca solo al abrir el tablero y se queda esperando
## un temporizador. Si se abriera otro tablero antes de que despierte, actuaria
## sobre el nuevo con los uids del viejo. Aqui se le deja terminar.
func _let_the_ai_thread_unwind() -> void:
	var guard := 0
	while CombatManager.is_enemy_thinking() and guard < 120:
		guard += 1
		await get_tree().process_frame
	assert_bool(CombatManager.is_enemy_thinking()).override_failure_message(
		"el turno enemigo no solto el hilo tras %d fotogramas" % guard).is_false()

# ══════════════════════════════════════════════════════════════════════
# Tramos del recorrido, reutilizados por las fases tardias
# ══════════════════════════════════════════════════════════════════════

## Era 1: techo, gente y las tres primeras palancas de la economia.
func _open_the_frontier() -> void:
	_bankroll()
	for i in range(HOUSES):
		_build("house")
	_grow_population_to(GameConfig.population_start + HOUSES * 6)
	_build("sawmill")
	_build("gold_mine")
	_build("warehouse")

## Era 2 y 3: la Fundicion abre el acero, la Refineria abre el petroleo, y por el
## camino queda la base militar que el final del juego necesita.
func _industrialise() -> void:
	_bankroll()
	_build("foundry")
	_build("barracks")
	_build("tower")
	_build("tower")
	_build("refinery")
	_bankroll()

## Diez operaciones en la Bolsa Imperial: el hito del Mercader.
func _trade_ten_times() -> void:
	for i in range(5):
		assert_bool(MarketManager.buy("wood", 5)).override_failure_message(
			"la compra %d de madera fue rechazada" % i).is_true()
		assert_bool(MarketManager.sell("wood", 5)).override_failure_message(
			"la venta %d de madera fue rechazada" % i).is_true()

## Ejercito de casa al tope de despliegue, con la moral alta para que las peleas
## se jueguen siempre en las mismas condiciones.
func _raise_an_army(roster: Dictionary) -> void:
	PopulationManager.load_save_data({
		"population": PopulationManager.get_population(), "morale": 100})
	_bankroll()
	for unit_id in roster:
		_train(String(unit_id), int(roster[unit_id]))

# ══════════════════════════════════════════════════════════════════════
# 1. La colonia nueva
# ══════════════════════════════════════════════════════════════════════

func test_a_new_colony_starts_exactly_where_the_design_says() -> void:
	assert_int(ResourceManager.get_amount(ResourceManager.Type.GOLD)).is_equal(
		int(GameConfig.starting_resources["gold"]))
	assert_int(ResourceManager.get_amount(ResourceManager.Type.WOOD)).is_equal(
		int(GameConfig.starting_resources["wood"]))
	assert_int(ResourceManager.get_amount(ResourceManager.Type.STEEL)).is_equal(0)
	assert_int(ResourceManager.get_amount(ResourceManager.Type.OIL)).is_equal(0)

	assert_int(PopulationManager.get_population()).is_equal(GameConfig.population_start)
	assert_int(PopulationManager.get_morale()).is_equal(GameConfig.morale_start)

	assert_int(ProgressionManager.current_era).is_equal(1)
	assert_int(ProgressionManager.current_phase).is_equal(GameConfig.Phase.FOUNDATION)
	assert_dict(ProgressionManager.milestones_completed).is_empty()
	assert_object(ProgressionManager.final_audit).is_null()

	# Solo el acero y el petroleo estan por abrir: son el premio de las eras 2 y 3.
	assert_bool(ResourceManager.is_unlocked(ResourceManager.Type.GOLD)).is_true()
	assert_bool(ResourceManager.is_unlocked(ResourceManager.Type.WOOD)).is_true()
	assert_bool(ResourceManager.is_unlocked(ResourceManager.Type.STEEL)).is_false()
	assert_bool(ResourceManager.is_unlocked(ResourceManager.Type.OIL)).is_false()

	# Y el Nucleo esta puesto, que es lo unico que la partida regala.
	assert_int(_count("nucleo")).is_equal(1)
	# El reloj de la Tormenta duerme hasta que la base sale del papel.
	assert_bool(StormManager.is_armed()).is_false()

# ══════════════════════════════════════════════════════════════════════
# 2. La economia: cada era se abre por lo que dice el diseño
# ══════════════════════════════════════════════════════════════════════

func test_each_era_opens_because_of_the_building_the_design_says() -> void:
	_open_the_frontier()

	# Los tres primeros hitos son de Era 1, y ninguno de ellos mueve la era.
	assert_array(_milestones).contains(
		["first_sawmill", "first_gold_mine", "first_warehouse"])
	assert_int(ProgressionManager.current_era).is_equal(1)
	assert_bool(ResourceManager.is_unlocked(ResourceManager.Type.STEEL)).is_false()
	# Y salir de FUNDACION es lo que despierta el reloj de la Tormenta.
	assert_bool(StormManager.is_armed()).is_true()

	# ── La Fundicion abre la Era 2, pero solo cuando esta terminada ──
	_bankroll()
	var foundry: Node3D = _place("foundry")
	assert_bool(ProductionManager.is_constructing(foundry)).is_true()
	assert_int(ProgressionManager.current_era).override_failure_message(
		"la era avanzo al COLOCAR la Fundicion, no al terminarla").is_equal(1)
	_finish_building()
	assert_int(ProgressionManager.current_era).is_equal(2)
	assert_bool(ResourceManager.is_unlocked(ResourceManager.Type.STEEL)).is_true()
	assert_bool(ProgressionManager.is_milestone_completed("era_2")).is_true()
	assert_array(_eras).contains([2])

	# ── Ni el Cuartel ni las Torres mueven la era: no es asunto suyo ──
	_build("barracks")
	_build("tower")
	_build("tower")
	assert_int(ProgressionManager.current_era).is_equal(2)
	assert_bool(ResourceManager.is_unlocked(ResourceManager.Type.OIL)).is_false()
	# Cuartel + 2 Torres es el hito del Comandante.
	assert_bool(ProgressionManager.is_milestone_completed("military_ready")).is_true()

	# ── La Refineria abre la Era 3 ──
	var refinery: Node3D = _place("refinery")
	assert_int(ProgressionManager.current_era).override_failure_message(
		"la era avanzo al COLOCAR la Refineria, no al terminarla").is_equal(2)
	_finish_building()
	assert_object(refinery).is_not_null()
	assert_int(ProgressionManager.current_era).is_equal(3)
	assert_bool(ResourceManager.is_unlocked(ResourceManager.Type.OIL)).is_true()
	assert_bool(ProgressionManager.is_milestone_completed("era_3")).is_true()
	assert_array(_eras).is_equal([2, 3])

	# ── El Mercader y el General cierran los ocho hitos previos a la victoria ──
	_trade_ten_times()
	assert_bool(ProgressionManager.is_milestone_completed("market_10_trades")).is_true()
	_bankroll()
	_build("headquarters")
	assert_bool(ProgressionManager.is_milestone_completed("hq_built")).is_true()

	# Ocho de nueve: el noveno es la victoria, y todavia no se ha peleado.
	assert_int(ProgressionManager.milestones_completed.size()).is_equal(8)
	assert_bool(ProgressionManager.is_milestone_completed("hq_max")).is_false()
	assert_array(_victories).is_empty()

## ⚠ PENDIENTE — fallo real, no se arregla desde aqui.
##
## **Los limites por edificio no limitan nada.**
## `BuildingPlacer.count_building()` (`scripts/buildings/BuildingPlacer.gd:720`)
## cuenta hijos del contenedor comparando `child.name == building_id`, pero el
## nodo se bautiza con el id del edificio en `_create_building_mesh()` (`:655`,
## `root.name = data.id`) y Godot renombra a los hermanos que repiten nombre
## ("house", "house2", "house3"...). Asi que el contador **devuelve 1 pase lo que
## pase**. Medido: con 4 Casas y 2 Torres en pie, `count_building()` dice 1 y 1.
##
## Lo que eso rompe, todo aguas abajo del mismo contador:
##   · `_check_building_limit()` (`:727`) nunca salta: `GameConfig.building_limits`
##     es letra muerta y se pueden levantar **dos Cuarteles Generales** aunque su
##     limite sea 1 — y el Cuartel General es el edificio que convoca el final.
##   · `ArmyManager.barracks_count()` (`scripts/services/ArmyManager.gd:71`) lee
##     este mismo metodo, asi que se queda en 1: `get_capacity()` se congela en
##     3+8=11 y `max_slots()` en una sola plaza. Construir el segundo y el tercer
##     Cuartel no hace absolutamente nada.
##   · `ResourceManager.set_warehouse_count(count_building("warehouse"))` (`:367`
##     al colocar y `:315` al demoler)
##     deja el almacen compartido en un solo Almacen. `GameManager._load_game()`
##     si los cuenta bien (uno por entrada guardada), asi que el tope **sube al
##     guardar y volver a cargar**: el jugador construye cinco Almacenes, no nota
##     nada, reinicia y de pronto le caben 2000 mas.
##
## `_check_prerequisites()` se salva de milagro, porque solo pregunta por >= 1.
##
## Ningun test lo veia porque todo el mundo cuenta edificios por
## `GridManager.get_all_buildings()`, que si es fiable; `count_building()` es la
## unica via alternativa y solo la usa el propio placer.
func test_the_building_limit_actually_limits() -> void:
	_open_the_frontier()
	# La colonia abierta deja 4 Casas en pie: el contador del placer tiene que
	# decir lo mismo que la rejilla.
	assert_int(_placer.count_building("house")).override_failure_message(
		"el placer cuenta %d Casas y en la rejilla hay %d" % [
			_placer.count_building("house"), _count("house")]).is_equal(_count("house"))

	# Y el limite tiene que limitar: se intentan dos Almacenes de mas.
	var limit: int = GameConfig.get_building_limit("warehouse")
	for i in range(limit + 2):
		_bankroll()
		_try_to_place("warehouse")
		_finish_building()
	assert_int(_count("warehouse")).override_failure_message(
		"se levantaron %d Almacenes con el limite en %d" % [_count("warehouse"), limit]
	).is_less_equal(limit)

# ══════════════════════════════════════════════════════════════════════
# 3. La Tormenta muerde
# ══════════════════════════════════════════════════════════════════════

func test_a_whole_storm_cycle_bites_the_base_and_settles_its_tithe() -> void:
	_open_the_frontier()
	_industrialise()
	# Bolsa modesta: con 4000 de cada cosa el Diezmo se llevaria una fortuna y el
	# reparto dejaria de leerse.
	ResourceManager.set_amounts({"gold": 400, "wood": 300, "steel": 100, "oil": 0})
	PopulationManager.load_save_data({
		"population": PopulationManager.get_population(), "morale": 100})

	var cycle: StormCycle = StormManager.get_cycle()
	assert_bool(StormManager.is_armed()).is_true()
	# La severidad se la gana la base creciendo; aqui se pone al maximo a mano
	# para que una sola tormenta baste y el caso no dure veinte minutos.
	cycle.severity = GameConfig.storm_severity_max
	cycle.deferred_severity = 0
	cycle.seconds_left = 0.01

	var gold_mine: Node3D = _first_node_of("gold_mine")
	var nucleo: Node3D = _first_node_of("nucleo")
	assert_object(gold_mine).is_not_null()
	assert_object(nucleo).is_not_null()

	# Lo que rinde la mina en calma, para poder comparar.
	var calm_yield: int = _one_production_tick(gold_mine)
	assert_int(calm_yield).override_failure_message(
		"la mina no produce nada en calma: el resto del caso no mide nada").is_greater(0)

	# ── Aviso ──
	_advance_storm_until(StormCycle.Phase.WARNING, "el aviso nunca llego")
	assert_int(_incoming).is_greater(0)
	assert_float(GameConfig.event_production_multiplier).override_failure_message(
		"el Aviso no puede cobrar produccion: es la unica ventana limpia").is_equal(1.0)

	# El Aviso puede resultar en nada (una falsa alarma de cada cuatro). Para que
	# el caso no dependa de esa tirada se fuerza el paso a Ceniza cortando la
	# fase por la mano, que es lo unico que el azar decide aqui.
	if cycle.phase == StormCycle.Phase.WARNING:
		_publish_storm(cycle._enter_ash())

	# ── Ceniza: ensucia, no tumba ──
	assert_int(cycle.phase).is_equal(StormCycle.Phase.ASH)
	assert_float(GameConfig.event_production_multiplier).is_equal(
		GameConfig.storm_ash_production_multiplier)
	var ruined_in_ash: int = _ruined.size()
	_advance_storm_until(StormCycle.Phase.STORM, "la ceniza nunca dio paso a la tormenta")
	assert_int(_ruined.size()).override_failure_message(
		"la ceniza tumbo edificios: tiene que ensuciar, no demoler").is_equal(ruined_in_ash)

	# ── Tormenta: la produccion se arrastra y los techos se van ──
	assert_float(GameConfig.event_production_multiplier).is_equal(
		GameConfig.storm_production_multiplier)
	var storm_yield: int = _one_production_tick(gold_mine)
	assert_int(storm_yield).override_failure_message(
		"la produccion no cayo con la tormenta encima (%d en calma, %d bajo la tormenta)" % [
			calm_yield, storm_yield]).is_less(calm_yield)

	# La fase del Diezmo no se puede esperar mirando `get_phase()`: cobrarlo y
	# saldarlo ocurren dentro del mismo `_process()` que lo abre, asi que el reloj
	# vuelve a la calma sin que nadie llegue a verlo en TITHE. Lo que se espera es
	# el hecho: o hay tablero, o ya se resolvio.
	_advance_storm_until_the_assessors_arrive()

	# Algo cayo, y no fue el Nucleo. La regla del Nucleo es el suelo de la
	# partida: se puede caer hasta el fondo, no se puede perder.
	assert_int(_ruined.size()).override_failure_message(
		"una tormenta a severidad maxima no dejo un solo edificio en ruinas").is_greater(0)
	assert_bool(BuildingHealth.is_ruined(nucleo)).override_failure_message(
		"el Nucleo se rompio: eso no puede pasar nunca").is_false()
	assert_int(BuildingHealth.get_health(nucleo)).is_equal(BuildingHealth.get_max_health(nucleo))

	# ── El Diezmo: se cobra o se repele, pero se resuelve ──
	if CombatManager.is_board_open():
		# Hay guarnicion o torres en pie: los Tasadores tienen que pasar por encima.
		_play_open_board_with_the_ai()
		await _let_the_ai_thread_unwind()
		CombatManager.end_encounter()
	assert_int(_tithes.size()).override_failure_message(
		"el Diezmo ni se cobro ni se repelio: la fase se quedo colgada").is_equal(1)

	# Y el reloj vuelve a correr, con la penalizacion levantada.
	assert_int(StormManager.get_phase()).override_failure_message(
		"el ciclo no volvio a la calma tras saldar el Diezmo").is_equal(StormCycle.Phase.CALM)
	assert_int(StormManager.storms_survived()).is_equal(1)
	assert_float(GameConfig.event_production_multiplier).is_equal(1.0)
	assert_bool(CombatManager.is_board_open()).override_failure_message(
		"quedo tablero colgado tras el Diezmo: todo lo que venga detras se juega a ciegas"
	).is_false()

## Empuja el reloj de la Tormenta por su propio `_process()` hasta llegar a la
## fase pedida. Se detiene tambien si los Tasadores se adelantan, para que un
## ciclo que se salte una fase no acabe corriendo ciclos enteros de mas. Con
## guarda: si no llega, el caso falla diciendo donde se quedo.
func _advance_storm_until(phase: int, what_failed: String) -> void:
	var guard := 0
	while StormManager.get_phase() != phase:
		guard += 1
		if guard > 400 or not _tithes.is_empty() or CombatManager.is_board_open():
			assert_bool(false).override_failure_message(
				"%s (fase %d tras %d pasos de reloj, %d Diezmos por el camino)" % [
					what_failed, StormManager.get_phase(), guard, _tithes.size()]).is_true()
			return
		StormManager._process(_storm_step())

## Corre el reloj hasta que el Diezmo aparece: o abre tablero, o ya esta saldado.
func _advance_storm_until_the_assessors_arrive() -> void:
	var guard := 0
	while _tithes.is_empty() and not CombatManager.is_board_open():
		guard += 1
		if guard > 400:
			assert_bool(false).override_failure_message(
				"la tormenta no llego a pasar: %d pasos de reloj y los Tasadores sin bajar (fase %d)" % [
					guard, StormManager.get_phase()]).is_true()
			return
		StormManager._process(_storm_step())

## Medio intervalo de tic por paso: asi ningun mordisco de la Tormenta se pierde
## por el camino y el recorrido entero cabe en la guarda.
func _storm_step() -> float:
	return GameConfig.get_storm_tick_interval() * 0.5

## Publica a mano una lista de eventos del ciclo, igual que hace `_process()`.
func _publish_storm(events: Array) -> void:
	StormManager._publish(events)

func _first_node_of(building_id: String) -> Node3D:
	for info in GridManager.get_all_buildings():
		if (info["data"] as BuildingData).id == building_id:
			return info["node"]
	return null

## Lo que un edificio rinde en un ciclo de produccion, ahora mismo.
func _one_production_tick(node: Node3D) -> int:
	var before: int = ResourceManager.get_amount(ResourceManager.Type.GOLD)
	ProductionManager._tick_production(GameConfig.get_production_interval(1.0) + 1.0)
	return ResourceManager.get_amount(ResourceManager.Type.GOLD) - before

# ══════════════════════════════════════════════════════════════════════
# 4. Ejercito y expedicion
# ══════════════════════════════════════════════════════════════════════

func test_an_expedition_comes_home_with_its_survivors_and_its_loot_once() -> void:
	_open_the_frontier()
	_industrialise()
	_raise_an_army({"infantry": 3, "artillery": 2})

	var party: Dictionary = {"infantry": 3, "artillery": 2}
	var army_before: Dictionary = (ArmyManager.get_save_data()["units"] as Dictionary).duplicate()
	assert_int(ArmyManager.get_total_units()).is_equal(5)

	# Almacen vacio y con sitio de sobra: asi el botin que llega se puede comparar
	# al centimo con lo que la expedicion dice haber ganado.
	ResourceManager.set_amounts({"gold": 0, "wood": 0, "steel": 0, "oil": 0})
	var stores_before: Dictionary = _resource_amounts()

	assert_bool(CombatManager.launch_expedition(party, EXPEDITION_SEED)).override_failure_message(
		"la columna no pudo salir: %s" % CombatManager.can_launch(party)["reason"]).is_true()

	# Mientras la columna esta fuera sigue contando en el Poder Militar: nada se
	# descuenta hasta saber quien vuelve.
	assert_int(ArmyManager.get_total_units()).override_failure_message(
		"el ejercito se descuento al salir, y solo debe descontarse al volver").is_equal(5)
	assert_dict(CombatManager.get_units_on_expedition()).is_equal(party)
	assert_dict(CombatManager.get_deployable_units()).is_empty()

	var saved_midway := false
	var guard := 0
	while CombatManager.has_active_expedition():
		guard += 1
		if guard > 60:
			assert_bool(false).override_failure_message(
				"la expedicion se atasco en el nodo %d tras %d pasos (tablero abierto: %s)" % [
					CombatManager.get_expedition().current_node, guard,
					str(CombatManager.is_board_open())]).is_true()
			break

		if CombatManager.get_encounter() == null:
			# Entre nodos: primero la carta, despues la ruta.
			if CombatManager.has_pending_draft():
				assert_bool(CombatManager.apply_draft(0)).override_failure_message(
					"la carta del draft no se pudo tomar en el paso %d" % guard).is_true()
			# ── Punto de guardado 1: a mitad de campana ──
			if not saved_midway:
				saved_midway = true
				_assert_a_save_and_load_puts_everything_back("a mitad de expedicion")
			var exits: Array = CombatManager.get_expedition().current_exits()
			if exits.is_empty():
				break
			assert_bool(CombatManager.select_node(int(exits[0]))).override_failure_message(
				"no se pudo entrar en el nodo %d" % int(exits[0])).is_true()
			continue

		_play_open_board_with_the_ai()
		await _let_the_ai_thread_unwind()
		if CombatManager.is_board_open():
			CombatManager.end_encounter()

	# ── De vuelta en casa ──
	assert_bool(CombatManager.has_active_expedition()).is_false()
	assert_bool(CombatManager.is_board_open()).override_failure_message(
		"la campana termino dejando tablero colgado: a partir de ahi todo Diezmo se juega a ciegas"
	).is_false()
	assert_int(_expedition_ends.size()).override_failure_message(
		"la expedicion se liquido %d veces" % _expedition_ends.size()).is_equal(1)

	var ended: Array = _expedition_ends[0]
	var rewards: Dictionary = ended[1]
	var losses: Dictionary = ended[2]

	# El ejercito cuadra con los supervivientes: lo que habia, menos los caidos.
	var expected: Dictionary = {}
	for unit_id in army_before:
		var left: int = int(army_before[unit_id]) - int(losses.get(unit_id, 0))
		if left > 0:
			expected[unit_id] = left
	assert_dict(ArmyManager.get_save_data()["units"]).override_failure_message(
		"el ejercito no cuadra con los supervivientes (salieron %s, cayeron %s)" % [
			str(army_before), str(losses)]).is_equal(expected)
	for unit_id in losses:
		assert_int(int(losses[unit_id])).is_less_equal(int(army_before.get(unit_id, 0)))

	# Y el botin llego al almacen una sola vez.
	var stores_after: Dictionary = _resource_amounts()
	for res_name in stores_after:
		var delta: int = int(stores_after[res_name]) - int(stores_before[res_name])
		assert_int(delta).override_failure_message(
			"el botin de %s no cuadra: %d en el almacen frente a %d en el parte" % [
				res_name, delta, int(rewards.get(res_name, 0))]
		).is_equal(int(rewards.get(res_name, 0)))

# ══════════════════════════════════════════════════════════════════════
# 5. El final: la Auditoria Final y la Victoria Imperial
# ══════════════════════════════════════════════════════════════════════

## El cableado del final del juego, de punta a punta: convocar, bajar, relevar
## oleadas y ganar.
##
## ⚠ Con la escalada de oleadas TAL COMO VIENE, este recorrido no se puede ganar
## y el caso no podria existir. Ver `test_the_shipped_siege_is_unwinnable_today`,
## justo debajo, que documenta el hallazgo con numeros. Aqui se aplana la escala
## (mismo numero de oleadas, misma composicion, sin multiplicador por oleada, por
## era ni de oleada final) porque lo que este caso prueba es la **costura**: que
## el nivel 3 convoque en vez de ganar, que cerrar un parte abra la oleada
## siguiente, que ganar la ultima pare la Tormenta y anuncie la victoria una sola
## vez. El balance del asedio se prueba en `tests/combat/test_final_audit.gd`.
func test_the_capstone_summons_the_audit_and_surviving_it_wins_the_game() -> void:
	_flatten_the_siege()
	_open_the_frontier()
	_industrialise()
	_trade_ten_times()
	# La guarnicion mas fuerte que el juego permite: el tope de despliegue en
	# vehiculos, mas las dotaciones de las dos torres.
	_raise_an_army({"vehicle": GameConfig.combat_deploy_cap})
	_bankroll(9000, 9000, 9000, 9000)
	var hq: Node3D = _build("headquarters")
	assert_object(hq).is_not_null()

	# ── El Cuartel General no gana: convoca ──
	_upgrade(hq, 2)
	assert_bool(ProgressionManager.is_milestone_completed("hq_max")).is_false()
	assert_object(ProgressionManager.final_audit).is_null()

	seed(AUDIT_SEED)   # `_audit_seed()` llama a randi(): asi el asedio es el mismo
	_upgrade(hq, 3)
	assert_bool(ProgressionManager.is_milestone_completed("hq_max")).is_true()
	assert_array(_victories).override_failure_message(
		"el nivel 3 gano la partida por si solo: tiene que convocar a la Regencia"
	).is_empty()
	assert_bool(ProgressionManager.is_final_audit_pending()).is_true()
	assert_bool(ProgressionManager.is_final_audit_active()).is_false()
	assert_int(ProgressionManager.milestones_completed.size()).is_equal(9)

	# ── Punto de guardado 2: asedio convocado y sin empezar ──
	_assert_a_save_and_load_puts_everything_back("con el asedio convocado")

	# Con la Regencia convocada la guarnicion no sale de casa.
	assert_bool(bool(CombatManager.can_launch({"infantry": 1}).get("ok", true))).override_failure_message(
		"se pudo lanzar una expedicion con el asedio convocado").is_false()

	# ── Que bajen ──
	var waves: int = ProgressionManager.final_audit.wave_count()
	assert_int(waves).is_greater_equal(GameConfig.final_audit_waves.x)
	assert_bool(ProgressionManager.begin_final_audit()).is_true()
	assert_bool(ProgressionManager.is_final_audit_active()).is_true()
	assert_bool(CombatManager.is_in_encounter()).override_failure_message(
		"bajar la Auditoria no puso ninguna oleada en el tablero").is_true()

	var fought: int = await _fight_the_siege_to_the_end()

	# ── La victoria ──
	assert_int(_audit_lost).override_failure_message(
		"el asedio se dio por perdido en la oleada %d" % ProgressionManager.final_audit.current_wave
	).is_equal(0)
	assert_bool(ProgressionManager.final_audit.is_won()).override_failure_message(
		"el asedio no se gano tras jugar %d oleadas de %d" % [fought, waves]).is_true()
	assert_int(fought).override_failure_message(
		"se jugaron %d oleadas de las %d que convoco la Regencia" % [fought, waves]).is_equal(waves)
	assert_int(_victories.size()).override_failure_message(
		"la victoria se anuncio %d veces" % _victories.size()).is_equal(1)

	# La Tormenta se para para siempre, y el mundo se calla antes que la pantalla.
	assert_int(_halts).is_equal(1)
	assert_bool(StormManager.is_halted()).is_true()
	assert_bool(StormManager.is_armed()).is_false()
	assert_int(StormManager.get_phase()).is_equal(StormCycle.Phase.CALM)
	assert_float(GameConfig.event_production_multiplier).is_equal(1.0)

	# Y el reloj ya no arma otro ciclo por mucho que corra.
	var avisos: int = _incoming
	for i in range(200):
		StormManager._process(GameConfig.get_storm_tick_interval())
	assert_int(_incoming).override_failure_message(
		"la Tormenta volvio despues de los creditos").is_equal(avisos)
	assert_int(StormManager.get_phase()).is_equal(StormCycle.Phase.CALM)

	# El tablero queda limpio: ganar no puede dejar un encuentro colgado.
	assert_bool(CombatManager.is_board_open()).is_false()

## El asedio, con la escalada TAL COMO VIENE. Este caso nacio en rojo: con la
## guarnicion mas fuerte que el juego permite se perdia siempre en la oleada 2,
## en todas las semillas probadas y en las tres longitudes posibles. El final del
## juego no se podia terminar.
##
## La causa no era el numero de oleadas ni la composicion, sino que el
## multiplicador toca HP y ATK **a la vez**, asi que el poder efectivo sube al
## cuadrado; y que la era entraba dos veces, porque el Cuartel General es de era
## 3 y el asedio no se convoca antes. Medido con `tools/siege_probe.gd`, tabla en
## `docs/17-balance-asedio.md`.
##
## Ahora se mide en vez de afirmarse sobre una semilla: con los valores reales la
## guarnicion maxima gana el 82% de las veces, asi que una sola semilla seria una
## moneda al aire con un 18% de cruz. Lo que este caso vigila es que la mayoria
## se gane, y que no se ganen todas: duro y ganable.
func test_the_siege_is_hard_but_winnable_with_a_full_garrison() -> void:
	_open_the_frontier()
	_industrialise()
	var won := 0
	for i in range(SIEGE_SAMPLES):
		# Guarnicion entera y sana en cada intento: lo que se mide es el asedio,
		# no lo que quedo del anterior.
		ArmyManager.reset()
		_raise_an_army({"vehicle": GameConfig.combat_deploy_cap})
		ProgressionManager.final_audit = null
		seed(AUDIT_SEED + i * 101)
		assert_bool(ProgressionManager.summon_final_audit()).is_true()
		assert_bool(ProgressionManager.begin_final_audit()).is_true()
		await _fight_the_siege_to_the_end()
		if ProgressionManager.final_audit.is_won():
			won += 1
		CombatManager.reset()

	assert_int(won).override_failure_message(
		"la guarnicion maxima gano %d de %d asedios; el diseno pide que la mayoria se gane"
		% [won, SIEGE_SAMPLES]).is_greater(SIEGE_SAMPLES / 2)

## Y el otro lado del objetivo: la guarnicion minima con la que se puede
## reconvocar no basta. Si bastara, perder el asedio no costaria nada.
func test_the_smallest_garrison_that_can_resummon_does_not_win() -> void:
	_open_the_frontier()
	_industrialise()
	var won := 0
	for i in range(SIEGE_SAMPLES):
		ArmyManager.reset()
		_raise_an_army({"infantry": 3})
		ProgressionManager.final_audit = null
		seed(AUDIT_SEED + i * 101)
		assert_bool(ProgressionManager.summon_final_audit()).is_true()
		assert_bool(ProgressionManager.begin_final_audit()).is_true()
		await _fight_the_siege_to_the_end()
		if ProgressionManager.final_audit.is_won():
			won += 1
		CombatManager.reset()

	assert_int(won).override_failure_message(
		"tres infantes ganaron %d de %d asedios: la Regencia no da miedo"
		% [won, SIEGE_SAMPLES]).is_less(2)

## Juega el asedio entero con la IA a los dos lados, cerrando cada parte como
## hace la pantalla. Devuelve cuantas oleadas se llegaron a pelear.
func _fight_the_siege_to_the_end() -> int:
	var fought := 0
	var guard := 0
	var waves: int = ProgressionManager.final_audit.wave_count()
	while ProgressionManager.is_final_audit_active():
		guard += 1
		if guard > waves + 3:
			assert_bool(false).override_failure_message(
				"el asedio se atasco en la oleada %d de %d tras %d vueltas" % [
					ProgressionManager.final_audit.current_wave, waves, guard]).is_true()
			break
		if not CombatManager.is_board_open():
			break
		_play_open_board_with_the_ai()
		await _let_the_ai_thread_unwind()
		fought += 1
		# Cerrar el parte es lo que reporta la oleada y, si queda alguna, abre la
		# siguiente dentro de esta misma llamada. Es lo que hace la pantalla.
		CombatManager.end_encounter()
	return fought

## Aplana la escalada de estadisticas del asedio dejando intacto todo lo demas:
## el numero de oleadas sigue saliendo de la semilla dentro del rango de diseño y
## la composicion (linea, cañones desde la segunda, blindados desde la tercera)
## no se toca. Se restaura en `after_test()` junto al resto de GameConfig.
func _flatten_the_siege() -> void:
	GameConfig.final_audit_scale_per_wave = 0.0
	GameConfig.final_audit_scale_per_era = 0.0
	GameConfig.final_audit_last_wave_multiplier = 1.0

## Sube un edificio de nivel por el mismo camino que la interfaz: pagar y esperar.
func _upgrade(node: Node3D, level: int) -> void:
	var data: BuildingData = GridManager.get_building_info(node)["data"]
	ProductionManager.start_upgrade(node, data, level)
	assert_bool(ProductionManager.is_constructing(node)).override_failure_message(
		"la mejora a nivel %d de %s ni siquiera empezo (coste %s)" % [
			level, data.id, str(GameConfig.get_upgrade_cost(data, level))]).is_true()
	_finish_building()
	assert_int(int(node.get_meta("level", 1))).override_failure_message(
		"la mejora a nivel %d de %s no llego a termino" % [level, data.id]).is_equal(level)

# ══════════════════════════════════════════════════════════════════════
# 6. Y el otro final: perder el asedio no cierra la partida
# ══════════════════════════════════════════════════════════════════════

func test_losing_the_siege_ruins_the_base_but_never_ends_the_game() -> void:
	_open_the_frontier()
	_industrialise()
	# Una guarnicion de uno, y aqui con la escalada TAL COMO VIENE: contra tres a
	# cinco oleadas que crecen, sin curas y sin relevos, el asedio esta perdido de
	# antemano. No se afirma en que oleada cae, solo que el asedio acaba perdido.
	_raise_an_army({"infantry": 1})
	ResourceManager.set_amounts({"gold": 500, "wood": 400, "steel": 200, "oil": 100})
	var stores_before: Dictionary = _resource_amounts()

	seed(AUDIT_SEED)
	assert_bool(ProgressionManager.summon_final_audit()).is_true()
	assert_bool(ProgressionManager.begin_final_audit()).is_true()
	await _fight_the_siege_to_the_end()

	assert_bool(ProgressionManager.is_final_audit_lost()).override_failure_message(
		"un solo soldado sobrevivio al asedio entero").is_true()
	assert_int(_audit_lost).is_equal(1)

	# ── Perder cuesta: Diezmo maximo y la base tocada ──
	assert_int(_tithes.size()).override_failure_message(
		"perder el asedio no cobro ningun Diezmo").is_equal(1)
	assert_bool(bool(_tithes[0][0])).override_failure_message(
		"el Diezmo de la derrota figura como repelido").is_false()
	assert_dict(_tithes[0][1]).override_failure_message(
		"los Tasadores se fueron con las manos vacias").is_not_empty()
	assert_int(ResourceManager.get_total_stored()).is_less(
		int(stores_before["gold"]) + int(stores_before["wood"])
		+ int(stores_before["steel"]) + int(stores_before["oil"]))
	assert_bool(_some_building_is_damaged()).override_failure_message(
		"perder el asedio dejo la base intacta").is_true()

	# ── Pero no es fin de partida ──
	assert_array(_victories).is_empty()
	assert_bool(StormManager.is_halted()).override_failure_message(
		"perder el asedio paro la Tormenta: perder no es un final").is_false()
	assert_bool(BuildingHealth.is_ruined(_first_node_of("nucleo"))).is_false()
	assert_bool(CombatManager.is_board_open()).is_false()

	# Se rehace el ejercito y se les vuelve a llamar. (Reparar los edificios
	# deberia ser parte de esto y hoy no se puede: ver
	# `test_a_damaged_building_can_be_repaired`, aqui debajo.)
	assert_bool(ProgressionManager.can_resummon_final_audit()).override_failure_message(
		"con el ejercito por rehacer, reconvocar deberia estar cerrado").is_false()

	_bankroll()
	_train("infantry", GameConfig.final_audit_resummon_min_units)
	assert_bool(ProgressionManager.can_resummon_final_audit()).is_true()
	var summons_before: int = ProgressionManager.final_audit.summons
	assert_bool(ProgressionManager.summon_final_audit()).override_failure_message(
		"no se pudo volver a convocar a la Regencia").is_true()
	assert_int(ProgressionManager.final_audit.summons).is_equal(summons_before + 1)
	assert_bool(ProgressionManager.is_final_audit_pending()).is_true()
	assert_bool(ProgressionManager.is_final_audit_lost()).is_false()

func _some_building_is_damaged() -> bool:
	for info in GridManager.get_all_buildings():
		if BuildingHealth.is_damaged(info["node"]):
			return true
	return false

## ⚠ PENDIENTE — fallo real, no se arregla desde aqui.
##
## **Reparar un edificio es imposible en el juego de hoy.** Es la otra mitad del
## ciclo de la Tormenta: la Tormenta rompe techos y la partida consiste en
## repararlos antes de la siguiente. Hoy no se puede reparar ninguno.
##
## La costura: `BuildingHealth.repair_cost()`
## (`scripts/services/BuildingHealth.gd:86-101`) devuelve el coste con claves de
## **texto** —"gold", "steel", "oil", "wood"—, pero `ResourceManager.can_afford()`
## y `spend_cost()` (`scripts/services/ResourceManager.gd:136` y `:178`) esperan
## claves del enum `ResourceManager.Type`, que es lo que devuelve
## `BuildingData.get_cost()` (`scripts/buildings/BuildingData.gd:52`). El
## diccionario cruza la frontera con el tipo equivocado y `has_enough()` revienta:
##
##   SCRIPT ERROR: Invalid type in function 'has_enough' ...
##   Cannot convert argument 1 from String to int.
##     at can_afford (res://scripts/services/ResourceManager.gd:138)
##     at can_repair (res://scripts/services/BuildingHealth.gd:107)
##
## Efecto en partida: `can_repair()` devuelve siempre `{ok:false}`, asi que el
## boton REPARAR de `BuildingInfoPanel` (`scripts/ui/BuildingInfoPanel.gd:445`)
## esta permanentemente deshabilitado — y el precio que ese mismo panel pinta
## encima (`:435`) si se lee bien, porque el pintado si usa nombres de texto. El
## jugador ve el coste, tiene el oro, y el boton no se deja pulsar.
##
## Escenario para reproducirlo: cualquier edificio tocado (una tormenta, el
## Diezmo o perder la Auditoria) con recursos de sobra en el almacen.
##
## Ningun test lo veia porque `BuildingHealth` solo se probaba por el lado del
## daño (`tests/storm/test_storm_targets.gd`, `test_operational.gd`), nunca por
## el de la reparacion, que es donde cruza a `ResourceManager`.
func test_a_damaged_building_can_be_repaired() -> void:
	_open_the_frontier()
	_bankroll()
	var sawmill: Node3D = _first_node_of("sawmill")
	var house: Node3D = _first_node_of("house")
	assert_object(house).is_not_null()
	assert_object(sawmill).is_not_null()

	BuildingHealth.damage_building(house, BuildingHealth.get_max_health(house) / 2)
	assert_bool(BuildingHealth.is_damaged(house)).is_true()

	var cost: Dictionary = BuildingHealth.repair_cost(house)
	assert_dict(cost).override_failure_message(
		"un edificio a medio romper tiene que costar algo repararlo").is_not_empty()
	assert_bool(ResourceManager.can_afford(cost)).override_failure_message(
		"con el almacen lleno, el coste de reparacion tiene que ser asumible").is_true()
	assert_bool(bool(BuildingHealth.can_repair(house)["ok"])).override_failure_message(
		"el juego dice que no se puede reparar: %s" % str(BuildingHealth.can_repair(house))).is_true()
	assert_bool(BuildingHealth.repair(house)).is_true()
	assert_bool(BuildingHealth.is_damaged(house)).is_false()

# ══════════════════════════════════════════════════════════════════════
# 7. Guardar y cargar a mitad del recorrido
# ══════════════════════════════════════════════════════════════════════

## Guarda con GameManager, borra del mapa todo lo que hay, resetea los servicios
## y vuelve a cargar. Lo que salga tiene que ser identico a lo que entro.
##
## Se llama desde dentro de las fases, en los dos momentos que mas duelen: con
## una expedicion a medias y con el asedio convocado sin empezar.
func _assert_a_save_and_load_puts_everything_back(moment: String) -> void:
	# El tope del almacen se aplica al cargar, asi que se aplica tambien antes de
	# la foto: si no, la comparacion acusaria al guardado de un recorte legitimo.
	ResourceManager.clamp_to_storage()
	var before: Dictionary = _snapshot()

	GameManager.save_game()
	assert_bool(FileAccess.file_exists(SAVE_PATH)).override_failure_message(
		"guardar %s no escribio nada en disco" % moment).is_true()

	_wipe_the_world()
	GameManager._load_game()

	var after: Dictionary = _snapshot()
	for key in before:
		assert_that(after[key]).override_failure_message(
			"al cargar %s, '%s' volvio distinto:\n  antes: %s\n  ahora: %s" % [
				moment, key, str(before[key]), str(after[key])]
		).is_equal(before[key])

## Todo lo que `GameManager.clear_save()` deja en cero, menos recargar la escena:
## el mundo desaparece y solo el fichero de guardado sabe lo que habia.
func _wipe_the_world() -> void:
	for info in GridManager.get_all_buildings():
		ProductionManager.unregister(info["node"])
	_placer.clear_all_buildings()
	_map.clear_all_deposits()
	GridManager.clear_all()
	ResourceManager.reset()
	ProcessManager.reset()
	ProgressionManager.reset()
	MarketManager.reset()
	PopulationManager.reset()
	RandomEventManager.reset()
	TechTreeManager.reset()
	ArmyManager.reset()
	CombatManager.reset()
	StormManager.reset()
	TutorialManager.reset()
	GameManager._warehouse_count = 0
	assert_int(ProgressionManager.current_era).override_failure_message(
		"el borrado no dejo el mundo en blanco").is_equal(1)

## La foto que tiene que sobrevivir al viaje de ida y vuelta por el disco.
func _snapshot() -> Dictionary:
	var milestones: Array = ProgressionManager.milestones_completed.keys()
	milestones.sort()
	return {
		"recursos": _resource_amounts(),
		"edificios": _buildings_by_id(),
		"era": ProgressionManager.current_era,
		"fase": ProgressionManager.current_phase,
		"hitos": milestones,
		"ejercito": (ArmyManager.get_save_data()["units"] as Dictionary).duplicate(),
		"expedicion": _expedition_snapshot(),
		"asedio": _audit_snapshot(),
		"tormenta_armada": StormManager.is_armed(),
	}

func _expedition_snapshot() -> Dictionary:
	var run: Expedition = CombatManager.get_expedition()
	if run == null:
		return {}
	return {
		"id": run.id,
		"semilla": run.seed_value,
		"nodo": run.current_node,
		"columna": run.party.size(),
		"en_pie": run.living_party().size(),
		"botin": run.rewards.duplicate(),
		"limpiados": run.nodes_cleared(),
	}

func _audit_snapshot() -> Dictionary:
	var audit: FinalAudit = ProgressionManager.final_audit
	if audit == null:
		return {}
	return {
		"semilla": audit.seed_value,
		"oleadas": audit.wave_count(),
		"oleada_actual": audit.current_wave,
		"convocatorias": audit.summons,
		"guarnicion": audit.garrison.size(),
		"pendiente": audit.is_pending(),
	}
