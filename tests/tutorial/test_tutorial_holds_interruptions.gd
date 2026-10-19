extends GdUnitTestSuite
## Nada que interrumpa llega mientras se hace el tutorial (queja de Bryan,
## 2026-10-19: "la primera tormenta esta llegando aunque este haciendo el
## tutorial"). TutorialManager.blocks_interruptions() lo decide; la tormenta de
## prueba (tests/storm/test_storm_trial.gd), la Tormenta de verdad y los eventos
## aleatorios lo preguntan.

var _saved_tutorial: Dictionary = {}
var _saved_phase: int = 0
var _saved_mode: int = GameMode.DEFAULT
var _saved_timer := 0.0
var _saved_next := 0.0

func before_test() -> void:
	_saved_tutorial = TutorialManager.get_save_data()
	_saved_phase = ProgressionManager.current_phase
	_saved_mode = GameMode.current
	_saved_timer = RandomEventManager._timer
	_saved_next = RandomEventManager._next_event_time
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	TutorialManager.guide_baseline = {}

func after_test() -> void:
	TutorialManager.load_save_data(_saved_tutorial)
	ProgressionManager.current_phase = _saved_phase
	GameMode.begin_run(_saved_mode)
	RandomEventManager._timer = _saved_timer
	RandomEventManager._next_event_time = _saved_next

func test_only_the_real_tutorial_holds_things_back() -> void:
	TutorialManager.guide_state = TutorialManager.GUIDE_ACTIVE
	assert_bool(TutorialManager.blocks_interruptions()).is_true()
	# Un repaso pedido desde AYUDA no frena nada.
	TutorialManager.guide_baseline = {"sawmills": 2}
	assert_bool(TutorialManager.blocks_interruptions()).is_false()
	TutorialManager.guide_baseline = {}
	for state in [TutorialManager.GUIDE_DONE, TutorialManager.GUIDE_SKIPPED]:
		TutorialManager.guide_state = state
		assert_bool(TutorialManager.blocks_interruptions()).is_false()

func test_random_events_wait_for_the_tutorial() -> void:
	ProgressionManager.current_phase = GameConfig.Phase.SURVIVAL
	RandomEventManager._timer = 0.0
	RandomEventManager._next_event_time = 1.0e9
	TutorialManager.guide_state = TutorialManager.GUIDE_ACTIVE
	RandomEventManager._process(30.0)
	assert_float(RandomEventManager._timer).is_equal(0.0)
	TutorialManager.guide_state = TutorialManager.GUIDE_DONE
	RandomEventManager._process(30.0)
	assert_float(RandomEventManager._timer).is_greater(0.0)
