extends Node
## Manages passive resource production from buildings and construction timers.
## Buildings with build_time > 0 go through construction before producing.
## Spawns floating text when resources are awarded.

# Construction tracking: Node3D → {remaining: float, duration: float}
var _constructing: Dictionary = {}
# Production tracking: Node3D → {timer: float, data: BuildingData}
var _producing: Dictionary = {}

var _res_colors := {
	"gold": Color(1.0, 0.85, 0.1),
	"steel": Color(0.7, 0.75, 0.8),
	"oil": Color(0.5, 0.4, 0.6),
	"wood": Color(0.55, 0.35, 0.15),
}

func _ready() -> void:
	EventBus.building_placed.connect(_on_building_placed)

# ── Registration ──

func _on_building_placed(data: Resource, cell: Vector2i) -> void:
	var building_data := data as BuildingData
	var node := GridManager.get_building_at(cell)
	if not node:
		return
	if building_data.build_time > 0.0:
		_start_construction(node, building_data)
	else:
		_register_producer(node, building_data)

## Called by GameManager when loading saved buildings.
func register_building(node: Node3D, data: BuildingData, construction_remaining := 0.0) -> void:
	if construction_remaining > 0.0:
		_constructing[node] = {
			"remaining": construction_remaining,
			"duration": data.build_time,
		}
		node.set_meta("under_construction", true)
		_apply_construction_visual(node)
	else:
		_register_producer(node, data)

func _register_producer(node: Node3D, data: BuildingData) -> void:
	if data.is_producer():
		_producing[node] = {"timer": 0.0, "data": data}

func unregister(node: Node3D) -> void:
	_constructing.erase(node)
	_producing.erase(node)

# ── Construction ──

func is_constructing(node: Node3D) -> bool:
	return _constructing.has(node)

func get_construction_progress(node: Node3D) -> float:
	if not _constructing.has(node):
		return 1.0
	var info: Dictionary = _constructing[node]
	if info["duration"] <= 0.0:
		return 1.0
	return clampf(1.0 - (info["remaining"] / info["duration"]), 0.0, 1.0)

func get_construction_remaining(node: Node3D) -> float:
	if not _constructing.has(node):
		return 0.0
	return _constructing[node]["remaining"]

func _start_construction(node: Node3D, data: BuildingData) -> void:
	_constructing[node] = {
		"remaining": data.build_time,
		"duration": data.build_time,
	}
	node.set_meta("under_construction", true)
	_apply_construction_visual(node)
	EventBus.construction_started.emit(node)

func _apply_construction_visual(node: Node3D) -> void:
	# Make mesh semi-transparent
	var mesh_inst := node.get_child(0)
	if mesh_inst is MeshInstance3D:
		var mat: StandardMaterial3D = mesh_inst.get_surface_override_material(0)
		if mat:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color.a = 0.35
	# Add construction label below name
	if not node.get_node_or_null("ConstructionLabel"):
		var data_info := GridManager.get_building_info(node)
		var height: float = 1.5
		if not data_info.is_empty():
			height = (data_info["data"] as BuildingData).mesh_height
		var label := Label3D.new()
		label.name = "ConstructionLabel"
		label.text = "Construyendo 0%"
		label.font_size = 18
		label.position.y = height + 0.7
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color(1.0, 0.8, 0.2, 0.9)
		label.outline_size = 4
		node.add_child(label)

func _complete_construction(node: Node3D) -> void:
	_constructing.erase(node)
	if not is_instance_valid(node):
		return
	node.remove_meta("under_construction")
	# Restore mesh opacity
	var mesh_inst := node.get_child(0)
	if mesh_inst is MeshInstance3D:
		var mat: StandardMaterial3D = mesh_inst.get_surface_override_material(0)
		if mat:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			mat.albedo_color.a = 1.0
	# Remove construction label
	var label := node.get_node_or_null("ConstructionLabel")
	if label:
		label.queue_free()
	# Spawn completion text
	_spawn_floating_text(node.global_position, "Construccion completa!", Color(0.3, 1.0, 0.3))
	# Register for production
	var info := GridManager.get_building_info(node)
	if not info.is_empty():
		_register_producer(node, info["data"])
	EventBus.construction_completed.emit(node)

# ── Production ──

func _process(delta: float) -> void:
	_tick_construction(delta)
	_tick_production(delta)

func _tick_construction(delta: float) -> void:
	var completed: Array = []
	for node in _constructing:
		if not is_instance_valid(node):
			completed.append(node)
			continue
		_constructing[node]["remaining"] -= delta
		var progress := get_construction_progress(node)
		var label := node.get_node_or_null("ConstructionLabel")
		if label:
			label.text = "Construyendo %d%%" % int(progress * 100)
		if _constructing[node]["remaining"] <= 0.0:
			completed.append(node)
	for node in completed:
		_complete_construction(node)

func _tick_production(delta: float) -> void:
	var to_remove: Array = []
	for node in _producing:
		if not is_instance_valid(node):
			to_remove.append(node)
			continue
		if node.has_meta("under_construction"):
			continue
		_producing[node]["timer"] += delta
		var data: BuildingData = _producing[node]["data"]
		if _producing[node]["timer"] >= data.production_interval:
			_producing[node]["timer"] -= data.production_interval
			_award_production(node, data)
	for node in to_remove:
		_producing.erase(node)

func _award_production(node: Node3D, data: BuildingData) -> void:
	var pos := node.global_position
	var offset := 0.0
	if data.produces_gold > 0:
		ResourceManager.add(ResourceManager.Type.GOLD, data.produces_gold)
		_spawn_floating_text(pos + Vector3(offset, 0, 0), "+%d oro" % data.produces_gold, _res_colors["gold"])
		offset += 0.3
	if data.produces_steel > 0:
		ResourceManager.add(ResourceManager.Type.STEEL, data.produces_steel)
		_spawn_floating_text(pos + Vector3(offset, 0, 0), "+%d acero" % data.produces_steel, _res_colors["steel"])
		offset += 0.3
	if data.produces_oil > 0:
		ResourceManager.add(ResourceManager.Type.OIL, data.produces_oil)
		_spawn_floating_text(pos + Vector3(offset, 0, 0), "+%d petroleo" % data.produces_oil, _res_colors["oil"])
		offset += 0.3
	if data.produces_wood > 0:
		ResourceManager.add(ResourceManager.Type.WOOD, data.produces_wood)
		_spawn_floating_text(pos + Vector3(offset, 0, 0), "+%d madera" % data.produces_wood, _res_colors["wood"])
	EventBus.production_tick.emit(node)

# ── Offline Progression ──

const MAX_OFFLINE_SECONDS := 28800.0  # 8 hours cap

## Called on load: applies elapsed time to construction and production.
## Returns dictionary of total earned resources {"gold": N, "steel": N, ...}.
func apply_offline_progression(elapsed: float) -> Dictionary:
	elapsed = minf(elapsed, MAX_OFFLINE_SECONDS)
	var earnings := {}

	# 1. Snapshot current producers before construction adds new ones
	var existing_producers: Array = _producing.keys().duplicate()

	# 2. Handle construction — complete buildings that finished offline
	var to_complete: Array = []
	for node in _constructing.keys():
		if not is_instance_valid(node):
			continue
		var remaining: float = _constructing[node]["remaining"]
		if elapsed >= remaining:
			to_complete.append({"node": node, "leftover": elapsed - remaining})
		else:
			# Still constructing but advanced
			_constructing[node]["remaining"] -= elapsed
			var progress := get_construction_progress(node)
			var label := node.get_node_or_null("ConstructionLabel")
			if label:
				label.text = "Construyendo %d%%" % int(progress * 100)

	for entry in to_complete:
		var node: Node3D = entry["node"]
		var leftover: float = entry["leftover"]
		var info := GridManager.get_building_info(node)
		_complete_construction(node)
		# Production for the time after construction finished
		if not info.is_empty():
			var data: BuildingData = info["data"]
			if data.is_producer():
				var cycles := int(leftover / data.production_interval)
				_accumulate_earnings(earnings, data, cycles)

	# 3. Production from buildings that were already operational
	for node in existing_producers:
		if not is_instance_valid(node):
			continue
		if not _producing.has(node):
			continue
		var data: BuildingData = _producing[node]["data"]
		var cycles := int(elapsed / data.production_interval)
		_accumulate_earnings(earnings, data, cycles)

	# 4. Award all resources at once
	for res_name in earnings:
		if earnings[res_name] > 0:
			var type = _res_to_type(res_name)
			if type != -1:
				ResourceManager.add(type, earnings[res_name])

	return earnings

func _accumulate_earnings(earnings: Dictionary, data: BuildingData, cycles: int) -> void:
	if cycles <= 0:
		return
	if data.produces_gold > 0:
		earnings["gold"] = earnings.get("gold", 0) + data.produces_gold * cycles
	if data.produces_steel > 0:
		earnings["steel"] = earnings.get("steel", 0) + data.produces_steel * cycles
	if data.produces_oil > 0:
		earnings["oil"] = earnings.get("oil", 0) + data.produces_oil * cycles
	if data.produces_wood > 0:
		earnings["wood"] = earnings.get("wood", 0) + data.produces_wood * cycles

func _res_to_type(res_name: String) -> int:
	match res_name:
		"gold": return ResourceManager.Type.GOLD
		"steel": return ResourceManager.Type.STEEL
		"oil": return ResourceManager.Type.OIL
		"wood": return ResourceManager.Type.WOOD
	return -1

# ── Floating Text ──

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
