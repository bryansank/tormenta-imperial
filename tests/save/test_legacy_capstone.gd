extends GdUnitTestSuite
## Una partida de antes de la Auditoria Final con el Cuartel General ya a nivel
## 3 tenia el hito hq_max hecho y ningun asedio: _complete_milestone() no vuelve
## a entrar, asi que no habia forma de ganarla. Al cargar se convoca, pendiente.

var _saved_progression: Dictionary = {}
var _saved_storm: Dictionary = {}
var _saved_army: Dictionary = {}
var _summoned: int = 0
var _started: int = 0

func before_test() -> void:
	_saved_progression = ProgressionManager.get_save_data()
	_saved_storm = StormManager.get_save_data()
	_saved_army = ArmyManager.get_save_data()
	CombatManager.reset()
	StormManager.reset()
	ArmyManager.load_save_data({"units": {"infantry": 3}, "training": [], "upkeep_accum": 0.0})
	_summoned = 0
	_started = 0
	EventBus.final_audit_summoned.connect(_on_summoned)
	EventBus.final_audit_started.connect(_on_started)

func after_test() -> void:
	EventBus.final_audit_summoned.disconnect(_on_summoned)
	EventBus.final_audit_started.disconnect(_on_started)
	CombatManager.end_encounter()
	CombatManager.reset()
	ProgressionManager.final_audit = null
	ProgressionManager.load_save_data(_saved_progression)
	StormManager.load_save_data(_saved_storm)
	StormManager._tithe_to_resume = false
	ArmyManager.load_save_data(_saved_army)

func _on_summoned(_waves: int, _summons: int) -> void:
	_summoned += 1

func _on_started(_waves: int) -> void:
	_started += 1

## Un save tal como lo escribia la version anterior: hq_max y sin final_audit.
func _legacy_save() -> Dictionary:
	return {
		"current_era": 3,
		"current_phase": GameConfig.Phase.EXPANSION,
		"milestones": {"hq_built": true, "hq_max": true},
	}

func test_a_legacy_capstone_becomes_a_pending_siege() -> void:
	ProgressionManager.load_save_data(_legacy_save())
	assert_object(ProgressionManager.final_audit).is_null()
	assert_bool(ProgressionManager.migrate_legacy_capstone()).is_true()
	assert_bool(ProgressionManager.is_final_audit_pending()).is_true()
	assert_int(_summoned).is_equal(1)
	# Nada de pelea al cargar: el tablero lo abre el jugador.
	assert_int(_started).is_equal(0)
	assert_bool(CombatManager.is_board_open()).is_false()

func test_the_migration_runs_once() -> void:
	ProgressionManager.load_save_data(_legacy_save())
	ProgressionManager.migrate_legacy_capstone()
	assert_bool(ProgressionManager.migrate_legacy_capstone()).is_false()
	assert_int(_summoned).is_equal(1)

func test_a_game_already_won_is_not_summoned_again() -> void:
	ProgressionManager.load_save_data(_legacy_save())
	StormManager._halted = true
	assert_bool(ProgressionManager.migrate_legacy_capstone()).is_false()
	assert_object(ProgressionManager.final_audit).is_null()

func test_without_the_capstone_there_is_nothing_to_migrate() -> void:
	ProgressionManager.load_save_data({"current_era": 3, "milestones": {"hq_built": true}})
	assert_bool(ProgressionManager.migrate_legacy_capstone()).is_false()
	assert_object(ProgressionManager.final_audit).is_null()

func test_the_loader_calls_the_migration() -> void:
	var src: String = FileAccess.get_file_as_string("res://scripts/services/GameManager.gd")
	var start: int = src.find("func _load_game")
	var end: int = src.find("\nfunc ", start + 1)
	assert_bool(src.substr(start, end - start).contains("migrate_legacy_capstone()")).is_true()
