extends RefCounted
class_name ConquestGenerator
## Volverse el Imperio (feat/volverse-imperio): las misiones de conquista de las
## islas vecinas. Puro y estatico, como ExpeditionGenerator: la misma oferta da
## siempre el mismo mapa (se ve antes de salir y se reconstruye igual al cargar).
##
## Una mision es una OFERTA como las de las campanas:
##   {kind: "conquest", island, mission, domain, seed, era, id: -1, blueprint: ""}
## y su mapa es una cadena corta (la de las campanas, ExpeditionGenerator._chain_map)
## de DOMINIO PURO: en mar, barcos sobre mar abierto; en aire, aviones sobre la
## costa; en tierra, el roster de siempre. La dureza sale del nivel de la isla
## (GameConfig.empire_tier_enemy) sobre la curva enemiga de siempre, en la era 3.
## Solo paga el ultimo combate de cada mision (abandonar y repetir no da botin dos
## veces). La isla y su tributo los da EmpireManager al volver la columna.

const KIND := "conquest"
## Flujos propios de la semilla (como CAMPAIGN_SEED_STRIDE).
const SEED_STRIDE := 7368787
const ISLAND_STRIDE := 1299709
const TERRAIN_STRIDE := 104729

## La oferta de la mision `mission` de `island_id`. `base_seed` es la de la
## partida (Archipelago.seed_value).
static func offer(island_id: String, mission: int, base_seed: int, era: int) -> Dictionary:
	var def: Dictionary = mission_def(island_id, mission)
	return {
		"id": -1,
		"kind": KIND,
		"island": island_id,
		"mission": mission,
		"domain": String(def.get("domain", "land")),
		"seed": mission_seed(base_seed, island_id, mission),
		"era": maxi(maxi(1, era), GameConfig.empire_min_era),
		"blueprint": "",
	}

static func island_index(island_id: String) -> int:
	return maxi(0, GameConfig.empire_island_ids().find(island_id))

static func mission_seed(base_seed: int, island_id: String, mission: int) -> int:
	var value: int = base_seed + ISLAND_STRIDE * (island_index(island_id) + 1) + SEED_STRIDE * (mission + 1)
	return value if value != 0 else 1

static func mission_def(island_id: String, mission: int) -> Dictionary:
	var list: Array = GameConfig.empire_island(island_id).get("missions", [])
	if mission < 0 or mission >= list.size():
		return {}
	return list[mission]

static func mission_count(island_id: String) -> int:
	return (GameConfig.empire_island(island_id).get("missions", []) as Array).size()

static func is_final(island_id: String, mission: int) -> bool:
	return mission == mission_count(island_id) - 1

static func is_boss_mission(island_id: String, mission: int) -> bool:
	return bool(mission_def(island_id, mission).get("boss", false))

## Clave de Tr del nombre de la mision (EMP_M_*).
static func mission_name_key(island_id: String, mission: int) -> String:
	return String(mission_def(island_id, mission).get("name", "EMP_M_LAND_LANDING"))

static func island_name_key(island_id: String) -> String:
	return "EMP_ISLE_%s_NAME" % island_id.to_upper()

static func tier_enemy(island_id: String) -> Dictionary:
	var t: int = clampi(int(GameConfig.empire_island(island_id).get("tier", 1)), 1, 3)
	return GameConfig.empire_tier_enemy.get(t, {"depth": 4, "mult": 1.0})

## El mapa de una mision de conquista. Vacio si la isla o la mision no existen.
static func mission_map(p_offer: Dictionary) -> Array:
	var island_id: String = String(p_offer.get("island", ""))
	var mission: int = maxi(0, int(p_offer.get("mission", 0)))
	var def: Dictionary = mission_def(island_id, mission)
	if def.is_empty():
		return []
	var domain: String = String(def.get("domain", "land"))
	var seed_value: int = int(p_offer.get("seed", 1))
	var era: int = maxi(1, int(p_offer.get("era", GameConfig.empire_min_era)))
	var rng := ExpeditionGenerator.make_rng(seed_value)
	var fights: int = maxi(1, int(def.get("fights", 1)))
	var boss_mission: bool = bool(def.get("boss", false))
	var enemy: Dictionary = tier_enemy(island_id)
	var level: int = int(enemy.get("depth", 4)) + mission
	var mult: float = float(enemy.get("mult", 1.0))
	var nodes: Array = ExpeditionGenerator._chain_map(rng, fights)
	var last: int = nodes.size() - 1
	for node in nodes:
		var index: int = int(node["index"])
		var depth: int = level + int(node["depth"])
		var final: bool = index == last
		var risk: int = int(node["risk"])
		if final and boss_mission:
			node["enemy_roster"] = ExpeditionGenerator.campaign_boss_roster(rng, depth, era, domain)
			node["enemy_scale"] = ExpeditionGenerator.enemy_scale(depth, era, 2, true) * GameConfig.empire_boss_extra_scale
			node["conquest_boss"] = true
		else:
			node["enemy_roster"] = ExpeditionGenerator.domain_roster(rng, depth, era, risk, domain)
			node["enemy_scale"] = ExpeditionGenerator.enemy_scale(depth, era, risk, bool(node["is_boss"])) * mult
		# El medio del tablero y del fondo del mapa (BattleScreen lo pinta).
		node["conquest_domain"] = domain
		node["conquest_island"] = island_id
		if domain == "sea":
			node["terrain_kind"] = ExpeditionGenerator.TERRAIN_KIND_SEA
		elif domain == "air":
			node["terrain_kind"] = ExpeditionGenerator.TERRAIN_KIND_AIR
		node["terrain_seed"] = seed_value + TERRAIN_STRIDE * (index + 1)
		if final:
			node["conquest_final"] = true
			node["rewards"] = rewards(island_id, mission, era)
			node["loot"] = loot(island_id, mission)
		else:
			node["rewards"] = {}
			node["loot"] = {}
	return nodes

## Oro y madera de la curva a la altura de la mision (por empire_reward_mult).
static func rewards(island_id: String, mission: int, era: int) -> Dictionary:
	var enemy: Dictionary = tier_enemy(island_id)
	var level_node := {"depth": int(enemy.get("depth", 4)) + mission, "risk": 1,
		"is_boss": is_boss_mission(island_id, mission)}
	return ExpeditionGenerator.curve_rewards(level_node, era, GameConfig.empire_reward_mult)

## Lo de mas de una mision ganada: repuestos (el doble en la que toma la isla).
static func loot(island_id: String, mission: int) -> Dictionary:
	var parts: int = maxi(0, GameConfig.empire_mission_parts)
	if is_final(island_id, mission):
		parts *= 2
	return {"parts": parts} if parts > 0 else {}

## ¿Es este mapa una mision de conquista? Devuelve la isla ("" si no).
static func map_island(map: Array) -> String:
	for node in map:
		var island_id: String = String(node.get("conquest_island", ""))
		if island_id != "":
			return island_id
	return ""
