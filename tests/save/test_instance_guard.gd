extends GdUnitTestSuite
## Una sola copia abierta (InstanceGuard): solo la parte pura. Que hacer segun el
## bloqueo, si su PID vive y la version; cuando no se mira; como se leen el
## bloqueo y la salida de tasklist. No toca el disco ni el sistema.

const Guard := preload("res://scripts/services/InstanceGuard.gd")
const ME := 5000
const V := "1.0.0"

func _lock(pid: int, version: String = V) -> Dictionary:
	return {"pid": pid, "version": version, "exe": "TormentaImperial.exe", "time": "2026-10-14T10:00:00"}

# ── decide ──

func test_sin_bloqueo_se_arranca() -> void:
	assert_int(Guard.decide({}, false, [], ME, V)).is_equal(Guard.Action.RUN)

func test_bloqueo_de_un_proceso_muerto_se_ignora() -> void:
	assert_int(Guard.decide(_lock(1234), false, [], ME, V)).is_equal(Guard.Action.RUN)

func test_bloqueo_propio_no_cuenta() -> void:
	assert_int(Guard.decide(_lock(ME), true, [], ME, V)).is_equal(Guard.Action.RUN)

func test_misma_version_viva_avisa() -> void:
	assert_int(Guard.decide(_lock(1234), true, [], ME, V)).is_equal(Guard.Action.ALREADY_OPEN)

func test_otra_version_viva_pregunta() -> void:
	assert_int(Guard.decide(_lock(1234, "0.9.0"), true, [], ME, V)).is_equal(Guard.Action.OTHER_VERSION)

func test_copia_suelta_sin_bloqueo_es_otra_version() -> void:
	assert_int(Guard.decide({}, false, [777], ME, V)).is_equal(Guard.Action.OTHER_VERSION)

func test_la_copia_suelta_propia_no_cuenta() -> void:
	assert_int(Guard.decide({}, false, [ME], ME, V)).is_equal(Guard.Action.RUN)

func test_un_bloqueo_vivo_manda_sobre_las_sueltas() -> void:
	assert_int(Guard.decide(_lock(1234), true, [777], ME, V)).is_equal(Guard.Action.ALREADY_OPEN)

# ── targets ──

func test_se_cierra_el_del_bloqueo() -> void:
	assert_array(Guard.targets(_lock(1234, "0.9.0"), true, [777], ME)).contains_exactly([1234])

func test_sin_bloqueo_vivo_se_cierran_las_sueltas() -> void:
	assert_array(Guard.targets(_lock(1234), false, [777, ME, 777, 888], ME)).contains_exactly([777, 888])

# ── applies ──

func test_no_se_mira_en_el_editor_ni_en_movil_ni_en_web() -> void:
	assert_bool(Guard.applies(["editor"], "Windows", [])).is_false()
	assert_bool(Guard.applies(["mobile"], "Android", [])).is_false()
	assert_bool(Guard.applies(["web"], "Web", [])).is_false()

func test_no_se_mira_sin_ventana() -> void:
	assert_bool(Guard.applies([], "headless", [])).is_false()

func test_no_se_mira_con_no_title_ni_multi() -> void:
	assert_bool(Guard.applies([], "Windows", ["--no-title"])).is_false()
	assert_bool(Guard.applies([], "Windows", ["--multi"])).is_false()

func test_se_mira_en_un_exportado_normal() -> void:
	assert_bool(Guard.applies([], "Windows", [])).is_true()
	assert_bool(Guard.applies([], "Windows", ["--view=2d"])).is_true()

# ── el bloqueo ──

func test_el_bloqueo_va_y_vuelve() -> void:
	var lock := Guard.parse_lock(Guard.lock_text(1234, V, "TormentaImperial.exe", "ahora"))
	assert_int(int(lock["pid"])).is_equal(1234)
	assert_str(str(lock["version"])).is_equal(V)
	assert_str(str(lock["exe"])).is_equal("TormentaImperial.exe")

func test_un_bloqueo_roto_es_ninguno() -> void:
	assert_dict(Guard.parse_lock("")).is_empty()
	assert_dict(Guard.parse_lock("no es json")).is_empty()
	assert_dict(Guard.parse_lock("[1, 2]")).is_empty()
	assert_dict(Guard.parse_lock("{\"version\": \"1.0.0\"}")).is_empty()

# ── tasklist ──

const TASKLIST_ROW := "\"TormentaImperial.exe\",\"1234\",\"Console\",\"1\",\"312.400 K\"\r\n"

func test_tasklist_encuentra_el_pid_y_el_nombre() -> void:
	assert_bool(Guard.tasklist_has(TASKLIST_ROW, 1234, "TormentaImperial.exe")).is_true()
	assert_bool(Guard.tasklist_has(TASKLIST_ROW, 1234, "tormentaimperial.EXE")).is_true()

func test_un_pid_reusado_por_otro_programa_no_es_el_juego() -> void:
	var row := "\"notepad.exe\",\"1234\",\"Console\",\"1\",\"9.000 K\"\r\n"
	assert_bool(Guard.tasklist_has(row, 1234, "TormentaImperial.exe")).is_false()

func test_tasklist_sin_resultados_en_cualquier_idioma() -> void:
	assert_bool(Guard.tasklist_has("INFO: No tasks are running which match the specified criteria.\r\n", 1234, "")).is_false()
	assert_bool(Guard.tasklist_has("INFORMACIÓN: no hay tareas ejecutándose que coincidan con los criterios especificados.\r\n", 1234, "")).is_false()

func test_tasklist_varias_filas() -> void:
	var out := TASKLIST_ROW + "\"TormentaImperial.exe\",\"4321\",\"Console\",\"1\",\"300.000 K\"\r\n"
	var rows := Guard.parse_tasklist(out)
	assert_int(rows.size()).is_equal(2)
	assert_int(int(rows[1]["pid"])).is_equal(4321)
