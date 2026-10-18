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
## `cover` (Bastion, feat/edificios-defensa-vida): defensa de mas que da la
## casilla en la que esta `target` (Encounter.cover_at). 0 = sin cobertura, la
## formula de siempre.
static func damage(attacker: CombatUnit, target: CombatUnit, cover: int = 0) -> int:
	var net: int = maxi(1, attacker.attack_power() - target.defense() - maxi(0, cover))
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
##
## Aire y mar (docs/15 §11): ademas, el dominio del atacante tiene que poder
## pegar al del objetivo (combat_domain_targets), a como mucho el alcance que
## esa tabla deje. Entre tierra y tierra todo sigue igual que antes.
static func in_attack_range(attacker: CombatUnit, target: CombatUnit) -> bool:
	return can_hit_from(attacker, attacker.position, target)

## ¿Puede `attacker`, plantado en `from`, pegar a `target` donde esta ahora?
static func can_hit_from(attacker: CombatUnit, from: Vector2i, target: CombatUnit) -> bool:
	var reach: int = max_reach(attacker, target)
	if reach <= 0:
		return false
	var dist: int = strike_distance(attacker, from, target)
	return dist >= attacker.min_range() and dist <= reach

## Hasta donde llega `attacker` contra `target` por dominio: 0 si no puede
## pegarle nunca; si no, su alcance, recortado por combat_domain_targets y por
## la fila `targets` de la unidad.
static func max_reach(attacker: CombatUnit, target: CombatUnit) -> int:
	var limit: int = target_limit(attacker.unit_id, attacker.domain(), target.domain())
	if limit == 0:
		return 0
	var reach: int = attacker.attack_range()
	if limit > 0:
		reach = mini(reach, limit)
	# Si el tope queda por debajo de su alcance minimo, no le llega nunca (la
	# artilleria contra un avion: tope 1, minimo 2).
	return reach if reach >= attacker.min_range() else 0

## El tope de alcance de un tipo contra un dominio: -1 = su alcance normal,
## 0 = no puede, N = como mucho N. La fila `targets` de la unidad manda sobre la
## tabla del dominio; un dominio que no sale en la tabla no se puede atacar.
static func target_limit(unit_id: String, attacker_domain: String, target_domain: String) -> int:
	var own: Dictionary = GameConfig.get_combat_stats(unit_id).get("targets", {})
	if own.has(target_domain):
		return int(own[target_domain])
	var row: Dictionary = GameConfig.combat_domain_targets.get(attacker_domain, {})
	if row.is_empty():
		# Dominio sin fila (no deberia pasar): como tierra contra tierra.
		return -1 if target_domain == attacker_domain else 0
	return int(row.get(target_domain, 0))

## La distancia de un golpe. En la misma capa, Manhattan; entre capas (un avion
## y lo que hay debajo) nunca menos de 1: el que vuela justo encima de un
## soldado esta "a una casilla" de el, y se pueden pegar los dos.
static func strike_distance(attacker: CombatUnit, from: Vector2i, target: CombatUnit) -> int:
	var dist: int = manhattan(from, target.position)
	if attacker.layer() != target.layer():
		return maxi(1, dist)
	return dist

## La capa de un dominio: "air" o "surface" (tierra y mar comparten capa).
static func layer_of(domain: String) -> String:
	return "air" if domain == "air" else "surface"

static func in_board(cell: Vector2i, board: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < board.x and cell.y < board.y

# ── Terreno (aire y mar, docs/15 §11) ────────────────────────────────

const TERRAIN_LAND := "land"
const TERRAIN_WATER := "water"
const TERRAIN_SHORE := "shore"

## El terreno de una casilla: lo que diga `terrain`, tierra si no dice nada.
static func terrain_at(terrain: Dictionary, cell: Vector2i) -> String:
	return String(terrain.get(cell, TERRAIN_LAND))

## ¿Puede plantarse (y pasar) una unidad de `domain` en ese terreno?
static func can_stand(domain: String, terrain_type: String) -> bool:
	var allowed: Array = GameConfig.combat_domain_moves.get(domain, [TERRAIN_LAND])
	return allowed.has(terrain_type)

## ¿Hay agua en el tablero?
static func has_water(terrain: Dictionary) -> bool:
	for cell in terrain:
		if String(terrain[cell]) == TERRAIN_WATER:
			return true
	return false

## El tablero de costa: `combat_coast_water_columns` columnas de agua pegadas a
## un lado y una columna de orilla junto a ellas; el resto, tierra. El lado
## (izquierda o derecha) sale de la semilla. Puro y determinista: la misma
## semilla da siempre la misma costa, y el guardado solo lleva la semilla (el
## nodo la trae en `terrain_seed`). Devuelve TODAS las casillas.
static func coastal_terrain(board: Vector2i, seed_value: int) -> Dictionary:
	var terrain: Dictionary = {}
	var water: int = clampi(GameConfig.combat_coast_water_columns, 1, maxi(1, board.x - 3))
	var on_left: bool = posmod(seed_value, 2) == 0
	for y in range(board.y):
		for x in range(board.x):
			var from_edge: int = x if on_left else board.x - 1 - x
			var kind: String = TERRAIN_LAND
			if from_edge < water:
				kind = TERRAIN_WATER
			elif from_edge == water:
				kind = TERRAIN_SHORE
			terrain[Vector2i(x, y)] = kind
	return terrain

## Mar abierto (Campana de Mar, feat/tres-campanas): todo el tablero es agua
## salvo `combat_sea_islets` islotes de una casilla (tierra con su orilla no: un
## islote es roca, los barcos lo rodean). Los islotes caen solo en las filas de en
## medio (nunca en las dos de despliegue de cada bando) y nunca dos pegados. Puro
## y determinista: la misma semilla, el mismo mar. Devuelve TODAS las casillas.
static func open_sea_terrain(board: Vector2i, seed_value: int, islets: int = 3) -> Dictionary:
	var terrain: Dictionary = {}
	for y in range(board.y):
		for x in range(board.x):
			terrain[Vector2i(x, y)] = TERRAIN_WATER
	if board.y < 6 or islets <= 0:
		return terrain
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var placed: Array = []
	var tries := 0
	while placed.size() < islets and tries < 40:
		tries += 1
		var cell := Vector2i(rng.randi_range(0, board.x - 1), rng.randi_range(2, board.y - 3))
		var clear := true
		for other in placed:
			if manhattan(cell, other) < 3:
				clear = false
				break
		if not clear:
			continue
		placed.append(cell)
		terrain[cell] = TERRAIN_LAND
	return terrain

## Breadth-first flood fill over 4 directions. Occupied cells block movement and
## cannot be entered, so units cannot walk through each other.
##
## Aire y mar: con `terrain`, solo se entra (y se pasa) por las casillas que el
## dominio puede pisar (combat_domain_moves). Sin terreno todo es tierra, que es
## exactamente lo de antes para las unidades de tierra. `blocked` lo da quien
## llama ya filtrado por capa (Encounter.valid_moves).
static func reachable_cells(origin: Vector2i, move_range: int, board: Vector2i, blocked: Array, terrain: Dictionary = {}, domain: String = TERRAIN_LAND) -> Array:
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
			if not can_stand(domain, terrain_at(terrain, next)):
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
## `per_casualty` < 0 = el de siempre (combat_morale_per_casualty); la
## Enfermeria pasa el suyo (infirmary_morale_per_casualty).
static func morale_delta(victory: bool, casualties: int, per_casualty: float = -1.0) -> int:
	var delta: float = GameConfig.combat_morale_on_victory if victory else 0.0
	var each: float = GameConfig.combat_morale_per_casualty if per_casualty < 0.0 else per_casualty
	delta -= each * float(maxi(0, casualties))
	return roundi(delta)

## Enfermeria (feat/edificios-militares): cuantos de `fallen` caidos vuelven a
## casa tras un combate ganado: uno de cada `every`, por abajo.
static func infirmary_returns(fallen: int, every: int) -> int:
	if every <= 0 or fallen <= 0:
		return 0
	return fallen / every

## Los `count` caidos que vuelven: los de mas Poder primero (a igual Poder, el
## uid menor), para que lo que se salva sea lo que mas cuesta reponer.
static func pick_recovered(fallen: Array, count: int) -> Array:
	if count <= 0 or fallen.is_empty():
		return []
	var sorted: Array = fallen.duplicate()
	sorted.sort_custom(func(a, b):
		if a.power() != b.power():
			return a.power() > b.power()
		return a.uid < b.uid)
	return sorted.slice(0, mini(count, sorted.size()))

static func living_units(units: Array, side: int) -> Array:
	var result: Array = []
	for unit in units:
		if unit.is_alive() and unit.side == side:
			result.append(unit)
	return result

## Las casillas ocupadas. Con `layer` ("air" / "surface"), solo las de esa capa:
## un avion no le cierra el paso a un soldado, ni al reves. Vacio = todas, lo de
## siempre.
static func occupied_cells(units: Array, ignore_uid: int = -1, layer: String = "") -> Array:
	var cells: Array = []
	for unit in units:
		if unit.is_alive() and unit.uid != ignore_uid and unit.position.x >= 0:
			if layer != "" and unit.layer() != layer:
				continue
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

# ── Vistas previas (docs/15 §3 "Ensenar el combate", 2026-10-14) ─────
# Lo que el tablero ensena ANTES de actuar. Puras como todo lo de arriba: no
# tocan las unidades, no tiran dados (no los hay) y no dependen de la vista.

## Lo que haria `attacker` a `target` si le atacara ahora, sin hacerlo:
## {damage, hp, max_hp, hp_after, kills, matchup (+1/0/-1), mult}. Usa damage(),
## asi que la ventaja por tipo, la defensa doblada y la moral ya van dentro.
static func preview_damage(attacker: CombatUnit, target: CombatUnit, cover: int = 0) -> Dictionary:
	var dealt: int = damage(attacker, target, cover)
	var hp_after: int = maxi(0, target.hp - dealt)
	return {
		"damage": dealt,
		"hp": target.hp,
		"max_hp": target.max_hp,
		"hp_after": hp_after,
		"kills": hp_after == 0,
		"matchup": type_matchup(attacker.unit_id, target.unit_id),
		"mult": type_multiplier(attacker.unit_id, target.unit_id),
	}

## Las casillas a las que `unit` puede disparar desde `from`: distancia entre su
## alcance minimo y el maximo, dentro del tablero.
static func fire_cells_from(unit: CombatUnit, from: Vector2i, board: Vector2i) -> Array:
	var out: Array = []
	var lo: int = unit.min_range()
	var hi: int = unit.attack_range()
	for dx in range(-hi, hi + 1):
		var rest: int = hi - absi(dx)
		for dy in range(-rest, rest + 1):
			var d: int = absi(dx) + absi(dy)
			if d < lo or d == 0:
				continue
			var cell := from + Vector2i(dx, dy)
			if in_board(cell, board):
				out.append(cell)
	return out

## Las casillas demasiado cerca para que `unit` dispare (dentro de su alcance
## minimo, sin contar la suya). Vacio para quien pega cuerpo a cuerpo: es la ✕
## de la artilleria.
static func min_range_cells(unit: CombatUnit, board: Vector2i) -> Array:
	var out: Array = []
	var lo: int = unit.min_range()
	if lo <= 1 or unit.position.x < 0:
		return out
	for dx in range(-(lo - 1), lo):
		var rest: int = (lo - 1) - absi(dx)
		for dy in range(-rest, rest + 1):
			if dx == 0 and dy == 0:
				continue
			var cell := unit.position + Vector2i(dx, dy)
			if in_board(cell, board):
				out.append(cell)
	return out

## El peligro: toda casilla a la que alguna unidad viva de `side` puede disparar
## en su proximo turno, moviendose antes con su movimiento entero. Una vez por
## turno, no cada fotograma: con 6 unidades y 64 casillas es poca cosa.
## Aire y mar: con `terrain`, cada unidad solo se planta donde su dominio puede,
## y solo la bloquea su capa (lo mismo que Encounter.valid_moves).
static func threat_cells(units: Array, side: int, board: Vector2i, terrain: Dictionary = {}) -> Array:
	var seen := {}
	for unit in units:
		if not unit.is_alive() or unit.side != side or unit.position.x < 0:
			continue
		var stands: Array = [unit.position]
		stands.append_array(reachable_cells(unit.position, unit.move_range(), board,
			occupied_cells(units, unit.uid, unit.layer()), terrain, unit.domain()))
		for stand in stands:
			for cell in fire_cells_from(unit, stand, board):
				seen[cell] = true
	return seen.keys()

# ── Cobertura del Bastion (feat/edificios-defensa-vida, doc 21 §6.3 n.º 18) ──

## Las casillas de cobertura de un tablero de defensa: `count` casillas de
## tierra en la fila `row` (la de atras del jugador), del centro hacia fuera
## (centro, izquierda del centro, derecha...). Solo tierra: en el agua no se
## levanta un parapeto. Puro y determinista; [] si count <= 0.
static func cover_cells(board: Vector2i, terrain: Dictionary, count: int, row: int) -> Array:
	var out: Array = []
	if count <= 0 or row < 0 or row >= board.y:
		return out
	var mid: int = floori(board.x * 0.5)
	var order: Array = [mid]
	for k in range(1, board.x):
		order.append(mid - k)
		order.append(mid + k)
	for x in order:
		if out.size() >= count:
			break
		var cell := Vector2i(int(x), row)
		if not in_board(cell, board):
			continue
		if terrain_at(terrain, cell) != TERRAIN_LAND:
			continue
		out.append(cell)
	return out
