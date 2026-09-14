extends RefCounted
class_name Expedition
## One roguelike run: the map, the party that marched out, what it picked up and
## where it is standing. Pure state — no nodes, no signals, no timers — so a full
## expedition can be played from launch to boss inside a headless test.
##
## Like Encounter, every mutating method returns an Array of event dictionaries
## instead of emitting anything. CombatManager drains them onto the EventBus
## (constitution, principles I and IV).
##
## Three design rules hold this together, and none of them is an accident:
##   * **Attrition.** Nothing heals between encounters. HP only comes back at the
##     base, when the expedition is over (FR-011).
##   * **Permadeath.** A unit that falls stays in `party` as a casualty and never
##     fights again in this run (FR-010).
##   * **No meta-progression.** Draft picks live and die with the expedition
##     (FR-018).
##
## The map is never saved: it is rebuilt from `seed` and repainted with the list
## of cleared nodes (research D5/D6).

const Generator := preload("res://scripts/combat/ExpeditionGenerator.gd")
const Rules := preload("res://scripts/combat/CombatRules.gd")
const CombatUnitScript := preload("res://scripts/combat/CombatUnit.gd")

enum State { ACTIVE, COMPLETED, DEFEATED, ABANDONED }

## Result codes for ExpeditionResult / the `expedition_ended` signal.
const RESULT_WON := 0
const RESULT_LOST := 1
const RESULT_ABANDONED := 2

const PLAYER := 0
const ENEMY := 1

var id: int = 0
var seed_value: int = 0
var era: int = 1
var map: Array = []                  ## Array[Dictionary], see ExpeditionNode
var current_node: int = 0
var party: Array = []                ## CombatUnit, the living and the fallen
var draft_picks: Array = []          ## Chosen DraftOptions, in order
var rewards: Dictionary = {}         ## resource_name -> int, accumulated
var morale_snapshot: float = 50.0
var state: int = State.ACTIVE

## uid counter, unique inside this expedition and shared with the enemies it
## fields, so no two units on a board can collide (data-model, CombatUnit.uid).
var _next_uid: int = 1

# ── Construction ─────────────────────────────────────────────────────

## Launches a run. `party_counts` is `unit_id -> count` as committed from the
## base; `morale_snapshot` freezes the base's spirit for the whole expedition,
## exactly as the design intends — the battle is fought with the morale the town
## had when the column marched out, not with live numbers.
static func create(p_id: int, p_seed: int, party_counts: Dictionary, p_morale: float, p_era: int = 1) -> Expedition:
	var run := Expedition.new()
	run.id = p_id
	run.seed_value = p_seed
	run.era = maxi(1, p_era)
	run.morale_snapshot = p_morale
	run.map = Generator.generate_map(
		Generator.make_rng(p_seed), Vector2i.ZERO, Vector2i.ZERO, run.era
	)
	run.current_node = 0
	run.state = State.ACTIVE
	run.from_army(party_counts)
	return run

## Turns a roster of committed units into the party, stamping each one with the
## morale modifiers of this expedition. Returns the party it built.
func from_army(party_counts: Dictionary) -> Array:
	var attack_mod: float = Rules.morale_attack_mod(morale_snapshot)
	var initiative_bonus: int = Rules.morale_initiative_bonus(morale_snapshot)
	for unit_id in party_counts.keys():
		for i in range(int(party_counts[unit_id])):
			var unit: CombatUnit = CombatUnitScript.create(next_uid(), String(unit_id), PLAYER, 1.0)
			unit.morale_attack_mod = attack_mod
			unit.morale_initiative_bonus = initiative_bonus
			party.append(unit)
	return party

func next_uid() -> int:
	var uid: int = _next_uid
	_next_uid += 1
	return uid

# ── Queries ──────────────────────────────────────────────────────────

func is_active() -> bool:
	return state == State.ACTIVE

func is_finished() -> bool:
	return state != State.ACTIVE

func node_at(index: int) -> Dictionary:
	if index < 0 or index >= map.size():
		return {}
	return map[index]

func current_node_data() -> Dictionary:
	return node_at(current_node)

func at_boss() -> bool:
	return bool(current_node_data().get("is_boss", false))

## Routes out of the node the player is standing on. Empty at the boss, which is
## exactly how the run ends.
func current_exits() -> Array:
	return current_node_data().get("exits", []).duplicate()

## A move is legal only along an exit of the current node — no jumping across the
## map, and no going back.
func can_select(index: int) -> bool:
	return is_active() and current_exits().has(index)

func living_party() -> Array:
	var alive: Array = []
	for unit in party:
		if unit.is_alive():
			alive.append(unit)
	return alive

func casualties() -> Array:
	var fallen: Array = []
	for unit in party:
		if not unit.is_alive():
			fallen.append(unit)
	return fallen

func is_party_wiped() -> bool:
	return living_party().is_empty()

func cleared_indices() -> Array:
	var cleared: Array = []
	for node in map:
		if bool(node.get("cleared", false)):
			cleared.append(int(node["index"]))
	return cleared

func nodes_cleared() -> int:
	return cleared_indices().size()

func boss_defeated() -> bool:
	var boss: int = Generator.boss_index(map)
	return boss >= 0 and boss < map.size() and bool(map[boss].get("cleared", false))

# ── The encounter of the current node ────────────────────────────────

## Fields this node's opposition. Fresh CombatUnits every time, so a retried node
## never inherits damage the player already dealt — but they take their uids from
## the expedition counter so they can never clash with the party.
func build_enemy_units() -> Array:
	var node: Dictionary = current_node_data()
	if node.is_empty():
		return []
	var scale: float = Generator.enemy_scale(
		int(node.get("depth", 0)), era, int(node.get("risk", 0)), bool(node.get("is_boss", false))
	)
	var units: Array = []
	var roster: Dictionary = node.get("enemy_roster", {})
	for unit_id in roster.keys():
		for i in range(int(roster[unit_id])):
			units.append(CombatUnitScript.create(next_uid(), String(unit_id), ENEMY, scale))
	return units

## Everyone who marches onto the next board: the survivors as they are, wounds
## and draft bonuses included, plus the node's garrison.
func build_encounter_units() -> Array:
	var units: Array = living_party()
	units.append_array(build_enemy_units())
	return units

# ── Transitions ──────────────────────────────────────────────────────

## The node is won. Books the loot, and if it was the boss the run is over.
## Called after the survivors have already stepped off the board.
func mark_cleared() -> Array:
	if not is_active():
		return []
	var node: Dictionary = current_node_data()
	if node.is_empty() or bool(node.get("cleared", false)):
		return []
	node["cleared"] = true
	add_rewards(Generator.node_rewards(node, era))
	var events: Array = [{"e": "node_cleared", "index": current_node, "is_boss": at_boss()}]
	if at_boss():
		state = State.COMPLETED
		events.append({"e": "expedition_ended", "result": RESULT_WON})
	return events

## The party is gone. There is no retry: the run ends where it fell.
func mark_defeated() -> Array:
	if not is_active():
		return []
	state = State.DEFEATED
	return [{"e": "expedition_ended", "result": RESULT_LOST}]

## Walking away keeps the loot and the survivors (FR-016). Quitting while ahead
## has to be a real option or every run becomes a coin flip on the last node.
func abandon() -> Array:
	if not is_active():
		return []
	state = State.ABANDONED
	return [{"e": "expedition_ended", "result": RESULT_ABANDONED}]

func select_node(index: int) -> Array:
	if not can_select(index):
		return []
	current_node = index
	return [{"e": "expedition_node_selected", "index": index}]

func add_rewards(gained: Dictionary) -> void:
	for res_name in gained:
		rewards[res_name] = int(rewards.get(res_name, 0)) + int(gained[res_name])

# ── Drafts ───────────────────────────────────────────────────────────

## The upgrades on offer after this node. Derived from the expedition seed and
## the node index, so reopening a save shows the same three cards.
func draft_options(count: int = -1) -> Array:
	return Generator.draft_options(
		Generator.draft_rng(seed_value, current_node), living_party(), count
	)

## Applies a pick to the survivors. The bonus rides on the units themselves and
## dies with the expedition — there is no meta-progression here (FR-018).
func apply_draft(option: Dictionary) -> Array:
	if not is_active() or option.is_empty():
		return []
	Generator.apply_option(option, party)
	draft_picks.append(option.duplicate(true))
	return [{"e": "draft_applied", "option": option}]

# ── Result ───────────────────────────────────────────────────────────

func result_code() -> int:
	match state:
		State.COMPLETED:
			return RESULT_WON
		State.ABANDONED:
			return RESULT_ABANDONED
		_:
			return RESULT_LOST

## The ExpeditionResult of data-model.md: what CombatManager hands to the base.
func result_summary() -> Dictionary:
	return {
		"result": result_code(),
		"rewards": rewards.duplicate(),
		"casualties": _tally(casualties()),
		"survivors": _tally(living_party()),
		"nodes_cleared": nodes_cleared(),
		"boss_defeated": boss_defeated(),
	}

func _tally(units: Array) -> Dictionary:
	var counts: Dictionary = {}
	for unit in units:
		counts[unit.unit_id] = int(counts.get(unit.unit_id, 0)) + 1
	return counts

# ── Persistence ──────────────────────────────────────────────────────

## Save shape from data-model.md. The map is deliberately absent: it is rebuilt
## from the seed and repainted with `cleared`, which keeps the save small and
## makes it impossible for a stale map to drift out of sync with its seed.
##
## `era` is stored on top of the documented schema because the rosters depend on
## it: the player can reach a new era while an expedition is paused, and without
## it the enemies would quietly change shape mid-run.
func to_dict() -> Dictionary:
	var units: Array = []
	for unit in party:
		units.append(unit.to_dict())
	return {
		"id": id,
		"seed": seed_value,
		"era": era,
		"current_node": current_node,
		"state": state,
		"morale_snapshot": morale_snapshot,
		"party": units,
		"draft_picks": draft_picks.duplicate(true),
		"rewards": rewards.duplicate(),
		"cleared": cleared_indices(),
	}

## Rebuilds a run from a save. `default_era` covers saves written before `era`
## was stored; a missing key is never an error (constitution, principle V).
##
## Returns null for anything that is not a live expedition, so the caller can
## treat "no key", "empty dict" and "run already finished" the same way.
static func from_dict(data: Dictionary, default_era: int = 1) -> Expedition:
	if data.is_empty() or not data.has("seed"):
		return null
	var run := Expedition.new()
	run.id = int(data.get("id", 0))
	run.seed_value = int(data.get("seed", 0))
	run.era = maxi(1, int(data.get("era", default_era)))
	run.current_node = int(data.get("current_node", 0))
	run.state = int(data.get("state", State.ACTIVE))
	run.morale_snapshot = float(data.get("morale_snapshot", 50.0))
	# JSON hands every number back as a float; the loot is counted in whole
	# units, so it is coerced here instead of leaking 90.0 into the base.
	for res_name in data.get("rewards", {}):
		run.rewards[res_name] = int(data["rewards"][res_name])
	run.draft_picks = data.get("draft_picks", []).duplicate(true)

	run.map = Generator.generate_map(
		Generator.make_rng(run.seed_value), Vector2i.ZERO, Vector2i.ZERO, run.era
	)
	for index in data.get("cleared", []):
		var i: int = int(index)
		if i >= 0 and i < run.map.size():
			run.map[i]["cleared"] = true
	run.current_node = clampi(run.current_node, 0, maxi(0, run.map.size() - 1))

	# The morale modifiers are recomputed rather than stored: they are a pure
	# function of the snapshot, and one less field is one less thing to drift.
	var attack_mod: float = Rules.morale_attack_mod(run.morale_snapshot)
	var initiative_bonus: int = Rules.morale_initiative_bonus(run.morale_snapshot)
	var highest_uid: int = 0
	for unit_data in data.get("party", []):
		var unit: CombatUnit = CombatUnitScript.from_dict(unit_data)
		unit.side = PLAYER
		unit.morale_attack_mod = attack_mod
		unit.morale_initiative_bonus = initiative_bonus
		highest_uid = maxi(highest_uid, unit.uid)
		run.party.append(unit)
	run._next_uid = highest_uid + 1
	return run
