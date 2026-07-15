extends Node
## Manages game resources: gold, steel, oil, wood.
## All changes emit signals through EventBus for UI and other systems to react.
## Storage caps enforced based on warehouse count.

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
	return GameConfig.get_storage_cap(_warehouse_count)

func set_warehouse_count(count: int) -> void:
	_warehouse_count = count

func has_enough(type: Type, amount: int) -> bool:
	return _resources.get(type, 0) >= amount

func can_afford(cost: Dictionary) -> bool:
	for type in cost:
		if not has_enough(type, cost[type]):
			return false
	return true

func add(type: Type, amount: int) -> int:
	var cap := get_storage_cap()
	# Clamp to [0, cap]: never below zero, even when called with a negative amount.
	_resources[type] = clampi(_resources.get(type, 0) + amount, 0, cap)
	EventBus.resource_changed.emit(_names[type], _resources[type], amount)
	return _resources[type]

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
	for type in _resources:
		EventBus.resource_changed.emit(_names[type], _resources[type], 0)

func set_amounts(data: Dictionary) -> void:
	var name_to_type := {}
	for type in _names:
		name_to_type[_names[type]] = type
	for res_name in data:
		if name_to_type.has(res_name):
			var type: Type = name_to_type[res_name]
			# Repair any negative value that may have been saved before this guard existed.
			_resources[type] = maxi(0, int(data[res_name]))
			EventBus.resource_changed.emit(res_name, _resources[type], 0)
