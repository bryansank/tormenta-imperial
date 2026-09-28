extends RefCounted
## Que vista del mapa se usa (3D o 2D) y como se cambia.
##
## La preferencia es GameConfig.ui_view_mode, guardada en user://settings.cfg.
## Para desarrollar, `--view=2d` (o `--view=3d`) tras `--` en la linea de
## comandos manda sobre ella en esa sesion sin tocar el fichero:
##
##     godot --path . -- --view=2d
##
## Cambiar de vista desde Ajustes guarda la preferencia y llama a
## GameManager.switch_to_scene(): se guarda la partida y se abre la otra escena,
## que carga el mismo save_game.json.

const MODE_3D := "3d"
const MODE_2D := "2d"
const SCENE_3D := "res://scenes/main/Main.tscn"
const SCENE_2D := "res://scenes/main/Main2D.tscn"

static var _cmdline_read := false
static var _session_override := ""

## `--view=2d` / `--view=3d` entre los argumentos de usuario, o "" si no hay.
static func parse_cmdline(args: PackedStringArray) -> String:
	for a in args:
		if a.begins_with("--view="):
			var v := normalize(a.substr(7))
			if v != "":
				return v
	return ""

## "2d"/"3d" (sin distinguir mayusculas), o "" si no es ninguna.
static func normalize(mode: String) -> String:
	var m := mode.strip_edges().to_lower()
	return m if m in [MODE_3D, MODE_2D] else ""

## La vista que toca ahora: la de la linea de comandos (solo la primera vez que
## se pregunta en la sesion, hasta que el jugador elija otra) o la preferencia.
static func requested() -> String:
	if not _cmdline_read:
		_cmdline_read = true
		_session_override = parse_cmdline(OS.get_cmdline_user_args())
	if _session_override != "":
		return _session_override
	var pref := normalize(GameConfig.ui_view_mode)
	return pref if pref != "" else MODE_3D

static func scene_for(mode: String) -> String:
	return SCENE_2D if normalize(mode) == MODE_2D else SCENE_3D

## La vista de la escena que esta corriendo, o "" si no es ninguna de las dos.
static func current(tree: SceneTree) -> String:
	var scene := tree.current_scene if tree else null
	if scene == null:
		return ""
	if scene.scene_file_path == SCENE_2D:
		return MODE_2D
	if scene.scene_file_path == SCENE_3D:
		return MODE_3D
	return ""

## Guarda la preferencia (sin cambiar de escena). Tambien anula el `--view` de
## la linea de comandos para el resto de la sesion: el jugador ya eligio.
static func set_preference(mode: String) -> void:
	var m := normalize(mode)
	if m == "":
		return
	_cmdline_read = true
	_session_override = ""
	GameConfig.ui_view_mode = m
	GameConfig.save_user_settings()

## Elige vista y, si no es la que corre, se cambia a ella sin perder la partida.
static func switch_to(mode: String, tree: SceneTree) -> void:
	set_preference(mode)
	var m := normalize(mode)
	if m == "" or current(tree) == m:
		return
	GameManager.switch_to_scene(scene_for(m))
