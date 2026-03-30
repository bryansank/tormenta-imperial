extends Node
## Manages game resources: gold, steel, oil, wood.
## All changes emit signals through EventBus for UI and other systems to react.
## Storage caps enforced based on warehouse count.

enum Type { GOLD, STEEL, OIL, WOOD }

var _resources: Dictionary = {
	Type.GOLD: 500,
	Type.STEEL: 300,
	Type.OIL: 200,
	Type.WOOD: 400,
}

var _names: Dictionary = {
	Type.GOLD: "gold",
	Type.STEEL: "steel",
	Type.OIL: "oil",
	Type.WOOD: "wood",
}

var _warehouse_count := 0

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
	_resources[type] = mini(_resources.get(type, 0) + amount, cap)
	EventBus.resource_changed.emit(_names[type], _resources[type], amount)
	return _resources[type]

func spend(type: Type, amount: int) -> bool:
	if not has_enough(type, amount):
		EventBus.resources_insufficient.emit(_names[type], amount, _resources.get(type, 0))
		return false
	_resources[type] -= amount
	EventBus.resource_changed.emit(_names[type], _resources[type], -amount)
	return true

func spend_cost(cost: Dictionary) -> bool:
	if not can_afford(cost):
		for type in cost:
			if not has_enough(type, cost[type]):
				EventBus.resources_insufficient.emit(_names[type], cost[type], _resources.get(type, 0))
		return false
	for type in cost:
		_resources[type] -= cost[type]
		EventBus.resource_changed.emit(_names[type], _resources[type], -cost[type])
	return true

func get_all() -> Dictionary:
	return _resources.duplicate()

func reset() -> void:
	var cfg := GameConfig.starting_resources
	_resources = {
		Type.GOLD: cfg.get("gold", 500),
		Type.STEEL: cfg.get("steel", 300),
		Type.OIL: cfg.get("oil", 200),
		Type.WOOD: cfg.get("wood", 400),
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
			_resources[type] = data[res_name]
			EventBus.resource_changed.emit(res_name, data[res_name], 0)
