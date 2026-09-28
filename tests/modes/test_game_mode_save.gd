extends GdUnitTestSuite
## El modo en la partida de verdad: GameManager lo escribe en el guardado, lo
## lee al cargar (sin clave = Campana), arranca una colonia nueva con sus
## reglas, y una Supervivencia perdida queda guardada y sellada.
##
## Levanta el BuildingPlacer y el MapGenerator reales, como test_full_campaign,
## y aparta el guardado del jugador mientras dura (tests/save/save_parking.gd).

const Placer := preload("res://scripts/buildings/BuildingPlacer.gd")
const MapGen := preload("res://scripts/map/MapGenerator.gd")
const Parking := preload("res://tests/save/save_parking.gd")

const SAVE_PATH := "user://save_game.json"
const BACKUP_PATH := "user://save_game.game_modes.bak"

## Esta suite escribe user://save_game.json. Si corre en la carpeta del jugador
## (lanzada sin tools/run_tests.sh) se salta entera: no hay partida que pisar.
func before(do_skip := Parking.in_player_dir(), skip_reason := "Carpeta de usuario del jugador: lanza los tests con tools/run_tests.sh") -> void:
	pass

var _saved_resources: Dictionary = {}
var _saved_unlocks: Dictionary = {}
var _saved_era: int = 1
var _saved_progression: Dictionary = {}
var _saved_population: Dictionary = {}
var _saved_army: Dictionary = {}
var _saved_storm: Dictionary = {}
var _saved_market: Dictionary = {}
var _saved_events: Dictionary = {}
var _saved_tech: Dictionary = {}
var _saved_tutorial: Dictionary = {}
var _saved_placer: Node = null
var _saved_map_gen: Node = null
var _saved_started: bool = false
var _saved_camera: Node = null
var _saved_loaded: bool = false

var _placer: Node = null
var _map: Node = null
var _scene: Node = null
var _made_scene: bool = false

func before_test() -> void:
	_saved_resources = {}
	for type in ResourceManager.get_all():
		_saved_resources[ResourceManager.get_type_name(type)] = ResourceManager.get_all()[type]
	_saved_unlocks = ResourceManager.get_unlock_state()
	_saved_era = ResourceManager.get_era()
	_saved_progression = ProgressionManager.get_save_data()
	_saved_population = PopulationManager.get_save_data()
	_saved_army = ArmyManager.get_save_data()
	_saved_storm = StormManager.get_save_data()
	_saved_market = MarketManager.get_save_data()
	_saved_events = RandomEventManager.get_save_data()
	_saved_tech = TechTreeManager.get_save_data()
	_saved_tutorial = TutorialManager.get_save_data()
	# Otra suite pudo dejar aqui nodos ya liberados: se guarda null en su lugar.
	_saved_placer = GameManager._placer if is_instance_valid(GameManager._placer) else null
	_saved_map_gen = GameManager._map_gen if is_instance_valid(GameManager._map_gen) else null
	_saved_started = GameManager._started
	_saved_camera = GameManager._camera if is_instance_valid(GameManager._camera) else null
	_saved_loaded = GameManager.loaded_from_save
	Parking.park(BACKUP_PATH)

func after_test() -> void:
	_close_colony()
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	GameManager._run_sealed = false
	GameManager._save_pending = false
	GameManager._placer = _saved_placer
	GameManager._map_gen = _saved_map_gen
	GameManager._started = _saved_started
	GameManager._camera = _saved_camera
	GameManager._warehouse_count = 0
	GameManager.loaded_from_save = _saved_loaded
	if GameManager._offline_canvas != null and is_instance_valid(GameManager._offline_canvas):
		GameManager._offline_canvas.queue_free()
	GameManager._offline_canvas = null
	CombatManager.reset()
	ProgressionManager.final_audit = null
	ProgressionManager.load_save_data(_saved_progression)
	StormManager.load_save_data(_saved_storm)
	ArmyManager.load_save_data(_saved_army)
	PopulationManager.load_save_data(_saved_population)
	MarketManager.load_save_data(_saved_market)
	RandomEventManager.load_save_data(_saved_events)
	TechTreeManager.reset()
	TechTreeManager.load_save_data(_saved_tech)
	TutorialManager.load_save_data(_saved_tutorial)
	ResourceManager.set_unlock_state(_saved_unlocks)
	ResourceManager.set_era(_saved_era)
	ResourceManager.set_amounts(_saved_resources)
	Parking.restore(BACKUP_PATH)

## Una colonia: con guardado en disco la carga, sin el empieza una nueva en el
## modo que haya puesto (lo que haria start_new_game antes de recargar).
func _open_colony() -> void:
	_scene = get_tree().current_scene
	if _scene == null:
		_scene = Node.new()
		_scene.name = "GameModesScene"
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
	_scene.add_child(_placer)
	assert_bool(GameManager._started).is_true()

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
	GameManager._placer = null
	GameManager._map_gen = null
	GameManager._started = false
	if _made_scene and is_instance_valid(_scene):
		get_tree().current_scene = null
		get_tree().root.remove_child(_scene)
		_scene.free()
		_made_scene = false
	_scene = null

func _read_save() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	return parsed if parsed is Dictionary else {}

## Un guardado del formato de hoy salvo que la prueba diga otro: sin la clave
## seria de antes de la red de carreteras y se apartaria sin cargarse.
func _write_raw_save(data: Dictionary) -> void:
	if not data.has("format"):
		data["format"] = GameManager.SAVE_FORMAT
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

# ── Guardar y cargar el modo ─────────────────────────────────────────

func test_a_new_game_writes_its_mode_into_the_save() -> void:
	GameMode.begin_run(GameMode.Mode.BUILDER)
	_open_colony()
	var data := _read_save()
	assert_str(String(data.get("game_mode", {}).get("mode", ""))).is_equal("builder")

func test_a_save_from_before_the_modes_loads_as_campaign() -> void:
	GameMode.begin_run(GameMode.Mode.SANDBOX)
	_write_raw_save({"saved_at": Time.get_unix_time_from_system(), "resources": {"gold": 111, "wood": 99}})
	_open_colony()
	assert_int(GameMode.current).is_equal(GameMode.Mode.CAMPAIGN)
	assert_int(ResourceManager.get_amount(ResourceManager.Type.GOLD)).is_equal(111)

## Un guardado de antes de los edificios de 2x2 (formato 1) no se carga: se
## aparta con fecha y empieza una colonia nueva con su acera.
func test_a_save_from_before_the_road_network_starts_a_new_colony() -> void:
	_write_raw_save({"format": 1, "saved_at": Time.get_unix_time_from_system(), "resources": {"gold": 111, "wood": 99}})
	_open_colony()
	assert_int(ResourceManager.get_amount(ResourceManager.Type.GOLD)).is_not_equal(111)
	assert_bool(GameManager.loaded_from_save).is_false()
	var kept := false
	for f in DirAccess.get_files_at("user://"):
		if f.begins_with("save_game.v1-"):
			kept = true
			DirAccess.remove_absolute("user://" + f)
	assert_bool(kept).is_true()

func test_a_saved_mode_comes_back_on_load() -> void:
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	_write_raw_save({"saved_at": Time.get_unix_time_from_system(), "game_mode": {"mode": "survival", "result": ""}})
	_open_colony()
	assert_int(GameMode.current).is_equal(GameMode.Mode.SURVIVAL)
	assert_bool(GameManager.is_run_sealed()).is_false()

# ── Colonias nuevas con las reglas del modo ──────────────────────────

func test_a_new_sandbox_colony_has_everything() -> void:
	GameMode.begin_run(GameMode.Mode.SANDBOX)
	_open_colony()
	assert_int(ProgressionManager.current_era).is_equal(3)
	assert_bool(ResourceManager.is_unlocked(ResourceManager.Type.OIL)).is_true()
	assert_int(ResourceManager.get_amount(ResourceManager.Type.STEEL)).is_greater_equal(GameConfig.sandbox_resource_floor)
	assert_int(TechTreeManager.get_researched_count()).is_equal(GameConfig.tech_definitions.size())

func test_a_new_survival_colony_starts_poorer() -> void:
	GameMode.begin_run(GameMode.Mode.SURVIVAL)
	_open_colony()
	assert_int(ResourceManager.get_amount(ResourceManager.Type.GOLD)).is_equal(int(GameMode.starting_resources()["gold"]))
	assert_int(ResourceManager.get_amount(ResourceManager.Type.WOOD)).is_equal(int(GameMode.starting_resources()["wood"]))

func test_a_new_game_forgets_that_the_last_run_was_over() -> void:
	GameMode.begin_run(GameMode.Mode.SURVIVAL)
	GameMode.finish_run(GameMode.RESULT_DEFEAT)
	_open_colony()
	assert_bool(GameMode.is_run_over()).is_false()
	assert_bool(GameManager.is_run_sealed()).is_false()

# ── Supervivencia perdida: guardada y sellada ────────────────────────

func test_a_lost_survival_run_is_saved_marked_and_then_never_written_again() -> void:
	GameMode.begin_run(GameMode.Mode.SURVIVAL)
	_open_colony()
	GameMode.finish_run(GameMode.RESULT_DEFEAT)
	EventBus.run_ended.emit(GameMode.RESULT_DEFEAT)
	var data := _read_save()
	assert_str(String(data.get("game_mode", {}).get("result", ""))).is_equal(GameMode.RESULT_DEFEAT)
	assert_bool(GameManager.is_run_sealed()).is_true()
	# Lo que pase despues no llega al disco.
	var before: String = FileAccess.get_file_as_string(SAVE_PATH)
	ResourceManager.add(ResourceManager.Type.GOLD, 50)
	GameManager.save_game()
	GameManager.request_save()
	GameManager.flush_pending_save()
	assert_str(FileAccess.get_file_as_string(SAVE_PATH)).is_equal(before)

func test_loading_a_finished_run_keeps_it_sealed_and_skips_offline_earnings() -> void:
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	_write_raw_save({
		"saved_at": Time.get_unix_time_from_system() - 3600.0,
		"resources": {"gold": 10, "wood": 10},
		"game_mode": {"mode": "survival", "result": "defeat"},
	})
	var before: String = FileAccess.get_file_as_string(SAVE_PATH)
	_open_colony()
	assert_bool(GameMode.is_run_over()).is_true()
	assert_bool(GameManager.is_run_sealed()).is_true()
	assert_bool(GameManager.is_offline_report_open()).is_false()
	GameManager.save_game()
	assert_str(FileAccess.get_file_as_string(SAVE_PATH)).is_equal(before)
