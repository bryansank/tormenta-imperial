extends Node
const Rules := preload("res://scripts/buildings/PlacementRules.gd")
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

# ── Hambruna ──
## Tics de consumo seguidos sin poder pagar. Se reinicia al pagar uno entero.
## Viaja en el guardado: el hambre no se olvida al cerrar el juego.
var _unpaid_ticks := 0

func _ready() -> void:
	EventBus.construction_completed.connect(_on_building_completed)
	# Una carretera es instantanea: al ponerla puede conectar algo que estaba suelto.
	EventBus.building_placed.connect(func(_d, _c): _recalculate_all())
	# Una veta agotada para al extractor de al lado (el nodo muere al final del frame).
	EventBus.deposit_depleted.connect(func(_n, _id): _recalculate_all.call_deferred())
	# Minar a mano ocupa trabajadores mientras dura (ProcessManager.busy_mining_workers).
	EventBus.mining_started.connect(func(_n, _id): _recalculate_all.call_deferred())
	EventBus.mining_completed.connect(func(_n, _id): _recalculate_all.call_deferred())
	EventBus.process_cancelled.connect(func(_n, _id, _r): _recalculate_all.call_deferred())
	EventBus.building_demolished.connect(_on_building_demolished)
	EventBus.building_upgrade_completed.connect(_on_upgrade_completed)
	# La moral es de esta casa: ArmyManager avisa de la desercion por EventBus y
	# aqui se traduce a moral, sin que un servicio toque el estado del otro.
	EventBus.army_deserted.connect(_on_army_deserted)

func _process(delta: float) -> void:
	if _notif_cooldown > 0.0:
		_notif_cooldown -= delta

	# Phase 0 (Foundation): no consumption, no growth — just build freely
	if ProgressionManager.current_phase < GameConfig.Phase.SETTLEMENT:
		return

	# Use gentler timers in early phases (1-2)
	var is_early := ProgressionManager.current_phase < GameConfig.Phase.SURVIVAL
	var cons_base := GameConfig.early_consumption_interval if is_early else GameConfig.consumption_interval
	var grow_base := GameConfig.early_growth_interval if is_early else GameConfig.growth_interval

	# Consumption tick
	var cons_interval := GameConfig.get_duration(cons_base)
	_consumption_timer += delta
	if _consumption_timer >= cons_interval:
		_consumption_timer -= cons_interval
		_tick_consumption()

	# Population growth
	var grow_interval := GameConfig.get_duration(grow_base)
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
	return morale_to_multiplier(_morale)

## La curva de diseno: 0 de moral = 0,5x, 50 = 1,0x, 100 = 1,2x, lineal a tramos.
## Antes era una sola recta (0,5 + m*0,007) que daba 0,85x a moral 50: el punto
## "normal" de la partida producia un 15% menos de lo que decia la documentacion.
## La mitad baja castiga rapido (media moral cuesta la mitad de la produccion); la
## alta premia poco, para que la moral alta sea un extra y no una obligacion.
static func morale_to_multiplier(morale: float) -> float:
	var m := clampf(morale, 0.0, 100.0)
	if m <= 50.0:
		return 0.5 + (m / 50.0) * 0.5
	return 1.0 + ((m - 50.0) / 50.0) * 0.2

func remove_population(amount: int) -> void:
	_set_population(_population - amount)

func adjust_morale(delta: int) -> void:
	_adjust_morale(delta)

## Tics seguidos de consumo impagado. Cero significa que se come.
func get_unpaid_ticks() -> int:
	return _unpaid_ticks

## El suelo de ruina vive aqui, en el unico sitio que escribe la poblacion.
## Se puede caer hasta el fondo, pero no se pierde la partida: por muy mal que
## vaya siempre queda alguien, y con alguien todavia se puede reconstruir.
func _set_population(value: int) -> void:
	var clamped: int = maxi(GameConfig.population_floor, value)
	if clamped == _population:
		return
	_population = clamped
	EventBus.population_changed.emit(_population, _max_population)

# ── Consumption ──

func _tick_consumption() -> void:
	if _population <= 0:
		return
	# Each pop unit consumes 1 wood and 1 gold per tick, reduced by tech bonus
	var reduction := GameConfig.tech_consumption_reduction
	var wood_needed: int = maxi(1, int(_population * maxf(0.1, 1.0 - reduction)))
	var gold_needed: int = maxi(1, int(_population * maxf(0.1, 1.0 - reduction)))

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
			_notif_cooldown = 30.0

	if gold_ok:
		ResourceManager.spend(ResourceManager.Type.GOLD, gold_needed)
	else:
		var available := ResourceManager.get_amount(ResourceManager.Type.GOLD)
		if available > 0:
			ResourceManager.spend(ResourceManager.Type.GOLD, available)
		EventBus.consumption_failed.emit("gold")
		if _notif_cooldown <= 0.0:
			EventBus.notification_posted.emit(Tr.t("NOTIF_NO_GOLD"), "warning", Color(0.9, 0.6, 0.2))
			_notif_cooldown = 30.0

	# Morale adjustments
	if wood_ok and gold_ok:
		_adjust_morale(GameConfig.morale_satisfied_recovery)
		# Un tic pagado entero borra la cuenta: el hambre no se arrastra.
		_unpaid_ticks = 0
		return

	_adjust_morale(GameConfig.morale_unsatisfied_penalty)
	_unpaid_ticks += 1
	# Dos tics de gracia. Al tercero la gente deja de aguantar.
	if GameConfig.unpaid_hurts(_unpaid_ticks):
		_starve()

## El impago sostenido mata. Hasta ahora solo restaba moral y avisaba, asi que
## se podia ignorar indefinidamente; una advertencia que nunca se cumple deja de
## leerse. El suelo de ruina sigue en pie: nunca baja del ultimo habitante.
func _starve() -> void:
	var before := _population
	_set_population(_population - GameConfig.starvation_deaths_per_tick)
	var deaths := before - _population
	if deaths <= 0:
		return  # Ya estamos en el suelo: no queda nadie mas que perder.
	_adjust_morale(GameConfig.starvation_morale_penalty)
	EventBus.population_starved.emit(deaths, _population)
	EventBus.notification_posted.emit(
		Tr.t("NOTIF_STARVATION") % deaths, "danger", Color(0.9, 0.3, 0.2))

func _on_army_deserted(_unit_id: String, count: int) -> void:
	_adjust_morale(GameConfig.desertion_morale_penalty * maxi(1, count))

func _adjust_morale(delta: int) -> void:
	# Phase 0-1: morale stays fixed — don't confuse new players
	if ProgressionManager.current_phase < GameConfig.Phase.ECONOMY:
		return
	var old := _morale
	# Use gentler penalty in early phases
	var actual_delta := delta
	if delta < 0 and ProgressionManager.current_phase < GameConfig.Phase.SURVIVAL:
		actual_delta = maxi(delta, GameConfig.early_morale_penalty)
	# Decoration bonus only active from Phase 3+
	var deco_rate := _get_decoration_morale_rate() if ProgressionManager.current_phase >= GameConfig.Phase.SURVIVAL else 0
	_morale = clampi(_morale + actual_delta + deco_rate, GameConfig.morale_min, GameConfig.morale_max)
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
	# Por debajo del suelo de rebrote la gente vuelve aunque la moral este por los
	# suelos. Sin esto una colonia hundida (hambre, Diezmo en obreros) se quedaba
	# en 1 habitante con la moral a 0: sin obreros no produce la mina, sin oro no
	# se paga la comida, sin comida la moral no sube de 30 y sin 30 no nace nadie.
	# Un atasco sin salida; "se puede caer, no se puede perder" pide que la haya.
	var regrowing: bool = _population < GameConfig.population_regrow_floor
	if _morale < GameConfig.morale_growth_threshold and not regrowing:
		return  # Too unhappy to grow
	# Grow 1 pop if morale is decent
	_population = mini(_population + 1, _max_population)
	EventBus.population_changed.emit(_population, _max_population)
	if _notif_cooldown <= 0.0:
		EventBus.notification_posted.emit(Tr.t("NOTIF_POP_GREW") % [_population, _max_population], "info", Color(0.4, 0.8, 0.4))
		_notif_cooldown = 30.0

# ── Building Events ──

func _on_building_completed(node: Node) -> void:
	_recalculate_all()

func _on_building_demolished(_node: Node, _cell: Vector2i) -> void:
	_recalculate_all()

func _on_upgrade_completed(_node: Node, _new_level: int) -> void:
	_recalculate_all()

func _recalculate_all() -> void:
	var old_max := _max_population
	var old_workers := _used_workers
	_max_population = 0
	_used_workers = 0
	_morale_bonus = 0

	# Sin carretera hasta el Nucleo, un edificio no funciona (2026-09-28): ni
	# recibe trabajadores, ni una vivienda da sitio, ni produce (ProductionManager
	# mira la misma meta `connected`). Se calcula la red una vez por recuento.
	var has_core: bool = not Rules.core_cells().is_empty()
	var network: Dictionary = Rules.connected_roads() if has_core else {}
	var connection_changed := false

	# First pass: count capacity and morale
	var buildings_needing_workers: Array = []
	for info in GridManager.get_all_buildings():
		var data: BuildingData = info["data"]
		var node: Node = info.get("node", null)
		var connected := true
		if has_core and not data.is_core and data.id != Rules.ROAD_ID:
			connected = Rules.touches_network(info.get("cells", []), network)
		if node and is_instance_valid(node):
			if bool(node.get_meta("connected", true)) != connected:
				connection_changed = true
			node.set_meta("connected", connected)
		if not connected:
			if node and is_instance_valid(node) and node.has_meta("staffed"):
				node.set_meta("staffed", false)
			continue
		# Sin su veta al lado (agotada a mano), un extractor no trabaja.
		var has_vein: bool = Rules.has_its_deposit(data, info.get("cells", []), GameManager.map_generator())
		if node and is_instance_valid(node):
			if bool(node.get_meta("has_vein", true)) != has_vein:
				connection_changed = true
			node.set_meta("has_vein", has_vein)
		# Skip buildings under construction
		if node and node is Node and node.has_meta("under_construction"):
			if node.has_meta("staffed"):
				node.remove_meta("staffed")
			continue
		var lvl: int = int(node.get_meta("level", 1)) if node != null and is_instance_valid(node) else 1
		_max_population += int(data.population_capacity * GameConfig.level_mult(GameConfig.upgrade_capacity_multiplier, lvl)) \
			if not data.is_core else data.population_capacity
		_morale_bonus += int(data.morale_bonus * GameConfig.level_mult(GameConfig.upgrade_morale_multiplier, lvl))
		# Los trabajadores retirados por el jugador (o sin veta) no se asignan:
		# quedan libres para otro edificio.
		var off: bool = node != null and is_instance_valid(node) and bool(node.get_meta("workers_off", false))
		if data.workers_required > 0 and (off or not has_vein):
			if node and is_instance_valid(node):
				node.set_meta("staffed", false)
			continue
		if data.workers_required > 0:
			buildings_needing_workers.append({"node": node, "data": data})

	# Clamp population to max — pero nunca por debajo del suelo de ruina:
	# quedarse sin casas no puede dejar la isla vacia.
	_population = maxi(GameConfig.population_floor, mini(_population, _max_population))

	# Second pass: assign workers with priority (first built = first served).
	# Los que estan sacando vetas a mano no estan en ningun edificio.
	var mining: int = mini(ProcessManager.busy_mining_workers(), _population)
	_used_workers += mining
	var remaining_workers := _population - mining
	for entry in buildings_needing_workers:
		var node: Node = entry["node"]
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
	# Tambien si solo cambio quien esta conectado: los carteles de estado
	# ("sin carretera") se repintan con esta senal.
	if _used_workers != old_workers or connection_changed:
		EventBus.workers_changed.emit(_used_workers, _population)

## El jugador retira (off = true) o devuelve los trabajadores de un edificio.
## Sus trabajadores quedan libres para otros; el edificio deja de producir.
func set_workers_off(node: Node, off: bool) -> void:
	if node == null or not is_instance_valid(node):
		return
	if off:
		node.set_meta("workers_off", true)
	elif node.has_meta("workers_off"):
		node.remove_meta("workers_off")
	_recalculate_all()
	# Aunque no cambie el numero de ocupados, los carteles y el panel se repintan.
	EventBus.workers_changed.emit(_used_workers, _population)

## Check if a specific building node is staffed (has enough workers assigned).
func is_building_staffed(node: Node) -> bool:
	return node.get_meta("staffed", false)

## Update the visual indicator on a building for worker status.
## El cartel rojo de "SIN TRABAJADORES" ya no se pinta aqui: el estado del
## edificio vive en su BuildingStatusBadge (A11), que lee la meta `staffed`
## que acabamos de escribir y la combina con construccion, ruina y procesos
## para decidir entre Zzz y el obrero. Aqui solo se le avisa de que mire.
func _update_worker_visual(node: Node, _staffed: bool) -> void:
	var badge: Node = node.get_node_or_null("StatusBadge")
	if badge and badge.has_method("refresh"):
		badge.refresh()

func has_enough_workers(data: BuildingData) -> bool:
	return get_free_workers() >= data.workers_required

# ── Save/Load ──

func get_save_data() -> Dictionary:
	return {
		"population": _population,
		"morale": _morale,
		"unpaid_ticks": _unpaid_ticks,
	}

func load_save_data(data: Dictionary) -> void:
	_population = maxi(GameConfig.population_floor, int(data.get("population", GameConfig.population_start)))
	_morale = data.get("morale", GameConfig.morale_start)
	# Un guardado anterior a la hambruna no trae contador: empieza a cero.
	_unpaid_ticks = int(data.get("unpaid_ticks", 0))
	_recalculate_all()

func reset() -> void:
	_population = GameConfig.population_start
	_max_population = GameConfig.population_start
	_used_workers = 0
	_morale = GameConfig.morale_start
	_morale_bonus = 0
	_consumption_timer = 0.0
	_growth_timer = 0.0
	_unpaid_ticks = 0
