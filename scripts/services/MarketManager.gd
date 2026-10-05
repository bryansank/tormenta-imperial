extends Node
## Internal market for buying/selling resources with gold.
## Prices float based on supply/demand with mean reversion.
##
## Gobernador (GameMode.market_dynamic): la "media" a la que vuelven los precios
## deja de ser 1.0 y la marca un calendario FIJO que sigue a la Tormenta
## (GameConfig.market_calendar): en el Aviso sube la madera, en la Tormenta baja
## el acero, tras el Diezmo el oro vale menos (todo cuesta mas oro) y en la calma
## todo vuelve a la media. El tick es mas corto para que una fase se note. En
## Colono el mercado es el de siempre.

# Current price modifiers (1.0 = base price, >1 = expensive, <1 = cheap)
var _price_mods: Dictionary = {
	"wood": 1.0,
	"steel": 1.0,
	"oil": 1.0,
}

var _tick_timer := 0.0
## Segundos que quedan de "tras el Diezmo" (oro devaluado). Persistido: un
## guardado hecho justo despues del Diezmo no puede olvidarlo al cargar.
var _after_tithe_left := 0.0

func _ready() -> void:
	EventBus.tithe_resolved.connect(_on_tithe_resolved)

func _process(delta: float) -> void:
	if _after_tithe_left > 0.0:
		_after_tithe_left = maxf(0.0, _after_tithe_left - delta)
	# Market not available until Phase 2 (Economy)
	if ProgressionManager.current_phase < GameConfig.Phase.ECONOMY:
		return
	_tick_timer += delta
	var interval := tick_interval()
	if _tick_timer >= interval:
		_tick_timer -= interval
		_apply_mean_reversion()
		EventBus.market_prices_updated.emit(get_all_prices())

## Cada cuanto se mueven los precios. Colono: el de siempre (10 s en dev_mode).
func tick_interval() -> float:
	if GameMode.market_dynamic():
		var t: float = GameConfig.market_dynamic_tick_interval
		return maxf(t * GameConfig.dev_time_scale, 1.0) if GameConfig.dev_mode else t
	return 10.0 if GameConfig.dev_mode else GameConfig.market_tick_interval

# ── Calendario de la Tormenta (Gobernador) ──

## La estacion del mercado ahora: "calm", "warning", "storm" o "after_tithe".
## Colono siempre "calm". Se deriva de la fase de la Tormenta, salvo el rato
## despues del Diezmo, que lleva su propio reloj.
func season() -> String:
	if not GameMode.market_dynamic():
		return "calm"
	return season_for(StormManager.get_phase(), _after_tithe_left > 0.0)

## La tabla pura: fase de la Tormenta (StormCycle.Phase) -> estacion.
static func season_for(storm_phase: int, after_tithe: bool) -> String:
	match storm_phase:
		StormCycle.Phase.WARNING, StormCycle.Phase.ASH:
			return "warning"
		StormCycle.Phase.STORM:
			return "storm"
		StormCycle.Phase.TITHE:
			return "after_tithe"
	return "after_tithe" if after_tithe else "calm"

## El modificador al que tiende `resource` en esta estacion (1.0 = la media).
func target_mod(resource: String) -> float:
	var shifts: Dictionary = GameConfig.market_calendar.get(season(), {})
	return clampf(1.0 + float(shifts.get(resource, 0.0)),
		GameConfig.market_min_price_mult, GameConfig.market_max_price_mult)

func _on_tithe_resolved(_paid: bool, _taken: Dictionary) -> void:
	_after_tithe_left = GameConfig.market_after_tithe_seconds

func after_tithe_seconds_left() -> float:
	return _after_tithe_left

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

## Lo que se pierde comprando y revendiendo una unidad ahora mismo.
func get_spread(resource: String) -> int:
	return maxi(0, get_buy_price(resource) - get_sell_price(resource))

func get_all_prices() -> Dictionary:
	var prices := {}
	for res in _price_mods:
		prices[res] = {"buy": get_buy_price(res), "sell": get_sell_price(res)}
	return prices

## Colono: si el precio esta caro (+1), barato (-1) o en la media (0).
## Gobernador: hacia donde va (el objetivo del calendario frente a lo de ahora).
func get_price_trend(resource: String) -> float:
	var mod: float = _price_mods.get(resource, 1.0)
	if GameMode.market_dynamic():
		var gap: float = target_mod(resource) - mod
		if absf(gap) <= GameConfig.market_trend_deadband:
			return 0.0
		return 1.0 if gap > 0.0 else -1.0
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
	var shift: float = float(signed_amount) * sensitivity
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
		# Revert toward 1.0 (Colono) or toward the Storm calendar (Gobernador)
		if GameMode.market_dynamic():
			mod = lerpf(mod, target_mod(res), maxf(reversion, GameConfig.market_calendar_pull))
		else:
			mod = lerpf(mod, 1.0, reversion)
		_price_mods[res] = clampf(mod, GameConfig.market_min_price_mult, GameConfig.market_max_price_mult)

# ── Save/Load ──

func get_save_data() -> Dictionary:
	return {"price_mods": _price_mods.duplicate(), "after_tithe_left": _after_tithe_left}

func load_save_data(data: Dictionary) -> void:
	if data.has("price_mods"):
		_price_mods = data["price_mods"]
	_after_tithe_left = maxf(0.0, float(data.get("after_tithe_left", 0.0)))

func reset() -> void:
	_price_mods = {"wood": 1.0, "steel": 1.0, "oil": 1.0}
	_tick_timer = 0.0
	_after_tithe_left = 0.0
