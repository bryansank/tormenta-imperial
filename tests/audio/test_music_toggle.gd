extends GdUnitTestSuite
## Musica si/no, aparte del volumen. El dueno la encontro muy invasiva: tiene que
## poder apagarse de un clic y quedarse apagada. Lo que se prueba es que nada la
## vuelve a encender sola: ni un cambio de era, ni el combate, ni el bucle de
## "keep-alive" de la pista. Los efectos no se tocan.
##
## Toca AudioManager y GameConfig (autoloads) y user://settings.cfg; cada prueba
## deja los tres como los encontro.

var _saved_enabled := true
var _saved_key := ""
## El settings.cfg del jugador se devuelve byte a byte: reescribirlo con
## save_user_settings() lo dejaba con claves nuevas que el jugador no tenia.
var _had_file := false
var _file_bytes := PackedByteArray()

func before_test() -> void:
	_saved_enabled = GameConfig.audio_music_enabled
	_saved_key = AudioManager.get_music_key()
	_had_file = FileAccess.file_exists(GameConfig.USER_SETTINGS_PATH)
	if _had_file:
		_file_bytes = FileAccess.get_file_as_bytes(GameConfig.USER_SETTINGS_PATH)

func after_test() -> void:
	AudioManager.set_music_enabled(_saved_enabled)
	GameConfig.audio_music_enabled = _saved_enabled
	AudioManager.stop_music()
	AudioManager._current_music_key = _saved_key
	_restore_settings_file()

func _restore_settings_file() -> void:
	if _had_file:
		var f := FileAccess.open(GameConfig.USER_SETTINGS_PATH, FileAccess.WRITE)
		f.store_buffer(_file_bytes)
		f.close()
	elif FileAccess.file_exists(GameConfig.USER_SETTINGS_PATH):
		DirAccess.remove_absolute(GameConfig.USER_SETTINGS_PATH)

func _has_track(key: String) -> bool:
	return AudioManager._streams.has(key)

func test_the_switch_persists_in_settings() -> void:
	AudioManager.set_music_enabled(false)
	GameConfig.audio_music_enabled = true  # se pierde en memoria a proposito
	GameConfig.load_user_settings()
	assert_bool(GameConfig.audio_music_enabled).is_false()

	AudioManager.set_music_enabled(true)
	GameConfig.audio_music_enabled = false
	GameConfig.load_user_settings()
	assert_bool(GameConfig.audio_music_enabled).is_true()

func test_no_music_plays_while_it_is_off() -> void:
	AudioManager.stop_music()
	AudioManager.set_music_enabled(false)
	AudioManager.play_music("era_1")
	assert_bool(AudioManager.is_music_playing()).is_false()
	# Pero se sabe que pista queria el juego, para volver a ella al encender.
	if _has_track("era_1"):
		assert_str(AudioManager.get_music_key()).is_equal("era_1")

func test_an_era_change_while_off_stays_silent() -> void:
	AudioManager.stop_music()
	AudioManager.set_music_enabled(false)
	AudioManager._on_era_advanced(2)
	assert_bool(AudioManager.is_music_playing()).is_false()
	if _has_track("era_2"):
		assert_str(AudioManager.get_music_key()).is_equal("era_2")

func test_switching_off_stops_what_was_playing() -> void:
	if not _has_track("era_1"):
		return
	AudioManager.set_music_enabled(true)
	AudioManager.stop_music()
	AudioManager.play_music("era_1")
	AudioManager.set_music_enabled(false)
	assert_bool(AudioManager.is_music_playing()).is_false()

func test_switching_back_on_resumes_the_wanted_track() -> void:
	if not _has_track("era_3"):
		return
	AudioManager.stop_music()
	AudioManager.set_music_enabled(false)
	AudioManager.play_music("era_3")
	AudioManager.set_music_enabled(true)
	assert_str(AudioManager.get_music_key()).is_equal("era_3")
	assert_bool(AudioManager._music_players[0].stream == AudioManager._streams["era_3"]).is_true()

func test_the_music_bus_is_muted_while_off_and_sfx_is_not() -> void:
	AudioManager.set_music_enabled(false)
	var music_bus := AudioServer.get_bus_index(AudioManager.BUS_MUSIC)
	var sfx_bus := AudioServer.get_bus_index(AudioManager.BUS_SFX)
	assert_bool(AudioServer.is_bus_mute(music_bus)).is_true()
	# Los efectos siguen como diga su propio deslizador.
	assert_bool(AudioServer.is_bus_mute(sfx_bus)).is_equal(GameConfig.audio_sfx_volume <= 0.0)

func test_the_volume_slider_does_not_unmute_music_that_is_off() -> void:
	AudioManager.set_music_enabled(false)
	var saved_volume := GameConfig.audio_music_volume
	AudioManager.set_music_volume(0.8)
	assert_bool(AudioServer.is_bus_mute(AudioServer.get_bus_index(AudioManager.BUS_MUSIC))).is_true()
	AudioManager.set_music_volume(saved_volume)

func test_toggling_announces_the_new_state() -> void:
	AudioManager.set_music_enabled(true)
	var received: Array = []
	var listener := func(enabled: bool): received.append(enabled)
	EventBus.music_toggled.connect(listener)
	AudioManager.toggle_music()
	AudioManager.toggle_music()
	EventBus.music_toggled.disconnect(listener)
	assert_array(received).is_equal([false, true])

func test_the_default_music_volume_is_gentle() -> void:
	# Bajada a proposito (0.6 -> 0.35). Si alguien la sube, que sea a conciencia.
	var fresh: Node = load("res://scripts/services/GameConfig.gd").new()
	assert_float(float(fresh.get("audio_music_volume"))).is_less_equal(0.4)
	assert_bool(bool(fresh.get("audio_music_enabled"))).is_true()
	fresh.free()
