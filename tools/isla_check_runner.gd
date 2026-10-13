extends Node
## La lanza tools/isla_check.gd (ver alli).

const MapGen := preload("res://scripts/map/MapGenerator.gd")
const Shape := preload("res://scripts/map/IslandShape.gd")
const IslandGen := preload("res://scripts/map/IslandGenerator.gd")
const SEEDS := [1, 7, 42, 99, 314, 2718, 4242, 9001, 12345, 55555]

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var seeds: Array = SEEDS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			seeds = []
			for part in a.substr(8).split(","):
				seeds.append(int(part))
	var nucleo: BuildingData = load("res://data/buildings/nucleo.tres")
	var road: BuildingData = load("res://data/buildings/road.tres")
	var map: Node = MapGen.new()
	add_child(map)
	print("| semilla | rejilla | tierra | construible | oro | hierro | petroleo | bosque | trabajables | encerradas | puntos costa | ms isla |")
	print("|---|---|---|---|---|---|---|---|---|---|---|---|")
	var all_ok := true
	for s in seeds:
		map.clear_all_deposits()
		GridManager.clear_all()
		seed(int(s))
		var t0 := Time.get_ticks_msec()
		GridManager.roll_new_map()
		var t_mask := Time.get_ticks_msec() - t0
		var core := Vector2i(GridManager.grid_width / 2, GridManager.grid_height / 2)
		var keep: Array = []
		var n_node := Node.new()
		keep.append(n_node)
		GridManager.place_building(core, nucleo, n_node)
		var ring: Array = []
		for y in range(core.y - 1, core.y + 4):
			for x in range(core.x - 1, core.x + 4):
				var c := Vector2i(x, y)
				if Rect2i(core, Vector2i(3, 3)).has_point(c):
					continue
				var r_node := Node.new()
				keep.append(r_node)
				GridManager.place_building(c, road, r_node)
				ring.append(c)
		map.generate_new_map()
		var counts := {}
		for id in MapGen.DEPOSIT_IDS:
			counts[id] = 0
		for d in map.get_all_deposits():
			counts[d["id"]] = int(counts[d["id"]]) + 1
		var free := 0
		for y in range(GridManager.grid_height):
			for x in range(GridManager.grid_width):
				if GridManager.is_cell_free(Vector2i(x, y)):
					free += 1
		var reach := _reach(ring)
		var enclosed := free - reach
		var workable: bool = map.all_deposits_workable()
		var coast := IslandGen.coast_for_grid()
		all_ok = all_ok and workable and enclosed == 0
		print("| %d | %dx%d | %d | %d | %d | %d | %d | %d | %s | %d | %d | %d |" % [s,
			GridManager.grid_width, GridManager.grid_height, GridManager.land_cell_count(), free,
			counts["gold_vein"], counts["iron_deposit"], counts["oil_well"], counts["forest"],
			"si" if workable else "NO", enclosed, coast.size(), t_mask])
		for n in keep:
			n.free()
	print("isla_check: ", "todo bien" if all_ok else "HAY PROBLEMAS")
	map.clear_all_deposits()
	GridManager.clear_all()
	GridManager.reset_size()
	get_tree().quit()

## Celdas libres a las que se llega andando desde la acera.
func _reach(ring: Array) -> int:
	var seen := {}
	var queue: Array = []
	for c in ring:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if GridManager.is_cell_free(n) and not seen.has(n):
				seen[n] = true
				queue.append(n)
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cur + d
			if GridManager.is_cell_free(n) and not seen.has(n):
				seen[n] = true
				queue.append(n)
	return seen.size()
