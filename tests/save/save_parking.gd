extends RefCounted
## Aparta las partidas de verdad mientras una suite escribe guardados, y las
## devuelve despues: la carpeta user://partidas/ entera (cada partida y su
## indice, docs/09), la partida activa de GameConfig (settings.cfg [partidas]) y
## el user://save_game.json de antes de las partidas, si quedara alguno.
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
const SLOTS_DIR := "user://partidas"
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
	if FileAccess.file_exists(SAVE_PATH):
		if DirAccess.rename_absolute(SAVE_PATH, backup_path) != OK:
			if DirAccess.copy_absolute(SAVE_PATH, backup_path) == OK:
				DirAccess.remove_absolute(SAVE_PATH)
	_park_slots(backup_path)
	return true

static func restore(backup_path: String, user_dir: String = OS.get_user_data_dir()) -> void:
	if is_player_dir(user_dir):
		return
	_restore_slots(backup_path)
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

# ── user://partidas y la partida activa ──────────────────────────────

static func slots_backup_dir(backup_path: String) -> String:
	return backup_path + ".partidas"

static func _active_backup(backup_path: String) -> String:
	return backup_path + ".activa"

static func _park_slots(backup_path: String) -> void:
	var backup_dir := slots_backup_dir(backup_path)
	var active_file := _active_backup(backup_path)
	if DirAccess.dir_exists_absolute(backup_dir):
		# Varada: lo de ahora es de la suite que murio; la copia aparcada es lo
		# de verdad y vuelve a su sitio antes que nada.
		_remove_dir(SLOTS_DIR)
		DirAccess.rename_absolute(backup_dir, SLOTS_DIR)
	if FileAccess.file_exists(active_file):
		GameConfig.saves_active_slot = int(FileAccess.get_file_as_string(active_file))
	if DirAccess.dir_exists_absolute(SLOTS_DIR):
		if DirAccess.rename_absolute(SLOTS_DIR, backup_dir) != OK:
			if _copy_dir(SLOTS_DIR, backup_dir):
				_remove_dir(SLOTS_DIR)
	var f := FileAccess.open(active_file, FileAccess.WRITE)
	if f:
		f.store_string(str(GameConfig.saves_active_slot))
		f.close()

static func _restore_slots(backup_path: String) -> void:
	var backup_dir := slots_backup_dir(backup_path)
	var active_file := _active_backup(backup_path)
	# Lo que haya ahora en user://partidas es de la suite.
	_remove_dir(SLOTS_DIR)
	if DirAccess.dir_exists_absolute(backup_dir):
		if DirAccess.rename_absolute(backup_dir, SLOTS_DIR) != OK:
			if _copy_dir(backup_dir, SLOTS_DIR):
				_remove_dir(backup_dir)
	if FileAccess.file_exists(active_file):
		GameConfig.saves_active_slot = int(FileAccess.get_file_as_string(active_file))
		DirAccess.remove_absolute(active_file)

static func _remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for f in dir.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for d in dir.get_directories():
		_remove_dir(path.path_join(d))
	DirAccess.remove_absolute(path)

static func _copy_dir(from: String, to: String) -> bool:
	var dir := DirAccess.open(from)
	if dir == null:
		return false
	DirAccess.make_dir_recursive_absolute(to)
	for f in dir.get_files():
		if DirAccess.copy_absolute(from.path_join(f), to.path_join(f)) != OK:
			return false
	return true
