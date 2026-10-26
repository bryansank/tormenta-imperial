extends GdUnitTestSuite
## Velocidad del juego x1 / x2 (docs/21 §13): la simulacion avanza al doble
## (produccion, construccion, Tormenta, dia y noche), la interfaz no (no se toca
## Engine.time_scale), el turno enemigo se acorta y al arrancar siempre es x1
## (no se lee de settings.cfg ni de la partida).

const SawmillData := preload("res://data/buildings/sawmill.tres")
const PauseMenuScene := "res://scenes/ui/PauseMenu.tscn"

var _storm_saved: Dictionary = {}
var _day_saved: Dictionary = {}
var _day_enabled := true
var _mode_saved: int
var _nodes: Array = []
var _speeds: Array = []

var _tutorial_saved: Dictionary = {}

func before_test() -> void:
	GameConfig.set_game_speed(1.0)
	# ProductionManager avanza por tic de 0,1 s (2026-10-26): lo que llevaba
	# acumulado de los fotogramas de antes no se cuela en la cuenta.
	ProductionManager._tick_acc = 0.0
	# Con el tutorial en marcha el reloj de la Tormenta espera (2026-10-19,
	# TutorialManager.blocks_interruptions): aqui se prueba el reloj solo.
	_tutorial_saved = TutorialManager.get_save_data()
	TutorialManager.guide_state = TutorialManager.GUIDE_DONE
	TutorialManager.guide_baseline = {}
	_storm_saved = StormManager.get_save_data()
	_day_saved = DayClock.get_save_data()
	_day_enabled = GameConfig.day_cycle_enabled
	_mode_saved = GameMode.current
	_nodes = []
	_speeds = []

func after_test() -> void:
	GameConfig.set_game_speed(1.0)
	for n in _nodes:
		if is_instance_valid(n):
			ProductionManager.unregister(n)
			n.free()
	GameMode.current = _mode_saved
	StormManager.reset()
	StormManager.load_save_data(_storm_saved)
	GameConfig.day_cycle_enabled = _day_enabled
	DayClock.load_save_data(_day_saved)
	TutorialManager.load_save_data(_tutorial_saved)
	get_tree().paused = false

func _node() -> Node3D:
	var n := Node3D.new()
	add_child(n)
	_nodes.append(n)
	return n

# ── El valor y la senal ──────────────────────────────────────────────

func test_it_starts_at_x1_and_only_takes_known_speeds() -> void:
	assert_float(GameConfig.game_speed).is_equal(1.0)
	GameConfig.set_game_speed(3.0)
	assert_float(GameConfig.game_speed).is_equal(1.0)
	GameConfig.toggle_game_speed()
	assert_float(GameConfig.game_speed).is_equal(2.0)
	GameConfig.toggle_game_speed()
	assert_float(GameConfig.game_speed).is_equal(1.0)

func test_changing_it_emits_game_speed_changed_once() -> void:
	var probe := func(s: float): _speeds.append(s)
	EventBus.game_speed_changed.connect(probe)
	GameConfig.set_game_speed(2.0)
	GameConfig.set_game_speed(2.0)
	EventBus.game_speed_changed.disconnect(probe)
	assert_array(_speeds).is_equal([2.0])

func test_settings_do_not_bring_back_x2_on_start() -> void:
	# Lo que hace GameConfig al abrir: cargar settings.cfg. La velocidad no esta
	# ahi: sigue en x1 aunque se hubiera dejado en x2.
	GameConfig.set_game_speed(2.0)
	GameConfig.save_user_settings()
	var fresh: Node = load("res://scripts/services/GameConfig.gd").new()
	assert_float(fresh.game_speed).is_equal(1.0)
	fresh.load_user_settings()
	assert_float(fresh.game_speed).is_equal(1.0)
	fresh.free()
	assert_bool(FileAccess.get_file_as_string(GameConfig.USER_SETTINGS_PATH).contains("speed")).is_false()
	# Ni viaja en la partida.
	assert_bool(GameManager.has_method("_write_save")).is_true()
	assert_bool(FileAccess.get_file_as_string("res://scripts/services/GameManager.gd").contains("game_speed")).is_false()

func test_it_does_not_touch_engine_time_scale() -> void:
	GameConfig.set_game_speed(2.0)
	assert_float(Engine.time_scale).is_equal(1.0)

# ── La simulacion va al doble ────────────────────────────────────────

func test_construction_ticks_twice_as_fast() -> void:
	var n := _node()
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	n.add_child(mesh)
	ProductionManager.register_building(n, SawmillData, 30.0)
	var start := ProductionManager.get_construction_remaining(n)
	assert_float(start).is_greater(1.0)
	ProductionManager._process(0.2)
	var mid := ProductionManager.get_construction_remaining(n)
	GameConfig.set_game_speed(2.0)
	ProductionManager._process(0.2)
	var end := ProductionManager.get_construction_remaining(n)
	assert_float(start - mid).is_equal_approx(0.2, 0.001)
	assert_float(mid - end).is_equal_approx(0.4, 0.001)

func test_production_cycle_ticks_twice_as_fast() -> void:
	var n := _node()
	ProductionManager.register_building(n, SawmillData)
	var start := ProductionManager.get_cycle_remaining(n)
	assert_float(start).is_greater(3.0)
	ProductionManager._process(0.5)
	var after_x1 := ProductionManager.get_cycle_remaining(n)
	GameConfig.set_game_speed(2.0)
	ProductionManager._process(0.5)
	var after_x2 := ProductionManager.get_cycle_remaining(n)
	assert_float(start - after_x1).is_equal_approx(0.5, 0.001)
	assert_float(after_x1 - after_x2).is_equal_approx(1.0, 0.001)

func test_the_storm_clock_ticks_twice_as_fast() -> void:
	GameMode.current = GameMode.Mode.CAMPAIGN
	StormManager.reset()
	StormManager._armed = true
	var cycle: StormCycle = StormManager.get_cycle()
	var start := cycle.seconds_left
	StormManager._process(1.0)
	var after_x1 := cycle.seconds_left
	GameConfig.set_game_speed(2.0)
	StormManager._process(1.0)
	var after_x2 := cycle.seconds_left
	assert_float(start - after_x1).is_equal_approx(1.0, 0.001)
	assert_float(after_x1 - after_x2).is_equal_approx(2.0, 0.001)

func test_the_day_clock_ticks_twice_as_fast() -> void:
	GameConfig.day_cycle_enabled = true
	DayClock.reset()
	var length := DayClock.get_cycle().length()
	var h0 := DayClock.get_hour()
	DayClock._process(1.0)
	var h1 := DayClock.get_hour()
	GameConfig.set_game_speed(2.0)
	DayClock._process(1.0)
	var h2 := DayClock.get_hour()
	assert_float((h1 - h0) * length).is_equal_approx(1.0, 0.01)
	assert_float((h2 - h1) * length).is_equal_approx(2.0, 0.01)

func test_the_enemy_turn_is_shorter_at_x2() -> void:
	var x1 := GameConfig.get_combat_ai_step_delay()
	GameConfig.set_game_speed(2.0)
	assert_float(GameConfig.get_combat_ai_step_delay()).is_equal_approx(x1 * 0.5, 0.0001)
	assert_float(GameConfig.combat_pace(0.4)).is_equal_approx(0.2, 0.0001)

# ── La interfaz no ───────────────────────────────────────────────────

func test_ui_cooldowns_stay_in_real_seconds() -> void:
	ProductionManager._full_bag_notice_cooldown = 5.0
	GameConfig.set_game_speed(2.0)
	ProductionManager._process(1.0)
	assert_float(ProductionManager._full_bag_notice_cooldown).is_equal_approx(4.0, 0.001)
	ProductionManager._full_bag_notice_cooldown = 0.0

func test_ui_tweens_run_at_real_speed() -> void:
	GameConfig.set_game_speed(2.0)
	var c := Control.new()
	add_child(c)
	_nodes.append(c)
	var tw := c.create_tween()
	tw.tween_property(c, "modulate:a", 0.0, 0.6)
	await get_tree().create_timer(0.3).timeout
	# A media animacion de verdad: x2 no la ha terminado antes de tiempo.
	assert_bool(tw.is_running()).is_true()
	assert_float(c.modulate.a).is_greater(0.2)
	tw.kill()

func test_played_time_counts_real_seconds() -> void:
	GameConfig.set_game_speed(2.0)
	var before := ProgressionManager.get_played_seconds()
	var started: bool = GameManager.is_started()
	ProgressionManager._process(1.0)
	var gained := ProgressionManager.get_played_seconds() - before
	assert_float(gained).is_equal_approx(1.0 if started else 0.0, 0.001)

# ── El boton ─────────────────────────────────────────────────────────

func test_the_menu_puts_the_speed_button_on_the_hud_and_it_toggles() -> void:
	var root := Node.new()
	add_child(root)
	_nodes.append(root)
	var menu: Node = load(PauseMenuScene).instantiate()
	menu.name = "PauseMenu"
	root.add_child(menu)
	await get_tree().process_frame
	var speed: Node = root.get_node_or_null("GameSpeedButton")
	assert_object(speed).is_not_null()
	assert_object(HudRegistry.control_of("GameSpeedButton")).is_not_null()
	var btn: Button = speed.button()
	assert_str(btn.text).is_equal("x1")
	btn.pressed.emit()
	assert_float(GameConfig.game_speed).is_equal(2.0)
	assert_str(btn.text).is_equal("x2")

func test_the_f_key_toggles_the_speed() -> void:
	var speed: CanvasLayer = load("res://scripts/ui/GameSpeedButton.gd").new()
	add_child(speed)
	_nodes.append(speed)
	var key := InputEventKey.new()
	key.keycode = KEY_F
	key.pressed = true
	speed._unhandled_key_input(key)
	assert_float(GameConfig.game_speed).is_equal(2.0)
	key.echo = true
	speed._unhandled_key_input(key)
	assert_float(GameConfig.game_speed).is_equal(2.0)

func test_the_button_is_hideable_and_movable() -> void:
	assert_bool("GameSpeedButton" in HudRegistry.hideable_ids()).is_true()
	assert_bool("GameSpeedButton" in HudRegistry.movable_ids()).is_true()
	assert_str(UILayoutConfig.PANEL_SLOTS.get("GameSpeedButton", "")).is_equal("speed_button")
	assert_str(Tr.t("HUD_GAME_SPEED")).is_not_equal("HUD_GAME_SPEED")
