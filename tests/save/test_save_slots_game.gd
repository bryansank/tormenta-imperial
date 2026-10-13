extends GdUnitTestSuite
## Las partidas guardadas con una colonia de verdad (BuildingPlacer y
## MapGenerator reales, como test_game_mode_save): cada partida se escribe en su
## archivo, el sellado de Supervivencia va por partida, abrir sin activa valida
## abre la ultima jugada, y una recarga interna (cambiar de vista 3D/2D o de
## idioma) no aplica progresion offline.
##
## Aparta las partidas de verdad mientras dura (tests/save/save_parking.gd).

const Placer := preload("res://scripts/buildings/BuildingPlacer.gd")
const MapGen := preload("res://scripts/map/MapGenerator.gd")
const Parking := preload("res://tests/save/save_parking.gd")
const Slots := preload("res://scripts/services/SaveSlots.gd")
const BACKUP_PATH := "user://save_game.save_slots_game.bak"

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
	_saved_placer = GameManager._placer if is_instance_valid(GameManager._placer) else null
	_saved_map_gen = GameManager._map_gen if is_instance_valid(GameManager._map_gen) else null
	_saved_started = GameManager._started
	_saved_camera = GameManager._camera if is_instance_valid(GameManager._camera) else null
	_saved_loaded = GameManager.loaded_from_save
	Parking.park(BACKUP_PATH)
	GameManager._fresh_slot_pending = false
	GameManager._skip_offline_once = false

func after_test() -> void:
	_close_colony()
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	GameManager._run_sealed = false
	GameManager._save_pending = false
	GameManager._active_deleted = false
	GameManager._skip_offline_once = false
	GameManager._fresh_slot_pending = false
	GameManager._placer = _saved_placer
	GameManager._map_gen = _saved_map_gen
	GameManager._started = _saved_started
	GameManager._camera = _saved_camera
	GameManager._warehouse_count = 0
	GameManager.loaded_from_save = _saved_loaded
	CombatManager.reset()
	ProductionManager.reset()
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

## Una colonia: GameManager elige la partida activa y la carga (o empieza una).
func _open_colony() -> void:
	_scene = get_tree().current_scene
	if _scene == null:
		_scene = Node.new()
		_scene.name = "SaveSlotsScene"
		get_tree().root.add_child(_scene)
		get_tree().current_scene = _scene
		_made_scene = true
	GridManager.clear_all()
	GameManager._placer = null
	GameManager._map_gen = null
	GameManager._started = false
	GameManager._warehouse_count = 0
	ProductionManager.reset()
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
	GridManager.reset_size()
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

## Una partida con un almacen a medio construir y guardada hace una hora: si se
## aplica la progresion offline, la obra se termina al cargar.
func _write_slot(id: int, saved_at: float, gold: int, mode: Dictionary = {}) -> void:
	var data := {
		"format": GameManager.SAVE_FORMAT,
		"saved_at": saved_at,
		"resources": {"gold": gold, "wood": 50, "food": 50},
		"buildings": [{"id": "warehouse", "cell_x": 6, "cell_y": 6, "level": 1,
			"construction_remaining": 600.0}],
		"game_mode": mode if not mode.is_empty() else {"mode": "campaign", "result": "", "tier": "colonist"},
	}
	var f := FileAccess.open(Slots.path_of(id), FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()

func _under_construction() -> int:
	return ProductionManager._constructing.size()

# ── Offline ──────────────────────────────────────────────────────────

func test_a_real_absence_applies_offline_progression() -> void:
	_write_slot(1, Time.get_unix_time_from_system() - 3600.0, 200)
	GameConfig.saves_active_slot = 1
	_open_colony()
	assert_bool(GameManager.loaded_from_save).is_true()
	# Una hora fuera: la obra de 600 s ya esta acabada.
	assert_int(_under_construction()).is_equal(0)

func test_switching_view_or_language_is_not_an_absence() -> void:
	_write_slot(1, Time.get_unix_time_from_system() - 3600.0, 200)
	GameConfig.saves_active_slot = 1
	# Lo que dejan switch_to_scene() y reload_keeping_game() antes de recargar.
	GameManager._skip_offline_once = true
	_open_colony()
	assert_bool(GameManager.loaded_from_save).is_true()
	assert_int(_under_construction()).is_equal(1)
	# Y solo cuenta para esa carga.
	assert_bool(GameManager._skip_offline_once).is_false()

func test_the_view_switch_and_the_language_reload_mark_the_reload_as_internal() -> void:
	var src: String = FileAccess.get_file_as_string("res://scripts/services/GameManager.gd")
	for fn in ["func switch_to_scene", "func reload_keeping_game"]:
		var start: int = src.find(fn)
		assert_int(start).is_greater(-1)
		var end: int = src.find("\nfunc ", start + 1)
		assert_bool(src.substr(start, end - start).contains("_skip_offline_once = ")).override_failure_message(
			"%s no marca la recarga como interna" % fn).is_true()

func test_there_is_no_offline_report_any_more() -> void:
	_write_slot(1, Time.get_unix_time_from_system() - 3600.0, 200)
	GameConfig.saves_active_slot = 1
	var before: int = GameManager.get_child_count()
	_open_colony()
	assert_int(GameManager.get_child_count()).is_equal(before)
	assert_bool(GameManager.has_signal("offline_report_closed")).is_false()
	assert_bool(GameManager.has_method("is_offline_report_open")).is_false()

# ── Cada partida en su archivo ───────────────────────────────────────

func test_saving_writes_only_the_active_game_and_its_index_line() -> void:
	_write_slot(1, 100.0, 111)
	_write_slot(2, 200.0, 222)
	GameConfig.saves_active_slot = 2
	_open_colony()
	assert_int(ResourceManager.get_amount(ResourceManager.Type.GOLD)).is_equal(222)
	var other: String = FileAccess.get_file_as_string(Slots.path_of(1))
	GameManager.save_game()
	assert_str(FileAccess.get_file_as_string(Slots.path_of(1))).is_equal(other)
	var entry: Dictionary = Slots.entry(2)
	assert_float(float(entry["saved_at"])).is_greater(200.0)
	# Ahora la 2 es la mas reciente.
	assert_int(Slots.most_recent_id()).is_equal(2)

func test_without_a_valid_active_game_it_opens_the_last_one_played() -> void:
	_write_slot(1, 100.0, 111)
	_write_slot(2, 300.0, 333)
	_write_slot(3, 200.0, 222)
	GameConfig.saves_active_slot = 7
	_open_colony()
	assert_int(GameManager.active_slot()).is_equal(2)
	assert_int(ResourceManager.get_amount(ResourceManager.Type.GOLD)).is_equal(333)

func test_with_no_games_at_all_a_new_one_is_born_and_can_be_reused() -> void:
	GameConfig.saves_active_slot = 0
	_open_colony()
	assert_bool(GameManager.loaded_from_save).is_false()
	assert_int(Slots.count()).is_equal(1)
	# Nadie la ha tocado: "Nueva partida" ocupara su sitio.
	assert_bool(GameManager.is_current_disposable()).is_true()

# ── Sellado por partida ──────────────────────────────────────────────

func test_a_sealed_game_does_not_seal_the_others() -> void:
	_write_slot(1, 100.0, 111, {"mode": "survival", "result": "defeat", "tier": "colonist"})
	_write_slot(2, 200.0, 222)
	var sealed_bytes: String = FileAccess.get_file_as_string(Slots.path_of(1))
	GameConfig.saves_active_slot = 2
	_open_colony()
	assert_bool(GameManager.is_run_sealed()).is_false()
	ResourceManager.add(ResourceManager.Type.GOLD, 5)
	GameManager.save_game()
	assert_str(FileAccess.get_file_as_string(Slots.path_of(1))).is_equal(sealed_bytes)
	assert_bool(bool(Slots.entry(1)["sealed"])).is_true()
	assert_bool(bool(Slots.entry(2)["sealed"])).is_false()

func test_opening_the_sealed_game_keeps_it_read_only() -> void:
	_write_slot(1, 100.0, 111, {"mode": "survival", "result": "defeat", "tier": "colonist"})
	var before: String = FileAccess.get_file_as_string(Slots.path_of(1))
	GameConfig.saves_active_slot = 1
	_open_colony()
	assert_bool(GameManager.is_run_sealed()).is_true()
	GameManager.save_game()
	assert_str(FileAccess.get_file_as_string(Slots.path_of(1))).is_equal(before)

func test_a_deleted_active_game_is_never_written_again() -> void:
	_write_slot(1, 100.0, 111)
	GameConfig.saves_active_slot = 1
	_open_colony()
	assert_bool(GameManager.delete_slot(1)).is_true()
	GameManager.save_game()
	GameManager.request_save()
	GameManager.flush_pending_save()
	assert_bool(Slots.exists(1)).is_false()
