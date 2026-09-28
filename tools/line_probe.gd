extends SceneTree
## Sonda de la linea jugable: juega la campana entera con TIEMPOS REALES (sin
## dev_mode), de la primera obra a la victoria, con un "jugador razonable" que
## sigue el camino que recomiendan los objetivos. Mide cuanto tarda cada hito,
## cuanto se espera sin nada que hacer, que cuesta cada Tormenta y si el asedio se
## gana. Tablas en docs/22-linea-jugable.md.
##
## Uso (SIEMPRE con un override.cfg de carpeta de usuario propia: la sonda borra
## y escribe user://save_game.json, y se niega a correr sobre la del jugador):
##
##   override.cfg en la raiz del proyecto, temporal y sin commitear:
##     [application]
##     config/use_custom_user_dir=true
##     config/custom_user_dir_name="TI_linea"
##
##   godot --headless --path . -s tools/line_probe.gd -- --no-dev --seeds=1,2,3,4,5
##
## Argumentos (opcionales):
##   --seeds=a,b,c   semillas del mapa (1..5 por defecto)
##   --hours=N       tope de horas de juego por partida (8)
##   --active=1      el jugador tambien exprime los procesos manuales
##   --log=1         imprime cada accion del jugador
##
## El jugador vive en tools/line_probe_player.gd: este script de arranque no puede
## nombrar autoloads (se compila antes de que existan), aquel si.

func _initialize() -> void:
	var user_dir: String = OS.get_user_data_dir()
	if not bool(ProjectSettings.get_setting("application/config/use_custom_user_dir", false)):
		push_error("line_probe: la carpeta de usuario es '%s', la del jugador. Hace falta un override.cfg con use_custom_user_dir=true: la sonda escribe partidas." % user_dir)
		quit(2)
		return
	var args: Dictionary = _parse_args()
	var player_script: GDScript = load("res://tools/line_probe_player.gd")
	var player: Node = player_script.new()
	player.name = "LineProbePlayer"
	player.options = args
	root.add_child(player)
	player.finished.connect(func(code: int) -> void: quit(code))
	player.run.call_deferred()

func _parse_args() -> Dictionary:
	var out := {"seeds": [1, 2, 3, 4, 5], "hours": 8.0, "active": false, "log": false}
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--") or not arg.contains("="):
			continue
		var key: String = arg.substr(2, arg.find("=") - 2)
		var value: String = arg.substr(arg.find("=") + 1)
		match key:
			"seeds":
				var seeds: Array = []
				for part in value.split(","):
					if part.strip_edges() != "":
						seeds.append(int(part))
				out["seeds"] = seeds
			"hours":
				out["hours"] = float(value)
			"active":
				out["active"] = value == "1"
			"log":
				out["log"] = value == "1"
			_:
				out[key] = value
	return out
