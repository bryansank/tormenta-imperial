extends GdUnitTestSuite
## El cableado del final del juego: que ganar el asedio pare la Tormenta para
## siempre, que perderlo cueste, y que nada de eso se pierda al guardar ni se
## arrastre a una partida nueva.
##
## Toca los autoloads de verdad, asi que cada caso deja StormManager y
## CombatManager como los encontro.

var _storm_saved: Dictionary = {}
var _army_saved: Dictionary = {}
var _mult_saved: float = 1.0

func before_test() -> void:
	_storm_saved = StormManager.get_save_data()
	_army_saved = ArmyManager.get_save_data()
	_mult_saved = GameConfig.event_production_multiplier
	StormManager.reset()
	CombatManager.reset()
	ArmyManager.reset()

func after_test() -> void:
	CombatManager.end_encounter()
	CombatManager.reset()
	StormManager.load_save_data(_storm_saved)
	ArmyManager.load_save_data(_army_saved)
	GameConfig.event_production_multiplier = _mult_saved

# ── is_cycle_active: la mitad de StormManager de la deuda de GameConfig ─────

func test_the_cycle_is_not_active_in_calm() -> void:
	assert_bool(StormManager.is_cycle_active()).is_false()

func test_the_cycle_is_active_once_the_warning_opens() -> void:
	var cycle: StormCycle = StormManager.get_cycle()
	cycle.phase = StormCycle.Phase.WARNING
	assert_bool(StormManager.is_cycle_active()).is_true()

func test_a_halted_storm_is_never_active_whatever_the_phase_says() -> void:
	EventBus.storm_halted_forever.emit()
	var cycle: StormCycle = StormManager.get_cycle()
	cycle.phase = StormCycle.Phase.STORM
	assert_bool(StormManager.is_cycle_active()).is_false()

func test_a_halted_storm_cancels_at_the_calm_price() -> void:
	# La deuda de GameConfig: el reembolso leia la fase a pelo. Con la Tormenta
	# parada la fase es CALM de todos modos, pero la fuente de verdad es una sola.
	EventBus.storm_halted_forever.emit()
	var cycle: StormCycle = StormManager.get_cycle()
	cycle.phase = StormCycle.Phase.STORM
	assert_float(GameConfig.get_cancel_refund_ratio()).is_equal(GameConfig.cancel_refund_ratio)

# ── Parar para siempre ───────────────────────────────────────────────

func test_halting_stops_and_disarms_the_clock() -> void:
	EventBus.storm_halted_forever.emit()
	assert_bool(StormManager.is_halted()).is_true()
	assert_bool(StormManager.is_armed()).is_false()

func test_halting_lifts_the_production_penalty_at_once() -> void:
	# Si el asedio se gana con la ceniza encima, las fabricas no pueden quedarse
	# al 15% para siempre.
	GameConfig.event_production_multiplier = 0.15
	EventBus.storm_halted_forever.emit()
	assert_float(GameConfig.event_production_multiplier).is_equal(1.0)

func test_halting_leaves_the_sky_reading_calm() -> void:
	var cycle: StormCycle = StormManager.get_cycle()
	cycle.phase = StormCycle.Phase.STORM
	EventBus.storm_halted_forever.emit()
	assert_int(StormManager.get_phase()).is_equal(StormCycle.Phase.CALM)

# ── Y sobrevive al guardado ──────────────────────────────────────────

func test_the_halt_travels_in_the_save() -> void:
	EventBus.storm_halted_forever.emit()
	var data := StormManager.get_save_data()
	assert_bool(bool(data.get("halted", false))).is_true()

func test_a_halted_save_reloads_halted_and_disarmed() -> void:
	# El caso que arruinaria el final: ganar, cerrar el juego, volver a entrar y
	# que caiga una tormenta despues de los creditos.
	EventBus.storm_halted_forever.emit()
	var data := StormManager.get_save_data()
	StormManager.reset()
	assert_bool(StormManager.is_halted()).is_false()
	StormManager.load_save_data(data)
	assert_bool(StormManager.is_halted()).is_true()
	assert_bool(StormManager.is_armed()).is_false()

func test_a_save_from_before_the_audit_existed_is_not_halted() -> void:
	# Compatibilidad hacia atras: sin la clave, la Tormenta sigue viniendo.
	var data := StormManager.get_save_data()
	data.erase("halted")
	StormManager.load_save_data(data)
	assert_bool(StormManager.is_halted()).is_false()

# ── Y no se arrastra a la partida siguiente ──────────────────────────

func test_a_new_game_gets_its_storm_back() -> void:
	# Sin esto, ganar una vez dejaria todas las partidas futuras sin Tormenta y
	# el juego pareceria roto. Es el patron del checklist de estado persistente.
	EventBus.storm_halted_forever.emit()
	StormManager.reset()
	assert_bool(StormManager.is_halted()).is_false()
	assert_bool(bool(StormManager.get_save_data().get("halted", true))).is_false()

# ── Perder el asedio pasa por encima ─────────────────────────────────

func test_losing_the_audit_collects_the_tithe_without_a_fight() -> void:
	ResourceManager.set_amounts({"gold": 1000, "wood": 500, "steel": 200, "oil": 0})
	var seen := [false, true, {}]
	var probe := func(paid: bool, taken: Dictionary) -> void:
		seen[0] = true
		seen[1] = paid
		seen[2] = taken
	EventBus.tithe_resolved.connect(probe)
	EventBus.final_audit_lost.emit(1)
	EventBus.tithe_resolved.disconnect(probe)
	assert_bool(seen[0]).is_true()
	assert_bool(seen[1]).is_false()    # no se repelio: se pago
	assert_bool((seen[2] as Dictionary).is_empty()).is_false()

func test_losing_the_audit_does_not_halt_the_storm() -> void:
	# Perder deja la base en ruinas Y con el reloj corriendo: el jugador
	# reconstruye y vuelve a convocarlos. No es un final.
	EventBus.final_audit_lost.emit(1)
	assert_bool(StormManager.is_halted()).is_false()

# ── Las oleadas traen su propia escala ───────────────────────────────

func test_a_defence_can_field_enemies_at_a_given_scale() -> void:
	ArmyManager.load_save_data({"units": {"infantry": 2}, "training": [], "upkeep_accum": 0.0})
	var ok: bool = CombatManager.start_defense({"infantry": 1}, [], 2.0)
	assert_bool(ok).is_true()
	var base_hp: int = int(GameConfig.get_combat_stats("infantry").get("hp", 0))
	var doubled := false
	for unit in CombatManager.get_units():
		if unit.side == Encounter.ENEMY:
			doubled = unit.max_hp == base_hp * 2
	assert_bool(doubled).is_true()

func test_without_a_scale_the_defence_fields_enemies_as_before() -> void:
	ArmyManager.load_save_data({"units": {"infantry": 2}, "training": [], "upkeep_accum": 0.0})
	CombatManager.start_defense({"infantry": 1})
	var base_hp: int = int(GameConfig.get_combat_stats("infantry").get("hp", 0))
	for unit in CombatManager.get_units():
		if unit.side == Encounter.ENEMY:
			assert_int(unit.max_hp).is_equal(base_hp)

# ── Cada unidad del tablero tiene su propio uid ──────────────────────
#
# La guarnicion del asedio la numera FinalAudit; las dotaciones y el enemigo los
# numera CombatManager. Sin reservar los primeros, los segundos repetian numero
# y Encounter.get_unit() confundia a unos con otros: los defensores se mataban
# entre si y la Regencia salia ilesa de las veinte rondas.

func _assert_uids_are_unique() -> void:
	var seen := {}
	for unit in CombatManager.get_units():
		assert_bool(seen.has(unit.uid)).override_failure_message(
			"uid %d repetido en el tablero" % unit.uid).is_false()
		seen[unit.uid] = true

func test_units_handed_in_keep_their_uids_and_the_enemy_never_reuses_them() -> void:
	var handed: Array = []
	for i in range(1, 4):
		handed.append(CombatUnit.create(i, "infantry", Encounter.PLAYER, 1.0))
	CombatManager.start_encounter_with_units(handed, {"infantry": 2, "artillery": 1}, false, 0, true, [])
	assert_int(CombatManager.get_units().size()).is_equal(6)
	_assert_uids_are_unique()
	for i in range(1, 4):
		var unit: CombatUnit = CombatManager.get_encounter().get_unit(i)
		assert_int(unit.side).is_equal(Encounter.PLAYER)

func test_the_first_audit_wave_fields_a_board_without_duplicate_uids() -> void:
	# El camino real: convocar, bajar, y mirar el tablero que abre la oleada.
	var progression_saved: Dictionary = ProgressionManager.get_save_data()
	ArmyManager.load_save_data({"units": {"infantry": 3, "vehicle": 1}, "training": [], "upkeep_accum": 0.0})
	ProgressionManager.final_audit = null
	assert_bool(ProgressionManager.summon_final_audit()).is_true()
	assert_bool(ProgressionManager.begin_final_audit()).is_true()
	assert_bool(CombatManager.is_in_encounter()).is_true()
	_assert_uids_are_unique()
	var enemies := 0
	for unit in CombatManager.get_units():
		if unit.side == Encounter.ENEMY:
			enemies += 1
	assert_int(enemies).is_greater(0)
	# El asedio es estado del servicio: se deja como estaba.
	CombatManager.end_encounter()
	ProgressionManager.final_audit = null
	ProgressionManager.load_save_data(progression_saved)
