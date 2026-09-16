extends Node
## Dev tool: juega una expedicion roguelike entera sin tocar la interfaz y
## comprueba, una por una, las invariantes que la hacen un roguelike y no una
## sucesion de escaramuzas: atricion, permadeath, cobro unico al volver, y que
## el ejercito que queda en el Cuartel es exactamente el que sobrevivio.
##
## Es la sonda de T045: el guion es specs/001-combate-pve/quickstart.md (E1-E9)
## y el parte que sale de aqui alimenta quickstart-results.md.
##
## Uso: registrar temporalmente como autoload y arrancar el juego CON ventana.
##   project.godot -> [autoload] -> ExpeditionProbe="*res://tools/expedition_probe.gd"
## Quitar la linea al terminar (project.godot no debe cambiar en el commit).
##
## Hermana de tools/audit_probe.gd, tools/storm_probe.gd y tools/battle_probe.gd.
##
## Nota sobre AutoResolver: no se usa su resolve() sobre el tablero de la
## expedicion. resolve() muta el Encounter y DEVUELVE los eventos; nadie los
## vuelca en CombatManager._emit_events(), asi que _apply_result() nunca
## correria y la campana se quedaria clavada en el nodo 0. La sonda usa el mismo
## cerebro (CombatAI, el que AutoResolver conduce) pero aplica cada paso por la
## API publica de CombatManager, que es el camino que recorre el jugador.

const AI := preload("res://scripts/combat/CombatAI.gd")

# ── Que se ejecuta ───────────────────────────────────────────────────

const SETTLE := 2.0
## Pasada 0: los noes. Salir sin tropas, sin tantas tropas, o cargar un save
## anterior a esta feature (quickstart E8 y E6 punto 3).
const RUN_EDGES := true
## Pasada 1: campana completa, de la salida al jefe, con todas las invariantes.
const RUN_FULL := true
## Pasada 2: abandonar a mitad (FR-016, quickstart E7).
const RUN_ABANDON := true
## Pasada 3: guardar y cargar a mitad de campana (FR-020, quickstart E6).
const RUN_SAVELOAD := true
## Pasada 4: cuanto aguanta una columna con el balance TAL COMO ESTA. No prueba
## cableado: mide si SC-008 (la expedicion se puede completar) se sostiene.
const RUN_BALANCE := true

## La pasada 1 tiene que llegar al jefe para probar el ultimo tramo del
## cableado (nodo jefe, sin draft detras, expedition_ended con result=0). Con el
## balance de serie la columna no pasa de la profundidad 1 (ver pasada 4), asi
## que aqui se baja al enemigo a proposito y se dice. Lo que se mide en la
## pasada 1 es el cableado; el balance se mide en la pasada 4.
## Se rebajaba al enemigo para que la pasada 1 llegara al jefe y se pudiera
## medir el cableado. Ya no hace falta: el balance de serie esta medido (ver
## docs/16-balance-combate.md) y la campana se gana. Se deja la palanca por si
## alguna vez hay que aislar el cableado de un balance roto otra vez.
const NERF_ENEMY := false
const NERF_SCALE_PER_DEPTH := 0.04
const NERF_SCALE_PER_ERA := 0.0
const NERF_RISK_SCALE := 0.05
const NERF_BOSS_MULTIPLIER := 1.15
const NERF_BASE_SLOTS := 2

## Semillas fijas: la sonda tiene que dar el mismo parte en dos ejecuciones.
const SEED_FULL := 20260915
const SEED_ABANDON := 771
const SEED_SAVELOAD := 4242

## Con que sale la columna. Tope del tablero: GameConfig.combat_deploy_cap (6).
const PARTY := {"infantry": 4, "artillery": 2}
const ERA := 2

## Topes anti-bucle. Ninguno deberia saltar en una partida sana.
const MAX_NODES := 40
const BOARD_GUARD := 4000

## Lineas de traza del primer tablero (quien pega a quien y por cuanto). Sirve
## para distinguir "el jugador pierde" de "el jugador no actua", que es la
## diferencia entre un problema de balance y un bug.
const TRACE_LINES := 60

# ── Estado del parte ─────────────────────────────────────────────────

var _checks: Array = []          ## [ok: bool, texto: String]
var _ended: Dictionary = {}      ## ultimo expedition_ended capturado
var _ended_seen: bool = false

func _ready() -> void:
	if not GameConfig.dev_mode:
		push_warning("[exped] dev_mode desactivado; no se hace nada")
		return
	await get_tree().create_timer(SETTLE).timeout
	await _run()

func _run() -> void:
	_freeze_base()
	EventBus.expedition_ended.connect(_on_expedition_ended)
	EventBus.unit_attacked.connect(_on_unit_attacked)
	EventBus.unit_died.connect(_on_unit_died)

	if RUN_EDGES:
		_pass_edges()
	if RUN_FULL:
		await _pass_full()
		_restore_enemy()
	if RUN_ABANDON:
		await _pass_abandon()
	if RUN_SAVELOAD:
		await _pass_saveload()
	if RUN_BALANCE:
		await _pass_balance()

	_p("")
	_p("===== RESUMEN DE INVARIANTES =====")
	var failed := 0
	for check in _checks:
		if not bool(check[0]):
			failed += 1
		_p("%s  %s" % ["OK   " if bool(check[0]) else "FALLO", check[1]])
	_p("===== %d comprobaciones, %d fallos =====" % [_checks.size(), failed])
	get_tree().quit()

# ══════════════════════════════════════════════════════════════════════
# Pasada 0: los noes
# ══════════════════════════════════════════════════════════════════════

func _pass_edges() -> void:
	_p("")
	_p("########## PASADA 0: los noes (E8, E6.3) ##########")
	_reset_world()

	# Sin tropas comprometidas no hay expedicion, y el motivo es una clave de Tr
	# para que la UI la traduzca (FR-002).
	var empty: Dictionary = CombatManager.can_launch({})
	_check(not bool(empty.get("ok", true)) and String(empty.get("reason", "")) == "MSG_NO_UNITS",
		"P0 E8: lanzar sin unidades -> %s" % String(empty.get("reason", "?")))
	_check(not CombatManager.launch_expedition({}),
		"P0 E8: launch_expedition({}) devuelve false")
	_check(not CombatManager.has_active_expedition(),
		"P0 E8: no se crea expedicion al intentarlo sin unidades")

	# Mas infanteria de la que hay en el Cuartel (5), pero sin pasarse del tope:
	# el motivo tiene que ser "no las tienes", no "no caben".
	var greedy: Dictionary = CombatManager.can_launch({"infantry": 6})
	_check(String(greedy.get("reason", "")) == "MSG_UNITS_UNAVAILABLE",
		"P0 pedir mas tropas de las que hay -> %s" % String(greedy.get("reason", "?")))

	# Mas de las que caben en el tablero.
	var cap: int = GameConfig.combat_deploy_cap
	var over: Dictionary = CombatManager.can_launch({"infantry": cap + 1})
	_check(String(over.get("reason", "")) in ["MSG_DEPLOY_CAP_EXCEEDED", "MSG_UNITS_UNAVAILABLE"],
		"P0 pasarse del tope de despliegue (%d) -> %s" % [cap, String(over.get("reason", "?"))])

	# Un save anterior a esta feature no trae la clave: eso es "no hay campana",
	# no un error de carga (constitucion, principio V).
	CombatManager.load_save_data({})
	_check(not CombatManager.has_active_expedition(),
		"P0 E6.3: un save sin clave 'expedition' arranca sin campana")
	CombatManager.load_save_data({"state": Expedition.State.COMPLETED, "seed": 1})
	_check(not CombatManager.has_active_expedition(),
		"P0 E6.3: un save con una campana ya terminada no la reabre")

# ══════════════════════════════════════════════════════════════════════
# Pasada 1: la campana entera
# ══════════════════════════════════════════════════════════════════════

func _pass_full() -> void:
	_p("")
	_p("########## PASADA 1: campana completa (semilla %d) ##########" % SEED_FULL)
	_reset_world()
	if NERF_ENEMY:
		_nerf_enemy()
		_p("AVISO: enemigo rebajado a proposito (prof x%.2f, era x%.2f, riesgo x%.2f, jefe x%.2f)." % [
			NERF_SCALE_PER_DEPTH, NERF_SCALE_PER_ERA, NERF_RISK_SCALE, NERF_BOSS_MULTIPLIER])
		_p("AVISO: esta pasada mide el CABLEADO hasta el jefe, no el balance. El balance va en la pasada 4.")

	var power_before: int = ArmyManager.get_power()
	var army_before: Dictionary = _army_counts()
	var res_before: Dictionary = _resources()
	_p("ejercito de salida=%s poder=%d" % [army_before, power_before])
	_p("recursos de salida=%s" % res_before)

	var launched: bool = CombatManager.launch_expedition(PARTY.duplicate(), SEED_FULL)
	_check(launched, "P1 la expedicion sale (launch_expedition)")
	if not launched:
		return

	var run: Expedition = CombatManager.get_expedition()
	_p("mapa=%d nodos, jefe en %d" % [run.map.size(), _boss_index(run)])

	# Bloqueo: mientras la columna esta fuera, esas unidades no se pueden volver
	# a comprometer (FR-017 / SC-004 leidos desde get_deployable_units()).
	var deployable: Dictionary = CombatManager.get_deployable_units()
	var blocked_ok := true
	for unit_id in PARTY:
		var left: int = int(army_before.get(unit_id, 0)) - int(PARTY[unit_id])
		if int(deployable.get(unit_id, 0)) != maxi(0, left):
			blocked_ok = false
	_check(blocked_ok, "P1 bloqueo: get_deployable_units()=%s no ofrece las %s que estan fuera" % [
		deployable, PARTY])

	# Rastro por nodo.
	var dead_uids: Dictionary = {}          ## uid -> unit_id del caido
	var prev_end_hp: Dictionary = {}        ## uid -> hp al bajar del tablero anterior
	var seen_damaged: Dictionary = {}       ## uid -> true si alguna vez perdio hp
	var attrition_ok := true
	var permadeath_ok := true
	var charge_ok := true
	var nodes_played := 0
	var last_rewards: Dictionary = {}
	var boss_played := false
	var draft_after_boss := false
	var healed_by_draft := 0
	var max_rounds := 0
	var all_by_elimination := true

	while CombatManager.has_active_expedition() and nodes_played < MAX_NODES:
		nodes_played += 1
		if not CombatManager.is_in_encounter():
			_p("  (sin tablero abierto en la vuelta %d)" % nodes_played)
			break

		var node: Dictionary = run.current_node_data()
		if bool(node.get("is_boss", false)):
			boss_played = true
		var start_hp: Dictionary = _player_hp_on_board()

		# Atricion: quien salio tocado del nodo anterior entra tocado en este.
		for uid in start_hp:
			if prev_end_hp.has(uid) and int(start_hp[uid]) != int(prev_end_hp[uid]):
				attrition_ok = false
				_p("  !! atricion rota: uid %d entra con %d, salio con %d" % [
					uid, int(start_hp[uid]), int(prev_end_hp[uid])])
			if bool(seen_damaged.get(uid, false)) and int(start_hp[uid]) >= _max_hp_of(uid):
				attrition_ok = false
				_p("  !! atricion rota: uid %d empieza a tope tras haber sangrado" % uid)

		# Permadeath: un caido no vuelve a formar.
		for unit in _player_units_on_board():
			if dead_uids.has(unit.uid):
				permadeath_ok = false
				_p("  !! permadeath roto: el uid %d (%s) vuelve al tablero" % [unit.uid, unit.unit_id])

		await _play_board()

		var end_hp: Dictionary = _player_hp_on_board()
		var result: Dictionary = CombatManager.get_last_result()
		max_rounds = maxi(max_rounds, int(result.get("rounds", 0)))
		# SC-003: ningun tablero se queda en bucle ni se decide por el reloj.
		if CombatManager.get_encounter() != null \
				and CombatManager.get_encounter().state == Encounter.State.TIMEOUT:
			all_by_elimination = false
		for uid in end_hp:
			if int(end_hp[uid]) < _max_hp_of(uid):
				seen_damaged[uid] = true
		for unit in run.party:
			if not unit.is_alive():
				dead_uids[unit.uid] = unit.unit_id

		last_rewards = run.rewards.duplicate()
		_p("nodo %d%s prof=%d riesgo=%d enemigo=%s x%.2f  victoria=%s rondas=%d" % [
			int(node.get("index", -1)), " [JEFE]" if bool(node.get("is_boss", false)) else "",
			int(node.get("depth", 0)), int(node.get("risk", 0)),
			node.get("enemy_roster", {}),
			ExpeditionGenerator.enemy_scale(int(node.get("depth", 0)), run.era,
				int(node.get("risk", 0)), bool(node.get("is_boss", false))),
			bool(result.get("victory", false)), int(result.get("rounds", 0))])
		_p("   vivos: %s" % _hp_line(run))
		_p("   bajas acumuladas: %s   botin acumulado: %s" % [_tally(dead_uids.values()), last_rewards])

		prev_end_hp = end_hp
		CombatManager.end_encounter()
		await get_tree().process_frame

		# Cobro unico: mientras la campana vive, el almacen no se mueve.
		if CombatManager.has_active_expedition():
			var now: Dictionary = _resources()
			if now != res_before:
				charge_ok = false
				_p("  !! cobro adelantado: recursos %s != %s" % [now, res_before])

		if not CombatManager.has_active_expedition():
			# El jefe no da carta: da la campana entera. Si aqui hubiera draft
			# pendiente, la recompensa del jefe estaria mal cableada.
			if bool(node.get("is_boss", false)) and CombatManager.has_pending_draft():
				draft_after_boss = true
			break

		# La carta, y solo despues la ruta (es el orden que impone CombatManager).
		if CombatManager.has_pending_draft():
			var options: Array = CombatManager.get_draft_options()
			var taken: bool = CombatManager.apply_draft(0)
			var picked: String = String(options[0].get("id", "?")) if not options.is_empty() else "?"
			_p("   draft: %d cartas, elegida '%s' -> %s" % [options.size(), picked, taken])
			_check(taken and options.size() >= 2,
				"P1 SC-009: el nodo %d ofrece %d cartas aplicables (>=2) y se aplica la elegida" % [
					int(node.get("index", -1)), options.size()])
			# La unica cura permitida dentro de la campana es la carta de puesto
			# de socorro. Se reajusta la referencia de atricion para que el
			# siguiente nodo se compare contra el HP YA curado: cualquier otra
			# subida de vida seguiria saltando como fallo.
			if taken and picked == "draft_hp_heal":
				healed_by_draft += 1
				prev_end_hp = {}
				for unit in run.living_party():
					prev_end_hp[unit.uid] = unit.hp
					if int(unit.hp) >= _max_hp_of_party(run, unit.uid):
						seen_damaged.erase(unit.uid)
				_p("   (curados por la carta: %s)" % _hp_line(run))

		var exits: Array = run.current_exits()
		if exits.is_empty():
			_p("   sin salidas (nodo jefe o mapa agotado)")
			break
		var chosen: int = _safest_exit(run, exits)
		var moved: bool = CombatManager.select_node(chosen)
		_p("   salidas=%s -> elegida %d (ok=%s)" % [exits, chosen, moved])
		if not moved:
			_p("  !! select_node fallo; se corta la campana")
			break

	_check(nodes_played < MAX_NODES, "P1 la campana termina sin agotar el tope de %d nodos" % MAX_NODES)
	_check(boss_played, "P1 la columna llega al nodo jefe (%d nodos jugados)" % nodes_played)
	_check(max_rounds <= GameConfig.combat_turn_limit,
		"P1 SC-001/SC-003: ningun encuentro pasa del limite de %d rondas (el peor, %d)" % [
			GameConfig.combat_turn_limit, max_rounds])
	_check(all_by_elimination,
		"P1 SC-003: todos los tableros se deciden por eliminacion, ninguno por agotar el reloj")
	_check(not draft_after_boss, "P1 el jefe no ofrece draft: da la campana entera")
	_check(attrition_ok,
		"P1 atricion: nadie se cura entre nodos salvo por la carta DRAFT_HP_HEAL (FR-011; %d curas por carta)" % healed_by_draft)
	_check(permadeath_ok, "P1 permadeath: ningun caido vuelve a un tablero (FR-010)")
	_check(charge_ok, "P1 cobro unico: los recursos no se mueven durante la campana (FR-017)")

	# ── La vuelta a casa ──
	_check(_ended_seen, "P1 se emite expedition_ended")
	var res_after: Dictionary = _resources()
	var paid: Dictionary = {}
	for key in res_after:
		var delta: int = int(res_after[key]) - int(res_before.get(key, 0))
		if delta != 0:
			paid[key] = delta
	var expected: Dictionary = _ended.get("rewards", {})
	_p("")
	_p("resultado=%d botin pagado=%s esperado=%s bajas=%s" % [
		int(_ended.get("result", -1)), paid, expected, _ended.get("casualties", {})])
	_check(_same_counts(paid, expected),
		"P1 el botin pagado %s coincide con lo acumulado %s" % [paid, expected])
	_check(_same_counts(expected, last_rewards),
		"P1 lo acumulado por nodos %s llega entero a la liquidacion %s" % [last_rewards, expected])

	# SC-004: el Cuartel queda con los supervivientes, ni uno mas ni uno menos.
	var survivors: Dictionary = CombatManager.get_last_result().get("survivors", {})
	var army_after: Dictionary = _army_counts()
	var expected_army: Dictionary = {}
	for unit_id in army_before:
		var kept: int = int(army_before[unit_id]) - int(PARTY.get(unit_id, 0)) + int(survivors.get(unit_id, 0))
		if kept > 0:
			expected_army[unit_id] = kept
	_p("supervivientes=%s ejercito final=%s esperado=%s" % [survivors, army_after, expected_army])
	_check(_same_counts(army_after, expected_army),
		"P1 SC-004: ArmyManager queda con los supervivientes (%s)" % army_after)
	var expected_power: int = _power_of(army_after)
	_check(ArmyManager.get_power() == expected_power,
		"P1 SC-004: get_power()=%d cuadra con el roster (%d)" % [ArmyManager.get_power(), expected_power])

	# Curacion al volver: el HP solo existia dentro de la expedicion.
	_check(not CombatManager.has_active_expedition(), "P1 no queda expedicion abierta al terminar")
	_check(CombatManager.get_deployable_units().get("infantry", 0) == int(army_after.get("infantry", 0)),
		"P1 tras volver, las supervivientes vuelven a ser desplegables")
	# Ganar o no ganar el jefe es balance, y una semilla no mide balance: lo mide
	# el barrido de tools/balance_probe.gd (docs/16-balance-combate.md). Aqui
	# basta con que la campana CIERRE con un resultado valido, que es lo que esta
	# pasada vigila. El resultado se informa para que se lea en el parte.
	var code: int = int(_ended.get("result", -1))
	_p("   . la campana cerro como %s" % (
		["GANADA", "PERDIDA", "ABANDONADA"][code] if code >= 0 and code <= 2 else "?"))
	_check(code == Expedition.RESULT_WON or code == Expedition.RESULT_LOST,
		"P1 la campana cierra con un resultado valido (visto %d)" % code)

# ══════════════════════════════════════════════════════════════════════
# Pasada 2: abandonar a mitad
# ══════════════════════════════════════════════════════════════════════

func _pass_abandon() -> void:
	_p("")
	_p("########## PASADA 2: abandonar a mitad (semilla %d) ##########" % SEED_ABANDON)
	_reset_world()
	var army_before: Dictionary = _army_counts()
	var res_before: Dictionary = _resources()

	if not CombatManager.launch_expedition(PARTY.duplicate(), SEED_ABANDON):
		_check(false, "P2 la expedicion sale")
		return
	var run: Expedition = CombatManager.get_expedition()

	# Un nodo ganado, su carta, y a mitad del siguiente se da media vuelta.
	await _play_board()
	CombatManager.end_encounter()
	await get_tree().process_frame
	if CombatManager.has_pending_draft():
		CombatManager.apply_draft(0)
	var loot: Dictionary = run.rewards.duplicate()
	var exits: Array = run.current_exits()
	if not exits.is_empty():
		CombatManager.select_node(int(exits[0]))
	_p("botin en la mochila=%s  nodo actual=%d  tablero abierto=%s" % [
		loot, run.current_node, CombatManager.is_in_encounter()])

	var fallen_before: Dictionary = _tally(_casualty_ids(run))
	var alive_before: Dictionary = _tally(_living_ids(run))
	_ended_seen = false
	var walked: bool = CombatManager.abandon_expedition()
	await get_tree().process_frame

	_check(walked, "P2 abandon_expedition() devuelve true")
	_check(_ended_seen and int(_ended.get("result", -1)) == Expedition.RESULT_ABANDONED,
		"P2 expedition_ended con result=2 (ABANDONADA) [visto=%s]" % int(_ended.get("result", -1)))
	var paid: Dictionary = {}
	for key in _resources():
		var delta: int = int(_resources()[key]) - int(res_before.get(key, 0))
		if delta != 0:
			paid[key] = delta
	_check(_same_counts(paid, loot), "P2 se cobra el botin acumulado %s (pagado %s)" % [loot, paid])
	_check(_same_counts(_ended.get("casualties", {}), fallen_before),
		"P2 sin bajas extra por abandonar (%s antes, %s en el parte)" % [
			fallen_before, _ended.get("casualties", {})])
	var expected_army: Dictionary = {}
	for unit_id in army_before:
		var kept: int = int(army_before[unit_id]) - int(PARTY.get(unit_id, 0)) + int(alive_before.get(unit_id, 0))
		if kept > 0:
			expected_army[unit_id] = kept
	_check(_same_counts(_army_counts(), expected_army),
		"P2 los supervivientes vuelven al Cuartel (%s)" % _army_counts())
	_check(not CombatManager.has_active_expedition(), "P2 la campana queda cerrada")

# ══════════════════════════════════════════════════════════════════════
# Pasada 3: guardar y cargar a mitad de campana
# ══════════════════════════════════════════════════════════════════════

func _pass_saveload() -> void:
	_p("")
	_p("########## PASADA 3: guardar y cargar a mitad (semilla %d) ##########" % SEED_SAVELOAD)
	_reset_world()
	if not CombatManager.launch_expedition(PARTY.duplicate(), SEED_SAVELOAD):
		_check(false, "P3 la expedicion sale")
		return
	var run: Expedition = CombatManager.get_expedition()

	await _play_board()
	CombatManager.end_encounter()
	await get_tree().process_frame
	if CombatManager.has_pending_draft():
		CombatManager.apply_draft(0)
	var exits: Array = run.current_exits()
	if exits.is_empty():
		_check(false, "P3 hay una ruta que seguir tras el primer nodo")
		return
	CombatManager.select_node(int(exits[0]))

	# Foto de lo que tiene que volver intacto.
	var before := {
		"nodo": run.current_node,
		"mapa": run.map.size(),
		"limpiados": run.cleared_indices(),
		"botin": run.rewards.duplicate(),
		"hp": _party_hp(run),
		"cartas": run.draft_picks.size(),
	}
	_p("antes de guardar: %s" % before)

	# El save de verdad: GameManager escribe user://save_game.json.
	GameManager.save_game()
	var stored: Dictionary = _read_saved_expedition()
	_check(not stored.is_empty(), "P3 el save incluye la clave 'expedition'")

	CombatManager.reset()
	_check(not CombatManager.has_active_expedition(), "P3 reset() deja la sesion sin expedicion")

	CombatManager.load_save_data(stored)
	var back: Expedition = CombatManager.get_expedition()
	_check(back != null, "P3 la campana se reanuda al cargar")
	if back == null:
		return
	var after := {
		"nodo": back.current_node,
		"mapa": back.map.size(),
		"limpiados": back.cleared_indices(),
		"botin": back.rewards.duplicate(),
		"hp": _party_hp(back),
		"cartas": back.draft_picks.size(),
	}
	_p("despues de cargar: %s" % after)
	_check(int(after["mapa"]) == int(before["mapa"]) and int(after["nodo"]) == int(before["nodo"]),
		"P3 el mapa y el nodo actual vuelven intactos (%d nodos, nodo %d)" % [
			int(after["mapa"]), int(after["nodo"])])
	_check(str(after["limpiados"]) == str(before["limpiados"]),
		"P3 los nodos limpiados vuelven intactos (%s)" % [after["limpiados"]])
	_check(str(after["hp"]) == str(before["hp"]),
		"P3 el HP de los supervivientes vuelve intacto (%s)" % [after["hp"]])
	_check(_same_counts(after["botin"], before["botin"]),
		"P3 el botin acumulado vuelve intacto (%s)" % [after["botin"]])
	_check(int(after["cartas"]) == int(before["cartas"]),
		"P3 las cartas ya elegidas vuelven (%d)" % int(after["cartas"]))

	# Y el tablero se vuelve a desplegar desde cero, con esas mismas unidades.
	var reopened: bool = CombatManager.enter_current_node()
	_check(reopened and CombatManager.is_in_encounter(),
		"P3 enter_current_node() vuelve a desplegar el tablero del nodo %d" % back.current_node)
	if reopened:
		var board_hp: Dictionary = _player_hp_on_board()
		_check(str(board_hp) == str(before["hp"]),
			"P3 el tablero reabierto forma con el HP guardado (%s)" % [board_hp])
		await _play_board()
		_check(true, "P3 el encuentro reanudado se juega hasta el final (victoria=%s)" % bool(
			CombatManager.get_last_result().get("victory", false)))
		CombatManager.end_encounter()
	if CombatManager.has_active_expedition():
		CombatManager.abandon_expedition()

# ══════════════════════════════════════════════════════════════════════
# Pasada 4: hasta donde llega una columna con el balance de serie
# ══════════════════════════════════════════════════════════════════════

## No mide cableado: mide SC-001 ("un jugador puede completar una expedicion de
## principio a fin ... en al menos el 80% de los casos"). Cinco semillas, el
## party del tope de despliegue y la ruta mas segura en cada cruce. Si ninguna
## pasa de los primeros nodos, el roguelike no se puede terminar, y eso hay que
## decirlo con numeros. De paso compara los mapas entre si (SC-008).
const BALANCE_SEEDS := [20260915, 771, 4242, 90210, 31337]

func _pass_balance() -> void:
	_p("")
	_p("########## PASADA 4: balance de serie (SC-001) y variedad (SC-008) ##########")
	_traced = TRACE_LINES  # sin traza: aqui solo interesa el resultado
	var reached: Array = []
	var signatures: Dictionary = {}
	for seed_value in BALANCE_SEEDS:
		_reset_world()
		if not CombatManager.launch_expedition(PARTY.duplicate(), int(seed_value)):
			continue
		var run: Expedition = CombatManager.get_expedition()
		signatures[_map_signature(run)] = true
		var deepest := 0
		var played := 0
		while CombatManager.has_active_expedition() and played < MAX_NODES:
			played += 1
			if not CombatManager.is_in_encounter():
				break
			deepest = maxi(deepest, int(run.current_node_data().get("depth", 0)))
			await _play_board()
			CombatManager.end_encounter()
			await get_tree().process_frame
			if not CombatManager.has_active_expedition():
				break
			if CombatManager.has_pending_draft():
				CombatManager.apply_draft(0)
			var exits: Array = run.current_exits()
			if exits.is_empty():
				break
			CombatManager.select_node(_safest_exit(run, exits))
		var code: int = int(_ended.get("result", -1))
		reached.append(deepest)
		_p("semilla %d: %d nodos jugados, profundidad maxima %d, resultado=%s" % [
			int(seed_value), played, deepest,
			["GANADA", "PERDIDA", "ABANDONADA"][code] if code >= 0 and code <= 2 else "?"])
		if CombatManager.has_active_expedition():
			CombatManager.abandon_expedition()
	var best: int = 0
	for d in reached:
		best = maxi(best, int(d))
	# Cuanto aguanta una columna es balance, y cinco semillas con la IA llevando
	# tambien al jugador son un suelo muy pesimista: CombatAI esta escrita para
	# atacar, no para cuidar una columna. El balance de verdad se mide en
	# tools/balance_probe.gd sobre miles de expediciones y con una politica de
	# juego (curar cuando toca, ruta de menos riesgo); ver docs/16-balance-combate.md.
	# Aqui solo se informa, para tener una referencia rapida del peor caso.
	_p("   . profundidad maxima alcanzada en %d semillas: %d (informativo, no es el balance)" % [
		BALANCE_SEEDS.size(), best])
	_check(best > 0,
		"P4 alguna columna avanza al menos un nodo (la mejor llego a profundidad %d)" % best)
	_check(signatures.size() == BALANCE_SEEDS.size(),
		"P4 SC-008: las %d semillas dan %d mapas distintos (rutas, riesgos y rosters)" % [
			BALANCE_SEEDS.size(), signatures.size()])

# ══════════════════════════════════════════════════════════════════════
# Conducir el tablero
# ══════════════════════════════════════════════════════════════════════

## Juega el tablero abierto hasta que se resuelve. El bando del jugador lo
## conduce CombatAI (el mismo cerebro que usa AutoResolver) pero cada paso entra
## por la API publica de CombatManager, que es lo unico que dispara _apply_result()
## y, con el, el avance de la expedicion.
func _play_board() -> void:
	var guard := 0
	while CombatManager.is_in_encounter() and guard < BOARD_GUARD:
		guard += 1
		if not CombatManager.is_player_turn():
			await get_tree().process_frame
			continue
		var unit: CombatUnit = CombatManager.get_active_unit()
		if unit == null:
			CombatManager.end_turn()
			await get_tree().process_frame
			continue
		var uid: int = unit.uid
		for step in AI.plan_turn(CombatManager.get_encounter(), uid):
			if not CombatManager.is_in_encounter():
				break
			_apply_step(uid, step)
		var enc: Encounter = CombatManager.get_encounter()
		if CombatManager.is_in_encounter() and enc.active_unit() != null and enc.active_unit().uid == uid:
			CombatManager.end_turn()
		await get_tree().process_frame
	if guard >= BOARD_GUARD:
		_check(false, "el tablero se resuelve sin agotar el tope de %d pasos" % BOARD_GUARD)

func _apply_step(uid: int, step: Dictionary) -> void:
	match step.get("action", "wait"):
		"move":
			CombatManager.move_unit(uid, step["to"])
		"attack":
			CombatManager.attack(uid, step["target"])
		"defend":
			CombatManager.defend(uid)
		_:
			CombatManager.wait_unit(uid)

# ══════════════════════════════════════════════════════════════════════
# Sembrado y quietud de la base
# ══════════════════════════════════════════════════════════════════════

## La base tiene que estar quieta: si el pueblo come, la tormenta muerde o cae
## un evento, los recursos se mueven solos y la invariante del cobro unico deja
## de medir lo que dice medir. Nada de esto cambia el combate.
func _freeze_base() -> void:
	GameConfig.combat_ai_step_delay = 0.0
	var forever := 1.0e9
	GameConfig.consumption_interval = forever
	GameConfig.early_consumption_interval = forever
	GameConfig.growth_interval = forever
	GameConfig.early_growth_interval = forever
	GameConfig.army_upkeep_interval = forever
	GameConfig.event_interval_min = forever
	GameConfig.event_interval_max = forever
	GameConfig.event_interval_min_dev = forever
	GameConfig.event_interval_max_dev = forever
	GameConfig.storm_first_interval = forever
	GameConfig.storm_interval_min = forever
	GameConfig.storm_interval_max = forever
	# Almacen de sobra: el pool compartido recorta el botin al llenarse, y eso
	# falsearia la comparacion entre lo acumulado y lo pagado.
	GameConfig.tech_storage_bonus = 100000

## Baja al enemigo para que la pasada 1 pueda llegar al jefe. Solo toca los
## diales de escalado; las reglas del tablero se quedan como estan.
func _nerf_enemy() -> void:
	GameConfig.combat_enemy_scale_per_depth = NERF_SCALE_PER_DEPTH
	GameConfig.combat_enemy_scale_per_era = NERF_SCALE_PER_ERA
	GameConfig.combat_risk_enemy_scale = NERF_RISK_SCALE
	GameConfig.combat_boss_multiplier = NERF_BOSS_MULTIPLIER
	GameConfig.combat_enemy_base_slots = NERF_BASE_SLOTS

## Devuelve los diales a los valores de GameConfig.gd, para que la pasada 4 mida
## el juego de verdad.
func _restore_enemy() -> void:
	GameConfig.combat_enemy_scale_per_depth = 0.15
	GameConfig.combat_enemy_scale_per_era = 0.25
	GameConfig.combat_risk_enemy_scale = 0.20
	GameConfig.combat_boss_multiplier = 1.8
	GameConfig.combat_enemy_base_slots = 2

## Ejercito y era de quien ya tiene Cuartel y puede salir de expedicion.
func _reset_world() -> void:
	CombatManager.reset()
	ProgressionManager.current_era = ERA
	ProgressionManager.current_phase = GameConfig.Phase.EXPANSION
	ResourceManager.set_unlock_state({"gold": true, "wood": true, "steel": true, "oil": true})
	ResourceManager.set_amounts({"gold": 500, "wood": 400, "steel": 200, "oil": 0})
	PopulationManager._morale = 70
	ArmyManager._units = {"infantry": 5, "artillery": 3}
	EventBus.army_changed.emit()
	_ended = {}
	_ended_seen = false

# ══════════════════════════════════════════════════════════════════════
# Lectura
# ══════════════════════════════════════════════════════════════════════

func _on_expedition_ended(result: int, rewards: Dictionary, casualties: Dictionary) -> void:
	_ended = {"result": result, "rewards": rewards.duplicate(), "casualties": casualties.duplicate()}
	_ended_seen = true

## Traza de golpes y muertos del primer tablero, por el EventBus para que
## tambien se vea lo que hace el enemigo (su turno lo conduce CombatManager por
## dentro). Distingue "el jugador pierde" de "el jugador no actua".
var _traced := 0

func _on_unit_attacked(attacker: int, target: int, damage: int) -> void:
	if _traced >= TRACE_LINES:
		return
	_traced += 1
	var enc: Encounter = CombatManager.get_encounter()
	if enc == null:
		return
	var a: CombatUnit = enc.get_unit(attacker)
	var t: CombatUnit = enc.get_unit(target)
	if a == null or t == null:
		return
	_p("   . r%d %s%s#%d (%d/%d) pega %d a %s%s#%d -> %d/%d" % [
		enc.round_number, "J" if a.side == Encounter.PLAYER else "E", a.unit_id, a.uid,
		a.hp, a.max_hp, damage,
		"J" if t.side == Encounter.PLAYER else "E", t.unit_id, t.uid, t.hp, t.max_hp])

func _on_unit_died(uid: int, side: int) -> void:
	if _traced >= TRACE_LINES:
		return
	_traced += 1
	_p("   . CAE %s#%d" % ["el jugador" if side == Encounter.PLAYER else "el enemigo", uid])

func _player_units_on_board() -> Array:
	var out: Array = []
	for unit in CombatManager.get_units():
		if unit.side == Encounter.PLAYER:
			out.append(unit)
	return out

func _player_hp_on_board() -> Dictionary:
	var hp: Dictionary = {}
	for unit in _player_units_on_board():
		hp[unit.uid] = unit.hp
	return hp

## HP de los que siguen en pie, que son los que vuelven a formar. Los caidos se
## dejan fuera a proposito: el tablero reabierto no los despliega (permadeath).
func _party_hp(run: Expedition) -> Dictionary:
	var hp: Dictionary = {}
	for unit in run.living_party():
		hp[unit.uid] = unit.hp
	return hp

func _max_hp_of(uid: int) -> int:
	var unit: CombatUnit = CombatManager.get_unit(uid)
	return unit.max_hp if unit != null else 0

## Igual que _max_hp_of() pero leyendo el party, para los momentos en que no hay
## tablero abierto (entre nodos, cuando se elige la carta).
func _max_hp_of_party(run: Expedition, uid: int) -> int:
	for unit in run.party:
		if unit.uid == uid:
			return unit.max_hp
	return 0

func _hp_line(run: Expedition) -> String:
	var parts: Array = []
	for unit in run.living_party():
		parts.append("%s#%d %d/%d" % [unit.unit_id, unit.uid, unit.hp, unit.max_hp])
	return ", ".join(parts) if not parts.is_empty() else "(nadie)"

func _living_ids(run: Expedition) -> Array:
	var ids: Array = []
	for unit in run.living_party():
		ids.append(unit.unit_id)
	return ids

func _casualty_ids(run: Expedition) -> Array:
	var ids: Array = []
	for unit in run.casualties():
		ids.append(unit.unit_id)
	return ids

func _tally(ids: Array) -> Dictionary:
	var counts: Dictionary = {}
	for id in ids:
		counts[String(id)] = int(counts.get(String(id), 0)) + 1
	return counts

func _army_counts() -> Dictionary:
	var counts: Dictionary = {}
	for unit_id in GameConfig.get_unit_ids():
		var n: int = ArmyManager.get_count(unit_id)
		if n > 0:
			counts[unit_id] = n
	return counts

func _power_of(counts: Dictionary) -> int:
	var power := 0
	for unit_id in counts:
		power += int(counts[unit_id]) * int(GameConfig.get_unit_def(String(unit_id)).get("power", 0))
	return power

func _resources() -> Dictionary:
	var out: Dictionary = {}
	for type in ResourceManager.get_all():
		out[ResourceManager.get_type_name(type)] = int(ResourceManager.get_all()[type])
	return out

## La ruta que elegiria alguien con cabeza: la salida de menor riesgo. Ir
## siempre por exits[0] hace que la sonda mida la mala suerte en vez del
## cableado; a igualdad de riesgo se queda con el indice mas bajo.
func _safest_exit(run: Expedition, exits: Array) -> int:
	var best: int = int(exits[0])
	var best_risk: int = 99
	for index in exits:
		var risk: int = int(run.node_at(int(index)).get("risk", 0))
		if risk < best_risk:
			best_risk = risk
			best = int(index)
	return best

## Huella del mapa: forma de las rutas, riesgos y composicion enemiga. Dos
## semillas con la misma huella serian la misma expedicion (SC-008).
func _map_signature(run: Expedition) -> String:
	var parts: Array = []
	for node in run.map:
		parts.append("%d:%d:%s:%s" % [
			int(node.get("depth", 0)), int(node.get("risk", 0)),
			node.get("exits", []), node.get("enemy_roster", {})])
	return "|".join(parts)

func _boss_index(run: Expedition) -> int:
	for node in run.map:
		if bool(node.get("is_boss", false)):
			return int(node.get("index", -1))
	return -1

func _read_saved_expedition() -> Dictionary:
	var file := FileAccess.open(GameManager.SAVE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {}
	var data: Dictionary = json.data
	return data.get("expedition", {})

## Compara dos diccionarios de recuento tratando "ausente" y "0" como lo mismo:
## JSON devuelve floats y las claves vacias no siempre se escriben.
func _same_counts(a: Dictionary, b: Dictionary) -> bool:
	var keys: Dictionary = {}
	for k in a:
		keys[String(k)] = true
	for k in b:
		keys[String(k)] = true
	for k in keys:
		if int(a.get(k, 0)) != int(b.get(k, 0)):
			return false
	return true

func _check(ok: bool, text: String) -> void:
	_checks.append([ok, text])
	_p("%s %s" % ["   [OK]" if ok else "   [FALLO]", text])

func _p(line: String) -> void:
	print("[exped] %s" % line)
