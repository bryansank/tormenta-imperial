extends GdUnitTestSuite
## Las partidas guardadas (docs/09, 2026-10-12): hasta cinco en user://partidas/,
## con su indice. Aqui lo que no necesita una colonia montada: migrar el
## save_game.json de antes, borrar, rehacer el indice, la sexta que pide borrar
## una, una sellada que no se carga y la lista que se ve.
##
## Aparta las partidas de verdad mientras dura (tests/save/save_parking.gd).

const Parking := preload("res://tests/save/save_parking.gd")
const Slots := preload("res://scripts/services/SaveSlots.gd")
const PanelScript := preload("res://scripts/ui/SavesPanel.gd")
const DialogScript := preload("res://scripts/ui/NewGameDialog.gd")
const BACKUP_PATH := "user://save_game.save_slots.bak"

func before(do_skip := Parking.in_player_dir(), skip_reason := "Carpeta de usuario del jugador: lanza los tests con tools/run_tests.sh") -> void:
	pass

var _auto_fresh := false
var _active := 0

func before_test() -> void:
	Parking.park(BACKUP_PATH)
	_auto_fresh = GameManager._auto_fresh
	_active = GameConfig.saves_active_slot
	get_tree().paused = false

func after_test() -> void:
	for child in GameManager.get_children():
		if child.get_script() == PanelScript or child.get_script() == DialogScript:
			child.free()
	GameManager._auto_fresh = _auto_fresh
	GameManager._active_deleted = false
	GameConfig.saves_active_slot = _active
	Parking.restore(BACKUP_PATH)

## Una partida en disco con lo que la lista lee de ella.
func _write_slot(id: int, saved_at: float, extra: Dictionary = {}) -> Dictionary:
	var data := {
		"format": GameManager.SAVE_FORMAT,
		"saved_at": saved_at,
		"resources": {"gold": 100 + id, "wood": 50},
		"progression": {"current_era": 2, "played_seconds": 3900.0},
		"game_mode": {"mode": "campaign", "result": "", "tier": "colonist"},
	}
	data.merge(extra, true)
	var f := FileAccess.open(Slots.path_of(id), FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	return data

# ── Migracion ────────────────────────────────────────────────────────

func test_an_old_save_game_becomes_game_one_without_losing_a_byte() -> void:
	var text := JSON.stringify({"format": 2, "saved_at": 1000.0, "resources": {"gold": 777}})
	var f := FileAccess.open(Slots.LEGACY_PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	var id: int = Slots.migrate_legacy()
	assert_int(id).is_equal(1)
	assert_bool(FileAccess.file_exists(Slots.LEGACY_PATH)).is_false()
	assert_str(FileAccess.get_file_as_string(Slots.path_of(1))).is_equal(text)
	var listed: Array = Slots.list()
	assert_int(listed.size()).is_equal(1)
	assert_int(int(listed[0]["id"])).is_equal(1)

func test_the_old_save_joins_the_others_with_the_next_number() -> void:
	_write_slot(1, 10.0)
	_write_slot(2, 20.0)
	var f := FileAccess.open(Slots.LEGACY_PATH, FileAccess.WRITE)
	f.store_string("{\"format\": 2}")
	f.close()
	assert_int(Slots.migrate_legacy()).is_equal(3)
	assert_int(Slots.count()).is_equal(3)

func test_nothing_to_migrate_touches_nothing() -> void:
	assert_int(Slots.migrate_legacy()).is_equal(0)
	assert_int(Slots.count()).is_equal(0)

func test_the_first_start_after_the_update_opens_the_migrated_game() -> void:
	var f := FileAccess.open(Slots.LEGACY_PATH, FileAccess.WRITE)
	f.store_string("{\"format\": 2}")
	f.close()
	GameConfig.saves_active_slot = 0
	GameManager._resolve_active_slot()
	assert_int(GameManager.active_slot()).is_equal(1)
	assert_bool(Slots.exists(1)).is_true()

# ── Borrar e indice ──────────────────────────────────────────────────

func test_deleting_a_game_removes_its_file_and_its_line() -> void:
	_write_slot(1, 10.0)
	_write_slot(2, 20.0)
	Slots.list()
	assert_bool(Slots.remove(1)).is_true()
	assert_bool(Slots.exists(1)).is_false()
	var listed: Array = Slots.list()
	assert_int(listed.size()).is_equal(1)
	assert_int(int(listed[0]["id"])).is_equal(2)
	var index: Variant = JSON.parse_string(FileAccess.get_file_as_string(Slots.INDEX_PATH))
	assert_int((index["slots"] as Array).size()).is_equal(1)

func test_a_lost_index_is_rebuilt_from_the_games() -> void:
	_write_slot(1, 10.0)
	_write_slot(2, 20.0, {"rank": {"color": "brass"}})
	Slots.list()
	DirAccess.remove_absolute(Slots.INDEX_PATH)
	var listed: Array = Slots.list()
	assert_int(listed.size()).is_equal(2)
	# La mas reciente primero, con lo que pinta la lista.
	assert_int(int(listed[0]["id"])).is_equal(2)
	assert_int(int(listed[0]["era"])).is_equal(2)
	assert_float(float(listed[0]["played_seconds"])).is_equal(3900.0)
	assert_str(String(listed[0]["mode"])).is_equal("campaign")
	assert_bool(FileAccess.file_exists(Slots.INDEX_PATH)).is_true()

func test_backups_and_the_index_are_not_games() -> void:
	_write_slot(1, 10.0)
	for extra in ["partida_1.corrupt-20261012-101010.json", "partida_1.v1-20261012-101010.json"]:
		var f := FileAccess.open(Slots.DIR.path_join(extra), FileAccess.WRITE)
		f.store_string("{}")
		f.close()
	Slots.list()
	assert_array(Slots.file_ids()).contains_exactly([1])
	assert_int(Slots.next_id()).is_equal(2)

func test_a_broken_game_still_shows_up_to_be_deleted() -> void:
	var f := FileAccess.open(Slots.path_of(4), FileAccess.WRITE)
	f.store_string("{esto no es json")
	f.close()
	var listed: Array = Slots.list()
	assert_int(listed.size()).is_equal(1)
	assert_bool(bool(listed[0].get("broken", false))).is_true()

# ── Continuar a la ultima ────────────────────────────────────────────

func test_continue_opens_the_last_game_played() -> void:
	_write_slot(1, 100.0)
	_write_slot(2, 300.0)
	_write_slot(3, 200.0)
	# La activa es la ultima jugada: se respeta aunque otra sea mas nueva.
	GameConfig.saves_active_slot = 3
	GameManager._fresh_slot_pending = false
	GameManager._resolve_active_slot()
	assert_int(GameManager.active_slot()).is_equal(3)
	# Sin activa valida (se borro a mano), la mas reciente.
	GameConfig.saves_active_slot = 9
	GameManager._resolve_active_slot()
	assert_int(GameManager.active_slot()).is_equal(2)
	assert_int(Slots.most_recent_id()).is_equal(2)

# ── Cinco como mucho ─────────────────────────────────────────────────

func test_the_sixth_game_asks_to_delete_one_first_and_deletes_nothing() -> void:
	for id in range(1, 6):
		_write_slot(id, float(id))
	GameManager._auto_fresh = false
	assert_bool(GameManager.is_save_list_full()).is_true()
	var opened: CanvasLayer = GameManager.request_new_game()
	assert_object(opened.get_script()).is_equal(PanelScript)
	assert_bool(opened.is_make_room()).is_true()
	# Con las cinco ocupadas no se cargan desde aqui: solo se borra.
	await await_idle_frame()
	var load_btn: Button = opened.row(1).find_child("Load", true, false)
	assert_bool(load_btn.visible).is_false()
	# start_new_game tampoco crea la sexta por su cuenta.
	GameManager.start_new_game(GameMode.Mode.CAMPAIGN)
	assert_int(Slots.count()).is_equal(5)

func test_deleting_one_to_make_room_goes_on_to_the_mode_picker() -> void:
	for id in range(1, 6):
		_write_slot(id, float(id))
	GameManager._auto_fresh = false
	GameConfig.saves_active_slot = 5
	var panel: CanvasLayer = GameManager.request_new_game()
	await await_idle_frame()
	(panel.row(2).find_child("Delete", true, false) as Button).pressed.emit()
	(panel.row(2).find_child("Yes", true, false) as Button).pressed.emit()
	assert_bool(Slots.exists(2)).is_false()
	assert_int(Slots.count()).is_equal(4)
	var dialogs: Array = []
	for child in GameManager.get_children():
		if child.get_script() == DialogScript and not child.is_queued_for_deletion():
			dialogs.append(child)
	assert_int(dialogs.size()).is_equal(1)

func test_a_fresh_island_nobody_touched_does_not_take_a_place() -> void:
	for id in range(1, 6):
		_write_slot(id, float(id))
	GameManager._auto_fresh = true
	var started: bool = GameManager._started
	GameManager._started = true
	var full: bool = GameManager.is_save_list_full()
	GameManager._started = started
	assert_bool(full).is_false()

# ── La lista ─────────────────────────────────────────────────────────

func test_the_list_shows_name_mode_era_time_and_date() -> void:
	_write_slot(1, 1760270000.0)
	var panel: CanvasLayer = GameManager.open_saves_list()
	await await_idle_frame()
	assert_int(panel.row_count()).is_equal(1)
	var row: Control = panel.row(1)
	assert_str((row.find_child("Name", true, false) as Label).text).is_equal(Tr.t("LBL_SAVE_COLONY_N") % 1)
	var info: String = (row.find_child("Info", true, false) as Label).text
	assert_str(info).contains(GameMode.display_name(GameMode.Mode.CAMPAIGN))
	assert_str(info).contains(Tr.t("LBL_SAVE_ERA") % 2)
	assert_str(info).contains("1 h 05")
	assert_str(info).contains(PanelScript.short_date(1760270000.0))
	assert_int(panel.process_mode).is_equal(Node.PROCESS_MODE_ALWAYS)

func test_a_colony_name_from_the_index_is_the_title() -> void:
	_write_slot(1, 10.0, {"rank": {"colony": {"name": "Valdoria"}}})
	var panel: CanvasLayer = GameManager.open_saves_list()
	await await_idle_frame()
	assert_str((panel.row(1).find_child("Name", true, false) as Label).text).is_equal("Valdoria")

func test_a_sealed_game_shows_finished_and_cannot_be_continued() -> void:
	_write_slot(1, 10.0, {"game_mode": {"mode": "survival", "result": "defeat", "tier": "colonist"}})
	_write_slot(2, 20.0)
	assert_bool(bool(Slots.entry(1)["sealed"])).is_true()
	assert_bool(bool(Slots.entry(2)["sealed"])).is_false()
	var panel: CanvasLayer = GameManager.open_saves_list()
	await await_idle_frame()
	assert_object(panel.row(1).find_child("Sealed", true, false)).is_not_null()
	assert_bool((panel.row(1).find_child("Load", true, false) as Button).disabled).is_true()
	assert_bool((panel.row(2).find_child("Load", true, false) as Button).disabled).is_false()

func test_delete_asks_first_and_no_keeps_the_game() -> void:
	_write_slot(1, 10.0)
	_write_slot(3, 30.0)
	GameConfig.saves_active_slot = 1
	var panel: CanvasLayer = GameManager.open_saves_list()
	await await_idle_frame()
	(panel.row(3).find_child("Delete", true, false) as Button).pressed.emit()
	assert_bool(Slots.exists(3)).is_true()
	(panel.row(3).find_child("No", true, false) as Button).pressed.emit()
	assert_bool(Slots.exists(3)).is_true()
	(panel.row(3).find_child("Delete", true, false) as Button).pressed.emit()
	(panel.row(3).find_child("Yes", true, false) as Button).pressed.emit()
	assert_bool(Slots.exists(3)).is_false()
	assert_bool(Slots.exists(1)).is_true()
	assert_int(panel.row_count()).is_equal(1)

func test_the_list_scrolls_by_dragging() -> void:
	for id in range(1, 6):
		_write_slot(id, float(id))
	var panel: CanvasLayer = GameManager.open_saves_list()
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(panel._scroll.has_node("DragScroll")).is_true()
