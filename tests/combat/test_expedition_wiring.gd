extends GdUnitTestSuite
## El cableado de la expedicion en CombatManager: lanzar, encadenar nodos con
## atricion y permadeath, draft, jefe, derrota, abandono, el bloqueo de las
## unidades que salieron y el guardado a mitad de campana.
##
## Lo que se prueba aqui no es el modelo (eso esta en test_expedition.gd) sino
## que el servicio cobre UNA sola vez y en el momento justo: nada llega al
## almacen ni al cuartel hasta que la columna vuelve (FR-010, FR-011, FR-017).
##
## Toca los autoloads de verdad, asi que cada caso los deja como los encontro.

const PARTY := {"infantry": 2, "artillery": 1}
const SEED := 424242

const PLAYER := 0
const ENEMY := 1

var _saved_army: Dictionary = {}
var _saved_population: Dictionary = {}
var _saved_resources: Dictionary = {}
var _saved_era: int = 1
var _saved_warehouses: int = 0
var _saved_storm: Dictionary = {}
var _saved_progression: Dictionary = {}

func before_test() -> void:
	_saved_army = ArmyManager.get_save_data()
	_saved_population = PopulationManager.get_save_data()
	_saved_storm = StormManager.get_save_data()
	_saved_progression = ProgressionManager.get_save_data()
	_saved_era = ResourceManager.get_era()
	_saved_warehouses = ResourceManager.get_warehouse_count()
	_saved_resources = {}
	for type in ResourceManager.get_all():
		_saved_resources[ResourceManager.get_type_name(type)] = int(ResourceManager.get_all()[type])

	StormManager.reset()
	CombatManager.reset()
	ArmyManager.reset()
	ProgressionManager.final_audit = null
	# Moral fija y alta: la iniciativa del jugador depende de ella, y estos tests
	# necesitan saber quien abre el tablero para poder cerrarlo a mano.
	PopulationManager.load_save_data({"morale": 100})
	# Almacen vacio y grande, para que el botin de una campana entera quepa y se
	# pueda comparar al centimo con lo que dice la expedicion.
	ResourceManager.set_amounts({"gold": 0, "wood": 0, "steel": 0, "oil": 0})
	ResourceManager.set_era(3)
	ResourceManager.set_warehouse_count(5)

func after_test() -> void:
	CombatManager.end_encounter()
	CombatManager.reset()
	ProgressionManager.final_audit = null
	ProgressionManager.load_save_data(_saved_progression)
	StormManager.load_save_data(_saved_storm)
	ArmyManager.load_save_data(_saved_army)
	PopulationManager.load_save_data(_saved_population)
	ResourceManager.set_era(_saved_era)
	ResourceManager.set_warehouse_count(_saved_warehouses)
	ResourceManager.set_amounts(_saved_resources)

# ── Utillaje ─────────────────────────────────────────────────────────

func _given_army(units: Dictionary) -> void:
	ArmyManager.load_save_data({"units": units, "training": [], "upkeep_accum": 0.0})

## Ejercito exacto al party y columna en marcha.
func _launch(party: Dictionary = PARTY) -> bool:
	_given_army(party)
	return CombatManager.launch_expedition(party, SEED)

func _units_of_side(side: int) -> Array:
	var found: Array = []
	for unit in CombatManager.get_units():
		if unit.side == side and unit.is_alive():
			found.append(unit)
	return found

func _wipe(side: int) -> void:
	for unit in _units_of_side(side):
		unit.take_damage(unit.max_hp * 10)

## Cierra el turno del jugador, que es lo que hace al tablero mirar si ya acabo.
func _settle() -> void:
	assert_bool(CombatManager.end_turn()).is_true()

func _win_node() -> void:
	_wipe(ENEMY)
	_settle()

func _lose_node() -> void:
	_wipe(PLAYER)
	_settle()

## Indice de una carta que no cure: para no enmascarar la atricion.
func _stat_draft_index() -> int:
	var options: Array = CombatManager.get_draft_options()
	for i in range(options.size()):
		if not (options[i] as Dictionary).get("effect", {}).has("heal_pct"):
			return i
	return 0

func _first_exit() -> int:
	return int(CombatManager.get_expedition().current_exits()[0])

## Gana el nodo, coge una carta y sigue por la primera salida.
func _clear_and_advance() -> void:
	_win_node()
	assert_bool(CombatManager.apply_draft(_stat_draft_index())).is_true()
	assert_bool(CombatManager.select_node(_first_exit())).is_true()

func _total(counts: Dictionary) -> int:
	var sum := 0
	for value in counts.values():
		sum += int(value)
	return sum

# ── can_launch: por que no se sale ───────────────────────────────────

func test_you_cannot_launch_with_nobody() -> void:
	_given_army({"infantry": 3})
	var check: Dictionary = CombatManager.can_launch({})
	assert_bool(bool(check["ok"])).is_false()
	assert_str(String(check["reason"])).is_equal("MSG_NO_UNITS")
	assert_bool(CombatManager.launch_expedition({}, SEED)).is_false()

func test_you_cannot_launch_more_than_the_deploy_cap() -> void:
	var cap: int = GameConfig.combat_deploy_cap
	_given_army({"infantry": cap + 4})
	var check: Dictionary = CombatManager.can_launch({"infantry": cap + 1})
	assert_bool(bool(check["ok"])).is_false()
	assert_str(String(check["reason"])).is_equal("MSG_DEPLOY_CAP_EXCEEDED")

func test_you_cannot_launch_units_you_do_not_have() -> void:
	_given_army({"infantry": 1})
	var check: Dictionary = CombatManager.can_launch({"infantry": 2})
	assert_bool(bool(check["ok"])).is_false()
	assert_str(String(check["reason"])).is_equal("MSG_UNITS_UNAVAILABLE")

func test_the_garrison_stays_home_once_the_audit_is_summoned() -> void:
	# Con la Regencia convocada, mandar el ejercito fuera seria regalar el final.
	_given_army({"infantry": 3})
	assert_bool(ProgressionManager.summon_final_audit()).is_true()
	var check: Dictionary = CombatManager.can_launch({"infantry": 2})
	assert_bool(bool(check["ok"])).is_false()
	assert_str(String(check["reason"])).is_equal("MSG_AUDIT_BLOCKS_EXPEDITION")
	assert_bool(CombatManager.launch_expedition({"infantry": 2}, SEED)).is_false()

func test_a_sound_party_may_leave() -> void:
	_given_army(PARTY)
	var check: Dictionary = CombatManager.can_launch(PARTY)
	assert_bool(bool(check["ok"])).is_true()
	assert_str(String(check["reason"])).is_equal("")

# ── Lanzar ───────────────────────────────────────────────────────────

func test_launching_announces_the_campaign_and_opens_the_first_board() -> void:
	var seen := [false, 0, 0]
	var probe := func(id: int, node_count: int) -> void:
		seen[0] = true
		seen[1] = id
		seen[2] = node_count
	EventBus.expedition_started.connect(probe)
	var ok: bool = _launch()
	EventBus.expedition_started.disconnect(probe)

	assert_bool(ok).is_true()
	assert_bool(seen[0]).is_true()
	assert_bool(CombatManager.has_active_expedition()).is_true()
	var run: Expedition = CombatManager.get_expedition()
	assert_int(int(seen[1])).is_equal(run.id)
	assert_int(int(seen[2])).is_equal(run.map.size())
	assert_int(run.current_node).is_equal(0)
	assert_bool(CombatManager.is_in_encounter()).is_true()
	assert_int(_units_of_side(PLAYER).size()).is_equal(3)

func test_the_board_fights_with_the_party_itself_not_a_copy() -> void:
	# Si el tablero trabajara sobre copias, el daño nunca llegaria al party y la
	# atricion seria decorativa.
	_launch()
	var run: Expedition = CombatManager.get_expedition()
	var board: Array = CombatManager.get_units()
	for unit in run.party:
		assert_bool(board.has(unit)).is_true()

func test_launching_does_not_touch_the_army_or_the_storehouse() -> void:
	_launch()
	assert_int(ArmyManager.get_count("infantry")).is_equal(2)
	assert_int(ArmyManager.get_count("artillery")).is_equal(1)
	assert_int(ResourceManager.get_amount(ResourceManager.Type.GOLD)).is_equal(0)

func test_only_one_column_at_a_time() -> void:
	_given_army({"infantry": 6})
	assert_bool(CombatManager.launch_expedition({"infantry": 2}, SEED)).is_true()
	var check: Dictionary = CombatManager.can_launch({"infantry": 2})
	assert_bool(bool(check["ok"])).is_false()
	assert_str(String(check["reason"])).is_equal("MSG_EXPEDITION_ACTIVE")

func test_no_skirmish_while_the_column_is_out() -> void:
	_given_army({"infantry": 6})
	CombatManager.launch_expedition({"infantry": 2}, SEED)
	CombatManager.end_encounter()
	assert_bool(CombatManager.start_skirmish({"infantry": 2})).is_false()

# ── Ganar un nodo: draft, y la base ni se entera ─────────────────────

func test_winning_a_node_offers_a_draft_and_pays_nothing_yet() -> void:
	_launch()
	var offered := [false, []]
	var ended := [false]
	var on_draft := func(options: Array) -> void:
		offered[0] = true
		offered[1] = options
	var on_end := func(_r: int, _rw: Dictionary, _c: Dictionary) -> void: ended[0] = true
	EventBus.draft_offered.connect(on_draft)
	EventBus.expedition_ended.connect(on_end)
	_win_node()
	EventBus.draft_offered.disconnect(on_draft)
	EventBus.expedition_ended.disconnect(on_end)

	assert_bool(offered[0]).is_true()
	assert_int((offered[1] as Array).size()).is_greater_equal(2)
	assert_bool(CombatManager.has_pending_draft()).is_true()
	assert_bool(ended[0]).is_false()
	assert_bool(CombatManager.has_active_expedition()).is_true()
	# El botin del nodo esta apuntado en la campana, no en el almacen.
	assert_bool(CombatManager.get_expedition().rewards.is_empty()).is_false()
	assert_int(ResourceManager.get_amount(ResourceManager.Type.GOLD)).is_equal(0)
	assert_int(ResourceManager.get_amount(ResourceManager.Type.WOOD)).is_equal(0)
	assert_int(ArmyManager.get_count("infantry")).is_equal(2)
	assert_int(ArmyManager.get_count("artillery")).is_equal(1)

func test_the_node_result_names_what_it_paid_without_cashing_it() -> void:
	_launch()
	_win_node()
	var result: Dictionary = CombatManager.get_last_result()
	assert_bool(bool(result["victory"])).is_true()
	assert_bool(bool(result.get("expedition", false))).is_true()
	assert_bool((result["rewards"] as Dictionary).is_empty()).is_false()
	assert_int(int(result["morale_delta"])).is_equal(0)

func test_the_draft_comes_after_the_board_is_declared_closed() -> void:
	# La UI cierra el tablero con encounter_ended; si la carta llegara antes se
	# pintaria debajo del parte de batalla.
	_launch()
	var order: Array = []
	var on_end := func(_v: bool, _t: int) -> void: order.append("encounter_ended")
	var on_draft := func(_o: Array) -> void: order.append("draft_offered")
	EventBus.encounter_ended.connect(on_end)
	EventBus.draft_offered.connect(on_draft)
	_win_node()
	EventBus.encounter_ended.disconnect(on_end)
	EventBus.draft_offered.disconnect(on_draft)
	assert_array(order).is_equal(["encounter_ended", "draft_offered"])

func test_the_next_board_waits_for_the_card_and_then_for_the_route() -> void:
	_launch()
	_win_node()
	assert_bool(CombatManager.is_in_encounter()).is_false()
	# Con la carta sin elegir no se elige ruta.
	assert_bool(CombatManager.select_node(_first_exit())).is_false()

	var applied := [false]
	var probe := func(_option: Dictionary) -> void: applied[0] = true
	EventBus.draft_applied.connect(probe)
	assert_bool(CombatManager.apply_draft(_stat_draft_index())).is_true()
	EventBus.draft_applied.disconnect(probe)
	assert_bool(applied[0]).is_true()
	assert_bool(CombatManager.has_pending_draft()).is_false()
	# Elegir carta no abre nada: la ruta es otra decision.
	assert_bool(CombatManager.is_in_encounter()).is_false()

	var selected := [-1]
	var on_select := func(index: int) -> void: selected[0] = index
	EventBus.expedition_node_selected.connect(on_select)
	var exit_index: int = _first_exit()
	assert_bool(CombatManager.select_node(exit_index)).is_true()
	EventBus.expedition_node_selected.disconnect(on_select)
	assert_int(int(selected[0])).is_equal(exit_index)
	assert_bool(CombatManager.is_in_encounter()).is_true()
	assert_int(CombatManager.get_expedition().current_node).is_equal(exit_index)

func test_you_cannot_jump_to_a_node_that_is_not_an_exit() -> void:
	_launch()
	_win_node()
	CombatManager.apply_draft(_stat_draft_index())
	var run: Expedition = CombatManager.get_expedition()
	var not_an_exit: int = run.map.size() - 1   # el jefe, y desde el nodo 0 no se llega
	if run.current_exits().has(not_an_exit):
		not_an_exit = 0                         # volver al inicio tampoco vale
	assert_bool(CombatManager.select_node(not_an_exit)).is_false()
	assert_bool(CombatManager.is_in_encounter()).is_false()

# ── Atricion y permadeath entre nodos ────────────────────────────────

func test_a_wounded_survivor_marches_on_wounded() -> void:
	_launch()
	var hero: CombatUnit = _units_of_side(PLAYER)[0]
	hero.take_damage(5)
	var wounded_hp: int = hero.hp
	assert_bool(hero.is_alive()).is_true()

	_clear_and_advance()

	var next_board: Array = CombatManager.get_units()
	assert_bool(next_board.has(hero)).is_true()
	assert_int(hero.hp).is_equal(wounded_hp)
	assert_bool(hero.position.x >= 0).is_true()   # y ha vuelto a formar

func test_the_fallen_do_not_form_up_again_and_are_not_struck_off_yet() -> void:
	_launch()
	var doomed: CombatUnit = _units_of_side(PLAYER)[0]
	doomed.take_damage(doomed.max_hp * 10)

	_clear_and_advance()

	assert_bool(CombatManager.get_units().has(doomed)).is_false()
	assert_int(_units_of_side(PLAYER).size()).is_equal(2)
	# En casa todavia lo cuentan: la baja se liquida cuando la columna vuelve.
	assert_int(ArmyManager.get_count("infantry")).is_equal(2)
	assert_int(ArmyManager.get_count("artillery")).is_equal(1)
	assert_int(_total(CombatManager.get_units_on_expedition())).is_equal(3)

# ── Perder ───────────────────────────────────────────────────────────

func test_losing_ends_the_campaign_and_only_then_the_army_pays() -> void:
	_launch()
	var power_before: int = ArmyManager.get_power()
	var seen := [false, -1, {}, {}]
	var probe := func(result: int, rewards: Dictionary, casualties: Dictionary) -> void:
		seen[0] = true
		seen[1] = result
		seen[2] = rewards
		seen[3] = casualties
	EventBus.expedition_ended.connect(probe)
	# Hasta el ultimo golpe, el cuartel no ha perdido a nadie.
	_wipe(PLAYER)
	assert_int(ArmyManager.get_count("infantry")).is_equal(2)
	_settle()
	EventBus.expedition_ended.disconnect(probe)

	assert_bool(seen[0]).is_true()
	assert_int(int(seen[1])).is_equal(Expedition.RESULT_LOST)
	assert_int(int((seen[3] as Dictionary).get("infantry", 0))).is_equal(2)
	assert_int(int((seen[3] as Dictionary).get("artillery", 0))).is_equal(1)
	assert_int(ArmyManager.get_count("infantry")).is_equal(0)
	assert_int(ArmyManager.get_count("artillery")).is_equal(0)
	assert_int(ArmyManager.get_power()).is_less(power_before)
	assert_bool(CombatManager.has_active_expedition()).is_false()
	assert_bool(CombatManager.get_units_on_expedition().is_empty()).is_true()

func test_a_lost_campaign_still_reports_the_bill_for_the_ui() -> void:
	_launch()
	_lose_node()
	var result: Dictionary = CombatManager.get_last_result()
	assert_bool(bool(result["victory"])).is_false()
	assert_int(int(result.get("result", -1))).is_equal(Expedition.RESULT_LOST)
	assert_int(_total(result["casualties"])).is_equal(3)
	assert_int(int(result["morale_delta"])).is_less(0)

# ── Ganar al jefe ────────────────────────────────────────────────────

func test_beating_the_boss_wins_the_campaign_and_the_spoils_come_home() -> void:
	_launch()
	var run: Expedition = CombatManager.get_expedition()
	var seen := [false, -1, {}]
	var probe := func(result: int, rewards: Dictionary, _c: Dictionary) -> void:
		seen[0] = true
		seen[1] = result
		seen[2] = rewards
	EventBus.expedition_ended.connect(probe)
	# Del nodo 0 al jefe por la primera salida de cada nodo, sin perder a nadie.
	var steps := 0
	while CombatManager.has_active_expedition() and steps < 16:
		steps += 1
		if run.at_boss():
			_win_node()
		else:
			_clear_and_advance()
	EventBus.expedition_ended.disconnect(probe)

	assert_bool(seen[0]).is_true()
	assert_int(int(seen[1])).is_equal(Expedition.RESULT_WON)
	var rewards: Dictionary = seen[2]
	assert_int(int(rewards.get("gold", 0))).is_greater(0)
	assert_int(ResourceManager.get_amount(ResourceManager.Type.GOLD)).is_equal(int(rewards["gold"]))
	assert_int(ResourceManager.get_amount(ResourceManager.Type.WOOD)).is_equal(int(rewards.get("wood", 0)))
	# Nadie murio, nadie falta.
	assert_int(ArmyManager.get_count("infantry")).is_equal(2)
	assert_int(ArmyManager.get_count("artillery")).is_equal(1)
	assert_bool(CombatManager.has_active_expedition()).is_false()
	assert_bool(bool(CombatManager.get_last_result().get("boss_defeated", false))).is_true()

func test_the_spoils_are_paid_exactly_once() -> void:
	_launch()
	var run: Expedition = CombatManager.get_expedition()
	var steps := 0
	while CombatManager.has_active_expedition() and steps < 16:
		steps += 1
		if run.at_boss():
			_win_node()
		else:
			_clear_and_advance()
	var gold: int = ResourceManager.get_amount(ResourceManager.Type.GOLD)
	# Cerrar el ultimo tablero, como hara la UI, no vuelve a cobrar.
	CombatManager.end_encounter()
	assert_int(ResourceManager.get_amount(ResourceManager.Type.GOLD)).is_equal(gold)

# ── Abandonar ────────────────────────────────────────────────────────

func test_abandoning_keeps_the_spoils_and_the_survivors() -> void:
	_launch()
	_win_node()
	CombatManager.apply_draft(_stat_draft_index())
	var banked: Dictionary = CombatManager.get_expedition().rewards.duplicate()
	var seen := [false, -1]
	var probe := func(result: int, _rw: Dictionary, _c: Dictionary) -> void:
		seen[0] = true
		seen[1] = result
	EventBus.expedition_ended.connect(probe)
	assert_bool(CombatManager.abandon_expedition()).is_true()
	EventBus.expedition_ended.disconnect(probe)

	assert_bool(seen[0]).is_true()
	assert_int(int(seen[1])).is_equal(Expedition.RESULT_ABANDONED)
	assert_int(ResourceManager.get_amount(ResourceManager.Type.GOLD)).is_equal(int(banked.get("gold", 0)))
	assert_int(ArmyManager.get_count("infantry")).is_equal(2)
	assert_int(ArmyManager.get_count("artillery")).is_equal(1)
	assert_bool(CombatManager.has_active_expedition()).is_false()
	assert_bool(CombatManager.get_deployable_units().has("infantry")).is_true()

func test_abandoning_mid_battle_closes_the_board() -> void:
	_launch()
	assert_bool(CombatManager.is_in_encounter()).is_true()
	assert_bool(CombatManager.abandon_expedition()).is_true()
	assert_bool(CombatManager.is_in_encounter()).is_false()
	assert_bool(CombatManager.has_active_expedition()).is_false()
	assert_int(ArmyManager.get_count("infantry")).is_equal(2)

func test_you_cannot_abandon_what_is_not_there() -> void:
	assert_bool(CombatManager.abandon_expedition()).is_false()

# ── Las unidades que salieron no estan en casa (SC-004) ──────────────

func test_committed_units_are_locked_out_but_still_count_as_power() -> void:
	_given_army({"infantry": 4, "artillery": 1, "vehicle": 1})
	var power_before: int = ArmyManager.get_power()
	assert_bool(CombatManager.launch_expedition({"infantry": 2, "artillery": 1}, SEED)).is_true()

	var deployable: Dictionary = CombatManager.get_deployable_units()
	assert_int(int(deployable.get("infantry", 0))).is_equal(2)
	assert_bool(deployable.has("artillery")).is_false()
	assert_int(int(deployable.get("vehicle", 0))).is_equal(1)

	var garrison: Dictionary = CombatManager.get_garrison()
	assert_int(int(garrison.get("infantry", 0))).is_equal(2)
	assert_bool(garrison.has("artillery")).is_false()

	var away: Dictionary = CombatManager.get_units_on_expedition()
	assert_int(int(away.get("infantry", 0))).is_equal(2)
	assert_int(int(away.get("artillery", 0))).is_equal(1)
	assert_int(ArmyManager.get_power()).is_equal(power_before)

func test_the_fallen_stay_locked_out_until_the_column_returns() -> void:
	# Un caido ya no esta en casa ni puede volver a salir, pero ArmyManager aun lo
	# cuenta: si se dejara de descontar, el jugador podria "redesplegar" a un muerto.
	_given_army({"infantry": 4})
	CombatManager.launch_expedition({"infantry": 2}, SEED)
	_units_of_side(PLAYER)[0].take_damage(999)
	_clear_and_advance()
	assert_int(int(CombatManager.get_deployable_units().get("infantry", 0))).is_equal(2)
	assert_int(int(CombatManager.get_units_on_expedition().get("infantry", 0))).is_equal(2)

func test_everything_comes_home_when_the_campaign_ends() -> void:
	_given_army({"infantry": 4})
	CombatManager.launch_expedition({"infantry": 2}, SEED)
	_lose_node()
	assert_int(int(CombatManager.get_deployable_units().get("infantry", 0))).is_equal(2)
	assert_int(ArmyManager.get_count("infantry")).is_equal(2)

# ── Guardar a mitad de campana (D6) ──────────────────────────────────

func test_the_campaign_survives_a_save_round_trip() -> void:
	_launch()
	var hero: CombatUnit = _units_of_side(PLAYER)[0]
	hero.take_damage(7)
	_clear_and_advance()
	var run: Expedition = CombatManager.get_expedition()
	var node_now: int = run.current_node
	var hero_uid: int = hero.uid
	var hero_hp: int = hero.hp

	var data: Dictionary = CombatManager.get_save_data()
	assert_bool(data.has("seed")).is_true()
	assert_bool(data.has("map")).is_false()   # el mapa se regenera, no se guarda

	CombatManager.end_encounter()
	CombatManager.reset()
	assert_bool(CombatManager.has_active_expedition()).is_false()

	var resumed := [false, -1]
	var probe := func(id: int) -> void:
		resumed[0] = true
		resumed[1] = id
	EventBus.expedition_resumed.connect(probe)
	CombatManager.load_save_data(data)
	EventBus.expedition_resumed.disconnect(probe)

	assert_bool(resumed[0]).is_true()
	assert_int(int(resumed[1])).is_equal(run.id)
	assert_bool(CombatManager.has_active_expedition()).is_true()
	var loaded: Expedition = CombatManager.get_expedition()
	assert_array(loaded.cleared_indices()).is_equal([0])
	assert_int(loaded.current_node).is_equal(node_now)
	assert_int(loaded.map.size()).is_equal(run.map.size())
	# El tablero a medias no se guarda: se reanuda en el mapa (D6)...
	assert_bool(CombatManager.is_in_encounter()).is_false()
	# ...y el lockout sigue en pie.
	assert_int(_total(CombatManager.get_units_on_expedition())).is_equal(3)
	assert_bool(CombatManager.get_deployable_units().is_empty()).is_true()
	# Volver a entrar despliega el nodo desde cero, con el daño que se traia.
	assert_bool(CombatManager.enter_current_node()).is_true()
	assert_bool(CombatManager.is_in_encounter()).is_true()
	var back: CombatUnit = CombatManager.get_encounter().get_unit(hero_uid)
	assert_object(back).is_not_null()
	assert_int(back.hp).is_equal(hero_hp)

func test_a_card_left_on_the_table_is_offered_again_after_loading() -> void:
	_launch()
	_win_node()
	var before: Array = CombatManager.get_draft_options()
	var data: Dictionary = CombatManager.get_save_data()
	CombatManager.end_encounter()
	CombatManager.reset()

	var offered := [false, []]
	var probe := func(options: Array) -> void:
		offered[0] = true
		offered[1] = options
	EventBus.draft_offered.connect(probe)
	CombatManager.load_save_data(data)
	EventBus.draft_offered.disconnect(probe)

	assert_bool(offered[0]).is_true()
	assert_bool(CombatManager.has_pending_draft()).is_true()
	# Mismas cartas: salen de la semilla y del nodo.
	assert_array(offered[1]).is_equal(before)
	assert_bool(CombatManager.enter_current_node()).is_false()   # el nodo esta limpio
	assert_bool(CombatManager.apply_draft(0)).is_true()

func test_a_save_from_before_expeditions_loads_with_nothing_to_resume() -> void:
	var resumed := [false]
	var probe := func(_id: int) -> void: resumed[0] = true
	EventBus.expedition_resumed.connect(probe)
	CombatManager.load_save_data({})
	EventBus.expedition_resumed.disconnect(probe)
	assert_bool(resumed[0]).is_false()
	assert_bool(CombatManager.has_active_expedition()).is_false()
	assert_bool(CombatManager.get_save_data().is_empty()).is_true()

func test_a_finished_campaign_in_the_save_is_not_resumed() -> void:
	_launch()
	var data: Dictionary = CombatManager.get_save_data()
	data["state"] = Expedition.State.DEFEATED
	CombatManager.end_encounter()
	CombatManager.reset()
	CombatManager.load_save_data(data)
	assert_bool(CombatManager.has_active_expedition()).is_false()

func test_without_a_campaign_there_is_nothing_to_save() -> void:
	assert_bool(CombatManager.get_save_data().is_empty()).is_true()

func test_a_new_game_forgets_the_campaign() -> void:
	_launch()
	CombatManager.end_encounter()
	CombatManager.reset()
	assert_bool(CombatManager.has_active_expedition()).is_false()
	assert_bool(CombatManager.has_pending_draft()).is_false()
	assert_int(int(CombatManager.get_deployable_units().get("infantry", 0))).is_equal(2)
