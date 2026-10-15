extends RefCounted
class_name CombatRules
## Pure combat maths. No nodes, no global state, no randomness: every function
## here is deterministic and unit-testable in headless mode.
##
## All tunable numbers come from GameConfig.combat_* (constitution, principle III).

## Damage is deterministic on purpose: variance at this scale adds frustration,
## not depth. Always at least 1 so a fight can never stall.
##
## Encima va la ventaja por tipo (GameConfig.combat_type_advantage): el dano neto
## se multiplica por la ventaja o la desventaja del emparejamiento y se redondea,
## sin bajar nunca de 1.
static func damage(attacker: CombatUnit, target: CombatUnit) -> int:
	var net: int = maxi(1, attacker.attack_power() - target.defense())
	var mult: float = type_multiplier(attacker.unit_id, target.unit_id)
	if is_equal_approx(mult, 1.0):
		return net
	return maxi(1, roundi(float(net) * mult))

## +1 si `attacker_id` pega con ventaja a `target_id`, -1 con desventaja, 0 si
## no hay nada entre ellos (o son del mismo tipo). La desventaja es la ventaja
## leida al reves: con el circulo basta escribir quien gana a quien.
static func type_matchup(attacker_id: String, target_id: String) -> int:
	if attacker_id == target_id:
		return 0
	var beats: Dictionary = GameConfig.combat_type_advantage.get("beats", {})
	if (beats.get(attacker_id, []) as Array).has(target_id):
		return 1
	if (beats.get(target_id, []) as Array).has(attacker_id):
		return -1
	return 0

## El multiplicador de dano del emparejamiento (1.0 si no hay ventaja).
static func type_multiplier(attacker_id: String, target_id: String) -> float:
	match type_matchup(attacker_id, target_id):
		1:
			return float(GameConfig.combat_type_advantage.get("advantage", 1.0))
		-1:
			return float(GameConfig.combat_type_advantage.get("disadvantage", 1.0))
	return 1.0

## Morale 0 -> low end, 50 -> 1.0, 100 -> high end of combat_morale_attack_range.
static func morale_attack_mod(morale: float) -> float:
	var range_cfg: Vector2 = GameConfig.combat_morale_attack_range
	var t: float = clampf(morale / 100.0, 0.0, 1.0)
	return lerpf(range_cfg.x, range_cfg.y, t)

## Symmetric around 50 morale: demoralised troops react late, inspired ones early.
static func morale_initiative_bonus(morale: float) -> int:
	var span: int = GameConfig.combat_morale_initiative_bonus
	var t: float = clampf(morale / 100.0, 0.0, 1.0)
	return roundi(lerpf(float(-span), float(span), t))

static func manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

## Artillery cannot fire at adjacent targets: that min_range is what makes
## positioning matter instead of everyone piling onto one tile.
static func in_attack_range(attacker: CombatUnit, target: CombatUnit) -> bool:
	var dist := manhattan(attacker.position, target.position)
	return dist >= attacker.min_range() and dist <= attacker.attack_range()

static func in_board(cell: Vector2i, board: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < board.x and cell.y < board.y

## Breadth-first flood fill over 4 directions. Occupied cells block movement and
## cannot be entered, so units cannot walk through each other.
static func reachable_cells(origin: Vector2i, move_range: int, board: Vector2i, blocked: Array) -> Array:
	var result: Array = []
	if move_range <= 0:
		return result
	var visited := {origin: 0}
	var queue: Array = [origin]
	const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		var dist: int = visited[current]
		if dist >= move_range:
			continue
		for dir in DIRS:
			var next: Vector2i = current + dir
			if visited.has(next) or not in_board(next, board) or blocked.has(next):
				continue
			visited[next] = dist + 1
			result.append(next)
			queue.append(next)
	return result

## Turn order: highest initiative first. Ties go to the player, then to the lower
## uid, so the order is stable and observable (FR-006).
static func build_turn_order(units: Array) -> Array:
	var alive: Array = []
	for unit in units:
		if unit.is_alive():
			alive.append(unit)
	alive.sort_custom(func(a: CombatUnit, b: CombatUnit) -> bool:
		if a.initiative() != b.initiative():
			return a.initiative() > b.initiative()
		if a.side != b.side:
			return a.side < b.side
		return a.uid < b.uid
	)
	var order: Array = []
	for unit in alive:
		order.append(unit.uid)
	return order

## Round limit reached: the side with more total HP wins. A tie is a player loss —
## the expedition punishes stalling rather than rewarding it (FR-015).
static func resolve_timeout(units: Array) -> int:
	var totals := {0: 0, 1: 0}
	for unit in units:
		if unit.is_alive():
			totals[unit.side] = totals[unit.side] + unit.hp
	return 0 if totals[0] > totals[1] else 1

## What a cleared encounter pays. Scales with the era exactly the way the enemy
## roster does, so the loot keeps pace with what you had to beat instead of
## turning into pocket change by era 3.
static func encounter_rewards(era: int) -> Dictionary:
	var mult: float = 1.0 + GameConfig.combat_enemy_scale_per_era * float(maxi(0, era - 1))
	var rewards: Dictionary = {}
	for res_name in GameConfig.combat_reward_base:
		rewards[res_name] = maxi(1, roundi(float(GameConfig.combat_reward_base[res_name]) * mult))
	return rewards

## The swing back home: a win lifts the town, and every unit that does not come
## back sinks it. A costly victory can still leave the base worse than it started,
## which is the whole point of tying the two halves together.
static func morale_delta(victory: bool, casualties: int) -> int:
	var delta: float = GameConfig.combat_morale_on_victory if victory else 0.0
	delta -= GameConfig.combat_morale_per_casualty * float(maxi(0, casualties))
	return roundi(delta)

static func living_units(units: Array, side: int) -> Array:
	var result: Array = []
	for unit in units:
		if unit.is_alive() and unit.side == side:
			result.append(unit)
	return result

static func occupied_cells(units: Array, ignore_uid: int = -1) -> Array:
	var cells: Array = []
	for unit in units:
		if unit.is_alive() and unit.uid != ignore_uid and unit.position.x >= 0:
			cells.append(unit.position)
	return cells

# ── Fuerza y probabilidades (doc 21 §3.4-3.5, 2026-10-14) ────────────

## Un numero comparable para "cuanto pega este bando": el poder de cada unidad
## viva (unit_types[...]["power"]) por la vida que le queda respecto a la de una
## unidad base de su tipo. La escala del enemigo multiplica la vida, asi que un
## enemigo mas duro cuenta mas; un herido cuenta menos. Es la misma medida que
## roster_power() de ExpeditionGenerator para una columna entera y sin heridas.
static func side_strength(units: Array, side: int) -> float:
	var total: float = 0.0
	for unit in units:
		if unit == null or not unit.is_alive() or unit.side != side:
			continue
		var base_hp: float = float(maxi(1, int(GameConfig.get_combat_stats(unit.unit_id).get("hp", 1))))
		total += float(unit.power()) * float(unit.hp) / base_hp
	return total

## La etiqueta de la seleccion de tropa: "favorable", "even" o "hard", segun la
## proporcion entre tu fuerza y la del enemigo.
static func odds_label(player_strength: float, enemy_strength: float) -> String:
	if enemy_strength <= 0.0:
		return "favorable"
	var ratio: float = player_strength / enemy_strength
	if ratio >= GameConfig.combat_odds_favorable:
		return "favorable"
	if ratio < GameConfig.combat_odds_hard:
		return "hard"
	return "even"

## "Resolver solo" solo se ofrece cuando tu fuerza dobla (o mas) la del enemigo.
static func can_auto_resolve(player_strength: float, enemy_strength: float) -> bool:
	if player_strength <= 0.0:
		return false
	return player_strength >= GameConfig.combat_auto_resolve_ratio * enemy_strength

## Lo que le queda al bando de la vida con la que empezo (0..1). `start_hp` es
## la suma de vida del bando al abrir el tablero.
static func hp_fraction(units: Array, side: int, start_hp: int) -> float:
	if start_hp <= 0:
		return 1.0
	var now := 0
	for unit in units:
		if unit.side == side and unit.is_alive():
			now += unit.hp
	return float(now) / float(start_hp)
