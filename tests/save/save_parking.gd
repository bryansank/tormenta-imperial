extends RefCounted
## Aparta la partida de verdad del jugador mientras una suite escribe en
## user://save_game.json, y la devuelve despues.
##
## Mas desconfiada que un rename y un remove: si al aparcar ya existe una copia
## aparcada, esa copia es una partida real que otra ejecucion dejo varada (una
## suite que murio antes de devolverla), y borrarla seria perderla. Se devuelve
## primero y solo entonces se aparca. Y si el rename falla, se copia.

const SAVE_PATH := "user://save_game.json"

static func park(backup_path: String) -> void:
	if FileAccess.file_exists(backup_path):
		# Varada de una ejecucion anterior: vuelve a su sitio antes que nada.
		if FileAccess.file_exists(SAVE_PATH):
			DirAccess.remove_absolute(SAVE_PATH)
		DirAccess.rename_absolute(backup_path, SAVE_PATH)
	if not FileAccess.file_exists(SAVE_PATH):
		return
	if DirAccess.rename_absolute(SAVE_PATH, backup_path) != OK:
		if DirAccess.copy_absolute(SAVE_PATH, backup_path) == OK:
			DirAccess.remove_absolute(SAVE_PATH)

static func restore(backup_path: String) -> void:
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
