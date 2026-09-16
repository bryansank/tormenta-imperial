extends Node
## Owner of the PVE combat domain. Holds the active Encounter, translates its
## events onto the EventBus and drives the enemy turn. Nothing else mutates
## combat state — the UI reads this API and reacts to signals (constitution,
## principles I and IV).
##
## The rules and the board live in scripts/combat/ as pure RefCounted objects.
## This node exists only for what needs a scene tree: signals and timing.
##
## ArmyManager stays the source of truth for the roster: units committed to an
## expedition are still counted there and are only deducted as casualties when
## the expedition resolves, so Military Power never lies mid-run.
##
## La expedicion (Expedition, scripts/combat/) es el otro modelo que este nodo
## posee: el mapa, el party que salio y lo que lleva ganado. Mientras dura, sus
## encuentros no cobran nada: recompensas y bajas se acumulan en el modelo y se
## liquidan una sola vez en _resolve_expedition() (FR-010, FR-011, FR-017).

const CombatUnitScript := preload("res://scripts/combat/CombatUnit.gd")
const EncounterScript := preload("res://scripts/combat/Encounter.gd")
const ExpeditionScript := preload("res://scripts/combat/Expedition.gd")
const Rules := preload("res://scripts/combat/CombatRules.gd")
const AI := preload("res://scripts/combat/CombatAI.gd")
const AutoResolverScript := preload("res://scripts/combat/AutoResolver.gd")

var _encounter: Encounter = null
## La expedicion en curso. Null en la base; se descarta al resolverla.
var _expedition: Expedition = null
var _next_expedition_id: int = 1
## El draft ofrecido tras ganar un nodo y aun sin elegir. Mientras dure no se
## abre ningun tablero: primero se elige la carta, despues la ruta.
var _draft_pending: bool = false
var _draft_options: Array = []
## Eventos del modelo de expedicion que un encuentro deja al resolverse (draft,
## fin de la expedicion). Se publican DESPUES de encounter_ended, para que la UI
## siempre vea cerrado el tablero antes de que le llegue lo que viene despues.
var _expedition_followups: Array = []
var _next_uid: int = 1
var _morale_snapshot: float = 50.0
var _enemy_turn_running: bool = false
## Guards against applying the outcome twice: a timeout and a wipe can both fire
## on the same advance, and paying the player twice for one fight is not a bug
## anybody reports.
var _result_applied: bool = false
var _last_result: Dictionary = {}
## uids de las dotaciones de torre del tablero actual. Pelean del lado del
## jugador pero no salen del cuartel, así que no pueden pasar por el ledger de
## ArmyManager: si murieran "como artillería", una defensa perdida le borraría al
## jugador cañones que nunca envió.
var _tower_crew_uids: Dictionary = {}
## Las dotaciones del tablero que acaba de cerrarse, entregadas por
## end_encounter() en el momento en que `_tower_crew_uids` deja de valer. Es lo
## unico que puede responder "quien era dotacion" cuando alguien encadena un
## tablero con los supervivientes del anterior, y solo sirve para ESE relevo: en
## cuanto se abre otro tablero, las unidades que salgan de el son las suyas.
## Quien componga un bando sin venir del tablero anterior (el asedio, que numera
## su guarnicion por su cuenta desde 1) no usa esto: dice sus dotaciones a la
## cara, porque sus uids pueden chocar con los de cualquier tablero pasado.
var _last_board_crew_uids: Dictionary = {}

## La Auditoria Final: el asedio en casa con el que termina la partida.
## FinalAudit (en ProgressionManager) lleva la guarnicion oleada a oleada y
## arrastra su daño; aqui solo se pone cada oleada en el tablero y se devuelve
## el resultado. Las dotaciones de torre no son del asedio: las compone quien lo
## lanza, y tambien sufren atricion — no hay relevos.
var _audit_wave_active: bool = false
## Como acabo la oleada del asedio, anotado al resolverse y leido al cerrar el
## tablero. Vive aparte de _last_result porque ese parte es de la ultima pelea
## que se resolvio, y no siempre es esta.
var _audit_wave_won: bool = false
var _audit_crews: Array = []
## Dotaciones caidas en lo que va de asedio. Las torres no se cansan, pero a
## una dotacion muerta no la reemplaza nadie.
var _audit_crew_losses: int = 0

func _ready() -> void:
	EventBus.final_audit_wave_ready.connect(_on_final_audit_wave_ready)

# ── Queries ──────────────────────────────────────────────────────────

func get_encounter() -> Encounter:
	return _encounter

func is_in_encounter() -> bool:
	return _encounter != null and _encounter.is_active()

## Hay tablero en pantalla, este jugandose o mostrando el parte. No es lo mismo
## que is_in_encounter(): entre que la pelea se resuelve y el jugador cierra el
## parte, el encuentro existe y no esta activo. Abrir otro tablero en ese hueco
## se lleva por delante el parte sin que nadie lo lea.
func is_board_open() -> bool:
	return _encounter != null

func is_enemy_thinking() -> bool:
	return _enemy_turn_running

func get_state() -> int:
	return _encounter.state if _encounter != null else Encounter.State.DEPLOYING

func get_round() -> int:
	return _encounter.round_number if _encounter != null else 1

func get_turn_limit() -> int:
	return GameConfig.combat_turn_limit

func get_board_size() -> Vector2i:
	return GameConfig.combat_board_size

func get_units() -> Array:
	return _encounter.units if _encounter != null else []

func get_unit(uid: int) -> CombatUnit:
	return _encounter.get_unit(uid) if _encounter != null else null

func get_unit_at(cell: Vector2i) -> CombatUnit:
	return _encounter.get_unit_at(cell) if _encounter != null else null

func get_active_unit() -> CombatUnit:
	return _encounter.active_unit() if _encounter != null else null

func get_turn_order() -> Array:
	return _encounter.turn_order if _encounter != null else []

func get_morale_snapshot() -> float:
	return _morale_snapshot

## True while it is the player's turn and the board is waiting on them.
func is_player_turn() -> bool:
	return is_in_encounter() and _encounter.state == Encounter.State.PLAYER_TURN and not _enemy_turn_running

## Units the player may still commit: everything trained and not already out on
## expedition. Las comprometidas se descuentan enteras, vivas y caidas, porque
## ArmyManager no borra a las caidas hasta que la columna vuelve (SC-004).
func get_deployable_units() -> Dictionary:
	var committed: Dictionary = get_units_on_expedition()
	var available: Dictionary = {}
	for unit_id in GameConfig.get_unit_ids():
		var count: int = ArmyManager.get_count(unit_id) - int(committed.get(unit_id, 0))
		if count > 0:
			available[unit_id] = count
	return available

# ── Encounter lifecycle ──────────────────────────────────────────────

## Builds both sides and opens the board. `party` and `enemy_roster` are
## unit_id -> count dictionaries.
## The Assessors come to collect and the garrison answers. Unlike a skirmish the
## player does not pick the party: whatever is at home fights, which is what makes
## sending the army out before a storm an actual gamble.
##
## Las torres en pie arman sus posiciones y pelean junto a la guarnición: es lo
## que se gana por construirlas y, sobre todo, por repararlas entre tormentas.
##
## Returns false when there is nobody left to stand — the caller then has to let
## the Tithe be collected. Con torres enteras y el cuartel vacío sí hay defensa:
## la posición se defiende sola, que es lo que una torre es.
##
## `defenders` permite entregar el bando defensor **ya montado** (CombatUnit con
## la vida que traen) en vez de recomponerlo desde ArmyManager. Vacío = se compone
## como siempre. El hueco existe porque una defensa no siempre empieza de cero:
## encadenar oleadas solo significa algo si los supervivientes entran tocados a la
## siguiente, y recalcular la guarnición cada vez borraría precisamente eso.
##
## `defender_crew_uids` dice cuáles de esos defensores son dotación de torre.
## Quien compone el bando lo sabe, y decirlo es la única forma de saberlo bien:
## deducirlo del estado que dejó el tablero anterior era apostar a que dos uids
## de tableros distintos nunca coinciden, y sí coinciden — el asedio numera su
## guarnición desde 1 por su cuenta, así que su infantería #2 se cruza con la
## dotación #2 de cualquier defensa anterior y sus bajas dejan de salir de
## ArmyManager.
##
## `null` es "no lo sé, dedúcelo", y solo vale para quien encadena con los
## supervivientes del tablero que se acaba de cerrar: son las mismas unidades y
## los mismos uids, así que no hay nada que confundir. Una lista vacía NO es lo
## mismo que `null`: es "ninguna, y lo sé" — una oleada sin torres en pie tiene
## que poder decirlo sin que nadie salga a buscarle dotaciones al pasado.
func start_defense(enemy_roster: Dictionary, defenders: Array = [], enemy_scale: float = -1.0, defender_crew_uids: Variant = null) -> bool:
	if is_board_open() or enemy_roster.is_empty():
		return false

	if not defenders.is_empty():
		# El bando viene dado: lo único que hay que conservar son las marcas de
		# dotación de torre que esas unidades ya traían, para que una dotación que
		# sobrevivió a la oleada anterior siga sin ser parte del ejército.
		var carried: Array = []
		if defender_crew_uids != null:
			carried = (defender_crew_uids as Array).duplicate()
		else:
			for unit in defenders:
				if _last_board_crew_uids.has(unit.uid):
					carried.append(unit.uid)
		start_encounter_with_units(defenders, enemy_roster, false, 0, true, carried, enemy_scale)
		return true

	var garrison: Dictionary = get_garrison()
	var crews: Dictionary = get_tower_crews(garrison)
	if garrison.is_empty() and crews.is_empty():
		return false
	start_encounter(garrison, enemy_roster, false, 0, true, crews, enemy_scale)
	if not crews.is_empty():
		EventBus.notification_posted.emit(
			Tr.t("STORM_TITHE_TOWER_CREWS") % roster_size(crews), "positive", UITheme.ACCENT)
	return true

# ── Defensa sin tablero ──────────────────────────────────────────────

## La misma defensa que start_defense(), pero jugada de una vez por la IA en un
## Encounter propio que nunca llega a ser `_encounter`: ni abre el tablero ni
## emite una sola senal de combate. Es lo que pasa cuando el Diezmo cae con el
## jugador en plena expedicion: la guarnicion que se quedo en casa pelea sola.
##
## El bando defensor se compone exactamente igual que en start_defense()
## (guarnicion de ArmyManager + dotaciones de las torres en pie, misma moral,
## misma escala enemiga) y el resultado se aplica por el mismo camino que una
## defensa jugada (_apply_result_for): bajas fuera del ejercito, nunca las
## dotaciones; sin botin; moral como siempre. Al terminar emite
## `defense_auto_resolved` con get_last_result() como parte.
##
## Las oleadas de la Auditoria Final no pasan por aqui a proposito: el asedio no
## puede convocarse con una expedicion fuera (can_launch se bloquea mientras hay
## asedio, y el asedio no se convoca con el tablero ocupado), asi que nunca hay
## tablero que esquivar; y una oleada resuelta a ciegas le quitaria al final del
## juego justo lo que lo hace final.
##
## Devuelve {"fought": false, "victory": false, "reason": ...} cuando no hay
## nadie que defienda (igual que start_defense() devuelve false) o nadie de quien
## defenderse; si se pelea, {"fought": true, "victory", "rounds", "summary"}.
func auto_resolve_defense(enemy_roster: Dictionary, enemy_scale: float = -1.0) -> Dictionary:
	if enemy_roster.is_empty():
		return {"fought": false, "victory": false, "reason": "no_attackers"}
	var garrison: Dictionary = get_garrison()
	var crews: Dictionary = get_tower_crews(garrison)
	if garrison.is_empty() and crews.is_empty():
		return {"fought": false, "victory": false, "reason": "undefended"}

	# La moral se captura como en cualquier lanzamiento, pero sin pisar la
	# instantanea del tablero que sigue abierto: la expedicion pelea con la moral
	# con la que salio.
	var board_snapshot: float = _morale_snapshot
	_morale_snapshot = _read_morale()
	var units: Array = _build_side(garrison, Encounter.PLAYER, 1.0)
	var crew_uids: Dictionary = {}
	for crew in _build_side(crews, Encounter.PLAYER, 1.0):
		crew_uids[crew.uid] = true
		units.append(crew)
	var scale: float = enemy_scale if enemy_scale > 0.0 else 1.0
	units.append_array(_build_side(enemy_roster, Encounter.ENEMY, scale))
	_morale_snapshot = board_snapshot

	var encounter: Encounter = EncounterScript.create(units, 0, false, true, crew_uids.keys())
	var outcome: Dictionary = AutoResolverScript.resolve(encounter)
	var victory: bool = bool(outcome["victory"])
	var rounds: int = int(outcome["rounds"])
	var summary: Dictionary = _apply_result_for(encounter, victory, rounds, crew_uids)
	EventBus.defense_auto_resolved.emit(victory, rounds, summary)
	return {"fought": true, "victory": victory, "rounds": rounds, "summary": summary}

## Una oleada del asedio pide tablero. Los defensores son la guarnicion viva que
## lleva FinalAudit —con el daño de la oleada anterior— mas las dotaciones de
## torre que sigan en pie. Sin relevos: lo que cae, cae.
func _on_final_audit_wave_ready(wave: int, roster: Dictionary, scale: float) -> void:
	var audit = ProgressionManager.final_audit
	if audit == null:
		return
	var defenders: Array = audit.living_garrison().duplicate()
	# Las dotaciones se fabrican aqui, antes de _open(): sin esto nacerian con los
	# uids 1 y 2, los mismos que la guarnicion, y no llegarian a actuar nunca.
	_reserve_uids(defenders)

	_morale_snapshot = _read_morale()
	# Una torre no se cansa, una dotacion si muere. Cada oleada las torres en pie
	# vuelven a mandar gente entera, pero las dotaciones caidas en oleadas
	# anteriores no se reemplazan: la atricion tambien les toca a ellas.
	if wave <= 0:
		_audit_crew_losses = 0
	else:
		for crew in _audit_crews:
			if not crew.is_alive():
				_audit_crew_losses += 1
	var counts: Dictionary = {}
	for unit in defenders:
		counts[unit.unit_id] = int(counts.get(unit.unit_id, 0)) + 1
	var wanted: int = roster_size(get_tower_crews(counts)) - _audit_crew_losses
	_audit_crews = []
	if wanted > 0:
		_audit_crews = _build_side({GameConfig.storm_tower_garrison_unit: wanted}, Encounter.PLAYER, 1.0)
	# Quien las fabrica es quien dice quienes son. La lista viaja hasta el tablero
	# en la misma llamada: ninguna decision sobre "esto es dotacion" pasa por lo
	# que dejo apuntado un tablero que ya no existe.
	var crew_uids: Array = []
	for crew in _audit_crews:
		crew_uids.append(crew.uid)
	defenders.append_array(_audit_crews)

	# Sin nadie en pie no se abre tablero: si se llamara a start_defense() con la
	# lista vacia, esta caeria al camino normal y armaria la defensa desde
	# ArmyManager, que no es la guarnicion del asedio. FinalAudit ya declara la
	# derrota al quedarse sin gente, pero este guard evita depender de ello.
	if defenders.is_empty():
		ProgressionManager.report_audit_wave(false)
		return

	_audit_wave_active = true
	if not start_defense(roster, defenders, scale, crew_uids):
		# Nadie en pie: la oleada pasa por encima sin abrir tablero.
		_audit_wave_active = false
		ProgressionManager.report_audit_wave(false)

## Everything trained and at home, up to the board's cap. Quien esta de
## expedicion no esta en casa: si el Diezmo cae con la columna fuera, defiende
## solo lo que se quedo.
func get_garrison() -> Dictionary:
	var away: Dictionary = get_units_on_expedition()
	var garrison: Dictionary = {}
	var committed := 0
	for unit_id in GameConfig.get_unit_ids():
		for i in ArmyManager.get_count(unit_id) - int(away.get(unit_id, 0)):
			if committed >= GameConfig.combat_deploy_cap:
				break
			garrison[unit_id] = int(garrison.get(unit_id, 0)) + 1
			committed += 1
	return garrison

## Lo que las torres aportan al tablero, sabiendo ya quién ha respondido: van
## además del tope de despliegue, pero nunca desbordan la fila del defensor.
func get_tower_crews(garrison: Dictionary) -> Dictionary:
	var crews: int = GameConfig.get_tower_garrison(count_standing_towers(), roster_size(garrison))
	if crews <= 0:
		return {}
	return {GameConfig.storm_tower_garrison_unit: crews}

## Torres en pie. Se cuentan aquí en vez de preguntárselo a StormManager a
## propósito: armar un tablero de defensa no puede depender del ciclo de la
## tormenta, porque el mismo camino lo usará el asedio mientras el jugador está
## de expedición.
##
## Una torre en ruinas no aporta nada, igual que no mitiga: repararlas antes de
## la siguiente tormenta es la decisión que todo esto existe para provocar.
func count_standing_towers() -> int:
	var standing := 0
	for info in GridManager.get_all_buildings():
		var data: BuildingData = info["data"]
		if data == null or data.id != GameConfig.storm_tower_building_id:
			continue
		if BuildingHealth.is_operational(info["node"]):
			standing += 1
	return standing

## Cuántas unidades suma un roster unit_id -> count.
func roster_size(roster: Dictionary) -> int:
	var total := 0
	for count in roster.values():
		total += int(count)
	return total

## True while the current fight is a defence of the base.
func is_defending() -> bool:
	return _encounter != null and _encounter.is_defense

## `reinforcements` son unidades del jugador que no salen de su ejército (hoy,
## las dotaciones de torre). Entran al tablero como cualquier otra, pero se
## anotan aparte para que las bajas no toquen el roster de ArmyManager.
func start_encounter(party: Dictionary, enemy_roster: Dictionary, is_boss: bool = false, encounter_index: int = 0, is_defense: bool = false, reinforcements: Dictionary = {}, enemy_scale: float = -1.0) -> void:
	_morale_snapshot = _read_morale()
	var player_units: Array = _build_side(party, Encounter.PLAYER, 1.0)
	var crew_uids: Array = []
	for crew in _build_side(reinforcements, Encounter.PLAYER, 1.0):
		crew_uids.append(crew.uid)
		player_units.append(crew)
	_open(player_units, enemy_roster, is_boss, encounter_index, is_defense, crew_uids, enemy_scale)

## El mismo encuentro, pero con el bando del jugador ya construido: las unidades
## entran con la vida que traen en vez de nacer enteras. Es lo que permite
## encadenar encuentros sin que cada uno empiece de cero.
##
## `crew_uids` marca cuáles de esas unidades no pertenecen al ejército.
func start_encounter_with_units(player_units: Array, enemy_roster: Dictionary, is_boss: bool = false, encounter_index: int = 0, is_defense: bool = false, crew_uids: Array = [], enemy_scale: float = -1.0) -> void:
	_morale_snapshot = _read_morale()
	_open(player_units, enemy_roster, is_boss, encounter_index, is_defense, crew_uids, enemy_scale)

## Monta el bando enemigo desde un roster y abre el tablero. Las escaramuzas y
## la defensa entran por aqui; la expedicion trae al enemigo ya fabricado por su
## propio modelo y entra directamente por _open_board().
func _open(player_units: Array, enemy_roster: Dictionary, is_boss: bool, encounter_index: int, is_defense: bool, crew_uids: Array, enemy_scale: float = -1.0) -> void:
	# Una escala dada (las oleadas del asedio) manda sobre la del jefe.
	var scale: float = enemy_scale if enemy_scale > 0.0 else (GameConfig.combat_boss_multiplier if is_boss else 1.0)
	# Las unidades que llegan hechas (la guarnicion del asedio, que FinalAudit
	# numera por su cuenta) traen sus uids puestos. Si no se reservan, el enemigo
	# se fabrica desde 1 y colisiona con ellas: Encounter.get_unit() devuelve la
	# primera coincidencia, asi que cada golpe al "enemigo #3" caia sobre el
	# defensor #3 y la Regencia no sangraba nunca. La sonda del asedio lo destapo.
	_reserve_uids(player_units)
	var units: Array = player_units.duplicate()
	units.append_array(_build_side(enemy_roster, Encounter.ENEMY, scale))
	_open_board(units, is_boss, encounter_index, is_defense, crew_uids)

## Único sitio donde se abre un tablero: recibe ambos bandos ya montados, fija
## quién no cuenta como ejército y arranca.
func _open_board(units: Array, is_boss: bool, encounter_index: int, is_defense: bool, crew_uids: Array) -> void:
	_reserve_uids(units)
	_tower_crew_uids.clear()
	for uid in crew_uids:
		_tower_crew_uids[int(uid)] = true

	# Las dotaciones de torre forman en la retaguardia: son artilleria con alcance
	# minimo 2, y en cabeza se quedan mudas justo cuando el enemigo llega a
	# contacto. Es la misma lista que ya se usa para no contarlas como bajas.
	_encounter = EncounterScript.create(units, encounter_index, is_boss, is_defense, crew_uids)
	_result_applied = false
	EventBus.encounter_started.emit(encounter_index, is_boss)
	_publish(_encounter.start())

## Empuja el contador por encima de cualquier uid que ya exista en `units`, para
## que todo lo que se fabrique despues (dotaciones, enemigo) no repita ninguno.
func _reserve_uids(units: Array) -> void:
	for unit in units:
		_next_uid = maxi(_next_uid, int(unit.uid) + 1)

func _build_side(roster: Dictionary, side: int, scale: float) -> Array:
	var built: Array = []
	for unit_id in roster.keys():
		for i in int(roster[unit_id]):
			var unit: CombatUnit = CombatUnitScript.create(_next_uid, unit_id, side, scale)
			_next_uid += 1
			if side == Encounter.PLAYER:
				# Morale is captured once, at launch: the battle is fought with the
				# spirit the base had when it set out, not with live numbers.
				unit.morale_attack_mod = Rules.morale_attack_mod(_morale_snapshot)
				unit.morale_initiative_bonus = Rules.morale_initiative_bonus(_morale_snapshot)
			built.append(unit)
	return built

## Standalone fight with the party the player just committed. This is the loop
## the expedition will wrap in US2: the same encounter, chained across a map with
## drafts between nodes. Until then it is the playable slice.
func start_skirmish(party: Dictionary) -> bool:
	if party.is_empty() or is_in_encounter() or has_active_expedition():
		return false
	start_encounter(party, build_enemy_roster(party, 0), false, 0)
	return true

## Fields an opposing force that answers what the player brought, so committing
## more never turns the fight into a walkover — the decision has to stay a
## decision. Deeper nodes and later eras tilt it against the player.
##
## Provisional: ExpeditionGenerator.enemy_roster() replaces this in T022, where
## the roster becomes seeded and reproducible.
func build_enemy_roster(party: Dictionary, depth: int) -> Dictionary:
	var committed := 0
	for count in party.values():
		committed += int(count)
	committed = maxi(1, committed)

	var era: int = ProgressionManager.current_era
	var pressure: float = 1.0 \
		+ GameConfig.combat_enemy_scale_per_depth * float(depth) \
		+ GameConfig.combat_enemy_scale_per_era * float(maxi(0, era - 1))
	var slots: int = clampi(roundi(float(committed) * pressure), 1, GameConfig.combat_deploy_cap)

	# A line of infantry with guns behind it: enough shape that positioning and
	# the artillery's minimum range both matter from the very first fight.
	var roster: Dictionary = {}
	var guns: int = slots / 3
	var armour: int = 1 if era >= 3 and slots >= 4 else 0
	var line: int = maxi(1, slots - guns - armour)
	roster["infantry"] = line
	if guns > 0:
		roster["artillery"] = guns
	if armour > 0:
		roster["vehicle"] = armour
	return roster

func end_encounter() -> void:
	var was_audit_wave: bool = _audit_wave_active
	# El resultado de la oleada se anota cuando la oleada se resuelve, no se
	# deduce aqui de _last_result: esa variable la pisa cualquier otra pelea
	# (la defensa a ciegas del Diezmo, sin ir mas lejos) y una oleada ganada
	# podia reportarse perdida, que es arrasar la base por un efecto colateral.
	var wave_won: bool = _audit_wave_won
	_audit_wave_active = false
	_audit_wave_won = false
	if _encounter != null:
		_encounter.release_survivors()
	_encounter = null
	_enemy_turn_running = false
	# Las marcas de dotacion dejan de ser "las del tablero" y pasan a ser "las del
	# tablero que acaba de cerrarse". El reparto de bajas ya se hizo (_apply_result
	# corre con encounter_ended, antes que esto), asi que aqui no le quitamos nada
	# a nadie; lo que se evita es que sigan vivas a espaldas de todos y contesten
	# por un tablero futuro con el que no tienen nada que ver.
	_last_board_crew_uids = _tower_crew_uids.duplicate()
	_tower_crew_uids.clear()
	# Se reporta con el tablero ya cerrado: si se hiciera al terminar la pelea,
	# la oleada siguiente llegaria con is_in_encounter() aun en true y se perderia.
	if was_audit_wave:
		ProgressionManager.report_audit_wave(wave_won)

# ── Player actions ───────────────────────────────────────────────────

func get_valid_moves(uid: int) -> Array:
	return _encounter.valid_moves(uid) if _encounter != null else []

func get_valid_targets(uid: int) -> Array:
	return _encounter.valid_targets(uid) if _encounter != null else []

func move_unit(uid: int, to: Vector2i) -> bool:
	if not is_player_turn():
		return false
	var events := _encounter.move_unit(uid, to)
	_publish(events)
	return not events.is_empty()

func attack(uid: int, target_uid: int) -> bool:
	if not is_player_turn():
		return false
	var events := _encounter.attack(uid, target_uid)
	_publish(events)
	return not events.is_empty()

func defend(uid: int) -> bool:
	if not is_player_turn():
		return false
	var events := _encounter.defend(uid)
	_publish(events)
	return not events.is_empty()

func wait_unit(uid: int) -> bool:
	if not is_player_turn():
		return false
	var events := _encounter.wait_unit(uid)
	_publish(events)
	return not events.is_empty()

func end_turn() -> bool:
	if not is_player_turn():
		return false
	_publish(_encounter.end_turn())
	return true

# ── Event translation ────────────────────────────────────────────────

## Translates the encounter's plain event list onto the EventBus. The UI only
## ever learns about combat through these signals.
func _emit_events(events: Array) -> void:
	for event in events:
		match event.get("e", ""):
			"turn_started":
				EventBus.turn_started.emit(event["side"], event["uid"])
			"unit_moved":
				EventBus.unit_moved.emit(event["uid"], event["from"], event["to"])
			"unit_attacked":
				EventBus.unit_attacked.emit(event["attacker"], event["target"], event["damage"])
			"unit_defended":
				EventBus.unit_defended.emit(event["uid"])
			"unit_died":
				EventBus.unit_died.emit(event["uid"], event["side"])
			"encounter_ended":
				# The base learns the outcome before anyone is told the fight is
				# over, so the UI reading get_last_result() always sees it applied.
				_apply_result(event["victory"], event["rounds"])
				EventBus.encounter_ended.emit(event["victory"], event["rounds"])
				# Y solo entonces la expedicion sigue: draft o final de la campana.
				_publish_expedition_followups()

## Publishes and then hands the board to the AI if the turn that just started
## belongs to the enemy. Used for everything the player triggers.
func _publish(events: Array) -> void:
	_emit_events(events)
	_maybe_run_enemy_turn()

func _maybe_run_enemy_turn() -> void:
	if _enemy_turn_running or _encounter == null:
		return
	if _encounter.state != Encounter.State.ENEMY_TURN:
		return
	_run_enemy_turn()

## Plays the enemy unit's plan with a pause between steps. Without the pause the
## whole enemy round resolves in one frame and the player never sees what hit them.
func _run_enemy_turn() -> void:
	_enemy_turn_running = true
	var uid: int = _encounter.active_unit().uid if _encounter.active_unit() != null else -1
	if uid == -1:
		_enemy_turn_running = false
		return

	var plan: Array = AI.plan_turn(_encounter, uid)
	var delay: float = GameConfig.get_combat_ai_step_delay()
	var follow_up: Array = []

	for step in plan:
		if _encounter == null or not _encounter.is_active():
			break
		await get_tree().create_timer(delay).timeout
		if _encounter == null or not _encounter.is_active():
			break
		match step.get("action", "wait"):
			"move":
				follow_up = _encounter.move_unit(uid, step["to"])
			"attack":
				follow_up = _encounter.attack(uid, step["target"])
			"defend":
				follow_up = _encounter.defend(uid)
			_:
				follow_up = _encounter.wait_unit(uid)
		_emit_events(follow_up)

	# The unit may have moved without attacking; close its turn either way.
	if _encounter != null and _encounter.is_active() and _encounter.active_unit() != null \
			and _encounter.active_unit().uid == uid:
		_emit_events(_encounter.end_turn())

	_enemy_turn_running = false
	_maybe_run_enemy_turn()

# ── Consequences ─────────────────────────────────────────────────────

## Turns the outcome of a fight into changes the player feels in the base: the
## dead are struck off the roster for good, a win pays, and the town's morale
## moves either way.
##
## This is what makes the board part of the game instead of a simulator. It runs
## exactly once per encounter, when the encounter resolves.
func _apply_result(victory: bool, rounds: int) -> void:
	if _encounter == null or _result_applied:
		return
	_result_applied = true
	if _audit_wave_active:
		_audit_wave_won = victory

	# Un nodo de expedicion no cobra ni entierra a nadie todavia: lo acumula el
	# modelo y se liquida todo junto al volver (FR-010, FR-011, FR-017). La
	# defensa de la base sigue su camino de siempre aunque haya columna fuera.
	if has_active_expedition() and not _encounter.is_defense:
		_apply_expedition_encounter(victory, rounds)
		return

	_apply_result_for(_encounter, victory, rounds, _tower_crew_uids)

## El mismo cierre para cualquier encuentro, este en el tablero o resuelto a
## ciegas por AutoResolver: `crew_uids` dice que unidades del jugador no
## pertenecen al ejercito. Deja el parte en get_last_result() y lo devuelve.
func _apply_result_for(encounter: Encounter, victory: bool, rounds: int, crew_uids: Dictionary) -> Dictionary:
	# Las dotaciones de torre quedan fuera del recuento: no salieron del cuartel,
	# así que ni se restan del ejército ni cuentan como supervivientes que vuelven.
	var fallen: Array = encounter.casualties(Encounter.PLAYER)
	var roster_fallen: Array = _roster_only(fallen, crew_uids)
	var casualties: Dictionary = _count_by_unit(roster_fallen)
	var survivors: Dictionary = _count_by_unit(_roster_only(encounter.survivors(), crew_uids))

	# ArmyManager is the source of truth for the roster: the party was never
	# deducted when it marched out, so only the dead are subtracted now and
	# Military Power lands exactly on the survivors.
	var lost: Dictionary = ArmyManager.remove_units(casualties)

	# Winning a defence pays nothing, and it should not: the reward is that the
	# Tithe goes uncollected. Handing out loot on top would pay the player twice
	# for the same fight.
	var rewards: Dictionary = {}
	if victory and not encounter.is_defense:
		rewards = Rules.encounter_rewards(ProgressionManager.current_era)
		for res_name in rewards:
			ResourceManager.add(_resource_type(res_name), int(rewards[res_name]))

	var dead: int = 0
	for count in lost.values():
		dead += int(count)
	var morale_delta: int = Rules.morale_delta(victory, dead)
	if morale_delta != 0:
		PopulationManager.adjust_morale(morale_delta)

	_last_result = {
		"victory": victory,
		"rounds": rounds,
		"defense": encounter.is_defense,
		"rewards": rewards,
		"casualties": lost,
		"survivors": survivors,
		"morale_delta": morale_delta,
		# Para que el parte de la defensa pueda decir cuánto pusieron las torres.
		"tower_crews": crew_uids.size(),
		"tower_crews_lost": fallen.size() - roster_fallen.size(),
	}
	return _last_result

## Quita del recuento a las unidades que no pertenecen al ejército del jugador.
func _roster_only(units: Array, crew_uids: Dictionary) -> Array:
	var result: Array = []
	for unit in units:
		if not crew_uids.has(unit.uid):
			result.append(unit)
	return result

## The outcome of the last encounter, for the UI to show. Empty before the first.
func get_last_result() -> Dictionary:
	return _last_result

func _count_by_unit(units: Array) -> Dictionary:
	var tally: Dictionary = {}
	for unit in units:
		tally[unit.unit_id] = int(tally.get(unit.unit_id, 0)) + 1
	return tally

func _resource_type(res_name: String) -> int:
	match res_name:
		"steel":
			return ResourceManager.Type.STEEL
		"oil":
			return ResourceManager.Type.OIL
		"wood":
			return ResourceManager.Type.WOOD
		_:
			return ResourceManager.Type.GOLD

# ── Expedition (T025, T028, T030-T033) ───────────────────────────────

func has_active_expedition() -> bool:
	return _expedition != null and _expedition.is_active()

## La expedicion en curso, para que la UI la lea. Null si no hay. Nadie fuera de
## este servicio la muta (constitucion, principio IV).
func get_expedition() -> Expedition:
	return _expedition

## unit_id -> count de todo el party, vivos y caidos. Los caidos cuentan porque
## ArmyManager sigue teniendolos hasta que la expedicion se resuelve; ArmyPanel
## los pinta "en campana" y get_deployable_units() los descuenta.
func get_units_on_expedition() -> Dictionary:
	if _expedition == null:
		return {}
	var counts: Dictionary = {}
	for unit in _expedition.party:
		counts[unit.unit_id] = int(counts.get(unit.unit_id, 0)) + 1
	return counts

## True entre ganar un nodo y elegir la carta. Mientras dure no se elige ruta.
func has_pending_draft() -> bool:
	return _draft_pending

## Las cartas sobre la mesa, en el orden que espera apply_draft(index). Vacio si
## no hay draft pendiente.
func get_draft_options() -> Array:
	return _draft_options.duplicate(true) if _draft_pending else []

## Por que no se puede salir, si no se puede. `reason` es una clave de Tr para
## que la UI la traduzca (FR-002). Las comprobaciones de estado van primero
## porque no dependen de lo que el jugador haya marcado.
func can_launch(party: Dictionary) -> Dictionary:
	if has_active_expedition():
		return {"ok": false, "reason": "MSG_EXPEDITION_ACTIVE"}
	if is_in_encounter():
		return {"ok": false, "reason": "MSG_ENCOUNTER_ACTIVE"}
	# Con la Regencia convocada o ya en la puerta, la guarnicion no sale: la
	# Auditoria Final se pelea con lo que hay en casa, y mandarla fuera ahora
	# seria regalarles la partida.
	if ProgressionManager.is_final_audit_pending() or ProgressionManager.is_final_audit_active():
		return {"ok": false, "reason": "MSG_AUDIT_BLOCKS_EXPEDITION"}
	var total: int = roster_size(party)
	if total <= 0:
		return {"ok": false, "reason": "MSG_NO_UNITS"}
	if total > GameConfig.combat_deploy_cap:
		return {"ok": false, "reason": "MSG_DEPLOY_CAP_EXCEEDED"}
	var available: Dictionary = get_deployable_units()
	for unit_id in party:
		var wanted: int = int(party[unit_id])
		if wanted < 0 or wanted > int(available.get(unit_id, 0)):
			return {"ok": false, "reason": "MSG_UNITS_UNAVAILABLE"}
	return {"ok": true, "reason": ""}

## Saca la columna. Crea la expedicion con una semilla nueva (o la dada, para
## reproducir una partida) y la moral que la base tiene ahora mismo, avisa y
## abre el tablero del nodo 0. Las unidades NO se descuentan de ArmyManager:
## siguen contando en el Poder Militar hasta que se sepa quien vuelve.
func launch_expedition(party: Dictionary, seed_value: int = 0) -> bool:
	if not bool(can_launch(party).get("ok", false)):
		return false
	var committed: Dictionary = {}
	for unit_id in party:
		if int(party[unit_id]) > 0:
			committed[String(unit_id)] = int(party[unit_id])
	_expedition = ExpeditionScript.create(
		_next_expedition_id, seed_value if seed_value != 0 else _new_seed(),
		committed, _read_morale(), ProgressionManager.current_era
	)
	_next_expedition_id += 1
	_morale_snapshot = _expedition.morale_snapshot
	_clear_draft()
	_expedition_followups = []
	EventBus.expedition_started.emit(_expedition.id, _expedition.map.size())
	enter_current_node()
	return true

## Elige la ruta. Solo una salida del nodo actual, y solo con la carta del draft
## ya elegida; despues abre el tablero del nodo elegido.
func select_node(node_index: int) -> bool:
	if not has_active_expedition() or is_in_encounter() or _draft_pending:
		return false
	if not _expedition.can_select(node_index):
		return false
	_publish_expedition_events(_expedition.select_node(node_index))
	return enter_current_node()

## Abre el tablero del nodo en el que esta el party. Lo usan el lanzamiento y
## select_node(), y es lo que la UI llama al reanudar una partida guardada a
## mitad de nodo (D6): el encuentro no se guarda, asi que se vuelve a desplegar
## desde cero, con las unidades y el HP tal como estaban.
##
## Las CombatUnit que entran son las mismas instancias de Expedition.party: el
## tablero les pega directamente, y por eso un superviviente llega tocado al
## siguiente nodo y un caido no vuelve a formar (FR-010, FR-011).
func enter_current_node() -> bool:
	if not has_active_expedition() or is_in_encounter() or _draft_pending:
		return false
	var node: Dictionary = _expedition.current_node_data()
	if node.is_empty() or bool(node.get("cleared", false)):
		return false
	if _expedition.is_party_wiped():
		# Sin nadie en pie no hay tablero que abrir: la campana termino.
		_publish_expedition_events(_expedition.mark_defeated())
		return false
	if _encounter != null:
		# Un tablero ya resuelto que la UI aun no cerro.
		end_encounter()
	_morale_snapshot = _expedition.morale_snapshot
	_open_board(
		_expedition.build_encounter_units(), bool(node.get("is_boss", false)),
		int(node.get("index", _expedition.current_node)), false, []
	)
	return true

## El jugador elige una carta del draft. El bono vive en las unidades y muere
## con la expedicion (FR-018). NO abre el siguiente tablero: la ruta se elige
## aparte con select_node().
func apply_draft(option_index: int) -> bool:
	if not has_active_expedition() or not _draft_pending:
		return false
	if option_index < 0 or option_index >= _draft_options.size():
		return false
	var events: Array = _expedition.apply_draft(_draft_options[option_index])
	if events.is_empty():
		return false
	_clear_draft()
	_publish_expedition_events(events)
	return true

## Volver a casa antes de tiempo, con el botin y los supervivientes (FR-016).
## Si hay tablero abierto se cierra sin aplicar resultado: quien sigue en pie
## se retira, y los caidos ya estan anotados en el party.
func abandon_expedition() -> bool:
	if not has_active_expedition():
		return false
	if _encounter != null:
		_result_applied = true
		end_encounter()
	_clear_draft()
	_publish_expedition_events(_expedition.abandon())
	return true

## Un encuentro de expedicion acaba de resolverse. Aqui no se toca la base: el
## modelo apunta el botin del nodo y decide si toca draft o si la campana ha
## terminado; eso se publica despues de encounter_ended (ver _emit_events).
func _apply_expedition_encounter(victory: bool, rounds: int) -> void:
	var fallen: Dictionary = _count_by_unit(_encounter.casualties(Encounter.PLAYER))
	var survivors: Dictionary = _count_by_unit(_encounter.survivors())
	# Los supervivientes bajan del tablero ya, con su daño puesto: son las mismas
	# instancias que viven en Expedition.party y asi entran al siguiente nodo.
	_encounter.release_survivors()

	var before: Dictionary = _expedition.rewards.duplicate()
	_expedition_followups = _expedition.mark_cleared() if victory else _expedition.mark_defeated()
	var gained: Dictionary = {}
	for res_name in _expedition.rewards:
		var delta: int = int(_expedition.rewards[res_name]) - int(before.get(res_name, 0))
		if delta > 0:
			gained[res_name] = delta

	_last_result = {
		"victory": victory,
		"rounds": rounds,
		"defense": false,
		"expedition": true,
		# Lo que pago este nodo y lo que costo. Nada de esto ha llegado aun al
		# almacen ni al cuartel: se liquida en _resolve_expedition().
		"rewards": gained,
		"casualties": fallen,
		"survivors": survivors,
		"morale_delta": 0,
		"tower_crews": 0,
		"tower_crews_lost": 0,
	}

func _publish_expedition_followups() -> void:
	var events: Array = _expedition_followups
	_expedition_followups = []
	_publish_expedition_events(events)

## Vuelca los eventos del modelo de expedicion al EventBus. Es el equivalente
## de _emit_events() para Expedition: el modelo nunca emite nada por su cuenta.
func _publish_expedition_events(events: Array) -> void:
	for event in events:
		match event.get("e", ""):
			"expedition_node_selected":
				EventBus.expedition_node_selected.emit(int(event["index"]))
			"node_cleared":
				# El jefe no da carta: da la campana entera, y eso viene detras.
				if not bool(event.get("is_boss", false)):
					_offer_draft()
			"draft_applied":
				EventBus.draft_applied.emit(event["option"])
			"expedition_ended":
				_resolve_expedition(int(event["result"]))

## Pone las cartas sobre la mesa. Salen de la semilla y del nodo, asi que
## reabrir la partida ensena las mismas.
func _offer_draft() -> void:
	if not has_active_expedition():
		return
	var options: Array = _expedition.draft_options()
	if options.is_empty():
		# Sin nadie vivo a quien mejorar no hay nada que ofrecer.
		return
	_draft_options = options
	_draft_pending = true
	EventBus.draft_offered.emit(options.duplicate(true))

func _clear_draft() -> void:
	_draft_pending = false
	_draft_options = []

## La liquidacion, una sola vez por campana: el botin entra al almacen (el pool
## compartido ya recorta y avisa por storage_overflow), los caidos salen del
## ejercito, los supervivientes vuelven enteros —basta con soltar el party, su
## HP solo existia aqui— y la moral del pueblo se mueve segun como fue (FR-017,
## FR-018, D8). Al final, expedition_ended, y la base vuelve a ser la base.
func _resolve_expedition(result: int) -> void:
	if _expedition == null:
		return
	# El tablero del ultimo nodo se cierra aqui, no en la interfaz: cuando la
	# campana termina por el jefe o por aniquilacion, el parte final sustituye al
	# del encuentro y con el desaparece el boton que llamaba a end_encounter().
	# Un _encounter colgado deja is_board_open() en true para siempre, y a partir
	# de ahi todo Diezmo se resuelve a ciegas y el asedio se da por perdido sin
	# jugarse una sola oleada.
	if _encounter != null:
		end_encounter()

	var summary: Dictionary = _expedition.result_summary()
	var rewards: Dictionary = summary.get("rewards", {})
	for res_name in rewards:
		ResourceManager.add(_resource_type(String(res_name)), int(rewards[res_name]))

	var lost: Dictionary = ArmyManager.remove_units(summary.get("casualties", {}))
	var dead: int = 0
	for count in lost.values():
		dead += int(count)
	# Misma formula que la escaramuza suelta: ganar levanta, cada caido hunde.
	# Abandonar no es ganar, pero tampoco cuesta mas que sus muertos.
	var morale_delta: int = Rules.morale_delta(result == Expedition.RESULT_WON, dead)
	if morale_delta != 0:
		PopulationManager.adjust_morale(morale_delta)

	_last_result = {
		"victory": result == Expedition.RESULT_WON,
		"rounds": int(_last_result.get("rounds", 0)),
		"defense": false,
		"expedition": true,
		"result": result,
		"rewards": rewards.duplicate(),
		"casualties": lost.duplicate(),
		"survivors": summary.get("survivors", {}),
		"morale_delta": morale_delta,
		"nodes_cleared": int(summary.get("nodes_cleared", 0)),
		"boss_defeated": bool(summary.get("boss_defeated", false)),
		"tower_crews": 0,
		"tower_crews_lost": 0,
	}

	_expedition = null
	_clear_draft()
	_expedition_followups = []
	EventBus.expedition_ended.emit(result, rewards.duplicate(), lost.duplicate())

func _new_seed() -> int:
	var value: int = randi()
	# Cero es "sin semilla" para launch_expedition(); que nunca salga por azar.
	return value if value != 0 else 1

# ── Dev helper (T014) ────────────────────────────────────────────────

## Starts a standalone encounter with whatever the player has trained, so the
## board can be exercised before the expedition layer exists.
func dev_start_encounter() -> bool:
	if not GameConfig.dev_mode or has_active_expedition():
		return false
	var party: Dictionary = {}
	var committed := 0
	var available: Dictionary = get_deployable_units()
	for unit_id in GameConfig.get_unit_ids():
		for i in int(available.get(unit_id, 0)):
			if committed >= GameConfig.combat_deploy_cap:
				break
			party[unit_id] = int(party.get(unit_id, 0)) + 1
			committed += 1
	if party.is_empty():
		return false
	start_encounter(party, {"infantry": 2, "artillery": 1}, false, 0)
	return true

# ── Persistence ──────────────────────────────────────────────────────

func _read_morale() -> float:
	if PopulationManager.has_method("get_morale"):
		return float(PopulationManager.get_morale())
	return 50.0

## Lo que va en data["expedition"]: nada si no hay campana, o el to_dict() del
## modelo (el mapa no se guarda, se regenera de la semilla — D5/D6). Encima va
## `draft_pending`, que es estado de este servicio y no del modelo: una carta
## ofrecida y sin elegir se vuelve a ofrecer al cargar, y son las mismas cartas
## porque salen de la semilla y del nodo.
##
## El encuentro a medias NO se guarda: el party va con el HP que tiene ahora
## mismo y el nodo sin limpiar, y al cargar se vuelve a desplegar desde cero.
func get_save_data() -> Dictionary:
	if not has_active_expedition():
		return {}
	var data: Dictionary = _expedition.to_dict()
	data["draft_pending"] = _draft_pending
	return data

## Reconstruye la campana guardada y avisa con expedition_resumed para que la UI
## abra el mapa en el nodo actual (D6); el tablero lo abre la UI llamando a
## enter_current_node(). Sin clave, dict vacio o campana ya terminada = no hay
## expedicion, que es exactamente lo que dice un save anterior a esta feature
## (constitucion, principio V).
func load_save_data(data: Dictionary) -> void:
	_clear_runtime_state()
	var run: Expedition = ExpeditionScript.from_dict(data, ProgressionManager.current_era)
	if run == null or not run.is_active():
		return
	_expedition = run
	_next_expedition_id = maxi(_next_expedition_id, run.id + 1)
	_morale_snapshot = run.morale_snapshot
	EventBus.expedition_resumed.emit(run.id)
	var node: Dictionary = run.current_node_data()
	if bool(data.get("draft_pending", false)) and bool(node.get("cleared", false)) and not run.at_boss():
		_offer_draft()

func reset() -> void:
	_clear_runtime_state()
	_next_expedition_id = 1

## Todo lo que este servicio se inventa mientras se juega: el tablero, la
## campana, el parte, las marcas del asedio y los contadores. Lo unico que NO
## limpia es `_next_expedition_id`, porque partida nueva y partida cargada no
## opinan lo mismo de el: la nueva lo devuelve a 1 y la cargada lo empuja por
## encima de la campana que trae.
##
## load_save_data() pasa por aqui aunque hoy no le haga falta: la carga solo
## ocurre con los autoloads recien arrancados, asi que todo esto ya estaba a cero
## y el comportamiento observable no cambia ni un paso. Lo que cambia es que deja
## de estar minado para el dia que se cargue en caliente —guardado en la nube,
## ranuras de partida—, cuando la carga entraria sobre un servicio usado y se
## traeria el parte de la partida anterior, el asedio a medias y un
## `_tower_crew_uids` que no es de ningun tablero.
func _clear_runtime_state() -> void:
	_encounter = null
	_expedition = null
	_clear_draft()
	_expedition_followups = []
	_enemy_turn_running = false
	_audit_wave_active = false
	_audit_wave_won = false
	_audit_crews.clear()
	_audit_crew_losses = 0
	_next_uid = 1
	_result_applied = false
	_last_result = {}
	_tower_crew_uids.clear()
	_last_board_crew_uids.clear()
