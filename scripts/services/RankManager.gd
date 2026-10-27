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

const ColonyIdentity := preload("res://scripts/services/ColonyIdentity.gd")
const ColonyFlag := preload("res://scripts/ui/ColonyFlag.gd")

var _xp := 0
var _rank := 1
## El pais: nombre y receta de la bandera (ColonyFlag). Se guardan con la
## partida (son de esta colonia, no del dispositivo).
var _colony_name := ""
var _flag_spec: Dictionary = GameConfig.COLONY_DEFAULT_SPEC.duplicate(true)

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
	# Tres campanas (feat/tres-campanas): cada mision ganada, y mas el jefe.
	EventBus.campaign_mission_won.connect(func(_d, _m, boss): add_xp_from("campaign_boss" if boss else "campaign_mission"))
	# Volverse el Imperio (feat/volverse-imperio): cada mision de conquista, y
	# mas al tomar la isla. El rango sigue subiendo hasta el 18 despues de ganar.
	EventBus.conquest_mission_won.connect(func(_i, _m, _c): add_xp_from("conquest_mission"))
	EventBus.island_conquered.connect(func(_i): add_xp_from("island_conquered"))
	_apply_bonuses()
	# Hasta la primera partida (o en escenas de prueba), un nombre ya puesto.
	if _colony_name.is_empty():
		_colony_name = ColonyIdentity.random_name(1, Tr.get_locale())

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
	if building_rank(building_id) <= _rank:
		return true
	# Un plano menor comprado al contrabandista lo abre antes de tiempo
	# (feat/edificios-economia, EconomyManager.grant_plan).
	var economy := get_node_or_null("/root/EconomyManager")
	if economy != null and economy.has_plan(building_id):
		return true
	# Volverse el Imperio: una isla conquistada abre su decoracion antes de rango.
	var empire: Node = get_node_or_null("/root/EmpireManager")
	return empire != null and bool(empire.unlocks_building(building_id))

## El rango que abre una pieza de la bandera ("patterns", "emblems", "colors").
static func piece_rank(kind: String, id: String) -> int:
	return ColonyIdentity.piece_rank(kind, id)

static func color_rank(color_id: String) -> int:
	return ColonyIdentity.piece_rank("colors", color_id)

## ¿Puede elegirse ya esta pieza? Sandbox lo tiene todo abierto.
func is_piece_unlocked(kind: String, id: String) -> bool:
	return ColonyIdentity.is_piece_open(kind, id, _rank, GameMode.all_unlocked())

func is_color_unlocked(color_id: String) -> bool:
	return is_piece_unlocked("colors", color_id)

## ¿Todas las piezas de la receta estan abiertas con el rango de ahora?
func is_spec_unlocked(spec: Dictionary) -> bool:
	return ColonyIdentity.is_spec_open(spec, _rank, GameMode.all_unlocked())

## Pone en GameConfig los bonos del rango actual. Asigna, no suma.
func _apply_bonuses() -> void:
	var total := rewards_up_to(_rank)
	GameConfig.rank_production_bonus = float(total.get("production", 0.0))
	GameConfig.rank_storage_bonus = float(total.get("storage", 0.0))
	GameConfig.rank_limit_bonus = total.get("limit", {}).duplicate()

# ── El pais: nombre y bandera ──

func get_colony_name() -> String:
	return _colony_name

## La receta de la bandera (copia: cambiarla no cambia la partida).
func get_flag_spec() -> Dictionary:
	return _flag_spec.duplicate(true)

## El color principal del pais (el primero de la bandera): el de las fichas
## propias del tablero.
func get_color_id() -> String:
	return String(_flag_spec["colors"][0])

func get_color() -> Color:
	return ColonyFlag.color_of(get_color_id())

## Cambia nombre y bandera. Falla (false, sin tocar nada) si el nombre no pasa
## el filtro o queda vacio, o si alguna pieza no esta abierta por rango. La
## receta se arregla para que se lea (ColonyFlag.fix_spec). Avisa y guarda solo
## si algo cambio.
func set_colony(colony_name: String, spec: Dictionary) -> bool:
	var clean := ColonyIdentity.clean_name(colony_name)
	if not ColonyIdentity.is_name_allowed(clean) or not is_spec_unlocked(spec):
		return false
	var fixed := ColonyFlag.fix_spec(spec, ColonyIdentity.open_pieces("colors", _rank, GameMode.all_unlocked()))
	if clean == _colony_name and ColonyFlag.spec_key(fixed) == ColonyFlag.spec_key(_flag_spec):
		return true
	_colony_name = clean
	_flag_spec = fixed
	EventBus.colony_identity_changed.emit(_colony_name, get_flag_spec())
	GameManager.request_save()
	return true

# ── Guardado ──

func get_save_data() -> Dictionary:
	return {"xp": _xp, "colony": {"name": _colony_name, "flag": get_flag_spec()}}

## Idempotente: todo se deriva de lo guardado. Sin clave (guardado viejo) =
## XP 0, rango 1. El pais:
##   - "colony" guardado: su nombre y su bandera; una pieza por encima del rango
##     (o desconocida) vuelve a la de serie, un nombre que no pasa el filtro
##     se cambia por uno al azar;
##   - sin "colony" pero con la bandera de antes ("flag", "color"): esa bandera
##     traducida a piezas y un nombre al azar;
##   - sin nada: nombre y bandera al azar.
## Lo "al azar" sale de la semilla de la isla (GridManager.island_seed, que se
## carga antes): la misma partida vieja da siempre el mismo pais.
func load_save_data(data: Dictionary) -> void:
	_xp = maxi(0, int(data.get("xp", 0)))
	_rank = rank_for_xp(_xp)
	_apply_bonuses()
	var all := GameMode.all_unlocked()
	var seed_value := ColonyIdentity.seed_for_island(GridManager.island_seed)
	var colony: Variant = data.get("colony", null)
	var spec: Dictionary
	var colony_name := ""
	if colony is Dictionary:
		colony_name = String(colony.get("name", ""))
		var raw: Variant = colony.get("flag", {})
		spec = raw if raw is Dictionary else {}
	elif data.has("flag") or data.has("color"):
		spec = ColonyIdentity.legacy_spec(String(data.get("flag", "band")), String(data.get("color", "brass")))
	else:
		spec = ColonyIdentity.random_spec(seed_value, _rank, all)
	_flag_spec = ColonyIdentity.clamp_spec(spec, _rank, all)
	colony_name = ColonyIdentity.clean_name(colony_name)
	if not ColonyIdentity.is_name_allowed(colony_name):
		colony_name = ColonyIdentity.random_name(seed_value, Tr.get_locale())
	_colony_name = colony_name
	EventBus.governor_xp_changed.emit(_xp, _rank, 0)
	EventBus.colony_identity_changed.emit(_colony_name, get_flag_spec())

## Tira el rango de la partida anterior. Sin avisos: una partida nueva no
## anuncia lo que perdio. El pais nuevo sale al azar (con su propio generador:
## no mueve el RNG global que sortea el mapa); el que se eligio en el paso de
## Nueva partida lo pone despues GameManager (_apply_pending_identity, con
## set_colony).
func reset() -> void:
	_xp = 0
	_rank = 1
	_apply_bonuses()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var seed_value := rng.randi()
	_colony_name = ColonyIdentity.random_name(seed_value, Tr.get_locale())
	_flag_spec = ColonyIdentity.random_spec(seed_value, 1)
