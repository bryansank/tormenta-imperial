extends Node
## Manages population, workers, morale, and resource consumption.
## Population lives in houses. Workers are assigned to production buildings.
## Population consumes resources each tick. Low supply = morale drop.

# ── Population ──
var _population: int = GameConfig.population_start
var _max_population: int = GameConfig.population_start
var _used_workers := 0

# ── Morale ──
var _morale: int = GameConfig.morale_start
var _morale_bonus := 0

# ── Timers ──
var _consumption_timer := 0.0
var _growth_timer := 0.0
var _notif_cooldown := 0.0  # Prevent notification spam

func _ready() -> void:
	EventBus.construction_completed.connect(_on_building_completed)
	EventBus.building_demolished.connect(_on_building_demolished)
	EventBus.building_upgrade_completed.connect(_on_upgrade_completed)

func _process(delta: float) -> void:
	if _notif_cooldown > 0.0:
		_notif_cooldown -= delta

	# Consumption tick
	var cons_interval := GameConfig.get_duration(GameConfig.consumption_interval)
	_consumption_timer += delta
	if _consumption_timer >= cons_interval:
		_consumption_timer -= cons_interval
		_tick_consumption()

	# Population growth
	var grow_interval := GameConfig.get_duration(GameConfig.growth_interval)
	_growth_timer += delta
	if _growth_timer >= grow_interval:
		_growth_timer -= grow_interval
		_tick_growth()

# ── Public API ──

func get_population() -> int:
	return _population

func get_max_population() -> int:
	return _max_population

func get_free_workers() -> int:
	return maxi(0, _population - _used_workers)

func get_used_workers() -> int:
	return _used_workers

func get_morale() -> int:
	return _morale

func get_morale_multiplier() -> float:
	# 100 morale = 1.2x production, 50 = 1.0x, 0 = 0.5x
	return clampf(0.5 + (_morale / 100.0) * 0.7, 0.5, 1.2)

func remove_population(amount: int) -> void:
	_population = maxi(0, _population - amount)
	EventBus.population_changed.emit(_population, _max_population)

func adjust_morale(delta: int) -> void:
	_adjust_morale(delta)

# ── Consumption ──

func _tick_consumption() -> void:
	if _population <= 0:
		return
	# Each pop unit consumes 1 wood and 1 gold per tick
	var wood_needed: int = _population
	var gold_needed: int = _population

	var wood_ok := ResourceManager.has_enough(ResourceManager.Type.WOOD, wood_needed)
	var gold_ok := ResourceManager.has_enough(ResourceManager.Type.GOLD, gold_needed)

	if wood_ok:
		ResourceManager.spend(ResourceManager.Type.WOOD, wood_needed)
	else:
		var available := ResourceManager.get_amount(ResourceManager.Type.WOOD)
		if available > 0:
			ResourceManager.spend(ResourceManager.Type.WOOD, available)
		EventBus.consumption_failed.emit("wood")
		if _notif_cooldown <= 0.0:
			EventBus.notification_posted.emit(Tr.t("NOTIF_NO_WOOD"), "warning", Color(0.9, 0.6, 0.2))
			_notif_cooldown = 10.0

	if gold_ok:
		ResourceManager.spend(ResourceManager.Type.GOLD, gold_needed)
	else:
		var available := ResourceManager.get_amount(ResourceManager.Type.GOLD)
		if available > 0:
			ResourceManager.spend(ResourceManager.Type.GOLD, available)
		EventBus.consumption_failed.emit("gold")
		if _notif_cooldown <= 0.0:
			EventBus.notification_posted.emit(Tr.t("NOTIF_NO_GOLD"), "warning", Color(0.9, 0.6, 0.2))
			_notif_cooldown = 10.0

	# Morale adjustments
	if wood_ok and gold_ok:
		_adjust_morale(GameConfig.morale_satisfied_recovery)
	else:
		_adjust_morale(GameConfig.morale_unsatisfied_penalty)

func _adjust_morale(delta: int) -> void:
	var old := _morale
	_morale = clampi(_morale + delta + _get_decoration_morale_rate(), GameConfig.morale_min, GameConfig.morale_max)
	if _morale != old:
		EventBus.morale_changed.emit(_morale)
		if _morale <= GameConfig.morale_danger_threshold and old > GameConfig.morale_danger_threshold:
			EventBus.notification_posted.emit(Tr.t("NOTIF_LOW_MORALE"), "danger", Color(0.9, 0.3, 0.2))

func _get_decoration_morale_rate() -> int:
	# Decorations add +1 morale per tick for every 10 points of bonus
	return _morale_bonus / 10

# ── Growth ──

func _tick_growth() -> void:
	if _population >= _max_population:
		return
	if _morale < GameConfig.morale_growth_threshold:
		return  # Too unhappy to grow
	# Grow 1 pop if morale is decent
	_population = mini(_population + 1, _max_population)
	EventBus.population_changed.emit(_population, _max_population)
	EventBus.notification_posted.emit(Tr.t("NOTIF_POP_GREW") % [_population, _max_population], "info", Color(0.4, 0.8, 0.4))

# ── Building Events ──

func _on_building_completed(node: Node3D) -> void:
	_recalculate_all()

func _on_building_demolished(_node: Node3D, _cell: Vector2i) -> void:
	_recalculate_all()

func _on_upgrade_completed(_node: Node3D, _new_level: int) -> void:
	_recalculate_all()

func _recalculate_all() -> void:
	var old_max := _max_population
	var old_workers := _used_workers
	_max_population = 0
	_used_workers = 0
	_morale_bonus = 0

	# First pass: count capacity and morale
	var buildings_needing_workers: Array = []
	for info in GridManager.get_all_buildings():
		var data: BuildingData = info["data"]
		var node: Node3D = info.get("node", null)
		# Skip buildings under construction
		if node and node is Node3D and node.has_meta("under_construction"):
			if node.has_meta("staffed"):
				node.remove_meta("staffed")
			continue
		_max_population += data.population_capacity
		_morale_bonus += data.morale_bonus
		if data.workers_required > 0:
			buildings_needing_workers.append({"node": node, "data": data})

	# Clamp population to max
	_population = mini(_population, _max_population)

	# Second pass: assign workers with priority (first built = first served)
	var remaining_workers := _population
	for entry in buildings_needing_workers:
		var node: Node3D = entry["node"]
		var data: BuildingData = entry["data"]
		if remaining_workers >= data.workers_required:
			remaining_workers -= data.workers_required
			_used_workers += data.workers_required
			if node and is_instance_valid(node):
				node.set_meta("staffed", true)
				_update_worker_visual(node, true)
		else:
			if node and is_instance_valid(node):
				node.set_meta("staffed", false)
				_update_worker_visual(node, false)

	if _max_population != old_max:
		EventBus.population_changed.emit(_population, _max_population)
	if _used_workers != old_workers:
		EventBus.workers_changed.emit(_used_workers, _population)

## Check if a specific building node is staffed (has enough workers assigned).
func is_building_staffed(node: Node3D) -> bool:
	return node.get_meta("staffed", true)

## Update the visual indicator on a building for worker status.
func _update_worker_visual(node: Node3D, staffed: bool) -> void:
	var indicator: Node = node.get_node_or_null("WorkerIndicator")
	if staffed:
		if indicator:
			indicator.queue_free()
	else:
		if not indicator:
			var label := Label3D.new()
			label.name = "WorkerIndicator"
			label.text = Tr.t("LBL_NO_WORKERS_SHORT")
			label.font_size = 36
			label.pixel_size = 0.01
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.no_depth_test = true
			label.outline_size = 8
			label.outline_modulate = Color(0, 0, 0, 0.8)
			label.modulate = Color(1.0, 0.3, 0.2, 0.9)
			var info := GridManager.get_building_info(node)
			var height := 1.5
			if not info.is_empty():
				height = (info["data"] as BuildingData).mesh_height
			label.position.y = height + 1.2
			node.add_child(label)

func has_enough_workers(data: BuildingData) -> bool:
	return get_free_workers() >= data.workers_required

# ── Save/Load ──

func get_save_data() -> Dictionary:
	return {
		"population": _population,
		"morale": _morale,
	}

func load_save_data(data: Dictionary) -> void:
	_population = data.get("population", GameConfig.population_start)
	_morale = data.get("morale", GameConfig.morale_start)
	_recalculate_all()

func reset() -> void:
	_population = GameConfig.population_start
	_max_population = GameConfig.population_start
	_used_workers = 0
	_morale = GameConfig.morale_start
	_morale_bonus = 0
	_consumption_timer = 0.0
	_growth_timer = 0.0
