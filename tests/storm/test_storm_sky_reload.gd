extends GdUnitTestSuite
## El cielo sobrevive a la recarga de escena.
##
## StormSky es un autoload: guardaba la luz y el Environment de la primera
## escena y, tras "Partida nueva" o una carga, seguia apuntando a una luz
## liberada. Tampoco repintaba el cielo al cargar: con la ceniza cayendo se veia
## despejado.

var _saved_storm: Dictionary = {}
var _saved_mult: float = 1.0
var _saved_scene: Node = null
var _scenes: Array = []
var _env: Environment = null

func before_test() -> void:
	_saved_storm = StormManager.get_save_data()
	_saved_mult = GameConfig.event_production_multiplier
	_saved_scene = get_tree().current_scene
	_env = Environment.new()
	_env.background_color = Color(0.5, 0.6, 0.7)
	_env.ambient_light_color = Color(0.8, 0.8, 0.8)
	_env.ambient_light_energy = 1.0
	StormSky.reset()

func after_test() -> void:
	get_tree().current_scene = _saved_scene if is_instance_valid(_saved_scene) else null
	for scene in _scenes:
		if is_instance_valid(scene):
			get_tree().root.remove_child(scene)
			scene.free()
	_scenes.clear()
	StormSky.reset()
	StormManager.load_save_data(_saved_storm)
	StormManager._tithe_to_resume = false
	GameConfig.event_production_multiplier = _saved_mult

## Una Main minima con el mismo Environment, como hace el sub-recurso cacheado.
func _scene() -> Node:
	var scene := Node3D.new()
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = _env
	scene.add_child(we)
	var light := DirectionalLight3D.new()
	light.name = "DirectionalLight"
	light.light_energy = 2.0
	scene.add_child(light)
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	_scenes.append(scene)
	return scene

func _load_phase(phase: int) -> void:
	var cycle := StormCycle.create(3)
	cycle.phase = phase
	cycle.seconds_left = 30.0
	var data: Dictionary = cycle.to_dict()
	data["armed"] = true
	StormManager.load_save_data(data)

func _sun_of(scene: Node) -> DirectionalLight3D:
	return scene.get_node("DirectionalLight")

func test_loading_during_the_ash_paints_the_ash_at_once() -> void:
	var scene := _scene()
	_load_phase(StormCycle.Phase.ASH)
	EventBus.game_load_completed.emit()
	assert_float(_env.fog_density).is_equal_approx(StormSky.MAX_FOG * StormSky.WEIGHT_ASH, 0.0001)
	assert_float(_sun_of(scene).light_energy).is_less(2.0)

func test_after_a_reload_the_sky_follows_the_new_scene_and_comes_back_clean() -> void:
	var first := _scene()
	_load_phase(StormCycle.Phase.STORM)
	EventBus.game_load_completed.emit()
	assert_float(_env.fog_density).is_greater(0.0)

	# Recarga: la escena vieja muere, el Environment (cacheado) sigue sucio.
	get_tree().root.remove_child(first)
	first.free()
	var second := _scene()
	StormManager.reset()
	EventBus.game_new_started.emit()

	assert_object(StormSky._sun).is_same(_sun_of(second))
	assert_float(_env.fog_density).is_equal(0.0)
	assert_that(_env.background_color).is_equal(Color(0.5, 0.6, 0.7))
	assert_float(_sun_of(second).light_energy).is_equal(2.0)

func test_syncing_twice_in_the_same_storm_does_not_lose_the_clean_sky() -> void:
	var scene := _scene()
	_load_phase(StormCycle.Phase.STORM)
	StormSky.sync_to_storm()
	StormSky.sync_to_storm()
	_load_phase(StormCycle.Phase.CALM)
	StormSky.sync_to_storm()
	assert_float(_sun_of(scene).light_energy).is_equal(2.0)
	assert_that(_env.background_color).is_equal(Color(0.5, 0.6, 0.7))

func test_every_phase_has_its_weight() -> void:
	assert_float(StormSky.weight_for(StormCycle.Phase.CALM, 3)).is_equal(0.0)
	assert_float(StormSky.weight_for(StormCycle.Phase.TITHE, 3)).is_equal(0.0)
	assert_float(StormSky.weight_for(StormCycle.Phase.WARNING, 3)).is_equal(StormSky.WEIGHT_WARNING)
	assert_float(StormSky.weight_for(StormCycle.Phase.ASH, 3)).is_equal(StormSky.WEIGHT_ASH)
	assert_float(StormSky.weight_for(StormCycle.Phase.STORM, 1)).is_greater_equal(0.6)
