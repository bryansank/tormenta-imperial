extends Node
## Manages game resources: gold, steel, oil.
## All changes emit signals through EventBus for UI and other systems to react.

enum Type { GOLD, STEEL, OIL, WOOD }

# Starting amounts
var _resources: Dictionary = {
	Type.GOLD: 500,
	Type.STEEL: 300,
	Type.OIL: 200,
	Type.WOOD: 400,
}

## Human-readable names for display
var _names: Dictionary = {
	Type.GOLD: "gold",
	Type.STEEL: "steel",
	Type.OIL: "oil",
	Type.WOOD: "wood",
}

func get_amount(type: Type) -> int:
	return _resources.get(type, 0)

func get_type_name(type: Type) -> String:
	return _names.get(type, "unknown")

## Check if we have enough of a single resource.
func has_enough(type: Type, amount: int) -> bool:
	return _resources.get(type, 0) >= amount

## Check if we can afford a cost dictionary {Type: int}.
func can_afford(cost: Dictionary) -> bool:
	for type in cost:
		if not has_enough(type, cost[type]):
			return false
	return true

## Add resources (income, loot, etc). Returns new amount.
func add(type: Type, amount: int) -> int:
	_resources[type] = _resources.get(type, 0) + amount
	EventBus.resource_changed.emit(_names[type], _resources[type], amount)
	return _resources[type]

## Spend resources. Returns true if successful, false if insufficient.
func spend(type: Type, amount: int) -> bool:
	if not has_enough(type, amount):
		EventBus.resources_insufficient.emit(_names[type], amount, _resources.get(type, 0))
		return false
	_resources[type] -= amount
	EventBus.resource_changed.emit(_names[type], _resources[type], -amount)
	return true

## Spend a full cost dictionary. All-or-nothing: either all are spent or none.
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

## Get all resources as {Type: int} — for UI display.
func get_all() -> Dictionary:
	return _resources.duplicate()
