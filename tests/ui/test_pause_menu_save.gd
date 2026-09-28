extends GdUnitTestSuite
## "Guardar" en el menu de pausa dice la verdad.
##
## El menu de pausa puede abrirse encima del tablero (BattleScreen no esta en la
## pila de UIManager), y con una pelea abierta GameManager no escribe nada: deja
## el guardado pendiente hasta que la pelea termine (CombatManager.is_save_safe()).
## Antes el menu decia "Partida guardada" igual. Ahora dice que se guardara al
## terminar la pelea, y solo dice "guardada" cuando se escribio.
##
## GameManager se prueba con un placer y un mapa de pega y el guardado real
## apartado, como en tests/save/test_autosave.gd.

const SAVE_PATH := "user://save_game.json"
const BACKUP_PATH := "user://save_game.pause_save_test.bak"
const STUB_SRC := "extends Node\nfunc get_all_placed_buildings() -> Array:\n\treturn []\nfunc get_all_deposits() -> Array:\n\treturn []\n"
const PARTY := {"infantry": 2}
const Parking := preload("res://tests/save/save_parking.gd")

var _saved_gm: Array = []
var _saved_army: Dictionary = {}
var _placer: Node = null
var _map: Node = null

func before_test() -> void:
	Parking.park(BACKUP_PATH)
	get_tree().paused = false
	_saved_gm = [GameManager._placer, GameManager._map_gen, GameManager._started, GameManager._camera]
	_saved_army = ArmyManager.get_save_data()
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
	CombatManager.reset()

func after_test() -> void:
	Parking.restore(BACKUP_PATH)
	get_tree().paused = false
	CombatManager.end_encounter()
	CombatManager.reset()
	GameManager._started = _saved_gm[2]
	GameManager._placer = _saved_gm[0] if is_instance_valid(_saved_gm[0]) else null
	GameManager._map_gen = _saved_gm[1] if is_instance_valid(_saved_gm[1]) else null
	GameManager._camera = _saved_gm[3] if is_instance_valid(_saved_gm[3]) else null
	GameManager._save_pending = false
	ArmyManager.load_save_data(_saved_army)
	_placer.free()
	_map.free()

func _menu() -> CanvasLayer:
	var menu: CanvasLayer = auto_free(load("res://scenes/ui/PauseMenu.tscn").instantiate())
	add_child(menu)
	return menu

func test_con_una_pelea_abierta_no_dice_que_ha_guardado() -> void:
	ArmyManager.load_save_data({"units": PARTY.duplicate(), "training": [], "upkeep_accum": 0.0})
	assert_bool(CombatManager.start_skirmish(PARTY)).is_true()
	assert_bool(CombatManager.is_save_safe()).is_false()
	var menu := _menu()
	menu.open_pause()
	menu.save()
	var text: String = menu._status.text
	menu.resume()
	assert_str(text).is_equal(Tr.t("MSG_SAVE_AFTER_FIGHT"))
	assert_str(text).is_not_equal(Tr.t("MSG_GAME_SAVED"))
	# Y es verdad: el guardado sigue pendiente.
	assert_bool(GameManager.has_pending_save()).is_true()

func test_sin_pelea_guarda_y_lo_dice() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	var menu := _menu()
	menu.open_pause()
	menu.save()
	var text: String = menu._status.text
	menu.resume()
	assert_str(text).is_equal(Tr.t("MSG_GAME_SAVED"))
	assert_bool(FileAccess.file_exists(SAVE_PATH)).is_true()
