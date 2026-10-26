class_name BootTrace
extends RefCounted
## Marcas de tiempo del arranque, hasta que el menu principal responde.
##
## Es el registro con el que se midio donde se va el tiempo al abrir el juego
## (docs/19 §14). Apunta poco: los autoloads y los hijos de la escena principal
## al entrar al arbol y al estar listos (con SceneTree.node_added, sin tocar
## cada script), las etapas que marcan GameManager y la pantalla de carga, y los
## primeros fotogramas despues de abrir el menu (ahi salen los tirones de
## compilar shaders).
##
## No imprime nada salvo con `-- --boot-trace` (tambien en un .exe exportado) o
## en dev_mode: entonces escribe el desglose al log y a user://boot_trace.txt.
## Sin ventana (tests, --headless) ni se engancha.

const REPORT_PATH := "user://boot_trace.txt"
## Fotogramas que se miran despues de abrir el menu.
const WATCH_FRAMES := 90
## Pasado este tiempo sin terminar, se suelta igual (una carga rota no deja el
## gancho de node_added puesto para siempre).
const GIVE_UP_MS := 120000

static var _marks: Array = []          # [usec, texto]
static var _installed := false
static var _finished := false
static var _frames: Array = []         # ms entre fotogramas tras el menu
static var _frame_prev_usec := 0
static var _start_usec := 0

static func enabled() -> bool:
	if OS.get_cmdline_user_args().has("--boot-trace"):
		return true
	var gc: Node = Engine.get_main_loop().root.get_node_or_null("GameConfig") if Engine.get_main_loop() is SceneTree else null
	return gc != null and bool(gc.get("dev_mode"))

## Desde el primer autoload (Tr._init): el reloj del motor ya cuenta desde que
## arranco el proceso, asi que la primera marca dice cuanto tardo el motor.
static func install() -> void:
	if _installed:
		return
	_installed = true
	if DisplayServer.get_name() == "headless":
		_finished = true
		return
	_start_usec = Time.get_ticks_usec()
	mark("motor listo: primer script (Tr)")
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.node_added.connect(_on_node_added)

static func is_active() -> bool:
	return _installed and not _finished

static func mark(label: String) -> void:
	if _finished:
		return
	_marks.append([Time.get_ticks_usec(), label])

## Milisegundos desde que arranco el proceso.
static func now_ms() -> float:
	return Time.get_ticks_usec() / 1000.0

static func _on_node_added(node: Node) -> void:
	var tree := node.get_tree()
	if tree == null:
		return
	if (Time.get_ticks_usec() - _start_usec) / 1000 > GIVE_UP_MS:
		_unhook()
		return
	var parent := node.get_parent()
	if parent == tree.root:
		mark("entra " + String(node.name))
		node.ready.connect(mark.bind("listo " + String(node.name)), CONNECT_ONE_SHOT)
	elif parent != null and parent.get_parent() == tree.root and parent.scene_file_path.begins_with("res://scenes/main/"):
		# Los hijos directos de Main / Main2D: un panel por linea.
		node.ready.connect(mark.bind("  listo " + String(node.name)), CONNECT_ONE_SHOT)

static func _unhook() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.node_added.is_connected(_on_node_added):
		tree.node_added.disconnect(_on_node_added)

## El menu ya esta abierto (o la partida en marcha sin menu): se dejan de mirar
## nodos y se cuentan los fotogramas que siguen antes de escribir el desglose.
static func finish(label: String) -> void:
	if _finished or not _installed:
		return
	mark(label)
	_unhook()
	_finished = true
	_frame_prev_usec = Time.get_ticks_usec()
	RenderingServer.frame_post_draw.connect(_on_frame)

static func _on_frame() -> void:
	var now := Time.get_ticks_usec()
	_frames.append((now - _frame_prev_usec) / 1000.0)
	_frame_prev_usec = now
	if _frames.size() == 1:
		_marks.append([now, "primer fotograma pintado tras el menu"])
	if _frames.size() >= WATCH_FRAMES:
		RenderingServer.frame_post_draw.disconnect(_on_frame)
		if enabled():
			_report()

static func report_text() -> String:
	var lines: PackedStringArray = []
	lines.append("== Arranque de Tormenta Imperial (%s, %s, %s) ==" % [
		OS.get_name(), RenderingServer.get_current_rendering_method(),
		"exportado" if OS.has_feature("template") else "editor"])
	lines.append("   ms total |  +ms paso | etapa")
	var prev := 0
	for m: Array in _marks:
		var t: int = m[0]
		lines.append("%10.1f | %9.1f | %s" % [t / 1000.0, (t - prev) / 1000.0 if prev > 0 else 0.0, m[1]])
		prev = t
	if not _frames.is_empty():
		var worst := 0.0
		var slow := 0
		var total := 0.0
		for f: float in _frames:
			worst = maxf(worst, f)
			total += f
			if f > 50.0:
				slow += 1
		lines.append("fotogramas tras el menu: %d, media %.1f ms, peor %.1f ms, %d por encima de 50 ms" % [
			_frames.size(), total / _frames.size(), worst, slow])
		var first: PackedStringArray = []
		for i in range(mini(10, _frames.size())):
			first.append("%.0f" % _frames[i])
		lines.append("primeros 10 fotogramas (ms): " + ", ".join(first))
	return "\n".join(lines)

static func _report() -> void:
	var text := report_text()
	print(text)
	var f := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(text + "\n")
		f.close()
