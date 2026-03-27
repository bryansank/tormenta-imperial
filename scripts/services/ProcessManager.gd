extends Node
## Manages timed processes for buildings and mining for deposits.
## Holds process/mining definitions and tracks active timers.

# Process definitions per building type
const BUILDING_PROCESSES := {
	"nucleo": [
		{"id": "wood_planks", "name": "Láminas de Madera", "duration": 30.0,
		 "cost": {"wood": 20}, "produces": {"wood": 50}},
		{"id": "iron_sheets", "name": "Láminas de Hierro", "duration": 45.0,
		 "cost": {"steel": 30}, "produces": {"steel": 70}},
		{"id": "water_pipes", "name": "Tubos de Agua", "duration": 60.0,
		 "cost": {"steel": 20, "wood": 10}, "produces": {"gold": 100}},
	],
}

# Mining yields per deposit type
const MINING_DATA := {
	"gold_vein": {"id": "mine_gold", "name": "Minar Oro", "duration": 15.0, "produces": {"gold": 25}},
	"iron_deposit": {"id": "mine_iron", "name": "Minar Hierro", "duration": 20.0, "produces": {"steel": 20}},
	"oil_well": {"id": "mine_oil", "name": "Extraer Petróleo", "duration": 25.0, "produces": {"oil": 15}},
	"forest": {"id": "mine_wood", "name": "Talar Árboles", "duration": 10.0, "produces": {"wood": 30}},
}

var _type_map := {
	"gold": ResourceManager.Type.GOLD,
	"steel": ResourceManager.Type.STEEL,
	"oil": ResourceManager.Type.OIL,
	"wood": ResourceManager.Type.WOOD,
}

# Active processes: Node3D → {id, name, remaining, duration, produces}
var _active: Dictionary = {}

func get_processes_for(building_id: String) -> Array:
	return BUILDING_PROCESSES.get(building_id, [])

func get_mining_info(deposit_id: String) -> Dictionary:
	return MINING_DATA.get(deposit_id, {})

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
		"name": process["name"],
		"remaining": process["duration"],
		"duration": process["duration"],
		"produces": process["produces"],
	}
	EventBus.process_started.emit(node, process["id"])
	return true

func start_mining(node: Node3D, deposit_id: String) -> bool:
	if _active.has(node):
		return false
	var data := get_mining_info(deposit_id)
	if data.is_empty():
		return false
	_active[node] = {
		"id": data["id"],
		"name": data["name"],
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

var _res_colors := {
	"gold": Color(1.0, 0.85, 0.1),
	"steel": Color(0.7, 0.75, 0.8),
	"oil": Color(0.5, 0.4, 0.6),
	"wood": Color(0.55, 0.35, 0.15),
}

func _complete(node: Node3D) -> void:
	var info: Dictionary = _active[node]
	# Award produced resources with floating text
	for res_name in info["produces"]:
		if _type_map.has(res_name):
			ResourceManager.add(_type_map[res_name], info["produces"][res_name])
			if is_instance_valid(node):
				_spawn_floating_text(node.global_position, "+%d %s" % [info["produces"][res_name], _translate_res(res_name)], _res_colors.get(res_name, Color.WHITE))
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

func _translate_res(res_name: String) -> String:
	match res_name:
		"gold": return "oro"
		"steel": return "acero"
		"oil": return "petroleo"
		"wood": return "madera"
	return res_name

func _spawn_floating_text(world_pos: Vector3, text: String, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 20
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 3
	label.modulate = color
	label.global_position = world_pos + Vector3(randf_range(-0.3, 0.3), 2.5, randf_range(-0.3, 0.3))
	get_tree().current_scene.add_child(label)
	var tween := create_tween()
	tween.tween_property(label, "global_position:y", world_pos.y + 5.0, 1.8).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 1.8).set_delay(0.4)
	tween.tween_callback(label.queue_free)
