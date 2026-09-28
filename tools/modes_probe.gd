extends Node
## Dev tool: capturas de los modos de juego tal como los ve el jugador. Los
## tests dicen que las reglas van; esto dice que el selector se lee y que cada
## modo, un minuto dentro, se ve como debe (en 3D y en 2D).
##
## Uso: con una carpeta de usuario PROPIA (override.cfg con
## config/use_custom_user_dir=true: nunca contra la partida del jugador),
## registrar temporalmente como autoload y arrancar CON ventana:
##   override.cfg -> [autoload] ModesProbe="*res://tools/modes_probe.gd"
##   godot --path . --resolution 1280x720 -- --no-title --shot=<png> --picker
##   godot --path . --resolution 1280x720 -- --no-title --shot=<png> --mode=sandbox [--view=2d]
## `--picker` fotografia el selector de "Nueva partida" (y su confirmacion en
## <png>_confirm.png). `--mode=<clave>` empieza una partida nueva en ese modo,
## deja correr un minuto de juego (a x4) y fotografia. Sale al terminar.

const SETTLE := 2.0
## Un minuto de juego en quince segundos reales.
const GAME_SECONDS := 60.0
const SPEED := 4.0

var _args: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		var parts: PackedStringArray = String(arg).trim_prefix("--").split("=", true, 1)
		_args[parts[0]] = parts[1] if parts.size() > 1 else "true"
	if not _args.has("shot"):
		print("[modes] sin --shot=<png>: no hago nada")
		return
	await get_tree().create_timer(SETTLE).timeout
	if _args.has("picker"):
		await _picker()
	elif _args.has("mode"):
		await _mode(GameMode.from_key(String(_args["mode"])))
	get_tree().quit()

func _picker() -> void:
	var dialog: CanvasLayer = GameManager.request_new_game(true)
	await _frames(6)
	await _shot(String(_args["shot"]))
	dialog.mode_card(GameMode.Mode.SURVIVAL).pressed.emit()
	dialog._on_start()
	await _frames(6)
	await _shot(String(_args["shot"]).replace(".png", "_confirm.png"))
	dialog.cancel()

func _mode(mode: int) -> void:
	GameManager.start_new_game(mode)
	await get_tree().create_timer(SETTLE).timeout
	var panel: Node = get_tree().current_scene.get_node_or_null("TutorialPanel")
	if panel != null and panel.is_intro_open():
		panel._close()
	Engine.time_scale = SPEED
	await get_tree().create_timer(GAME_SECONDS, true, false, false).timeout
	Engine.time_scale = 1.0
	if mode == GameMode.Mode.SANDBOX:
		var tools: Node = get_tree().current_scene.get_node_or_null("SandboxPanel")
		if tools != null:
			StormManager.invoke_storm()
			tools.open()
	await _frames(10)
	print("[modes] %s: era=%d fase=%d tormenta_armada=%s oro=%d" % [
		GameMode.current_key(), ProgressionManager.current_era, StormManager.get_phase(),
		StormManager.is_armed(), ResourceManager.get_amount(ResourceManager.Type.GOLD)])
	await _shot(String(_args["shot"]))
	# El modo en el menu de pausa.
	if _args.has("pause"):
		var pause: Node = get_tree().current_scene.get_node_or_null("PauseMenu")
		if pause != null:
			pause.open_pause()
			await _frames(6)
			await _shot(String(_args["shot"]).replace(".png", "_pause.png"))
			pause.resume()
	# Supervivencia: perder la unica Auditoria es el final. Se fuerza la
	# derrota (sin jugar el asedio) para ver la pantalla.
	if _args.has("defeat"):
		ProgressionManager.summon_final_audit()
		ProgressionManager._publish_audit([{"e": "final_audit_lost", "wave": 1}])
		await get_tree().create_timer(1.0).timeout
		await _shot(String(_args["shot"]).replace(".png", "_defeat.png"))

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("[modes] captura %s -> %s" % [path, error_string(err)])
