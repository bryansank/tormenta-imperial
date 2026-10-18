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
	var order: Array = ["infantry", "artillery", "torpedo_boat", "gunboat", "vehicle", "dreadnought"]
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
## barcos. Cada barco ocupa el sitio de un infante (nunca deja la linea vacia ni
## pasa del tope del tablero):
##   era 2: una lancha torpedera (canonera si el roster ya es grande o es jefe);
##   era 3: una canonera, y el jefe ademas un acorazado.
## En era 1 no hay barcos (no los hay en el juego hasta el Astillero).
static func add_ships(roster: Dictionary, era: int, is_boss: bool) -> Dictionary:
	var result: Dictionary = roster.duplicate()
	var ships: Array = []
	if era >= 3:
		ships.append("gunboat")
		if is_boss and _is_available("dreadnought", era):
			ships.append("dreadnought")
	elif era >= 2:
		ships.append("gunboat" if is_boss or roster_size(roster) >= 4 else "torpedo_boat")
	for ship in ships:
		if not _is_available(String(ship), era):
			continue
		# El barco entra por un infante si hay mas de uno; si no, se suma.
		if int(result.get("infantry", 0)) > 1:
			result["infantry"] = int(result["infantry"]) - 1
		result[ship] = int(result.get(ship, 0)) + 1
	return _trim_to_cap(result)

## ¿Tiene agua el tablero de este nodo?
static func node_is_coastal(node: Dictionary) -> bool:
	return bool(node.get("coastal", false))

## El terreno del tablero de un nodo: el de costa si lo es, {} (todo tierra) si no.
static func node_terrain(node: Dictionary, board: Vector2i) -> Dictionary:
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
