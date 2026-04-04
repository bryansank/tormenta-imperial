extends Node
## Internal market for buying/selling resources with gold.
## Prices float based on supply/demand with mean reversion.

# Current price modifiers (1.0 = base price, >1 = expensive, <1 = cheap)
var _price_mods: Dictionary = {
	"wood": 1.0,
	"steel": 1.0,
	"oil": 1.0,
}

var _tick_timer := 0.0

func _process(delta: float) -> void:
	# Market not available until Phase 2 (Economy)
	if ProgressionManager.current_phase < GameConfig.Phase.ECONOMY:
		return
	_tick_timer += delta
	var interval := GameConfig.market_tick_interval
	if GameConfig.dev_mode:
		interval = 10.0
	if _tick_timer >= interval:
		_tick_timer -= interval
		_apply_mean_reversion()
		EventBus.market_prices_updated.emit(get_all_prices())

# ── Price Calculations ──

func get_buy_price(resource: String) -> int:
	var base: int = GameConfig.market_base_prices.get(resource, 0)
	if base == 0:
		return 0
	var mod: float = _price_mods.get(resource, 1.0)
	var spread: float = GameConfig.market_spread
	return maxi(1, int(ceil(base * mod * (1.0 + spread / 2.0))))

func get_sell_price(resource: String) -> int:
	var base: int = GameConfig.market_base_prices.get(resource, 0)
	if base == 0:
		return 0
	var mod: float = _price_mods.get(resource, 1.0)
	var spread: float = GameConfig.market_spread
	return maxi(1, int(floor(base * mod * (1.0 - spread / 2.0))))

func get_all_prices() -> Dictionary:
	var prices := {}
	for res in _price_mods:
		prices[res] = {"buy": get_buy_price(res), "sell": get_sell_price(res)}
	return prices

func get_price_trend(resource: String) -> float:
	var mod: float = _price_mods.get(resource, 1.0)
	if mod > 1.1:
		return 1.0
	elif mod < 0.9:
		return -1.0
	return 0.0

# ── Trading ──

func buy(resource: String, amount: int) -> bool:
	if amount <= 0:
		return false
	if not ResourceManager.is_unlocked_by_name(resource):
		return false
	var price_per := get_buy_price(resource)
	var total_cost := price_per * amount
	if not ResourceManager.has_enough(ResourceManager.Type.GOLD, total_cost):
		EventBus.resources_insufficient.emit("gold", total_cost, ResourceManager.get_amount(ResourceManager.Type.GOLD))
		return false
	var res_type := ResourceManager.name_to_type(resource)
	if res_type == -1:
		return false
	ResourceManager.spend(ResourceManager.Type.GOLD, total_cost)
	ResourceManager.add(res_type, amount)
	# Price goes up when buying (demand)
	_adjust_price(resource, amount)
	EventBus.market_trade_completed.emit(resource, amount, true, total_cost)
	return true

func sell(resource: String, amount: int) -> bool:
	if amount <= 0:
		return false
	if not ResourceManager.is_unlocked_by_name(resource):
		return false
	var res_type := ResourceManager.name_to_type(resource)
	if res_type == -1:
		return false
	if not ResourceManager.has_enough(res_type, amount):
		EventBus.resources_insufficient.emit(resource, amount, ResourceManager.get_amount(res_type))
		return false
	var price_per := get_sell_price(resource)
	var total_gold := price_per * amount
	ResourceManager.spend(res_type, amount)
	ResourceManager.add(ResourceManager.Type.GOLD, total_gold)
	# Price goes down when selling (supply)
	_adjust_price(resource, -amount)
	EventBus.market_trade_completed.emit(resource, amount, false, total_gold)
	return true

# ── Price Adjustment ──

func _adjust_price(resource: String, signed_amount: int) -> void:
	var sensitivity: float = GameConfig.market_price_sensitivity
	var shift := float(signed_amount) * sensitivity
	var mod: float = _price_mods.get(resource, 1.0)
	mod += shift
	mod = clampf(mod, GameConfig.market_min_price_mult, GameConfig.market_max_price_mult)
	_price_mods[resource] = mod

func _apply_mean_reversion() -> void:
	var reversion: float = GameConfig.market_mean_reversion
	for res in _price_mods:
		var mod: float = _price_mods[res]
		# Add small random volatility
		mod += randf_range(-GameConfig.market_volatility, GameConfig.market_volatility) * 0.1
		# Revert toward 1.0
		mod = lerpf(mod, 1.0, reversion)
		_price_mods[res] = clampf(mod, GameConfig.market_min_price_mult, GameConfig.market_max_price_mult)

# ── Save/Load ──

func get_save_data() -> Dictionary:
	return {"price_mods": _price_mods.duplicate()}

func load_save_data(data: Dictionary) -> void:
	if data.has("price_mods"):
		_price_mods = data["price_mods"]

func reset() -> void:
	_price_mods = {"wood": 1.0, "steel": 1.0, "oil": 1.0}
	_tick_timer = 0.0
