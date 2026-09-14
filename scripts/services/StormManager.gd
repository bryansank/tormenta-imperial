extends Node
## Drives the Imperial Storm: runs the clock, republishes its events on the
## EventBus, and applies what the storm does to the base.
##
## The clock itself lives in `scripts/storm/StormCycle.gd` as a pure RefCounted,
## so this node only owns what needs a scene tree: signals, timing and the
## handful of systems the storm reaches into (constitution, principles I and IV).
##
## The storm is the game's metronome. Everything else — building, trading,
## training, fighting — is measured against the next one.

const StormCycleScript := preload("res://scripts/storm/StormCycle.gd")
## El orden en que se vacía la bolsa. El oro primero porque es lo que duele
## anotar, y la madera al final porque es lo que permite reconstruir.
const _TITHE_ORDER: Array = [
	ResourceManager.Type.GOLD, ResourceManager.Type.STEEL,
	ResourceManager.Type.OIL, ResourceManager.Type.WOOD,
]

var _cycle: StormCycle = null
## The storm stays asleep until the base is real enough to be noticed. In the
## fiction, a province that does not show up in the ledger is not worth a storm.
var _armed: bool = false

func _ready() -> void:
	_cycle = StormCycleScript.create()
	EventBus.phase_advanced.connect(_on_phase_advanced)
	EventBus.game_load_completed.connect(_check_arming)
	EventBus.encounter_ended.connect(_on_encounter_ended)
	_check_arming()

func _process(delta: float) -> void:
	if not _armed or _cycle == null:
		return
	_publish(_cycle.advance(delta))

# ── Queries ──────────────────────────────────────────────────────────

func get_cycle() -> StormCycle:
	return _cycle

func is_armed() -> bool:
	return _armed

func get_phase() -> int:
	return _cycle.phase if _cycle != null else StormCycle.Phase.CALM

## What the storm actually hits with: the severity the base earned by growing,
## plus whatever a false alarm deferred onto it.
func get_severity() -> int:
	return _cycle.effective_severity() if _cycle != null else 1

## Severity a false alarm has postponed onto the next storm. Never shown: the
## whole point of deferring it is that the player cannot price the next one.
func get_deferred_severity() -> int:
	return _cycle.deferred_severity if _cycle != null else 0

func is_ashfall() -> bool:
	return _cycle != null and _cycle.is_ashfall()

func is_storming() -> bool:
	return _cycle != null and _cycle.is_storming()

## Seconds until the ash starts falling. Dev tooling only — the HUD stopped
## counting, and a false alarm can make this number mean nothing at all.
func seconds_until_ash() -> float:
	return _cycle.seconds_until_ash() if _cycle != null else 0.0

func storms_survived() -> int:
	return _cycle.storms_survived if _cycle != null else 0

# ── Arming ───────────────────────────────────────────────────────────

## The clock only starts once the base has grown past the Foundation phase —
## the same threshold at which consumption and events wake up. Before that the
## player is still invisible, and that is exactly the point.
func _check_arming() -> void:
	if _armed:
		return
	if ProgressionManager.current_phase >= GameConfig.Phase.SETTLEMENT:
		_armed = true

func _on_phase_advanced(_phase: int) -> void:
	_check_arming()

# ── Event translation ────────────────────────────────────────────────

func _publish(events: Array) -> void:
	for event in events:
		match event.get("e", ""):
			"phase":
				_on_phase_entered(int(event["phase"]))
				EventBus.storm_phase_changed.emit(int(event["phase"]), float(event["left"]))
			"incoming":
				EventBus.storm_incoming.emit(float(event["seconds"]))
				# The first one reads as bad weather. The second one gives the game
				# away by coming back at all — that is how the player finds out it
				# has a sender, without a single line of exposition.
				var key: String = "STORM_INCOMING_FIRST" if storms_survived() == 0 else "STORM_INCOMING"
				EventBus.notification_posted.emit(Tr.t(key), "warning", UITheme.WARNING)
			"false_alarm":
				EventBus.storm_false_alarm.emit(int(event["deferred"]))
				# Worded as relief and nothing more: the player is never told that
				# the assessment is still on the books, which is what makes the
				# next warning land heavier than this one.
				EventBus.notification_posted.emit(
					Tr.t("STORM_FALSE_ALARM"), "info", UITheme.TEXT_DIM)
			"ash_started":
				EventBus.storm_ash_started.emit()
				EventBus.notification_posted.emit(
					Tr.t("STORM_ASH_STARTED"), "warning", UITheme.WARNING)
			"storm_started":
				EventBus.storm_started.emit(int(event["severity"]))
				EventBus.notification_posted.emit(
					Tr.t("STORM_STARTED"), "danger", UITheme.DANGER)
			"storm_tick":
				_apply_storm_tick(int(event["phase"]))
				EventBus.storm_tick.emit(int(event["phase"]), float(event["left"]))
			"storm_ended":
				EventBus.storm_ended.emit(int(event["severity"]))
				EventBus.notification_posted.emit(
					Tr.t("STORM_ENDED"), "info", UITheme.TEXT_DIM)
			"tithe":
				EventBus.tithe_demanded.emit(int(event["severity"]))
				_begin_tithe(int(event["severity"]))

## Production is taxed in two steps, and the Warning is not one of them: halved
## while the ash falls, a crawl once the storm is overhead. The multiplier is
## lifted the moment the phase passes, whatever happens next.
func _on_phase_entered(phase: int) -> void:
	match phase:
		StormCycle.Phase.ASH:
			GameConfig.event_production_multiplier = GameConfig.storm_ash_production_multiplier
		StormCycle.Phase.STORM:
			GameConfig.event_production_multiplier = GameConfig.storm_production_multiplier
		_:
			GameConfig.event_production_multiplier = 1.0

## Cada mordisco cuesta moral, y solo la TORMENTA derriba edificios. La ceniza
## ensucia, no tumba: si tumbara, la fase de Ceniza dejaria de ser la ultima
## ventana en la que reparar un techo sirve de algo.
func _apply_storm_tick(phase: int) -> void:
	var severity: int = get_severity()
	var bleed: float = GameConfig.storm_morale_per_tick * float(severity)
	if phase != StormCycle.Phase.STORM:
		PopulationManager.adjust_morale(-roundi(bleed))
		return
	PopulationManager.adjust_morale(-roundi(bleed * GameConfig.storm_morale_storm_multiplier))
	_damage_buildings(severity)

## La Tormenta no rompe al azar: rompe con criterio. Gasta sus mordiscos del tic
## en el escalón más alto que tenga gente en pie y solo baja al siguiente cuando
## ese se le acaba.
##
## Que la prioridad exista es lo que convierte el daño en una conversación: la
## Tormenta te quita primero el colchón de moral y la defensa, después el techo,
## y solo cuando viene de verdad fuerte se mete con lo que te da de comer.
func _damage_buildings(severity: int) -> void:
	var towers: int = _standing_towers()
	var hits: int = GameConfig.storm_buildings_hit_per_tick
	for tier in damage_priority(severity):
		if hits <= 0:
			return
		# Dentro del escalón sigue mandando el azar: entre dos estatuas la
		# Tormenta no elige, y esa arbitrariedad de detalle es la que hace que
		# la base se sienta expuesta en vez de auditada.
		tier.shuffle()
		for node in tier:
			if hits <= 0:
				return
			var amount: int = GameConfig.get_storm_damage(
				severity, BuildingHealth.get_max_health(node), towers)
			BuildingHealth.damage_building(node, amount)
			hits -= 1

## Los escalones de objetivos, del más prioritario al menos, ya filtrados de todo
## lo intocable. Público porque es la regla que hay que poder auditar sin
## encender una tormenta entera encima de una base de mentira.
##
## Fuera del reparto, pase lo que pase:
##   · lo que ya está en ruinas — no se rompe dos veces;
##   · el último Aserradero y la última Mina de oro **en pie** — sin madera ni
##     oro no hay con qué reparar, y una base que no puede repararse ya perdió
##     sin haberse enterado. Es la regla anti-softlock y no admite excepciones;
##   · el Núcleo, que `BuildingHealth` ya blinda por su cuenta. Aquí se le
##     pregunta a él en vez de repetir la regla: el guard no se duplica, pero un
##     objetivo invulnerable seguiría gastando un mordisco del tic en no hacer
##     nada, y el reparto tiene que ser honesto sobre a quién apunta.
func damage_priority(severity: int) -> Array:
	var defense: Array = []
	var shelter: Array = []
	var economy: Array = []
	var last_standing: Dictionary = _last_standing_essentials()

	for info in GridManager.get_all_buildings():
		var data: BuildingData = info["data"]
		var node: Node3D = info["node"]
		if node == null or not is_instance_valid(node) or BuildingHealth.is_ruined(node):
			continue
		if BuildingHealth.is_core(node):
			continue
		if last_standing.get(data.id, null) == node:
			continue
		if data.is_decoration or data.id in GameConfig.storm_targets_defense:
			defense.append(node)
		elif data.id in GameConfig.storm_targets_shelter:
			shelter.append(node)
		else:
			economy.append(node)

	var tiers: Array = [defense, shelter]
	# La producción solo entra con severidad alta. Una tormenta menor que ya
	# tumba fundiciones no deja ventana para rehacerse, y sin ventana el ciclo
	# deja de ser presión y pasa a ser una cuenta atrás.
	if severity >= GameConfig.storm_production_target_severity:
		tiers.append(economy)
	return tiers

## Para cada edificio esencial, el único que queda en pie — o nada si hay más de
## uno, porque entonces perder uno no cierra ninguna puerta.
func _last_standing_essentials() -> Dictionary:
	var standing: Dictionary = {}
	for info in GridManager.get_all_buildings():
		var data: BuildingData = info["data"]
		if not data.id in GameConfig.storm_essential_buildings:
			continue
		var node: Node3D = info["node"]
		if node == null or not is_instance_valid(node) or BuildingHealth.is_ruined(node):
			continue
		if standing.has(data.id):
			standing[data.id] = null  # Hay dos: ya ninguno es el último.
		else:
			standing[data.id] = node
	return standing

## Solo cuentan las torres en pie: una torre en ruinas no protege nada, que es
## justo lo que obliga a repararlas antes de la siguiente.
func _standing_towers() -> int:
	var count := 0
	for info in GridManager.get_all_buildings():
		var data: BuildingData = info["data"]
		if data == null or data.id != GameConfig.storm_tower_building_id:
			continue
		if BuildingHealth.is_operational(info["node"]):
			count += 1
	return count

# ── The Tithe ────────────────────────────────────────────────────────

## The Assessors arrive. If there is a garrison at home, they have to get through
## it first; with nobody to stand, they simply help themselves.
func _begin_tithe(severity: int) -> void:
	if CombatManager.start_defense(assessor_roster(severity)):
		return
	EventBus.notification_posted.emit(Tr.t("STORM_TITHE_UNDEFENDED"), "danger", UITheme.DANGER)
	_pay_tithe(severity)

## The force that comes to collect. A line of Assessors with guns behind it,
## growing with severity — the more you are worth, the more they send.
##
## Y creciendo también con cada Diezmo que le has repelido. No es rencor: es
## que una provincia capaz de echarlos figura en el libro como una que puede
## pagar más, y la próxima partida de gasto se aprueba sola. Ganarles hoy no
## quita el problema, lo encarece.
func assessor_roster(severity: int) -> Dictionary:
	var raw: float = float(GameConfig.storm_tithe_base_force + severity - 1) 		* GameConfig.get_assessor_escalation(storms_survived())
	var force: int = clampi(roundi(raw), 1, GameConfig.combat_deploy_cap)
	var guns: int = force / 3
	var line: int = maxi(1, force - guns)
	var roster: Dictionary = {"infantry": line}
	if guns > 0:
		roster["artillery"] = guns
	return roster

## Settles the collection once the board is done with it.
func _on_encounter_ended(victory: bool, _turns: int) -> void:
	if _cycle == null or not _cycle.is_collecting():
		return
	if not CombatManager.is_defending():
		return
	if victory:
		repel_tithe()
	else:
		EventBus.notification_posted.emit(Tr.t("STORM_TITHE_PAID"), "danger", UITheme.DANGER)
		_pay_tithe(get_severity())

func _pay_tithe(severity: int) -> void:
	var taken: Dictionary = _collect_tithe(severity)
	EventBus.tithe_resolved.emit(false, taken)
	_settle()

## La Cuota Mínima. Antes esto era un porcentaje de lo almacenado y nada más, y
## por eso no servía: con el almacén en cero se llevaban cero, así que vaciar la
## bolsa en la cola antes de que bajaran convertía el Diezmo en un trámite
## gratis. Era la jugada dominante del juego.
##
## Ahora hay una deuda que existe tengas lo que tengas, y lo que no se cubra con
## recursos **se cobra en carne**: primero lo que es lujo o fuerza —decoraciones
## y edificios militares— y solo después los obreros. Nunca el Núcleo y nunca
## el último habitante: se puede caer hasta el fondo, no se puede perder.
##
## El orden importa tanto como las cifras. Empezar por las estatuas y acabar por
## la gente es lo que hace que el Diezmo se lea como una tasación y no como un
## saqueo: los Tasadores embargan bienes, y solo cuando no quedan bienes anotan
## personas.
func _collect_tithe(severity: int) -> Dictionary:
	var taken: Dictionary = {}
	var debt: int = GameConfig.get_tithe_debt(
		severity, ProgressionManager.current_era, ResourceManager.get_total_stored())

	debt -= _take_from_stores(debt, taken)
	if debt <= 0:
		return taken
	debt -= _take_in_seizures(debt, taken)
	if debt <= 0:
		return taken
	_take_in_workers(debt, taken)
	return taken

## Lo que se cobra de la bolsa. Dos pasadas a propósito: la primera reparte a
## prorrata para que el recorte se sienta en las cuatro columnas a la vez, la
## segunda barre lo que falte para que la cuenta cuadre exacta. Un Tasador no
## deja pendiente un resto de redondeo.
func _take_from_stores(debt: int, taken: Dictionary) -> int:
	var total: int = ResourceManager.get_total_stored()
	if debt <= 0 or total <= 0:
		return 0
	var target: int = mini(debt, total)
	var collected: int = 0
	for sweep in 2:
		for type in _TITHE_ORDER:
			if collected >= target:
				break
			var held: int = ResourceManager.get_amount(type)
			if held <= 0:
				continue
			var bite: int = held if sweep == 1 else int(float(target) * float(held) / float(total))
			bite = mini(bite, target - collected)
			if bite <= 0:
				continue
			ResourceManager.spend(type, bite)
			var key: String = _resource_name(type)
			taken[key] = int(taken.get(key, 0)) + bite
			collected += bite
	return collected

## El embargo. Deja los bienes en ruinas en vez de borrarlos porque un edificio
## dañado no se destruye nunca (2.1): lo que se llevan es el uso, y recuperarlo
## cuesta una reparación — que es justo la deuda con la siguiente tormenta.
func _take_in_seizures(debt: int, taken: Dictionary) -> int:
	var value: int = maxi(1, GameConfig.storm_tithe_building_value)
	var settled: int = 0
	var seized: int = 0
	for node in _seizable_buildings():
		if settled >= debt:
			break
		BuildingHealth.damage_building(node, BuildingHealth.get_max_health(node))
		seized += 1
		settled += value
	if seized > 0:
		taken["buildings"] = seized
		EventBus.notification_posted.emit(
			Tr.t("STORM_TITHE_SEIZED") % seized, "danger", UITheme.DANGER)
	return settled

## Lo embargable, en el orden en que se anota: primero el lujo, después la
## fuerza. Que las estatuas caigan antes que el Cuartel no es piedad, es
## contabilidad — y de paso es el golpe de moral más legible que existe.
func _seizable_buildings() -> Array:
	var luxury: Array = []
	var military: Array = []
	for info in GridManager.get_all_buildings():
		var data: BuildingData = info["data"]
		var node: Node3D = info["node"]
		if node == null or not is_instance_valid(node) or BuildingHealth.is_ruined(node):
			continue
		if BuildingHealth.is_core(node):
			continue
		if data.is_decoration:
			luxury.append(node)
		elif data.id in GameConfig.storm_targets_defense:
			military.append(node)
	luxury.shuffle()
	military.shuffle()
	return luxury + military

## Lo último que se cobra. `remove_population()` tiene su propio suelo, así que
## por muy grande que sea la deuda siempre queda alguien: sin habitantes no hay
## a quién volver a cobrarle, y una colonia arrasada no paga el año que viene.
func _take_in_workers(debt: int, taken: Dictionary) -> void:
	var value: int = maxi(1, GameConfig.storm_tithe_worker_value)
	var wanted: int = ceili(float(debt) / float(value))
	if wanted <= 0:
		return
	var before: int = PopulationManager.get_population()
	PopulationManager.remove_population(wanted)
	var lost: int = before - PopulationManager.get_population()
	if lost <= 0:
		return
	taken["workers"] = lost
	PopulationManager.adjust_morale(-GameConfig.storm_tithe_worker_morale * lost)
	EventBus.notification_posted.emit(
		Tr.t("STORM_TITHE_CONSCRIPTED") % lost, "danger", UITheme.DANGER)

## Repelling them costs nothing but the fight. Called when the board is won.
func repel_tithe() -> void:
	if _cycle == null or not _cycle.is_collecting():
		return
	EventBus.tithe_resolved.emit(true, {})
	EventBus.notification_posted.emit(Tr.t("STORM_TITHE_REPELLED"), "success", UITheme.POSITIVE)
	_settle()

func _settle() -> void:
	if _cycle == null:
		return
	_publish(_cycle.settle_tithe(_industrial_footprint(), ProgressionManager.current_era))

## How much smoke the base makes. This is what the Regency actually measures, and
## what decides how hard the next storm hits.
func _industrial_footprint() -> int:
	var count := 0
	for info in GridManager.get_all_buildings():
		var data: BuildingData = info["data"]
		if data.produces_gold > 0 or data.produces_steel > 0 \
				or data.produces_oil > 0 or data.produces_wood > 0:
			count += 1
	return count

func _resource_name(type: int) -> String:
	match type:
		ResourceManager.Type.STEEL:
			return "steel"
		ResourceManager.Type.OIL:
			return "oil"
		ResourceManager.Type.WOOD:
			return "wood"
		_:
			return "gold"

# ── Persistence ──────────────────────────────────────────────────────

func get_save_data() -> Dictionary:
	if _cycle == null:
		return {}
	var data: Dictionary = _cycle.to_dict()
	data["armed"] = _armed
	return data

func load_save_data(data: Dictionary) -> void:
	_cycle = StormCycleScript.from_dict(data)
	_armed = bool(data.get("armed", false))
	GameConfig.event_production_multiplier = 1.0

func reset() -> void:
	_cycle = StormCycleScript.create()
	_armed = false
	GameConfig.event_production_multiplier = 1.0
