extends Node
## Dev tool: convoca la Auditoria Final, juega el asedio entero sin tocar la
## interfaz y cuenta lo que pasa. Es la prueba de que **la partida puede
## terminar**: hasta este cableado, el HQ nivel 3 convocaba a la Regencia y
## nadie la hacia bajar.
##
## Uso: registrar temporalmente como autoload y arrancar el juego CON ventana.
##   project.godot -> [autoload] -> AuditProbe="*res://tools/audit_probe.gd"
## Quitar la linea al terminar.
##
## Con FORCE_SHORT_SIEGE el asedio es de una oleada, para ver el camino de la
## victoria (parar la Tormenta para siempre) sin depender de la suerte. Con
## false se juega el asedio real y, si se pierde, se ve el camino del Diezmo.
##
## Hermano de tools/storm_probe.gd y tools/battle_probe.gd.

const SETTLE := 2.0
const FORCE_SHORT_SIEGE := true

var _log: Array = []

func _ready() -> void:
	if not GameConfig.dev_mode:
		push_warning("[audit] dev_mode desactivado; no se hace nada")
		return
	await get_tree().create_timer(SETTLE).timeout
	await _run()

func _run() -> void:
	_seed()
	_listen()
	if FORCE_SHORT_SIEGE:
		GameConfig.final_audit_waves = Vector2i(1, 1)
	GameConfig.combat_ai_step_delay = 0.0

	print("[audit] antes: %s" % _snapshot())
	print("[audit] tormenta parada=%s armada=%s" % [StormManager.is_halted(), StormManager.is_armed()])

	# 1. El HQ nivel 3 convoca (aqui a mano: no hay que jugar dos horas).
	var summoned: bool = ProgressionManager.summon_final_audit()
	print("[audit] convocada=%s pendiente=%s" % [summoned, _audit_state()])

	# 2. El jugador pulsa QUE BAJEN.
	var began: bool = ProgressionManager.begin_final_audit()
	print("[audit] empieza=%s activa=%s" % [began, ProgressionManager.is_final_audit_active()])
	if not began:
		print("[audit] ERROR: el asedio no arranco")
		get_tree().quit()
		return

	# 3. Se juega hasta que el asedio se resuelva, oleada tras oleada.
	var guard := 0
	while ProgressionManager.is_final_audit_active() and guard < 20000:
		guard += 1
		var enc: Encounter = CombatManager.get_encounter()
		if enc != null and enc.is_resolved():
			# Lo que haria el jugador al cerrar el panel de resultado.
			CombatManager.end_encounter()
			await get_tree().process_frame
			continue
		if CombatManager.is_in_encounter():
			await _play_one_turn()
			continue
		await get_tree().process_frame

	print("[audit] --- resultado ---")
	print("[audit] vueltas=%d estado=%s" % [guard, _audit_state()])
	for line in _log:
		print("[audit] %s" % line)
	print("[audit] despues: %s" % _snapshot())
	print("[audit] tormenta parada=%s armada=%s ciclo_activo=%s" % [
		StormManager.is_halted(), StormManager.is_armed(), StormManager.is_cycle_active()])
	print("[audit] multiplicador produccion=%.2f" % GameConfig.event_production_multiplier)
	if not ProgressionManager.is_final_audit_active() and ProgressionManager.final_audit != null \
			and ProgressionManager.final_audit.is_lost():
		print("[audit] se puede reconvocar=%s" % ProgressionManager.can_resummon_final_audit())
	get_tree().quit()

## Era 3, base creible, ejercito al tope y dos torres: lo que tendria alguien
## que acaba de terminar el Cuartel General.
func _seed() -> void:
	ResourceManager.set_unlock_state({"gold": true, "wood": true, "steel": true, "oil": true})
	ResourceManager.set_amounts({"gold": 2500, "wood": 1200, "steel": 800, "oil": 300})
	ProgressionManager.current_era = 3
	ProgressionManager.current_phase = GameConfig.Phase.EXPANSION
	PopulationManager._population = 24
	PopulationManager._max_population = 30
	PopulationManager._morale = 85
	ArmyManager._units = {"infantry": 3, "artillery": 2, "vehicle": 1}
	EventBus.army_changed.emit()
	EventBus.phase_advanced.emit(ProgressionManager.current_phase)
	_build_towers()

func _build_towers() -> void:
	var main := get_tree().current_scene
	var placer: Node = main.get_node_or_null("BuildingPlacer") if main != null else null
	if placer == null:
		return
	var data: BuildingData = load("res://data/buildings/tower.tres")
	if data == null:
		return
	for wanted in [Vector2i(14, 19), Vector2i(28, 19)]:
		for radius in range(0, 6):
			var placed := false
			for dy in range(-radius, radius + 1):
				for dx in range(-radius, radius + 1):
					var cell: Vector2i = (wanted as Vector2i) + Vector2i(dx, dy)
					if GridManager.can_place(cell, data.grid_size):
						var node: Node3D = placer.place_building_at(data, cell)
						if node != null:
							ProductionManager.register_building(node, data, 0.0)
							placed = true
							break
				if placed:
					break
			if placed:
				break

func _listen() -> void:
	EventBus.final_audit_summoned.connect(func(w, s): _log.append("convocada: %d oleadas, convocatoria %d" % [w, s]))
	EventBus.final_audit_started.connect(func(w): _log.append("empieza: %d oleadas" % w))
	EventBus.final_audit_wave_ready.connect(func(i, r, sc): _log.append("oleada %d lista: %s x%.2f" % [i, r, sc]))
	EventBus.encounter_started.connect(func(_i, _b): _log.append("  tablero: defensa=%s unidades=%d" % [
		CombatManager.is_defending(), CombatManager.get_units().size()]))
	EventBus.encounter_ended.connect(func(v, t): _log.append("  oleada resuelta: victoria=%s rondas=%d bajas=%s" % [
		v, t, CombatManager.get_last_result().get("casualties", {})]))
	EventBus.final_audit_wave_cleared.connect(func(w, r): _log.append("oleada %d rechazada, quedan %d" % [w, r]))
	EventBus.final_audit_lost.connect(func(w): _log.append("PERDIDA en la oleada %d" % w))
	EventBus.storm_halted_forever.connect(func(): _log.append("*** LA TORMENTA SE DETIENE. PARA SIEMPRE. ***"))
	EventBus.tithe_resolved.connect(func(paid, taken): _log.append("diezmo: repelido=%s se llevan %s" % [paid, taken]))

## Juega el turno activo del jugador: ataca si puede, si no se acerca y pasa.
func _play_one_turn() -> void:
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
		CombatManager.move_unit(unit.uid, cells[cells.size() - 1])
	CombatManager.end_turn()

func _audit_state() -> String:
	var a = ProgressionManager.final_audit
	if a == null:
		return "sin asedio"
	if a.is_pending():
		return "pendiente"
	if a.is_active():
		return "activa (oleada %d de %d)" % [a.current_wave + 1, a.wave_count()]
	if a.is_won():
		return "GANADA"
	if a.is_lost():
		return "perdida"
	return "?"

func _snapshot() -> Dictionary:
	return {
		"oro": ResourceManager.get_amount(ResourceManager.Type.GOLD),
		"acero": ResourceManager.get_amount(ResourceManager.Type.STEEL),
		"tropas": ArmyManager.get_total_units(),
		"poder": ArmyManager.get_power(),
		"moral": PopulationManager.get_morale(),
	}
