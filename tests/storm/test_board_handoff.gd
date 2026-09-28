extends GdUnitTestSuite
## Los relevos de tablero: el rato en que un encuentro acaba y otro empieza, o
## en que el jugador lee un parte con el tablero todavia en pantalla.
##
## Aqui vivian cuatro fallos que dejaban la partida sin final, y ninguno se veia
## desde los modelos puros: todos nacen de que "hay pelea" y "hay tablero" no son
## lo mismo, y de que cerrar una oleada del asedio abre la siguiente dentro de la
## misma llamada.
##
## Toca los autoloads de verdad; cada caso los deja como estaban.

var _storm_saved: Dictionary = {}
var _army_saved: Dictionary = {}
var _population_saved: Dictionary = {}
var _resources_saved: Dictionary = {}
var _progression_saved: Dictionary = {}

var _tithes: Array = []        # [repelled, taken] por emision
var _auto_defenses: Array = []
var _audit_lost: int = 0

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
	_tithes = []
	_auto_defenses = []
	_audit_lost = 0
	EventBus.tithe_resolved.connect(_on_tithe)
	EventBus.defense_auto_resolved.connect(_on_auto_defense)
	EventBus.final_audit_lost.connect(_on_audit_lost)

func after_test() -> void:
	EventBus.tithe_resolved.disconnect(_on_tithe)
	EventBus.defense_auto_resolved.disconnect(_on_auto_defense)
	EventBus.final_audit_lost.disconnect(_on_audit_lost)
	CombatManager.reset()
	ProgressionManager.final_audit = null
	ProgressionManager.load_save_data(_progression_saved)
	StormManager.load_save_data(_storm_saved)
	ArmyManager.load_save_data(_army_saved)
	PopulationManager.load_save_data(_population_saved)
	ResourceManager.set_amounts(_resources_saved)

func _on_tithe(repelled: bool, taken: Dictionary) -> void:
	_tithes.append([repelled, taken])

func _on_auto_defense(victory: bool, rounds: int, summary: Dictionary) -> void:
	_auto_defenses.append([victory, rounds, summary])

func _on_audit_lost(_wave: int) -> void:
	_audit_lost += 1

func _resource_amounts() -> Dictionary:
	return {
		"gold": ResourceManager.get_amount(ResourceManager.Type.GOLD),
		"wood": ResourceManager.get_amount(ResourceManager.Type.WOOD),
		"steel": ResourceManager.get_amount(ResourceManager.Type.STEEL),
		"oil": ResourceManager.get_amount(ResourceManager.Type.OIL),
	}

func _given_army(units: Dictionary) -> void:
	ArmyManager.load_save_data({"units": units, "training": [], "upkeep_accum": 0.0})

## Deja el encuentro abierto resuelto sin cerrarlo: es el estado exacto en que
## el jugador esta leyendo el parte. Cerrar el turno es lo que hace al tablero
## mirar si ya acabo, igual que en partida.
func _resolve_open_board(player_wins: bool) -> void:
	var loser: int = Encounter.ENEMY if player_wins else Encounter.PLAYER
	for unit in CombatManager.get_units():
		if unit.side == loser and unit.is_alive():
			unit.take_damage(unit.max_hp * 10)
	CombatManager.end_turn()

# ── "Hay tablero" no es "hay pelea" ──────────────────────────────────

func test_a_resolved_board_still_counts_as_open() -> void:
	_given_army({"infantry": 3})
	CombatManager.start_skirmish({"infantry": 2})
	_resolve_open_board(true)
	# La pelea acabo, pero el parte sigue en pantalla.
	assert_bool(CombatManager.is_in_encounter()).is_false()
	assert_bool(CombatManager.is_board_open()).is_true()

func test_a_tithe_never_opens_a_board_over_an_unread_report() -> void:
	_given_army({"infantry": 4})
	CombatManager.start_skirmish({"infantry": 2})
	_resolve_open_board(true)
	var board: Encounter = CombatManager.get_encounter()

	StormManager._begin_tithe(1)

	# El tablero que el jugador esta leyendo sigue siendo el mismo objeto: la
	# defensa se resolvio a ciegas en vez de borrarle el parte de delante.
	assert_object(CombatManager.get_encounter()).is_same(board)
	assert_array(_auto_defenses).is_not_empty()

# ── La expedicion no deja el tablero colgado ─────────────────────────

func test_winning_the_boss_closes_the_board_it_was_fought_on() -> void:
	_given_army({"infantry": 3})
	assert_bool(CombatManager.launch_expedition({"infantry": 3})).is_true()

	var guard := 0
	while CombatManager.has_active_expedition() and guard < 40:
		guard += 1
		if CombatManager.get_encounter() == null:
			# Entre nodos: tomar carta si toca y seguir por la primera salida.
			if CombatManager.has_pending_draft():
				CombatManager.apply_draft(0)
			var exits: Array = CombatManager.get_expedition().current_exits()
			if exits.is_empty():
				break
			CombatManager.select_node(int(exits[0]))
			continue
		_resolve_open_board(true)
		if CombatManager.has_active_expedition():
			CombatManager.end_encounter()

	# Gane el jefe o no, al cerrarse la campana no puede quedar tablero colgado:
	# con uno abierto, todo Diezmo posterior se resuelve a ciegas y el asedio se
	# da por perdido sin jugarse.
	assert_bool(CombatManager.has_active_expedition()).is_false()
	assert_bool(CombatManager.is_board_open()).is_false()

func test_losing_an_expedition_closes_the_board_too() -> void:
	_given_army({"infantry": 3})
	assert_bool(CombatManager.launch_expedition({"infantry": 3})).is_true()
	_resolve_open_board(false)

	assert_bool(CombatManager.has_active_expedition()).is_false()
	assert_bool(CombatManager.is_board_open()).is_false()

# ── El Diezmo no cobra mientras se pelea la Auditoria Final ──────────

func test_the_tithe_stands_down_while_the_siege_is_being_fought() -> void:
	_given_army({"infantry": 4})
	assert_bool(ProgressionManager.summon_final_audit()).is_true()
	assert_bool(ProgressionManager.begin_final_audit()).is_true()
	assert_bool(ProgressionManager.is_final_audit_active()).is_true()
	var before: Dictionary = _resource_amounts()
	var army_before: int = ArmyManager.get_total_units()

	StormManager._begin_tithe(GameConfig.storm_severity_max)

	# Ni se cobra, ni se alista dos veces a la misma guarnicion.
	assert_dict(_resource_amounts()).is_equal(before)
	assert_int(ArmyManager.get_total_units()).is_equal(army_before)
	assert_int(_audit_lost).is_equal(0)
	# Y la fase se cierra igual, para que el ciclo siga corriendo.
	assert_array(_tithes).is_not_empty()
	assert_bool(bool(_tithes[0][0])).is_true()
	assert_dict(_tithes[0][1]).is_empty()

func test_a_summoned_but_unbegun_siege_does_not_stop_the_tithe() -> void:
	_given_army({"infantry": 2})
	assert_bool(ProgressionManager.summon_final_audit()).is_true()
	assert_bool(ProgressionManager.is_final_audit_active()).is_false()

	StormManager._begin_tithe(1)

	# Convocarla no es pelearla: hasta que el jugador la hace bajar, los
	# Tasadores siguen viniendo y la guarnicion sale a recibirlos.
	assert_bool(CombatManager.is_board_open()).is_true()

# ── El relevo de oleadas visto desde la pantalla ─────────────────────

## Cerrar el parte de una oleada ABRE la siguiente, y lo hace dentro de la misma
## llamada a end_encounter(): report_audit_wave encadena hasta encounter_started
## sin soltar el hilo. Si la pantalla sigue de largo tras esa llamada, esconde el
## tablero que se acaba de abrir y el asedio se queda sin jugar: el jugador ve la
## base, sin tablero y sin boton que le devuelva al asedio.
func test_closing_a_wave_report_leaves_the_next_wave_on_screen() -> void:
	_given_army({"infantry": 4, "artillery": 2})
	assert_bool(ProgressionManager.summon_final_audit()).is_true()
	var waves: int = ProgressionManager.final_audit.wave_count()
	if waves < 2:
		return  # Un asedio de una sola oleada no tiene relevo que probar.
	assert_bool(ProgressionManager.begin_final_audit()).is_true()

	var screen: CanvasLayer = auto_free(load("res://scenes/ui/BattleScreen.tscn").instantiate())
	add_child(screen)
	# El tablero de la oleada ya estaba abierto cuando la pantalla entro: se le
	# pone al dia como haria la senal que se perdio.
	screen._on_encounter_started(0, false)
	assert_bool(screen._board_open).is_true()

	_resolve_open_board(true)
	screen._close_board()

	# La oleada siguiente esta en el tablero y en pantalla.
	assert_bool(CombatManager.is_in_encounter()).is_true()
	assert_bool(screen._board_open).is_true()
	assert_bool(screen.visible).is_true()
	assert_int(_audit_lost).is_equal(0)
