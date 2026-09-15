extends GdUnitTestSuite
## El tutorial sale una vez. Esa es toda la regla, y es la que se vigila aqui:
## cada consejo una sola vez por partida, la intro no vuelve una vez vista,
## `reset()` lo olvida todo y el guardado lo trae de vuelta intacto.
##
## Se escucha EventBus conectando a mano: monitor_signals() libera el objeto
## vigilado y EventBus es un autoload.

var _saved: Dictionary = {}
var _intro_requests := 0
var _tips: Array = []

func before_test() -> void:
	_saved = TutorialManager.get_save_data()
	TutorialManager.reset()
	_intro_requests = 0
	_tips.clear()
	EventBus.tutorial_intro_requested.connect(_count_intro)
	EventBus.tutorial_tip_requested.connect(_collect_tip)

func after_test() -> void:
	EventBus.tutorial_intro_requested.disconnect(_count_intro)
	EventBus.tutorial_tip_requested.disconnect(_collect_tip)
	TutorialManager.load_save_data(_saved)

func _count_intro() -> void:
	_intro_requests += 1

func _collect_tip(tip_id: String, _title: String, _body: String) -> void:
	_tips.append(tip_id)

# ── Consejos: una vez cada uno ───────────────────────────────────────

func test_the_storm_warning_tip_fires_once() -> void:
	EventBus.storm_incoming.emit(30.0)
	EventBus.storm_incoming.emit(30.0)
	assert_array(_tips).contains_exactly(["storm_incoming"])

func test_the_ash_tip_fires_once() -> void:
	EventBus.storm_ash_started.emit()
	EventBus.storm_ash_started.emit()
	assert_array(_tips).contains_exactly(["storm_ash"])

func test_the_storm_tip_fires_once() -> void:
	EventBus.storm_started.emit(1)
	EventBus.storm_started.emit(2)
	assert_array(_tips).contains_exactly(["storm_started"])

func test_the_tithe_tip_fires_once() -> void:
	EventBus.tithe_demanded.emit(1)
	EventBus.tithe_demanded.emit(1)
	assert_array(_tips).contains_exactly(["tithe"])

func test_the_ruined_building_tip_fires_once() -> void:
	var node := Node3D.new()
	auto_free(node)
	EventBus.building_ruined.emit(node)
	EventBus.building_ruined.emit(node)
	assert_array(_tips).contains_exactly(["ruined"])

func test_the_overflow_tip_fires_once() -> void:
	EventBus.storage_overflow.emit("wood", 12, 600)
	EventBus.storage_overflow.emit("gold", 3, 600)
	assert_array(_tips).contains_exactly(["overflow"])

func test_the_board_tip_fires_once() -> void:
	EventBus.encounter_started.emit(0, false)
	EventBus.encounter_started.emit(1, true)
	assert_array(_tips).contains_exactly(["encounter"])

func test_every_tip_is_independent_of_the_others() -> void:
	# Ver uno no gasta los demas: son siete sucesos distintos.
	EventBus.storm_incoming.emit(30.0)
	EventBus.storm_ash_started.emit()
	EventBus.storm_started.emit(1)
	EventBus.tithe_demanded.emit(1)
	assert_array(_tips).contains_exactly(["storm_incoming", "storm_ash", "storm_started", "tithe"])
	assert_bool(TutorialManager.has_seen_tip("overflow")).is_false()

func test_tips_arrive_translated_not_as_keys() -> void:
	# Tr devuelve la clave si falta: si el titulo empieza por TUT_ la cadena no
	# existe en el idioma activo.
	var got: Array = []
	var grab := func(_id: String, title: String, body: String): got.append([title, body])
	EventBus.tutorial_tip_requested.connect(grab)
	for tip_id in TutorialManager.TIPS.keys():
		TutorialManager.offer_tip(tip_id)
	EventBus.tutorial_tip_requested.disconnect(grab)
	assert_int(got.size()).is_equal(TutorialManager.TIPS.size())
	for pair in got:
		assert_str(pair[0]).not_contains("TUT_")
		assert_str(pair[1]).not_contains("TUT_")
		assert_str(pair[1]).is_not_empty()

func test_an_unknown_tip_is_ignored() -> void:
	TutorialManager.offer_tip("no_existe")
	assert_array(_tips).is_empty()
	assert_bool(TutorialManager.has_seen_tip("no_existe")).is_false()

# ── Intro: una por partida ───────────────────────────────────────────

func test_a_new_game_asks_for_the_intro() -> void:
	EventBus.game_new_started.emit()
	# Se emite diferida: el panel es el ultimo nodo de la escena.
	await await_idle_frame()
	assert_int(_intro_requests).is_equal(1)

func test_the_intro_does_not_come_back_once_seen() -> void:
	EventBus.game_new_started.emit()
	await await_idle_frame()
	EventBus.tutorial_intro_closed.emit()
	assert_bool(TutorialManager.intro_seen).is_true()
	EventBus.game_new_started.emit()
	EventBus.game_load_completed.emit()
	await await_idle_frame()
	assert_int(_intro_requests).is_equal(1)

func test_loading_an_old_save_without_the_flag_offers_the_intro() -> void:
	# La partida de quien se quejo de no entender nada es de antes del tutorial.
	TutorialManager.load_save_data({})
	EventBus.game_load_completed.emit()
	await await_idle_frame()
	assert_int(_intro_requests).is_equal(1)

func test_show_intro_reopens_it_even_when_seen() -> void:
	# Para el futuro boton HISTORIA: volver a leer el lore no depende de la marca.
	TutorialManager.intro_seen = true
	TutorialManager.show_intro()
	assert_int(_intro_requests).is_equal(1)
	assert_bool(TutorialManager.intro_seen).is_true()

# ── reset() y guardado ───────────────────────────────────────────────

func test_reset_forgets_everything() -> void:
	EventBus.storm_incoming.emit(30.0)
	EventBus.tutorial_intro_closed.emit()
	TutorialManager.reset()
	assert_bool(TutorialManager.intro_seen).is_false()
	assert_array(TutorialManager.tips_seen).is_empty()

func test_reset_does_not_notify_anyone() -> void:
	TutorialManager.reset()
	assert_int(_intro_requests).is_equal(0)
	assert_array(_tips).is_empty()

func test_save_data_round_trips() -> void:
	EventBus.storm_incoming.emit(30.0)
	EventBus.tithe_demanded.emit(1)
	EventBus.tutorial_intro_closed.emit()
	var data: Dictionary = TutorialManager.get_save_data()
	TutorialManager.reset()
	TutorialManager.load_save_data(data)
	assert_bool(TutorialManager.intro_seen).is_true()
	assert_array(TutorialManager.tips_seen).contains_exactly(["storm_incoming", "tithe"])

func test_a_restored_tip_stays_silent() -> void:
	# Lo que se guardo como visto no vuelve a salir tras cargar.
	TutorialManager.load_save_data({"intro_seen": true, "tips_seen": ["storm_incoming"]})
	EventBus.storm_incoming.emit(30.0)
	assert_array(_tips).is_empty()

func test_save_data_is_a_copy_not_a_reference() -> void:
	var data: Dictionary = TutorialManager.get_save_data()
	EventBus.storm_incoming.emit(30.0)
	assert_array(data["tips_seen"]).is_empty()

func test_load_survives_garbage() -> void:
	# Un guardado editado a mano no debe tirar la carga: lo raro se descarta y
	# lo dudoso cuenta como "no visto".
	TutorialManager.load_save_data({"intro_seen": "si", "tips_seen": [7, null, "storm_ash", "storm_ash"]})
	assert_bool(TutorialManager.intro_seen).is_false()
	assert_array(TutorialManager.tips_seen).contains_exactly(["storm_ash"])
