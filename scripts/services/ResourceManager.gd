extends Node
## Manages game resources: gold, steel, oil, wood.
## All changes emit signals through EventBus for UI and other systems to react.
##
## Storage is a SINGLE shared pool for all four resources, not a cap per resource:
## the cap scales with the current era and with every warehouse standing. Storing
## gold means not storing steel, which is what makes the market worth using and
## makes spending before the Storm the right play. Anything that does not fit is
## lost, and the player is told the first time it happens.

enum Type { GOLD, STEEL, OIL, WOOD }

var _resources: Dictionary = {
	Type.GOLD: 300,
	Type.STEEL: 0,
	Type.OIL: 0,
	Type.WOOD: 200,
}

var _names: Dictionary = {
	Type.GOLD: "gold",
	Type.STEEL: "steel",
	Type.OIL: "oil",
	Type.WOOD: "wood",
}

var _unlocked: Dictionary = {
	Type.GOLD: true,
	Type.STEEL: false,
	Type.OIL: false,
	Type.WOOD: true,
}

var _warehouse_count := 0

## The era is owned by ProgressionManager, but ResourceManager loads long before it
## (autoload #6 vs #10). Instead of reaching for a service that may not exist yet, we
## keep our own copy: EventBus tells us when the era advances, and GameManager sets it
## explicitly when restoring a save (where the era changes without a signal).
var _era := 1

## The "you are losing harvest" warning fires once per game, not on every tick.
var _overflow_warned := false

func _ready() -> void:
	EventBus.era_advanced.connect(_on_era_advanced)

func _on_era_advanced(new_era: int) -> void:
	_era = new_era

## Set from the save-load path, where the era is restored without emitting a signal.
func set_era(era: int) -> void:
	_era = maxi(1, era)

func get_era() -> int:
	return _era

func is_unlocked(type: Type) -> bool:
	return _unlocked.get(type, false)

func is_unlocked_by_name(res_name: String) -> bool:
	var type := name_to_type(res_name)
	if type == -1:
		return false
	return _unlocked.get(type, false)

func unlock(type: Type) -> void:
	if _unlocked.get(type, false):
		return
	_unlocked[type] = true
	EventBus.resource_unlocked.emit(_names[type])

func name_to_type(res_name: String) -> int:
	for type in _names:
		if _names[type] == res_name:
			return type
	return -1

func get_amount(type: Type) -> int:
	return _resources.get(type, 0)

func get_type_name(type: Type) -> String:
	return _names.get(type, "unknown")

func get_storage_cap() -> int:
	return GameConfig.get_storage_cap(_warehouse_count, _era)

## Everything stored, across all four resources: this is what competes for the cap.
func get_total_stored() -> int:
	var total := 0
	for type in _resources:
		total += int(_resources[type])
	return total

## Room left in the shared pool. Never negative, even right after a cap drop.
func get_free_space() -> int:
	return maxi(0, get_storage_cap() - get_total_stored())

func is_storage_full() -> bool:
	return get_free_space() <= 0

func set_warehouse_count(count: int) -> void:
	_warehouse_count = maxi(0, count)

func get_warehouse_count() -> int:
	return _warehouse_count

func has_enough(type: Type, amount: int) -> bool:
	return _resources.get(type, 0) >= amount

func can_afford(cost: Dictionary) -> bool:
	for type in cost:
		if not has_enough(type, cost[type]):
			return false
	return true

func add(type: Type, amount: int) -> int:
	var current: int = _resources.get(type, 0)
	if amount <= 0:
		# Losses and no-ops do not compete for room; only the floor at zero matters.
		_resources[type] = maxi(0, current + amount)
		EventBus.resource_changed.emit(_names[type], _resources[type], amount)
		return _resources[type]
	# One pool: what comes in competes with everything already inside, not with a
	# per-resource ceiling.
	var stored: int = mini(amount, get_free_space())
	var lost := amount - stored
	_resources[type] = current + stored
	# Emitted even when stored is 0 so the HUD repaints the counter red on a full bag.
	EventBus.resource_changed.emit(_names[type], _resources[type], stored)
	if lost > 0:
		_report_overflow(type, lost)
	return _resources[type]

func _report_overflow(type: Type, lost: int) -> void:
	EventBus.storage_overflow.emit(_names[type], lost, get_storage_cap())
	if _overflow_warned:
		return
	_overflow_warned = true
	EventBus.notification_posted.emit(
		Tr.t("NOTIF_STORAGE_FULL") % [lost, Tr.res_name(_names[type])],
		"danger", Color(0.9, 0.35, 0.25)
	)

func spend(type: Type, amount: int) -> bool:
	if not has_enough(type, amount):
		EventBus.resources_insufficient.emit(_names[type], amount, _resources.get(type, 0))
		return false
	_resources[type] = maxi(0, _resources[type] - amount)
	EventBus.resource_changed.emit(_names[type], _resources[type], -amount)
	return true

func spend_cost(cost: Dictionary) -> bool:
	if not can_afford(cost):
		for type in cost:
			if not has_enough(type, cost[type]):
				EventBus.resources_insufficient.emit(_names[type], cost[type], _resources.get(type, 0))
		return false
	for type in cost:
		_resources[type] = maxi(0, _resources[type] - cost[type])
		EventBus.resource_changed.emit(_names[type], _resources[type], -cost[type])
	return true

func get_all() -> Dictionary:
	return _resources.duplicate()

func get_unlocked_types() -> Array:
	var result: Array = []
	for type in _unlocked:
		if _unlocked[type]:
			result.append(type)
	return result

func get_unlock_state() -> Dictionary:
	var result := {}
	for type in _names:
		result[_names[type]] = _unlocked[type]
	return result

func set_unlock_state(state: Dictionary) -> void:
	for res_name in state:
		var type := name_to_type(res_name)
		if type != -1:
			_unlocked[type] = state[res_name]

func reset() -> void:
	var cfg := GameConfig.starting_resources
	_resources = {
		Type.GOLD: cfg.get("gold", 300),
		Type.STEEL: cfg.get("steel", 0),
		Type.OIL: cfg.get("oil", 0),
		Type.WOOD: cfg.get("wood", 200),
	}
	_unlocked = {
		Type.GOLD: true,
		Type.STEEL: false,
		Type.OIL: false,
		Type.WOOD: true,
	}
	_warehouse_count = 0
	_era = 1
	_overflow_warned = false
	for type in _resources:
		EventBus.resource_changed.emit(_names[type], _resources[type], 0)

func set_amounts(data: Dictionary) -> void:
	# A freshly loaded game gets its overflow warning back: the first loss of the
	# session still has to be visible.
	_overflow_warned = false
	var name_to_type := {}
	for type in _names:
		name_to_type[_names[type]] = type
	for res_name in data:
		if name_to_type.has(res_name):
			var type: Type = name_to_type[res_name]
			# Repair any negative value that may have been saved before this guard existed.
			_resources[type] = maxi(0, int(data[res_name]))
			EventBus.resource_changed.emit(res_name, _resources[type], 0)

## Trims the pool down to the current cap, keeping each resource's share of what
## there was. Needed when loading a save written while the cap was per-resource: a
## veteran could have 800 of each, and 3200 no longer fits anywhere.
##
## The cut is proportional on purpose. Emptying whatever the dictionary happened to
## list first would be a balance decision taken by iteration order — it could wipe a
## player's entire oil and leave their gold untouched. Proportional keeps the shape
## of what they built. Returns true if anything was actually taken.
func clamp_to_storage() -> bool:
	var cap := get_storage_cap()
	var total := get_total_stored()
	if total <= cap:
		return false
	var trimmed := {}
	var assigned := 0
	for type in _resources:
		var share: int = int(float(_resources[type]) * float(cap) / float(total))
		trimmed[type] = share
		assigned += share
	# Truncating leaves crumbs unassigned (at most one per resource). They go to the
	# most abundant ones, which are the ones the split shortchanged the most.
	var order: Array = _resources.keys()
	order.sort_custom(func(a, b): return int(_resources[a]) > int(_resources[b]))
	var leftover := cap - assigned
	for type in order:
		if leftover <= 0:
			break
		trimmed[type] = int(trimmed[type]) + 1
		leftover -= 1
	for type in trimmed:
		var before: int = _resources[type]
		var after: int = int(trimmed[type])
		if after == before:
			continue
		_resources[type] = after
		EventBus.resource_changed.emit(_names[type], after, after - before)
	EventBus.notification_posted.emit(
		Tr.t("NOTIF_STORAGE_TRIMMED") % [total - cap, cap],
		"warning", Color(0.85, 0.55, 0.2)
	)
	return true
