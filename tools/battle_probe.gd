extends Node
## Dev tool: abre el tablero de combate con un ejercito sembrado, juega una pelea
## entera y la fotografia (despliegue, movimiento, ataque, muerte, parte). Sirve
## para revisar la pantalla de batalla sin tener que jugar hasta el Cuartel.
##
## Uso: registrar temporalmente como autoload y arrancar el juego CON ventana y
## con un override.cfg propio (siembra una partida y la guarda).
##   project.godot -> [autoload] -> BattleProbe="*res://tools/battle_probe.gd"
##   godot --path . --resolution 1280x800 -- --no-title
##   godot --path . --resolution 1280x800 -- --no-title --profile=tablet --tag=tablet
##   godot --path . --resolution 1280x800 -- --no-title --board=2d --tag=2d
##   godot --path . --resolution 1280x800 -- --no-title --fps
## Salida: res://docs/media/dev/battle_<tag>_*.png (git-ignorado). Con --fps no
## hace capturas: mide fotogramas por segundo (sin vsync) con el mapa solo y con
## el tablero 3D abierto, en las calidades alta, baja y minima, y lo imprime.
## Quitar la linea del autoload al terminar.
##
## Argumentos tras `--`: --board=3d|2d (por defecto 3d), --profile=pc|tablet|phone,
## --tag=<nombre> (prefijo de las capturas), --quality=high|low|minimal, --fps.
##
## Hermano de tools/showcase_shots.gd y tools/ui_tour.gd.

const OUT_DIR := "res://docs/media/dev"
const SETTLE := 2.0
const STEP := 0.6
const FPS_SAMPLE := 3.0

var _tag := "pc"
var _style := "3d"
var _screen: Node = null
var _deaths := 0
var _shot_attack := false
var _shot_death := false
var _shot_shell := false
var _shot_targets := false

func _ready() -> void:
	if not GameConfig.dev_mode:
		push_warning("[battle] dev_mode desactivado; no se hace nada")
		return
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--tag="):
			_tag = a.substr(6)
		elif a.begins_with("--board="):
			_style = a.substr(8)
		elif a.begins_with("--profile="):
			DeviceProfile.set_profile_override(a.substr(10))
		elif a.begins_with("--quality="):
			GameConfig.ui_graphics_quality = a.substr(10)
			EventBus.graphics_quality_changed.emit(GameConfig.ui_graphics_quality)
	await get_tree().create_timer(SETTLE).timeout
	_quiet_onboarding()
	await get_tree().create_timer(0.3).timeout
	if args.has("--fps"):
		await _measure_fps()
	else:
		await _run()
	get_tree().quit()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var main := get_tree().current_scene
	if main == null:
		push_warning("[battle] no hay escena actual")
		return
	_screen = main.get_node_or_null("BattleScreen")
	_seed()
	await get_tree().create_timer(1.0).timeout

	# 1. El panel de escaramuzas, con la seleccion de tropas.
	var skirmish: Node = main.get_node_or_null("SkirmishPanel")
	if skirmish != null and skirmish.has_method("_open"):
		skirmish._open()
		skirmish._selection = {"infantry": 3, "artillery": 1}
		skirmish._refresh()
		await _shot("00_skirmish")
		skirmish._close()

	if _screen != null:
		_screen.force_board_style(_style)
		if DeviceProfile.current() != "pc":
			_screen.set_touch_mode(true)

	# 2. El despliegue: las piezas caen sobre la maqueta. Defensa en casa con un
	#    jefe y una dotacion de torre, para ver todas las marcas a la vez.
	_open_showcase_board()
	# En 3D la captura de un golpe o una caida se hace cuando la MAQUETA llega a
	# ese evento (va por detras de las senales); en 2D, al llegar la senal.
	if _board() != null:
		_board().event_played.connect(_on_board_event)
	else:
		EventBus.unit_attacked.connect(func(_a, _t, _d): _on_board_event({"e": "attack"}))
		EventBus.unit_died.connect(func(_u, _s): _on_board_event({"e": "die"}))
	await get_tree().create_timer(0.22).timeout
	await _shot("01_deploy", 0.0)
	await _until_idle()
	await _shot("02_board")

	# 3. Una unidad que se mueve: la ruta casilla a casilla, con saltitos.
	await _until_player_turn()
	var active: CombatUnit = CombatManager.get_active_unit()
	if active != null and CombatManager.is_player_turn():
		var moves: Array = CombatManager.get_valid_moves(active.uid)
		if not moves.is_empty():
			moves.sort_custom(func(a, b): return a.y < b.y)
			CombatManager.move_unit(active.uid, moves[0])
			await get_tree().create_timer(0.2).timeout
			await _shot("03_move", 0.0)
			await _until_idle()
			await _shot("03b_after_move")
			if _screen != null and DeviceProfile.current() != "pc":
				_screen._on_cell_pressed(CombatManager.get_unit(active.uid).position)
				await _shot("07_inspect", 0.1)

	# 4. La pelea, jugada por la sonda con la misma regla que un jugador sencillo:
	#    ataca si puede, si no avanza. Espera siempre a que la maqueta acabe.
	GameConfig.combat_ai_step_delay = 0.2
	var guard := 0
	print("[battle] peleando hasta el final...")
	var before := _snapshot()
	while CombatManager.is_in_encounter() and guard < 4000:
		guard += 1
		await _play_one_turn()
	await _until_idle()
	await get_tree().create_timer(0.4).timeout
	await _shot("06_result")
	var after := _snapshot()
	print("[battle] resultado: %s  (oro %d -> %d, tropas %d -> %d)" % [
		CombatManager.get_last_result(), before["gold"], after["gold"], before["units"], after["units"]])

func _open_showcase_board() -> void:
	var units: Array = []
	var uid := 900
	for id in ["infantry", "infantry", "artillery", "vehicle", "artillery"]:
		uid += 1
		units.append(CombatUnit.create(uid, id, Encounter.PLAYER))
	# La ultima es la dotacion de la torre (retaguardia, nido de sacos).
	CombatManager.start_encounter_with_units(units, {"infantry": 3, "artillery": 1, "vehicle": 1}, true, 2, true, [uid], 1.0)

func _on_board_event(ev: Dictionary) -> void:
	match String(ev.get("e", "")):
		"attack":
			if not _shot_attack:
				_shot_attack = true
				_delayed_shot("04_attack", 0.5)
			elif not _shot_shell and _is_artillery(int(ev.get("attacker", -1))):
				_shot_shell = true
				_delayed_shot("04b_shell", 0.42)
		"die":
			_deaths += 1
			if not _shot_death:
				_shot_death = true
				_delayed_shot("05_death_a", 0.08)
				_delayed_shot("05_death_b", 0.26)

func _is_artillery(uid: int) -> bool:
	var u: CombatUnit = CombatManager.get_unit(uid)
	return u != null and u.unit_id == "artillery"

func _delayed_shot(name_: String, wait: float) -> void:
	await get_tree().create_timer(wait).timeout
	await _shot(name_, 0.0)

func _board():
	if _screen == null or _screen.board3d() == null:
		return null
	return _screen.board3d().board

func _until_idle() -> void:
	var b = _board()
	var guard := 0
	while b != null and b.is_busy() and guard < 600:
		guard += 1
		await get_tree().process_frame

func _until_player_turn() -> void:
	var guard := 0
	while CombatManager.is_in_encounter() and not CombatManager.is_player_turn() and guard < 2000:
		guard += 1
		await get_tree().process_frame
	await _until_idle()

func _play_one_turn() -> void:
	await get_tree().process_frame
	await _until_idle()
	if not CombatManager.is_player_turn():
		return
	var unit: CombatUnit = CombatManager.get_active_unit()
	if unit == null:
		return
	var targets: Array = CombatManager.get_valid_targets(unit.uid)
	if not targets.is_empty():
		if not _shot_targets:
			# Las marcas de objetivo, antes de disparar.
			_shot_targets = true
			_screen._refresh()
			await _shot("02c_targets", 0.2)
			if not CombatManager.is_player_turn():
				return
		CombatManager.attack(unit.uid, targets[0])
		return
	var cells: Array = CombatManager.get_valid_moves(unit.uid)
	if not cells.is_empty():
		cells.sort_custom(func(a, b): return a.y < b.y)
		CombatManager.move_unit(unit.uid, cells[0])
		await _until_idle()
		var after: Array = CombatManager.get_valid_targets(unit.uid)
		if not after.is_empty() and CombatManager.is_player_turn():
			CombatManager.attack(unit.uid, after[0])
			return
	if CombatManager.is_player_turn():
		CombatManager.end_turn()

# ── FPS ──────────────────────────────────────────────────────────────

## Mapa solo contra tablero abierto, en cada calidad. Sin vsync ni tope, para
## que el numero sea el coste y no el refresco de la pantalla.
func _measure_fps() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var main := get_tree().current_scene
	_screen = main.get_node_or_null("BattleScreen") if main != null else null
	_seed()
	await get_tree().create_timer(1.0).timeout
	var renderer := RenderingServer.get_current_rendering_method()
	print("[fps] renderizador %s, ventana %s, GPU %s" % [renderer, get_viewport().get_visible_rect().size, RenderingServer.get_video_adapter_name()])
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	for q in ["high", "low", "minimal"]:
		GameConfig.ui_graphics_quality = q
		EventBus.graphics_quality_changed.emit(q)
		await get_tree().create_timer(0.8).timeout
		var map_s: Array = await _sample()
		for style in ["3d", "2d"]:
			_screen.force_board_style(style)
			_open_showcase_board()
			await get_tree().create_timer(1.2).timeout
			await _until_idle()
			var board_s: Array = await _sample()
			print("[fps] calidad %-8s  mapa %5.0f fps %5.2f ms GPU   tablero %s %5.0f fps %5.2f ms GPU" % [
				q, map_s[0], map_s[1], style, board_s[0], board_s[1]])
			_screen._close_all()
			CombatManager.end_encounter()
			await get_tree().create_timer(0.5).timeout
	GameConfig.ui_graphics_quality = "auto"

## [fps, ms de GPU por fotograma]. La GPU suma la ventana y, si esta abierto,
## el SubViewport del tablero 3D (lo que pagaria una grafica integrada).
func _sample() -> Array:
	var vps: Array = [get_viewport().get_viewport_rid()]
	if _screen != null and _screen.board3d() != null and _screen.board3d().is_visible_in_tree():
		var sub: SubViewport = _screen.board3d().viewport
		RenderingServer.viewport_set_measure_render_time(sub.get_viewport_rid(), true)
		vps.append(sub.get_viewport_rid())
	var frames := 0
	var gpu := 0.0
	var t0 := Time.get_ticks_usec()
	while float(Time.get_ticks_usec() - t0) < FPS_SAMPLE * 1000000.0:
		await get_tree().process_frame
		frames += 1
		for rid in vps:
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
	var fps := float(frames) / (float(Time.get_ticks_usec() - t0) / 1000000.0)
	return [fps, gpu / float(maxi(1, frames))]

# ── Utilidades ───────────────────────────────────────────────────────

## Sin prologo, guia rapida ni tutorial: tapan el tablero (y el prologo pausa).
func _quiet_onboarding() -> void:
	TutorialManager.intro_seen = true
	TutorialManager.mark_help_seen("quick_guide")
	if TutorialManager.is_guide_active():
		TutorialManager.skip_guide()
	for group in ["prologue_screen", "quick_guide"]:
		for n in get_tree().get_nodes_in_group(group):
			if n.has_method("is_open") and n.is_open():
				n.close()
	var offline: Variant = GameManager.get("_offline_canvas")
	if offline != null and is_instance_valid(offline):
		(offline as Node).queue_free()
		GameManager.set("_offline_canvas", null)
	get_tree().paused = false

func _snapshot() -> Dictionary:
	return {
		"gold": ResourceManager.get_amount(ResourceManager.Type.GOLD),
		"wood": ResourceManager.get_amount(ResourceManager.Type.WOOD),
		"units": ArmyManager.get_total_units(),
		"power": ArmyManager.get_power(),
		"morale": PopulationManager.get_morale(),
	}

## Un Cuartel, tropas entrenadas y moral alta: lo minimo para que el boton de
## escaramuzas exista y el combate tenga con que pelear.
func _seed() -> void:
	ResourceManager.set_unlock_state({"gold": true, "wood": true, "steel": true, "oil": true})
	ResourceManager.set_amounts({"gold": 2400, "wood": 1100, "steel": 600, "oil": 200})
	ProgressionManager.current_era = 3
	# La fase importa: PopulationManager ignora cualquier cambio de moral antes de
	# Phase.ECONOMY. En partida real, tener Cuartel implica Aserradero y Fundicion,
	# asi que ya se esta en EXPANSION; sembrando a mano hay que ponerlo a mano o la
	# moral del combate se descarta en silencio y parece un bug que no existe.
	ProgressionManager.current_phase = GameConfig.Phase.EXPANSION
	PopulationManager._population = 26
	PopulationManager._max_population = 32
	PopulationManager._morale = 84
	ArmyManager._units = {"infantry": 6, "artillery": 3, "vehicle": 2}
	EventBus.army_changed.emit()
	EventBus.sidebar_toggled.emit(true)

func _shot(file_name: String, wait := STEP) -> void:
	if wait > 0.0:
		await get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/battle_%s_%s.png" % [OUT_DIR, _tag, file_name]
	var err := image.save_png(path)
	print("[battle] %s (err %d)" % [path.get_file(), err])
