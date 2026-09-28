extends GdUnitTestSuite
## El autoguardado. Antes solo se guardaba al tocar un edificio, un yacimiento
## o el arbol tecnologico: una tarde de comercio, entrenamiento y expediciones
## se perdia entera si el juego se cerraba sin tocar una pala.
##
## GameManager se prueba con un placer y un mapa de pega (solo tienen que
## devolver listas) y el guardado real apartado: una suite no se cobra la
## partida de nadie.

const SAVE_PATH := "user://save_game.json"
const BACKUP_PATH := "user://save_game.autosave_test.bak"
const STUB_SRC := "extends Node\nfunc get_all_placed_buildings() -> Array:\n\treturn []\nfunc get_all_deposits() -> Array:\n\treturn []\n"
const PARTY := {"infantry": 2}
const Parking := preload("res://tests/save/save_parking.gd")

## Esta suite escribe user://save_game.json. Si corre en la carpeta del jugador
## (lanzada sin tools/run_tests.sh) se salta entera: no hay partida que pisar.
func before(do_skip := Parking.in_player_dir(), skip_reason := "Carpeta de usuario del jugador: lanza los tests con tools/run_tests.sh") -> void:
	pass

var _saved_gm: Array = []
var _saved_army: Dictionary = {}
var _saved_population: Dictionary = {}
var _saved_resources: Dictionary = {}
var _placer: Node = null
var _map: Node = null

func before_test() -> void:
	Parking.park(BACKUP_PATH)
	_saved_gm = [GameManager._placer, GameManager._map_gen, GameManager._started, GameManager._camera]
	_saved_army = ArmyManager.get_save_data()
	_saved_population = PopulationManager.get_save_data()
	_saved_resources = {}
	for type in ResourceManager.get_all():
		_saved_resources[ResourceManager.get_type_name(type)] = int(ResourceManager.get_all()[type])
	var stub := GDScript.new()
	stub.source_code = STUB_SRC
	stub.reload()
	_placer = Node.new()
	_placer.set_script(stub)
	_map = Node.new()
	_map.set_script(stub)
	GameManager._placer = _placer
	GameManager._map_gen = _map
	GameManager._camera = null
	GameManager._started = true
	GameManager._save_pending = false
	GameManager._autosave_elapsed = 0.0
	CombatManager.reset()
	PopulationManager.load_save_data({"morale": 100})

func after_test() -> void:
	# Lo primero, la partida del jugador: si algo de abajo fallara, que no se
	# quede aparcada.
	Parking.restore(BACKUP_PATH)
	CombatManager.end_encounter()
	CombatManager.reset()
	GameManager._started = _saved_gm[2]
	GameManager._placer = _saved_gm[0] if is_instance_valid(_saved_gm[0]) else null
	GameManager._map_gen = _saved_gm[1] if is_instance_valid(_saved_gm[1]) else null
	GameManager._camera = _saved_gm[3] if is_instance_valid(_saved_gm[3]) else null
	GameManager._save_pending = false
	GameManager._autosave_elapsed = 0.0
	ArmyManager.load_save_data(_saved_army)
	PopulationManager.load_save_data(_saved_population)
	ResourceManager.set_amounts(_saved_resources)
	_placer.free()
	_map.free()

func _saved() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func _forget_disk() -> void:
	if _saved():
		DirAccess.remove_absolute(SAVE_PATH)

func _past_debounce() -> void:
	GameManager._process(GameConfig.autosave_debounce + 0.01)

func _open_a_board() -> void:
	ArmyManager.load_save_data({"units": PARTY.duplicate(), "training": [], "upkeep_accum": 0.0})
	assert_bool(CombatManager.start_skirmish(PARTY)).is_true()
	assert_bool(CombatManager.is_in_encounter()).is_true()

func _win_the_board() -> void:
	for unit in CombatManager.get_units():
		if unit.side == 1 and unit.is_alive():
			unit.take_damage(unit.max_hp * 10)
	CombatManager.end_turn()
	assert_bool(CombatManager.is_in_encounter()).is_false()

# ── Rafagas y debounce ───────────────────────────────────────────────

func test_a_burst_of_events_is_written_once_after_the_debounce() -> void:
	EventBus.market_trade_completed.emit("wood", 5, true, 20)
	EventBus.market_trade_completed.emit("wood", 5, false, 10)
	EventBus.unit_trained.emit("infantry")
	EventBus.tithe_resolved.emit(true, {})
	assert_bool(GameManager.has_pending_save()).is_true()
	assert_bool(_saved()).override_failure_message(
		"se escribio en el acto: la rafaga no se fundio").is_false()
	_past_debounce()
	assert_bool(_saved()).is_true()
	assert_bool(GameManager.has_pending_save()).is_false()
	# Nada mas pendiente: el siguiente fotograma no vuelve a escribir.
	_forget_disk()
	_past_debounce()
	assert_bool(_saved()).is_false()

func test_every_key_event_asks_for_a_save() -> void:
	var building: Node3D = auto_free(Node3D.new())
	var emitters: Array = [
		func(): EventBus.market_trade_completed.emit("wood", 1, true, 3),
		func(): EventBus.unit_trained.emit("infantry"),
		func(): EventBus.unit_training_cancelled.emit("infantry", {}),
		func(): EventBus.encounter_ended.emit(true, 3),
		func(): EventBus.tithe_resolved.emit(false, {}),
		func(): EventBus.final_audit_summoned.emit(3, 1),
		func(): EventBus.final_audit_wave_cleared.emit(0, 2),
		func(): EventBus.expedition_node_selected.emit(2),
		func(): EventBus.process_completed.emit(building, "x"),
	]
	for emit in emitters:
		GameManager._save_pending = false
		emit.call()
		assert_bool(GameManager.has_pending_save()).is_true()
	GameManager._save_pending = false

func test_nothing_is_asked_before_the_game_has_started() -> void:
	GameManager._started = false
	EventBus.market_trade_completed.emit("wood", 1, true, 3)
	assert_bool(GameManager.has_pending_save()).is_false()

func test_the_periodic_autosave_fires_on_its_own() -> void:
	GameManager._process(GameConfig.autosave_interval + 0.1)
	assert_bool(_saved()).is_true()

# ── Con un tablero abierto ───────────────────────────────────────────

func test_opening_a_board_writes_a_checkpoint_before_anyone_moves() -> void:
	_forget_disk()
	_open_a_board()
	assert_bool(_saved()).override_failure_message(
		"abrir el tablero no dejo punto de control en disco").is_true()

func test_nothing_is_written_mid_fight_and_the_save_waits_for_the_result() -> void:
	_open_a_board()
	_forget_disk()
	EventBus.market_trade_completed.emit("wood", 1, true, 3)
	GameManager._process(GameConfig.autosave_interval + 1.0)
	GameManager.save_game()
	assert_bool(_saved()).override_failure_message(
		"se guardo con una pelea en juego").is_false()
	assert_bool(GameManager.has_pending_save()).is_true()

	_win_the_board()
	assert_bool(CombatManager.is_save_safe()).is_true()
	_past_debounce()
	assert_bool(_saved()).is_true()

func test_closing_the_window_saves_but_not_mid_fight() -> void:
	GameManager._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	assert_bool(_saved()).is_true()
	_open_a_board()
	_forget_disk()
	GameManager._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	assert_bool(_saved()).is_false()

func test_the_report_of_a_siege_wave_is_not_a_safe_moment() -> void:
	_open_a_board()
	_win_the_board()
	CombatManager._audit_wave_active = true
	assert_bool(CombatManager.is_save_safe()).is_false()
	CombatManager._audit_wave_active = false
	assert_bool(CombatManager.is_save_safe()).is_true()
