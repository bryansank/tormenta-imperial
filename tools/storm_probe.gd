extends Node
## Dev tool: acorta el reloj de la Tormenta y observa un ciclo entero, contando
## lo que le pasa a la base. Sirve para comprobar que el ciclo se engancha de
## verdad al juego y no solo a los tests.
##
## Uso: registrar temporalmente como autoload y arrancar el juego.
##   project.godot -> [autoload] -> StormProbe="*res://tools/storm_probe.gd"
## Quitar la linea al terminar.
##
## Hermano de tools/battle_probe.gd.

const SETTLE := 2.0
## Segundos que se le dejan a la primera tormenta antes de caer.
const FUSE := 4.0

func _ready() -> void:
	if not GameConfig.dev_mode:
		push_warning("[storm] dev_mode desactivado; no se hace nada")
		return
	await get_tree().create_timer(SETTLE).timeout
	await _run()

func _run() -> void:
	_seed()
	_listen()

	# Armar el reloj y acortar la mecha: no interesa esperar la cuenta real.
	var cycle: StormCycle = StormManager.get_cycle()
	if cycle == null:
		print("[storm] ERROR: no hay ciclo")
		get_tree().quit()
		return
	cycle.seconds_left = FUSE
	print("[storm] armado=%s fase=%d severidad=%d impacto_en=%.1fs" % [
		StormManager.is_armed(), StormManager.get_phase(),
		StormManager.get_severity(), StormManager.seconds_until_impact()
	])
	print("[storm] antes: %s" % _snapshot())

	# Un ciclo entero: mecha + aviso + tormenta + cobranza, con margen.
	var total: float = FUSE + GameConfig.get_storm_warning() + GameConfig.get_storm_duration() + 6.0
	# La IA espera entre accion y accion para que se vea; aqui no mira nadie.
	GameConfig.combat_ai_step_delay = 0.0
	var elapsed := 0.0
	var seen_storm := false
	var seen_warning := false
	while elapsed < total:
		if StormManager.get_phase() == StormCycle.Phase.WARNING and not seen_warning:
			seen_warning = true
			await _shot("storm_01_aviso")
		# Si los Tasadores abren tablero, hay que pelear o el ciclo se queda
		# esperando: la fase de cobranza detiene el reloj a proposito.
		if CombatManager.is_in_encounter():
			await _play_one_turn()
			continue
		await get_tree().create_timer(0.5).timeout
		elapsed += 0.5
		if StormManager.is_storming() and not seen_storm:
			seen_storm = true
			print("[storm] EN TORMENTA | multiplicador de produccion = %.2f" % GameConfig.event_production_multiplier)
			await _shot("storm_02_cayendo")

	print("[storm] despues: %s" % _snapshot())
	print("[storm] fase final=%d tormentas_superadas=%d severidad=%d" % [
		StormManager.get_phase(), StormManager.storms_survived(), StormManager.get_severity()
	])
	print("[storm] multiplicador de produccion restaurado = %.2f" % GameConfig.event_production_multiplier)
	get_tree().quit()

## Una base creible y ya fuera de la fase Fundacion, que es donde el reloj se arma.
## Con guarnicion: asi el Diezmo llega a las manos en vez de cobrarse solo.
func _seed() -> void:
	ArmyManager._units = {"infantry": 4, "artillery": 2}
	EventBus.army_changed.emit()
	ResourceManager.set_unlock_state({"gold": true, "wood": true, "steel": true, "oil": false})
	ResourceManager.set_amounts({"gold": 2000, "wood": 1000, "steel": 500, "oil": 0})
	ProgressionManager.current_era = 2
	ProgressionManager.current_phase = GameConfig.Phase.EXPANSION
	PopulationManager._population = 20
	PopulationManager._max_population = 30
	PopulationManager._morale = 80
	EventBus.phase_advanced.emit(ProgressionManager.current_phase)

func _listen() -> void:
	EventBus.storm_incoming.connect(func(secs, sev):
		print("[storm] AVISO: impacto en %.1fs, severidad %d" % [secs, sev]))
	EventBus.storm_started.connect(func(sev):
		print("[storm] CAE LA CENIZA (severidad %d)" % sev))
	EventBus.storm_ended.connect(func(_sev):
		print("[storm] el aire aclara"))
	EventBus.tithe_demanded.connect(func(sev):
		print("[storm] LLEGAN LOS TASADORES (severidad %d)" % sev))
	EventBus.encounter_started.connect(func(_i, _b):
		print("[storm] TABLERO ABIERTO | defensa=%s | guarnicion=%s" % [
			CombatManager.is_defending(), CombatManager.get_garrison()]))
	EventBus.tithe_resolved.connect(func(paid, taken):
		print("[storm] cobranza resuelta: repelida=%s, se llevan %s" % [paid, taken]))

## Juega el turno activo del jugador: ataca si puede, si no se acerca y pasa.
## El turno enemigo lo lleva la IA sola.
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

const OUT_DIR := "res://docs/media/dev"

func _shot(file_name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png("%s/%s.png" % [OUT_DIR, file_name])
	print("[storm] %s.png (err %d)" % [file_name, err])

func _snapshot() -> Dictionary:
	return {
		"oro": ResourceManager.get_amount(ResourceManager.Type.GOLD),
		"madera": ResourceManager.get_amount(ResourceManager.Type.WOOD),
		"acero": ResourceManager.get_amount(ResourceManager.Type.STEEL),
		"moral": PopulationManager.get_morale(),
	}
