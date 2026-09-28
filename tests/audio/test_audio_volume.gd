extends GdUnitTestSuite
## Volumen de serie bajo y deslizador con curva perceptual (bug 4 del
## diagnostico de jugabilidad). En el primer arranque, sin settings.cfg, los
## efectos sonaban ~15 dB por encima de la musica y era_up recortaba.

const GameConfigScript := preload("res://scripts/services/GameConfig.gd")
const AudioManagerScript := preload("res://scripts/services/AudioManager.gd")

var _saved := {}

func before_test() -> void:
	_saved = {
		"master": GameConfig.audio_master_volume,
		"sfx": GameConfig.audio_sfx_volume,
		"music": GameConfig.audio_music_volume,
	}

func after_test() -> void:
	AudioManager.set_master_volume(_saved["master"])
	AudioManager.set_sfx_volume(_saved["sfx"])
	AudioManager.set_music_volume(_saved["music"])

## Una GameConfig recien hecha es lo que ve un primer arranque: sin
## settings.cfg, load_user_settings() no toca nada.
func test_first_launch_defaults_are_low() -> void:
	var fresh: Node = auto_free(GameConfigScript.new())
	assert_float(fresh.audio_master_volume).is_equal_approx(0.8, 0.001)
	assert_float(fresh.audio_sfx_volume).is_equal_approx(0.5, 0.001)
	assert_float(fresh.audio_music_volume).is_equal_approx(0.35, 0.001)
	assert_float(fresh.audio_ambient_volume).is_less_equal(0.5)

func test_slider_curve_is_perceptual() -> void:
	# La mitad del deslizador baja 12 dB (antes, 6).
	assert_float(AudioManagerScript.slider_to_db(0.5)).is_less_equal(-12.0)
	assert_float(AudioManagerScript.slider_to_db(1.0)).is_equal_approx(0.0, 0.001)
	assert_float(AudioManagerScript.slider_to_db(0.0)).is_less_equal(-79.0)
	# Monotona: subir el deslizador nunca baja el volumen.
	var prev := -100.0
	for i in range(1, 21):
		var db: float = AudioManagerScript.slider_to_db(i / 20.0)
		assert_float(db).is_greater(prev)
		prev = db

func test_sfx_bus_gets_the_curve() -> void:
	AudioManager.set_sfx_volume(0.5)
	var idx := AudioServer.get_bus_index("SFX")
	assert_float(AudioServer.get_bus_volume_db(idx)).is_less_equal(-12.0)

## Con los valores de serie, un efecto llega al altavoz por debajo de -6 dB
## (master + bus SFX), y mas bajo aun con su ganancia de clip.
func test_default_sfx_path_is_below_minus_six_db() -> void:
	var fresh: Node = auto_free(GameConfigScript.new())
	var total: float = AudioManagerScript.slider_to_db(fresh.audio_master_volume) \
		+ AudioManagerScript.slider_to_db(fresh.audio_sfx_volume)
	assert_float(total).is_less(-6.0)
	assert_float(total + AudioManager.sfx_gain_db("build_place")).is_less(-15.0)

func test_clipping_and_frequent_clips_are_attenuated() -> void:
	# era_up recortaba (+0.1 dBFS): tiene que bajar al menos 10 dB.
	assert_float(AudioManager.sfx_gain_db("era_up")).is_less_equal(-10.0)
	# ui_click suena en cada boton.
	assert_float(AudioManager.sfx_gain_db("ui_click")).is_less_equal(-9.0)
	# Las claves de combate que reusan un clip se llevan su ganancia.
	assert_float(AudioManager.sfx_gain_db("expedition_return")).is_equal(AudioManager.sfx_gain_db("era_up"))
	# Ningun efecto sale sin atenuar.
	for key in AudioManager.SFX_MANIFEST:
		assert_float(AudioManager.sfx_gain_db(key)).is_less(0.0)
