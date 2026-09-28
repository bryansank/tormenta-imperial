extends GdUnitTestSuite
## save_parking.gd no toca nada si cree estar en la carpeta del jugador.
##
## Aparcar es un rename y un remove sobre user://save_game.json: en la carpeta de
## tests es inofensivo, en la del jugador es jugar con su partida. Si la suite se
## lanza sin tools/run_tests.sh (sin carpeta de tests), la guarda avisa y se
## aparta: no mueve, no borra, y le dice a quien llama que no aparco nada.

const Parking := preload("res://tests/save/save_parking.gd")

func test_reconoce_las_carpetas_del_jugador() -> void:
	var data := OS.get_data_dir()
	assert_bool(Parking.is_player_dir(data.path_join("Godot/app_userdata/Tormenta Imperial"))).is_true()
	# Mismo sitio, escrito como lo devuelve Windows.
	assert_bool(Parking.is_player_dir(data.path_join("Godot/app_userdata/Tormenta Imperial").replace("/", "\\").to_upper() + "\\")).is_true()
	# El del juego exportado tambien es del jugador.
	assert_bool(Parking.is_player_dir(data.path_join("TormentaImperial"))).is_true()
	assert_bool(Parking.is_player_dir(data.path_join("TormentaImperial_tests"))).is_false()
	assert_bool(Parking.is_player_dir(data.path_join("TI_arreglos_sueltos"))).is_false()

func test_la_ejecucion_actual_no_corre_en_la_carpeta_del_jugador() -> void:
	# Si esto falla, la suite se lanzo sin tools/run_tests.sh.
	assert_bool(Parking.is_player_dir(OS.get_user_data_dir())).is_false()

func test_en_la_carpeta_del_jugador_no_aparca_ni_borra() -> void:
	var backup := "user://save_game.parking_guard_test.bak"
	var had_save := FileAccess.file_exists(Parking.SAVE_PATH)
	var before := FileAccess.get_file_as_string(Parking.SAVE_PATH) if had_save else ""
	var player_dir := OS.get_data_dir().path_join("Godot/app_userdata/Tormenta Imperial")
	assert_bool(Parking.park(backup, player_dir)).is_false()
	assert_bool(FileAccess.file_exists(backup)).is_false()
	assert_bool(FileAccess.file_exists(Parking.SAVE_PATH)).is_equal(had_save)
	# restore tampoco borra lo que haya en su sitio.
	Parking.restore(backup, player_dir)
	assert_bool(FileAccess.file_exists(Parking.SAVE_PATH)).is_equal(had_save)
	if had_save:
		assert_str(FileAccess.get_file_as_string(Parking.SAVE_PATH)).is_equal(before)

func test_en_la_carpeta_de_tests_aparca_y_devuelve() -> void:
	var backup := "user://save_game.parking_guard_test.bak"
	var had_save := FileAccess.file_exists(Parking.SAVE_PATH)
	var original := FileAccess.get_file_as_string(Parking.SAVE_PATH) if had_save else ""
	var f := FileAccess.open(Parking.SAVE_PATH, FileAccess.WRITE)
	f.store_string("{\"marca\":1}")
	f.close()
	assert_bool(Parking.park(backup)).is_true()
	assert_bool(FileAccess.file_exists(Parking.SAVE_PATH)).is_false()
	Parking.restore(backup)
	assert_str(FileAccess.get_file_as_string(Parking.SAVE_PATH)).is_equal("{\"marca\":1}")
	if had_save:
		var w := FileAccess.open(Parking.SAVE_PATH, FileAccess.WRITE)
		w.store_string(original)
		w.close()
	else:
		DirAccess.remove_absolute(Parking.SAVE_PATH)
