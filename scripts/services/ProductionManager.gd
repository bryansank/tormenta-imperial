extends Node
## Manages passive resource production from buildings and construction timers.
## Buildings with build_time > 0 go through construction before producing.
## Spawns floating text when resources are awarded.

# Construction tracking: Node3D -> {remaining: float, duration: float}
var _constructing: Dictionary = {}
# Production tracking: Node3D -> {timer: float, data: BuildingData}
var _producing: Dictionary = {}


func _ready() -> void:
	EventBus.building_placed.connect(_on_building_placed)

# ── Registration ──

func _on_building_placed(data: Resource, cell: Vector2i) -> void:
	var building_data := data as BuildingData
	var node := GridManager.get_building_at(cell)
	if not node:
		return
	var build_time := GameConfig.get_build_time(building_data.build_time)
	if build_time > 0.0:
		_start_construction(node, building_data, build_time)
	else:
		_register_producer(node, building_data)

## Called by GameManager when loading saved buildings.
func register_building(node: Node3D, data: BuildingData, construction_remaining := 0.0) -> void:
	if construction_remaining > 0.0:
		var total_duration := GameConfig.get_build_time(data.build_time)
		_constructing[node] = {
			"remaining": minf(construction_remaining, total_duration),
			"duration": total_duration,
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

func _start_construction(node: Node3D, data: BuildingData, duration: float = -1.0) -> void:
	var dur := duration if duration > 0.0 else GameConfig.get_build_time(data.build_time)
	_constructing[node] = {
		"remaining": dur,
		"duration": dur,
	}
	node.set_meta("under_construction", true)
	_apply_construction_visual(node)
	EventBus.construction_started.emit(node)

func _apply_construction_visual(node: Node3D) -> void:
	var mesh_inst := node.get_child(0)
	if mesh_inst is MeshInstance3D:
		var mat: StandardMaterial3D = mesh_inst.get_surface_override_material(0)
		if mat:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color.a = 0.35
	if not node.get_node_or_null("ConstructionLabel"):
		var data_info := GridManager.get_building_info(node)
		var height: float = 1.5
		if not data_info.is_empty():
			height = (data_info["data"] as BuildingData).mesh_height
		var label := Label3D.new()
		label.name = "ConstructionLabel"
		label.text = Tr.t("FMT_CONSTRUCTING") % [0]
		label.font_size = 18
		label.position.y = height + 0.7
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color(1.0, 0.8, 0.2, 0.9)
		label.outline_size = 4
		node.add_child(label)

func _complete_construction(node: Node3D) -> void:
	var constr_info: Dictionary = _constructing.get(node, {})
	var is_upgrade: bool = constr_info.get("is_upgrade", false)
	var new_level: int = constr_info.get("new_level", 1)
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
	var label: Node = node.get_node_or_null("ConstructionLabel")
	if label:
		label.queue_free()
	if is_upgrade:
		node.set_meta("level", new_level)
		# Scale up mesh slightly per level
		if mesh_inst is MeshInstance3D:
			var s := 1.0 + (new_level - 1) * 0.1
			mesh_inst.scale = Vector3(s, s, s)
		FloatingText.spawn(get_tree(), node.global_position, Tr.t("LBL_UPGRADE_COMPLETE"), Color(0.3, 0.8, 1.0))
		EventBus.building_upgrade_completed.emit(node, new_level)
		var binfo := GridManager.get_building_info(node)
		if not binfo.is_empty():
			EventBus.notification_posted.emit(Tr.t("NOTIF_UPGRADE_DONE") % [(binfo["data"] as BuildingData).display_name, new_level], "info", Color(0.3, 0.8, 1.0))
	else:
		FloatingText.spawn(get_tree(), node.global_position, Tr.t("FMT_CONSTRUCTION_COMPLETE"), Color(0.3, 1.0, 0.3))
		EventBus.construction_completed.emit(node)
		var binfo := GridManager.get_building_info(node)
		if not binfo.is_empty():
			EventBus.notification_posted.emit(Tr.t("NOTIF_BUILT") % (binfo["data"] as BuildingData).display_name, "info", Color(0.3, 1.0, 0.3))
	# Register for production
	var info := GridManager.get_building_info(node)
	if not info.is_empty():
		_register_producer(node, info["data"])

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
		var label: Node = node.get_node_or_null("ConstructionLabel")
		if label:
			var fmt_key := "FMT_UPGRADING" if _constructing[node].get("is_upgrade", false) else "FMT_CONSTRUCTING"
			label.text = Tr.t(fmt_key) % [int(progress * 100)]
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
		var interval := GameConfig.get_production_interval(data.production_interval)
		if interval > 0.0 and _producing[node]["timer"] >= interval:
			_producing[node]["timer"] -= interval
			_award_production(node, data)
	for node in to_remove:
		_producing.erase(node)

func _award_production(node: Node3D, data: BuildingData) -> void:
	# Skip if building is not staffed (no workers assigned)
	if data.workers_required > 0 and not PopulationManager.is_building_staffed(node):
		return
	var pos := node.global_position
	var level: int = node.get_meta("level", 1)
	var morale_mult := PopulationManager.get_morale_multiplier()
	var base_mult := GameConfig.get_production_multiplier(level) + GameConfig.tech_production_bonus
	var mult := base_mult * morale_mult
	var offset := 0.0
	if data.produces_gold > 0:
		var amount := int(data.produces_gold * mult)
		ResourceManager.add(ResourceManager.Type.GOLD, amount)
		FloatingText.spawn_resource(get_tree(), pos + Vector3(offset, 0, 0), amount, "gold")
		offset += 0.3
	if data.produces_steel > 0:
		var amount := int(data.produces_steel * mult)
		ResourceManager.add(ResourceManager.Type.STEEL, amount)
		FloatingText.spawn_resource(get_tree(), pos + Vector3(offset, 0, 0), amount, "steel")
		offset += 0.3
	if data.produces_oil > 0:
		var amount := int(data.produces_oil * mult)
		ResourceManager.add(ResourceManager.Type.OIL, amount)
		FloatingText.spawn_resource(get_tree(), pos + Vector3(offset, 0, 0), amount, "oil")
		offset += 0.3
	if data.produces_wood > 0:
		var amount := int(data.produces_wood * mult)
		ResourceManager.add(ResourceManager.Type.WOOD, amount)
		FloatingText.spawn_resource(get_tree(), pos + Vector3(offset, 0, 0), amount, "wood")
	EventBus.production_tick.emit(node)

## Start upgrade on a building (reuses construction system)
func start_upgrade(node: Node3D, data: BuildingData, new_level: int) -> void:
	var cost := GameConfig.get_upgrade_cost(data, new_level)
	if not ResourceManager.can_afford(cost):
		return
	ResourceManager.spend_cost(cost)
	var dur := GameConfig.get_upgrade_duration(new_level)
	_producing.erase(node)
	_constructing[node] = {
		"remaining": dur,
		"duration": dur,
		"is_upgrade": true,
		"new_level": new_level,
	}
	node.set_meta("under_construction", true)
	_apply_construction_visual(node)
	EventBus.building_upgrade_started.emit(node, new_level)

# ── Offline Progression ──

func apply_offline_progression(elapsed: float) -> Dictionary:
	elapsed = minf(elapsed, GameConfig.max_offline_seconds)
	var earnings := {}
	var morale_mult := PopulationManager.get_morale_multiplier()

	var existing_producers: Array = _producing.keys().duplicate()

	var to_complete: Array = []
	for node in _constructing.keys():
		if not is_instance_valid(node):
			continue
		var remaining: float = _constructing[node]["remaining"]
		if elapsed >= remaining:
			to_complete.append({"node": node, "leftover": elapsed - remaining})
		else:
			_constructing[node]["remaining"] -= elapsed
			var progress := get_construction_progress(node)
			var label: Node = node.get_node_or_null("ConstructionLabel")
			if label:
				label.text = Tr.t("FMT_CONSTRUCTING") % int(progress * 100)

	for entry in to_complete:
		var node: Node3D = entry["node"]
		var leftover: float = entry["leftover"]
		var info := GridManager.get_building_info(node)
		_complete_construction(node)
		if not info.is_empty():
			var data: BuildingData = info["data"]
			if data.is_producer():
				var interval := GameConfig.get_production_interval(data.production_interval)
				if interval > 0.0:
					var cycles := int(leftover / interval)
					_accumulate_earnings(earnings, data, cycles, morale_mult)

	for node in existing_producers:
		if not is_instance_valid(node):
			continue
		if not _producing.has(node):
			continue
		var data: BuildingData = _producing[node]["data"]
		var level: int = node.get_meta("level", 1)
		var level_mult := GameConfig.get_production_multiplier(level)
		var interval := GameConfig.get_production_interval(data.production_interval)
		if interval > 0.0:
			var cycles := int(elapsed / interval)
			_accumulate_earnings(earnings, data, cycles, morale_mult * level_mult)

	# Deduct population consumption (each pop consumes 1 gold + 1 wood per consumption tick)
	var pop := PopulationManager.get_population()
	if pop > 0:
		var cons_interval := GameConfig.get_duration(GameConfig.consumption_interval)
		if cons_interval > 0.0:
			var cons_ticks := int(elapsed / cons_interval)
			var gold_consumed := pop * cons_ticks
			var wood_consumed := pop * cons_ticks
			earnings["gold"] = earnings.get("gold", 0) - gold_consumed
			earnings["wood"] = earnings.get("wood", 0) - wood_consumed

	for res_name in earnings:
		var type = _res_to_type(res_name)
		if type == -1:
			continue
		if earnings[res_name] > 0:
			ResourceManager.add(type, earnings[res_name])
		elif earnings[res_name] < 0:
			var current := ResourceManager.get_amount(type)
			ResourceManager.spend(type, mini(absi(earnings[res_name]), current))

	return earnings

func _accumulate_earnings(earnings: Dictionary, data: BuildingData, cycles: int, mult: float = 1.0) -> void:
	if cycles <= 0:
		return
	if data.produces_gold > 0:
		earnings["gold"] = earnings.get("gold", 0) + int(data.produces_gold * mult) * cycles
	if data.produces_steel > 0:
		earnings["steel"] = earnings.get("steel", 0) + int(data.produces_steel * mult) * cycles
	if data.produces_oil > 0:
		earnings["oil"] = earnings.get("oil", 0) + int(data.produces_oil * mult) * cycles
	if data.produces_wood > 0:
		earnings["wood"] = earnings.get("wood", 0) + int(data.produces_wood * mult) * cycles

func _res_to_type(res_name: String) -> int:
	match res_name:
		"gold": return ResourceManager.Type.GOLD
		"steel": return ResourceManager.Type.STEEL
		"oil": return ResourceManager.Type.OIL
		"wood": return ResourceManager.Type.WOOD
	return -1
