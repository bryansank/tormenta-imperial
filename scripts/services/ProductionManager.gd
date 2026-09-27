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
##
## `upgrade_to` > 0 dice que lo que estaba en obras era una mejora a ese nivel y
## no la construccion inicial. Sin el, una mejora a medias volvia de la carga
## como obra normal: al terminar no subia de nivel, y la del Cuartel General a
## nivel 3 —la que convoca la Auditoria Final— se perdia sin dejar rastro. Un
## save anterior a la clave llega con 0, que es lo que siempre significo.
func register_building(node: Node, data: BuildingData, construction_remaining := 0.0, upgrade_to: int = 0) -> void:
	if construction_remaining > 0.0:
		var is_upgrade: bool = upgrade_to > 1
		var total_duration := GameConfig.get_upgrade_duration(upgrade_to) if is_upgrade 				else GameConfig.get_build_time(data.build_time)
		var info := {
			"remaining": minf(construction_remaining, total_duration),
			"duration": total_duration,
		}
		if is_upgrade:
			info["is_upgrade"] = true
			info["new_level"] = upgrade_to
		_constructing[node] = info
		node.set_meta("under_construction", true)
		_apply_construction_visual(node)
	else:
		_register_producer(node, data)

## Olvida todo lo que estaba en obras y produciendo. Lo llama GameManager en los
## tres sitios que empiezan partida: los nodos de la escena anterior mueren con
## la recarga, pero este autoload sobrevive y los seguiria teniendo de clave.
## Tira, no liquida: una partida nueva no termina las obras de la vieja.
func reset() -> void:
	_constructing.clear()
	_producing.clear()

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

## El nivel al que sube una mejora en curso, o 0 si lo que hay en obras es una
## construccion (o no hay nada). Es lo que el guardado necesita para no confundir
## una cosa con la otra.
func get_upgrade_target(node: Node3D) -> int:
	if not _constructing.has(node):
		return 0
	var info: Dictionary = _constructing[node]
	if not bool(info.get("is_upgrade", false)):
		return 0
	return int(info.get("new_level", 0))

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

## Sin tipo en el parametro a proposito: una clave de `_constructing` puede ser
## un nodo ya liberado, y pasar un objeto liberado a un parametro tipado revienta
## la llamada antes de la primera linea. Entonces el erase no llegaba a correr y
## el mismo error se repetia cada fotograma. Primero se borra, despues se mira.
func _complete_construction(stale_or_node) -> void:
	var constr_info: Dictionary = _constructing.get(stale_or_node, {})
	_constructing.erase(stale_or_node)
	if not is_instance_valid(stale_or_node):
		return
	var node: Node3D = stale_or_node
	var is_upgrade: bool = constr_info.get("is_upgrade", false)
	var new_level: int = constr_info.get("new_level", 1)
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
			var s: float = 1.0 + (new_level - 1) * 0.1
			mesh_inst.scale = Vector3(s, s, s)
		FloatingText.spawn(get_tree(), node.global_position, Tr.t("LBL_UPGRADE_COMPLETE"), Color(0.3, 0.8, 1.0))
		EventBus.building_upgrade_completed.emit(node, new_level)
		var binfo := GridManager.get_building_info(node)
		if not binfo.is_empty():
			EventBus.notification_posted.emit(Tr.t("NOTIF_UPGRADE_DONE") % [(binfo["data"] as BuildingData).get_display_name(), new_level], "info", Color(0.3, 0.8, 1.0))
	else:
		FloatingText.spawn(get_tree(), node.global_position, Tr.t("FMT_CONSTRUCTION_COMPLETE"), Color(0.3, 1.0, 0.3))
		EventBus.construction_completed.emit(node)
		var binfo := GridManager.get_building_info(node)
		if not binfo.is_empty():
			EventBus.notification_posted.emit(Tr.t("NOTIF_BUILT") % (binfo["data"] as BuildingData).get_display_name(), "info", Color(0.3, 1.0, 0.3))
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
	var gone: Array = []
	for node in _constructing:
		if not is_instance_valid(node):
			gone.append(node)
			continue
		_constructing[node]["remaining"] -= delta
		var progress := get_construction_progress(node)
		var label: Node = node.get_node_or_null("ConstructionLabel")
		if label:
			var fmt_key := "FMT_UPGRADING" if _constructing[node].get("is_upgrade", false) else "FMT_CONSTRUCTING"
			label.text = Tr.t(fmt_key) % [int(progress * 100)]
		if _constructing[node]["remaining"] <= 0.0:
			completed.append(node)
	for node in gone:
		_constructing.erase(node)
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
	var produced := get_cycle_yield(node, data)
	if produced.is_empty():
		return
	var pos := node.global_position
	var offset := 0.0
	for res_name in produced:
		var amount: int = produced[res_name]
		ResourceManager.add(_res_to_type(res_name), amount)
		FloatingText.spawn_resource(get_tree(), pos + Vector3(offset, 0, 0), amount, res_name)
		offset += 0.3
	EventBus.production_tick.emit(node)

## Lo que rinde un edificio en UN ciclo ahora mismo (recurso -> cantidad). Es la
## unica formula de produccion: la usan el tic en vivo y la progresion offline,
## para que estar fuera nunca rinda distinto de estar mirando.
##
## Vacio si el edificio esta en ruinas o le faltan trabajadores. Con
## `include_events` a false se deja fuera lo pasajero (tormenta, plaga): offline
## no se simula ninguno de los dos, asi que tampoco se cobran.
func get_cycle_yield(node: Node, data: BuildingData, include_events := true) -> Dictionary:
	# A building in ruins produces nothing until it is repaired. This is what
	# gives the storm teeth beyond a bad afternoon.
	if BuildingHealth.is_ruined(node):
		return {}
	# Skip if building is not staffed (no workers assigned)
	if data.workers_required > 0 and not PopulationManager.is_building_staffed(node):
		return {}
	var level: int = node.get_meta("level", 1)
	var base_mult := GameConfig.get_production_multiplier(level) + GameConfig.tech_production_bonus
	var mult := base_mult * PopulationManager.get_morale_multiplier()
	# Temporary, event-driven penalties (the Imperial Storm, the plague) ride on
	# their own multipliers so they can be lifted cleanly. Folding them into the
	# tech bonus would mix a passing squall with permanent research.
	if include_events:
		mult *= GameConfig.get_event_production_multiplier()
	var produced := {}
	if data.produces_gold > 0:
		produced["gold"] = int(data.produces_gold * mult)
	if data.produces_steel > 0:
		produced["steel"] = int(data.produces_steel * mult)
	if data.produces_oil > 0:
		produced["oil"] = int(data.produces_oil * mult)
	if data.produces_wood > 0:
		produced["wood"] = int(data.produces_wood * mult)
	return produced

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
#
# Offline solo se produce (y se come, con tope). La tormenta, los eventos, el
# ejercito y los procesos se quedan congelados donde estaban: ver
# docs/09-save-system.md. Cada edificio rinde lo que diga get_cycle_yield(), la
# misma formula que en vivo, asi que una ruina o un edificio sin obreros tampoco
# produce estando fuera.

func apply_offline_progression(elapsed: float) -> Dictionary:
	# Reloj atrasado, NaN o infinito: no ha pasado nada que se pueda cobrar.
	if is_nan(elapsed) or elapsed <= 0.0:
		return {}
	# Un salto hacia delante sospechoso (reloj adelantado, anos de ausencia) se
	# queda en el tope de 8 h, igual que una ausencia real larga.
	elapsed = minf(elapsed, GameConfig.max_offline_seconds)
	var earnings := {}

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
				var fmt_key := "FMT_UPGRADING" if _constructing[node].get("is_upgrade", false) else "FMT_CONSTRUCTING"
				label.text = Tr.t(fmt_key) % int(progress * 100)

	# Lo que se termina estando fuera produce solo el tiempo que le sobro. Se
	# completa antes de medir: completar pone el nivel nuevo y (por la senal de
	# construccion/mejora) reparte los obreros, y el rendimiento lee las dos cosas.
	var finished: Array = []
	for entry in to_complete:
		var node: Node3D = entry["node"]
		var info := GridManager.get_building_info(node)
		_complete_construction(node)
		if not info.is_empty():
			finished.append({"node": node, "data": info["data"], "seconds": float(entry["leftover"])})
	for node in existing_producers:
		if not is_instance_valid(node) or not _producing.has(node):
			continue
		finished.append({"node": node, "data": _producing[node]["data"], "seconds": elapsed})

	for entry in finished:
		var node: Node3D = entry["node"]
		if not is_instance_valid(node):
			continue
		var data: BuildingData = entry["data"]
		if not data.is_producer():
			continue
		var interval := GameConfig.get_production_interval(data.production_interval)
		if interval <= 0.0:
			continue
		var cycles := int(float(entry["seconds"]) / interval)
		if cycles <= 0:
			continue
		var per_cycle := get_cycle_yield(node, data, false)
		for res_name in per_cycle:
			earnings[res_name] = int(earnings.get(res_name, 0)) + int(per_cycle[res_name]) * cycles

	# Population consumption while offline is capped to what was PRODUCED offline.
	# Being away can eat into your offline gains, but never into the stockpile you
	# left with — the player must never return poorer than when they closed the game.
	var pop := PopulationManager.get_population()
	if pop > 0:
		var cons_interval := GameConfig.get_duration(GameConfig.consumption_interval)
		if cons_interval > 0.0:
			var cons_ticks := int(elapsed / cons_interval)
			var reduction := GameConfig.tech_consumption_reduction
			var cons_mult := maxf(0.1, 1.0 - reduction)
			var demand := int(pop * cons_ticks * cons_mult)
			earnings["gold"] = maxi(0, earnings.get("gold", 0) - demand)
			earnings["wood"] = maxi(0, earnings.get("wood", 0) - demand)

	for res_name in earnings:
		var type = _res_to_type(res_name)
		if type == -1:
			continue
		var net: int = earnings[res_name]
		var before := ResourceManager.get_amount(type)
		if net > 0:
			ResourceManager.add(type, net)
		elif net < 0:
			# Never spend more than is available — offline losses can't go below 0.
			ResourceManager.spend(type, mini(absi(net), before))
		# Report the ACTUAL applied change (capped by storage cap / available stock),
		# not the raw theoretical net, so the offline summary never shows a resource
		# dropping below what the player actually had.
		earnings[res_name] = ResourceManager.get_amount(type) - before

	return earnings

func _res_to_type(res_name: String) -> int:
	match res_name:
		"gold": return ResourceManager.Type.GOLD
		"steel": return ResourceManager.Type.STEEL
		"oil": return ResourceManager.Type.OIL
		"wood": return ResourceManager.Type.WOOD
	return -1
