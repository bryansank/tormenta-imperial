extends GdUnitTestSuite
## La carga tiene que llegar a una UI que escucha.
##
## BuildingPlacer y MapGenerator se registran en GameManager desde su _ready, y
## en Main.tscn hay trece paneles despues de ellos. La carga corria en el acto,
## dentro del _ready de MapGenerator: expedition_resumed, draft_offered y
## game_load_completed no los oia nadie. Con un draft pendiente en el save, el
## mapa volvia sin respuesta (select_node rechaza mientras haya draft) y la
## partida quedaba bloqueada.

const Placer := preload("res://scripts/buildings/BuildingPlacer.gd")
const MapGen := preload("res://scripts/map/MapGenerator.gd")
const SAVE_PATH := "user://save_game.json"
const BACKUP_PATH := "user://save_game.load_ui.bak"
const PARTY := {"infantry": 2, "artillery": 1}
const SEED := 424242
const Parking := preload("res://tests/save/save_parking.gd")

## Esta suite escribe user://save_game.json. Si corre en la carpeta del jugador
## (lanzada sin tools/run_tests.sh) se salta entera: no hay partida que pisar.
func before(do_skip := Parking.in_player_dir(), skip_reason := "Carpeta de usuario del jugador: lanza los tests con tools/run_tests.sh") -> void:
	pass

var _saved_army: Dictionary = {}
var _saved_population: Dictionary = {}
var _saved_progression: Dictionary = {}
var _saved_storm: Dictionary = {}
var _saved_market: Dictionary = {}
var _saved_events: Dictionary = {}
var _saved_tech: Dictionary = {}
var _saved_tutorial: Dictionary = {}
var _saved_resources: Dictionary = {}
var _saved_era: int = 1
var _saved_warehouses: int = 0
var _saved_gm: Array = []

func before_test() -> void:
	_saved_army = ArmyManager.get_save_data()
	_saved_population = PopulationManager.get_save_data()
	_saved_progression = ProgressionManager.get_save_data()
	_saved_storm = StormManager.get_save_data()
	_saved_market = MarketManager.get_save_data()
	_saved_events = RandomEventManager.get_save_data()
	_saved_tech = TechTreeManager.get_save_data()
	_saved_tutorial = TutorialManager.get_save_data()
	_saved_era = ResourceManager.get_era()
	_saved_warehouses = ResourceManager.get_warehouse_count()
	_saved_resources = {}
	for type in ResourceManager.get_all():
		_saved_resources[ResourceManager.get_type_name(type)] = int(ResourceManager.get_all()[type])
	_saved_gm = [GameManager._placer, GameManager._map_gen, GameManager._started, GameManager._camera]
	CombatManager.reset()
	PopulationManager.load_save_data({"morale": 100})

func after_test() -> void:
	CombatManager.end_encounter()
	CombatManager.reset()
	# Otra suite pudo dejar aqui nodos ya liberados: se devuelven solo si viven.
	GameManager._placer = _saved_gm[0] if is_instance_valid(_saved_gm[0]) else null
	GameManager._map_gen = _saved_gm[1] if is_instance_valid(_saved_gm[1]) else null
	GameManager._started = _saved_gm[2]
	GameManager._camera = _saved_gm[3] if is_instance_valid(_saved_gm[3]) else null
	GameManager._warehouse_count = 0
	ProgressionManager.final_audit = null
	ProgressionManager.load_save_data(_saved_progression)
	StormManager.load_save_data(_saved_storm)
	ArmyManager.load_save_data(_saved_army)
	PopulationManager.load_save_data(_saved_population)
	MarketManager.load_save_data(_saved_market)
	RandomEventManager.load_save_data(_saved_events)
	TechTreeManager.load_save_data(_saved_tech)
	TutorialManager.load_save_data(_saved_tutorial)
	ResourceManager.set_era(_saved_era)
	ResourceManager.set_warehouse_count(_saved_warehouses)
	ResourceManager.set_amounts(_saved_resources)

func _screen() -> CanvasLayer:
	var screen: CanvasLayer = auto_free(load("res://scenes/ui/BattleScreen.tscn").instantiate())
	add_child(screen)
	return screen

func _launch_and_win_a_node() -> void:
	ArmyManager.load_save_data({"units": PARTY.duplicate(), "training": [], "upkeep_accum": 0.0})
	assert_bool(CombatManager.launch_expedition(PARTY, SEED)).is_true()
	for unit in CombatManager.get_units():
		if unit.side == 1 and unit.is_alive():
			unit.take_damage(unit.max_hp * 10)
	assert_bool(CombatManager.end_turn()).is_true()
	assert_bool(CombatManager.has_pending_draft()).is_true()

# ── La red de seguridad de la UI ─────────────────────────────────────

func test_a_draft_loaded_before_the_screen_existed_is_still_offered() -> void:
	_launch_and_win_a_node()
	var data: Dictionary = CombatManager.get_save_data()
	CombatManager.end_encounter()
	CombatManager.reset()
	# La carga, sin nadie escuchando: exactamente lo que pasaba al arrancar.
	CombatManager.load_save_data(data)
	assert_bool(CombatManager.has_pending_draft()).is_true()

	var screen := _screen()
	await await_idle_frame()
	assert_int(screen.current_view()).override_failure_message(
		"la pantalla no abrio el mapa de la campana cargada").is_equal(screen.View.MAP)
	assert_bool(screen.is_draft_open()).override_failure_message(
		"el draft cargado no se ofrecio: el mapa quedaria bloqueado").is_true()
	# Y elegir la carta desbloquea el mapa, que es lo que antes no pasaba.
	screen._draft_cards.get_child(0).pressed.emit()
	assert_bool(CombatManager.has_pending_draft()).is_false()
	var exit: int = int(CombatManager.get_expedition().current_exits()[0])
	assert_bool(CombatManager.select_node(exit)).is_true()

func test_the_safety_net_does_not_open_anything_twice() -> void:
	_launch_and_win_a_node()
	var data: Dictionary = CombatManager.get_save_data()
	CombatManager.end_encounter()
	CombatManager.reset()
	var screen := _screen()
	await await_idle_frame()
	CombatManager.load_save_data(data)   # con la pantalla ya escuchando
	assert_bool(screen.is_draft_open()).is_true()
	var cards: int = screen.draft_card_count()
	screen.sync_with_state()
	await await_idle_frame()
	assert_int(screen.draft_card_count()).is_equal(cards)
	assert_bool(screen.is_draft_open()).is_true()

func test_without_a_campaign_the_safety_net_stays_quiet() -> void:
	var screen := _screen()
	await await_idle_frame()
	assert_int(screen.current_view()).is_equal(screen.View.NONE)
	assert_bool(screen.visible).is_false()

# ── El orden de arranque ─────────────────────────────────────────────

func test_the_game_starts_only_once_the_whole_scene_is_ready() -> void:
	Parking.park(BACKUP_PATH)
	GridManager.clear_all()
	GameManager._placer = null
	GameManager._map_gen = null
	GameManager._started = false

	# Una Main en miniatura: placer y mapa primero, y un "panel" detras.
	var main := Node.new()
	main.name = "FakeMain"
	var placer: Node3D = Placer.new()
	placer.name = "BuildingPlacer"
	var map: Node = MapGen.new()
	map.name = "MapGenerator"
	var panel := Node.new()
	panel.name = "LastPanel"
	main.add_child(placer)
	main.add_child(map)
	main.add_child(panel)

	var panel_ready_at_start := [null]
	var probe := func() -> void: panel_ready_at_start[0] = panel.is_node_ready()
	EventBus.game_new_started.connect(probe)
	get_tree().root.add_child(main)
	EventBus.game_new_started.disconnect(probe)

	assert_bool(GameManager._started).is_true()
	assert_that(panel_ready_at_start[0]).override_failure_message(
		"la partida nueva se anuncio antes de que el ultimo nodo de la escena estuviera listo"
	).is_equal(true)

	for info in GridManager.get_all_buildings():
		ProductionManager.unregister(info["node"])
	placer.clear_all_buildings()
	map.clear_all_deposits()
	GridManager.clear_all()
	get_tree().root.remove_child(main)
	main.free()
	Parking.restore(BACKUP_PATH)
