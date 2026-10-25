extends Node
## Generates random resource deposits on the map.
## Deposits occupy multiple grid cells with random sizes.
## Each deposit has limited uses before depletion.

const DEPOSIT_TYPES := {
	"gold_vein": { "display_name": "DEP_GOLD_VEIN", "color": Color(0.9, 0.75, 0.1, 1), "height": 0.6 },
	"iron_deposit": { "display_name": "DEP_IRON", "color": Color(0.6, 0.6, 0.65, 1), "height": 0.5 },
	"oil_well": { "display_name": "DEP_OIL", "color": Color(0.15, 0.15, 0.18, 1), "height": 0.15 },
	"forest": { "display_name": "DEP_FOREST", "color": Color(0.2, 0.5, 0.15, 1), "height": 0.8 },
	# Banco de peces (feat/muelle-pesca): en el agua, pegado a la costa. Lo
	# explota el Muelle de pesca (GameConfig.building_deposit_rules); no se agota.
	"fish_shoal": { "display_name": "DEP_FISH_SHOAL", "color": Color(0.25, 0.5, 0.7, 1), "height": 0.1 },
}

const DEPOSIT_IDS := ["gold_vein", "iron_deposit", "oil_well", "forest"]

## La maqueta de cada yacimiento en 3D (una malla, color por vertice).
const DepositMesh := preload("res://scripts/map/DepositMesh.gd")

var _deposits_container: Node
var _deposit_cells: Array = []  # [{ "id": String, "cell_x": int, "cell_y": int, "size_x": int, "size_y": int, "node": Node }]

func _ready() -> void:
	_deposits_container = _make_container()
	_deposits_container.name = "Deposits"
	add_child(_deposits_container)
	EventBus.mining_completed.connect(_on_mining_completed)
	# Las marcas de las amenazas de costa (feat/amenazas-costa): solo vista,
	# las lee de ThreatManager.
	var marks := _make_threat_marks()
	if marks != null:
		marks.name = "ThreatMarks"
		add_child(marks)
	GameManager.register_map_generator(self)

func _roll_deposit_size(deposit_id: String) -> Vector2i:
	var sizes: Dictionary = GameConfig.deposit_sizes.get(deposit_id, {"min_w": 2, "max_w": 3, "min_h": 2, "max_h": 3})
	var w: int = randi_range(sizes["min_w"], sizes["max_w"])
	var h: int = randi_range(sizes["min_h"], sizes["max_h"])
	return Vector2i(w, h)

## Mapa nuevo: para CADA tipo se sortea cuantos yacimientos trae, entre
## `GameConfig.deposit_per_type_min` y `deposit_per_type_max`, y se reparten con
## tamano y sitio al azar (RNG global: seed() fija el mapa entero).
##
## Cada yacimiento tiene que ser trabajable: su extractor (2x2) cabe al lado (o
## encima, la Refineria sobre su pozo) y desde ese hueco hay camino de celdas
## libres hasta la acera del Nucleo, por donde tender la carretera. Uno que no lo
## es se retira y se sortea otro del mismo tipo. Como un yacimiento puesto
## despues puede encajonar a uno anterior, al final se repasan todos juntos.
##
## Ninguno cae en la franja de costa (`map_shore_band`): queda libre para los
## futuros recursos del mar y la orilla (ver shore_cells()).
func generate_new_map() -> Array:
	var lo: int = mini(GameConfig.deposit_per_type_min, GameConfig.deposit_per_type_max)
	var hi: int = maxi(GameConfig.deposit_per_type_min, GameConfig.deposit_per_type_max)
	var wanted := {}
	for deposit_id in DEPOSIT_IDS:
		wanted[deposit_id] = randi_range(lo, hi)
		_fill_type(deposit_id, int(wanted[deposit_id]))
	# Repaso: fuera los que quedaron sin camino a la red, y se reponen.
	for pass_i in range(4):
		var reach := _road_reach()
		var removed := false
		for entry in _deposit_cells.duplicate():
			if not _deposit_is_workable(entry, reach):
				remove_deposit(entry["node"])
				removed = true
		if not removed:
			break
		for deposit_id in DEPOSIT_IDS:
			_fill_type(deposit_id, int(wanted[deposit_id]))
	_generate_shore_deposits()
	return get_all_deposits()

## Sortea yacimientos de `deposit_id` hasta tener `wanted` que dejen hueco a su
## extractor. El camino hasta la red lo mira el repaso final (es caro de mirar
## en cada intento y casi nunca falla: la isla esta casi vacia).
func _fill_type(deposit_id: String, wanted: int) -> void:
	var center := core_origin()
	var tries := 0
	while _count_type(deposit_id) < wanted and tries < wanted * 25:
		tries += 1
		var dep_size := _roll_deposit_size(deposit_id)
		var cell := _random_cell_for_deposit(center, dep_size)
		if cell == Vector2i(-1, -1):
			continue
		var node := spawn_deposit(deposit_id, cell, -1, dep_size)
		if node != null and _extractor_spots(_entry_of(node), 1).is_empty():
			remove_deposit(node)

func _count_type(deposit_id: String) -> int:
	var n := 0
	for entry in _deposit_cells:
		if entry["id"] == deposit_id and is_instance_valid(entry["node"]):
			n += 1
	return n

func _entry_of(node: Node) -> Dictionary:
	for entry in _deposit_cells:
		if entry["node"] == node:
			return entry
	return {}

# ── Nucleo, costa y mar ───────────────────────────────────────────────

## Celda de origen del Nucleo: la misma cuenta que GameManager._new_game().
func core_origin() -> Vector2i:
	return Vector2i(GridManager.grid_width / 2, GridManager.grid_height / 2)

## El Nucleo mas su acera (la corona de carreteras de pave_core_ring()).
func core_ring_rect() -> Rect2i:
	var size := Vector2i(3, 3)
	var data: Resource = _building_data("nucleo")
	if data != null:
		size = data.grid_size
	return Rect2i(core_origin(), size).grow(1)

## ¿Es `cell` de la franja de costa? La franja son las celdas de tierra a
## `map_shore_band` celdas (o menos, contando diagonales) del agua: de la que
## entra en la rejilla (isla irregular) o de la de fuera (la isla cuadrada de
## antes, donde la franja es el anillo exterior). Tierra construible, pero sin
## yacimientos de tierra: es el gancho de los futuros recursos del mar.
static func is_shore_cell(cell: Vector2i) -> bool:
	if not GridManager.is_land_cell(cell):
		return false
	var band: int = GameConfig.map_shore_band
	for dy in range(-band, band + 1):
		for dx in range(-band, band + 1):
			if not GridManager.is_land_cell(cell + Vector2i(dx, dy)):
				return true
	return false

## Todas las celdas de la franja de costa.
static func shore_cells() -> Array:
	var out: Array = []
	for y in range(GridManager.grid_height):
		for x in range(GridManager.grid_width):
			var c := Vector2i(x, y)
			if is_shore_cell(c):
				out.append(c)
	return out

## ¿Es mar? El agua de dentro de la rejilla (isla irregular) y todo lo de fuera.
## Ahi no se construye; un recurso marino se trabajaria desde una celda de costa
## pegada a el.
static func is_sea_cell(cell: Vector2i) -> bool:
	return not GridManager.is_land_cell(cell)

## Yacimientos de mar (feat/muelle-pesca): el banco de peces. Viven en celdas de
## AGUA de la rejilla (GridManager.place_sea_obstacle), MAR ADENTRO desde
## fix/peces-en-el-mar (2026-10-19): entre `min_gap` y `max_gap` casillas de agua
## los separan de la tierra (GameConfig.sea_deposit_rolls), nunca pegados a la
## arena. Su extractor, el Muelle de pesca, se planta en la costa (regla "shore")
## y llega al banco a distancia (GameConfig.fishing_dock_reach); un banco sirve a
## `fishing_dock_per_shoal` muelles (PlacementRules.deposit_with_room). Ninguno
## se agota (GameConfig.endless_deposits). El guardado los lleva como a los
## demas: get_all_deposits() no mira el tipo.
## Otro recurso del mar (sal, petroleo en alta mar...): su tipo en DEPOSIT_TYPES,
## su id aqui, la regla de su extractor y sus cifras en GameConfig.sea_deposit_rolls.
const SHORE_DEPOSIT_IDS: Array = ["fish_shoal"]

## Las ocho celdas vecinas (diagonales incluidas), como la regla de costa.
const _AROUND := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]

## ¿Vive en el agua este yacimiento?
static func is_sea_deposit(deposit_id: String) -> bool:
	return deposit_id in SHORE_DEPOSIT_IDS

func _generate_shore_deposits() -> void:
	for deposit_id in SHORE_DEPOSIT_IDS:
		_fill_sea_type(String(deposit_id))

## Una partida de antes del muelle (la 1.0) no trae bancos de peces: al cargarla
## se sortean (con la semilla de su isla: siempre los mismos). Solo si no hay
## ninguno de ese tipo: un banco nunca se agota ni se consume, asi que "cero"
## solo puede ser una partida vieja, o una isla sin agua dentro de la rejilla (la
## cuadrada de antes de 2026-10-12), donde no cabe ninguno y esto no hace nada.
##
## Una partida de antes de fix/peces-en-el-mar trae los bancos pegados a la
## orilla: los que ningun muelle usa se recolocan mar adentro (se quitan y se
## vuelve a sortear hasta el numero de la isla); los que si tienen muelle se
## respetan tal cual, para no dejarlo sin peces. Se llama despues de poner los
## edificios guardados (GameManager), asi que los muelles ya estan en la rejilla.
func ensure_shore_deposits() -> void:
	for deposit_id in SHORE_DEPOSIT_IDS:
		var id := String(deposit_id)
		var moved := _drop_unused_coast_hugging(id)
		if moved or _count_type(id) == 0:
			_fill_sea_type(id)

## ¿Esta este yacimiento de mar a la distancia de la orilla que pide su tirada?
func _at_sea_distance(deposit_id: String, origin: Vector2i, size: Vector2i) -> bool:
	var roll: Dictionary = GameConfig.sea_deposit_rolls.get(deposit_id, {})
	return not _has_land_within(origin, size, int(roll.get("min_gap", 0)) - 1) \
		and _has_land_within(origin, size, int(roll.get("max_gap", 0)))

## ¿Hay alguna celda de tierra con `gap` casillas o menos de agua entre ella y
## el rectangulo? gap 0 = pegada a el (diagonal incluida); gap < 0 = nunca.
static func _has_land_within(origin: Vector2i, size: Vector2i, gap: int) -> bool:
	if gap < 0:
		return false
	var r := gap + 1
	for y in range(origin.y - r, origin.y + size.y + r):
		for x in range(origin.x - r, origin.x + size.x + r):
			if GridManager.is_land_cell(Vector2i(x, y)):
				return true
	return false

## Quita los bancos de `deposit_id` que estan mas cerca de la tierra de lo que
## pide su tirada (los de antes de fix/peces-en-el-mar) y que ningun extractor
## alcanza. true si quito alguno.
func _drop_unused_coast_hugging(deposit_id: String) -> bool:
	var roll: Dictionary = GameConfig.sea_deposit_rolls.get(deposit_id, {})
	var min_gap := int(roll.get("min_gap", 0))
	if min_gap <= 0:
		return false
	var drop: Array = []
	for entry in _deposit_cells:
		if String(entry["id"]) != deposit_id or not is_instance_valid(entry["node"]):
			continue
		var o := Vector2i(entry["cell_x"], entry["cell_y"])
		var sz := Vector2i(entry.get("size_x", 2), entry.get("size_y", 2))
		if not _has_land_within(o, sz, min_gap - 1):
			continue
		if not _used_by_an_extractor(deposit_id, o, sz):
			drop.append(entry["node"])
	for node in drop:
		remove_deposit(node)
	return not drop.is_empty()

## ¿Lo alcanza algun edificio cuya regla pide este tipo de yacimiento?
func _used_by_an_extractor(deposit_id: String, origin: Vector2i, size: Vector2i) -> bool:
	for info in GridManager.buildings_view():
		var data: Resource = info.get("data")
		if data == null:
			continue
		var rule: Dictionary = GameConfig.get_deposit_rule(String(data.id))
		if rule.is_empty() or String(rule["deposit"]) != deposit_id:
			continue
		if deposit_within_reach(origin, size, info["cells"], int(rule["reach"])):
			return true
	return false

## Sortea los yacimientos de mar de `deposit_id`. Con su propio azar (semilla de
## la isla y del tipo), no con el global: el resto del mapa sale igual que antes
## de haberlos, y cargar una partida vieja da siempre los mismos bancos. Se mira
## una vez por partida nueva (o por carga vieja), nunca por fotograma.
func _fill_sea_type(deposit_id: String) -> void:
	var roll: Dictionary = GameConfig.sea_deposit_rolls.get(deposit_id, {})
	if roll.is_empty():
		return
	var candidates: Array = _sea_spots(deposit_id)
	if candidates.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([deposit_id, GridManager.island_seed, GridManager.grid_width, GridManager.grid_height])
	var lo: int = mini(int(roll["min"]), int(roll["max"]))
	var hi: int = maxi(int(roll["min"]), int(roll["max"]))
	var wanted: int = rng.randi_range(lo, hi)
	var spacing: int = int(roll.get("spacing", 6))
	# Barajado con el azar propio (shuffle() usaria el global).
	for i in range(candidates.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = t
	var reach := _road_reach()
	var taken: Array = []
	for entry in _deposit_cells:
		if String(entry["id"]) == deposit_id:
			taken.append(Rect2i(Vector2i(entry["cell_x"], entry["cell_y"]), Vector2i(entry.get("size_x", 2), entry.get("size_y", 2))))
	for cand in candidates:
		if _count_type(deposit_id) >= wanted:
			break
		var origin: Vector2i = cand
		# Algunos salen de 3 de largo, si el agua da para ello.
		var size := Vector2i(2, 2)
		var long_size := Vector2i(3, 2) if rng.randf() < 0.5 else Vector2i(2, 3)
		if rng.randf() < float(roll.get("long_chance", 0.0)) and _is_sea_spot(deposit_id, origin, long_size):
			size = long_size
		var rect := Rect2i(origin, size)
		var crowded := false
		for other in taken:
			if (other as Rect2i).grow(spacing).intersects(rect):
				crowded = true
				break
		if crowded:
			continue
		var node := spawn_deposit(deposit_id, origin, -1, size)
		if node == null:
			continue
		# Un banco sin hueco en la costa para su muelle, o sin camino a la red, no vale.
		if not _deposit_is_workable(_entry_of(node), reach):
			remove_deposit(node)
			continue
		taken.append(rect)

## Origenes 2x2 de agua libre a la distancia de la orilla que pide la tirada de
## `deposit_id` (mar adentro), lejos del Nucleo. En el orden de la rejilla.
func _sea_spots(deposit_id: String) -> Array:
	var out: Array = []
	var keep_out: Rect2i = core_ring_rect().grow(GameConfig.deposit_core_gap)
	for y in range(GridManager.grid_height - 1):
		for x in range(GridManager.grid_width - 1):
			var o := Vector2i(x, y)
			if keep_out.intersects(Rect2i(o, Vector2i(2, 2))):
				continue
			if _is_sea_spot(deposit_id, o, Vector2i(2, 2)):
				out.append(o)
	return out

## ¿Cabe un yacimiento de mar de `size` en `origin`? Todo agua de la rejilla,
## sin nada encima, y mar adentro: al menos `min_gap` casillas de agua hasta la
## tierra (no toca la arena) y como mucho `max_gap` (si no, ningun muelle llega).
func _is_sea_spot(deposit_id: String, origin: Vector2i, size: Vector2i) -> bool:
	for c in GridManager.cells_for(origin, size):
		if not GridManager.is_water_cell(c) or GridManager.get_building_at(c) != null:
			return false
	return _at_sea_distance(deposit_id, origin, size)

## ¿Toca el agua alguna de estas celdas (diagonal incluida)? La costa de
## PlacementRules.is_coast_cell, sin cargar PlacementRules.
static func touches_water(cells: Array) -> bool:
	for c in cells:
		for d in _AROUND:
			if not GridManager.is_land_cell(c + d):
				return true
	return false

# ── Yacimiento trabajable ─────────────────────────────────────────────

var _data_cache := {}

func _building_data(building_id: String) -> Resource:
	if not _data_cache.has(building_id):
		_data_cache[building_id] = load("res://data/buildings/%s.tres" % building_id)
	return _data_cache[building_id]

## Huecos libres para el extractor de este yacimiento (hasta `limit`). Un tipo
## sin extractor (ninguno hoy) siempre vale. Con alcance 0 (la Refineria) el
## hueco va encima del yacimiento, que se ignora al mirar si cabe.
func _extractor_spots(entry: Dictionary, limit: int = 0) -> Array:
	if entry.is_empty():
		return []
	var deposit_id: String = entry["id"]
	for building_id in GameConfig.building_deposit_rules:
		var rule: Dictionary = GameConfig.building_deposit_rules[building_id]
		if String(rule["deposit"]) != deposit_id:
			continue
		var data: Resource = _building_data(building_id)
		var footprint: Vector2i = data.grid_size if data != null else Vector2i(2, 2)
		return _spots_for(entry, footprint, int(rule["reach"]), limit, bool(rule.get("shore", false)))
	return [{"origin": Vector2i(entry["cell_x"], entry["cell_y"]), "size": Vector2i.ONE}]

func _spots_for(entry: Dictionary, footprint: Vector2i, reach: int, limit: int, shore: bool = false) -> Array:
	var spots: Array = []
	var dep_origin := Vector2i(entry["cell_x"], entry["cell_y"])
	var dep_size := Vector2i(entry.get("size_x", 2), entry.get("size_y", 2))
	var ignore: Node = entry["node"] if reach == 0 else null
	var orientations: Array = [footprint]
	if footprint.x != footprint.y:
		orientations.append(Vector2i(footprint.y, footprint.x))
	for size in orientations:
		var s: Vector2i = size
		for ox in range(dep_origin.x - s.x - reach + 1, dep_origin.x + dep_size.x + reach):
			for oy in range(dep_origin.y - s.y - reach + 1, dep_origin.y + dep_size.y + reach):
				var origin := Vector2i(ox, oy)
				if not GridManager.can_place(origin, s, null, ignore):
					continue
				var cells: Array = GridManager.cells_for(origin, s)
				if shore and not touches_water(cells):
					continue
				if deposit_within_reach(dep_origin, dep_size, cells, reach):
					spots.append({"origin": origin, "size": s})
					if limit > 0 and spots.size() >= limit:
						return spots
	return spots

## Celdas desde las que se llega a la acera del Nucleo andando por celdas
## libres (celda -> true), la acera incluida. Por ahi iria la carretera.
func _road_reach() -> Dictionary:
	var ring := core_ring_rect()
	var core := ring.grow(-1)
	var seen := {}
	var queue: Array = []
	for y in range(ring.position.y, ring.end.y):
		for x in range(ring.position.x, ring.end.x):
			var c := Vector2i(x, y)
			if core.has_point(c) or not GridManager.is_valid_cell(c):
				continue
			seen[c] = true
			queue.append(c)
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cur + d
			if not seen.has(n) and GridManager.is_cell_free(n):
				seen[n] = true
				queue.append(n)
	return seen

## ¿Tiene este yacimiento un hueco para su extractor con camino hasta la red?
func _deposit_is_workable(entry: Dictionary, reach: Dictionary) -> bool:
	if not is_instance_valid(entry.get("node")):
		return true
	for spot in _extractor_spots(entry):
		var cells: Array = GridManager.cells_for(spot["origin"], spot["size"])
		var footprint := {}
		for c in cells:
			footprint[c] = true
		for c in cells:
			if reach.has(c):
				return true
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = c + d
				if not footprint.has(n) and reach.has(n):
					return true
	return false

## Lo que el repaso de generate_new_map() exige, para los tests: todos los
## yacimientos del mapa tienen hueco para su extractor y camino a la red.
func all_deposits_workable() -> bool:
	var reach := _road_reach()
	for entry in _deposit_cells:
		if not _deposit_is_workable(entry, reach):
			return false
	return true

func spawn_deposit(deposit_id: String, cell: Vector2i, uses_override: int = -1, dep_size: Vector2i = Vector2i(2, 2)) -> Node:
	if not DEPOSIT_TYPES.has(deposit_id):
		return null
	var info: Dictionary = DEPOSIT_TYPES[deposit_id]

	var root := _build_deposit_node(deposit_id, info, dep_size)
	root.name = deposit_id
	root.set_meta("deposit_id", deposit_id)
	root.set_meta("cell", cell)
	root.set_meta("deposit_size", dep_size)

	# Set uses remaining from GameConfig
	var max_uses: int = GameConfig.get_deposit_max_uses(deposit_id)
	var uses: int = uses_override if uses_override > 0 else max_uses
	root.set_meta("uses_remaining", uses)
	root.set_meta("max_uses", max_uses)

	# Add to tree FIRST, then position (a global transform needs a parent)
	_deposits_container.add_child(root)
	_place_deposit_node(root, cell, dep_size)
	_refresh_deposit_look(root)
	if is_sea_deposit(deposit_id):
		GridManager.place_sea_obstacle(cell, root, dep_size)
	else:
		GridManager.place_obstacle(cell, root, dep_size)

	_deposit_cells.append({ "id": deposit_id, "cell_x": cell.x, "cell_y": cell.y, "size_x": dep_size.x, "size_y": dep_size.y, "node": root })
	if is_sea_deposit(deposit_id):
		_queue_sand_holes()
	return root

# ── La arena no tapa los bancos (1.1) ─────────────────────────────────
# Hasta fix/peces-en-el-mar los bancos iban en la primera franja de agua, justo
# donde la playa 3D de IslandGenerator baja desde el cesped hasta el mar: la
# arena los tapaba casi enteros, y la isla abria un hueco sobre cada uno
# (island_sand.gdshader, `holes`; la cala de Island2D en 2D). Ahora van mar
# adentro, pero con una casilla de agua por medio la cola de la playa 3D aun
# roza su borde, y la playa 2D (Island2D.SHORE_WIDTH, mas de dos casillas) los
# cubre: el hueco sigue en las dos vistas, acotado a la huella del banco y, en
# 2D, abierto hacia el mar (agua azul alrededor del banco, nunca hacia la
# tierra). Se avisa una vez por fotograma como mucho, solo cuando cambian.

var _sand_holes_queued := false

func _queue_sand_holes() -> void:
	if _sand_holes_queued or not is_inside_tree():
		return
	_sand_holes_queued = true
	_push_sand_holes.call_deferred()

## Los rectangulos (mundo XZ: centro y semiejes) de los yacimientos de mar.
func sea_deposit_rects() -> Array:
	var rects: Array = []
	for entry in _deposit_cells:
		if not is_sea_deposit(String(entry["id"])):
			continue
		var size := Vector2i(int(entry.get("size_x", 2)), int(entry.get("size_y", 2)))
		var c := GridManager.building_center(Vector2i(int(entry["cell_x"]), int(entry["cell_y"])), size)
		var half := Vector2(size) * GridManager.cell_size * 0.5
		rects.append(Vector4(c.x, c.z, half.x, half.y))
	return rects

func _push_sand_holes() -> void:
	_sand_holes_queued = false
	if not is_inside_tree() or get_tree().current_scene == null:
		return
	var island := get_tree().current_scene.get_node_or_null("IslandGenerator")
	if island != null and island.has_method("set_sand_holes"):
		island.set_sand_holes(sea_deposit_rects())

# ── Ganchos de vista ──────────────────────────────────────────────────
# Todo lo que es dibujo pasa por estos cinco metodos. La vista 2D
# (scripts/view2d/MapGenerator2D.gd) hereda de aqui y solo cambia estos; el
# sorteo, el registro, el agotamiento, el guardado y la regla de alcance son
# los mismos en las dos vistas.

## Contenedor de los yacimientos.
func _make_container() -> Node:
	return Node3D.new()

## Las marcas de las amenazas de costa (feat/amenazas-costa).
func _make_threat_marks() -> Node:
	return preload("res://scripts/map/ThreatMarks3D.gd").new()

## El nodo visible de un yacimiento (sin posicionar). La malla ("Look", una
## sola MeshInstance3D con la maqueta de DepositMesh) la pone
## _refresh_deposit_look() cuando el nodo ya sabe su celda y sus usos. Lleva un
## Label3D oculto: BuildingInfoPanel lee de ahi el nombre al hacer clic.
func _build_deposit_node(deposit_id: String, info: Dictionary, dep_size: Vector2i) -> Node:
	var root := Node3D.new()
	var look := MeshInstance3D.new()
	look.name = "Look"
	root.add_child(look)

	# Hidden label — used by BuildingInfoPanel to get display name on click
	var label := Label3D.new()
	label.text = Tr.t(info["display_name"])
	label.font_size = 48
	label.pixel_size = 0.01
	label.position.y = info["height"] * float(maxi(dep_size.x, dep_size.y)) + 1.2
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 10
	label.outline_modulate = Color(0, 0, 0, 0.8)
	label.modulate = Color(1, 1, 1, 1)
	label.visible = false

	root.add_child(label)
	return root

## Monta (o rehace) la maqueta del yacimiento con su semilla (la celda) y su
## etapa de agotamiento (DepositMesh.stage_of). Solo rehace la malla si la
## etapa cambio: minar no cuesta nada mientras no se cruza un cuarto.
func _refresh_deposit_look(root: Node) -> void:
	var stage := DepositMesh.stage_of(int(root.get_meta("uses_remaining", 1)), int(root.get_meta("max_uses", 1)))
	if int(root.get_meta("look_stage", -1)) == stage:
		return
	root.set_meta("look_stage", stage)
	var look := root.get_node_or_null("Look") as MeshInstance3D
	if look == null:
		return
	var cell: Vector2i = root.get_meta("cell", Vector2i.ZERO)
	look.mesh = DepositMesh.mesh_for(String(root.get_meta("deposit_id", "")), root.get_meta("deposit_size", Vector2i(2, 2)),
		DepositMesh.seed_for(cell), stage, GridManager.cell_size)

## Coloca el nodo ya metido en el arbol sobre su huella.
func _place_deposit_node(root: Node, cell: Vector2i, dep_size: Vector2i) -> void:
	(root as Node3D).global_position = GridManager.building_center(cell, dep_size)

## El aviso flotante de "agotado" sobre el yacimiento que desaparece.
func _show_depleted_text(node: Node) -> void:
	var pos: Vector3 = (node as Node3D).global_position
	var label := Label3D.new()
	label.text = Tr.t("LBL_DEPOSIT_DEPLETED")
	label.font_size = 22
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 3
	label.modulate = Color(0.8, 0.3, 0.2)
	label.global_position = pos + Vector3(0, 2.0, 0)
	get_tree().current_scene.add_child(label)
	var tween := create_tween()
	tween.tween_property(label, "global_position:y", pos.y + 5.0, 2.0).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 2.0).set_delay(0.5)
	tween.tween_callback(label.queue_free)

func _on_mining_completed(deposit_node: Node, _deposit_id: String) -> void:
	if not is_instance_valid(deposit_node):
		return
	if not deposit_node.has_meta("uses_remaining"):
		return
	var uses: int = deposit_node.get_meta("uses_remaining") - 1
	deposit_node.set_meta("uses_remaining", uses)
	if uses <= 0:
		_deplete_deposit(deposit_node)
	else:
		_refresh_deposit_look(deposit_node)

func _deplete_deposit(node: Node) -> void:
	var deposit_id: String = node.get_meta("deposit_id", "")
	var cell: Vector2i = node.get_meta("cell", Vector2i(-1, -1))
	var dep_size: Vector2i = node.get_meta("deposit_size", Vector2i(2, 2))
	# Remove from tracking
	for i in range(_deposit_cells.size() - 1, -1, -1):
		if _deposit_cells[i]["node"] == node:
			_deposit_cells.remove_at(i)
			break
	# Remove from grid (multi-cell)
	if cell != Vector2i(-1, -1):
		GridManager.remove_obstacle(cell, dep_size)
	# Floating text
	_show_depleted_text(node)
	# Signal and remove node
	EventBus.deposit_depleted.emit(node, deposit_id)
	EventBus.notification_posted.emit(Tr.t("NOTIF_DEPOSIT_GONE") % Tr.t(DEPOSIT_TYPES[deposit_id]["display_name"]), "warning", Color(0.8, 0.5, 0.2))
	node.queue_free()
	# Auto-save
	GameManager.save_game()

func get_all_deposits() -> Array:
	var result: Array = []
	for entry in _deposit_cells:
		if is_instance_valid(entry["node"]):
			var node: Node = entry["node"]
			var dep_entry := {
				"id": entry["id"],
				"cell_x": entry["cell_x"],
				"cell_y": entry["cell_y"],
				"size_x": entry.get("size_x", 2),
				"size_y": entry.get("size_y", 2),
			}
			if node.has_meta("uses_remaining"):
				dep_entry["uses_remaining"] = node.get_meta("uses_remaining")
			# Ya tuvo su camino de acceso (PlacementRules.pave_access_ring): solo
			# se guarda si es asi; un save sin la clave es "aun no".
			if bool(node.get_meta("access_ring", false)):
				dep_entry["access_ring"] = true
			result.append(dep_entry)
	return result

func clear_all_deposits() -> void:
	for entry in _deposit_cells:
		var dep_size := Vector2i(entry.get("size_x", 2), entry.get("size_y", 2))
		GridManager.remove_obstacle(Vector2i(entry["cell_x"], entry["cell_y"]), dep_size)
		if is_instance_valid(entry["node"]):
			entry["node"].queue_free()
	_deposit_cells.clear()
	_queue_sand_holes()

# ── Deposit reach (placement rules) ──

## Pure check: is the deposit rectangle (dep_origin, dep_size) within `reach`
## cells of ANY of `cells`? Distance is Chebyshev (king's move), so reach 1
## means "touching, diagonals included" and reach 0 means "overlapping".
## Static and free of scene state on purpose: this is the rule the placement
## tests pin down, so it must not live inside the mouse flow.
static func deposit_within_reach(dep_origin: Vector2i, dep_size: Vector2i, cells: Array, reach: int) -> bool:
	var max_x: int = dep_origin.x + dep_size.x - 1
	var max_y: int = dep_origin.y + dep_size.y - 1
	for cell in cells:
		var c: Vector2i = cell
		# Gap between the cell and the rectangle along each axis (0 = inside)
		var dx: int = maxi(0, maxi(dep_origin.x - c.x, c.x - max_x))
		var dy: int = maxi(0, maxi(dep_origin.y - c.y, c.y - max_y))
		if maxi(dx, dy) <= reach:
			return true
	return false

## First deposit of the given type within `reach` of the provided cells, or null.
func find_deposit_near_cells(deposit_id: String, cells: Array, reach: int) -> Node:
	for entry in _deposit_cells:
		if entry["id"] != deposit_id or not is_instance_valid(entry["node"]):
			continue
		var dep_origin := Vector2i(entry["cell_x"], entry["cell_y"])
		var dep_size := Vector2i(entry.get("size_x", 2), entry.get("size_y", 2))
		if deposit_within_reach(dep_origin, dep_size, cells, reach):
			return entry["node"]
	return null

## Every deposit of the type within `reach` of the cells, nearest first (by
## Chebyshev gap; ties keep the map order). The fishing dock picks among them.
func find_deposits_near_cells(deposit_id: String, cells: Array, reach: int) -> Array:
	var found: Array = []
	for entry in _deposit_cells:
		if entry["id"] != deposit_id or not is_instance_valid(entry["node"]):
			continue
		var dep_origin := Vector2i(entry["cell_x"], entry["cell_y"])
		var dep_size := Vector2i(entry.get("size_x", 2), entry.get("size_y", 2))
		var d := deposit_distance(dep_origin, dep_size, cells)
		if d <= reach:
			found.append([d, found.size(), entry["node"]])
	found.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	return found.map(func(f): return f[2])

## El embarcadero de un muelle (fix/peces-en-el-mar): las celdas de agua entre
## su huella (`dock_cells`) y el banco mas cercano a su alcance, en linea (pasos
## de rey, el mas recto entre los mas cortos): {"cells", "from" (la celda del
## muelle de la que sale), "to" (la del banco a la que llega)}. "cells" vacio sin
## banco, o si ya lo toca (un muelle de una partida vieja). Solo dibujo: no ocupa
## la rejilla. Se pide al colocar, mover o cargar, nunca por fotograma.
func pier_path(dock_cells: Array, building_id: String = "fishing_dock") -> Dictionary:
	var rule: Dictionary = GameConfig.get_deposit_rule(building_id)
	if rule.is_empty() or dock_cells.is_empty():
		return {"cells": []}
	var near := find_deposits_near_cells(String(rule["deposit"]), dock_cells, int(rule["reach"]))
	if near.is_empty():
		return {"cells": []}
	var dep: Node = near[0]
	var o: Vector2i = dep.get_meta("cell", Vector2i.ZERO)
	var sz: Vector2i = dep.get_meta("deposit_size", Vector2i(2, 2))
	var shoal := Rect2i(o, sz)
	var from: Vector2i = dock_cells[0]
	var to: Vector2i = from
	var best_d := 1 << 30
	var best_m := 1 << 30
	for cell in dock_cells:
		var a: Vector2i = cell
		var b := Vector2i(clampi(a.x, o.x, shoal.end.x - 1), clampi(a.y, o.y, shoal.end.y - 1))
		var d: int = maxi(absi(b.x - a.x), absi(b.y - a.y))
		var m: int = absi(b.x - a.x) + absi(b.y - a.y)
		if d < best_d or (d == best_d and m < best_m):
			best_d = d
			best_m = m
			from = a
			to = b
	var out: Array = []
	var cur := from
	for _i in range(best_d):
		cur += Vector2i(signi(to.x - cur.x), signi(to.y - cur.y))
		if shoal.has_point(cur):
			break
		if GridManager.is_water_cell(cur):
			out.append(cur)
	return {"cells": out, "from": from, "to": to}

## Chebyshev distance from the nearest of `cells` to the rectangle (0 = inside).
static func deposit_distance(dep_origin: Vector2i, dep_size: Vector2i, cells: Array) -> int:
	var max_x: int = dep_origin.x + dep_size.x - 1
	var max_y: int = dep_origin.y + dep_size.y - 1
	var best := 1 << 30
	for cell in cells:
		var c: Vector2i = cell
		var dx: int = maxi(0, maxi(dep_origin.x - c.x, c.x - max_x))
		var dy: int = maxi(0, maxi(dep_origin.y - c.y, c.y - max_y))
		best = mini(best, maxi(dx, dy))
	return best

## Find a deposit of the given type that overlaps any of the provided cells.
## Returns the deposit node or null. Kept as the reach-0 case of the rule above.
func find_deposit_at_cells(deposit_id: String, cells: Array) -> Node:
	return find_deposit_near_cells(deposit_id, cells, 0)

## Is there at least one free spot where a building with `footprint` (either
## orientation) could stand within `reach` of a `deposit_id` deposit? Uses the
## live grid occupancy. This is the "can the player actually open Era 1 with a
## sawmill next to a forest" question, asked by the map tests.
func has_buildable_spot_near(deposit_id: String, footprint: Vector2i, reach: int) -> bool:
	return not buildable_spots_near(deposit_id, footprint, reach, 1).is_empty()

## All free origins (with their orientation) for `footprint` within `reach` of a
## `deposit_id` deposit, up to `limit` results (0 = no limit).
func buildable_spots_near(deposit_id: String, footprint: Vector2i, reach: int, limit: int = 0) -> Array:
	var spots: Array = []
	var orientations: Array = [footprint]
	if footprint.x != footprint.y:
		orientations.append(Vector2i(footprint.y, footprint.x))
	for entry in _deposit_cells:
		if entry["id"] != deposit_id or not is_instance_valid(entry["node"]):
			continue
		var dep_origin := Vector2i(entry["cell_x"], entry["cell_y"])
		var dep_size := Vector2i(entry.get("size_x", 2), entry.get("size_y", 2))
		for size in orientations:
			var s: Vector2i = size
			# Any origin whose footprint could touch the deposit's reach band.
			for ox in range(dep_origin.x - s.x - reach + 1, dep_origin.x + dep_size.x + reach):
				for oy in range(dep_origin.y - s.y - reach + 1, dep_origin.y + dep_size.y + reach):
					var origin := Vector2i(ox, oy)
					if not GridManager.can_place(origin, s):
						continue
					# Lo que trabaja un banco de mar se planta en la costa.
					if is_sea_deposit(deposit_id) and not touches_water(GridManager.cells_for(origin, s)):
						continue
					if deposit_within_reach(dep_origin, dep_size, GridManager.cells_for(origin, s), reach):
						spots.append({"origin": origin, "size": s})
						if limit > 0 and spots.size() >= limit:
							return spots
	return spots

## Remove a deposit programmatically (used when a building consumes it).
func remove_deposit(node: Node) -> void:
	if not is_instance_valid(node):
		return
	var deposit_id: String = node.get_meta("deposit_id", "")
	var cell: Vector2i = node.get_meta("cell", Vector2i(-1, -1))
	var dep_size: Vector2i = node.get_meta("deposit_size", Vector2i(2, 2))
	for i in range(_deposit_cells.size() - 1, -1, -1):
		if _deposit_cells[i]["node"] == node:
			_deposit_cells.remove_at(i)
			break
	if cell != Vector2i(-1, -1):
		GridManager.remove_obstacle(cell, dep_size)
	if is_sea_deposit(deposit_id):
		_queue_sand_holes()
	node.queue_free()

## Una celda al azar donde cabe un yacimiento de `dep_size`: dentro de la
## rejilla pero fuera de la franja de costa, lejos del centro y sin tocar la
## acera del Nucleo (queda `deposit_core_gap` de hueco para que la red crezca).
func _random_cell_for_deposit(center: Vector2i, dep_size: Vector2i) -> Vector2i:
	var keep_out: Rect2i = core_ring_rect().grow(GameConfig.deposit_core_gap)
	# Se sortea dentro del rectangulo de la tierra (en una isla irregular el mar
	# se come buena parte de la rejilla) y nunca en la franja de costa.
	var land: Rect2i = GridManager.land_bounds()
	var max_x: int = land.end.x - dep_size.x
	var max_y: int = land.end.y - dep_size.y
	if max_x < land.position.x or max_y < land.position.y:
		return Vector2i(-1, -1)
	for attempt in range(120):
		var cx: int = randi_range(land.position.x, max_x)
		var cy: int = randi_range(land.position.y, max_y)
		var cell := Vector2i(cx, cy)
		# Check center exclusion from deposit center
		var mid_x: float = cx + dep_size.x * 0.5
		var mid_y: float = cy + dep_size.y * 0.5
		var dist: float = absf(mid_x - center.x) + absf(mid_y - center.y)
		if dist <= GameConfig.deposit_center_exclusion:
			continue
		if keep_out.intersects(Rect2i(cell, dep_size)):
			continue
		# Check all cells are free (y en tierra: can_place no acepta agua)
		if not GridManager.can_place(cell, dep_size):
			continue
		if _touches_shore(cell, dep_size):
			continue
		return cell
	return Vector2i(-1, -1)

func _touches_shore(cell: Vector2i, dep_size: Vector2i) -> bool:
	for c in GridManager.cells_for(cell, dep_size):
		if is_shore_cell(c):
			return true
	return false
