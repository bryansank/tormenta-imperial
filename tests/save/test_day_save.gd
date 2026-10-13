extends GdUnitTestSuite
## La hora del dia viaja en el guardado (clave "day", DayClock) y la limpian los
## tres sitios de GameManager que empiezan partida. Carga idempotente; una
## partida sin la clave empieza de dia. Con el ciclo apagado siempre es de dia.

const GM_PATH := "res://scripts/services/GameManager.gd"

var _saved_day: Dictionary = {}
var _saved_enabled := true
var _phases: Array = []

func before_test() -> void:
	_saved_day = DayClock.get_save_data()
	_saved_enabled = GameConfig.day_cycle_enabled
	GameConfig.day_cycle_enabled = true
	_phases = []
	EventBus.day_phase_changed.connect(_on_phase)

func after_test() -> void:
	EventBus.day_phase_changed.disconnect(_on_phase)
	GameConfig.day_cycle_enabled = _saved_enabled
	DayClock.load_save_data(_saved_day)

func _on_phase(phase: int, _hour: float) -> void:
	_phases.append(phase)

func _night_hour() -> float:
	var c := DayClock.get_cycle()
	return 1.0 - 0.5 * c.night_seconds / c.length()

func test_the_hour_round_trips_through_json() -> void:
	DayClock.set_hour(_night_hour())
	var data: Dictionary = JSON.parse_string(JSON.stringify(DayClock.get_save_data()))
	DayClock.reset()
	assert_bool(DayClock.is_night()).is_false()
	DayClock.load_save_data(data)
	assert_bool(DayClock.is_night()).is_true()
	assert_float(DayClock.get_hour()).is_equal_approx(_night_hour(), 0.0001)

func test_loading_twice_is_the_same_as_once() -> void:
	DayClock.set_hour(0.5)
	var data := DayClock.get_save_data()
	DayClock.load_save_data(data)
	DayClock.load_save_data(data)
	assert_float(DayClock.get_hour()).is_equal_approx(0.5, 0.0001)

func test_a_save_without_the_key_starts_in_daylight() -> void:
	DayClock.set_hour(_night_hour())
	DayClock.load_save_data({})
	assert_int(DayClock.get_phase()).is_equal(DayCycle.Phase.DAY)
	assert_float(DayClock.light_weight()).is_equal(1.0)

func test_reset_is_a_fresh_morning_and_says_nothing() -> void:
	DayClock.set_hour(_night_hour())
	DayClock.reset()
	assert_int(DayClock.get_phase()).is_equal(DayCycle.Phase.DAY)
	assert_array(_phases).is_empty()

func test_switched_off_it_is_always_day() -> void:
	DayClock.set_hour(_night_hour())
	GameConfig.day_cycle_enabled = false
	assert_bool(DayClock.is_night()).is_false()
	assert_float(DayClock.light_weight()).is_equal(1.0)
	assert_float(DayClock.warm_weight()).is_equal(0.0)
	assert_float(DayClock.sun_arc()).is_equal(0.0)

func test_the_clock_publishes_its_phase_changes() -> void:
	var c := DayClock.get_cycle()
	# Justo antes del atardecer.
	DayClock.set_hour((c.dawn_seconds + c.day_seconds) / c.length() - 0.0001)
	DayClock._process(c.length() * 0.001)
	assert_array(_phases).is_equal([DayCycle.Phase.DUSK])

## Los tres sitios que empiezan partida (docs CLAUDE.md, "Adding Persistent
## State") llaman a DayClock.reset(), y el guardado escribe y lee la clave.
func test_game_manager_resets_writes_and_loads_the_day() -> void:
	var src := FileAccess.get_file_as_string(GM_PATH)
	assert_int(src.count("DayClock.reset()")).is_equal(3)
	assert_bool(src.contains("data[\"day\"] = DayClock.get_save_data()")).is_true()
	assert_bool(src.contains("DayClock.load_save_data(")).is_true()
	for fn in ["func _new_game", "func clear_save()", "func clear_save_and_reload_from"]:
		var start := src.find(fn)
		assert_int(start).is_greater(-1)
		var next := src.find("\nfunc ", start + 1)
		assert_bool(src.substr(start, next - start).contains("DayClock.reset()")).override_failure_message(fn).is_true()
