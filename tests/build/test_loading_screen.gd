extends GdUnitTestSuite
## La pantalla de carga del arranque (scripts/boot/LoadingScreen.gd, docs/19 §14):
## Boot.tscn es la escena principal, las etapas tienen texto en los dos idiomas,
## la barra no retrocede, las rutas de get_dependencies() se entienden y
## AudioManager ya no carga sus clips al crearse.

const LoadingScreen := preload("res://scripts/boot/LoadingScreen.gd")
const BOOT_SCENE := "res://scenes/main/Boot.tscn"

func test_boot_is_the_main_scene() -> void:
	assert_str(str(ProjectSettings.get_setting("application/run/main_scene"))).is_equal(BOOT_SCENE)
	var packed: PackedScene = load(BOOT_SCENE)
	assert_object(packed).is_not_null()
	# Ligera: un solo nodo, para pintarse en el primer fotograma.
	var state := packed.get_state()
	assert_int(state.get_node_count()).is_equal(1)

func test_every_stage_text_exists_in_both_languages() -> void:
	var keys: Array = ["LOAD_LINE", "LOAD_COUNT", "LOAD_STAGE_NEW_GAME", "LOAD_STAGE_INSTANCE",
		"LOAD_STAGE_MENU", "LOAD_HINT_GRAPHICS", "LOAD_SLOW", "LOAD_FAILED_TITLE",
		"LOAD_FAILED_AT", "LOAD_FAILED_FILE", "LOAD_FAILED_LOG", "LOAD_BTN_RETRY"]
	for s: Dictionary in LoadingScreen.STAGES:
		keys.append(s["key"])
	for i in range(1, LoadingScreen.TIP_COUNT + 1):
		keys.append("LOAD_TIP_%d" % i)
	for lang in ["es", "en"]:
		for k in keys:
			assert_bool(Tr._STRINGS[lang].has(k)).override_failure_message("%s sin %s" % [lang, k]).is_true()
	# Un consejo de mas no se queda sin ensenar (TIP_COUNT al dia).
	assert_bool(Tr._STRINGS["es"].has("LOAD_TIP_%d" % (LoadingScreen.TIP_COUNT + 1))).is_false()

func test_random_tip_is_a_real_text() -> void:
	for _i in 20:
		var tip: String = LoadingScreen.random_tip()
		assert_bool(tip.begins_with("LOAD_TIP_")).is_false()

func test_version_reads_the_project_setting() -> void:
	var v := str(ProjectSettings.get_setting("application/config/version", ""))
	assert_str(LoadingScreen.version_text()).is_equal(v.replace("-", " "))

func test_dependency_lines_give_a_res_path() -> void:
	assert_str(LoadingScreen.dep_path("res://a/b.gd")).is_equal("res://a/b.gd")
	assert_str(LoadingScreen.dep_path("uid://abc::Script::res://a/b.gd")).is_equal("res://a/b.gd")
	assert_str(LoadingScreen.dep_path("uid://nada_que_exista")).is_equal("")
	# Las de la escena de verdad salen todas legibles.
	for dep in ResourceLoader.get_dependencies("res://scenes/main/Main.tscn"):
		assert_str(LoadingScreen.dep_path(dep)).starts_with("res://")

func test_the_bar_never_goes_back() -> void:
	var screen = LoadingScreen.new()
	for s: Dictionary in LoadingScreen.STAGES:
		screen._weights[s["id"]] = float(s["w"])
		screen._frac[s["id"]] = 0.0
	screen._frac["world"] = 1.0
	screen._frac["ui"] = 0.5
	var before: float = screen.percent()
	assert_float(before).is_greater(0.0)
	# Una etapa que crece al saber cuantos edificios hay no hace bajar la barra.
	screen._weights["game"] = 50000.0
	assert_float(screen.percent()).is_equal(before)
	for s: Dictionary in LoadingScreen.STAGES:
		screen._frac[s["id"]] = 1.0
	assert_float(screen.percent()).is_equal_approx(100.0, 0.001)
	screen.free()

func test_audio_clips_load_on_demand() -> void:
	var paths: PackedStringArray = AudioManager.stream_paths()
	assert_int(paths.size()).is_greater(0)
	for p in paths:
		assert_bool(ResourceLoader.exists(p)).is_true()
	assert_bool(AudioManager.has_stream("era_1")).is_true()
	assert_object(AudioManager._stream("era_1")).is_not_null()
	assert_object(AudioManager._stream("no_existe")).is_null()
