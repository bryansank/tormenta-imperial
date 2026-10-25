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
## Lo mismo para el botin de una salida: un flujo propio, para que sortear el
## botin no mueva el mapa ni los enemigos (y al reves).
const LOOT_SEED_STRIDE := 104729

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

## La primera escaramuza de la partida: un solo nodo, sin salidas ni jefe, con su
## enemigo, su escala y su botin fijados en GameConfig.combat_first_sortie_*. No
## gasta el generador: no hay nada que sortear, y la expedicion que la lleva se
## reconstruye igual desde el guardado sin depender de la semilla.
##
## El nodo lleva `enemy_scale` y `rewards` propios; node_scale() y node_rewards()
## los prefieren a la curva de profundidad, era y riesgo.
static func first_sortie_map() -> Array:
	var nodes: Array = []
	_add_node(nodes, 0, 0, false)
	var node: Dictionary = nodes[0]
	node["enemy_roster"] = GameConfig.combat_first_sortie_roster.duplicate()
	node["enemy_scale"] = GameConfig.combat_first_sortie_enemy_scale
	node["rewards"] = GameConfig.combat_first_sortie_rewards.duplicate()
	node["first_sortie"] = true
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
## En Gobernador (GameMode.combat_hard) todo sale `expedition_enemy_mult` mas
## fuerte; las reglas del tablero no cambian. La primera escaramuza, que trae su
## escala fijada en el nodo, no pasa por aqui.
static func enemy_scale(depth: int, era: int, risk: int, is_boss: bool = false) -> float:
	var scale: float = enemy_pressure(depth, era, risk) * GameMode.expedition_enemy_mult()
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
##
## Aire y mar: solo de `domain` (tierra por defecto). El jefe de siempre lleva un
## tanque, no un acorazado: los barcos enemigos solo salen en nodos de costa
## (add_ships), donde hay agua para ellos.
static func top_tier_unit(era: int, domain: String = "land") -> String:
	var best: String = ""
	var best_tier: int = -1
	for unit_id in GameConfig.get_unit_ids():
		if not _is_available(unit_id, era):
			continue
		if GameConfig.get_unit_domain(String(unit_id)) != domain:
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
	var order: Array = ["infantry", "artillery", "torpedo_boat", "gunboat", "fighter", "vehicle", "dreadnought", "airship"]
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

## The HP/ATK multiplier of one node's enemies: the node's own `enemy_scale` if it
## carries one (the first sortie), the depth/era/risk curve otherwise.
static func node_scale(node: Dictionary, era: int) -> float:
	if node.has("enemy_scale"):
		return float(node["enemy_scale"])
	return enemy_scale(int(node.get("depth", 0)), era, int(node.get("risk", 0)), bool(node.get("is_boss", false)))

## Strength of a whole node, roster and stat multiplier together.
static func node_power(node: Dictionary, era: int) -> float:
	return roster_power(node.get("enemy_roster", {}), node_scale(node, era))

# ── Rewards ──────────────────────────────────────────────────────────

## What clearing this node pays. Deeper, riskier and later-era nodes pay more, on
## the same curve the enemy grows on, so the dangerous road stays worth taking.
static func node_rewards(node: Dictionary, era: int) -> Dictionary:
	# Un nodo con su botin fijado (la primera escaramuza) paga eso, sin curva.
	if node.get("rewards", null) is Dictionary:
		var fixed: Dictionary = {}
		for res_name in node["rewards"]:
			fixed[res_name] = int(node["rewards"][res_name])
		return fixed
	return curve_rewards(node, era)

## La curva de siempre (profundidad, era, riesgo, jefe) sobre combat_reward_base,
## multiplicada por `scale`. node_rewards() la usa con 1.0 cuando el nodo no trae
## su botin fijado; las salidas nuevas la fijan al sortear con
## combat_sortie_reward_mult.
static func curve_rewards(node: Dictionary, era: int, scale: float = 1.0) -> Dictionary:
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
		rewards[res_name] = maxi(1, roundi(float(GameConfig.combat_reward_base[res_name]) * mult * scale))
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

# ── Salidas nuevas: incursion y expedicion corta (doc 21 §3, 2026-10-14) ──
#
# Una salida es una OFERTA del tablon (SortieBoard): {kind, flavor, seed, era,
# blueprint}. El mapa entero sale de la oferta, asi que se ve antes de lanzar y
# se reconstruye igual al cargar la partida. Cada nodo lleva su `rewards`
# (oro y madera, ya fijados) y su `loot` (lo que solo se consigue fuera:
# "parts", "colonists", "tithe_pct" (rebaja del Diezmo en %), "blueprint").

const KIND_RAID := "raid"
const KIND_EXPEDITION := "expedition"
const FLAVOR_BANDITS := "bandits"
const FLAVOR_OUTPOST := "outpost"

## Los nombres de destino de la expedicion (claves de Tr). Se elige uno por
## semilla: es solo un nombre, no cambia nada del mapa.
const EXPEDITION_NAMES := ["SORTIE_DEST_DOCK", "SORTIE_DEST_FACTORY", "SORTIE_DEST_MINE", "SORTIE_DEST_BRIDGE", "SORTIE_DEST_DEPOT"]

## El mapa de una oferta. Vacio si la oferta no es de un tipo conocido.
##
## Aire y mar: si la oferta es de costa (offer_is_coastal), todos sus nodos
## llevan agua en el tablero y barcos enemigos segun la era (make_coastal).
static func sortie_map(offer: Dictionary) -> Array:
	var seed_value: int = int(offer.get("seed", 1))
	var era: int = maxi(1, int(offer.get("era", 1)))
	var map: Array = []
	match String(offer.get("kind", "")):
		KIND_RAID:
			map = raid_map(seed_value, era, String(offer.get("flavor", FLAVOR_BANDITS)))
		KIND_EXPEDITION:
			map = short_expedition_map(seed_value, era, String(offer.get("blueprint", "")))
		KIND_CAMPAIGN:
			# Las tres campanas (feat/tres-campanas): dominio puro, nunca costa mixta.
			return campaign_mission_map(offer)
		KIND_THREAT:
			# Amenazas de costa (feat/amenazas-costa): un combate de dominio puro.
			return threat_map(offer)
	if not map.is_empty() and offer_is_coastal(offer):
		make_coastal(map, seed_value, era)
	return map

# ── Costa: agua en el tablero y barcos enemigos (aire y mar, docs/15 §11) ──

## Un flujo de azar propio para decidir la costa: no mueve ni el mapa, ni los
## enemigos, ni el botin de las ofertas de siempre (y al reves).
const COAST_SEED_STRIDE := 15485863

## ¿Es de costa esta oferta? Desde `combat_coastal_min_era`: la expedicion al
## Puerto (SORTIE_DEST_DOCK) siempre; las incursiones de saqueadores, a veces
## (piratas, `combat_coastal_raid_chance`). La avanzadilla de la Regencia y la
## primera escaramuza, nunca. Se decide solo con la oferta: se ve antes de salir
## y se reconstruye igual al cargar.
static func offer_is_coastal(offer: Dictionary) -> bool:
	# Las misiones MIXTAS (tierra y barcos en el mismo tablero) son futuro
	# (feat/tres-campanas): con el interruptor apagado ninguna oferta es de costa.
	if not GameConfig.combat_mixed_missions_enabled:
		return false
	if int(offer.get("era", 1)) < GameConfig.combat_coastal_min_era:
		return false
	match String(offer.get("kind", "")):
		KIND_EXPEDITION:
			return offer_name_key(offer) == "SORTIE_DEST_DOCK"
		KIND_RAID:
			if String(offer.get("flavor", FLAVOR_BANDITS)) != FLAVOR_BANDITS:
				return false
			var rng := make_rng(int(offer.get("seed", 1)) + COAST_SEED_STRIDE)
			return rng.randf() < GameConfig.combat_coastal_raid_chance
	return false

## Convierte un mapa en uno de costa: cada nodo con `coastal`, su `terrain_seed`
## (el tablero se genera con CombatRules.coastal_terrain), barcos en el roster
## enemigo y un repuesto de mas en el ultimo combate. Muta `map`.
static func make_coastal(map: Array, seed_value: int, era: int) -> void:
	var last: int = boss_index(map)
	for node in map:
		var index: int = int(node.get("index", 0))
		node["coastal"] = true
		node["terrain_seed"] = seed_value + COAST_SEED_STRIDE * (index + 1)
		node["enemy_roster"] = add_ships(node.get("enemy_roster", {}), era, bool(node.get("is_boss", false)))
		if index == last and GameConfig.combat_loot_coastal_parts > 0:
			var loot: Dictionary = node.get("loot", {})
			loot["parts"] = int(loot.get("parts", 0)) + GameConfig.combat_loot_coastal_parts
			node["loot"] = loot

## Los barcos de un roster de costa. Sin azar: el mismo roster da los mismos
## barcos. UN barco por combate, y ocupa el sitio de un cuerpo (un infante si
## hay mas de uno; si no, un canon): el combate de costa tiene los mismos cuerpos
## que el de tierra, nunca mas.
##   era 2: una lancha torpedera (canonera si el roster ya es grande o es jefe);
##   era 3: una canonera (tambien el jefe).
## En era 1 no hay barcos (no los hay en el juego hasta el Astillero).
##
## Medido (2026-10-17, docs/16 "Aire y mar", tools/balance_probe.gd
## --only=coast): con "se suma si no hay infante de sobra" y canonera +
## acorazado en el jefe de era 3, el jefe del Puerto ganaba siempre (1 % con 4
## de tierra en era 2; 0 % en era 3 incluso con 2 canoneras, 2 lanchas o 2
## cazas: solo los bombarderos lo tumbaban). El jefe ya lleva la escolta
## recortada (combat_expedition_boss_escort_cut) y los barcos se la devolvian.
## El acorazado enemigo, aun entrando por el tanque del jefe, seguia en 0 %: se
## queda fuera de las salidas (lo sigue teniendo el jugador).
static func add_ships(roster: Dictionary, era: int, is_boss: bool) -> Dictionary:
	var result: Dictionary = roster.duplicate()
	var ship: String = ""
	if era >= 3:
		ship = "gunboat"
	elif era >= 2:
		ship = "gunboat" if is_boss or roster_size(roster) >= 4 else "torpedo_boat"
	if ship == "" or not _is_available(ship, era):
		return _trim_to_cap(result)
	if int(result.get("infantry", 0)) > 1:
		result["infantry"] = int(result["infantry"]) - 1
	elif int(result.get("artillery", 0)) > 0:
		result["artillery"] = int(result["artillery"]) - 1
		if int(result["artillery"]) == 0:
			result.erase("artillery")
	result[ship] = int(result.get(ship, 0)) + 1
	return _trim_to_cap(result)

## ¿Tiene agua el tablero de este nodo? (La costa mixta, o el mar abierto de la
## Campana de Mar.)
static func node_is_coastal(node: Dictionary) -> bool:
	return bool(node.get("coastal", false)) or String(node.get("terrain_kind", "")) == TERRAIN_KIND_SEA

## El terreno del tablero de un nodo: el de costa si lo es, el mar abierto en la
## Campana de Mar, una costa vista desde el cielo en la de Aire (los aviones
## pisan todo: el agua de abajo es solo paisaje), {} (todo tierra) si no.
static func node_terrain(node: Dictionary, board: Vector2i) -> Dictionary:
	match String(node.get("terrain_kind", "")):
		TERRAIN_KIND_SEA:
			return Rules.open_sea_terrain(board, int(node.get("terrain_seed", 0)), GameConfig.combat_sea_islets)
		TERRAIN_KIND_AIR:
			return Rules.coastal_terrain(board, int(node.get("terrain_seed", 0)))
	if not node_is_coastal(node):
		return {}
	return Rules.coastal_terrain(board, int(node.get("terrain_seed", 0)))

## ¿Algun nodo del mapa es de costa? (La seleccion de tropa lo ensena antes de
## salir y deja llevar barcos.)
static func map_has_water(map: Array) -> bool:
	for node in map:
		if node_is_coastal(node):
			return true
	return false

## La clave de Tr con el nombre de la oferta.
static func offer_name_key(offer: Dictionary) -> String:
	if String(offer.get("kind", "")) == KIND_THREAT:
		return threat_name_key(String(offer.get("threat_type", THREAT_RAIDERS)), String(offer.get("domain", "land")))
	if String(offer.get("kind", "")) == KIND_CAMPAIGN:
		return campaign_mission_name_key(String(offer.get("domain", "land")), int(offer.get("mission", 0)))
	if String(offer.get("kind", "")) == KIND_RAID:
		return "SORTIE_NAME_OUTPOST" if String(offer.get("flavor", "")) == FLAVOR_OUTPOST else "SORTIE_NAME_BANDITS"
	var seed_value: int = absi(int(offer.get("seed", 0)))
	return String(EXPEDITION_NAMES[seed_value % EXPEDITION_NAMES.size()])

## La incursion: un solo combate, sin salidas ni jefe. Los saqueadores traen
## repuestos y colonos rescatados; la avanzadilla de la Regencia, repuestos y la
## rebaja del proximo Diezmo.
static func raid_map(seed_value: int, era: int, flavor: String) -> Array:
	var rng := make_rng(seed_value)
	var nodes: Array = []
	var depth: int = maxi(0, GameConfig.combat_raid_depth)
	var risk: int = 1 if flavor == FLAVOR_OUTPOST else rng.randi_range(0, 1)
	_add_node(nodes, depth, risk, false)
	var node: Dictionary = nodes[0]
	node["enemy_roster"] = enemy_roster(rng, depth, era, risk)
	node["rewards"] = curve_rewards(node, era, GameConfig.combat_sortie_reward_mult)
	node["loot"] = raid_loot(make_rng(seed_value + LOOT_SEED_STRIDE), flavor)
	node["raid"] = true
	return nodes

## Lo que trae una incursion, sorteado dentro de los rangos de GameConfig.
static func raid_loot(rng: RandomNumberGenerator, flavor: String) -> Dictionary:
	var loot: Dictionary = {}
	if flavor == FLAVOR_OUTPOST:
		loot["parts"] = _roll_range(rng, GameConfig.combat_loot_outpost_parts)
		# En puntos de porcentaje enteros: el botin solo lleva enteros.
		loot["tithe_pct"] = maxi(0, roundi(GameConfig.sortie_tithe_discount_pct() * 100.0))
	else:
		loot["parts"] = _roll_range(rng, GameConfig.combat_loot_raid_parts)
		loot["colonists"] = _roll_range(rng, GameConfig.combat_loot_raid_colonists)
	return _drop_zeros(loot)

## La expedicion corta: apertura -> elegir 1 de 2 -> jefe (3 combates). El jefe
## lleva menos escolta y trae lo gordo: mas repuestos, colonos y el plano.
## `blueprint` lo eligio quien sorteo la oferta (vacio = ninguno por conseguir).
static func short_expedition_map(seed_value: int, era: int, blueprint: String = "") -> Array:
	var rng := make_rng(seed_value)
	var nodes: Array = generate_map(rng, GameConfig.combat_expedition_depth,
		GameConfig.combat_expedition_branching, era)
	for node in nodes:
		node["rewards"] = curve_rewards(node, era, GameConfig.combat_sortie_reward_mult)
		if bool(node.get("is_boss", false)):
			node["enemy_roster"] = trim_escort(node["enemy_roster"], GameConfig.combat_expedition_boss_escort_cut)
			node["loot"] = boss_loot(blueprint)
		else:
			node["loot"] = _drop_zeros({"parts": GameConfig.combat_loot_expedition_node_parts})
	return nodes

## Lo que da el jefe de una expedicion corta. Fijo y a la vista (doc 21 §2.3:
## nada de cajas sorpresa).
static func boss_loot(blueprint: String) -> Dictionary:
	var loot: Dictionary = _drop_zeros({
		"parts": GameConfig.combat_loot_expedition_boss_parts,
		"colonists": GameConfig.combat_loot_expedition_boss_colonists,
	})
	if blueprint != "":
		loot["blueprint"] = blueprint
	return loot

## Quita `cut` infantes de escolta, sin dejar nunca el roster vacio.
static func trim_escort(roster: Dictionary, cut: int) -> Dictionary:
	var result: Dictionary = roster.duplicate()
	for i in range(maxi(0, cut)):
		if int(result.get("infantry", 0)) <= 0 or roster_size(result) <= 1:
			break
		result["infantry"] = int(result["infantry"]) - 1
		if int(result["infantry"]) <= 0:
			result.erase("infantry")
	return result

## Todo el botin de un mapa sumado (lo que se lleva quien gana todos sus nodos;
## en una expedicion solo se pisa uno de cada capa, ver path_loot()). Los planos
## van en una lista aparte (`blueprints`).
static func map_loot(map: Array) -> Dictionary:
	var total: Dictionary = {}
	for node in map:
		add_loot(total, node.get("loot", {}))
	return total

## El botin de recorrer el mapa de punta a punta: en cada capa, el nodo que mas
## da (en una expedicion corta todas las rutas dan lo mismo). Es lo que ensena la
## tarjeta de la oferta antes de salir.
static func path_loot(map: Array) -> Dictionary:
	var by_depth: Dictionary = {}
	for node in map:
		var depth: int = int(node.get("depth", 0))
		var loot: Dictionary = node.get("loot", {})
		if not by_depth.has(depth) or _loot_weight(loot) > _loot_weight(by_depth[depth]):
			by_depth[depth] = loot
	var total: Dictionary = {}
	for depth in by_depth:
		add_loot(total, by_depth[depth])
	return total

## El oro y la madera de recorrer el mapa, por la ruta que mas paga.
static func path_rewards(map: Array, era: int) -> Dictionary:
	var by_depth: Dictionary = {}
	for node in map:
		var depth: int = int(node.get("depth", 0))
		var rewards: Dictionary = node_rewards(node, era)
		if not by_depth.has(depth) or _sum(rewards) > _sum(by_depth[depth]):
			by_depth[depth] = rewards
	var total: Dictionary = {}
	for depth in by_depth:
		for res_name in by_depth[depth]:
			total[res_name] = int(total.get(res_name, 0)) + int(by_depth[depth][res_name])
	return total

## Suma `gained` sobre `into`: enteros sumados; "blueprint" (o la lista
## "blueprints") a la lista "blueprints", sin repetir.
static func add_loot(into: Dictionary, gained: Dictionary) -> void:
	for key in gained:
		match String(key):
			"blueprint":
				var list: Array = into.get("blueprints", [])
				var id: String = String(gained[key])
				if id != "" and not list.has(id):
					list.append(id)
				into["blueprints"] = list
			"blueprints":
				for id in gained[key]:
					add_loot(into, {"blueprint": String(id)})
			_:
				into[key] = int(into.get(key, 0)) + int(gained[key])

## La fuerza del nodo mas duro del mapa (el jefe, o el unico nodo de una
## incursion): contra eso se mide la columna en la seleccion de tropa.
## La fuerza de una columna para la prevision (ronda final de la 1.1): la suma
## de `power` por la escala AL CUADRADO (sube la vida y el ataque a la vez) y por
## el numero de cuerpos (ley cuadrada de Lanchester: dos contra tres pierden por
## numero aunque cada uno valga mas). Con la suma a secas, "56 contra 34" (2
## canones contra 3 infantes) salia favorable y se perdia siempre.
static func column_strength(roster: Dictionary, scale: float = 1.0) -> float:
	return roster_power(roster) * scale * scale * float(roster_size(roster))

static func node_strength(node: Dictionary, era: int) -> float:
	return column_strength(node.get("enemy_roster", {}), node_scale(node, era))

static func hardest_node_strength(map: Array, era: int) -> float:
	var best: float = 0.0
	for node in map:
		best = maxf(best, node_strength(node, era))
	return best

static func hardest_node_power(map: Array, era: int) -> float:
	var best: float = 0.0
	for node in map:
		best = maxf(best, node_power(node, era))
	return best

## Cuantos combates pelea quien recorre el mapa de principio a fin (una capa,
## un combate).
static func fights_on_path(map: Array) -> int:
	var depths: Dictionary = {}
	for node in map:
		depths[int(node.get("depth", 0))] = true
	return depths.size()

## El mapa por capas, para pintarlo: Array de Arrays de indices, de la apertura
## al jefe.
static func layers_of(map: Array) -> Array:
	var by_depth: Dictionary = {}
	for node in map:
		var depth: int = int(node.get("depth", 0))
		var list: Array = by_depth.get(depth, [])
		list.append(int(node.get("index", 0)))
		by_depth[depth] = list
	var depths: Array = by_depth.keys()
	depths.sort()
	var result: Array = []
	for depth in depths:
		result.append(by_depth[depth])
	return result

# ── Las tres campanas: Tierra, Mar y Aire (feat/tres-campanas, docs/15 §13) ──
#
# Una mision de campana es una OFERTA como las del tablon, {kind: "campaign",
# domain, mission, seed, era}, y con ella se rehace el mapa entero (se ve antes de
# salir y se reconstruye igual al cargar). DOMINIO PURO: en la de tierra solo
# tropa de tierra, en la de mar solo barcos sobre mar abierto, en la de aire solo
# aviones; el enemigo es del mismo medio. La ultima mision de cada campana es la
# del JEFE de campana. Solo el ultimo combate de cada mision paga: abandonar a
# medias y repetir no da botin dos veces.

const KIND_CAMPAIGN := "campaign"
## Que tablero lleva el nodo (Expedition.current_terrain lo lee).
const TERRAIN_KIND_SEA := "sea"
const TERRAIN_KIND_AIR := "air"
## Flujos propios de la semilla de cada mision (como DRAFT_SEED_STRIDE).
const CAMPAIGN_SEED_STRIDE := 2750159
const CAMPAIGN_DOMAIN_SALT := {"land": 0, "sea": 1000003, "air": 2000029}
const CAMPAIGN_TERRAIN_STRIDE := 104723

## La oferta de la mision `mission` de la campana `domain`. `base_seed` es la de
## la partida (CampaignBook.seed_value): la misma partida, el mismo mapa.
static func campaign_offer(domain: String, mission: int, base_seed: int, era: int) -> Dictionary:
	return {
		"id": -1,
		"kind": KIND_CAMPAIGN,
		"domain": domain,
		"mission": mission,
		"seed": campaign_seed(base_seed, domain, mission),
		"era": maxi(maxi(1, era), campaign_mission_era(domain, mission)),
		"blueprint": "",
	}

## La escala de los enemigos de una mision sobre la curva (campaign_enemy_mult:
## un numero para todo el medio o una fila por mision).
static func campaign_mission_mult(domain: String, mission: int) -> float:
	var value = GameConfig.campaign_enemy_mult.get(domain, 1.0)
	if value is Array:
		var row: Array = value
		if row.is_empty():
			return 1.0
		return float(row[clampi(mission, 0, row.size() - 1)])
	return float(value)

static func campaign_seed(base_seed: int, domain: String, mission: int) -> int:
	var value: int = base_seed + int(CAMPAIGN_DOMAIN_SALT.get(domain, 0)) + CAMPAIGN_SEED_STRIDE * (mission + 1)
	return value if value != 0 else 1

## La era minima de una mision (GameConfig.campaign_defs[domain].eras).
static func campaign_mission_era(domain: String, mission: int) -> int:
	var eras: Array = GameConfig.campaign_defs.get(domain, {}).get("eras", [])
	if eras.is_empty():
		return 1
	return int(eras[clampi(mission, 0, eras.size() - 1)])

## Combates de una mision.
static func campaign_mission_fights(domain: String, mission: int) -> int:
	var fights: Array = GameConfig.campaign_defs.get(domain, {}).get("fights", [])
	if fights.is_empty():
		return 1
	return maxi(1, int(fights[clampi(mission, 0, fights.size() - 1)]))

static func campaign_is_boss_mission(domain: String, mission: int) -> bool:
	return mission == GameConfig.campaign_mission_count(domain) - 1

## Clave de Tr del nombre: CAMP_LAND_M1 ... y CAMP_LAND_BOSS para el jefe.
static func campaign_mission_name_key(domain: String, mission: int) -> String:
	if campaign_is_boss_mission(domain, mission):
		return "CAMP_%s_BOSS" % domain.to_upper()
	return "CAMP_%s_M%d" % [domain.to_upper(), mission + 1]

## El mapa de una mision de campana: una cadena corta (apertura, 1 de 2 en medio
## y el jefe de la mision al final); con un solo combate, un nodo suelto. Todos
## los nodos del medio de la campana, su tablero y su enemigo.
static func campaign_mission_map(offer: Dictionary) -> Array:
	var domain: String = String(offer.get("domain", "land"))
	var mission: int = maxi(0, int(offer.get("mission", 0)))
	var seed_value: int = int(offer.get("seed", 1))
	var era: int = maxi(1, int(offer.get("era", 1)))
	var rng := make_rng(seed_value)
	var fights: int = campaign_mission_fights(domain, mission)
	var boss_mission: bool = campaign_is_boss_mission(domain, mission)
	var level: int = mission * maxi(0, GameConfig.campaign_level_step)
	# Cada derrota en esta mision debilita a la Regencia (mismo mapa, misma
	# semilla): sin dados, perder una vez con una columna era perder siempre.
	var ease: float = maxf(GameConfig.campaign_retry_floor,
		pow(GameConfig.campaign_retry_ease, float(maxi(0, int(offer.get("retries", 0))))))
	var mult: float = campaign_mission_mult(domain, mission) * ease
	var boss_mult: float = float(GameConfig.campaign_boss_extra_scale.get(domain, 1.0)) * ease
	var nodes: Array = _chain_map(rng, fights)
	var last: int = nodes.size() - 1
	for node in nodes:
		var index: int = int(node["index"])
		var depth: int = level + int(node["depth"])
		var final: bool = index == last
		var risk: int = int(node["risk"])
		if final and boss_mission:
			node["enemy_roster"] = campaign_boss_roster(rng, depth, era, domain)
			node["enemy_scale"] = enemy_scale(depth, era, 2, true) * boss_mult
			node["campaign_boss"] = true
		else:
			node["enemy_roster"] = domain_roster(rng, depth, era, risk, domain)
			node["enemy_scale"] = enemy_scale(depth, era, risk, bool(node["is_boss"])) * mult
		node["campaign_domain"] = domain
		if domain == "sea":
			node["terrain_kind"] = TERRAIN_KIND_SEA
		elif domain == "air":
			node["terrain_kind"] = TERRAIN_KIND_AIR
		node["terrain_seed"] = seed_value + CAMPAIGN_TERRAIN_STRIDE * (index + 1)
		if final:
			node["campaign_final"] = true
			node["rewards"] = campaign_rewards(domain, mission, era)
			node["loot"] = campaign_loot(domain, mission, String(offer.get("blueprint", "")))
		else:
			# Los combates de paso no pagan: todo llega con el ultimo.
			node["rewards"] = {}
			node["loot"] = {}
	return nodes

## Una cadena de `fights` capas: la apertura sola, en medio 1 o 2 nodos por capa y
## al final uno solo (el jefe de la mision, is_boss). Con un combate, un nodo sin
## salidas que no es jefe (como la incursion: at_end() lo da por ultimo).
static func _chain_map(rng: RandomNumberGenerator, fights: int) -> Array:
	var nodes: Array = []
	if fights <= 1:
		_add_node(nodes, 0, rng.randi_range(0, 1), false)
		return nodes
	var layers: Array = [[_add_node(nodes, 0, 0, false)]]
	for d in range(1, fights - 1):
		var layer: Array = []
		for i in range(rng.randi_range(1, 2)):
			layer.append(_add_node(nodes, d, _roll_risk(rng), false))
		layers.append(layer)
	layers.append([_add_node(nodes, fights - 1, 2, true)])
	for i in range(layers.size() - 1):
		_link_layers(rng, nodes, layers[i], layers[i + 1], 1, 2)
	return nodes

## Los enemigos de un nodo de campana, del medio de la campana. Tierra: el roster
## de siempre (infanteria, canones y blindados por era). Mar: lanchas en linea,
## canoneras detras y un acorazado en los combates gordos de la era 3. Aire: cazas
## y, detras, dirigibles. Mismo numero de cuerpos que la curva de siempre.
static func domain_roster(rng: RandomNumberGenerator, depth: int, era: int, risk: int, domain: String) -> Dictionary:
	if domain == "land":
		return enemy_roster(rng, depth, era, risk)
	var pressure: float = enemy_pressure(depth, era, risk)
	var cap: int = maxi(1, GameConfig.combat_deploy_cap)
	var slots: int = clampi(roundi(float(GameConfig.combat_enemy_base_slots) * pressure), 1, cap)
	var roster: Dictionary = {}
	if domain == "sea":
		var heavy: int = 1 if era >= 3 and slots >= 4 else 0
		var guns: int = slots / 2
		if guns > 0 and rng.randf() < 0.35:
			guns = mini(guns + 1, slots - heavy - 1) if slots - heavy > 1 else guns
		var line: int = maxi(1, slots - guns - heavy)
		guns = mini(guns, maxi(0, slots - line - heavy))
		roster["torpedo_boat"] = line
		if guns > 0:
			roster["gunboat"] = guns
		if heavy > 0:
			roster["dreadnought"] = heavy
	else:
		var ships: int = slots / 3
		if ships > 0 and rng.randf() < 0.35:
			ships = mini(ships + 1, slots - 1)
		roster["fighter"] = maxi(1, slots - ships)
		if ships > 0:
			roster["airship"] = ships
	return _trim_to_cap(roster)

## El jefe de campana: su escolta del medio y `campaign_boss_heavies` de lo mas
## pesado que su medio tiene en la era (tanque, acorazado o dirigible; en la era 2
## el de mar trae canoneras: el acorazado es de la era 3).
static func campaign_boss_roster(rng: RandomNumberGenerator, depth: int, era: int, domain: String) -> Dictionary:
	var roster: Dictionary = domain_roster(rng, depth, era, 1, domain)
	var top: String = _domain_heavy(era, domain)
	if top != "":
		roster[top] = int(roster.get(top, 0)) + maxi(1, int(GameConfig.campaign_boss_heavies.get(domain, 1)))
	return _trim_to_cap(roster)

## Lo mas pesado de un medio que la era deja sacar al enemigo. Para el aire es
## siempre el dirigible (todo el aire es de la era 3); para la tierra y el mar,
## top_tier_unit (el tanque o la artilleria; el acorazado o la canonera).
static func _domain_heavy(era: int, domain: String) -> String:
	if domain == "air":
		return "airship"
	var top: String = top_tier_unit(era, domain)
	if domain == "sea" and top == "torpedo_boat":
		return "gunboat"
	return top

## Oro y madera (la curva de siempre a la altura de la mision) y el recurso de
## mas de su medio (acero en el mar, petroleo en el aire).
static func campaign_rewards(domain: String, mission: int, era: int) -> Dictionary:
	var level_node := {"depth": mission * maxi(0, GameConfig.campaign_level_step), "risk": 1,
		"is_boss": campaign_is_boss_mission(domain, mission)}
	var rewards: Dictionary = curve_rewards(level_node, era, GameConfig.campaign_reward_mult)
	var bonus_res: String = String(GameConfig.campaign_defs.get(domain, {}).get("bonus_res", ""))
	if bonus_res != "":
		var amount: int = GameConfig.campaign_bonus_base + GameConfig.campaign_bonus_per_mission * mission
		if campaign_is_boss_mission(domain, mission):
			amount *= 2
		rewards[bonus_res] = int(rewards.get(bonus_res, 0)) + amount
	return rewards

## Lo exclusivo de una mision ganada: repuestos, colonos (tierra) y la rebaja del
## proximo Impuesto; el jefe, mas de todo y el plano si queda alguno.
static func campaign_loot(domain: String, mission: int, blueprint: String = "") -> Dictionary:
	var loot: Dictionary = {}
	if campaign_is_boss_mission(domain, mission):
		loot["parts"] = GameConfig.campaign_boss_parts
		loot["colonists"] = GameConfig.campaign_boss_colonists
		loot["tithe_pct"] = GameConfig.campaign_boss_tithe_pct
		if blueprint != "":
			loot["blueprint"] = blueprint
	else:
		loot["parts"] = int(GameConfig.campaign_mission_parts.get(domain, 0))
		loot["colonists"] = int(GameConfig.campaign_mission_colonists.get(domain, 0))
		loot["tithe_pct"] = GameConfig.campaign_mission_tithe_pct
	return _drop_zeros(loot)

## ¿Es este mapa una mision de campana? (El dominio lo lleva cada nodo.)
static func map_campaign_domain(map: Array) -> String:
	for node in map:
		var domain: String = String(node.get("campaign_domain", ""))
		if domain != "":
			return domain
	return ""

# ── Amenazas de costa (feat/amenazas-costa, docs/15 §14) ─────────────
#
# Botin opcional (decision de Bryan, 2026-10-18): marcas en la orilla que se van
# solas sin hacer dano. Una amenaza atacable es una OFERTA como las del tablon,
#   {id, kind: "threat", threat_id, threat_type, seed, era, domain}
# y con ella se rehace su unico combate y su botin (se ve antes de salir y se
# reconstruye igual al cargar). DOMINIO PURO: en tierra, tropa de tierra contra
# tropa de tierra; en el agua, barcos contra barcos sobre mar abierto. El pecio
# no se pelea: se explora con trabajadores, y su botin sale de las mismas
# funciones (threat_rewards / threat_loot).

const KIND_THREAT := "threat"
const THREAT_RAIDERS := "raiders"
const THREAT_VANGUARD := "vanguard"
const THREAT_WRECK := "wreck"
const THREAT_TYPES := [THREAT_RAIDERS, THREAT_VANGUARD, THREAT_WRECK]
## Flujos propios de la semilla de la amenaza (como LOOT_SEED_STRIDE): el botin no
## mueve al enemigo ni al reves.
const THREAT_REWARD_STRIDE := 7368787
const THREAT_LOOT_STRIDE := 9369319
const THREAT_TERRAIN_STRIDE := 104717

## Clave de Tr del nombre: THREAT_NAME_RAIDERS, _RAIDERS_SEA, _VANGUARD, _WRECK.
static func threat_name_key(threat_type: String, domain: String = "land") -> String:
	if threat_type == THREAT_RAIDERS and domain == "sea":
		return "THREAT_NAME_RAIDERS_SEA"
	return "THREAT_NAME_" + threat_type.to_upper()

## ¿Se pelea esta amenaza? (El pecio se explora.)
static func threat_is_fight(threat_type: String) -> bool:
	return threat_type == THREAT_RAIDERS or threat_type == THREAT_VANGUARD

## El unico combate de una amenaza. Vacio para el pecio (no se pelea).
static func threat_map(offer: Dictionary) -> Array:
	var threat_type: String = String(offer.get("threat_type", THREAT_RAIDERS))
	if not threat_is_fight(threat_type):
		return []
	var seed_value: int = int(offer.get("seed", 1))
	var era: int = maxi(1, int(offer.get("era", 1)))
	var domain: String = String(offer.get("domain", "land"))
	var fight: Dictionary = GameConfig.threat_fight.get(threat_type, {})
	var rng := make_rng(seed_value)
	var depth: int = maxi(0, int(fight.get("depth", 0)))
	var risk: int = clampi(_roll_range(rng, fight.get("risk", Vector2i(0, 1))), 0, 2)
	var nodes: Array = []
	_add_node(nodes, depth, risk, false)
	var node: Dictionary = nodes[0]
	node["enemy_roster"] = domain_roster(rng, depth, era, risk, domain)
	node["enemy_scale"] = enemy_scale(depth, era, risk) * float(fight.get("mult", 1.0))
	if domain == "sea":
		node["terrain_kind"] = TERRAIN_KIND_SEA
		node["terrain_seed"] = seed_value + THREAT_TERRAIN_STRIDE
	node["rewards"] = threat_rewards(offer)
	node["loot"] = threat_loot(offer)
	node["raid"] = true
	node["threat"] = threat_type
	return nodes

## Oro, madera (y acero en la avanzadilla) de una amenaza, fijos por su semilla
## y un poco mas por era (GameConfig.threat_rewards, threat_era_reward_step).
static func threat_rewards(offer: Dictionary) -> Dictionary:
	var threat_type: String = String(offer.get("threat_type", THREAT_RAIDERS))
	var era: int = maxi(1, int(offer.get("era", 1)))
	var rng := make_rng(int(offer.get("seed", 1)) + THREAT_REWARD_STRIDE)
	var table: Dictionary = GameConfig.threat_rewards.get(threat_type, {})
	var mult: float = 1.0 + GameConfig.threat_era_reward_step * float(era - 1)
	var out: Dictionary = {}
	for res_name in table:
		var amount: int = roundi(float(_roll_range(rng, table[res_name])) * mult)
		if amount > 0:
			out[String(res_name)] = amount
	return out

## Lo que solo da una amenaza: repuestos y, a veces, un material de taller
## ("planks", "ingots", "beams", "fuel") segun la era. Fijo por la semilla: la
## tarjeta lo ensena antes de atacar o explorar.
static func threat_loot(offer: Dictionary) -> Dictionary:
	var threat_type: String = String(offer.get("threat_type", THREAT_RAIDERS))
	var era: int = clampi(int(offer.get("era", 1)), 1, 3)
	var rng := make_rng(int(offer.get("seed", 1)) + THREAT_LOOT_STRIDE)
	var loot: Dictionary = {}
	loot["parts"] = _roll_range(rng, GameConfig.threat_parts.get(threat_type, Vector2i.ZERO))
	if String(offer.get("domain", "land")) == "sea":
		loot["parts"] = int(loot["parts"]) + maxi(0, GameConfig.threat_sea_extra_parts)
	var rare_roll: float = rng.randf()
	if rare_roll < float(GameConfig.threat_rare_chance.get(threat_type, 0.0)):
		var pool: Array = GameConfig.threat_rare_by_era.get(era, [])
		if not pool.is_empty():
			var material: String = String(pool[rng.randi_range(0, pool.size() - 1)])
			loot[material] = int(loot.get(material, 0)) + _roll_range(rng, GameConfig.threat_rare_amount)
	return _drop_zeros(loot)

static func _roll_range(rng: RandomNumberGenerator, range_v: Vector2i) -> int:
	return rng.randi_range(mini(range_v.x, range_v.y), maxi(range_v.x, range_v.y))

static func _drop_zeros(loot: Dictionary) -> Dictionary:
	var clean: Dictionary = {}
	for key in loot:
		if loot[key] is String or int(loot[key]) > 0:
			clean[key] = loot[key]
	return clean

static func _loot_weight(loot: Dictionary) -> int:
	var total: int = 0
	for key in loot:
		if loot[key] is String:
			total += 100
		elif loot[key] is Array:
			total += 100 * (loot[key] as Array).size()
		else:
			total += int(loot[key])
	return total

static func _sum(amounts: Dictionary) -> int:
	var total: int = 0
	for value in amounts.values():
		total += int(value)
	return total
