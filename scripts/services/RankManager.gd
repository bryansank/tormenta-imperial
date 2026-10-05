extends Node
## El rango del gobernador: XP dentro de la partida, aparte de eras e hitos.
##
## Escucha el EventBus (obras, mejoras, produccion, comercio, entrenamiento,
## peleas, tormentas, hitos) y suma XP segun GameConfig.rank_xp_sources. El rango
## NO se guarda: se deriva de la XP con GameConfig.rank_xp_thresholds. Asi la
## carga es idempotente por construccion y un guardado viejo (sin clave "rank")
## es simplemente XP 0 = rango 1.
##
## Lo que da cada rango (GameConfig.rank_rewards) se aplica asignando el total
## del rango actual en GameConfig (rank_production_bonus, rank_storage_bonus,
## rank_limit_bonus), nunca sumando encima: cargar dos veces da los mismos bonos.
##
## Por que un autoload propio y no dentro de ProgressionManager: el rango es
## otro eje (XP continua, no hitos sueltos), tiene su propia clave en el
## guardado y su propio reset, y ProgressionManager ya carga con eras, hitos y la
## Auditoria Final. Va el ultimo de la lista: solo depende de GameConfig,
## EventBus y GameMode, y nadie lo necesita durante el _ready de los demas.

var _xp := 0
var _rank := 1
## Cosmeticos elegidos. Se guardan con la partida (son de esta colonia, no del
## dispositivo).
var _flag := GameConfig.COLONY_DEFAULT_FLAG
var _color := GameConfig.COLONY_DEFAULT_COLOR

func _ready() -> void:
	EventBus.construction_completed.connect(_on_construction_completed)
	EventBus.building_upgrade_completed.connect(func(_n, _l): add_xp_from("upgrade"))
	EventBus.production_tick.connect(func(_n): add_xp_from("production"))
	EventBus.process_completed.connect(func(_n, _p): add_xp_from("process"))
	EventBus.mining_completed.connect(func(_n, _d): add_xp_from("mining"))
	EventBus.market_trade_completed.connect(func(_r, _a, _b, _p): add_xp_from("trade"))
	EventBus.unit_trained.connect(func(_u): add_xp_from("train"))
	EventBus.encounter_ended.connect(_on_encounter_ended)
	EventBus.defense_auto_resolved.connect(func(victory, _r, _s): _on_encounter_ended(victory, 0))
	EventBus.expedition_ended.connect(_on_expedition_ended)
	EventBus.storm_ended.connect(_on_storm_ended)
	EventBus.milestone_completed.connect(func(_m): add_xp_from("milestone"))
	_apply_bonuses()

# ── XP ──

## Suma la XP de una fuente de GameConfig.rank_xp_sources. Devuelve lo sumado.
func add_xp_from(source: String, times: int = 1) -> int:
	var amount: int = int(GameConfig.rank_xp_sources.get(source, 0)) * maxi(0, times)
	add_xp(amount)
	return amount

## Suma XP y, si cruza uno o varios umbrales, sube de rango y lo anuncia una vez
## con todo lo que se ha ganado en el salto.
func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	_xp += amount
	var new_rank := rank_for_xp(_xp)
	if new_rank > _rank:
		var old_rank := _rank
		_rank = new_rank
		_apply_bonuses()
		EventBus.governor_rank_up.emit(_rank, rewards_between(old_rank, _rank))
	EventBus.governor_xp_changed.emit(_xp, _rank, amount)

func _on_construction_completed(node: Node) -> void:
	var info := GridManager.get_building_info(node)
	if info.is_empty():
		return
	var data: BuildingData = info["data"]
	if data.is_core or data.id == "road":
		return
	add_xp_from("build_decoration" if data.is_decoration else "build")

func _on_encounter_ended(victory: bool, _turns: int) -> void:
	if victory:
		add_xp_from("fight_won")

## `result` 0 = victoria (EventBus).
func _on_expedition_ended(result: int, _rewards: Dictionary, _casualties: Dictionary) -> void:
	if result == 0:
		add_xp_from("expedition_won")

func _on_storm_ended(severity: int) -> void:
	add_xp(int(GameConfig.rank_xp_sources.get("storm", 0))
		+ int(GameConfig.rank_xp_sources.get("storm_per_severity", 0)) * maxi(0, severity))

# ── Curva ──

static func max_rank() -> int:
	return GameConfig.rank_xp_thresholds.size()

## El rango que corresponde a una XP (1..max_rank()).
static func rank_for_xp(xp: int) -> int:
	var thresholds: Array = GameConfig.rank_xp_thresholds
	var rank := 1
	for i in range(thresholds.size()):
		if xp >= int(thresholds[i]):
			rank = i + 1
	return rank

static func xp_for_rank(rank: int) -> int:
	var thresholds: Array = GameConfig.rank_xp_thresholds
	return int(thresholds[clampi(rank, 1, thresholds.size()) - 1])

func get_xp() -> int:
	return _xp

func get_rank() -> int:
	return _rank

func is_max_rank() -> bool:
	return _rank >= max_rank()

## Progreso dentro del rango actual (0..1). 1 en el rango maximo.
func get_rank_progress() -> float:
	if is_max_rank():
		return 1.0
	var lo := xp_for_rank(_rank)
	var hi := xp_for_rank(_rank + 1)
	return clampf(float(_xp - lo) / float(maxi(1, hi - lo)), 0.0, 1.0)

## XP que falta para el siguiente rango (0 en el maximo).
func xp_to_next() -> int:
	return 0 if is_max_rank() else maxi(0, xp_for_rank(_rank + 1) - _xp)

func get_title_key() -> String:
	return GameConfig.rank_title_key(_rank)

# ── Recompensas ──

## Lo ganado al pasar de `from_rank` (excluido) a `to_rank` (incluido), unido:
## listas concatenadas, fracciones sumadas, huecos sumados.
static func rewards_between(from_rank: int, to_rank: int) -> Dictionary:
	var out := {}
	for r in range(from_rank + 1, to_rank + 1):
		var rw: Dictionary = GameConfig.rank_rewards.get(r, {})
		for key in rw:
			var value: Variant = rw[key]
			if value is Array:
				var list: Array = out.get(key, [])
				list.append_array(value)
				out[key] = list
			elif value is Dictionary:
				var dict: Dictionary = out.get(key, {})
				for id in value:
					dict[id] = int(dict.get(id, 0)) + int(value[id])
				out[key] = dict
			else:
				out[key] = float(out.get(key, 0.0)) + float(value)
	return out

## Todo lo acumulado hasta `rank` (incluido).
static func rewards_up_to(rank: int) -> Dictionary:
	return rewards_between(0, rank)

## El rango que desbloquea un edificio, o 0 si el rango no lo bloquea.
static func building_rank(building_id: String) -> int:
	for r in GameConfig.rank_rewards:
		if building_id in GameConfig.rank_rewards[r].get("buildings", []):
			return int(r)
	return 0

## ¿Puede construirse ya por rango? Sandbox lo tiene todo abierto.
func is_building_unlocked(building_id: String) -> bool:
	if GameMode.all_unlocked():
		return true
	return building_rank(building_id) <= _rank

static func flag_rank(flag_id: String) -> int:
	return _reward_rank("flags", flag_id)

static func color_rank(color_id: String) -> int:
	return _reward_rank("colors", color_id)

static func _reward_rank(key: String, id: String) -> int:
	for r in GameConfig.rank_rewards:
		if id in GameConfig.rank_rewards[r].get(key, []):
			return int(r)
	return 0

func is_flag_unlocked(flag_id: String) -> bool:
	if not (flag_id in GameConfig.COLONY_FLAGS):
		return false
	return GameMode.all_unlocked() or flag_rank(flag_id) <= _rank

func is_color_unlocked(color_id: String) -> bool:
	if not GameConfig.colony_colors.has(color_id):
		return false
	return GameMode.all_unlocked() or color_rank(color_id) <= _rank

## Pone en GameConfig los bonos del rango actual. Asigna, no suma.
func _apply_bonuses() -> void:
	var total := rewards_up_to(_rank)
	GameConfig.rank_production_bonus = float(total.get("production", 0.0))
	GameConfig.rank_storage_bonus = float(total.get("storage", 0.0))
	GameConfig.rank_limit_bonus = total.get("limit", {}).duplicate()

# ── Cosmeticos ──

func get_flag() -> String:
	return _flag

func get_color_id() -> String:
	return _color

func get_color() -> Color:
	return GameConfig.colony_colors.get(_color, GameConfig.colony_colors[GameConfig.COLONY_DEFAULT_COLOR])

## Elige bandera; solo si el rango la tiene. Devuelve si cambio.
func set_flag(flag_id: String) -> bool:
	if flag_id == _flag or not is_flag_unlocked(flag_id):
		return false
	_flag = flag_id
	EventBus.colony_cosmetics_changed.emit(_flag, _color)
	GameManager.request_save()
	return true

func set_color(color_id: String) -> bool:
	if color_id == _color or not is_color_unlocked(color_id):
		return false
	_color = color_id
	EventBus.colony_cosmetics_changed.emit(_flag, _color)
	GameManager.request_save()
	return true

# ── Guardado ──

func get_save_data() -> Dictionary:
	return {"xp": _xp, "flag": _flag, "color": _color}

## Idempotente: todo se deriva de lo guardado. Sin clave (guardado viejo) =
## XP 0, rango 1, cosmeticos de serie. Un cosmetico desconocido o por encima del
## rango vuelve al de serie.
func load_save_data(data: Dictionary) -> void:
	_xp = maxi(0, int(data.get("xp", 0)))
	_rank = rank_for_xp(_xp)
	_apply_bonuses()
	_flag = String(data.get("flag", GameConfig.COLONY_DEFAULT_FLAG))
	if not is_flag_unlocked(_flag):
		_flag = GameConfig.COLONY_DEFAULT_FLAG
	_color = String(data.get("color", GameConfig.COLONY_DEFAULT_COLOR))
	if not is_color_unlocked(_color):
		_color = GameConfig.COLONY_DEFAULT_COLOR
	EventBus.governor_xp_changed.emit(_xp, _rank, 0)
	EventBus.colony_cosmetics_changed.emit(_flag, _color)

## Tira el rango de la partida anterior. Sin avisos: una partida nueva no
## anuncia lo que perdio.
func reset() -> void:
	_xp = 0
	_rank = 1
	_flag = GameConfig.COLONY_DEFAULT_FLAG
	_color = GameConfig.COLONY_DEFAULT_COLOR
	_apply_bonuses()
