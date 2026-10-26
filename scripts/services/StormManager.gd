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
## anotar, y la madera al final porque es lo que permite reconstruir. La comida
## (2026-10-04) va en la bolsa y cuenta para el porcentaje, asi que tambien se
## cobra, la ultima de todas: es lo que se quita a la mesa de la gente.
const _TITHE_ORDER: Array = [
	ResourceManager.Type.GOLD, ResourceManager.Type.STEEL,
	ResourceManager.Type.OIL, ResourceManager.Type.WOOD,
	ResourceManager.Type.FOOD,
]

var _cycle: StormCycle = null
## The storm stays asleep until the base is real enough to be noticed. In the
## fiction, a province that does not show up in the ledger is not worth a storm.
var _armed: bool = false
## Ganada la Auditoria Final, la Tormenta no vuelve. Vive aqui y no en
## StormCycle a proposito: load_save_data() reconstruye el ciclo entero desde el
## dict, y un from_dict que no lo contemplara lo borraria al cargar.
var _halted: bool = false
## La carga trajo un Diezmo sin cobrar. Transitorio: lo pone load_save_data() y
## lo consume el final de la carga.
var _tithe_to_resume: bool = false
## La parte de moral que la tormenta ya se ha ganado pero que todavia no suma un
## punto entero. Transitorio (una fraccion de punto no merece viajar en el
## guardado): se tira en reset() y al saldar cada Diezmo.
var _morale_debt: float = 0.0
## Una tormenta invocada a mano (Sandbox) esta corriendo aunque el modo tenga el
## reloj apagado. Se apaga sola cuando el ciclo vuelve a la calma.
var _on_demand: bool = false
## Ese Diezmo llego a reclamarse con el arbol en pausa (el menu principal sale
## encima de la partida recien cargada) y espera al primer frame con el juego en
## marcha. Transitorio, como el de arriba.
var _resume_when_running: bool = false
## La tormenta de prueba de la era 1 mientras pasa (otro StormCycle, con
## `trial` puesto), y si ya paso o ya no toca. Las dos viajan en el guardado: la
## prueba sale una vez por partida, tambien si se guarda y se carga en medio.
var _trial: StormCycle = null
var _trial_done: bool = false
## El Impuesto de juguete de la prueba (2026-10-17, feat/cuartel-temprano) esta
## pedido y sin resolver: los Cobradores de prueba bajaron y aun no se fueron (la
## pelea en el tablero sigue, o la partida se guardo en medio). Viaja en el
## guardado: al cargar se vuelve a pedir, como el Diezmo de verdad.
var _trial_tithe_pending: bool = false
## La pelea del tablero abierto es la de ese Impuesto de juguete. Transitorio: una
## pelea no se guarda, y al cargar se vuelve a empezar desde la puerta.
var _trial_tithe_defending: bool = false
## Igual que _resume_when_running, para el Impuesto de juguete. Transitorio.
var _trial_tithe_resume: bool = false
## La Visita (feat/ritmo-colono, decision de Bryan 2026-10-25): solo uno de cada
## `storm_tithe_board_every` Impuestos se pelea en el tablero; los demas los
## resuelve la guarnicion sola con el parte automatico (AutoResolver, las mismas
## reglas). Antes de resolverlo se ofrece ¡PELEAR! durante
## `storm_tithe_choice_seconds`: estos segundos que quedan (> 0 = abierta), la
## severidad y la escolta. Transitorio: un guardado en medio vuelve a pedir el
## Impuesto al cargar (_tithe_to_resume) y la oferta se abre otra vez.
var _tithe_choice_left: float = 0.0
var _tithe_choice_severity: int = 0
var _tithe_choice_roster: Dictionary = {}

func _ready() -> void:
	_cycle = StormCycleScript.create()
	EventBus.phase_advanced.connect(_on_phase_advanced)
	EventBus.game_load_completed.connect(_check_arming)
	EventBus.game_load_completed.connect(_on_game_load_completed)
	EventBus.encounter_ended.connect(_on_encounter_ended)
	# Red de seguridad del Impuesto de juguete: un tablero de su defensa que se
	# cierra sin resultado (no deberia pasar) no lo deja pendiente para siempre.
	EventBus.encounter_closed.connect(_on_encounter_closed)
	EventBus.storm_halted_forever.connect(_on_halted_forever)
	EventBus.final_audit_lost.connect(_on_final_audit_lost)
	_check_arming()

func _process(delta: float) -> void:
	# x2: la simulacion avanza al doble (GameConfig.sim_delta).
	delta = GameConfig.sim_delta(delta)
	# _process no corre con el arbol en pausa: llegar aqui es que el jugador ya
	# solto el menu que tapaba la partida.
	if _resume_when_running:
		_resume_when_running = false
		_resume_tithe()
	if _trial_tithe_resume:
		_trial_tithe_resume = false
		_resume_trial_tithe()
	_tick_tithe_choice(delta)
	_tick_trial(delta)
	if _halted or _cycle == null or not is_armed():
		return
	# Con el tutorial en marcha la Tormenta de verdad no empieza (2026-10-19): el
	# reloj de la calma se para. Una ya empezada (guardado viejo) sigue su curso.
	if _cycle.phase == StormCycle.Phase.CALM and not _on_demand and TutorialManager.blocks_interruptions():
		return
	_publish(_cycle.advance(delta))

# ── Queries ──────────────────────────────────────────────────────────

func get_cycle() -> StormCycle:
	return _cycle

## El reloj corre: armado y con la Tormenta activa en este modo, o invocada a
## mano. En Constructor y Sandbox se arma igual (la fase lo decide) pero no corre.
func is_armed() -> bool:
	return (_armed and GameMode.storm_enabled()) or _on_demand

## La fase que se ve: la de la tormenta de prueba mientras pasa, si no la del
## reloj de verdad. El cielo, el HUD y la cola leen esta, asi que la prueba se
## ve y se siente como una tormenta sin tocar el reloj que cuenta.
func get_phase() -> int:
	var cycle: StormCycle = _visible_cycle()
	return cycle.phase if cycle != null else StormCycle.Phase.CALM

## What the storm actually hits with: the severity the base earned by growing,
## plus whatever a false alarm deferred onto it.
func get_severity() -> int:
	var cycle: StormCycle = _visible_cycle()
	return cycle.effective_severity() if cycle != null else 1

func _visible_cycle() -> StormCycle:
	return _trial if _trial != null else _cycle

## La tormenta de prueba esta pasando (Aviso, Ceniza o Tormenta).
func is_trial_running() -> bool:
	return _trial != null

## La tormenta de prueba ya paso (o ya no tocaba: llego la Fundicion antes).
func is_trial_done() -> bool:
	return _trial_done

## Severity a false alarm has postponed onto the next storm. Never shown: the
## whole point of deferring it is that the player cannot price the next one.
func get_deferred_severity() -> int:
	return _cycle.deferred_severity if _cycle != null else 0

func is_ashfall() -> bool:
	var cycle: StormCycle = _visible_cycle()
	return cycle != null and cycle.is_ashfall()

func is_storming() -> bool:
	var cycle: StormCycle = _visible_cycle()
	return cycle != null and cycle.is_storming()

## Seconds until the ash starts falling. Dev tooling only — the HUD stopped
## counting, and a false alarm can make this number mean nothing at all.
func seconds_until_ash() -> float:
	return _cycle.seconds_until_ash() if _cycle != null else 0.0

func storms_survived() -> int:
	return _cycle.storms_survived if _cycle != null else 0

func tithes_repelled() -> int:
	return _cycle.tithes_repelled if _cycle != null else 0

# ── Arming ───────────────────────────────────────────────────────────

## The clock only starts once the base has grown past the Foundation phase —
## the same threshold at which consumption and events wake up. Before that the
## player is still invisible, and that is exactly the point.
func _check_arming() -> void:
	if _halted or _armed:
		return
	if ProgressionManager.current_phase >= GameConfig.storm_arm_phase:
		_armed = true
		# La primera Orden sale con el reloj: desde la Fundicion hay a quien pedirle.
		_ensure_order(true)

## Hay tormenta en marcha (cualquier fase que no sea la calma). Es la mitad de
## StormManager de la deuda de GameConfig: la tabla de balance no debe
## preguntarle la fase a un autoload posterior; recibe este bool.
func is_cycle_active() -> bool:
	return not _halted and _cycle != null and _cycle.phase != StormCycle.Phase.CALM

func is_halted() -> bool:
	return _halted

## La Regencia ha perdido la Auditoria Final. Se para el reloj para siempre y se
## levanta cualquier efecto que hubiera encima. Sin bool: quien emite esto ya ha
## decidido; aqui solo se obedece.
func _on_halted_forever() -> void:
	_halted = true
	_armed = false
	_trial = null
	_trial_done = true
	_trial_tithe_pending = false
	_trial_tithe_defending = false
	_trial_tithe_resume = false
	_close_tithe_choice()
	GameConfig.event_production_multiplier = 1.0
	_cycle = StormCycleScript.create()
	EventBus.storm_phase_changed.emit(StormCycle.Phase.CALM, 0.0)

## Perder el asedio no es perder la partida, pero pasa por encima: Diezmo a
## severidad maxima y una tormenta maxima de daño. La base queda en ruinas y con
## el reloj corriendo, y el jugador reconstruye y vuelve a convocarlos.
func _on_final_audit_lost(_wave: int) -> void:
	var worst: int = GameConfig.storm_severity_max
	_damage_buildings(worst)
	# Sin rebajas: esto no es la visita de la Orden, es el castigo del asedio.
	var taken: Dictionary = _collect_tithe(worst, false)
	EventBus.tithe_resolved.emit(false, taken)

func _on_phase_advanced(_phase: int) -> void:
	_check_arming()

# ── La tormenta de prueba (era 1) ────────────────────────────────────
#
# Un ensayo guionizado hacia el minuto 5 de partida: Aviso, Ceniza, Tormenta y
# calma, con los mismos avisos y consejos que la de verdad, pero sin Diezmo, sin
# romper edificios ni la cola y con poca moral. Va en su propio StormCycle para
# que el reloj de verdad (que se arma con la Fundicion) no se entere.

## Cuenta la partida hasta la hora de la prueba y la mueve mientras pasa.
func _tick_trial(delta: float) -> void:
	if _trial != null:
		_publish_trial(_trial.advance(delta))
		return
	# Solo con una partida en marcha: sin ella no hay a quien ensenarle nada.
	if GameManager.is_started():
		check_trial()

## Lanza la prueba si ya toca. Devuelve true si la lanzo. Publica para las pruebas.
func check_trial() -> bool:
	if _trial != null or _trial_done or _halted or not GameMode.storm_trial_enabled():
		return false
	# Si la Fundicion ya armo la Tormenta de verdad, la prueba sobra: no se
	# ensaya lo que ya viene de camino.
	if _armed or ProgressionManager.current_era > 1:
		_trial_done = true
		return false
	# Nunca en medio del tutorial (queja de Bryan, 2026-10-19): espera a que acabe
	# y llega storm_trial_after_guide despues, con su Aviso delante.
	if TutorialManager.blocks_interruptions():
		return false
	if ProgressionManager.get_played_seconds() >= trial_due_at():
		return start_trial()
	return false

## Cuando toca la tormenta de prueba, en segundos de partida jugados: a su hora
## (storm_trial_at) y nunca antes de storm_trial_after_guide despues de acabar el
## tutorial. Una partida sin esa marca (guardado de antes) la tiene a su hora.
func trial_due_at() -> float:
	var at: float = GameConfig.get_storm_trial_at()
	var finished: float = TutorialManager.guide_finished_at
	if finished >= 0.0:
		at = maxf(at, finished + GameConfig.get_duration(GameConfig.storm_trial_after_guide))
	return at

## Lanza la tormenta de prueba ya. Una sola vez por partida. Publica para las
## pruebas y la sonda; el juego la lanza solo desde _tick_trial().
func start_trial() -> bool:
	if _trial != null or _trial_done or _halted:
		return false
	_trial = StormCycleScript.create_trial()
	_publish_trial(_trial.summon_now())
	return true

## Lo mismo que _publish() para la de prueba, con sus textos y sin cobro. Las
## senales son las de siempre: el cielo, el HUD, el sonido y los consejos del
## tutorial reaccionan igual que a una de verdad.
func _publish_trial(events: Array) -> void:
	for event in events:
		match event.get("e", ""):
			"phase":
				var phase: int = int(event["phase"])
				_on_trial_phase(phase)
				EventBus.storm_phase_changed.emit(phase, float(event["left"]))
			"incoming":
				EventBus.storm_incoming.emit(float(event["seconds"]))
				EventBus.notification_posted.emit(Tr.t("STORM_TRIAL_INCOMING"), "warning", UITheme.WARNING)
			"ash_started":
				EventBus.storm_ash_started.emit()
				EventBus.notification_posted.emit(Tr.t("STORM_TRIAL_ASH"), "warning", UITheme.WARNING)
			"storm_started":
				EventBus.storm_started.emit(int(event["severity"]))
				EventBus.notification_posted.emit(Tr.t("STORM_TRIAL_STARTED"), "danger", UITheme.DANGER)
			"storm_tick":
				_apply_trial_tick(int(event["phase"]))
				EventBus.storm_tick.emit(int(event["phase"]), float(event["left"]))
			"storm_ended":
				EventBus.storm_ended.emit(int(event["severity"]))
				EventBus.notification_posted.emit(Tr.t("STORM_TRIAL_ENDED"), "info", UITheme.TEXT_DIM)
			"trial_tithe":
				begin_trial_tithe()

# ── El Impuesto de juguete (2026-10-17, feat/cuartel-temprano) ───────
#
# Al escampar la prueba bajan unos Cobradores de juguete. Con tropas en casa se
# pelea en el tablero contra una escolta minima y debil (uno por soldado en
# casa, hasta storm_trial_tithe_force_max): es la primera pelea de la partida si
# aun no hubo mision, asi que el combate guiado (`basics`) sale solo. Sin tropas
# se llevan un poco de la bolsa (storm_trial_tithe_pct, con tope) y el parte
# explica que con un Cuartel y soldados no se lo habrian llevado. Nunca edificios,
# trabajadores ni dano; no cuenta como Diezmo (ni escolta que crece, ni rebaja,
# ni Mercado): por eso no pasa por tithe_resolved.

## Los Cobradores de juguete para `home` unidades en casa. Pura, para las pruebas.
static func trial_tithe_roster(home: int) -> Dictionary:
	var force: int = clampi(home, 1, maxi(1, GameConfig.storm_trial_tithe_force_max))
	return {GameConfig.storm_trial_tithe_unit: force}

func is_trial_tithe_pending() -> bool:
	return _trial_tithe_pending

## Bajan los Cobradores de juguete. Publico para las pruebas; el juego lo llama al
## escampar la tormenta de prueba (evento `trial_tithe`) y al cargar una partida
## guardada con ellos en la puerta.
func begin_trial_tithe() -> void:
	if _halted or not GameMode.tithe_enabled():
		_trial_tithe_pending = false
		return
	_trial_tithe_pending = true
	_trial_tithe_defending = false
	var garrison: Dictionary = CombatManager.get_garrison()
	if garrison.is_empty():
		_pay_trial_tithe()
		return
	var roster: Dictionary = trial_tithe_roster(CombatManager.roster_size(garrison))
	var scale: float = GameConfig.storm_trial_tithe_enemy_scale
	EventBus.notification_posted.emit(Tr.t("STORM_TRIAL_TITHE_DEFEND"), "notice", UITheme.ACCENT)
	# Con un tablero ya abierto (una mision a medias) no se abre otro encima: las
	# tropas de casa pelean solas, como con el Diezmo de verdad.
	if CombatManager.is_board_open():
		var outcome: Dictionary = CombatManager.auto_resolve_defense(roster, scale)
		if bool(outcome.get("fought", false)) and bool(outcome.get("victory", false)):
			_resolve_trial_tithe(true, {})
		else:
			_pay_trial_tithe()
		return
	_trial_tithe_defending = true
	if not CombatManager.start_defense(roster, [], scale):
		_trial_tithe_defending = false
		_pay_trial_tithe()

## Sin defensa (o perdida): se llevan un poco de la bolsa. Solo recursos.
func _pay_trial_tithe() -> void:
	var taken: Dictionary = {}
	var debt: int = GameConfig.get_trial_tithe_debt(ResourceManager.get_total_stored())
	_take_from_stores(debt, taken)
	_resolve_trial_tithe(false, taken)

func _resolve_trial_tithe(repelled: bool, taken: Dictionary) -> void:
	_trial_tithe_pending = false
	_trial_tithe_defending = false
	if repelled:
		EventBus.notification_posted.emit(Tr.t("STORM_TRIAL_TITHE_REPELLED"), "success", UITheme.POSITIVE)
	else:
		EventBus.notification_posted.emit(Tr.t("STORM_TRIAL_TITHE_PAID"), "notice", UITheme.WARNING)
	EventBus.trial_tithe_resolved.emit(repelled, taken)
	GameManager.request_save()

func _on_encounter_closed() -> void:
	if _trial_tithe_defending:
		_pay_trial_tithe()

## Al cargar con los Cobradores de juguete en la puerta: se vuelven a pedir con el
## juego en marcha (el menu principal pausa encima de la partida cargada).
func _resume_trial_tithe() -> void:
	if not _trial_tithe_pending or _trial_tithe_defending:
		return
	if is_inside_tree() and get_tree().paused:
		_trial_tithe_resume = true
		return
	begin_trial_tithe()

## Produccion de la prueba: un recorte suave en la Ceniza y en la Tormenta, y de
## vuelta a 1,0 al escampar. Al volver la calma la prueba se da por cerrada.
func _on_trial_phase(phase: int) -> void:
	match phase:
		StormCycle.Phase.ASH, StormCycle.Phase.STORM:
			GameConfig.event_production_multiplier = GameConfig.storm_trial_production_multiplier
		StormCycle.Phase.CALM:
			GameConfig.event_production_multiplier = 1.0
			if _trial != null and _trial.finished:
				_trial = null
				_trial_done = true
				_morale_debt = 0.0
		_:
			GameConfig.event_production_multiplier = 1.0

## Un tic de la prueba: solo moral, una fraccion de la de verdad. No rompe nada.
func _apply_trial_tick(phase: int) -> void:
	var bleed: float = GameConfig.storm_morale_per_tick * float(_trial.effective_severity()) \
		* GameConfig.storm_trial_morale_factor
	if phase == StormCycle.Phase.STORM:
		bleed *= GameConfig.storm_morale_storm_multiplier
	_morale_debt += bleed
	var whole: int = int(floor(_morale_debt))
	if whole > 0:
		_morale_debt -= float(whole)
		PopulationManager.adjust_morale(-whole)

# ── Event translation ────────────────────────────────────────────────

func _publish(events: Array) -> void:
	for event in events:
		match event.get("e", ""):
			"phase":
				# La tormenta invocada termina al volver la calma.
				if int(event["phase"]) == StormCycle.Phase.CALM and not GameMode.storm_enabled():
					_on_demand = false
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
				_well_repairs()
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
##
## La moral se cobra con decimales: cada tic suma su parte a `_morale_debt` y solo
## se descuentan los puntos enteros. Con el redondeo por tic, cualquier sangria por
## debajo de 0,5 se volvia cero y cualquier cosa por encima valia un punto entero
## por tic, asi que no habia forma de que una tormenta leve costara poco: con 24
## tics por tormenta, la de severidad 1 se llevaba 96 puntos (docs/22-linea-jugable.md).
func _apply_storm_tick(phase: int) -> void:
	var severity: int = _cycle.effective_severity()
	var bleed: float = GameConfig.storm_morale_per_tick * float(severity)
	if phase == StormCycle.Phase.STORM:
		bleed *= GameConfig.storm_morale_storm_multiplier
	_morale_debt += bleed
	var whole: int = int(floor(_morale_debt))
	if whole > 0:
		_morale_debt -= float(whole)
		PopulationManager.adjust_morale(-whole)
	if phase == StormCycle.Phase.STORM:
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
			# Un Pozo cerca (meta de UtilityEffects) quita parte del golpe.
			var cover: float = float(node.get_meta("well_cover", 0.0))
			if cover > 0.0:
				amount = maxi(1, int(round(float(amount) * (1.0 - cover))))
			BuildingHealth.damage_building(node, amount)
			hits -= 1

## Pasada la Tormenta, los Pozos (1.1) remiendan un poco lo que tienen cerca:
## cada edificio herido, no en ruinas, con `well_cover` recupera
## `well_repair_ratio` de su salud. Gratis: es el agua a mano, no la obra.
func _well_repairs() -> int:
	var healed := 0
	for info in GridManager.buildings_view():
		var node: Node = info.get("node")
		if node == null or not is_instance_valid(node):
			continue
		if float(node.get_meta("well_cover", 0.0)) <= 0.0:
			continue
		if BuildingHealth.is_ruined(node) or not BuildingHealth.is_damaged(node):
			continue
		var amount := maxi(1, int(round(float(BuildingHealth.get_max_health(node)) * GameConfig.well_repair_ratio)))
		if BuildingHealth.heal(node, amount) > 0:
			healed += 1
	return healed

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

	for info in GridManager.buildings_view():
		var data: BuildingData = info["data"]
		var node: Node = info["node"]
		if node == null or not is_instance_valid(node) or BuildingHealth.is_ruined(node):
			continue
		if BuildingHealth.is_immune(node):
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
	for info in GridManager.buildings_view():
		var data: BuildingData = info["data"]
		if not data.id in GameConfig.storm_essential_buildings:
			continue
		var node: Node = info["node"]
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
	for info in GridManager.buildings_view():
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
	# Un modo sin Diezmo: la tormenta pasa y nadie baja a cobrar.
	if not GameMode.tithe_enabled():
		EventBus.tithe_resolved.emit(true, {})
		_settle()
		return
	# Con la Auditoria Final en el tablero no hay Diezmo aparte: la Regencia ya
	# esta en la puerta, y cobrar por un lado mientras se pelea por el otro pone
	# a la misma guarnicion a defender dos sitios a la vez. get_garrison() no sabe
	# de las unidades que estan en las oleadas del asedio, asi que las volveria a
	# alistar y les descontaria las bajas por duplicado: el jugador perderia
	# soldados que no murieron.
	if ProgressionManager.is_final_audit_active():
		EventBus.notification_posted.emit(
			Tr.t("STORM_TITHE_DURING_AUDIT"), "warning", UITheme.WARNING)
		EventBus.tithe_resolved.emit(true, {})
		_settle()
		return

	var roster: Dictionary = assessor_roster(severity)
	# Con el tablero ocupado (una expedicion a medias) la guarnicion que quedo en
	# casa pelea sola: el mismo Encounter, resuelto a ciegas, sin abrir otro
	# tablero encima del que el jugador esta jugando.
	# is_board_open() y no is_in_encounter(): mientras el jugador lee el parte de
	# la pelea anterior el tablero sigue en pantalla aunque ya no se juegue, y
	# abrir la defensa encima se lo borraria de delante sin haberlo leido.
	if CombatManager.is_board_open():
		_auto_resolve_tithe(roster, severity)
		return
	# La Visita: este Impuesto no toca tablero. La guarnicion lo resuelve sola
	# (parte automatico), salvo que el jugador pulse ¡PELEAR! mientras se ofrece.
	if not is_visit_due():
		_open_tithe_choice(severity, roster)
		return
	_defend_on_board(roster, severity)

## El Impuesto en el tablero: la guarnicion de casa contra la escolta, o el cobro
## directo si no hay nadie.
func _defend_on_board(roster: Dictionary, severity: int) -> void:
	if CombatManager.start_defense(roster):
		return
	EventBus.notification_posted.emit(Tr.t("STORM_TITHE_UNDEFENDED"), "danger", UITheme.DANGER)
	_pay_tithe(severity)

# ── La Visita: uno de cada tres Impuestos en el tablero ──────────────

## ¿Este Impuesto (el que esta cobrando ahora, o el proximo) es la Visita? El
## primero de verdad siempre (ensena), luego uno de cada `storm_tithe_board_every`.
## Cuenta los Impuestos ya saldados (StormCycle.storms_survived), asi que es puro
## y vale igual despues de cargar. La prueba de la era 1 no cuenta (no salda).
func is_visit_due() -> bool:
	var every: int = maxi(1, GameConfig.storm_tithe_board_every)
	return storms_survived() % every == 0

## Cuantos Impuestos con parte automatico quedan antes de la proxima Visita,
## contando desde el siguiente (0 = el siguiente es la Visita).
func tithes_before_visit() -> int:
	var every: int = maxi(1, GameConfig.storm_tithe_board_every)
	return posmod(every - posmod(storms_survived(), every), every)

## Se esta ofreciendo ¡PELEAR! en un Impuesto con parte automatico.
func is_tithe_choice_open() -> bool:
	return _tithe_choice_left > 0.0

func tithe_choice_seconds_left() -> float:
	return maxf(0.0, _tithe_choice_left)

func _open_tithe_choice(severity: int, roster: Dictionary) -> void:
	_tithe_choice_severity = severity
	_tithe_choice_roster = roster.duplicate()
	_tithe_choice_left = maxf(0.01, GameConfig.storm_tithe_choice_seconds)
	EventBus.notification_posted.emit(Tr.t("STORM_TITHE_AUTO_OFFER"), "warning", UITheme.WARNING)
	EventBus.tithe_choice_changed.emit(true)

func _close_tithe_choice() -> void:
	var was_open: bool = _tithe_choice_left > 0.0 or not _tithe_choice_roster.is_empty()
	_tithe_choice_left = 0.0
	_tithe_choice_roster = {}
	if was_open:
		EventBus.tithe_choice_changed.emit(false)

func _tick_tithe_choice(delta: float) -> void:
	if _tithe_choice_left <= 0.0:
		return
	_tithe_choice_left -= delta
	if _tithe_choice_left > 0.0:
		return
	resolve_tithe_auto()

## El jugador deja que su guarnicion se encargue ya (o se acabo el tiempo).
func resolve_tithe_auto() -> bool:
	if _tithe_choice_roster.is_empty():
		return false
	var roster: Dictionary = _tithe_choice_roster.duplicate()
	var severity: int = _tithe_choice_severity
	_close_tithe_choice()
	if _cycle == null or not _cycle.is_collecting() or _halted:
		return false
	_auto_resolve_tithe(roster, severity, true)
	return true

## ¡PELEAR!: este Impuesto, que iba con parte automatico, se pelea en el tablero.
## false si no hay oferta abierta o si el tablero esta ocupado.
func fight_this_tithe() -> bool:
	if not is_tithe_choice_open() or CombatManager.is_board_open():
		return false
	var roster: Dictionary = _tithe_choice_roster.duplicate()
	var severity: int = _tithe_choice_severity
	_close_tithe_choice()
	if _cycle == null or not _cycle.is_collecting() or _halted:
		return false
	_defend_on_board(roster, severity)
	return true

## El Diezmo cae con el jugador de expedicion. La defensa se resuelve al
## instante y el Diezmo con ella: aqui no se espera `encounter_ended`, porque esa
## senal es del tablero abierto, no de esta pelea. El parte llega por
## `defense_auto_resolved` y por un aviso con bajas y rondas.
## `routine` (la Visita): no es que el ejercito este fuera, es uno de los
## Impuestos que se resuelven solos. El parte lo dice ("Parte automatico").
func _auto_resolve_tithe(roster: Dictionary, severity: int, routine: bool = false) -> void:
	var outcome: Dictionary = CombatManager.auto_resolve_defense(roster, -1.0, "auto_tithe" if routine else "")
	if not bool(outcome.get("fought", false)):
		EventBus.notification_posted.emit(Tr.t("STORM_TITHE_UNDEFENDED"), "danger", UITheme.DANGER)
		_pay_tithe(severity)
		return
	var summary: Dictionary = outcome.get("summary", {})
	var dead: int = 0
	for count in summary.get("casualties", {}).values():
		dead += int(count)
	var rounds: int = int(outcome.get("rounds", 0))
	if bool(outcome.get("victory", false)):
		EventBus.notification_posted.emit(
			Tr.t("MSG_TITHE_AUTO_WON" if routine else "MSG_DEFENSE_AUTO_WON") % [dead, rounds], "success", UITheme.POSITIVE)
		repel_tithe()
	else:
		EventBus.notification_posted.emit(
			Tr.t("MSG_TITHE_AUTO_LOST" if routine else "MSG_DEFENSE_AUTO_LOST") % [dead, rounds], "danger", UITheme.DANGER)
		_pay_tithe(severity)

## The force that comes to collect. A line of Assessors with guns behind it,
## growing with severity — the more you are worth, the more they send.
##
## Y creciendo también con cada Diezmo que le has repelido. No es rencor: es
## que una provincia capaz de echarlos figura en el libro como una que puede
## pagar más, y la próxima partida de gasto se aprueba sola. Ganarles hoy no
## quita el problema, lo encarece.
func assessor_roster(severity: int) -> Dictionary:
	# Gobernador: la escolta trae `tithe_force_mult` veces los cuerpos.
	var raw: float = float(GameConfig.storm_tithe_base_force + severity - 1) \
		* GameConfig.get_assessor_escalation(tithes_repelled()) \
		* GameMode.tithe_force_mult()
	var force: int = clampi(roundi(raw), 1, GameConfig.combat_deploy_cap)
	var guns: int = force / 3
	var line: int = maxi(1, force - guns)
	var roster: Dictionary = {"infantry": line}
	if guns > 0:
		roster["artillery"] = guns
	return roster

## Settles the collection once the board is done with it.
func _on_encounter_ended(victory: bool, _turns: int) -> void:
	# La defensa del Impuesto de juguete: ganada, se van sin nada; perdida (o
	# abandonada), se llevan un poco, como si no hubiera habido tropas.
	if _trial_tithe_defending and CombatManager.is_defending():
		if victory:
			_resolve_trial_tithe(true, {})
		else:
			_pay_trial_tithe()
		return
	if _cycle == null or not _cycle.is_collecting():
		return
	if not CombatManager.is_defending():
		return
	if victory:
		repel_tithe()
	else:
		EventBus.notification_posted.emit(Tr.t("STORM_TITHE_PAID"), "danger", UITheme.DANGER)
		_pay_tithe(_cycle.effective_severity())

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
func _collect_tithe(severity: int, apply_discount: bool = true) -> Dictionary:
	var taken: Dictionary = {}
	var debt: int = GameConfig.get_tithe_debt(
		severity, ProgressionManager.current_era, ResourceManager.get_total_stored(),
		storms_survived() == 0)
	# Las rebajas de la Orden (entrega, escaramuza...) recortan la deuda entera,
	# porcentaje y Cuota Minima juntos, antes de empezar a cobrar.
	if apply_discount and _cycle != null:
		debt = _cycle.discounted(debt)

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
	for info in GridManager.buildings_view():
		var data: BuildingData = info["data"]
		var node: Node = info["node"]
		if node == null or not is_instance_valid(node) or BuildingHealth.is_ruined(node):
			continue
		if BuildingHealth.is_immune(node):
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
	_settle(true)

func _settle(repelled: bool = false) -> void:
	if _cycle == null:
		return
	_morale_debt = 0.0
	_publish(_cycle.settle_tithe(_industrial_footprint(), ProgressionManager.current_era, repelled))
	# settle_tithe() ya tiro la Orden vieja: la de la calma que empieza.
	_ensure_order(true)

## How much smoke the base makes. This is what the Regency actually measures, and
## what decides how hard the next storm hits.
func _industrial_footprint() -> int:
	var count := 0
	for info in GridManager.buildings_view():
		var data: BuildingData = info["data"]
		if data.produces_gold > 0 or data.produces_steel > 0 \
				or data.produces_oil > 0 or data.produces_wood > 0:
			count += 1
	return count

func _resource_name(type: int) -> String:
	var n: String = ResourceManager.get_type_name(type)
	return n if n != "unknown" else "gold"

# ── Persistence ──────────────────────────────────────────────────────

func get_save_data() -> Dictionary:
	if _cycle == null:
		return {}
	var data: Dictionary = _cycle.to_dict()
	data["armed"] = _armed
	data["halted"] = _halted
	data["on_demand"] = _on_demand
	data["trial_done"] = _trial_done
	data["trial_storm"] = _trial.to_dict() if _trial != null else {}
	data["trial_tithe_pending"] = _trial_tithe_pending
	return data

func load_save_data(data: Dictionary) -> void:
	_cycle = StormCycleScript.from_dict(data)
	_armed = bool(data.get("armed", false))
	_halted = bool(data.get("halted", false))
	_on_demand = bool(data.get("on_demand", false)) and not _halted
	if _halted:
		_armed = false
	# El castigo a la produccion sale de la fase cargada, no se da por levantado:
	# cargar con la ceniza cayendo ya no la limpiaba.
	if _halted:
		GameConfig.event_production_multiplier = 1.0
	else:
		_on_phase_entered(_cycle.phase)
	# La prueba: hecha o no (un guardado de antes no trae la clave: no hecha), y
	# si se guardo en medio, vuelve en su fase con su recorte de produccion.
	_trial_done = bool(data.get("trial_done", false)) or _halted
	_trial = null
	var trial_data: Variant = data.get("trial_storm", {})
	if not _trial_done and trial_data is Dictionary and not (trial_data as Dictionary).is_empty():
		_trial = StormCycleScript.from_dict(trial_data)
		_trial.trial = true
		if _trial.finished or _trial.phase == StormCycle.Phase.CALM:
			_trial = null
			_trial_done = true
		else:
			_on_trial_phase(_trial.phase)
	_tithe_to_resume = not _halted and _cycle.is_collecting()
	_tithe_choice_left = 0.0
	_tithe_choice_roster = {}
	# Un guardado de antes de la Orden llega sin encargo: se sortea uno sin abrir
	# la tarjeta (no es una calma nueva, es la de siempre que ahora se ve).
	_ensure_order(false)
	EventBus.storm_order_changed.emit(false)
	# El Impuesto de juguete a medias (se guardo con los Cobradores de prueba en la
	# puerta o en plena pelea): vuelve a pedirse al terminar la carga. Un guardado
	# de antes no trae la clave: no hay nada pendiente.
	var tt: Variant = data.get("trial_tithe_pending", false)
	_trial_tithe_pending = tt is bool and tt and not _halted
	_trial_tithe_defending = false
	_trial_tithe_resume = false

## El Diezmo que la carga trajo pendiente se reclama cuando la escena ya escucha,
## y diferido para ir detras de cualquier otro oyente de game_load_completed (la
## pantalla de combate abre el mapa de una campana ahi, y abrir la defensa antes
## la dejaria tapada).
func _on_game_load_completed() -> void:
	if _tithe_to_resume:
		_resume_tithe.call_deferred()
	if _trial_tithe_pending:
		_resume_trial_tithe.call_deferred()

## Se reclama por el mismo camino que en partida: defensa con la guarnicion que
## haya en casa, o cobro directo si no hay nadie. El tablero no se guarda, asi
## que un Diezmo interrumpido vuelve a empezar desde la puerta.
##
## Con el arbol en pausa no: el menu principal pausa en su _ready, antes de que
## la partida cargue, y la defensa se abria detras de el. Espera a que el juego
## vuelva a correr (_process).
func _resume_tithe() -> void:
	if not _tithe_to_resume:
		return
	if is_inside_tree() and get_tree().paused:
		_resume_when_running = true
		return
	_tithe_to_resume = false
	if _halted or _cycle == null or not _cycle.is_collecting():
		return
	var severity: int = _cycle.effective_severity()
	EventBus.notification_posted.emit(Tr.t("STORM_TITHE_RESUMED"), "warning", UITheme.WARNING)
	EventBus.tithe_demanded.emit(severity)
	_begin_tithe(severity)

func reset() -> void:
	_cycle = StormCycleScript.create()
	_armed = false
	_halted = false
	_tithe_to_resume = false
	_tithe_choice_left = 0.0
	_tithe_choice_roster = {}
	_tithe_choice_severity = 0
	_morale_debt = 0.0
	_on_demand = false
	_resume_when_running = false
	_trial = null
	_trial_done = false
	_trial_tithe_pending = false
	_trial_tithe_defending = false
	_trial_tithe_resume = false
	GameConfig.event_production_multiplier = 1.0

# ── La Orden de la Regencia (doc 21 §2.2; docs/06 §Orden de la Regencia) ──
#
# Cada calma, la Regencia dice lo que se llevara en la proxima visita y como
# pagar menos. El estado (rebajas, encargo, barometro) vive en StormCycle y viaja
# en el guardado `storm`; aqui solo se decide quien puede verlo y se cobra.

## Hay Orden que ensenar: reloj armado, con Diezmo en este modo y sin parar.
func order_visible() -> bool:
	return is_armed() and not _on_demand and GameMode.tithe_enabled() \
		and not _halted and _cycle != null

## API PUBLICA para cualquier fuente de rebaja (la rama de escaramuzas la usa al
## ganar una salida: `add_tithe_discount("expedicion", GameConfig.storm_order_expedition_pct)`).
## Aditiva y con tope (`storm_order_discount_max`); dura hasta el proximo Diezmo.
## `source` es un nombre corto y estable ("entrega", "expedicion", "contrato"...).
## Avisa al jugador y emite `storm_order_changed`. Devuelve la rebaja total, o
## -1.0 si no se apunto (sin Orden activa o con los Tasadores ya en la puerta).
func add_tithe_discount(source: String, pct: float, notify: bool = true) -> float:
	if not order_visible() or pct <= 0.0 or _cycle.is_collecting():
		return -1.0
	var before: float = _cycle.tithe_discount()
	var total: float = _cycle.add_tithe_discount(source, pct)
	if notify and total > before:
		EventBus.notification_posted.emit(
			Tr.t("STORM_ORDER_DISCOUNT") % [roundi((total - before) * 100.0), roundi(total * 100.0)],
			"notice", UITheme.POSITIVE)
	EventBus.storm_order_changed.emit(false)
	return total

## La rebaja total del proximo Diezmo (0..tope).
func get_tithe_discount() -> float:
	return _cycle.tithe_discount() if _cycle != null else 0.0

## Lo que una fuente concreta ya ha rebajado en esta calma.
func get_discount_from(source: String) -> float:
	return _cycle.discount_from(source) if _cycle != null else 0.0

## El encargo de esta calma ({"res", "amount", "done"}), copia. Vacio si no hay.
func get_order() -> Dictionary:
	return _cycle.order.duplicate() if _cycle != null else {}

## Se puede entregar ya: hay encargo abierto, no estan cobrando y alcanza.
func can_deliver_order() -> bool:
	if not order_visible() or not _cycle.has_open_order() or _cycle.is_collecting():
		return false
	var type: int = ResourceManager.name_to_type(String(_cycle.order["res"]))
	return type >= 0 and ResourceManager.get_amount(type) >= int(_cycle.order["amount"])

## Paga el encargo y apunta su rebaja. true si se entrego.
func deliver_order() -> bool:
	if not can_deliver_order():
		return false
	var res: String = String(_cycle.order["res"])
	var amount: int = int(_cycle.order["amount"])
	if not ResourceManager.spend(ResourceManager.name_to_type(res), amount):
		return false
	var before: float = _cycle.tithe_discount()
	_cycle.complete_order()
	EventBus.notification_posted.emit(
		Tr.t("STORM_ORDER_DELIVERED") % [amount, Tr.res_name(res),
			roundi((_cycle.tithe_discount() - before) * 100.0)],
		"notice", UITheme.POSITIVE)
	EventBus.storm_order_changed.emit(false)
	GameManager.request_save()
	return true

## El barometro de la calma ({"fill", "low", "high"}), o vacio si no toca: fuera
## de la calma, sin reloj, con la Tormenta parada o en un modo sin ella.
func get_barometer() -> Dictionary:
	if _halted or _cycle == null or _on_demand or not (_armed and GameMode.storm_enabled()):
		return {}
	return _cycle.barometer()

## Lo que pedira el proximo Diezmo, para la tarjeta. Con la severidad que la
## colonia se ha ganado (`_cycle.severity`), NO con la efectiva: lo que dejo
## pendiente una falsa alarma sigue sin decirse (puede llevarse algo mas).
##   ratio / ratio_after   fraccion de lo guardado, antes y despues de rebajas
##   floor / floor_after   la Cuota Minima (0 en la primera visita)
##   escort                cuantos Tasadores bajan
##   discount              la rebaja total
func tithe_preview() -> Dictionary:
	if _cycle == null:
		return {}
	var sev: int = clampi(_cycle.severity, 1, GameConfig.storm_severity_max)
	var discount: float = _cycle.tithe_discount()
	var ratio: float = GameConfig.get_tithe_ratio(sev) * GameMode.tithe_mult()
	var floor_debt: int = GameConfig.get_tithe_debt(
		sev, ProgressionManager.current_era, 0, storms_survived() == 0)
	var escort: int = 0
	for count in assessor_roster(sev).values():
		escort += int(count)
	return {
		"ratio": ratio,
		"ratio_after": ratio * (1.0 - discount),
		"floor": floor_debt,
		"floor_after": _cycle.discounted(floor_debt),
		"escort": escort,
		"discount": discount,
	}

## Las torres en pie y lo que quitan del daño, para la tercera via de la tarjeta.
func tower_status() -> Dictionary:
	var towers: int = _standing_towers()
	return {
		"standing": towers,
		"goal": maxi(1, GameConfig.storm_order_towers_goal),
		"mitigation": GameConfig.get_storm_mitigation(towers),
		"goal_mitigation": GameConfig.get_storm_mitigation(maxi(1, GameConfig.storm_order_towers_goal)),
	}

## Sortea el encargo si falta. Pide materiales que la colonia ya sabe hacer; si
## no hay ninguno, madera u oro. No pisa un encargo que ya existe (idempotente:
## cargar dos veces no cambia la Orden).
func _ensure_order(fresh: bool) -> void:
	if not order_visible() or _cycle.is_collecting() or not _cycle.order.is_empty():
		return
	_cycle.roll_order(_order_candidates())
	if not _cycle.order.is_empty():
		EventBus.storm_order_changed.emit(fresh)

func _order_candidates() -> Array:
	var out: Array = []
	for type in ResourceManager.MATERIALS:
		if ResourceManager.is_unlocked(type):
			out.append(ResourceManager.get_type_name(type))
	if out.is_empty():
		out = ["wood", "gold"]
	return out

# ── modos-de-juego ──

## Sandbox: la tormenta viene ahora. Entra en la Advertencia (que esta vez no
## puede ser falsa alarma) y sigue el ciclo de siempre: ceniza, tormenta,
## Diezmo. Al volver la calma se para otra vez. Solo desde la calma y nunca con
## la Tormenta parada para siempre.
func invoke_storm() -> bool:
	if not GameMode.sandbox_tools() or _halted or _cycle == null:
		return false
	if _cycle.phase != StormCycle.Phase.CALM:
		return false
	_on_demand = true
	_publish(_cycle.summon_now())
	EventBus.sandbox_invoked.emit("storm")
	return true

func is_on_demand() -> bool:
	return _on_demand
