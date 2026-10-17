class_name ErrorLog
extends Logger
## Registro local de errores (docs/19 §7). Un archivo pequeno en el user dir,
## `user://logs/registro.txt`, que nunca sale del equipo: aqui no hay red.
##
## Por que uno propio y no solo el log de archivo de Godot
## (`debug/file_logging/*`): el de Godot viene apagado en Android, no tiene tope
## de tamano por archivo (una sesion que repite un error lo hace crecer sin
## fin) y escribe a su ritmo, sin que el juego pueda leer sus ultimas lineas al
## dia. Este se engancha con OS.add_logger(), asi que recibe lo mismo (print,
## push_error, errores de script y del motor) en PC y en Android.
##
## Rendimiento ("en una papa"): nada por fotograma. Cada linea va a dos listas
## en memoria (las ultimas para el informe, y las pendientes de escribir); el
## disco se toca en bloque cada FLUSH_SECONDS con un Timer, y al cerrar o al
## pasar a segundo plano. Una linea repetida seguida se cuenta, no se repite.
##
## Tope: MAX_BYTES por archivo y ROTATIONS copias viejas (registro.1.txt,
## registro.2.txt). Lo instala GameConfig._ready(), una vez por proceso.

const DIR := "user://logs"
const FILE_NAME := "registro.txt"
const MAX_BYTES := 200 * 1024
const ROTATIONS := 2
const FLUSH_SECONDS := 3.0
## Lineas que se guardan en memoria para el informe de fallo.
const RECENT_MAX := 80
## Tope de lineas sin escribir: un bucle que escupe errores no se come la RAM.
const PENDING_MAX := 600
## Del archivo de la sesion anterior se recuperan como mucho estos bytes del
## final (para que un cierre inesperado salga en el informe al volver a abrir).
const TAIL_BYTES := 8 * 1024

static var _instance: ErrorLog = null

var _mutex := Mutex.new()
var _recent: PackedStringArray = []
var _pending: PackedStringArray = []
var _dropped := 0
var _last := ""
var _repeats := 0
var _path := DIR + "/" + FILE_NAME

## Engancha el registro (una sola vez) y pone el Timer que lo vuelca.
static func install(host: Node) -> void:
	if _instance != null:
		return
	_instance = ErrorLog.new()
	_instance._load_previous_tail()
	_instance._add_line("=== %s · v%s · %s %s ===" % [
		Time.get_datetime_string_from_system(false, true),
		str(ProjectSettings.get_setting("application/config/version", "?")),
		OS.get_name(), OS.get_version()])
	OS.add_logger(_instance)
	if host != null:
		var flusher := Flusher.new()
		flusher.name = "ErrorLogFlusher"
		host.add_child(flusher)

static func instance() -> ErrorLog:
	return _instance

## Ruta del archivo (user://), para la documentacion y los tests.
static func file_path() -> String:
	return DIR + "/" + FILE_NAME

## Las ultimas `count` lineas (sesion anterior incluida si la actual es corta).
static func recent_lines(count: int = 40) -> PackedStringArray:
	if _instance == null:
		return PackedStringArray()
	return _instance._recent_copy(count)

## Escribe ya lo pendiente (el Flusher lo llama; tambien los tests).
static func flush_now() -> void:
	if _instance != null:
		_instance._flush()

## Anota una linea a mano (sin pasar por print). Para pruebas y avisos propios.
static func note(text: String) -> void:
	if _instance != null:
		_instance._add_line(text)

# ── Logger ───────────────────────────────────────────────────────────

func _log_message(message: String, error: bool) -> void:
	var text := message.strip_edges(false, true)
	if text.is_empty():
		return
	_add_line(("E " if error else "") + text)

func _log_error(function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
	# push_error y los errores de script vienen del motor (variant_utility.cpp):
	# lo util es el script que lo lanzo, el primer marco de la pila (si la hay;
	# en un exportado sin depuracion puede venir vacia).
	for bt in script_backtraces:
		if bt != null and bt.get_frame_count() > 0:
			file = bt.get_frame_file(0)
			line = bt.get_frame_line(0)
			function = bt.get_frame_function(0)
			break
	var kind := "ERROR"
	match error_type:
		Logger.ERROR_TYPE_WARNING:
			kind = "WARNING"
		Logger.ERROR_TYPE_SCRIPT:
			kind = "SCRIPT ERROR"
		Logger.ERROR_TYPE_SHADER:
			kind = "SHADER ERROR"
	var what := rationale if not rationale.is_empty() else code
	_add_line("%s: %s (%s:%d @ %s)" % [kind, what, file, line, function])

# ── Interno ──────────────────────────────────────────────────────────

func _add_line(text: String) -> void:
	_mutex.lock()
	if text == _last:
		_repeats += 1
		_mutex.unlock()
		return
	_close_repeats()
	_last = text
	_push("%s %s" % [Time.get_time_string_from_system(), text])
	_mutex.unlock()

## Con el mutex tomado.
func _close_repeats() -> void:
	if _repeats > 0:
		_push("  (x%d)" % (_repeats + 1))
		_repeats = 0

## Con el mutex tomado.
func _push(line: String) -> void:
	_recent.append(line)
	if _recent.size() > RECENT_MAX:
		_recent = _recent.slice(_recent.size() - RECENT_MAX)
	_pending.append(line)
	if _pending.size() > PENDING_MAX:
		_dropped += _pending.size() - PENDING_MAX
		_pending = _pending.slice(_pending.size() - PENDING_MAX)

func _recent_copy(count: int) -> PackedStringArray:
	_mutex.lock()
	var out := _recent.duplicate()
	if _repeats > 0:
		out.append("  (x%d)" % (_repeats + 1))
	_mutex.unlock()
	if out.size() > count:
		out = out.slice(out.size() - count)
	return out

## Vuelca lo pendiente en un solo bloque. Rota antes si no cabe.
func _flush() -> void:
	_mutex.lock()
	if _pending.is_empty():
		_mutex.unlock()
		return
	var block := ""
	if _dropped > 0:
		block += "  (%d lineas sin escribir: demasiadas seguidas)\n" % _dropped
		_dropped = 0
	block += "\n".join(_pending) + "\n"
	_pending.clear()
	_mutex.unlock()
	_write_block(block)

func _write_block(block: String) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var bytes := block.to_utf8_buffer()
	var size := 0
	if FileAccess.file_exists(_path):
		var probe := FileAccess.open(_path, FileAccess.READ)
		if probe != null:
			size = probe.get_length()
			probe.close()
	if size > 0 and size + bytes.size() > MAX_BYTES:
		_rotate()
		size = 0
	var f: FileAccess
	if size > 0:
		f = FileAccess.open(_path, FileAccess.READ_WRITE)
	else:
		f = FileAccess.open(_path, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_buffer(bytes)
	f.close()

## registro.txt -> registro.1.txt -> registro.2.txt; el mas viejo se tira.
func _rotate() -> void:
	var base := DIR + "/" + FILE_NAME.get_basename()
	var oldest := "%s.%d.txt" % [base, ROTATIONS]
	if FileAccess.file_exists(oldest):
		DirAccess.remove_absolute(oldest)
	for i in range(ROTATIONS - 1, 0, -1):
		var from := "%s.%d.txt" % [base, i]
		if FileAccess.file_exists(from):
			DirAccess.rename_absolute(from, "%s.%d.txt" % [base, i + 1])
	if FileAccess.file_exists(_path):
		DirAccess.rename_absolute(_path, "%s.1.txt" % base)

## Las ultimas lineas de la sesion anterior, solo en memoria (ya estan en disco).
func _load_previous_tail() -> void:
	if not FileAccess.file_exists(_path):
		return
	var f := FileAccess.open(_path, FileAccess.READ)
	if f == null:
		return
	var length := f.get_length()
	var start := maxi(0, length - TAIL_BYTES)
	f.seek(start)
	var text := f.get_buffer(length - start).get_string_from_utf8()
	f.close()
	var lines := text.split("\n", false)
	# La primera puede venir cortada por la mitad.
	if start > 0 and lines.size() > 0:
		lines.remove_at(0)
	var keep := lines.slice(maxi(0, lines.size() - RECENT_MAX / 2))
	_recent.append_array(keep)

## Vuelca el registro cada FLUSH_SECONDS, al cerrar y al pasar a segundo plano
## (movil). Sigue con el juego en pausa: un error con el menu abierto tambien
## tiene que llegar al disco.
class Flusher extends Node:
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		var timer := Timer.new()
		timer.wait_time = ErrorLog.FLUSH_SECONDS
		timer.autostart = true
		timer.timeout.connect(ErrorLog.flush_now)
		add_child(timer)

	func _notification(what: int) -> void:
		match what:
			NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED, \
					NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_EXIT_TREE, \
					NOTIFICATION_CRASH:
				ErrorLog.flush_now()
