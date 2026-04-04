extends Node
## Triggers random events at intervals to keep gameplay dynamic.
## Events can be positive, negative, or neutral.

var _timer := 0.0
var _next_event_time := 0.0
var _active_event: Dictionary = {}
var _active_timer := 0.0
var _events_triggered := 0

func _ready() -> void:
	_schedule_next_event()

func _process(delta: float) -> void:
	# Random events don't start until Phase 3 (Survival)
	if ProgressionManager.current_phase < GameConfig.Phase.SURVIVAL:
		return

	# Check for next event
	_timer += delta
	if _timer >= _next_event_time and _active_event.is_empty():
		_timer = 0.0
		_trigger_random_event()
		_schedule_next_event()

	# Process active event duration
	if not _active_event.is_empty():
		_active_timer -= delta
		if _active_timer <= 0.0:
			_end_active_event()

func _schedule_next_event() -> void:
	var base_min: float
	var base_max: float
	if GameConfig.dev_mode:
		base_min = GameConfig.event_interval_min_dev
		base_max = GameConfig.event_interval_max_dev
	else:
		base_min = GameConfig.event_interval_min
		base_max = GameConfig.event_interval_max
	_next_event_time = randf_range(base_min, base_max)

# ── Event Definitions ──

func _get_event_pool() -> Array:
	var pool: Array = [
		{
			"id": "storm",
			"name": "EVENT_STORM",
			"desc": "EVENT_STORM_DESC",
			"category": "danger",
			"color": Color(0.8, 0.3, 0.3),
			"weight": 15,
			"duration": 0.0,
			"effect": "_effect_storm",
		},
		{
			"id": "resource_find",
			"name": "EVENT_RESOURCE_FIND",
			"desc": "EVENT_RESOURCE_FIND_DESC",
			"category": "positive",
			"color": Color(0.3, 0.8, 0.3),
			"weight": 20,
			"duration": 0.0,
			"effect": "_effect_resource_find",
		},
		{
			"id": "mining_accident",
			"name": "EVENT_MINING_ACCIDENT",
			"desc": "EVENT_MINING_ACCIDENT_DESC",
			"category": "danger",
			"color": Color(0.9, 0.4, 0.2),
			"weight": 10,
			"duration": 0.0,
			"effect": "_effect_mining_accident",
		},
		{
			"id": "trade_caravan",
			"name": "EVENT_TRADE_CARAVAN",
			"desc": "EVENT_TRADE_CARAVAN_DESC",
			"category": "positive",
			"color": Color(0.9, 0.8, 0.2),
			"weight": 15,
			"duration": 0.0,
			"effect": "_effect_trade_caravan",
		},
		{
			"id": "morale_boost",
			"name": "EVENT_FESTIVAL",
			"desc": "EVENT_FESTIVAL_DESC",
			"category": "positive",
			"color": Color(0.5, 0.8, 1.0),
			"weight": 15,
			"duration": 0.0,
			"effect": "_effect_festival",
		},
		{
			"id": "plague",
			"name": "EVENT_PLAGUE",
			"desc": "EVENT_PLAGUE_DESC",
			"category": "danger",
			"color": Color(0.6, 0.3, 0.5),
			"weight": 8,
			"duration": 60.0,
			"effect": "_effect_plague",
		},
		{
			"id": "good_harvest",
			"name": "EVENT_GOOD_HARVEST",
			"desc": "EVENT_GOOD_HARVEST_DESC",
			"category": "positive",
			"color": Color(0.3, 0.7, 0.2),
			"weight": 18,
			"duration": 0.0,
			"effect": "_effect_good_harvest",
		},
		{
			"id": "bandit_raid",
			"name": "EVENT_BANDIT_RAID",
			"desc": "EVENT_BANDIT_RAID_DESC",
			"category": "danger",
			"color": Color(0.8, 0.2, 0.2),
			"weight": 12,
			"duration": 0.0,
			"effect": "_effect_bandit_raid",
		},
	]
	return pool

# ── Weighted Random Selection ──

func _trigger_random_event() -> void:
	var pool := _get_event_pool()
	var total_weight: int = 0
	for event in pool:
		total_weight += int(event["weight"])
	var roll: int = randi() % total_weight
	var cumulative: int = 0
	for event in pool:
		cumulative += event["weight"]
		if roll < cumulative:
			_execute_event(event)
			break

func _execute_event(event: Dictionary) -> void:
	_events_triggered += 1
	var duration: float = event.get("duration", 0.0)
	if GameConfig.dev_mode and duration > 0.0:
		duration = 10.0

	# Notify
	EventBus.notification_posted.emit(Tr.t(event["name"]) + ": " + Tr.t(event["desc"]), event["category"], event["color"])
	EventBus.random_event_started.emit(event["id"], event)

	# Apply immediate effect
	if event.has("effect"):
		call(event["effect"])

	# Track timed events
	if duration > 0.0:
		_active_event = event
		_active_timer = duration
	else:
		EventBus.random_event_ended.emit(event["id"])

func _end_active_event() -> void:
	var event_id: String = _active_event.get("id", "")
	# Reverse timed effects
	if event_id == "plague":
		EventBus.notification_posted.emit(Tr.t("EVENT_PLAGUE_OVER"), "info", Color(0.5, 0.7, 0.5))
	_active_event = {}
	_active_timer = 0.0
	EventBus.random_event_ended.emit(event_id)

# ── Effect Functions ──

func _effect_storm() -> void:
	# Lose some wood
	var loss := randi_range(20, 50)
	var available := ResourceManager.get_amount(ResourceManager.Type.WOOD)
	ResourceManager.spend(ResourceManager.Type.WOOD, mini(loss, available))

func _effect_resource_find() -> void:
	# Gain random resources
	var types := [ResourceManager.Type.GOLD, ResourceManager.Type.WOOD]
	if ResourceManager.is_unlocked(ResourceManager.Type.STEEL):
		types.append(ResourceManager.Type.STEEL)
	if ResourceManager.is_unlocked(ResourceManager.Type.OIL):
		types.append(ResourceManager.Type.OIL)
	var type: ResourceManager.Type = types[randi() % types.size()]
	var amount := randi_range(30, 80)
	ResourceManager.add(type, amount)

func _effect_mining_accident() -> void:
	# Lose population and morale
	if PopulationManager.get_population() > 2:
		PopulationManager.remove_population(1)
	PopulationManager.adjust_morale(-15)

func _effect_trade_caravan() -> void:
	# Free gold bonus
	ResourceManager.add(ResourceManager.Type.GOLD, randi_range(50, 120))

func _effect_festival() -> void:
	# Morale boost
	PopulationManager.adjust_morale(20)

func _effect_plague() -> void:
	# Immediate morale hit, production halved while active (checked by ProductionManager)
	PopulationManager.adjust_morale(-25)

func _effect_good_harvest() -> void:
	# Free wood
	ResourceManager.add(ResourceManager.Type.WOOD, randi_range(40, 80))

func _effect_bandit_raid() -> void:
	# Lose gold
	var loss := randi_range(30, 80)
	var available := ResourceManager.get_amount(ResourceManager.Type.GOLD)
	ResourceManager.spend(ResourceManager.Type.GOLD, mini(loss, available))
	PopulationManager.adjust_morale(-10)

# ── Query ──

func is_event_active(event_id: String) -> bool:
	return _active_event.get("id", "") == event_id

func has_active_event() -> bool:
	return not _active_event.is_empty()

func get_active_event() -> Dictionary:
	return _active_event

# ── Save/Load ──

func get_save_data() -> Dictionary:
	return {"events_triggered": _events_triggered}

func load_save_data(data: Dictionary) -> void:
	_events_triggered = data.get("events_triggered", 0)

func reset() -> void:
	_timer = 0.0
	_active_event = {}
	_active_timer = 0.0
	_events_triggered = 0
	_schedule_next_event()
