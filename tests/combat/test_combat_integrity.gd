extends GdUnitTestSuite
## Integridad del estado de combate: que el ledger de ArmyManager, el tablero, la
## expedicion y el asedio cuenten siempre la misma historia, tambien a traves de
## un guardado y de dos tableros que se pisan.
##
## Toca los autoloads de verdad; cada caso los deja como estaban.

var _storm_saved: Dictionary = {}
var _army_saved: Dictionary = {}
var _population_saved: Dictionary = {}
var _resources_saved: Dictionary = {}
var _progression_saved: Dictionary = {}

var _audit_lost: int = 0
var _encounters_ended: int = 0

func before_test() -> void:
	_storm_saved = StormManager.get_save_data()
	_army_saved = ArmyManager.get_save_data()
	_population_saved = PopulationManager.get_save_data()
	_resources_saved = _resource_amounts()
	_progression_saved = ProgressionManager.get_save_data()
	StormManager.reset()
	CombatManager.reset()
	ArmyManager.reset()
	ProgressionManager.final_audit = null
	PopulationManager.load_save_data({"morale": 100})
	ResourceManager.set_amounts({"gold": 400, "wood": 200, "steel": 0, "oil": 0})
	_audit_lost = 0
	_encounters_ended = 0
	EventBus.final_audit_lost.connect(_on_audit_lost)
	EventBus.encounter_ended.connect(_on_encounter_ended)

func after_test() -> void:
	EventBus.final_audit_lost.disconnect(_on_audit_lost)
	EventBus.encounter_ended.disconnect(_on_encounter_ended)
	CombatManager.reset()
	ProgressionManager.final_audit = null
	ProgressionManager.load_save_data(_progression_saved)
	StormManager.load_save_data(_storm_saved)
	ArmyManager.load_save_data(_army_saved)
	PopulationManager.load_save_data(_population_saved)
	ResourceManager.set_amounts(_resources_saved)

func _on_audit_lost(_wave: int) -> void:
	_audit_lost += 1

func _on_encounter_ended(_victory: bool, _rounds: int) -> void:
	_encounters_ended += 1

func _resource_amounts() -> Dictionary:
	return {
		"gold": ResourceManager.get_amount(ResourceManager.Type.GOLD),
		"wood": ResourceManager.get_amount(ResourceManager.Type.WOOD),
		"steel": ResourceManager.get_amount(ResourceManager.Type.STEEL),
		"oil": ResourceManager.get_amount(ResourceManager.Type.OIL),
	}

func _given_army(units: Dictionary) -> void:
	ArmyManager.load_save_data({"units": units, "training": [], "upkeep_accum": 0.0})

func _enemy_roster_on_board() -> Dictionary:
	var counts: Dictionary = {}
	for unit in CombatManager.get_units():
		if unit.side == Encounter.ENEMY:
			counts[unit.unit_id] = int(counts.get(unit.unit_id, 0)) + 1
	return counts

## Mata a un bando entero sin pasar por el modelo y cierra el turno para que el
## encuentro mire si ya acabo. No emite unit_died: es el camino "a ciegas".
func _resolve_open_board(player_wins: bool) -> void:
	var loser: int = Encounter.ENEMY if player_wins else Encounter.PLAYER
	for unit in CombatManager.get_units():
		if unit.side == loser and unit.is_alive():
			unit.take_damage(unit.max_hp * 10)
	CombatManager.end_turn()

# ── 8. La escaramuza usa el generador con semilla ────────────────────

func test_a_skirmish_fields_the_seeded_roster_of_the_first_node() -> void:
	_given_army({"infantry": 3})
	assert_bool(CombatManager.start_skirmish({"infantry": 2}, 1234)).is_true()
	var expected: Dictionary = ExpeditionGenerator.enemy_roster(
		ExpeditionGenerator.make_rng(1234), 0, ProgressionManager.current_era, 0)
	assert_dict(_enemy_roster_on_board()).is_equal(expected)

func test_the_same_seed_fields_the_same_skirmish() -> void:
	_given_army({"infantry": 3})
	CombatManager.start_skirmish({"infantry": 2}, 77)
	var first: Dictionary = _enemy_roster_on_board()
	CombatManager.reset()
	CombatManager.start_skirmish({"infantry": 2}, 77)
	assert_dict(_enemy_roster_on_board()).is_equal(first)

func test_the_provisional_unseeded_roster_is_gone() -> void:
	assert_bool(CombatManager.has_method("build_enemy_roster")).is_false()

# ── 1. No se deja atras un nodo sin pelear ───────────────────────────

func test_a_run_reloaded_mid_node_has_to_fight_it_before_moving_on() -> void:
	_given_army({"infantry": 3})
	assert_bool(CombatManager.launch_expedition({"infantry": 3}, 4242)).is_true()
	_resolve_open_board(true)
	CombatManager.end_encounter()
	if CombatManager.has_pending_draft():
		CombatManager.apply_draft(0)
	var exits: Array = CombatManager.get_expedition().current_exits()
	assert_bool(CombatManager.select_node(int(exits[0]))).is_true()
	assert_bool(CombatManager.is_in_encounter()).is_true()

	# Se guarda con el tablero del nodo 1 a medias y se vuelve a cargar.
	var data: Dictionary = CombatManager.get_save_data()
	CombatManager.reset()
	CombatManager.load_save_data(data)
	var run: Expedition = CombatManager.get_expedition()
	assert_bool(run.needs_fight()).is_true()

	var next: Array = run.current_exits()
	if not next.is_empty():
		assert_bool(CombatManager.select_node(int(next[0]))).is_false()
	assert_int(run.current_node).is_equal(int(exits[0]))
	assert_bool(CombatManager.enter_current_node()).is_true()
	assert_bool(CombatManager.is_in_encounter()).is_true()

# ── 4. Abandonar solo cierra el tablero de la columna ────────────────

## El Diezmo cae entre dos nodos: con el tablero libre, la guarnicion que se quedo
## en casa lo defiende en un tablero propio. Abandonar la expedicion en ese rato
## no puede llevarse ese tablero por delante: sin su encounter_ended el ciclo de
## la tormenta se quedaba cobrando para siempre.
func test_abandoning_leaves_a_tithe_defense_board_to_resolve_itself() -> void:
	_given_army({"infantry": 5})
	assert_bool(CombatManager.launch_expedition({"infantry": 2}, 99)).is_true()
	_resolve_open_board(true)
	CombatManager.end_encounter()
	assert_bool(CombatManager.is_board_open()).is_false()

	StormManager.get_cycle().phase = StormCycle.Phase.TITHE
	StormManager._begin_tithe(1)
	assert_bool(CombatManager.is_defending()).is_true()
	var defense: Encounter = CombatManager.get_encounter()

	assert_bool(CombatManager.abandon_expedition()).is_true()
	assert_bool(CombatManager.has_active_expedition()).is_false()
	# La defensa sigue en el tablero y sin resolver.
	assert_object(CombatManager.get_encounter()).is_same(defense)
	assert_bool(CombatManager.is_in_encounter()).is_true()

	_encounters_ended = 0
	_resolve_open_board(true)
	assert_int(_encounters_ended).is_equal(1)
	assert_bool(StormManager.get_cycle().is_collecting()).is_false()

func test_abandoning_still_closes_the_expeditions_own_board() -> void:
	_given_army({"infantry": 3})
	assert_bool(CombatManager.launch_expedition({"infantry": 2}, 99)).is_true()
	assert_bool(CombatManager.is_board_open()).is_true()
	assert_bool(CombatManager.abandon_expedition()).is_true()
	assert_bool(CombatManager.is_board_open()).is_false()

# ── 7. Quien esta en un tablero no esta en casa ──────────────────────

func test_units_fighting_a_skirmish_are_not_in_the_garrison() -> void:
	_given_army({"infantry": 4})
	assert_bool(CombatManager.start_skirmish({"infantry": 3}, 5)).is_true()
	assert_dict(CombatManager.get_units_on_board()).is_equal({"infantry": 3})
	assert_dict(CombatManager.get_garrison()).is_equal({"infantry": 1})
	assert_dict(CombatManager.get_deployable_units()).is_equal({"infantry": 1})

func test_a_blind_tithe_during_a_skirmish_never_charges_the_same_dead_twice() -> void:
	# Todo el ejercito esta en la escaramuza: en casa no queda nadie que defienda.
	_given_army({"infantry": 2})
	assert_bool(CombatManager.start_skirmish({"infantry": 2}, 5)).is_true()
	var outcome: Dictionary = CombatManager.auto_resolve_defense({"infantry": 6}, 3.0)
	assert_bool(bool(outcome["fought"])).is_false()
	assert_int(ArmyManager.get_count("infantry")).is_equal(2)
	# La escaramuza se pierde: las dos bajas salen una sola vez.
	_resolve_open_board(false)
	assert_int(ArmyManager.get_count("infantry")).is_equal(0)

func test_once_the_result_is_applied_the_survivors_are_home_again() -> void:
	_given_army({"infantry": 3})
	assert_bool(CombatManager.start_skirmish({"infantry": 2}, 5)).is_true()
	_resolve_open_board(true)
	# El parte sigue en pantalla, pero la pelea ya se liquido.
	assert_bool(CombatManager.is_board_open()).is_true()
	assert_dict(CombatManager.get_units_on_board()).is_empty()
	assert_dict(CombatManager.get_garrison()).is_equal({"infantry": 3})

func test_nobody_deserts_from_the_middle_of_a_fight() -> void:
	_given_army({"infantry": 2, "artillery": 1})
	assert_bool(CombatManager.start_skirmish({"artillery": 1}, 5)).is_true()
	# La artilleria es la mas cara de mantener, pero esta en el tablero.
	ArmyManager._desert()
	assert_int(ArmyManager.get_count("artillery")).is_equal(1)
	assert_int(ArmyManager.get_count("infantry")).is_less(2)

# ── 3. La guarnicion del asedio se pasa lista al abrir la puerta ──────

func _living_counts(audit: FinalAudit) -> Dictionary:
	var counts: Dictionary = {}
	for unit in audit.living_garrison():
		counts[unit.unit_id] = int(counts.get(unit.unit_id, 0)) + 1
	return counts

func test_the_first_begin_musters_whoever_is_home_now() -> void:
	var audit := FinalAudit.create(11, {"infantry": 4}, 1, 50.0)
	assert_int(audit.garrison.size()).is_equal(4)
	audit.begin({"infantry": 2, "artillery": 1})
	assert_dict(_living_counts(audit)).is_equal({"infantry": 2, "artillery": 1})
	assert_bool(audit.started).is_true()

func test_a_siege_already_fought_is_reconciled_never_remustered() -> void:
	var audit := FinalAudit.create(11, {"infantry": 3}, 1, 50.0)
	audit.begin({"infantry": 3})
	audit.garrison[0].take_damage(5)
	var wounded_hp: int = audit.garrison[0].hp
	var back: FinalAudit = FinalAudit.from_dict(audit.to_dict())
	assert_bool(back.is_pending()).is_true()
	assert_bool(back.started).is_true()
	# Diez en casa no son diez en el asedio: los refuerzos no entran.
	back.begin({"infantry": 10})
	assert_int(back.garrison.size()).is_equal(3)
	assert_int(back.garrison[0].hp).is_equal(wounded_hp)
	# Y si el ejercito encogio, la guarnicion encoge con el.
	back.reconcile({"infantry": 1})
	assert_dict(_living_counts(back)).is_equal({"infantry": 1})
	assert_int(back.garrison[0].hp).is_equal(wounded_hp)

func test_an_old_save_guesses_whether_the_siege_had_started() -> void:
	var fresh := FinalAudit.create(11, {"infantry": 2}, 1, 50.0)
	var data: Dictionary = fresh.to_dict()
	data.erase("started")
	assert_bool(FinalAudit.from_dict(data).started).is_false()
	data["current_wave"] = 1
	assert_bool(FinalAudit.from_dict(data).started).is_true()

func test_the_siege_is_fought_by_who_is_home_when_it_begins() -> void:
	_given_army({"infantry": 4})
	assert_bool(ProgressionManager.summon_final_audit()).is_true()
	# Mientras la Regencia espera, dos desertan y se entrena una artilleria.
	ArmyManager.remove_units({"infantry": 2})
	_given_army({"infantry": 2, "artillery": 1})
	assert_bool(ProgressionManager.begin_final_audit()).is_true()
	assert_dict(_living_counts(ProgressionManager.final_audit)).is_equal({"infantry": 2, "artillery": 1})

func test_the_garrison_is_squared_with_the_army_before_every_wave() -> void:
	_given_army({"infantry": 3})
	assert_bool(ProgressionManager.summon_final_audit()).is_true()
	assert_bool(ProgressionManager.begin_final_audit()).is_true()
	if ProgressionManager.final_audit.wave_count() < 2:
		return
	_resolve_open_board(true)
	var alive: int = ProgressionManager.final_audit.living_garrison().size()
	# Entre oleadas, uno deserta. La oleada siguiente no lo cuenta.
	ArmyManager.remove_units({"infantry": 1})
	CombatManager.end_encounter()
	assert_int(ProgressionManager.final_audit.living_garrison().size()).is_equal(mini(alive, ArmyManager.get_count("infantry")))

# ── 6. Una oleada no se pierde por encontrar el tablero ocupado ───────

func test_the_siege_cannot_begin_over_an_open_board_and_says_why() -> void:
	_given_army({"infantry": 4})
	assert_bool(ProgressionManager.summon_final_audit()).is_true()
	assert_bool(CombatManager.start_skirmish({"infantry": 2}, 5)).is_true()
	assert_str(CombatManager.final_audit_block_reason()).is_equal("MSG_AUDIT_BOARD_BUSY")
	assert_bool(ProgressionManager.begin_final_audit()).is_false()
	assert_bool(ProgressionManager.is_final_audit_pending()).is_true()
	assert_int(_audit_lost).is_equal(0)

func test_the_audit_button_is_disabled_with_a_reason_while_a_board_is_open() -> void:
	_given_army({"infantry": 4})
	assert_bool(ProgressionManager.summon_final_audit()).is_true()
	assert_bool(CombatManager.start_skirmish({"infantry": 2}, 5)).is_true()
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/SkirmishPanel.tscn").instantiate())
	add_child(panel)
	await await_idle_frame()
	panel._refresh_audit_button()
	assert_bool(panel._audit_btn.visible).is_true()
	assert_bool(panel._audit_btn.disabled).is_true()
	assert_str(panel._audit_btn.tooltip_text).is_equal(Tr.t("MSG_AUDIT_BOARD_BUSY"))
	# Pulsarlo a la fuerza tampoco lo abre.
	panel._on_audit_pressed()
	assert_bool(ProgressionManager.is_final_audit_pending()).is_true()

func test_a_wave_that_finds_the_board_busy_waits_instead_of_being_lost() -> void:
	_given_army({"infantry": 4})
	assert_bool(ProgressionManager.summon_final_audit()).is_true()
	assert_bool(CombatManager.start_skirmish({"infantry": 2}, 5)).is_true()
	# Saltandose el bloqueo: el asedio empieza con el tablero ocupado.
	ProgressionManager._publish_audit(ProgressionManager.final_audit.begin())
	ProgressionManager._announce_wave()
	assert_int(_audit_lost).is_equal(0)
	assert_bool(ProgressionManager.is_final_audit_active()).is_true()
	assert_bool(CombatManager.is_defending()).is_false()

	_resolve_open_board(true)
	CombatManager.end_encounter()
	await await_idle_frame()
	# La oleada bajo en cuanto el tablero quedo libre.
	assert_bool(CombatManager.is_in_encounter()).is_true()
	assert_bool(CombatManager.is_defending()).is_true()
	assert_int(_audit_lost).is_equal(0)

# ── 5. Un solo bucle enemigo por tablero ─────────────────────────────

var _enemy_actions: int = 0

func _count_enemy_action(_a = null, _b = null, _c = null) -> void:
	_enemy_actions += 1

## Tablero A con la IA pensando (paso corto); se cierra y se abre B, tambien con
## el enemigo moviendo primero pero con un paso muy largo. Si el bucle de A
## despierta y se cree el dueño de B, suelta la bandera y relanza un bucle nuevo
## que ya lee el paso corto: el enemigo de B actuaria mucho antes de su tiempo.
func test_a_stale_enemy_turn_never_drives_the_next_board() -> void:
	var saved_delay: float = GameConfig.combat_ai_step_delay
	var saved_dev: bool = GameConfig.dev_mode
	GameConfig.dev_mode = false
	_enemy_actions = 0
	# Artilleria (iniciativa 3) contra infanteria (5): abre el enemigo. Con la
	# moral a tope la artilleria empataria y el empate es del jugador.
	PopulationManager.load_save_data({"morale": 0})
	GameConfig.combat_ai_step_delay = 0.15
	CombatManager.start_encounter({"artillery": 2}, {"infantry": 2})
	assert_bool(CombatManager.is_enemy_thinking()).is_true()
	CombatManager.end_encounter()

	GameConfig.combat_ai_step_delay = 4.0
	CombatManager.start_encounter({"artillery": 2}, {"infantry": 2})
	assert_bool(CombatManager.is_enemy_thinking()).is_true()
	GameConfig.combat_ai_step_delay = 0.02

	EventBus.unit_moved.connect(_count_enemy_action)
	EventBus.unit_attacked.connect(_count_enemy_action)
	EventBus.unit_defended.connect(_count_enemy_action)
	await get_tree().create_timer(0.6).timeout
	EventBus.unit_moved.disconnect(_count_enemy_action)
	EventBus.unit_attacked.disconnect(_count_enemy_action)
	EventBus.unit_defended.disconnect(_count_enemy_action)

	GameConfig.combat_ai_step_delay = saved_delay
	GameConfig.dev_mode = saved_dev
	assert_int(_enemy_actions).is_equal(0)
	assert_bool(CombatManager.is_enemy_thinking()).is_true()
