extends Node
## Manages timed processes for buildings and mining for deposits.
## Reads definitions from GameConfig (durations already scaled).

var _type_map := {
	"gold": ResourceManager.Type.GOLD,
	"steel": ResourceManager.Type.STEEL,
	"oil": ResourceManager.Type.OIL,
	"wood": ResourceManager.Type.WOOD,
}

# Active processes: Node3D -> {id, name, remaining, duration, produces}
var _active: Dictionary = {}

func get_processes_for(building_id: String) -> Array:
	return GameConfig.get_processes_for(building_id)

func get_mining_info(deposit_id: String) -> Dictionary:
	return GameConfig.get_mining_info(deposit_id)

func is_busy(node: Node3D) -> bool:
	return _active.has(node)

func cancel(node: Node3D) -> void:
	_active.erase(node)

func get_active(node: Node3D) -> Dictionary:
	return _active.get(node, {})

func get_progress(node: Node3D) -> float:
	if not _active.has(node):
		return 0.0
	var info: Dictionary = _active[node]
	return clampf(1.0 - (info["remaining"] / info["duration"]), 0.0, 1.0)

func start_process(node: Node3D, process: Dictionary) -> bool:
	if _active.has(node):
		return false
	if process.has("cost") and not process["cost"].is_empty():
		var cost := _convert_cost(process["cost"])
		if not ResourceManager.can_afford(cost):
			return false
		ResourceManager.spend_cost(cost)
	_active[node] = {
		"id": process["id"],
		"name": Tr.t(process["name"]),
		"remaining": process["duration"],
		"duration": process["duration"],
		"produces": process["produces"],
	}
	EventBus.process_started.emit(node, process["id"])
	return true

func start_mining(node: Node3D, deposit_id: String) -> bool:
	if _active.has(node):
		return false
	if not GameConfig.is_deposit_unlocked(deposit_id):
		return false
	var data := get_mining_info(deposit_id)
	if data.is_empty():
		return false
	_active[node] = {
		"id": data["id"],
		"name": Tr.t(data["name"]),
		"remaining": data["duration"],
		"duration": data["duration"],
		"produces": data["produces"],
	}
	EventBus.mining_started.emit(node, deposit_id)
	return true

func _process(delta: float) -> void:
	var completed: Array = []
	for node in _active:
		if not is_instance_valid(node):
			completed.append(node)
			continue
		_active[node]["remaining"] -= delta
		if _active[node]["remaining"] <= 0.0:
			completed.append(node)
	for node in completed:
		_complete(node)

func _complete(node: Node3D) -> void:
	var info: Dictionary = _active[node]
	for res_name in info["produces"]:
		if _type_map.has(res_name):
			ResourceManager.add(_type_map[res_name], info["produces"][res_name])
			if is_instance_valid(node):
				FloatingText.spawn_resource(get_tree(), node.global_position, info["produces"][res_name], res_name)
	var pid: String = info["id"]
	_active.erase(node)
	if is_instance_valid(node):
		if pid.begins_with("mine_"):
			EventBus.mining_completed.emit(node, pid)
		else:
			EventBus.process_completed.emit(node, pid)

func _convert_cost(cost_dict: Dictionary) -> Dictionary:
	var result := {}
	for res_name in cost_dict:
		if _type_map.has(res_name):
			result[_type_map[res_name]] = cost_dict[res_name]
	return result

# ── Save/Load ──

func get_save_data() -> Array:
	var result: Array = []
	for node in _active:
		if not is_instance_valid(node):
			continue
		var info: Dictionary = _active[node]
		var binfo := GridManager.get_building_info(node)
		if not binfo.is_empty():
			result.append({
				"cell_x": (binfo["origin_cell"] as Vector2i).x,
				"cell_y": (binfo["origin_cell"] as Vector2i).y,
				"id": info["id"],
				"name": info["name"],
				"remaining": info["remaining"],
				"duration": info["duration"],
				"produces": info["produces"],
			})
		elif node.has_meta("cell"):
			var cell: Vector2i = node.get_meta("cell")
			result.append({
				"cell_x": cell.x,
				"cell_y": cell.y,
				"id": info["id"],
				"name": info["name"],
				"remaining": info["remaining"],
				"duration": info["duration"],
				"produces": info["produces"],
				"is_deposit": true,
			})
	return result

func load_save_data(data: Array) -> void:
	for entry in data:
		var cell := Vector2i(entry["cell_x"], entry["cell_y"])
		var node := GridManager.get_building_at(cell)
		if not node or not is_instance_valid(node):
			continue
		_active[node] = {
			"id": entry["id"],
			"name": entry["name"],
			"remaining": entry["remaining"],
			"duration": entry["duration"],
			"produces": entry["produces"],
		}

