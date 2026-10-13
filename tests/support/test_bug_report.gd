extends GdUnitTestSuite
## "Informar de un fallo" (☰ MENÚ > PARTIDA) y el registro local (ErrorLog,
## docs/19 §7): el informe lleva version, sistema, video, interfaz, partida y
## las ultimas lineas del registro; nunca rutas con el nombre del usuario ni el
## nombre de la colonia. El registro escribe en bloque y rota con tope.

func test_the_report_has_every_section() -> void:
	var text := BugReport.build(["linea uno", "linea dos"])
	var version := str(ProjectSettings.get_setting("application/config/version"))
	assert_str(text).contains(version)
	for key in ["REPORT_SYSTEM", "REPORT_VIDEO", "REPORT_SCREEN", "REPORT_GAME", "REPORT_LOG"]:
		assert_str(text).contains(Tr.t(key) + ":")
	assert_str(text).contains(OS.get_name())
	assert_str(text).contains(GameConfig.ui_locale)
	assert_str(text).contains("linea dos")

func test_the_report_is_short() -> void:
	var lines: Array = []
	for i in 40:
		lines.append("l%d" % i)
	var text := BugReport.build(lines)
	# Seis lineas de cabecera, las dos vallas y las del registro.
	assert_int(text.split("\n").size()).is_less_equal(40 + 8)

func test_the_menu_entry_copies_and_says_so() -> void:
	var root := Node.new()
	add_child(root)
	var menu: Node = load("res://scenes/ui/PauseMenu.tscn").instantiate()
	menu.name = "PauseMenu"
	root.add_child(menu)
	var btn: Button = menu.entry("Game_Report")
	assert_object(btn).is_not_null()
	assert_str(btn.text).is_equal(Tr.t("BTN_REPORT_BUG"))
	menu.report_bug()
	assert_str(menu._status.text).is_equal(Tr.t("MSG_REPORT_COPIED"))
	root.free()

func test_windows_and_unix_home_paths_become_tilde() -> void:
	var dirty := "ERROR: C:\\Users\\MariaPerez\\AppData\\Roaming\\TormentaImperial\\save.json\n" \
		+ "C:/Users/MariaPerez/AppData/Roaming/Godot/x.cfg\n/home/maria/.local/share/godot\n/Users/maria/Library"
	var clean := BugReport.sanitize(dirty)
	assert_str(clean).not_contains("MariaPerez")
	assert_str(clean).not_contains("maria")
	assert_str(clean).contains("~\\AppData\\Roaming\\TormentaImperial\\save.json")
	assert_str(clean).contains("~/AppData/Roaming/Godot/x.cfg")

func test_this_machine_home_dir_never_reaches_the_report() -> void:
	var home := OS.get_environment("USERPROFILE")
	if home.is_empty():
		home = OS.get_environment("HOME")
	if home.length() <= 3:
		return
	var text := BugReport.build([home + "\\logs\\x.txt", OS.get_user_data_dir() + "/logs/registro.txt"])
	assert_str(text).not_contains(home)
	assert_str(text).not_contains(home.replace("\\", "/"))
	var user := home.replace("\\", "/").get_file()
	if user.length() >= 3:
		assert_str(text).not_contains("/" + user + "/")
		assert_str(text).not_contains("\\" + user + "\\")

func test_the_colony_name_is_covered() -> void:
	var saved: String = RankManager._colony_name
	RankManager._colony_name = "Venezuela Libre"
	var text := BugReport.build(["Colonia Venezuela Libre fundada"])
	RankManager._colony_name = saved
	assert_str(text).not_contains("Venezuela Libre")
	assert_str(text).contains("<colonia>")

# ── El registro ──────────────────────────────────────────────────────

func test_the_log_is_installed_and_keeps_recent_lines() -> void:
	assert_object(ErrorLog.instance()).is_not_null()
	ErrorLog.note("prueba-registro-123")
	var recent := ErrorLog.recent_lines(40)
	assert_bool(recent.size() <= 40).is_true()
	assert_str(recent[recent.size() - 1]).contains("prueba-registro-123")

func test_print_reaches_the_log() -> void:
	print("prueba-print-456")
	var joined := "\n".join(ErrorLog.recent_lines(80))
	assert_str(joined).contains("prueba-print-456")

func test_repeated_lines_are_counted_not_repeated() -> void:
	for i in 5:
		ErrorLog.note("prueba-repetida")
	ErrorLog.note("prueba-otra")
	var recent := ErrorLog.recent_lines(80)
	var count := 0
	for l in recent:
		if l.contains("prueba-repetida"):
			count += 1
	assert_int(count).is_equal(1)
	assert_str("\n".join(recent)).contains("(x5)")

func test_flush_writes_to_the_user_dir_file() -> void:
	ErrorLog.note("prueba-disco-789")
	ErrorLog.flush_now()
	var text := FileAccess.get_file_as_string(ErrorLog.file_path())
	assert_str(text).contains("prueba-disco-789")

func test_the_file_rotates_at_the_cap() -> void:
	ErrorLog.flush_now()
	var base := ErrorLog.DIR + "/" + ErrorLog.FILE_NAME.get_basename()
	var real := FileAccess.get_file_as_string(ErrorLog.file_path())
	var big := "x".repeat(ErrorLog.MAX_BYTES - 10) + "\n"
	var f := FileAccess.open(ErrorLog.file_path(), FileAccess.WRITE)
	f.store_string(big)
	f.close()
	ErrorLog.instance()._write_block("una linea que ya no cabe\n".repeat(4))
	# Lo viejo paso a .1 y el archivo nuevo empieza pequeno.
	assert_bool(FileAccess.file_exists(base + ".1.txt")).is_true()
	assert_int(FileAccess.open(ErrorLog.file_path(), FileAccess.READ).get_length()).is_less(1024)
	assert_int(FileAccess.open(base + ".1.txt", FileAccess.READ).get_length()).is_less_equal(ErrorLog.MAX_BYTES)
	# Nunca mas de ROTATIONS copias viejas.
	for i in 3:
		var g := FileAccess.open(ErrorLog.file_path(), FileAccess.WRITE)
		g.store_string(big)
		g.close()
		ErrorLog.instance()._write_block("otra\n")
	assert_bool(FileAccess.file_exists("%s.%d.txt" % [base, ErrorLog.ROTATIONS + 1])).is_false()
	# Deja el registro como estaba.
	var back := FileAccess.open(ErrorLog.file_path(), FileAccess.WRITE)
	back.store_string(real)
	back.close()
	for i in range(1, ErrorLog.ROTATIONS + 1):
		DirAccess.remove_absolute("%s.%d.txt" % [base, i])
