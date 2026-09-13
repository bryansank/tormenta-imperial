extends Node
## Dev tool: abre el tablero de combate con un ejercito sembrado y lo fotografia.
## Sirve para revisar la pantalla de batalla sin tener que jugar hasta el Cuartel.
##
## Uso: registrar temporalmente como autoload y arrancar el juego CON ventana.
##   project.godot -> [autoload] -> BattleProbe="*res://tools/battle_probe.gd"
## Salida: res://docs/media/dev/*.png
## Quitar la linea del autoload al terminar.
##
## Hermano de tools/showcase_shots.gd y tools/ui_tour.gd.

const OUT_DIR := "res://docs/media/dev"
const SETTLE := 2.0
const STEP := 0.6

func _ready() -> void:
	if not GameConfig.dev_mode:
		push_warning("[battle] dev_mode desactivado; no se hace nada")
		return
	await get_tree().create_timer(SETTLE).timeout
	await _run()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var main := get_tree().current_scene
	if main == null:
		push_warning("[battle] no hay escena actual")
		return

	_seed()
	await get_tree().create_timer(1.0).timeout

	# 1. El panel de escaramuzas, con la seleccion de tropas.
	var skirmish: Node = main.get_node_or_null("SkirmishPanel")
	if skirmish != null and skirmish.has_method("_open"):
		skirmish._open()
		skirmish._selection = {"infantry": 3, "artillery": 1}
		skirmish._refresh()
		await _shot("battle_00_skirmish")
		skirmish._close()

	# 2. El tablero recien desplegado.
	CombatManager.start_skirmish({"infantry": 3, "artillery": 1})
	await _shot("battle_01_board")

	# 3. Una unidad movida, para ver las celdas validas y el rastro.
	var active: CombatUnit = CombatManager.get_active_unit()
	if active != null:
		var moves: Array = CombatManager.get_valid_moves(active.uid)
		if not moves.is_empty():
			CombatManager.move_unit(active.uid, moves[moves.size() - 1])
			await _shot("battle_02_moved")

	# 4. Unas rondas corriendo solas, para ver la IA y los numeros de dano.
	for i in range(6):
		await get_tree().create_timer(STEP).timeout
		if not CombatManager.is_in_encounter():
			break
		await _play_one_turn(STEP * 0.5)
	await _shot("battle_03_midfight")

	# 5. Pelear hasta el final y comprobar que el resultado llega a la base.
	#    Esto es lo que verifica que el combate no es un simulador suelto.
	# A ritmo de fotograma: aqui no interesa verlo, interesa que termine.
	# El margen es alto a proposito: la IA espera entre accion y accion, asi que
	# muchas de estas vueltas se van solo en esperar al enemigo.
	# La IA espera entre accion y accion para que se vea; aqui no se mira nadie y
	# esa pausa convierte una pelea de 20 rondas en minutos. Se anula.
	GameConfig.combat_ai_step_delay = 0.0
	var before := _snapshot()
	var guard := 0
	print("[battle] peleando hasta el final...")
	while CombatManager.is_in_encounter() and guard < 6000:
		guard += 1
		await _play_one_turn(0.0)
	if CombatManager.is_in_encounter():
		print("[battle] AVISO: la pelea no termino en %d vueltas (ronda %d)" % [guard, CombatManager.get_round()])
	else:
		print("[battle] pelea resuelta en %d vueltas" % guard)
	await _shot("battle_04_result")

	var after := _snapshot()
	var result: Dictionary = CombatManager.get_last_result()
	print("[battle] --- consecuencias ---")
	print("[battle] resultado: %s" % result)
	print("[battle] oro   %d -> %d" % [before["gold"], after["gold"]])
	print("[battle] madera %d -> %d" % [before["wood"], after["wood"]])
	print("[battle] tropas %d -> %d" % [before["units"], after["units"]])
	print("[battle] poder  %d -> %d" % [before["power"], after["power"]])
	print("[battle] moral  %d -> %d" % [before["morale"], after["morale"]])
	get_tree().quit()

## Juega el turno activo: ataca si puede, si no se acerca y pasa. El turno
## enemigo lo lleva la IA sola, asi que aqui solo hay que esperarlo.
## `pausa` a 0 corre a ritmo de fotograma, para terminar la pelea rapido.
func _play_one_turn(pausa: float) -> void:
	if pausa > 0.0:
		await get_tree().create_timer(pausa).timeout
	else:
		await get_tree().process_frame
	if not CombatManager.is_player_turn():
		return
	var unit: CombatUnit = CombatManager.get_active_unit()
	if unit == null:
		return
	var targets: Array = CombatManager.get_valid_targets(unit.uid)
	if not targets.is_empty():
		CombatManager.attack(unit.uid, targets[0])
		return
	var cells: Array = CombatManager.get_valid_moves(unit.uid)
	if not cells.is_empty():
		CombatManager.move_unit(unit.uid, cells[0])
	CombatManager.end_turn()

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
	ResourceManager.set_unlock_state({"gold": true, "wood": true, "steel": true, "oil": false})
	ResourceManager.set_amounts({"gold": 2400, "wood": 1100, "steel": 600, "oil": 0})
	ProgressionManager.current_era = 2
	# La fase importa: PopulationManager ignora cualquier cambio de moral antes de
	# Phase.ECONOMY. En partida real, tener Cuartel implica Aserradero y Fundicion,
	# asi que ya se esta en EXPANSION; sembrando a mano hay que ponerlo a mano o la
	# moral del combate se descarta en silencio y parece un bug que no existe.
	ProgressionManager.current_phase = GameConfig.Phase.EXPANSION
	PopulationManager._population = 26
	PopulationManager._max_population = 32
	PopulationManager._morale = 84
	ArmyManager._units = {"infantry": 6, "artillery": 3}
	# El boton lateral depende de que haya un Cuartel construido de verdad; aqui
	# se abre el panel a mano, asi que no hace falta plantarlo.
	EventBus.army_changed.emit()
	EventBus.sidebar_toggled.emit(true)

func _shot(file_name: String) -> void:
	await get_tree().create_timer(STEP).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png("%s/%s.png" % [OUT_DIR, file_name])
	print("[battle] %s.png (err %d)" % [file_name, err])
