extends SceneTree
## Sonda de rendimiento (docs/26-rendimiento.md). Monta un escenario fijo por
## semilla, lo calienta, lo mide N segundos y deja tabla, JSON y CSV en
## reports/perf/ (git-ignored). El trabajo lo hace tools/perf_probe_runner.gd:
## este lanzador no puede nombrar autoloads (se compila antes de que existan).
##
## CON VENTANA (headless no pinta: no habria draw calls ni GPU que medir) y
## SIEMPRE con un override.cfg de carpeta de usuario propia: la sonda escribe
## user://save_game.json y se niega a correr sobre la del jugador.
##
##   override.cfg en la raiz del proyecto, temporal y sin commitear:
##     [application]
##     config/use_custom_user_dir=true
##     config/custom_user_dir_name="TI_rendimiento"
##
##   godot --path . -s tools/perf_probe.gd -- --scenario=grande --seconds=15
##   godot --path . --rendering-method mobile -s tools/perf_probe.gd -- --scenario=all
##   godot --path . --rendering-method gl_compatibility -s tools/perf_probe.gd -- --scenario=all --quality=low
##
## Argumentos (tras `--`, todos opcionales):
##   --scenario=   inicio | media | grande | tormenta | combate | grande_2d | all  (grande)
##                 `all` lanza un proceso hijo por escenario con los mismos argumentos
##   --seconds=N   segundos medidos (15)
##   --warmup=N    segundos de calentamiento antes de medir (6)
##   --quality=    auto | high | low | minima  (auto). `minima` es la propuesta de
##                 docs/26 emulada por la sonda: baja + sin sombras, glow ni humo,
##                 scaling_3d 0.6 y pocos caminantes. No es un ajuste del juego.
##                 `minimal` es la Minima de verdad del juego (Ajustes, WorldLook +
##                 GraphicsQuality.apply_runtime), la que pone la deteccion.
##   --view=       3d | 2d (3d; grande_2d fuerza 2d)
##   --size=WxH    tamano de ventana (1280x720)
##   --seed=N      semilla del mapa y de los yacimientos sueltos (1)
##   --vsync=1     mide con vsync (por defecto sin vsync ni tope de FPS)
##   --profile=N   segundos de perfil por script tras la medida (4; 0 lo apaga)
##   --tag=texto   prefijo de los ficheros de salida (por defecto renderer_calidad)
##   --shot=0      no guarda la captura de control
##   --v12=on|off  lo que cuesta la 1.2 (on): dos amenazas de costa en la orilla
##                 y el barco del contrabandista atracado; los camiones van solos.
##                 off quita camiones, marcas y barco para comparar (docs/26).

const SCENARIOS := ["inicio", "media", "grande", "tormenta", "combate", "grande_2d"]

func _initialize() -> void:
	if not bool(ProjectSettings.get_setting("application/config/use_custom_user_dir", false)):
		push_error("perf_probe: la carpeta de usuario es '%s', la del jugador. Hace falta un override.cfg con use_custom_user_dir=true: la sonda escribe partidas." % OS.get_user_data_dir())
		quit(2)
		return
	var opts := parse_args(OS.get_cmdline_user_args())
	if str(opts["scenario"]) == "all":
		_run_all.call_deferred()
		return
	var runner: Node = load("res://tools/perf_probe_runner.gd").new()
	runner.name = "PerfProbe"
	runner.options = opts
	root.add_child.call_deferred(runner)

## Un proceso por escenario: cada uno arranca con los autoloads limpios, que es
## lo honrado (cargar una partida encima de otra deja estado de la anterior).
func _run_all() -> void:
	var exe := OS.get_executable_path()
	var engine_args: PackedStringArray = OS.get_cmdline_args()
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	var opts := parse_args(user_args)
	var failed := 0
	for scenario in SCENARIOS:
		var args := PackedStringArray()
		# `--path` y `--rendering-method` no siempre llegan en get_cmdline_args():
		# se ponen a mano con lo que corre este proceso.
		if not engine_args.has("--path"):
			args.append_array(["--path", ProjectSettings.globalize_path("res://").trim_suffix("/")])
		if not engine_args.has("--rendering-method"):
			args.append_array(["--rendering-method", RenderingServer.get_current_rendering_method()])
		if not engine_args.has("--rendering-driver"):
			args.append_array(["--rendering-driver", RenderingServer.get_current_rendering_driver_name()])
		args.append_array(engine_args)
		args.append("--")
		for a in user_args:
			if not a.begins_with("--scenario="):
				args.append(a)
		args.append("--scenario=" + scenario)
		print("perf_probe: --- ", scenario, " ---")
		# El hijo es el ejecutable con ventana: su salida no siempre llega por la
		# tuberia. Lo que cuenta queda en su JSON, que se lee al final.
		var output: Array = []
		var code := OS.execute(exe, args, output, true)
		if code != 0:
			failed += 1
			print("perf_probe: el escenario %s salio con codigo %d" % [scenario, code])
	_print_summary(opts)
	quit(1 if failed > 0 else 0)

## Tabla de los seis escenarios a partir de sus JSON.
func _print_summary(opts: Dictionary) -> void:
	var tag: String = opts["tag"]
	if tag == "":
		tag = "%s_%s" % [RenderingServer.get_current_rendering_method(), opts["quality"]]
	print("perf_probe: resumen %s" % tag)
	print("| escenario | fps | 1 % bajo | p99 ms | render CPU ms | resto CPU ms | GPU ms | draw calls | primitivas | nodos | est. MB | video MB | proceso MB |")
	print("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
	for scenario in SCENARIOS:
		var path := "res://reports/perf/%s_%s.json" % [tag, scenario]
		if not FileAccess.file_exists(path):
			print("| %s | (sin datos) |" % scenario)
			continue
		var r: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (r is Dictionary):
			continue
		var m: Dictionary = r["metrics"]
		print("| %s | %.0f | %.0f | %.1f | %.2f | %.2f | %.2f | %.0f | %.0f | %d | %.0f | %.0f | %.0f |" % [
			scenario, m["fps_mean"], m["fps_1pct_low"], m["frame_ms_p99"], m["render_cpu_ms"], m["cpu_other_ms"],
			m["render_gpu_ms"], m["draw_calls"], m["primitives_in_frame"], int(r["nodes"]), r["static_mem_mb"],
			r["video_mem_mb"], float(r["process_mem_mb"].get("working_set", -1.0))])

static func parse_args(user_args: PackedStringArray) -> Dictionary:
	var out := {
		"scenario": "grande", "seconds": 15.0, "warmup": 6.0, "quality": "auto",
		"view": "3d", "size": Vector2i(1280, 720), "seed": 1, "vsync": false,
		"profile": 4.0, "tag": "", "shot": true, "v12": "on",
	}
	for arg in user_args:
		if not arg.begins_with("--") or not arg.contains("="):
			continue
		var key: String = arg.substr(2, arg.find("=") - 2)
		var value: String = arg.substr(arg.find("=") + 1)
		match key:
			"scenario":
				out["scenario"] = value if value in SCENARIOS or value == "all" else "grande"
			"seconds", "warmup", "profile":
				out[key] = maxf(0.0, float(value))
			"quality":
				out["quality"] = value if value in ["auto", "high", "low", "minimal", "minima"] else "auto"
			"view":
				out["view"] = "2d" if value == "2d" else "3d"
			"size":
				var parts := value.to_lower().split("x")
				if parts.size() == 2:
					out["size"] = Vector2i(maxi(320, int(parts[0])), maxi(240, int(parts[1])))
			"seed":
				out["seed"] = int(value)
			"vsync":
				out["vsync"] = value == "1"
			"tag":
				out["tag"] = value
			"shot":
				out["shot"] = value != "0"
			"v12":
				out["v12"] = "off" if value in ["off", "0"] else "on"
	if out["scenario"] == "grande_2d":
		out["view"] = "2d"
	return out
