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
## Current scope: the encounter core (T012-T020). The expedition map, drafts and
## the economy bridge land in US2/US3 — see specs/001-combate-pve/tasks.md.

const CombatUnitScript := preload("res://scripts/combat/CombatUnit.gd")
const EncounterScript := preload("res://scripts/combat/Encounter.gd")
const Rules := preload("res://scripts/combat/CombatRules.gd")
const AI := preload("res://scripts/combat/CombatAI.gd")

var _encounter: Encounter = null
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

# ── Queries ──────────────────────────────────────────────────────────

func get_encounter() -> Encounter:
	return _encounter

func is_in_encounter() -> bool:
	return _encounter != null and _encounter.is_active()

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

## Units the player may still commit: everything trained and not already deployed.
func get_deployable_units() -> Dictionary:
	var available: Dictionary = {}
	for unit_id in GameConfig.get_unit_ids():
		var count: int = ArmyManager.get_count(unit_id)
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
func start_defense(enemy_roster: Dictionary, defenders: Array = []) -> bool:
	if is_in_encounter() or enemy_roster.is_empty():
		return false

	if not defenders.is_empty():
		# El bando viene dado: lo único que hay que conservar son las marcas de
		# dotación de torre que esas unidades ya traían, para que una dotación que
		# sobrevivió a la oleada anterior siga sin ser parte del ejército.
		var carried: Array = []
		for unit in defenders:
			if _tower_crew_uids.has(unit.uid):
				carried.append(unit.uid)
		start_encounter_with_units(defenders, enemy_roster, false, 0, true, carried)
		return true

	var garrison: Dictionary = get_garrison()
	var crews: Dictionary = get_tower_crews(garrison)
	if garrison.is_empty() and crews.is_empty():
		return false
	start_encounter(garrison, enemy_roster, false, 0, true, crews)
	if not crews.is_empty():
		EventBus.notification_posted.emit(
			Tr.t("STORM_TITHE_TOWER_CREWS") % roster_size(crews), "positive", UITheme.ACCENT)
	return true

## Everything trained and at home, up to the board's cap.
func get_garrison() -> Dictionary:
	var garrison: Dictionary = {}
	var committed := 0
	for unit_id in GameConfig.get_unit_ids():
		for i in ArmyManager.get_count(unit_id):
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
func start_encounter(party: Dictionary, enemy_roster: Dictionary, is_boss: bool = false, encounter_index: int = 0, is_defense: bool = false, reinforcements: Dictionary = {}) -> void:
	_morale_snapshot = _read_morale()
	var player_units: Array = _build_side(party, Encounter.PLAYER, 1.0)
	var crew_uids: Array = []
	for crew in _build_side(reinforcements, Encounter.PLAYER, 1.0):
		crew_uids.append(crew.uid)
		player_units.append(crew)
	_open(player_units, enemy_roster, is_boss, encounter_index, is_defense, crew_uids)

## El mismo encuentro, pero con el bando del jugador ya construido: las unidades
## entran con la vida que traen en vez de nacer enteras. Es lo que permite
## encadenar encuentros sin que cada uno empiece de cero.
##
## `crew_uids` marca cuáles de esas unidades no pertenecen al ejército.
func start_encounter_with_units(player_units: Array, enemy_roster: Dictionary, is_boss: bool = false, encounter_index: int = 0, is_defense: bool = false, crew_uids: Array = []) -> void:
	_morale_snapshot = _read_morale()
	_open(player_units, enemy_roster, is_boss, encounter_index, is_defense, crew_uids)

## Único sitio donde se abre un tablero: monta el bando enemigo, fija quién no
## cuenta como ejército y arranca.
func _open(player_units: Array, enemy_roster: Dictionary, is_boss: bool, encounter_index: int, is_defense: bool, crew_uids: Array) -> void:
	var scale: float = GameConfig.combat_boss_multiplier if is_boss else 1.0
	var units: Array = player_units.duplicate()
	units.append_array(_build_side(enemy_roster, Encounter.ENEMY, scale))

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
	if party.is_empty() or is_in_encounter():
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
	if _encounter != null:
		_encounter.release_survivors()
	_encounter = null
	_enemy_turn_running = false

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

	# Las dotaciones de torre quedan fuera del recuento: no salieron del cuartel,
	# así que ni se restan del ejército ni cuentan como supervivientes que vuelven.
	var fallen: Array = _encounter.casualties(Encounter.PLAYER)
	var roster_fallen: Array = _roster_only(fallen)
	var casualties: Dictionary = _count_by_unit(roster_fallen)
	var survivors: Dictionary = _count_by_unit(_roster_only(_encounter.survivors()))

	# ArmyManager is the source of truth for the roster: the party was never
	# deducted when it marched out, so only the dead are subtracted now and
	# Military Power lands exactly on the survivors.
	var lost: Dictionary = ArmyManager.remove_units(casualties)

	# Winning a defence pays nothing, and it should not: the reward is that the
	# Tithe goes uncollected. Handing out loot on top would pay the player twice
	# for the same fight.
	var rewards: Dictionary = {}
	if victory and not _encounter.is_defense:
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
		"defense": _encounter.is_defense,
		"rewards": rewards,
		"casualties": lost,
		"survivors": survivors,
		"morale_delta": morale_delta,
		# Para que el parte de la defensa pueda decir cuánto pusieron las torres.
		"tower_crews": _tower_crew_uids.size(),
		"tower_crews_lost": fallen.size() - roster_fallen.size(),
	}

## Quita del recuento a las unidades que no pertenecen al ejército del jugador.
func _roster_only(units: Array) -> Array:
	var result: Array = []
	for unit in units:
		if not _tower_crew_uids.has(unit.uid):
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

# ── Dev helper (T014) ────────────────────────────────────────────────

## Starts a standalone encounter with whatever the player has trained, so the
## board can be exercised before the expedition layer exists.
func dev_start_encounter() -> bool:
	if not GameConfig.dev_mode:
		return false
	var party: Dictionary = {}
	var committed := 0
	for unit_id in GameConfig.get_unit_ids():
		for i in ArmyManager.get_count(unit_id):
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

## No expedition layer yet, so nothing persists. Kept so GameManager can wire the
## save slot now and stay backward compatible when expeditions land (T036).
func get_save_data() -> Dictionary:
	return {}

func load_save_data(_data: Dictionary) -> void:
	pass

func reset() -> void:
	_encounter = null
	_enemy_turn_running = false
	_next_uid = 1
	_result_applied = false
	_last_result = {}
	_tower_crew_uids.clear()
