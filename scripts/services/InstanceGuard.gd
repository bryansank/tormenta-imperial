extends RefCounted
## Una sola copia del juego abierta a la vez (pedido del dueño, 2026-10-14):
## "si ya el juego se está ejecutando no dejes que levante varias veces, a menos
## que sea otra versión: túmbala y pregunta".
##
## Dos juegos abiertos sobre la misma carpeta de usuario se pisan la partida: los
## dos autoguardan, y gana el ultimo en escribir. Al arrancar se mira un archivo de
## bloqueo en el user dir (`user://instancia.lock`: PID, version, ejecutable y
## hora) y si ese PID sigue vivo y es el juego:
##   - misma version abierta  -> aviso corto y se sale (se intenta traer al
##                                frente la ventana que ya estaba);
##   - otra version abierta   -> se pregunta; con SI se cierra la otra
##                                (OS.kill), se espera a que muera y se sigue.
## Un bloqueo de un proceso muerto (un cierre a lo bruto) se ignora y se reescribe.
## Las versiones de antes de este archivo no escriben bloqueo: en Windows se buscan
## ademas otros procesos con el mismo nombre de ejecutable y se tratan como "otra
## version" sin numero.
##
## No se aplica (applies()) en el editor, sin ventana (headless), con `-- --no-title`
## o `-- --multi`: las sondas, los tests y los agentes abren varios Godot a la vez,
## cada worktree con su user dir. Tampoco en movil ni en web: Android ya da una
## sola instancia por app (launchMode de la actividad de Godot).
##
## La parte pura (applies, decide, parse_*) no toca el sistema y se prueba en
## tests/save/test_instance_guard.gd; el resto (leer y escribir el bloqueo,
## preguntar a tasklist, matar) lo usa GameManager.

const LOCK_PATH := "user://instancia.lock"

enum Action {
	RUN,            ## No hay otra copia viva: se arranca y se toma el bloqueo.
	ALREADY_OPEN,   ## La misma version ya esta abierta: aviso y salir.
	OTHER_VERSION,  ## Otra version abierta: preguntar si se cierra.
}

# ── Parte pura ──────────────────────────────────────────────────────

## Si la comprobacion va en esta ejecucion. `features` son los feature tags que
## importan ("editor", "mobile", "web"), `display` el nombre del DisplayServer.
static func applies(features: Array, display: String, user_args: Array) -> bool:
	if features.has("editor") or features.has("mobile") or features.has("web"):
		return false
	if display == "headless":
		return false
	if user_args.has("--no-title") or user_args.has("--multi"):
		return false
	return true

## Que hacer al arrancar. `lock` es el bloqueo leido ({} si no hay o no se lee),
## `lock_alive` si su PID sigue vivo y es el juego, `strays` los PID de otras copias
## del mismo ejecutable halladas sin bloqueo (versiones antiguas).
static func decide(lock: Dictionary, lock_alive: bool, strays: Array, my_pid: int, my_version: String) -> int:
	var pid: int = int(lock.get("pid", 0))
	if pid > 0 and pid != my_pid and lock_alive:
		if str(lock.get("version", "")) == my_version:
			return Action.ALREADY_OPEN
		return Action.OTHER_VERSION
	for stray in strays:
		if int(stray) > 0 and int(stray) != my_pid:
			return Action.OTHER_VERSION
	return Action.RUN

## Los PID a cerrar si el jugador dice SI: el del bloqueo si vive, si no los
## sueltos. Nunca el propio.
static func targets(lock: Dictionary, lock_alive: bool, strays: Array, my_pid: int) -> Array:
	var pid: int = int(lock.get("pid", 0))
	if pid > 0 and pid != my_pid and lock_alive:
		return [pid]
	var out: Array = []
	for stray in strays:
		if int(stray) > 0 and int(stray) != my_pid and not out.has(int(stray)):
			out.append(int(stray))
	return out

## El texto del bloqueo.
static func lock_text(pid: int, version: String, exe: String, time: String) -> String:
	return JSON.stringify({"pid": pid, "version": version, "exe": exe, "time": time})

## Lee el texto del bloqueo. Algo que no es un diccionario con PID cuenta como
## "no hay bloqueo".
static func parse_lock(text: String) -> Dictionary:
	var data: Variant = JSON.parse_string(text)
	if not (data is Dictionary) or not data.has("pid"):
		return {}
	return data

## Las filas de `tasklist /FO CSV /NH`: [{"image", "pid"}]. Si no hay ninguna, tasklist
## escribe una linea "INFO: ..." (o "INFORMACION: ..." segun el idioma de Windows)
## que no empieza por comillas y se salta.
static func parse_tasklist(output: String) -> Array:
	var rows: Array = []
	for raw in output.split("\n"):
		var line: String = str(raw).strip_edges()
		if not line.begins_with("\""):
			continue
		var fields := line.trim_prefix("\"").trim_suffix("\"").split("\",\"")
		if fields.size() < 2 or not fields[1].is_valid_int():
			continue
		rows.append({"image": fields[0], "pid": int(fields[1])})
	return rows

## Si en la salida de tasklist esta `pid` y es `exe` (sin mirar mayusculas). Sin
## `exe` (un bloqueo raro) basta el PID.
static func tasklist_has(output: String, pid: int, exe: String) -> bool:
	for row in parse_tasklist(output):
		if int(row["pid"]) != pid:
			continue
		return exe == "" or str(row["image"]).to_lower() == exe.to_lower()
	return false

# ── Parte con el sistema ────────────────────────────────────────────

static func applies_here() -> bool:
	var features: Array = []
	for tag in ["editor", "mobile", "web"]:
		if OS.has_feature(tag):
			features.append(tag)
	return applies(features, DisplayServer.get_name(), Array(OS.get_cmdline_user_args()))

static func my_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))

static func my_exe() -> String:
	return OS.get_executable_path().get_file()

static func read_lock() -> Dictionary:
	if not FileAccess.file_exists(LOCK_PATH):
		return {}
	var f := FileAccess.open(LOCK_PATH, FileAccess.READ)
	if f == null:
		return {}
	return parse_lock(f.get_as_text())

## Se queda el bloqueo para este proceso.
static func write_lock() -> void:
	var f := FileAccess.open(LOCK_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[InstanceGuard] no se pudo escribir %s" % LOCK_PATH)
		return
	f.store_string(lock_text(OS.get_process_id(), my_version(), my_exe(), Time.get_datetime_string_from_system()))

## Borra el bloqueo si es de este proceso (el de otro no se toca).
static func release() -> void:
	var lock := read_lock()
	if lock.is_empty() or int(lock.get("pid", 0)) != OS.get_process_id():
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LOCK_PATH))

## Si `pid` esta vivo y es `exe`.
static func is_game_alive(pid: int, exe: String) -> bool:
	if pid <= 0:
		return false
	if OS.get_name() == "Windows":
		var out: Array = []
		var code := OS.execute("tasklist", ["/FI", "PID eq %d" % pid, "/FO", "CSV", "/NH"], out)
		if code != 0 or out.is_empty():
			return false
		return tasklist_has(str(out[0]), pid, exe)
	# Linux / macOS: ps da el nombre del proceso; sin salida, no existe.
	var ps_out: Array = []
	if OS.execute("ps", ["-p", str(pid), "-o", "comm="], ps_out) != 0 or ps_out.is_empty():
		return false
	var comm := str(ps_out[0]).strip_edges()
	return comm != "" and (exe == "" or comm.get_file().to_lower() == exe.to_lower())

## Otras copias del mismo ejecutable (solo Windows): las versiones de antes del
## bloqueo no escriben archivo, pero se llaman igual.
static func stray_pids() -> Array:
	if OS.get_name() != "Windows":
		return []
	var exe := my_exe()
	if exe == "":
		return []
	var out: Array = []
	if OS.execute("tasklist", ["/FI", "IMAGENAME eq %s" % exe, "/FO", "CSV", "/NH"], out) != 0 or out.is_empty():
		return []
	var pids: Array = []
	for row in parse_tasklist(str(out[0])):
		if int(row["pid"]) != OS.get_process_id():
			pids.append(int(row["pid"]))
	return pids

## Intenta traer al frente la ventana de `pid`, sin esperar y sin dependencias:
## el WScript.Shell de Windows (AppActivate acepta un PID). Si falla (ventana
## minimizada, Windows no deja robar el foco) solo parpadea en la barra de tareas.
static func focus_window(pid: int) -> void:
	if OS.get_name() != "Windows" or pid <= 0:
		return
	OS.create_process("powershell.exe", ["-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden",
		"-Command", "(New-Object -ComObject WScript.Shell).AppActivate(%d) | Out-Null" % pid])
