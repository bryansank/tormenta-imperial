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
const ExpeditionGeneratorScript := preload("res://scripts/combat/ExpeditionGenerator.gd")
const SortieBoardScript := preload("res://scripts/combat/SortieBoard.gd")
const CampaignBookScript := preload("res://scripts/combat/CampaignBook.gd")

## El tablon de salidas (doc 21 §3, 2026-10-14): la incursion y la expedicion a
## la vista, cuando llega la siguiente, los planos conseguidos y la rebaja del
## Diezmo pendiente. Modelo puro; este servicio le da el reloj y las semillas.
var _sorties: SortieBoard = SortieBoardScript.new()
var _sortie_timer: Timer = null
## Las tres campanas (feat/tres-campanas): Tierra, Mar y Aire. Cuantas misiones
## lleva cada una y cuando toca la siguiente. Modelo puro; clave "campaigns".
var _campaigns: CampaignBook = CampaignBookScript.new()
## True mientras "resolver solo" juega el tablero de un tiron: el parte lo dice.
var _auto_resolving: bool = false

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
## Numero de tablero. Sube cada vez que un tablero se abre o se cierra. El turno
## enemigo es una corrutina que espera entre pasos: si el tablero cambia mientras
## espera, al despertar ve otro numero y se retira sin tocar nada. Sin esto,
## cerrar un tablero con la IA pensando y abrir otro dejaba dos bucles enemigos
## corriendo a la vez sobre el nuevo.
var _board_generation: int = 0
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
## uids del tablero actual cuya muerte ya se liquido en caliente (ver
## _settle_audit_death). Solo lo usan las oleadas del asedio.
var _audit_charged: Dictionary = {}
## Una oleada del asedio que llego con otro tablero en pantalla. No se da por
## perdida: espera a que ese tablero se cierre y entonces baja.
var _audit_wave_queued: bool = false

## Edificios militares (feat/edificios-militares): Enfermeria y Campo de tiro.
const Military := preload("res://scripts/buildings/MilitaryBuildings.gd")
## La leccion del simulacro que va a abrir el proximo _open_board ("" = no es
## un simulacro). Se consume al abrir.
var _pending_practice: String = ""

func _ready() -> void:
	EventBus.final_audit_wave_ready.connect(_on_final_audit_wave_ready)
	# El Diezmo gasta el apunte de la rebaja y se lleva la avanzadilla no echada.
	EventBus.tithe_resolved.connect(func(_paid, _taken): _publish_sortie_events(_sorties.on_tithe_resolved()))
	# Un reloj lento y barato: mira dos fechas y, si toca, sortea una oferta.
	# Pausable: con el juego parado no aparece nada.
	_sortie_timer = Timer.new()
	_sortie_timer.name = "SortieTimer"
	_sortie_timer.wait_time = maxf(0.25, GameConfig.combat_sortie_refresh_interval)
	_sortie_timer.process_mode = Node.PROCESS_MODE_PAUSABLE
	_sortie_timer.timeout.connect(refresh_sorties)
	add_child(_sortie_timer)
	_sortie_timer.start()

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

## Se puede guardar sin mentir. El tablero no se guarda nunca (D6), asi que con
## una pelea en juego el save captaria unidades a medio herir sobre un nodo sin
## limpiar. Tampoco con el parte de una oleada del asedio en pantalla: su
## resultado no llega a FinalAudit hasta que se cierra (end_encounter), y un save
## en ese hueco traeria la guarnicion herida a repetir la misma oleada. Con el
## parte de cualquier otra pelea delante, el resultado ya esta liquidado.
func is_save_safe() -> bool:
	if _encounter == null:
		return true
	if _encounter.is_active():
		return false
	return _result_applied and not _audit_wave_active

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
	var committed: Dictionary = get_units_away()
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

	var encounter: Encounter = EncounterScript.create(units, 0, false, true, crew_uids.keys(), false, home_terrain(units))
	apply_home_cover(encounter)
	var outcome: Dictionary = AutoResolverScript.resolve(encounter)
	var victory: bool = bool(outcome["victory"])
	var rounds: int = int(outcome["rounds"])
	var summary: Dictionary = _apply_result_for(encounter, victory, rounds, crew_uids)
	EventBus.defense_auto_resolved.emit(victory, rounds, summary)
	return {"fought": true, "victory": victory, "rounds": rounds, "summary": summary}

## Una oleada del asedio pide tablero. Los defensores son la guarnicion viva que
## lleva FinalAudit —con el daño de la oleada anterior— mas las dotaciones de
## torre que sigan en pie. Sin relevos: lo que cae, cae.
func _on_final_audit_wave_ready(_wave: int, roster: Dictionary, scale: float) -> void:
	var audit = ProgressionManager.final_audit
	if audit == null:
		return
	# Con otro tablero abierto la oleada no cabe, y antes eso contaba como oleada
	# perdida: Diezmo maximo y daño maximo por haber pulsado en mal momento. Ahora
	# espera en la puerta; end_encounter() la deja bajar al cerrarse el tablero.
	if is_board_open():
		_audit_wave_queued = true
		return
	_audit_wave_queued = false
	var defenders: Array = audit.living_garrison().duplicate()
	# Las dotaciones se fabrican aqui, antes de _open(): sin esto nacerian con los
	# uids 1 y 2, los mismos que la guarnicion, y no llegarian a actuar nunca.
	_reserve_uids(defenders)

	_morale_snapshot = _read_morale()
	# Una torre no se cansa, una dotacion si muere. Cada oleada las torres en pie
	# vuelven a mandar gente entera, pero las dotaciones caidas en lo que va de
	# asedio no se reemplazan. La cuenta vive en FinalAudit (y con el, en el
	# guardado): una dotacion muerta antes de cargar sigue muerta despues.
	var counts: Dictionary = {}
	for unit in defenders:
		counts[unit.unit_id] = int(counts.get(unit.unit_id, 0)) + 1
	var wanted: int = roster_size(get_tower_crews(counts)) - int(audit.crew_losses)
	var audit_crews: Array = []
	if wanted > 0:
		audit_crews = _build_side({GameConfig.storm_tower_garrison_unit: wanted}, Encounter.PLAYER, 1.0)
	# Quien las fabrica es quien dice quienes son. La lista viaja hasta el tablero
	# en la misma llamada: ninguna decision sobre "esto es dotacion" pasa por lo
	# que dejo apuntado un tablero que ya no existe.
	var crew_uids: Array = []
	for crew in audit_crews:
		crew_uids.append(crew.uid)
	defenders.append_array(audit_crews)

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
## solo lo que se quedo. Y quien esta en un tablero abierto tampoco: un Diezmo
## resuelto a ciegas durante una escaramuza alistaba a las mismas unidades que
## estaban peleandola, y sus bajas se cobraban dos veces.
##
## Los huecos se llenan de la unidad mas fuerte a la mas debil. Antes se llenaban
## en el orden del diccionario (infanteria primero), asi que quien guardaba tres
## infantes de la era 1 y luego entrenaba seis blindados para el final defendia el
## asedio con 3 infantes y 3 blindados: la mitad de su mejor tropa se quedaba
## mirando, y la Auditoria pasaba de ganarse 4 de cada 5 veces a casi nunca.
func get_garrison() -> Dictionary:
	var away: Dictionary = get_units_away()
	var garrison: Dictionary = {}
	var committed := 0
	var by_strength: Array = GameConfig.get_unit_ids()
	by_strength.sort_custom(func(a, b) -> bool:
		return int(GameConfig.get_unit_def(a).get("power", 0)) > int(GameConfig.get_unit_def(b).get("power", 0)))
	for unit_id in by_strength:
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
	for info in GridManager.buildings_view():
		var data: BuildingData = info["data"]
		if data == null or data.id != GameConfig.storm_tower_building_id:
			continue
		if BuildingHealth.is_operational(info["node"]):
			standing += 1
	return standing

## Una dotacion que cae en un tablero deja su torre **dañada** (decision de
## Bryan, 2026-10-04): la torre no se defiende sola, alguien tiene que
## reparar el puesto que se quedo sin gente. Daña una torre en pie por cada
## dotacion caida, la mas entera primero, en `storm_tower_crew_loss_damage` de
## su vida maxima, y **nunca la deja en ruinas**: sigue mitigando y poniendo dotacion,
## pero hay que pagar la reparacion. Devuelve cuantas torres dañó.
func damage_towers_for_lost_crews(crews_lost: int) -> int:
	if crews_lost <= 0:
		return 0
	var towers: Array = []
	for info in GridManager.buildings_view():
		var data: BuildingData = info["data"]
		if data == null or data.id != GameConfig.storm_tower_building_id:
			continue
		if BuildingHealth.is_operational(info["node"]):
			towers.append(info["node"])
	towers.sort_custom(func(a, b): return BuildingHealth.get_health(a) > BuildingHealth.get_health(b))
	var damaged: int = 0
	for node in towers:
		if damaged >= crews_lost:
			break
		var max_health: int = BuildingHealth.get_max_health(node)
		var amount: int = maxi(1, roundi(float(max_health) * GameConfig.storm_tower_crew_loss_damage))
		amount = mini(amount, BuildingHealth.get_health(node) - 1)
		if amount <= 0:
			continue
		BuildingHealth.damage_building(node, amount)
		damaged += 1
	return damaged

## Cuántas unidades suma un roster unit_id -> count.
func roster_size(roster: Dictionary) -> int:
	var total := 0
	for count in roster.values():
		total += int(count)
	return total

## True while the current fight is a defence of the base.
func is_defending() -> bool:
	return _encounter != null and _encounter.is_defense

## True while the open board is a SIMULACRO of the Firing range (no real losses).
func is_practice() -> bool:
	return _encounter != null and _encounter.is_practice

## La leccion del simulacro abierto ("" si no lo es).
func practice_lesson() -> String:
	return _encounter.practice_lesson if is_practice() else ""

## Por que no se puede abrir un simulacro ahora (clave de Tr), o "" si se puede.
func practice_block_reason() -> String:
	if not Military.firing_range_working() and not GameMode.all_unlocked():
		return "PRACTICE_WHY_NO_RANGE"
	if is_board_open():
		return "PRACTICE_WHY_BOARD"
	if has_active_expedition():
		return "PRACTICE_WHY_EXPEDITION"
	if ProgressionManager.is_final_audit_active():
		return "PRACTICE_WHY_AUDIT"
	return ""

## SIMULACRO (doc 21 §4.4): abre el tablero de la leccion `lesson_id` con su
## tropa de practica (no sale del ejercito; lleva la doctrina activa) contra
## munecos. Nada de lo que pase toca la base salvo el premio de la primera
## victoria (ArmyManager.complete_practice).
func start_practice(lesson_id: String) -> bool:
	var lesson: Dictionary = GameConfig.get_practice_lesson(lesson_id)
	if lesson.is_empty() or practice_block_reason() != "":
		return false
	# Moral neutra: la practica no depende de como este el pueblo.
	_morale_snapshot = 50.0
	var player_units: Array = _build_side(lesson.get("player", {}), Encounter.PLAYER, 1.0)
	_pending_practice = lesson_id
	_open(player_units, lesson.get("enemy", {}), false, 0, false, [],
		float(lesson.get("enemy_scale", 0.5)))
	return true

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
##
## `terrain` (aire y mar, docs/15 §11): el de la expedicion lo da su nodo; para
## el resto (Diezmo, asedio, escaramuza) null = el de casa (home_terrain): agua
## solo si en el bando del jugador hay barcos.
func _open_board(units: Array, is_boss: bool, encounter_index: int, is_defense: bool, crew_uids: Array, can_rout: bool = false, terrain: Variant = null) -> void:
	_reserve_uids(units)
	_auto_resolving = false
	_tower_crew_uids.clear()
	_audit_charged.clear()
	for uid in crew_uids:
		_tower_crew_uids[int(uid)] = true

	# Las dotaciones de torre forman en la retaguardia: son artilleria con alcance
	# minimo 2, y en cabeza se quedan mudas justo cuando el enemigo llega a
	# contacto. Es la misma lista que ya se usa para no contarlas como bajas.
	# La retirada enemiga solo en los tableros de la columna (D7 = B): quien abre
	# un nodo de expedicion o incursion la pide; el Diezmo y el asedio, no.
	var board_terrain: Dictionary = home_terrain(units) if terrain == null else (terrain as Dictionary)
	_encounter = EncounterScript.create(units, encounter_index, is_boss, is_defense, crew_uids, can_rout, board_terrain)
	# Simulacro del Campo de tiro: se marca antes de avisar a nadie, para que
	# el titulo del tablero ya lo sepa (BattleScreen) y la liquidacion lo salte.
	_encounter.is_practice = _pending_practice != ""
	_encounter.practice_lesson = _pending_practice
	_pending_practice = ""
	if is_defense:
		apply_home_cover(_encounter)
	_board_generation += 1
	_enemy_turn_running = false
	_result_applied = false
	EventBus.encounter_started.emit(encounter_index, is_boss)
	_publish(_encounter.start())

## La cobertura del Bastion en un tablero de defensa (Impuesto y asedio,
## feat/edificios-defensa-vida): las casillas que dice
## GameConfig.defense_cover_cells (DefenseLifeEffects, al construir/derribar),
## en la fila de atras del jugador, con `bastion_cover_defense` de defensa de
## mas. Sin bastiones en pie no hace nada: el tablero de siempre.
func apply_home_cover(encounter: Encounter) -> void:
	if encounter == null or not encounter.is_defense:
		return
	var count: int = GameConfig.defense_cover_cells
	if count <= 0:
		return
	var row: int = encounter.board_size.y - 1
	encounter.set_cover(Rules.cover_cells(encounter.board_size, encounter.terrain, count, row),
		GameConfig.bastion_cover_defense)

## El tablero de casa (Diezmo, Ataque Final, escaramuza de pruebas). Decision de
## aire y mar (2026-10-17): tiene agua SOLO si en el bando del jugador hay algun
## barco — tu flota guarda la costa y el combate se da en la playa. Sin barcos
## es todo tierra, como siempre, y el equilibrio del Diezmo y del asedio de las
## partidas sin flota no cambia ni una casilla. La costa de casa es siempre la
## misma (combat_home_coast_seed). Los aviones no necesitan agua.
func home_terrain(units: Array) -> Dictionary:
	for unit in units:
		if unit.side == Encounter.PLAYER and unit.domain() == CombatUnit.DOMAIN_SEA:
			return Rules.coastal_terrain(GameConfig.combat_board_size, GameConfig.combat_home_coast_seed)
	return {}

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

## Pelea suelta con el party que el jugador acaba de comprometer. El enemigo es
## el mismo que el del primer nodo de una expedicion (profundidad 0, riesgo bajo),
## sacado de ExpeditionGenerator con su propia semilla: el roster provisional sin
## semilla que vivia aqui se fue, y con el la segunda formula de "cuanto enemigo
## toca". `seed_value` = 0 tira una semilla nueva; otra cosa reproduce la pelea.
func start_skirmish(party: Dictionary, seed_value: int = 0) -> bool:
	if party.is_empty() or is_in_encounter() or has_active_expedition():
		return false
	var era: int = ProgressionManager.current_era
	var rng: RandomNumberGenerator = ExpeditionGeneratorScript.make_rng(
		seed_value if seed_value != 0 else _new_seed())
	var roster: Dictionary = ExpeditionGeneratorScript.enemy_roster(rng, 0, era, 0)
	start_encounter(party, roster, false, 0, false, {}, ExpeditionGeneratorScript.enemy_scale(0, era, 0))
	return true

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
	_board_generation += 1
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
	elif _audit_wave_queued:
		# Diferido: quien cierra este tablero puede seguir trabajando despues
		# (_resolve_expedition publica su parte, BattleScreen recoloca vistas), y
		# abrir la oleada en mitad de eso la esconderia nada mas abrirla.
		call_deferred("_release_queued_audit_wave")
	# Al final: si report_audit_wave abrio la oleada siguiente, quien escucha
	# ve el tablero nuevo abierto y sigue esperando.
	EventBus.encounter_closed.emit()

## Deja bajar la oleada que esperaba en la puerta, si sigue habiendo asedio y el
## tablero sigue libre. Si otro tablero se abrio entretanto, vuelve a esperar.
func _release_queued_audit_wave() -> void:
	if not _audit_wave_queued:
		return
	var audit = ProgressionManager.final_audit
	if audit == null or not audit.is_active():
		_audit_wave_queued = false
		return
	var wave: Dictionary = audit.current_wave_data()
	if wave.is_empty():
		_audit_wave_queued = false
		return
	_on_final_audit_wave_ready(int(wave["index"]), wave["roster"].duplicate(), float(wave["scale"]))

## Por que no se puede llamar ahora a la Regencia, como clave de Tr; vacio si se
## puede. El asedio se pelea en casa y con el tablero libre: con otro tablero
## abierto la oleada no tendria donde bajar, y con la columna fuera la guarnicion
## que se pasaria lista no seria la de la base.
func final_audit_block_reason() -> String:
	if is_board_open():
		return "MSG_AUDIT_BOARD_BUSY"
	if has_active_expedition():
		return "MSG_AUDIT_EXPEDITION_OUT"
	return ""

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
				if _audit_wave_active:
					_settle_audit_death(int(event["uid"]))
				EventBus.unit_died.emit(event["uid"], event["side"])
			"enemy_routed":
				EventBus.enemy_routed.emit()
			"encounter_ended":
				# The base learns the outcome before anyone is told the fight is
				# over, so the UI reading get_last_result() always sees it applied.
				_apply_result(event["victory"], event["rounds"])
				# Como acabo: el parte dice si se retiraron o si se resolvio solo.
				_last_result["routed"] = bool(event.get("routed", false))
				_last_result["auto_resolved"] = _auto_resolving
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
	var generation: int = _board_generation
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
		# process_always = false: con el juego en pausa el enemigo tambien espera.
		# El valor por defecto (true) le dejaba seguir jugando detras del menu.
		await get_tree().create_timer(delay, false).timeout
		# El tablero por el que se empezo a pensar ya no esta: este bucle no es de
		# nadie. Ni actua, ni suelta la bandera, ni relanza turno: el tablero nuevo
		# tiene (o tendra) su propio bucle.
		if generation != _board_generation:
			return
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
		# Emitir puede cerrar este tablero y abrir otro (una oleada que acaba y
		# encadena la siguiente): mismo criterio que tras la espera.
		if generation != _board_generation:
			return

	# The unit may have moved without attacking; close its turn either way.
	if _encounter != null and _encounter.is_active() and _encounter.active_unit() != null 			and _encounter.active_unit().uid == uid:
		_emit_events(_encounter.end_turn())
		if generation != _board_generation:
			return

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
	# Simulacro: ni bajas, ni moral, ni botin; solo el premio de la primera vez.
	if _encounter.is_practice:
		_apply_practice_result(victory, rounds)
		return
	if _audit_wave_active:
		_audit_wave_won = victory
		# Quien cayo sin que llegara su unit_died (no deberia pasar en partida,
		# pero el ledger no puede depender de ello) se liquida ahora, por el mismo
		# camino y una sola vez.
		for unit in _encounter.casualties(Encounter.PLAYER):
			_settle_audit_death(unit.uid)

	# Un nodo de expedicion no cobra ni entierra a nadie todavia: lo acumula el
	# modelo y se liquida todo junto al volver (FR-010, FR-011, FR-017). La
	# defensa de la base sigue su camino de siempre aunque haya columna fuera.
	if has_active_expedition() and not _encounter.is_defense:
		_apply_expedition_encounter(victory, rounds)
		return

	_apply_result_for(_encounter, victory, rounds, _tower_crew_uids, _audit_charged)

## El parte de un simulacro: nadie cae de verdad, la moral no se mueve y solo
## la primera victoria de cada leccion paga (ArmyManager.complete_practice).
func _apply_practice_result(victory: bool, rounds: int) -> void:
	var lesson: String = _encounter.practice_lesson
	var reward: Dictionary = ArmyManager.complete_practice(lesson, victory)
	_last_result = {
		"victory": victory,
		"rounds": rounds,
		"defense": false,
		"practice": true,
		"lesson": lesson,
		"rewards": reward,
		"casualties": {},
		"survivors": _count_by_unit(_encounter.survivors()),
		"morale_delta": 0,
		"tower_crews": 0,
		"tower_crews_lost": 0,
		"towers_damaged": 0,
	}

## Una unidad del jugador cae en una oleada del asedio, y su baja se cobra YA, no
## al cerrar la oleada. La guarnicion del asedio son las mismas CombatUnit que
## pelean en el tablero, y el guardado se lleva su HP tal cual: si ArmyManager
## esperase al final de la oleada, una partida guardada a medias volveria con los
## muertos muertos en el asedio y vivos en el cuartel —cobrando paga, sumando
## Poder Militar, defendiendo Diezmos— porque al cargar la oleada se reintenta y
## nadie liquida lo que ya paso. Cobrando en el momento, lo guardado siempre
## cuadra: el cuartel y el asedio cuentan los mismos muertos.
##
## Una dotacion de torre no sale del ejercito: se anota en FinalAudit, que es
## quien decide cuantas manda cada oleada. Idempotente por uid.
func _settle_audit_death(uid: int) -> void:
	if _encounter == null or _audit_charged.has(uid):
		return
	var unit: CombatUnit = _encounter.get_unit(uid)
	if unit == null or unit.side != Encounter.PLAYER or unit.is_alive():
		return
	_audit_charged[uid] = true
	if _tower_crew_uids.has(uid):
		var audit = ProgressionManager.final_audit
		if audit != null:
			audit.record_crew_loss()
	else:
		ArmyManager.remove_units({unit.unit_id: 1})

## El mismo cierre para cualquier encuentro, este en el tablero o resuelto a
## ciegas por AutoResolver: `crew_uids` dice que unidades del jugador no
## pertenecen al ejercito. Deja el parte en get_last_result() y lo devuelve.
##
## `precharged` son uids cuya baja ya salio de ArmyManager en plena pelea (las
## oleadas del asedio, ver _settle_audit_death): cuentan en el parte y en la moral,
## pero no se vuelven a restar.
func _apply_result_for(encounter: Encounter, victory: bool, rounds: int, crew_uids: Dictionary, precharged: Dictionary = {}) -> Dictionary:
	# Las dotaciones de torre quedan fuera del recuento: no salieron del cuartel,
	# así que ni se restan del ejército ni cuentan como supervivientes que vuelven.
	var fallen: Array = encounter.casualties(Encounter.PLAYER)
	var roster_fallen: Array = _roster_only(fallen, crew_uids)
	var to_charge: Array = []
	var already: Array = []
	for unit in roster_fallen:
		if precharged.has(unit.uid):
			already.append(unit)
		else:
			to_charge.append(unit)
	var survivors: Dictionary = _count_by_unit(_roster_only(encounter.survivors(), crew_uids))

	# Enfermeria (feat/edificios-militares): tras una victoria vuelve uno de
	# cada tres caidos del ejercito. No en el asedio (sus bajas se cobran en
	# plena pelea, `precharged`) ni para las dotaciones de torre.
	var recovered: Dictionary = {}
	if victory and precharged.is_empty() and not _audit_wave_active and Military.infirmary_working():
		var back: Array = Rules.pick_recovered(to_charge,
			Rules.infirmary_returns(to_charge.size(), GameConfig.infirmary_return_every))
		for unit in back:
			to_charge.erase(unit)
		recovered = _count_by_unit(back)

	# ArmyManager is the source of truth for the roster: the party was never
	# deducted when it marched out, so only the dead are subtracted now and
	# Military Power lands exactly on the survivors.
	var lost: Dictionary = ArmyManager.remove_units(_count_by_unit(to_charge))
	for unit in already:
		lost[unit.unit_id] = int(lost.get(unit.unit_id, 0)) + 1

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
	var morale_delta: int = Rules.morale_delta(victory, dead, Military.morale_per_casualty())
	if morale_delta != 0:
		PopulationManager.adjust_morale(morale_delta)

	var crews_lost: int = fallen.size() - roster_fallen.size()
	var towers_damaged: int = damage_towers_for_lost_crews(crews_lost) if encounter.is_defense else 0

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
		"tower_crews_lost": crews_lost,
		# Torres que quedaron dañadas por perder su dotación (hay que repararlas).
		"towers_damaged": towers_damaged,
		# Lo que cayo del otro lado: el parte de una defensa resuelta a ciegas
		# tiene que contar las dos columnas, no solo la nuestra.
		"enemy_casualties": _count_by_unit(encounter.casualties(Encounter.ENEMY)),
		# Enfermeria: caidos que volvieron a casa en vez de morir.
		"recovered": recovered,
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
		"parts":
			return ResourceManager.Type.PARTS
		_:
			return ResourceManager.Type.GOLD

# ── Expedition (T025, T028, T030-T033) ───────────────────────────────

func has_active_expedition() -> bool:
	return _expedition != null and _expedition.is_active()

## El tablero abierto es un nodo de la expedicion en curso. Con columna fuera no
## se abre ningun otro tablero que no sea de defensa (start_skirmish() y el de
## pruebas se niegan), asi que "no es defensa" basta para saberlo.
func _is_expedition_board() -> bool:
	return _encounter != null and _expedition != null and not _encounter.is_defense

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

## unit_id -> count de las unidades del EJERCITO que estan ahora mismo en el
## tablero abierto y cuya suerte aun no se ha liquidado: vivas, y caidas cuya
## baja todavia no salio de ArmyManager. No cuentan las dotaciones de torre (no
## son del ejercito), ni un tablero cuyo resultado ya se aplico (los caidos ya se
## restaron y los supervivientes han vuelto a casa), ni el tablero de la
## expedicion (esas ya salen en get_units_on_expedition()).
func get_units_on_board() -> Dictionary:
	if _encounter == null or _result_applied or _is_expedition_board():
		return {}
	var counts: Dictionary = {}
	for unit in _encounter.units:
		if unit.side != Encounter.PLAYER or _tower_crew_uids.has(unit.uid):
			continue
		if not unit.is_alive() and _audit_charged.has(unit.uid):
			continue
		counts[unit.unit_id] = int(counts.get(unit.unit_id, 0)) + 1
	return counts

## Todo lo que no esta en casa: la columna de expedicion y quien pelea en el
## tablero abierto. Es lo que get_garrison(), get_deployable_units() y la
## desercion de ArmyManager restan antes de contar a nadie.
func get_units_away() -> Dictionary:
	var away: Dictionary = get_units_on_expedition()
	var board: Dictionary = get_units_on_board()
	for unit_id in board:
		away[unit_id] = int(away.get(unit_id, 0)) + int(board[unit_id])
	return away

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

## Lo mismo que can_launch(), sabiendo ademas a donde va la columna (aire y mar):
## los barcos solo salen a una mision con agua (de costa). `offer` vacio o
## {"kind": "first"} = la primera escaramuza, que es en tierra.
func can_launch_to(party: Dictionary, offer: Dictionary) -> Dictionary:
	var check: Dictionary = can_launch(party)
	if not bool(check.get("ok", false)):
		return check
	# Tres campanas: dominio puro. Solo tropa del medio de la campana, y de esa
	# solo la que puede pegar a ese medio (el bombardero no va a la de aire).
	if String(offer.get("kind", "")) == ExpeditionGeneratorScript.KIND_CAMPAIGN:
		var domain: String = String(offer.get("domain", "land"))
		for unit_id in party:
			if int(party[unit_id]) <= 0:
				continue
			var why: String = campaign_unit_block(String(unit_id), domain)
			if why != "":
				return {"ok": false, "reason": why}
		return check
	if party_has_ships(party) and not offer_has_water(offer):
		return {"ok": false, "reason": "MSG_SHIPS_NEED_WATER"}
	return check

## ¿Lleva barcos esta columna (unit_id -> cuantos)?
static func party_has_ships(party: Dictionary) -> bool:
	for unit_id in party:
		if int(party[unit_id]) > 0 and GameConfig.get_unit_domain(String(unit_id)) == CombatUnit.DOMAIN_SEA:
			return true
	return false

## ¿Tiene agua alguno de los combates de esta oferta del tablon?
func offer_has_water(offer: Dictionary) -> bool:
	if offer.is_empty() or String(offer.get("kind", "")) == "first":
		return false
	return ExpeditionGeneratorScript.map_has_water(offer_map(offer))

## Saca la columna. Crea la expedicion con una semilla nueva (o la dada, para
## reproducir una partida) y la moral que la base tiene ahora mismo, avisa y
## abre el tablero del nodo 0. Las unidades NO se descuentan de ArmyManager:
## siguen contando en el Poder Militar hasta que se sepa quien vuelve.
##
## `first_sortie`: en vez del mapa, la primera escaramuza de la partida (un solo
## nodo facil, docs/15-combat.md §4). Lo decide quien lanza preguntando
## is_first_sortie_due(); por defecto es una expedicion normal, que es lo que
## esperan los tests y las sondas que lanzan con semilla.
func launch_expedition(party: Dictionary, seed_value: int = 0, first_sortie: bool = false) -> bool:
	if not bool(can_launch(party).get("ok", false)):
		return false
	# La expedicion de siempre y la primera escaramuza son en tierra: sin barcos.
	if party_has_ships(party):
		return false
	var committed: Dictionary = {}
	for unit_id in party:
		if int(party[unit_id]) > 0:
			committed[String(unit_id)] = int(party[unit_id])
	_expedition = ExpeditionScript.create(
		_next_expedition_id, seed_value if seed_value != 0 else _new_seed(),
		committed, _read_morale(), ProgressionManager.current_era, first_sortie
	)
	_next_expedition_id += 1
	_morale_snapshot = _expedition.morale_snapshot
	_clear_draft()
	_expedition_followups = []
	EventBus.expedition_started.emit(_expedition.id, _expedition.map.size())
	enter_current_node()
	return true

## La siguiente salida de la base es la primera escaramuza: la partida aun no ha
## ganado ninguna (lo recuerda TutorialManager, en la partida). Mientras no se
## gane, cada salida vuelve a ser la facil; perderla o abandonarla no la gasta.
func is_first_sortie_due() -> bool:
	return not TutorialManager.is_first_sortie_done()

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
	# El terreno del nodo: agua si es de costa (aire y mar), todo tierra si no.
	_open_board(
		_expedition.build_encounter_units(), bool(node.get("is_boss", false)),
		int(node.get("index", _expedition.current_node)), false, [], true,
		_expedition.current_terrain(GameConfig.combat_board_size)
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
## Si el tablero abierto es el de la expedicion se cierra sin aplicar resultado:
## quien sigue en pie se retira, y los caidos ya estan anotados en el party.
##
## Solo el suyo. Un tablero de defensa (el Diezmo que cayo entre dos nodos) no es
## de la columna: cerrarlo aqui con el resultado dado por aplicado se tragaba el
## encounter_ended, y sin el StormManager se quedaba en TITHE para siempre. Esa
## defensa sigue abierta y se resuelve como cualquier otra.
func abandon_expedition() -> bool:
	if not has_active_expedition():
		return false
	if _is_expedition_board():
		_result_applied = true
		end_encounter()
	_clear_draft()
	_publish_expedition_events(_expedition.abandon())
	return true

## Un encuentro de expedicion acaba de resolverse. Aqui no se toca la base: el
## modelo apunta el botin del nodo y decide si toca draft o si la campana ha
## terminado; eso se publica despues de encounter_ended (ver _emit_events).
func _apply_expedition_encounter(victory: bool, rounds: int) -> void:
	var fallen_units: Array = _encounter.casualties(Encounter.PLAYER)
	var survivors: Dictionary = _count_by_unit(_encounter.survivors())
	# Los supervivientes bajan del tablero ya, con su daño puesto: son las mismas
	# instancias que viven en Expedition.party y asi entran al siguiente nodo.
	_encounter.release_survivors()

	# Enfermeria (feat/edificios-militares): ganado el combate, uno de cada tres
	# caidos de ESTE combate vuelve a casa (sale de la columna, no cuenta como
	# baja). Y la cura entre combates sube un 30 %.
	var recovered: Dictionary = {}
	var infirmary: bool = Military.infirmary_working()
	if victory and infirmary:
		var back: Array = Rules.pick_recovered(fallen_units,
			Rules.infirmary_returns(fallen_units.size(), GameConfig.infirmary_return_every))
		var uids: Array = []
		for unit in back:
			uids.append(unit.uid)
			fallen_units.erase(unit)
		recovered = _expedition.evacuate(uids)
	var fallen: Dictionary = _count_by_unit(fallen_units)
	_expedition.heal_mult = GameConfig.infirmary_heal_mult if infirmary else 1.0

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
		"towers_damaged": 0,
		"recovered": recovered,
	}
	# Lo que da este nodo de lo que solo se consigue fuera, y si la columna se
	# curo al seguir (expedicion corta). Para el parte del encuentro.
	_last_result["loot"] = (_expedition.current_node_data().get("loot", {}) as Dictionary).duplicate(true) if victory else {}
	for event in _expedition_followups:
		if String(event.get("e", "")) == "party_healed":
			_last_result["healed_pct"] = float(event.get("pct", 0.0))

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
	# Pero solo el de la columna: una defensa abierta en paralelo tiene su propio
	# parte y su propio Diezmo por liquidar.
	if _is_expedition_board():
		end_encounter()

	var summary: Dictionary = _expedition.result_summary()
	var rewards: Dictionary = summary.get("rewards", {})
	for res_name in rewards:
		ResourceManager.add(_resource_type(String(res_name)), int(rewards[res_name]))
	# Lo que solo se consigue fuera: repuestos, colonos, planos y la rebaja del
	# Diezmo. Como el oro, lo de los nodos ganados llega aunque se abandone.
	var loot: Dictionary = _apply_loot(summary.get("loot", {}))
	# La oferta del tablon vuelve si la columna no gano ningun combate (se puede
	# intentar otra vez) o deja paso a la siguiente tras el enfriamiento. Con un
	# combate ganado ya se cobro botin: si volviera entera, abandonar tras el
	# primero y relanzar seria repetir botin gratis.
	if not _expedition.offer.is_empty() and not _expedition.is_campaign():
		var spent: bool = result == Expedition.RESULT_WON or int(summary.get("nodes_cleared", 0)) > 0
		_publish_sortie_events(_sorties.finish(_expedition.offer, spent,
			_now(), _sortie_cooldown(_expedition.kind)))

	var lost: Dictionary = ArmyManager.remove_units(summary.get("casualties", {}))
	var dead: int = 0
	for count in lost.values():
		dead += int(count)
	# Misma formula que la escaramuza suelta: ganar levanta, cada caido hunde.
	# Abandonar no es ganar, pero tampoco cuesta mas que sus muertos.
	var morale_delta: int = Rules.morale_delta(result == Expedition.RESULT_WON, dead, Military.morale_per_casualty())
	if morale_delta != 0:
		PopulationManager.adjust_morale(morale_delta)

	_last_result = {
		"victory": result == Expedition.RESULT_WON,
		"rounds": int(_last_result.get("rounds", 0)),
		"defense": false,
		"expedition": true,
		"result": result,
		"rewards": rewards.duplicate(),
		"loot": loot,
		"kind": _expedition.kind,
		# Como acabo el ultimo combate: lo pone _emit_events justo antes.
		"routed": bool(_last_result.get("routed", false)),
		"auto_resolved": bool(_last_result.get("auto_resolved", false)),
		"casualties": lost.duplicate(),
		# Enfermeria: los que volvieron a casa en vez de caer, en toda la salida.
		"recovered": (summary.get("evacuated", {}) as Dictionary).duplicate(),
		"survivors": summary.get("survivors", {}),
		"morale_delta": morale_delta,
		"nodes_cleared": int(summary.get("nodes_cleared", 0)),
		"boss_defeated": bool(summary.get("boss_defeated", false)),
		"tower_crews": 0,
		"tower_crews_lost": 0,
		"towers_damaged": 0,
	}

	var campaign_domain: String = _expedition.campaign_domain()
	var campaign_mission: int = _expedition.campaign_mission()
	if campaign_domain != "":
		_last_result["campaign_domain"] = campaign_domain
		_last_result["campaign_mission"] = campaign_mission
		_last_result["campaign_boss"] = ExpeditionGeneratorScript.campaign_is_boss_mission(campaign_domain, campaign_mission)

	_expedition = null
	_clear_draft()
	_expedition_followups = []
	if not loot.is_empty():
		EventBus.sortie_loot_gained.emit(loot.duplicate(true))
	EventBus.expedition_ended.emit(result, rewards.duplicate(), lost.duplicate())
	# Tres campanas: la mision avanza solo si su ultimo combate cayo. Despues de
	# expedition_ended, para que quien lea el parte lo vea antes que el progreso
	# (y el Ataque Final, si con esto ya se puede llamar).
	if campaign_domain != "":
		_publish_campaign_events(_campaigns.finish(campaign_domain, campaign_mission,
			result == Expedition.RESULT_WON, _now(), GameConfig.get_duration(GameConfig.campaign_mission_cooldown)))

func _new_seed() -> int:
	var value: int = randi()
	# Cero es "sin semilla" para launch_expedition(); que nunca salga por azar.
	return value if value != 0 else 1

# ── Salidas: el tablon, el botin y "resolver solo" (doc 21 §3) ───────

## Las ofertas a la vista (copias: la UI no las muta).
func get_sortie_offers() -> Array:
	return _sorties.offers.duplicate(true)

func get_sortie_offer(offer_id: int) -> Dictionary:
	return _sorties.get_offer(offer_id).duplicate(true)

## El mapa entero de una oferta, el mismo que se jugara (se ve antes de salir).
func offer_map(offer: Dictionary) -> Array:
	return ExpeditionGeneratorScript.sortie_map(offer)

## Todo lo que la seleccion de tropa ensena antes de lanzar: nombre, combates,
## enemigos por nodo, botin, oro y madera, y las fuerzas de los dos lados con su
## etiqueta (Favorable / Igualada / Dificil). `party` es unit_id -> count.
## Sirve tambien para la primera escaramuza (offer = {"kind": "first"}).
func sortie_preview(offer: Dictionary, party: Dictionary) -> Dictionary:
	var map: Array = []
	var era: int = maxi(1, int(offer.get("era", ProgressionManager.current_era)))
	var first: bool = String(offer.get("kind", "")) == "first"
	if first:
		map = ExpeditionGeneratorScript.first_sortie_map()
	else:
		map = offer_map(offer)
	var enemy: float = ExpeditionGeneratorScript.hardest_node_power(map, era)
	var mine: float = ExpeditionGeneratorScript.roster_power(party)
	return {
		"name_key": "SORTIE_NAME_FIRST" if first else ExpeditionGeneratorScript.offer_name_key(offer),
		"kind": String(offer.get("kind", "")),
		"fights": ExpeditionGeneratorScript.fights_on_path(map),
		"map": map,
		"layers": ExpeditionGeneratorScript.layers_of(map),
		"loot": ExpeditionGeneratorScript.path_loot(map),
		"rewards": ExpeditionGeneratorScript.path_rewards(map, era),
		"enemy_power": enemy,
		"player_power": mine,
		"odds": Rules.odds_label(mine, enemy),
		# Aire y mar: hay agua en el tablero (se pueden llevar barcos; vienen barcos).
		"coastal": ExpeditionGeneratorScript.map_has_water(map),
		# Pre-lanzamiento: la incursion se puede resolver sola si la columna dobla
		# al enemigo. La expedicion y la primera escaramuza, no.
		"can_auto": String(offer.get("kind", "")) == ExpeditionGeneratorScript.KIND_RAID \
			and Rules.can_auto_resolve(mine, enemy),
		# Tres campanas: de que campana es y si es la del jefe.
		"campaign_domain": String(offer.get("domain", "")) if String(offer.get("kind", "")) == ExpeditionGeneratorScript.KIND_CAMPAIGN else "",
		"campaign_boss": String(offer.get("kind", "")) == ExpeditionGeneratorScript.KIND_CAMPAIGN \
			and ExpeditionGeneratorScript.campaign_is_boss_mission(String(offer.get("domain", "")), int(offer.get("mission", 0))),
	}

## Saca la columna a una oferta del tablon. Mismas comprobaciones que
## launch_expedition(); la oferta sale del tablon y vuelve si la columna pierde.
## `auto_resolve`: la incursion se juega de un tiron con la IA (solo si la
## fuerza lo permite; si no, se juega normal).
func launch_sortie(offer_id: int, party: Dictionary, auto_resolve: bool = false) -> bool:
	if not bool(can_launch(party).get("ok", false)):
		return false
	if _sorties.get_offer(offer_id).is_empty():
		return false
	# Aire y mar: barcos solo a una mision con agua.
	if not bool(can_launch_to(party, _sorties.get_offer(offer_id)).get("ok", false)):
		return false
	var committed: Dictionary = {}
	for unit_id in party:
		if int(party[unit_id]) > 0:
			committed[String(unit_id)] = int(party[unit_id])
	var offer: Dictionary = _sorties.take(offer_id)
	_expedition = ExpeditionScript.create_sortie(_next_expedition_id, offer, committed, _read_morale())
	_next_expedition_id += 1
	_morale_snapshot = _expedition.morale_snapshot
	_clear_draft()
	_expedition_followups = []
	EventBus.sortie_offers_changed.emit()
	EventBus.expedition_started.emit(_expedition.id, _expedition.map.size())
	enter_current_node()
	if auto_resolve and can_auto_resolve():
		auto_resolve_current()
	return true

## "Resolver solo" (D6 = A) vale ahora: el tablero abierto es una incursion o un
## Diezmo (nunca el asedio, ni una expedicion de tres), sigue en juego, y tu
## fuerza es al menos combat_auto_resolve_ratio veces la del enemigo.
func can_auto_resolve() -> bool:
	if _encounter == null or not _encounter.is_active() or _audit_wave_active:
		return false
	var allowed: bool = false
	if _encounter.is_defense:
		allowed = true
	elif _is_expedition_board() and _expedition.is_raid():
		allowed = true
	if not allowed:
		return false
	return Rules.can_auto_resolve(
		Rules.side_strength(_encounter.units, Encounter.PLAYER),
		Rules.side_strength(_encounter.units, Encounter.ENEMY))

## Juega el tablero abierto de un tiron con la IA en los dos bandos: el mismo
## Encounter y el mismo AutoResolver que el Diezmo a ciegas. Solo se publican
## las muertes y el final (no cien movimientos en un fotograma); el parte dice
## "resuelto solo". Devuelve false si no se puede.
func auto_resolve_current() -> bool:
	if not can_auto_resolve():
		return false
	# Un turno enemigo a medias (corrutina esperando) deja de ser de nadie.
	_board_generation += 1
	_enemy_turn_running = false
	_auto_resolving = true
	var outcome: Dictionary = AutoResolverScript.resolve(_encounter)
	var events: Array = []
	for event in outcome.get("events", []):
		if String(event.get("e", "")) in ["unit_died", "enemy_routed", "encounter_ended"]:
			events.append(event)
	_emit_events(events)
	_auto_resolving = false
	return true

## Planos (1.2, feat/nucleo-y-planos): un edificio de
## GameConfig.blueprint_required no se construye sin el suyo. Lo comprueba
## PlacementRules.check_blueprint() (colocar, CONSTRUIR, ¿QUE HACER?). Los
## planos ganados viven en el tablon (SortieBoard.blueprints, clave "sorties"
## del guardado): un mecanismo generico, sirve para cualquier id.
func blueprint_locked(building_id: String) -> bool:
	return GameConfig.needs_blueprint(building_id) and not _sorties.has_blueprint(building_id)

func has_blueprint(building_id: String) -> bool:
	return _sorties.has_blueprint(building_id)

func get_blueprints() -> Array:
	return _sorties.blueprints.duplicate()

## Da los planos `ids` (los que ya se tienen no cuentan dos veces). Con
## `announce`, cada plano nuevo sale como blueprint_unlocked y con su aviso.
## La puerta generica para cualquier fuente de planos (campanas hoy; el
## contrabandista del Puerto u otras, manana).
func grant_blueprints(ids: Array, announce: bool = true) -> void:
	if ids.is_empty():
		return
	if announce:
		_publish_sortie_events(_sorties.bank_loot({"blueprints": ids.duplicate()}))
		return
	for id in ids:
		var building_id := String(id)
		if building_id != "" and not _sorties.blueprints.has(building_id):
			_sorties.blueprints.append(building_id)

## Los planos de las misiones de campana ya ganadas (GameConfig.blueprint_sources).
## Idempotente: se llama al cargar (sin avisos: una partida vieja, o una mision
## ganada antes de que su edificio existiera, recibe el suyo) y al ganar una
## mision.
func _sync_campaign_blueprints(announce: bool) -> void:
	var ids: Array = []
	for domain in CampaignBookScript.DOMAINS:
		for mission in _campaigns.won(String(domain)):
			for id in GameConfig.blueprints_for_mission(String(domain), mission):
				if not _sorties.has_blueprint(String(id)) and not ids.has(id):
					ids.append(id)
	grant_blueprints(ids, announce)

## Rebaja del proximo Diezmo ganada en una salida, en % (0 = ninguna). Solo el
## apunte: la aplica StormManager.add_tithe_discount() al volver la columna
## (_apply_loot). Se borra con tithe_resolved.
func get_tithe_cut_pct() -> int:
	return _sorties.tithe_cut_pct

## El jugador ha abierto el tablon: se apaga el aviso de "nuevo".
func mark_sorties_seen() -> void:
	_publish_sortie_events(_sorties.mark_all_seen())
	_publish_campaign_events(_campaigns.mark_all_seen())

## Por que conviene salir ahora, como clave de Tr, o "" si no hay motivo. Es la
## unica respuesta: el punto rojo del boton ESCARAMUZAS y la linea de ¿QUE
## HACER? la leen de aqui. Sin columna en casa no hay motivo que valga.
func sortie_reason() -> String:
	if has_active_expedition() or is_board_open():
		return ""
	if ProgressionManager.is_final_audit_pending() or ProgressionManager.is_final_audit_active():
		return ""
	if not ArmyManager.has_military_building() or get_deployable_units().is_empty():
		return ""
	if is_first_sortie_due():
		return "SORTIE_WHY_FIRST"
	if _sorties.has_outpost() and _sorties.tithe_cut_pct <= 0 and StormManager.is_armed():
		return "SORTIE_WHY_OUTPOST"
	if not _sorties.offers.is_empty() and _parts_wanted() > ResourceManager.get_amount(ResourceManager.Type.PARTS):
		return "SORTIE_WHY_PARTS"
	if _sorties.has_unseen():
		return "SORTIE_WHY_NEW"
	# Tres campanas: una mision nueva que se puede lanzar ya, con tropa de su medio.
	if campaign_waiting_unseen() != "":
		return "SORTIE_WHY_CAMPAIGN"
	return ""

## Repuestos que pide la mejora mas barata que ya se podria hacer (un productor
## en el nivel justo de debajo). 0 si ninguna los pide.
func _parts_wanted() -> int:
	var wanted: int = 0
	for info in GridManager.buildings_view():
		var data: BuildingData = info["data"]
		if data == null or not data.id in GameConfig.upgrade_parts_buildings:
			continue
		var level: int = int((info["node"] as Node).get_meta("level", 1))
		var need: int = GameConfig.upgrade_parts_needed(data.id, level + 1)
		if need > 0 and (wanted == 0 or need < wanted):
			wanted = need
	return wanted

## Revisa el tablon: oferta nueva si toca. La llama el reloj cada pocos segundos
## (y los tests a mano).
func refresh_sorties() -> void:
	_publish_sortie_events(_sorties.refresh(_now(), _sortie_context(), _new_seed()))
	_check_campaign_rest()

## Una campana que acaba de terminar su descanso avisa (punto rojo, panel). Dos
## restas por tic: nada que medir.
var _campaign_resting: Dictionary = {}
func _check_campaign_rest() -> void:
	var now: float = _now()
	var changed := false
	for domain in CampaignBook.DOMAINS:
		var resting: bool = _campaigns.cooldown_left(domain, now) > 0.0
		if bool(_campaign_resting.get(domain, false)) and not resting:
			changed = true
		_campaign_resting[domain] = resting
	if changed:
		EventBus.campaign_changed.emit()

func _sortie_context() -> Dictionary:
	var open: bool = ArmyManager.has_military_building() and TutorialManager.is_first_sortie_done() \
		and not GameMode.is_run_over() and not StormManager.is_halted()
	var era: int = ProgressionManager.current_era
	return {
		"raids": open,
		# La expedicion corta del tablon es ahora la Campana de Tierra
		# (feat/tres-campanas): apagada salvo con su interruptor.
		"expeditions": open and era >= GameConfig.combat_expedition_min_era and GameConfig.combat_board_expeditions_enabled,
		"outpost": open and GameMode.tithe_enabled() and StormManager.is_armed(),
		"era": era,
		"blueprint": _next_blueprint(),
		"raid_out": _expedition != null and _expedition.kind == ExpeditionGeneratorScript.KIND_RAID,
		"expedition_out": _expedition != null and _expedition.kind == ExpeditionGeneratorScript.KIND_EXPEDITION,
	}

## El plano que llevaria una expedicion nueva del tablon: el primero de
## blueprint_required que no salga de ninguna campana (esos los da su mision,
## blueprint_sources), cuyo edificio exista ya en data/buildings, no se tenga y
## no este ya prometido.
func _next_blueprint() -> String:
	var promised: Array = _sorties.offered_blueprints()
	if _expedition != null:
		promised.append(String(_expedition.offer.get("blueprint", "")))
	for id in GameConfig.blueprint_required:
		var building_id: String = String(id)
		if not GameConfig.blueprint_source(building_id).is_empty():
			continue
		if _sorties.has_blueprint(building_id) or promised.has(building_id):
			continue
		if ResourceLoader.exists("res://data/buildings/%s.tres" % building_id):
			return building_id
	return ""

## Aplica a la colonia lo que la columna trajo de fuera y devuelve lo que de
## verdad entro (los colonos se quedan en lo que quepa en las casas).
func _apply_loot(raw: Dictionary) -> Dictionary:
	var applied: Dictionary = {}
	var parts: int = int(raw.get("parts", 0))
	if parts > 0:
		ResourceManager.unlock(ResourceManager.Type.PARTS)
		ResourceManager.add(ResourceManager.Type.PARTS, parts)
		applied["parts"] = parts
	var colonists: int = int(raw.get("colonists", 0))
	if colonists > 0:
		var room: int = maxi(0, PopulationManager.get_max_population() - PopulationManager.get_population())
		var arrived: int = mini(colonists, room)
		if arrived > 0:
			# remove_population con signo negativo es "llegan": la API publica que
			# escribe la poblacion (y respeta su suelo y su señal).
			PopulationManager.remove_population(-arrived)
			applied["colonists"] = arrived
		if arrived < colonists:
			applied["colonists_no_room"] = colonists - arrived
	var banked: Dictionary = {}
	if raw.has("blueprints"):
		banked["blueprints"] = raw["blueprints"]
		applied["blueprints"] = (raw["blueprints"] as Array).duplicate()
	if int(raw.get("tithe_pct", 0)) > 0:
		var pct: int = int(raw["tithe_pct"])
		banked["tithe_pct"] = pct
		applied["tithe_pct"] = pct
		# Un solo mecanismo de rebaja, el de la Orden de la Regencia (rama
		# feat/orden-regencia). Sin esa funcion la rebaja se anota y no hace nada.
		if StormManager.has_method("add_tithe_discount"):
			StormManager.call("add_tithe_discount", "expedicion", float(pct) / 100.0)
	if not banked.is_empty():
		_publish_sortie_events(_sorties.bank_loot(banked))
	return applied

func _publish_sortie_events(events: Array) -> void:
	var changed := false
	for event in events:
		match String(event.get("e", "")):
			"blueprint_gained":
				EventBus.blueprint_unlocked.emit(String(event["id"]))
				var bp_path := "res://data/buildings/%s.tres" % String(event["id"])
				var bp_data: BuildingData = load(bp_path) as BuildingData if ResourceLoader.exists(bp_path) else null
				var bp_name: String = bp_data.get_display_name() if bp_data != null else String(event["id"])
				EventBus.notification_posted.emit(Tr.t("NOTIF_BLUEPRINT_GAINED") % bp_name, "info", Color(0.3, 0.8, 1.0))
			"offers_changed", "tithe_cut_gained":
				changed = true
	if changed:
		EventBus.sortie_offers_changed.emit()

func _sortie_cooldown(kind: String) -> float:
	var base: float = GameConfig.combat_raid_cooldown if kind == ExpeditionGeneratorScript.KIND_RAID \
		else GameConfig.combat_expedition_cooldown
	return GameConfig.get_duration(base)

func _now() -> float:
	return ProgressionManager.get_played_seconds()

# ── Las tres campanas: Tierra, Mar y Aire (feat/tres-campanas) ───────

## El libro de campanas, para leer (la UI y las pruebas). Nadie fuera de este
## servicio lo muta.
func get_campaign_book() -> CampaignBook:
	return _campaigns

func campaign_won(domain: String) -> int:
	return _campaigns.won(domain)

func campaign_total(domain: String) -> int:
	return CampaignBook.total(domain)

func is_campaign_complete(domain: String) -> bool:
	return _campaigns.is_complete(domain)

## Las tres completas: lo que, con el Cuartel General a nivel 3, abre el Ataque
## Final (ProgressionManager.final_audit_ready()).
func campaigns_all_complete() -> bool:
	return _campaigns.all_complete()

func campaigns_completed_count() -> int:
	return _campaigns.completed_count()

## La oferta de la mision que toca en `domain`, con la era de ahora (vacia si la
## campana esta completa). Lleva el plano que da esa mision
## (GameConfig.blueprint_sources), si aun no se tiene y su edificio existe: asi
## se ve antes de salir y viaja en el botin del ultimo combate.
func campaign_offer(domain: String) -> Dictionary:
	var offer: Dictionary = _campaigns.offer_for(domain, ProgressionManager.current_era)
	if offer.is_empty():
		return offer
	offer["blueprint"] = campaign_mission_blueprint(domain, int(offer["mission"]))
	return offer

## El plano que da la mision `mission` (desde 0) de `domain` y aun no se tiene,
## o "" (ninguno, ya lo tienes o su edificio aun no existe en esta version).
func campaign_mission_blueprint(domain: String, mission: int) -> String:
	for id in GameConfig.blueprints_for_mission(domain, mission):
		var building_id: String = String(id)
		if _sorties.has_blueprint(building_id):
			continue
		if ResourceLoader.exists("res://data/buildings/%s.tres" % building_id):
			return building_id
	return ""

## Por que no se puede salir ahora a la siguiente mision de `domain`, como clave
## de Tr (sin cifras), o "" si se puede (falta elegir la tropa, eso aparte).
## El orden es el de lo que el jugador tiene que arreglar primero.
##   CAMP_DONE              la campana esta completa
##   CAMP_LOCK_BUILDING     falta su edificio (Cuartel, Astillero, Aerodromo)
##   CAMP_LOCK_FIRST_SORTIE falta ganar la primera escaramuza
##   CAMP_LOCK_ERA          la mision pide una era que aun no llega
##   CAMP_LOCK_REST         la tropa descansa tras la ultima mision
##   y los de can_launch (columna fuera, asedio convocado...)
func campaign_lock_reason(domain: String) -> String:
	if _campaigns.is_complete(domain):
		return "CAMP_DONE"
	if GameMode.is_run_over():
		return "OBJ_WHY_RUN_OVER"
	var building: String = String(GameConfig.campaign_defs.get(domain, {}).get("building", "barracks"))
	if ArmyManager.building_count(building) <= 0:
		return "CAMP_LOCK_BUILDING"
	if is_first_sortie_due():
		return "CAMP_LOCK_FIRST_SORTIE"
	var mission: int = _campaigns.next_mission(domain)
	if ProgressionManager.current_era < ExpeditionGeneratorScript.campaign_mission_era(domain, mission):
		return "CAMP_LOCK_ERA"
	if _campaigns.cooldown_left(domain, _now()) > 0.0:
		return "CAMP_LOCK_REST"
	if has_active_expedition():
		return "MSG_EXPEDITION_ACTIVE"
	if is_in_encounter():
		return "MSG_ENCOUNTER_ACTIVE"
	if ProgressionManager.is_final_audit_pending() or ProgressionManager.is_final_audit_active():
		return "MSG_AUDIT_BLOCKS_EXPEDITION"
	return ""

## Segundos de descanso que le quedan a `domain` (0 = lista).
func campaign_rest_left(domain: String) -> float:
	return _campaigns.cooldown_left(domain, _now())

## El edificio que abre `domain` (para el candado: "Construye: Astillero").
static func campaign_building(domain: String) -> String:
	return String(GameConfig.campaign_defs.get(domain, {}).get("building", "barracks"))

## Por que `unit_id` no puede ir a la campana `domain`, o "" si puede.
func campaign_unit_block(unit_id: String, domain: String) -> String:
	if GameConfig.get_unit_domain(unit_id) != domain:
		return "CAMP_UNIT_WRONG_DOMAIN"
	if not GameConfig.campaign_unit_allowed(domain, unit_id):
		return "CAMP_UNIT_CANT_HIT"
	return ""

## Lo que hay en casa que puede ir a la campana `domain` (unit_id -> cuantos).
func campaign_units_home(domain: String) -> Dictionary:
	var home: Dictionary = get_deployable_units()
	var out: Dictionary = {}
	for unit_id in home:
		if campaign_unit_block(String(unit_id), domain) == "":
			out[String(unit_id)] = int(home[unit_id])
	return out

## Saca la columna a la mision que toca de `domain`. Mismas comprobaciones que
## launch_sortie(), y ademas el candado de la campana y su dominio puro. Si la
## columna pierde o abandona, la mision sigue ahi (con el mismo mapa).
func launch_campaign_mission(domain: String, party: Dictionary) -> bool:
	if campaign_lock_reason(domain) != "":
		return false
	var offer: Dictionary = campaign_offer(domain)
	if offer.is_empty():
		return false
	if not bool(can_launch_to(party, offer).get("ok", false)):
		return false
	var committed: Dictionary = {}
	for unit_id in party:
		if int(party[unit_id]) > 0:
			committed[String(unit_id)] = int(party[unit_id])
	_expedition = ExpeditionScript.create_sortie(_next_expedition_id, offer, committed, _read_morale())
	_next_expedition_id += 1
	_morale_snapshot = _expedition.morale_snapshot
	_clear_draft()
	_expedition_followups = []
	_publish_campaign_events(_campaigns.mark_all_seen())
	EventBus.expedition_started.emit(_expedition.id, _expedition.map.size())
	enter_current_node()
	return true

## La primera campana con una mision nueva sin mirar que ya se podria lanzar y
## con tropa de su medio en casa, o "". Para el punto rojo y ¿QUE HACER?.
func campaign_waiting_unseen() -> String:
	for domain in CampaignBook.DOMAINS:
		if not _campaigns.is_unseen(domain):
			continue
		if campaign_lock_reason(domain) != "":
			continue
		if campaign_units_home(domain).is_empty():
			continue
		return String(domain)
	return ""

func _publish_campaign_events(events: Array) -> void:
	var changed := false
	for event in events:
		match String(event.get("e", "")):
			"campaign_mission_won":
				EventBus.campaign_mission_won.emit(String(event["domain"]), int(event["mission"]), bool(event["boss"]))
				# El plano de la mision, aunque no viajara en el botin (su
				# edificio no existia al salir): ganar la mision lo da.
				grant_blueprints(GameConfig.blueprints_for_mission(String(event["domain"]), int(event["mission"])))
			"campaign_completed":
				EventBus.campaign_completed.emit(String(event["domain"]))
			"campaign_changed":
				changed = true
	if changed:
		EventBus.campaign_changed.emit()

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
	if bool(data.get("draft_pending", false)) and bool(node.get("cleared", false)) and not run.at_end():
		_offer_draft()

func reset() -> void:
	_clear_runtime_state()
	_next_expedition_id = 1
	# El tablon es estado de la partida (clave "sorties"): partida nueva, tablon
	# vacio. Se tira, no se liquida: ni planos ni rebaja pasan a la nueva.
	_sorties = SortieBoardScript.new()
	# Las tres campanas (clave "campaigns"): partida nueva, ninguna empezada, y
	# una semilla nueva para todos sus mapas. Se tiran, no se liquidan.
	_campaigns = CampaignBookScript.new()
	_campaigns.ensure_seed(_new_seed())

## Lo que va en data["sorties"]: ofertas, relojes, planos y rebaja del Diezmo.
## Aparte de data["expedition"] porque vive aunque no haya columna fuera.
func get_sorties_save_data() -> Dictionary:
	return _sorties.to_dict()

## Idempotente: sustituye el tablon entero por el guardado. Sin la clave
## (guardado anterior a las salidas nuevas) llega {} y el tablon empieza vacio;
## la primera oferta sale en el siguiente tic del reloj.
func load_sorties_save_data(data: Dictionary) -> void:
	_sorties = SortieBoardScript.from_dict(data)
	EventBus.sortie_offers_changed.emit()

## Lo que va en data["campaigns"] (feat/tres-campanas): semilla, misiones ganadas
## por campana, descansos y lo visto.
func get_campaigns_save_data() -> Dictionary:
	return _campaigns.to_dict()

## Idempotente: sustituye el libro entero. Sin la clave (guardado anterior a las
## tres campanas) llega {}: ninguna empezada, con semilla nueva. Un Ataque Final
## ya convocado o ganado en ese guardado no se toca: vive en ProgressionManager.
func load_campaigns_save_data(data: Dictionary) -> void:
	_campaigns = CampaignBookScript.from_dict(data)
	_campaigns.ensure_seed(_new_seed())
	# Los planos de las misiones ya ganadas (1.2): una partida de la 1.1 los
	# recibe sin aviso. Va despues del tablon (GameManager carga "sorties" antes).
	_sync_campaign_blueprints(false)
	EventBus.campaign_changed.emit()

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
	_board_generation += 1
	_audit_wave_active = false
	_audit_wave_won = false
	_next_uid = 1
	_result_applied = false
	_last_result = {}
	_tower_crew_uids.clear()
	_last_board_crew_uids.clear()
	_audit_charged.clear()
	_audit_wave_queued = false
	_pending_practice = ""
