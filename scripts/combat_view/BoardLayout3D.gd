extends RefCounted
## Geometria del tablero 3D (docs/15 §3, "El tablero 3D"): de casilla a mundo y
## vuelta, la ruta casilla a casilla de un movimiento y donde se coloca una
## unidad segun su dominio. Puro y estatico: lo fijan las pruebas sin escena.
##
## Esto es VISTA. Las reglas (que casillas se pueden pisar, a cuanto se dispara)
## siguen en scripts/combat/: la ruta de aqui solo dibuja un movimiento que el
## modelo ya hizo, por eso no mira alcances ni costes, solo casillas libres.

## Lado de una casilla en metros (el mismo que el mapa de la base).
const CELL := 2.0

## Altura de la peana segun el dominio de la unidad (CombatUnit.domain()). Hoy
## solo hay tierra. Mar: la peana flota en la lamina de agua (un poco por debajo
## del suelo de la casilla, que tendra su "agua"); aire: vuela a esta altura con
## una sombra en el suelo. El espacio, si llega, iria por encima del aire.
const DOMAIN_HEIGHT := {"land": 0.0, "sea": -0.12, "air": 1.7, "space": 2.6}
## Los dominios que se mecen en reposo (el barco con las olas, el avion en el aire).
const DOMAIN_BOBS := ["sea", "air", "space"]

static func board_extent(board: Vector2i) -> Vector2:
	return Vector2(board) * CELL

## El centro de una casilla, con el tablero centrado en el origen. La fila 0 (la
## del enemigo) queda al fondo (-Z) y la ultima, la del jugador, delante (+Z).
static func cell_to_world(cell: Vector2i, board: Vector2i) -> Vector3:
	return Vector3(
		(float(cell.x) - float(board.x - 1) * 0.5) * CELL,
		0.0,
		(float(cell.y) - float(board.y - 1) * 0.5) * CELL)

## La casilla que hay bajo un punto del suelo, o (-1, -1) fuera del tablero.
static func world_to_cell(p: Vector3, board: Vector2i) -> Vector2i:
	var cx := int(floor(p.x / CELL + float(board.x) * 0.5))
	var cy := int(floor(p.z / CELL + float(board.y) * 0.5))
	if cx < 0 or cy < 0 or cx >= board.x or cy >= board.y:
		return Vector2i(-1, -1)
	return Vector2i(cx, cy)

## Desorden del frente (docs/15 §3, "Las dos vistas"): cuanto se aparta una pieza
## del centro de su casilla, como mucho, en metros. Menos de media casilla, asi
## que tocar su sitio sigue cayendo en la misma casilla.
const SPOT_JITTER := 0.38

## El "sitio libre" de una casilla en la vista frontal: el centro corrido un poco,
## siempre igual para la misma casilla y semilla (las piezas no tiemblan entre
## turnos y el sitio al que se mueve es el que se ilumino). Puro: un hash.
static func spot_offset(cell: Vector2i, seed_value: int) -> Vector3:
	var h: int = hash(Vector3i(cell.x, cell.y, seed_value))
	var a := float(h & 0xffff) / 65535.0
	var b := float((h >> 16) & 0xffff) / 65535.0
	return Vector3((a - 0.5) * 2.0 * SPOT_JITTER, 0.0, (b - 0.5) * 2.0 * SPOT_JITTER)

static func domain_height(domain: String) -> float:
	return float(DOMAIN_HEIGHT.get(domain, 0.0))

static func domain_bobs(domain: String) -> bool:
	return DOMAIN_BOBS.has(domain)

## La ruta mas corta de `from` a `to` en pasos de una casilla (4 vecinos) sin
## pisar `blocked` (casilla -> true). Incluye las dos puntas. Si no hay ninguna
## (el modelo movio por donde la vista ya no ve hueco), devuelve el salto
## directo [from, to]: la unidad llega igual, solo que sin rodeo.
static func path(from: Vector2i, to: Vector2i, blocked: Dictionary, board: Vector2i) -> Array:
	if from == to:
		return [from]
	var prev := {from: from}
	var frontier: Array = [from]
	var dirs := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	while not frontier.is_empty():
		var cur: Vector2i = frontier.pop_front()
		if cur == to:
			break
		for d in dirs:
			var nxt: Vector2i = cur + d
			if nxt.x < 0 or nxt.y < 0 or nxt.x >= board.x or nxt.y >= board.y:
				continue
			if prev.has(nxt):
				continue
			if nxt != to and blocked.has(nxt):
				continue
			prev[nxt] = cur
			frontier.append(nxt)
	if not prev.has(to):
		return [from, to]
	var out: Array = [to]
	var c: Vector2i = to
	while c != from:
		c = prev[c]
		out.push_front(c)
	return out

## Giro en Y para que una pieza con el frente en +Z mire de `a` hacia `b`.
static func yaw_towards(a: Vector3, b: Vector3) -> float:
	var d := b - a
	if Vector2(d.x, d.z).length() < 0.001:
		return 0.0
	return atan2(d.x, d.z)

## Cuantas casillas separan dos puntos (Manhattan), para elegir la animacion.
static func cell_distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

# ── El terreno del tablero (mar y aire, 1.1) ─────────────────────────
#
# Las reglas (rama de reglas) dan `Encounter.terrain`: casilla -> "land",
# "water" o "shore"; vacio = todo tierra. La vista solo lo PINTA: que casillas
# se pueden pisar lo sigue diciendo el modelo (valid_moves). Se lee de forma
# defensiva (`get`), asi esta vista funciona igual con un Encounter sin terreno.

const TERRAIN_LAND := "land"
const TERRAIN_WATER := "water"
const TERRAIN_SHORE := "shore"
## La lamina de agua de una casilla de mar queda por debajo del suelo de las
## losetas (y = 0): los barcos flotan en ella (DOMAIN_HEIGHT["sea"]).
const WATER_TOP := -0.07

## El terreno de un encuentro (copia), o {} si no tiene.
static func terrain_of(encounter) -> Dictionary:
	if encounter == null:
		return {}
	var t = encounter.get("terrain")
	return (t as Dictionary).duplicate() if t is Dictionary else {}

static func cell_kind(terrain: Dictionary, cell: Vector2i) -> String:
	return String(terrain.get(cell, TERRAIN_LAND))

static func is_water(terrain: Dictionary, cell: Vector2i) -> bool:
	return cell_kind(terrain, cell) == TERRAIN_WATER

static func has_water(terrain: Dictionary) -> bool:
	for c in terrain:
		if String(terrain[c]) == TERRAIN_WATER:
			return true
	return false

## Altura del suelo de una casilla en la vista: la lamina de agua en el mar,
## el suelo de siempre en tierra y en la orilla.
static func ground_y(terrain: Dictionary, cell: Vector2i) -> float:
	return WATER_TOP if is_water(terrain, cell) else 0.0

## Lo que una pieza no puede cruzar al DIBUJAR su ruta: un barco no pasa por
## tierra (solo agua y orilla). Las de tierra y aire no tienen nada que evitar
## aqui (el aire vuela derecho, ver UnitToy3D.fly_along). Las reglas ya
## decidieron a donde llega; esto solo hace que el dibujo no corte por la playa.
static func route_blocked(terrain: Dictionary, domain: String, board: Vector2i) -> Dictionary:
	var out := {}
	if domain != "sea" or not has_water(terrain):
		return out
	for y in board.y:
		for x in board.x:
			var c := Vector2i(x, y)
			if cell_kind(terrain, c) == TERRAIN_LAND:
				out[c] = true
	return out
