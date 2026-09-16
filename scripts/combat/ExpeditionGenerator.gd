extends RefCounted
class_name ExpeditionGenerator
## Builds an expedition out of a single number: the map, the enemy rosters, the
## loot and the drafts all come from one seeded RandomNumberGenerator.
##
## Static and pure — no nodes, no signals, no global randomness. `randf()` is
## banned here on purpose: the save only stores the seed and the list of cleared
## nodes, so the map has to be rebuildable byte for byte when the player reopens
## the game (research D5, D6). Two expeditions with the same seed are the same
## expedition.
##
## All balance lives in GameConfig.combat_* (constitution, principle III).

const Rules := preload("res://scripts/combat/CombatRules.gd")

## Offsets that derive a child RNG from the expedition seed. Arbitrary primes:
## what matters is that the draft at node 3 always rolls the same way without
## depending on how many times the map generator happened to call the RNG.
const DRAFT_SEED_STRIDE := 7919

## The catalogue of draft upgrades. `stat` empty means the option heals instead
## of buffing a derived stat.
const DRAFT_CATALOGUE := [
	{"id": "draft_atk", "label_key": "DRAFT_ATK", "stat": "atk"},
	{"id": "draft_def", "label_key": "DRAFT_DEF", "stat": "def"},
	{"id": "draft_move", "label_key": "DRAFT_MOVE", "stat": "move"},
	{"id": "draft_init", "label_key": "DRAFT_INIT", "stat": "initiative"},
	{"id": "draft_hp_heal", "label_key": "DRAFT_HP_HEAL", "stat": ""},
]

# ── Seeding ──────────────────────────────────────────────────────────

## The one place a RandomNumberGenerator is born. Everything downstream takes it
## as an argument so a test can hand over its own.
static func make_rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng

## An independent stream for one node's draft, so drafts stay reproducible after
## a save/load even though the map generator is not replayed alongside them.
static func draft_rng(seed_value: int, node_index: int) -> RandomNumberGenerator:
	return make_rng(seed_value + DRAFT_SEED_STRIDE * (node_index + 1))

# ── Map ──────────────────────────────────────────────────────────────

## Builds the branching map as a layered graph: one start node, `depth` layers of
## choices, and the boss at the end.
##
## The hard invariant is that **every node reaches the boss**. It comes for free
## from the shape: edges only ever go from one layer to the next, every node gets
## at least one exit, and every node gets at least one parent. Induction from the
## boss backwards does the rest — no dead ends, no orphans, no repair pass.
##
## `depth_range` / `branching_range` default to GameConfig when left at zero.
## `era` only feeds the rosters; the shape of the map does not care about it.
static func generate_map(rng: RandomNumberGenerator, depth_range: Vector2i = Vector2i.ZERO, branching_range: Vector2i = Vector2i.ZERO, era: int = 1) -> Array:
	var depth_cfg: Vector2i = depth_range if depth_range != Vector2i.ZERO else GameConfig.combat_map_depth
	var branch_cfg: Vector2i = branching_range if branching_range != Vector2i.ZERO else GameConfig.combat_map_branching

	var steps: int = rng.randi_range(mini(depth_cfg.x, depth_cfg.y), maxi(depth_cfg.x, depth_cfg.y))
	var min_branch: int = maxi(1, mini(branch_cfg.x, branch_cfg.y))
	var max_branch: int = maxi(min_branch, maxi(branch_cfg.x, branch_cfg.y))

	var nodes: Array = []
	# layers[i] holds the node indices sitting at depth i.
	var layers: Array = []

	# Depth 0: the opening fight, always alone and always the tame one. A run
	# that can open on a high-risk node is a run that can be over before the
	# player has understood the board.
	layers.append([_add_node(nodes, 0, 0, false)])

	for d in range(1, steps + 1):
		var width: int = rng.randi_range(min_branch, max_branch)
		var layer: Array = []
		for i in range(width):
			layer.append(_add_node(nodes, d, _roll_risk(rng), false))
		layers.append(layer)

	layers.append([_add_node(nodes, steps + 1, 2, true)])

	for i in range(layers.size() - 1):
		_link_layers(rng, nodes, layers[i], layers[i + 1], min_branch, max_branch)

	# Rosters last, in index order, so the RNG stream stays stable no matter how
	# the linking above evolves.
	for node in nodes:
		if node["is_boss"]:
			node["enemy_roster"] = boss_roster(rng, int(node["depth"]), era)
		else:
			node["enemy_roster"] = enemy_roster(rng, int(node["depth"]), era, int(node["risk"]))

	return nodes

static func _add_node(nodes: Array, depth: int, risk: int, is_boss: bool) -> int:
	var index: int = nodes.size()
	nodes.append({
		"index": index,
		"depth": depth,
		"exits": [],
		"enemy_roster": {},
		"risk": risk,
		"is_boss": is_boss,
		"cleared": false,
	})
	return index

## Weighted towards the safe side: high risk should feel like a choice the player
## made, not like the map's default mood.
static func _roll_risk(rng: RandomNumberGenerator) -> int:
	var roll: float = rng.randf()
	if roll < 0.45:
		return 0
	return 1 if roll < 0.82 else 2

## Wires one layer to the next. Two passes: give every parent its exits, then
## adopt any child nobody picked. Both halves of the invariant, in that order.
static func _link_layers(rng: RandomNumberGenerator, nodes: Array, parents: Array, children: Array, min_branch: int, max_branch: int) -> void:
	var adopted: Dictionary = {}
	for parent in parents:
		var wanted: int = clampi(rng.randi_range(min_branch, max_branch), 1, children.size())
		var picks: Array = _shuffled(rng, children).slice(0, wanted)
		picks.sort()
		nodes[parent]["exits"] = picks
		for child in picks:
			adopted[child] = true
	for child in children:
		if adopted.has(child):
			continue
		var parent: int = parents[rng.randi_range(0, parents.size() - 1)]
		var exits: Array = nodes[parent]["exits"]
		exits.append(child)
		exits.sort()

## Fisher-Yates against the expedition's own RNG. Array.shuffle() would reach for
## the global generator and break determinism.
static func _shuffled(rng: RandomNumberGenerator, source: Array) -> Array:
	var result: Array = source.duplicate()
	for i in range(result.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = result[i]
		result[i] = result[j]
		result[j] = tmp
	return result

# ── Enemy rosters ────────────────────────────────────────────────────

## How much harder than the opening fight this node is. Depth, era and risk all
## push in the same direction; the boss multiplies whatever came out.
static func enemy_pressure(depth: int, era: int, risk: int) -> float:
	return 1.0 \
		+ GameConfig.combat_enemy_scale_per_depth * float(maxi(0, depth)) \
		+ GameConfig.combat_enemy_scale_per_era * float(maxi(0, era - 1)) \
		+ GameConfig.combat_risk_enemy_scale * float(clampi(risk, 0, 2))

## The HP/ATK multiplier handed to CombatUnit.create() for this node's enemies.
static func enemy_scale(depth: int, era: int, risk: int, is_boss: bool = false) -> float:
	var scale: float = enemy_pressure(depth, era, risk)
	if is_boss:
		scale *= GameConfig.combat_boss_multiplier
	return scale

## Composition, not just a number of bodies: a line of infantry with guns behind
## it, and armour once the era fields it. That shape is what makes the artillery's
## minimum range and the player's positioning matter from the first node.
##
## Only the count comes from here; the stat multiplier is enemy_scale().
static func enemy_roster(rng: RandomNumberGenerator, depth: int, era: int, risk: int) -> Dictionary:
	var pressure: float = enemy_pressure(depth, era, risk)
	var cap: int = maxi(1, GameConfig.combat_deploy_cap)
	var slots: int = clampi(roundi(float(GameConfig.combat_enemy_base_slots) * pressure), 1, cap)

	var guns: int = slots / 3 if _is_available("artillery", era) else 0
	# A coin flip for one extra gun: the same depth twice should not field the
	# same squad twice, or the map stops being worth generating.
	if guns > 0 and slots >= 3 and rng.randf() < 0.35:
		guns += 1
	var armour: int = 1 if _is_available("vehicle", era) and slots >= 4 else 0
	var line: int = maxi(1, slots - guns - armour)
	# maxi() above can push the total over; the line is what gives way.
	guns = mini(guns, maxi(0, slots - line - armour))

	var roster: Dictionary = {}
	roster["infantry"] = line
	if guns > 0:
		roster["artillery"] = guns
	if armour > 0:
		roster["vehicle"] = armour
	return roster

## The boss is the same squad plus the heaviest thing the era can field. It gets
## its teeth from enemy_scale(), not from drowning the board in bodies.
static func boss_roster(rng: RandomNumberGenerator, depth: int, era: int) -> Dictionary:
	var roster: Dictionary = enemy_roster(rng, depth, era, 2)
	var top: String = top_tier_unit(era)
	if top != "":
		roster[top] = int(roster.get(top, 0)) + 1
	return _trim_to_cap(roster)

## Heaviest unit type the given era unlocks, by tier.
static func top_tier_unit(era: int) -> String:
	var best: String = ""
	var best_tier: int = -1
	for unit_id in GameConfig.get_unit_ids():
		if not _is_available(unit_id, era):
			continue
		var tier: int = int(GameConfig.get_unit_def(unit_id).get("tier", 0))
		if tier > best_tier:
			best_tier = tier
			best = unit_id
	return best

static func _is_available(unit_id: String, era: int) -> bool:
	return era >= int(GameConfig.get_unit_def(unit_id).get("era", 1))

## Sheds the cheapest bodies first until the roster fits on the board.
static func _trim_to_cap(roster: Dictionary) -> Dictionary:
	var cap: int = maxi(1, GameConfig.combat_deploy_cap)
	var order: Array = ["infantry", "artillery", "vehicle"]
	while roster_size(roster) > cap:
		var removed := false
		for unit_id in order:
			if int(roster.get(unit_id, 0)) > 0:
				roster[unit_id] = int(roster[unit_id]) - 1
				if int(roster[unit_id]) <= 0:
					roster.erase(unit_id)
				removed = true
				break
		if not removed:
			break
	return roster

static func roster_size(roster: Dictionary) -> int:
	var total: int = 0
	for count in roster.values():
		total += int(count)
	return total

## A single comparable number for "how hard is this node", used by the map UI and
## by the tests that check difficulty actually climbs.
static func roster_power(roster: Dictionary, scale: float = 1.0) -> float:
	var total: float = 0.0
	for unit_id in roster:
		var power: int = int(GameConfig.get_unit_def(unit_id).get("power", 1))
		total += float(power) * float(roster[unit_id])
	return total * scale

## Strength of a whole node, roster and stat multiplier together.
static func node_power(node: Dictionary, era: int) -> float:
	return roster_power(
		node.get("enemy_roster", {}),
		enemy_scale(int(node.get("depth", 0)), era, int(node.get("risk", 0)), bool(node.get("is_boss", false)))
	)

# ── Rewards ──────────────────────────────────────────────────────────

## What clearing this node pays. Deeper, riskier and later-era nodes pay more, on
## the same curve the enemy grows on, so the dangerous road stays worth taking.
static func node_rewards(node: Dictionary, era: int) -> Dictionary:
	var depth: int = int(node.get("depth", 0))
	var risk: int = int(node.get("risk", 0))
	var mult: float = 1.0 \
		+ GameConfig.combat_enemy_scale_per_depth * float(maxi(0, depth)) \
		+ GameConfig.combat_enemy_scale_per_era * float(maxi(0, era - 1)) \
		+ GameConfig.combat_risk_reward_bonus * float(clampi(risk, 0, 2))
	if bool(node.get("is_boss", false)):
		mult *= GameConfig.combat_boss_multiplier
	var rewards: Dictionary = {}
	for res_name in GameConfig.combat_reward_base:
		rewards[res_name] = maxi(1, roundi(float(GameConfig.combat_reward_base[res_name]) * mult))
	return rewards

# ── Drafts ───────────────────────────────────────────────────────────

## The upgrades offered after a won encounter. Every option returned is
## applicable to the party as it stands (SC-009): a field station is not an
## option for a party at full health, and the generator refuses to offer it.
##
## `party` is the list of the player's CombatUnits; the dead are ignored.
static func draft_options(rng: RandomNumberGenerator, party: Array, count: int = -1) -> Array:
	var wanted: int = count if count > 0 else GameConfig.combat_draft_options
	var living: Array = _living(party)
	if living.is_empty():
		return []

	var pool: Array = []
	for entry in DRAFT_CATALOGUE:
		var option: Dictionary = _build_option(rng, entry, living)
		if is_applicable(option, living):
			pool.append(option)

	# The four stat upgrades are applicable whenever anybody is still standing,
	# so the pool cannot fall under the two options the spec demands.
	return _shuffled(rng, pool).slice(0, mini(wanted, pool.size()))

## Rolls one catalogue entry into a concrete offer, choosing between helping the
## whole party a little or one unit type twice as much.
static func _build_option(rng: RandomNumberGenerator, entry: Dictionary, living: Array) -> Dictionary:
	var values: Dictionary = GameConfig.combat_draft_values
	var types: Array = _living_types(living)
	var applies_to: String = "all"
	var focus: int = 1
	if types.size() > 1 and rng.randf() < 0.4:
		applies_to = String(types[rng.randi_range(0, types.size() - 1)])
		focus = maxi(1, GameConfig.combat_draft_focus_multiplier)

	var stat: String = String(entry["stat"])
	var effect: Dictionary = {}
	if stat == "":
		# Healing does not double up when focused: a full heal for one unit type
		# would be strictly better than every other card on the table.
		effect = {"heal_pct": float(values.get("heal_pct", 0.3))}
	else:
		effect = {"stat": stat, "delta": int(values.get(stat, 1)) * focus}

	return {
		"id": String(entry["id"]),
		"label_key": String(entry["label_key"]),
		"effect": effect,
		"applies_to": applies_to,
	}

## Applicable = at least one living unit actually gains something. Healing a
## party already at full health is the case this exists for.
static func is_applicable(option: Dictionary, party: Array) -> bool:
	var effect: Dictionary = option.get("effect", {})
	var applies_to: String = String(option.get("applies_to", "all"))
	for unit in _living(party):
		if applies_to != "all" and unit.unit_id != applies_to:
			continue
		if effect.has("heal_pct"):
			if unit.hp < unit.max_hp:
				return true
		elif int(effect.get("delta", 0)) != 0:
			return true
	return false

## Applies a chosen option to the party. Only the living benefit — a draft never
## brings anybody back (FR-010).
static func apply_option(option: Dictionary, party: Array) -> void:
	var effect: Dictionary = option.get("effect", {})
	var applies_to: String = String(option.get("applies_to", "all"))
	for unit in _living(party):
		if applies_to != "all" and unit.unit_id != applies_to:
			continue
		if effect.has("heal_pct"):
			unit.heal_percent(float(effect["heal_pct"]))
		else:
			var stat: String = String(effect.get("stat", ""))
			if stat == "":
				continue
			unit.draft_bonuses[stat] = int(unit.draft_bonuses.get(stat, 0)) + int(effect.get("delta", 0))

static func _living(party: Array) -> Array:
	var alive: Array = []
	for unit in party:
		if unit != null and unit.is_alive():
			alive.append(unit)
	return alive

static func _living_types(living: Array) -> Array:
	var types: Array = []
	for unit in living:
		if not types.has(unit.unit_id):
			types.append(unit.unit_id)
	types.sort()
	return types

# ── Map queries ──────────────────────────────────────────────────────

## Every node index reachable from `from_index`, following exits forward.
static func reachable_from(map: Array, from_index: int) -> Array:
	var seen: Dictionary = {}
	var queue: Array = [from_index]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		if seen.has(current) or current < 0 or current >= map.size():
			continue
		seen[current] = true
		for exit_index in map[current].get("exits", []):
			queue.append(int(exit_index))
	return seen.keys()

static func boss_index(map: Array) -> int:
	for i in range(map.size() - 1, -1, -1):
		if bool(map[i].get("is_boss", false)):
			return i
	return map.size() - 1

## The invariant this whole file is built around, exposed so tests and the map UI
## can assert it instead of trusting the comment above.
static func every_node_reaches_boss(map: Array) -> bool:
	if map.is_empty():
		return false
	var boss: int = boss_index(map)
	for i in range(map.size()):
		if i == boss:
			continue
		if not reachable_from(map, i).has(boss):
			return false
	return true
