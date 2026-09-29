extends Node
## Generates random resource deposits on the map.
## Deposits occupy multiple grid cells with random sizes.
## Each deposit has limited uses before depletion.

const DEPOSIT_TYPES := {
	"gold_vein": { "display_name": "DEP_GOLD_VEIN", "color": Color(0.9, 0.75, 0.1, 1), "height": 0.6 },
	"iron_deposit": { "display_name": "DEP_IRON", "color": Color(0.6, 0.6, 0.65, 1), "height": 0.5 },
	"oil_well": { "display_name": "DEP_OIL", "color": Color(0.15, 0.15, 0.18, 1), "height": 0.15 },
	"forest": { "display_name": "DEP_FOREST", "color": Color(0.2, 0.5, 0.15, 1), "height": 0.8 },
}

const DEPOSIT_IDS := ["gold_vein", "iron_deposit", "oil_well", "forest"]

var _deposits_container: Node
var _deposit_cells: Array = []  # [{ "id": String, "cell_x": int, "cell_y": int, "size_x": int, "size_y": int, "node": Node }]

func _ready() -> void:
	_deposits_container = _make_container()
	_deposits_container.name = "Deposits"
	add_child(_deposits_container)
	EventBus.mining_completed.connect(_on_mining_completed)
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

## ¿Es `cell` de la franja de costa? La franja son las `map_shore_band` celdas
## exteriores de la rejilla: tierra construible, pero sin yacimientos de tierra.
static func is_shore_cell(cell: Vector2i) -> bool:
	if not GridManager.is_valid_cell(cell):
		return false
	var band: int = GameConfig.map_shore_band
	return cell.x < band or cell.y < band \
		or cell.x >= GridManager.grid_width - band or cell.y >= GridManager.grid_height - band

## Todas las celdas de la franja de costa.
static func shore_cells() -> Array:
	var out: Array = []
	for y in range(GridManager.grid_height):
		for x in range(GridManager.grid_width):
			var c := Vector2i(x, y)
			if is_shore_cell(c):
				out.append(c)
	return out

## ¿Es mar? Todo lo que queda fuera de la rejilla: margen de hierba, arena y agua
## (IslandGenerator). Ahi no se construye; un recurso marino se trabajaria desde
## una celda de costa pegada a el.
static func is_sea_cell(cell: Vector2i) -> bool:
	return not GridManager.is_valid_cell(cell)

## Yacimientos de costa y mar. Hoy no hay ninguno. Cuando los haya (pesca,
## petroleo en alta mar, sal...): se anade su tipo a DEPOSIT_TYPES y a esta
## lista, se le pone una regla en GameConfig.building_deposit_rules para su
## extractor (un muelle, que tocaria una celda de costa y el mar de al lado), y
## aqui se sortean sobre shore_cells(), que ningun yacimiento de tierra pisa.
## El guardado ya los llevaria: get_all_deposits() no mira el tipo.
const SHORE_DEPOSIT_IDS: Array = []

func _generate_shore_deposits() -> void:
	for _deposit_id in SHORE_DEPOSIT_IDS:
		pass

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
		return _spots_for(entry, footprint, int(rule["reach"]), limit)
	return [{"origin": Vector2i(entry["cell_x"], entry["cell_y"]), "size": Vector2i.ONE}]

func _spots_for(entry: Dictionary, footprint: Vector2i, reach: int, limit: int) -> Array:
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
				if deposit_within_reach(dep_origin, dep_size, GridManager.cells_for(origin, s), reach):
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
	GridManager.place_obstacle(cell, root, dep_size)

	_deposit_cells.append({ "id": deposit_id, "cell_x": cell.x, "cell_y": cell.y, "size_x": dep_size.x, "size_y": dep_size.y, "node": root })
	return root

# ── Ganchos de vista ──────────────────────────────────────────────────
# Todo lo que es dibujo pasa por estos cuatro metodos. La vista 2D
# (scripts/view2d/MapGenerator2D.gd) hereda de aqui y solo cambia estos; el
# sorteo, el registro, el agotamiento, el guardado y la regla de alcance son
# los mismos en las dos vistas.

## Contenedor de los yacimientos.
func _make_container() -> Node:
	return Node3D.new()

## El nodo visible de un yacimiento (sin posicionar). Lleva un Label3D oculto:
## BuildingInfoPanel lee de ahi el nombre al hacer clic.
func _build_deposit_node(deposit_id: String, info: Dictionary, dep_size: Vector2i) -> Node:
	var root := Node3D.new()

	# Scale mesh to fill the multi-cell area
	var scale_x: float = float(dep_size.x)
	var scale_z: float = float(dep_size.y)
	var deposit_mesh := _create_deposit_mesh(deposit_id, info)
	deposit_mesh.scale = Vector3(scale_x, maxf(scale_x, scale_z) * 0.8, scale_z)
	root.add_child(deposit_mesh)

	# Hidden label — used by BuildingInfoPanel to get display name on click
	var label := Label3D.new()
	label.text = Tr.t(info["display_name"])
	label.font_size = 48
	label.pixel_size = 0.01
	label.position.y = info["height"] * maxf(scale_x, scale_z) + 1.2
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 10
	label.outline_modulate = Color(0, 0, 0, 0.8)
	label.modulate = Color(1, 1, 1, 1)
	label.visible = false

	root.add_child(label)
	return root

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
			result.append(dep_entry)
	return result

func clear_all_deposits() -> void:
	for entry in _deposit_cells:
		var dep_size := Vector2i(entry.get("size_x", 2), entry.get("size_y", 2))
		GridManager.remove_obstacle(Vector2i(entry["cell_x"], entry["cell_y"]), dep_size)
		if is_instance_valid(entry["node"]):
			entry["node"].queue_free()
	_deposit_cells.clear()

# ── Deposit mesh generation ──

func _dep_metal(color: Color, metallic: float = 0.7, roughness: float = 0.45) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	return mat

func _dep_emissive(color: Color, energy: float = 1.5) -> StandardMaterial3D:
	var mat := _dep_metal(color, 0.0, 0.9)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat

func _dep_add_box(parent: Node3D, pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.set_surface_override_material(0, mat)
	mi.position = pos
	parent.add_child(mi)
	return mi

func _dep_add_cyl(parent: Node3D, pos: Vector3, radius: float, height: float, mat: StandardMaterial3D, seg: int = 24) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = seg
	mi.mesh = mesh
	mi.set_surface_override_material(0, mat)
	mi.position = pos
	parent.add_child(mi)
	return mi

func _dep_add_sphere(parent: Node3D, pos: Vector3, radius: float, mat: StandardMaterial3D, seg: int = 16) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = seg
	mesh.rings = maxi(seg / 2, 8)
	mi.mesh = mesh
	mi.set_surface_override_material(0, mat)
	mi.position = pos
	parent.add_child(mi)
	return mi

func _dep_add_cone(parent: Node3D, pos: Vector3, bot_r: float, top_r: float, height: float, mat: StandardMaterial3D, seg: int = 24) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_r
	mesh.bottom_radius = bot_r
	mesh.height = height
	mesh.radial_segments = seg
	mi.mesh = mesh
	mi.set_surface_override_material(0, mat)
	mi.position = pos
	parent.add_child(mi)
	return mi

func _create_deposit_mesh(deposit_id: String, info: Dictionary) -> Node3D:
	match deposit_id:
		"gold_vein": return _deposit_gold_vein()
		"iron_deposit": return _deposit_iron()
		"oil_well": return _deposit_oil_well()
		"forest": return _deposit_forest()
	# Fallback
	var node := Node3D.new()
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = GridManager.cell_size * 0.35
	cyl.bottom_radius = GridManager.cell_size * 0.4
	cyl.height = info["height"]
	mi.mesh = cyl
	mi.set_surface_override_material(0, _dep_metal(info["color"]))
	mi.position.y = info["height"] * 0.5
	node.add_child(mi)
	return node

func _deposit_gold_vein() -> Node3D:
	var root := Node3D.new()
	var mat_rock := _dep_metal(Color(0.40, 0.35, 0.30), 0.3, 0.8)
	var mat_gold := _dep_metal(Color(0.85, 0.70, 0.15), 0.95, 0.2)
	var mat_gold_glow := _dep_emissive(Color(0.9, 0.75, 0.1), 0.6)
	# Large rock cluster
	_dep_add_sphere(root, Vector3(0, 0.4, 0), 0.7, mat_rock)
	_dep_add_sphere(root, Vector3(0.5, 0.5, 0.3), 0.5, mat_rock)
	_dep_add_sphere(root, Vector3(-0.4, 0.45, -0.35), 0.55, mat_rock)
	_dep_add_sphere(root, Vector3(-0.6, 0.3, 0.4), 0.4, mat_rock)
	_dep_add_sphere(root, Vector3(0.3, 0.3, -0.5), 0.45, mat_rock)
	# Gold veins (bright streaks on surface)
	_dep_add_box(root, Vector3(0.2, 0.7, 0.5), Vector3(0.35, 0.08, 0.08), mat_gold)
	_dep_add_box(root, Vector3(-0.3, 0.75, -0.2), Vector3(0.25, 0.07, 0.12), mat_gold)
	_dep_add_box(root, Vector3(0.5, 0.5, 0.0), Vector3(0.08, 0.18, 0.25), mat_gold)
	_dep_add_box(root, Vector3(-0.1, 0.6, 0.4), Vector3(0.3, 0.06, 0.06), mat_gold)
	# Gold nuggets scattered around base
	_dep_add_sphere(root, Vector3(0.7, 0.1, 0.5), 0.12, mat_gold_glow)
	_dep_add_sphere(root, Vector3(-0.6, 0.08, 0.5), 0.09, mat_gold_glow)
	_dep_add_sphere(root, Vector3(0.0, 0.85, 0.2), 0.1, mat_gold_glow)
	_dep_add_sphere(root, Vector3(-0.5, 0.1, -0.4), 0.08, mat_gold_glow)
	_dep_add_sphere(root, Vector3(0.4, 0.08, -0.6), 0.1, mat_gold_glow)
	return root

func _deposit_iron() -> Node3D:
	var root := Node3D.new()
	var mat_iron := _dep_metal(Color(0.45, 0.42, 0.48), 0.85, 0.35)
	var mat_dark := _dep_metal(Color(0.25, 0.23, 0.27), 0.8, 0.4)
	var mat_rust := _dep_metal(Color(0.55, 0.30, 0.15), 0.5, 0.6)
	var mat_sheen := _dep_emissive(Color(0.55, 0.55, 0.65), 0.3)
	# Large angular iron ore chunks (scattered boulders)
	var b1 := _dep_add_box(root, Vector3(0, 0.5, 0), Vector3(0.8, 1.0, 0.7), mat_iron)
	b1.rotation.y = 0.3
	var b2 := _dep_add_box(root, Vector3(0.4, 0.65, 0.4), Vector3(0.55, 0.9, 0.5), mat_dark)
	b2.rotation.y = -0.5
	b2.rotation.x = 0.15
	var b3 := _dep_add_box(root, Vector3(-0.3, 0.4, -0.25), Vector3(0.65, 0.7, 0.55), mat_iron)
	b3.rotation.y = 0.8
	var b4 := _dep_add_box(root, Vector3(-0.5, 0.3, 0.4), Vector3(0.45, 0.5, 0.45), mat_dark)
	b4.rotation.y = -0.2
	b4.rotation.z = 0.1
	# Tall ore pillar
	var b5 := _dep_add_box(root, Vector3(0.15, 0.7, -0.35), Vector3(0.35, 1.2, 0.3), mat_iron)
	b5.rotation.y = 0.5
	# Metallic veins (shiny streaks)
	_dep_add_box(root, Vector3(0.2, 0.85, 0.4), Vector3(0.4, 0.05, 0.08), mat_sheen)
	_dep_add_box(root, Vector3(-0.15, 0.7, -0.3), Vector3(0.3, 0.05, 0.1), mat_sheen)
	_dep_add_box(root, Vector3(0.5, 0.5, -0.1), Vector3(0.08, 0.05, 0.3), mat_sheen)
	# Rust weathering
	_dep_add_box(root, Vector3(-0.4, 0.6, 0.25), Vector3(0.5, 0.03, 0.06), mat_rust)
	_dep_add_box(root, Vector3(0.3, 0.35, 0.15), Vector3(0.35, 0.03, 0.08), mat_rust)
	# Scattered ore fragments
	_dep_add_sphere(root, Vector3(0.6, 0.1, -0.4), 0.1, mat_dark)
	_dep_add_sphere(root, Vector3(-0.55, 0.08, 0.55), 0.08, mat_dark)
	_dep_add_sphere(root, Vector3(0.7, 0.07, 0.3), 0.07, mat_iron)
	_dep_add_sphere(root, Vector3(-0.65, 0.06, -0.35), 0.06, mat_dark)
	_dep_add_sphere(root, Vector3(0.1, 0.05, 0.65), 0.07, mat_iron)
	return root

func _deposit_oil_well() -> Node3D:
	var root := Node3D.new()
	var mat_oil_dark := _dep_metal(Color(0.06, 0.05, 0.08), 0.4, 0.15)
	var mat_oil_sheen := _dep_emissive(Color(0.12, 0.08, 0.20), 0.4)
	var mat_oil_edge := _dep_metal(Color(0.10, 0.08, 0.12), 0.3, 0.25)
	var mat_iron := _dep_metal(Color(0.25, 0.23, 0.27), 0.8, 0.4)
	var mat_rust := _dep_metal(Color(0.50, 0.28, 0.15), 0.6, 0.55)
	var mat_warning := _dep_emissive(Color(1.0, 0.3, 0.05), 1.5)
	# Oil puddle base
	_dep_add_cyl(root, Vector3(0, 0.02, 0), 0.85, 0.04, mat_oil_sheen, 12)
	_dep_add_cyl(root, Vector3(0.35, 0.02, 0.25), 0.55, 0.04, mat_oil_dark)
	_dep_add_cyl(root, Vector3(-0.3, 0.02, -0.2), 0.6, 0.04, mat_oil_dark)
	_dep_add_cyl(root, Vector3(-0.45, 0.02, 0.35), 0.4, 0.03, mat_oil_sheen)
	_dep_add_cyl(root, Vector3(0.5, 0.02, -0.35), 0.45, 0.03, mat_oil_edge)
	# Natural oil seep (geyser pipe)
	_dep_add_cyl(root, Vector3(0, 0.3, 0), 0.08, 0.6, mat_iron)
	_dep_add_cyl(root, Vector3(0, 0.65, 0), 0.12, 0.1, mat_rust)
	# Oil bubbling up from pipe
	_dep_add_sphere(root, Vector3(0, 0.72, 0), 0.08, mat_oil_sheen)
	_dep_add_sphere(root, Vector3(0.04, 0.78, 0.02), 0.04, mat_oil_dark)
	# Warning stakes around the seep
	for i in range(4):
		var angle: float = i * TAU / 4.0 + PI / 4.0
		var sx: float = cos(angle) * 0.6
		var sz: float = sin(angle) * 0.6
		_dep_add_cyl(root, Vector3(sx, 0.2, sz), 0.02, 0.4, mat_rust)
		_dep_add_sphere(root, Vector3(sx, 0.42, sz), 0.035, mat_warning)
	# Small satellite puddles
	_dep_add_cyl(root, Vector3(0.7, 0.015, 0.5), 0.25, 0.03, mat_oil_dark)
	_dep_add_cyl(root, Vector3(-0.65, 0.015, -0.5), 0.3, 0.03, mat_oil_sheen)
	# Bubbles
	_dep_add_sphere(root, Vector3(0.15, 0.05, 0.15), 0.06, mat_oil_sheen)
	_dep_add_sphere(root, Vector3(-0.25, 0.05, -0.1), 0.05, mat_oil_sheen)
	return root

func _deposit_forest() -> Node3D:
	var root := Node3D.new()
	var mat_trunk := _dep_metal(Color(0.35, 0.22, 0.10), 0.1, 0.85)
	var mat_trunk_birch := _dep_metal(Color(0.65, 0.58, 0.48), 0.1, 0.8)
	var mat_leaves_dark := _dep_metal(Color(0.15, 0.35, 0.10), 0.1, 0.8)
	var mat_leaves_light := _dep_metal(Color(0.28, 0.50, 0.18), 0.1, 0.75)
	var mat_leaves_autumn := _dep_metal(Color(0.45, 0.35, 0.10), 0.1, 0.8)
	var mat_moss := _dep_metal(Color(0.18, 0.30, 0.12), 0.05, 0.9)
	var mat_mushroom := _dep_emissive(Color(0.8, 0.6, 0.2), 0.3)
	# Main tall pine (layered canopy)
	_dep_add_cyl(root, Vector3(0, 0.8, 0), 0.12, 1.6, mat_trunk)
	_dep_add_cone(root, Vector3(0, 2.0, 0), 0.65, 0.0, 0.9, mat_leaves_dark)
	_dep_add_cone(root, Vector3(0, 1.7, 0), 0.72, 0.2, 0.6, mat_leaves_light)
	_dep_add_cone(root, Vector3(0, 1.4, 0), 0.55, 0.3, 0.4, mat_leaves_dark)
	# Second tall tree (birch)
	_dep_add_cyl(root, Vector3(0.55, 0.65, 0.5), 0.07, 1.3, mat_trunk_birch)
	_dep_add_sphere(root, Vector3(0.55, 1.55, 0.5), 0.4, mat_leaves_light)
	_dep_add_sphere(root, Vector3(0.55, 1.35, 0.55), 0.35, mat_leaves_dark)
	# Third pine
	_dep_add_cyl(root, Vector3(-0.55, 0.5, -0.45), 0.08, 1.0, mat_trunk)
	_dep_add_cone(root, Vector3(-0.55, 1.25, -0.45), 0.45, 0.0, 0.7, mat_leaves_dark)
	_dep_add_cone(root, Vector3(-0.55, 1.05, -0.45), 0.50, 0.12, 0.4, mat_leaves_light)
	# Fourth small autumn tree
	_dep_add_cyl(root, Vector3(-0.35, 0.5, 0.55), 0.06, 1.0, mat_trunk)
	_dep_add_sphere(root, Vector3(-0.35, 1.2, 0.55), 0.35, mat_leaves_autumn)
	# Fifth young sapling
	_dep_add_cyl(root, Vector3(0.4, 0.3, -0.5), 0.04, 0.6, mat_trunk)
	_dep_add_cone(root, Vector3(0.4, 0.75, -0.5), 0.2, 0.0, 0.35, mat_leaves_light)
	# Dense undergrowth
	_dep_add_sphere(root, Vector3(-0.4, 0.2, 0.15), 0.25, mat_leaves_light)
	_dep_add_sphere(root, Vector3(0.3, 0.2, -0.3), 0.22, mat_leaves_dark)
	_dep_add_sphere(root, Vector3(0.65, 0.15, 0.1), 0.2, mat_leaves_light)
	_dep_add_sphere(root, Vector3(-0.6, 0.18, -0.2), 0.22, mat_leaves_dark)
	_dep_add_sphere(root, Vector3(0.1, 0.15, 0.65), 0.18, mat_leaves_light)
	_dep_add_sphere(root, Vector3(-0.2, 0.14, -0.6), 0.16, mat_leaves_dark)
	# Fallen logs
	var log1 := _dep_add_cyl(root, Vector3(-0.6, 0.1, 0.4), 0.07, 0.5, mat_trunk)
	log1.rotation.z = PI / 2.0
	var log2 := _dep_add_cyl(root, Vector3(0.5, 0.1, 0.7), 0.06, 0.45, mat_trunk)
	log2.rotation.z = PI / 2.0
	log2.rotation.y = 0.8
	# Tree stump
	_dep_add_cyl(root, Vector3(0.6, 0.1, -0.55), 0.1, 0.2, mat_trunk)
	# Moss patches
	_dep_add_cyl(root, Vector3(0.1, 0.01, -0.1), 0.6, 0.02, mat_moss)
	_dep_add_cyl(root, Vector3(-0.3, 0.01, 0.3), 0.45, 0.02, mat_moss)
	_dep_add_cyl(root, Vector3(0.4, 0.01, 0.35), 0.3, 0.02, mat_moss)
	# Mushrooms
	_dep_add_cyl(root, Vector3(-0.5, 0.06, 0.0), 0.015, 0.06, mat_trunk)
	_dep_add_sphere(root, Vector3(-0.5, 0.1, 0.0), 0.04, mat_mushroom)
	_dep_add_cyl(root, Vector3(-0.45, 0.05, 0.05), 0.01, 0.04, mat_trunk)
	_dep_add_sphere(root, Vector3(-0.45, 0.08, 0.05), 0.03, mat_mushroom)
	return root

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
	node.queue_free()

## Una celda al azar donde cabe un yacimiento de `dep_size`: dentro de la
## rejilla pero fuera de la franja de costa, lejos del centro y sin tocar la
## acera del Nucleo (queda `deposit_core_gap` de hueco para que la red crezca).
func _random_cell_for_deposit(center: Vector2i, dep_size: Vector2i) -> Vector2i:
	var band: int = GameConfig.map_shore_band
	var keep_out: Rect2i = core_ring_rect().grow(GameConfig.deposit_core_gap)
	var max_x: int = GridManager.grid_width - band - dep_size.x
	var max_y: int = GridManager.grid_height - band - dep_size.y
	if max_x < band or max_y < band:
		return Vector2i(-1, -1)
	for attempt in range(80):
		var cx: int = randi_range(band, max_x)
		var cy: int = randi_range(band, max_y)
		var cell := Vector2i(cx, cy)
		# Check center exclusion from deposit center
		var mid_x: float = cx + dep_size.x * 0.5
		var mid_y: float = cy + dep_size.y * 0.5
		var dist: float = absf(mid_x - center.x) + absf(mid_y - center.y)
		if dist <= GameConfig.deposit_center_exclusion:
			continue
		if keep_out.intersects(Rect2i(cell, dep_size)):
			continue
		# Check all cells are free
		if not GridManager.can_place(cell, dep_size):
			continue
		return cell
	return Vector2i(-1, -1)
