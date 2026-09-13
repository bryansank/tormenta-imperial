extends RefCounted
class_name CombatRules
## Pure combat maths. No nodes, no global state, no randomness: every function
## here is deterministic and unit-testable in headless mode.
##
## All tunable numbers come from GameConfig.combat_* (constitution, principle III).

## Damage is deterministic on purpose: variance at this scale adds frustration,
## not depth. Always at least 1 so a fight can never stall.
static func damage(attacker: CombatUnit, target: CombatUnit) -> int:
	return maxi(1, attacker.attack_power() - target.defense())

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
