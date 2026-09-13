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
		if CombatManager.is_player_turn():
			var unit: CombatUnit = CombatManager.get_active_unit()
			if unit == null:
				continue
			var targets: Array = CombatManager.get_valid_targets(unit.uid)
			if not targets.is_empty():
				CombatManager.attack(unit.uid, targets[0])
			else:
				var cells: Array = CombatManager.get_valid_moves(unit.uid)
				if not cells.is_empty():
					CombatManager.move_unit(unit.uid, cells[0])
				CombatManager.end_turn()
	await _shot("battle_03_midfight")

	print("[battle] capturas en %s | estado %d | ronda %d" % [
		OUT_DIR, CombatManager.get_state(), CombatManager.get_round()
	])
	get_tree().quit()

## Un Cuartel, tropas entrenadas y moral alta: lo minimo para que el boton de
## escaramuzas exista y el combate tenga con que pelear.
func _seed() -> void:
	ResourceManager.set_unlock_state({"gold": true, "wood": true, "steel": true, "oil": false})
	ResourceManager.set_amounts({"gold": 2400, "wood": 1100, "steel": 600, "oil": 0})
	ProgressionManager.current_era = 2
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
