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
## El cielo limpio es el del dia pleno: la prueba fija la hora para que el reloj
## del dia (que corre, y en dev_mode rapido) no la cambie por debajo.
var _saved_day: Dictionary = {}

func before_test() -> void:
	_saved_storm = StormManager.get_save_data()
	_saved_mult = GameConfig.event_production_multiplier
	_saved_scene = get_tree().current_scene
	_env = Environment.new()
	_env.background_color = Color(0.5, 0.6, 0.7)
	_env.ambient_light_color = Color(0.8, 0.8, 0.8)
	_env.ambient_light_energy = 1.0
	_saved_day = DayClock.get_save_data()
	DayClock.set_hour(DayClock.get_cycle().day_start() + 0.01)
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
	DayClock.load_save_data(_saved_day)

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
	assert_float(_env.fog_density).is_equal_approx(StormSky.MAX_FOG * StormSky.ash_weight(), 0.0001)
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
	assert_float(StormSky.weight_for(StormCycle.Phase.WARNING, 3)).is_equal(StormSky.warning_weight())
	assert_float(StormSky.weight_for(StormCycle.Phase.ASH, 3)).is_equal(StormSky.ash_weight())
	# Fuera del golpe la Tormenta se queda en el tono de fondo; el golpe dice la severidad.
	assert_float(StormSky.weight_for(StormCycle.Phase.STORM, 1)).is_equal(StormSky.linger_weight())
	assert_float(StormSky.punch_weight(1)).is_greater_equal(0.6)
	assert_float(StormSky.punch_weight(99)).is_equal(1.0)
	assert_float(StormSky.linger_weight()).is_less(StormSky.punch_weight(1))

## La espuma de la isla, con su shader de verdad, colgada de la escena.
func _add_foam(scene: Node) -> ShaderMaterial:
	var foam := MeshInstance3D.new()
	foam.name = "Foam"
	foam.mesh = PlaneMesh.new()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/map/island_foam.gdshader")
	foam.set_surface_override_material(0, mat)
	scene.add_child(foam)
	return mat

func test_the_island_darkens_with_the_sky_and_comes_back_clean() -> void:
	var scene := _scene()
	var foam := _add_foam(scene)
	_load_phase(StormCycle.Phase.ASH)
	EventBus.game_load_completed.emit()
	assert_float(float(foam.get_shader_parameter("storm_weight"))).is_equal_approx(StormSky.ash_weight(), 0.0001)
	assert_float(StormSky.get_island_weight()).is_equal_approx(StormSky.ash_weight(), 0.0001)
	_load_phase(StormCycle.Phase.CALM)
	EventBus.game_load_completed.emit()
	assert_float(float(foam.get_shader_parameter("storm_weight"))).is_equal(0.0)

func test_without_a_sky_the_island_weight_is_still_kept() -> void:
	# Vista 2D o escena a medio montar: no hay cielo, pero la isla que se cree
	# despues tiene que nacer con la Tormenta puesta.
	var bare := Node3D.new()
	get_tree().root.add_child(bare)
	get_tree().current_scene = bare
	_scenes.append(bare)
	_load_phase(StormCycle.Phase.STORM)
	StormSky.sync_to_storm()
	# Cargar a media Tormenta no repite el golpe (feat/danos-y-tormenta-corta):
	# la isla nace con el tono de fondo, no en blanco.
	assert_float(StormSky.get_island_weight()).is_equal_approx(StormSky.linger_weight(), 0.0001)
	assert_float(StormSky.get_island_weight()).is_greater(0.0)
	StormSky.restore_now()
	assert_float(StormSky.get_island_weight()).is_equal(0.0)

## De noche el cielo se enfria y baja, pero la Tormenta encima pinta la misma
## ceniza que de dia (la ceniza manda), y al pasar vuelve la noche.
func test_at_night_the_sky_is_blue_and_the_storm_still_rules() -> void:
	var scene := _scene()
	var foam := _add_foam(scene)
	var c := DayClock.get_cycle()
	_load_phase(StormCycle.Phase.CALM)
	DayClock.set_hour(1.0 - 0.5 * c.night_seconds / c.length())
	EventBus.game_load_completed.emit()
	var sun := _sun_of(scene)
	assert_float(sun.light_energy).is_less(2.0)
	assert_float(sun.light_energy).is_greater(0.5)
	assert_float(sun.light_color.b).is_greater(sun.light_color.r)
	assert_float(float(foam.get_shader_parameter("night_weight"))).is_equal_approx(1.0, 0.0001)
	var night_bg := _env.background_color
	_load_phase(StormCycle.Phase.ASH)
	StormSky.sync_to_storm()
	var night_ash := _env.background_color
	assert_float(float(foam.get_shader_parameter("night_weight"))).is_less(0.5)
	DayClock.set_hour(c.day_start() + 0.01)
	StormSky.sync_to_storm()
	var day_ash := _env.background_color
	# Con ceniza la noche se nota menos que sin ella.
	assert_float(absf(night_ash.b - day_ash.b)).is_less(absf(night_bg.b - Color(0.5, 0.6, 0.7).b))
	assert_float(_env.fog_density).is_equal_approx(StormSky.MAX_FOG * StormSky.ash_weight(), 0.0001)

func test_windows_glow_more_at_night_than_by_day() -> void:
	_scene()
	var c := DayClock.get_cycle()
	_load_phase(StormCycle.Phase.CALM)
	StormSky.sync_to_storm()
	var day_gain := StormSky.glow_gain_now()
	DayClock.set_hour(1.0 - 0.5 * c.night_seconds / c.length())
	StormSky.refresh_day()
	assert_float(StormSky.glow_gain_now()).is_greater(day_gain)
	assert_float(day_gain).is_less(1.0)
