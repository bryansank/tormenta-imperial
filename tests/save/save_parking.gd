extends RefCounted
## Aparta la partida de verdad del jugador mientras una suite escribe en
## user://save_game.json, y la devuelve despues.
##
## Mas desconfiada que un rename y un remove: si al aparcar ya existe una copia
## aparcada, esa copia es una partida real que otra ejecucion dejo varada (una
## suite que murio antes de devolverla), y borrarla seria perderla. Se devuelve
## primero y solo entonces se aparca. Y si el rename falla, se copia.
##
## Y ante todo, no opera en la carpeta del jugador. Los tests se lanzan con
## tools/run_tests.sh (o .ps1), que les da una carpeta de usuario propia; si
## alguien los lanza a pelo, user:// es la carpeta donde vive la partida de
## verdad, y dos suites a la vez aparcando y devolviendo se la pisan. Entonces
## park() avisa, no mueve ni borra nada y devuelve false; restore() tampoco toca
## nada. Las suites que aparcan se saltan enteras en ese caso (ver skip_reason
## en su before()).

const SAVE_PATH := "user://save_game.json"
const SKIP_REASON := "Carpeta de usuario del jugador: lanza los tests con tools/run_tests.sh"

## Las carpetas donde vive la partida del jugador: la del editor (F5) y la del
## juego exportado (application/config/custom_user_dir_name.template).
static func player_dirs() -> PackedStringArray:
	var data := OS.get_data_dir()
	var name := str(ProjectSettings.get_setting("application/config/name", "Tormenta Imperial"))
	var exported := str(ProjectSettings.get_setting(
			"application/config/custom_user_dir_name.template", "TormentaImperial"))
	return PackedStringArray([
		data.path_join("Godot/app_userdata").path_join(name),
		data.path_join(exported),
	])

static func _norm(path: String) -> String:
	return path.replace("\\", "/").simplify_path().trim_suffix("/").to_lower()

static func is_player_dir(user_dir: String) -> bool:
	var target := _norm(user_dir)
	for dir in player_dirs():
		if _norm(dir) == target:
			return true
	return false

## true si esta ejecucion corre en la carpeta del jugador (para do_skip).
static func in_player_dir() -> bool:
	return is_player_dir(OS.get_user_data_dir())

## Aparta la partida. Devuelve false, sin tocar nada, en la carpeta del jugador.
static func park(backup_path: String, user_dir: String = OS.get_user_data_dir()) -> bool:
	if is_player_dir(user_dir):
		push_warning("save_parking: user:// es la carpeta del jugador (%s); no se aparca nada. %s" % [user_dir, SKIP_REASON])
		return false
	if FileAccess.file_exists(backup_path):
		# Varada de una ejecucion anterior: vuelve a su sitio antes que nada.
		if FileAccess.file_exists(SAVE_PATH):
			DirAccess.remove_absolute(SAVE_PATH)
		DirAccess.rename_absolute(backup_path, SAVE_PATH)
	if not FileAccess.file_exists(SAVE_PATH):
		return true
	if DirAccess.rename_absolute(SAVE_PATH, backup_path) != OK:
		if DirAccess.copy_absolute(SAVE_PATH, backup_path) == OK:
			DirAccess.remove_absolute(SAVE_PATH)
	return true

static func restore(backup_path: String, user_dir: String = OS.get_user_data_dir()) -> void:
	if is_player_dir(user_dir):
		return
	if not FileAccess.file_exists(backup_path):
		# No habia partida que apartar: lo que haya ahora es de la suite.
		if FileAccess.file_exists(SAVE_PATH):
			DirAccess.remove_absolute(SAVE_PATH)
		return
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	if DirAccess.rename_absolute(backup_path, SAVE_PATH) != OK:
		if DirAccess.copy_absolute(backup_path, SAVE_PATH) == OK:
			DirAccess.remove_absolute(backup_path)
