extends GdUnitTestSuite
## La plaga parte la produccion por la mitad mientras dura, en su propio
## multiplicador: se combina con el de la tormenta y ninguno pisa al otro. El
## evento en curso y sus relojes viajan en el guardado.

var _saved_events: Dictionary = {}
var _saved_storm_mult := 1.0
var _saved_population: Dictionary = {}

func before_test() -> void:
	_saved_events = RandomEventManager.get_save_data()
	_saved_storm_mult = GameConfig.event_production_multiplier
	_saved_population = PopulationManager.get_save_data()
	RandomEventManager.reset()
	GameConfig.event_production_multiplier = 1.0

func after_test() -> void:
	RandomEventManager.reset()
	RandomEventManager.load_save_data(_saved_events)
	GameConfig.event_production_multiplier = _saved_storm_mult
	PopulationManager.load_save_data(_saved_population)

func _start_plague() -> void:
	RandomEventManager._execute_event(RandomEventManager._find_event("plague"))

func test_the_plague_halves_production_while_it_lasts() -> void:
	_start_plague()
	assert_float(GameConfig.get_event_production_multiplier()).is_equal_approx(
		GameConfig.plague_production_multiplier, 0.0001)
	RandomEventManager._end_active_event()
	assert_float(GameConfig.get_event_production_multiplier()).is_equal_approx(1.0, 0.0001)

func test_plague_and_storm_combine_and_neither_erases_the_other() -> void:
	_start_plague()
	GameConfig.event_production_multiplier = GameConfig.storm_production_multiplier
	assert_float(GameConfig.get_event_production_multiplier()).is_equal_approx(
		GameConfig.storm_production_multiplier * GameConfig.plague_production_multiplier, 0.0001)
	# La tormenta amaina: la plaga sigue mordiendo.
	GameConfig.event_production_multiplier = 1.0
	assert_float(GameConfig.get_event_production_multiplier()).is_equal_approx(
		GameConfig.plague_production_multiplier, 0.0001)
	# Y al reves: acaba la plaga con la tormenta encima, la tormenta sigue.
	GameConfig.event_production_multiplier = GameConfig.storm_production_multiplier
	RandomEventManager._end_active_event()
	assert_float(GameConfig.get_event_production_multiplier()).is_equal_approx(
		GameConfig.storm_production_multiplier, 0.0001)

func test_an_active_plague_survives_save_and_load() -> void:
	_start_plague()
	RandomEventManager._active_timer = 23.5
	RandomEventManager._timer = 7.0
	var data := RandomEventManager.get_save_data()
	# Viaja como JSON: nada que no se pueda serializar.
	var round_trip: Dictionary = JSON.parse_string(JSON.stringify(data))
	RandomEventManager.reset()
	assert_float(GameConfig.get_event_production_multiplier()).is_equal_approx(1.0, 0.0001)
	RandomEventManager.load_save_data(round_trip)
	var again := RandomEventManager.get_save_data()
	assert_str(again["active_event_id"]).is_equal("plague")
	assert_float(again["active_timer"]).is_equal_approx(23.5, 0.001)
	assert_float(again["timer"]).is_equal_approx(7.0, 0.001)
	assert_float(GameConfig.get_event_production_multiplier()).is_equal_approx(
		GameConfig.plague_production_multiplier, 0.0001)

func test_loading_does_not_hit_morale_twice() -> void:
	_start_plague()
	var data := RandomEventManager.get_save_data()
	var morale_before := PopulationManager.get_morale()
	RandomEventManager.load_save_data(data)
	assert_int(PopulationManager.get_morale()).is_equal(morale_before)

func test_an_old_save_without_clock_loads_without_an_event() -> void:
	RandomEventManager.load_save_data({"events_triggered": 4})
	var data := RandomEventManager.get_save_data()
	assert_int(int(data["events_triggered"])).is_equal(4)
	assert_str(data["active_event_id"]).is_equal("")
	assert_float(GameConfig.get_event_production_multiplier()).is_equal_approx(1.0, 0.0001)

func test_reset_lifts_the_plague_silently() -> void:
	_start_plague()
	RandomEventManager.reset()
	assert_float(GameConfig.random_event_production_multiplier).is_equal(1.0)
	assert_str(RandomEventManager.get_save_data()["active_event_id"]).is_equal("")
