extends RefCounted
class_name StormCycle
## The clock the whole game is measured against: calm, warning, ash, storm, tithe.
##
## Pure state — no nodes, no EventBus, no timers. `advance(delta)` returns an Array
## of event dictionaries and StormManager republishes them (same contract as
## Encounter). That is what lets a hundred storm cycles run headless in a test.
##
## The storm is **dispatched, not rolled**. What the dice decide is *when* the
## calm ends and *whether* a Warning amounts to anything — never how hard it hits
## once it does, and never without notice. A disaster you cannot prepare for is
## noise; a disaster that always means the same thing is arithmetic. This sits
## between the two.

enum Phase {
	CALM,      ## Counting down. Nothing on the horizon yet.
	WARNING,   ## Announced and harmless. The clean window to decide in.
	ASH,       ## Dirty air: production halves, morale bleeds. Nothing falls down.
	STORM,     ## Overhead. Production crawls, morale bleeds hard, roofs go.
	TITHE,     ## The Assessors are on the board. The clock is held.
}

var phase: int = Phase.CALM
var seconds_left: float = 0.0
## Severity the base has earned by growing. What the next storm actually lands
## with is `effective_severity()`: this, plus anything a false alarm deferred.
var severity: int = 1
## Assessments postponed by false alarms. Deferred, never forgiven — it rides
## along with the next real storm and is only cleared once that tithe is settled.
## Persisted, because forgetting it on reload would make the false alarm free.
var deferred_severity: int = 0
var storms_survived: int = 0
## Diezmos que la guarnicion ha echado. Es lo que engorda la escolta que vuelve
## (GameConfig.get_assessor_escalation): una provincia que paga no les ha
## ensenado nada; una que los echa figura en el libro como una que puede mas.
## Antes la escolta crecia con `storms_survived`, que cuenta tambien los Diezmos
## pagados, y a la septima tormenta llegaba al tope aunque no se hubiera ganado
## ninguna (docs/22-linea-jugable.md).
var tithes_repelled: int = 0
## Only the first storm gets the long fuse and the gentle severity.
var _first: bool = true
## The next Warning cannot turn out to be a false alarm. Set by `summon_now()`
## (a storm called on demand is a storm that comes) and spent on that Warning.
var forced: bool = false
## La tormenta de prueba de la era 1 (StormManager): recorre Aviso, Ceniza y
## Tormenta igual que una de verdad, pero al pasar no bajan los Tasadores: vuelve
## a la calma y se da por terminada (`finished`). Es otro ciclo, no este con una
## bandera puesta a medias: el reloj de verdad no se entera de que paso.
var trial: bool = false
## La de prueba ya paso. Un ciclo terminado no vuelve a moverse.
var finished: bool = false
var _tick_accum: float = 0.0
## The cycle owns its randomness so a test can seed it and get the same run
## twice. Never the global `randf()`: a model that reads global state is not
## pure, and an unreproducible storm cycle cannot be tested at all.
var _rng := RandomNumberGenerator.new()

# ── La Orden de la Regencia (docs/06 §Orden de la Regencia) ──
# Lo que viene en la proxima visita y las formas de pagar menos. Vive aqui porque
# es estado del ciclo (se borra con cada Diezmo, viaja en el guardado `storm`),
# pero no toca el reloj: ni la fase ni la severidad saben que existe.

## Rebajas del proximo Diezmo por fuente ("entrega", "expedicion"...), como
## fraccion (0,15 = un 15 % menos). Se suman entre si con tope
## (`GameConfig.storm_order_discount_max`) y se tiran al saldar cada Diezmo,
## pagado o echado: una rebaja es para la visita que viene, no se acumula.
var tithe_discounts: Dictionary = {}
## El encargo de la Regencia de esta calma: {"res", "amount", "done"}. Vacio
## hasta que StormManager lo sortea (al armarse el reloj y tras cada Diezmo).
var order: Dictionary = {}
## Lo que duro esta calma al empezar, para llenar el barometro. Una falsa alarma
## abre una calma nueva y lo vuelve a poner.
var calm_total: float = 0.0
## Desplazamiento del centro del barometro, sorteado al empezar cada calma. Es lo
## que hace que el margen ("entre 3 y 5 min") no delate el minuto exacto: el
## centro del margen no es el momento de verdad.
var barometer_offset: float = 0.0
## Generador aparte para la Orden y el barometro. Si usaran `_rng`, cada sorteo
## nuevo moveria la secuencia del reloj y una semilla fija dejaria de dar la
## misma tormenta que daba (las pruebas del ciclo cuentan con eso).
var _order_rng := RandomNumberGenerator.new()

# ── Construction ─────────────────────────────────────────────────────

## `rng_seed` below zero means "seed from the system", which is what the game
## does. Tests pass a seed and get the same storm twice.
static func create(rng_seed: int = -1) -> StormCycle:
	var cycle := StormCycle.new()
	cycle.phase = Phase.CALM
	cycle.seconds_left = GameConfig.get_storm_first_interval()
	cycle.severity = clampi(GameConfig.storm_first_severity + GameConfig.get_storm_severity_bonus(),
		1, GameConfig.storm_severity_max)
	cycle.seed_rng(rng_seed)
	cycle._start_calm(cycle.seconds_left)
	return cycle

## La tormenta de prueba: severidad fija, sin falsa alarma (`forced`) y sin
## Diezmo al final. Se arranca con `summon_now()`.
static func create_trial(rng_seed: int = -1) -> StormCycle:
	var cycle := StormCycle.new()
	cycle.phase = Phase.CALM
	cycle.seconds_left = 0.0
	cycle.severity = clampi(GameConfig.storm_trial_severity, 1, GameConfig.storm_severity_max)
	cycle.trial = true
	cycle.seed_rng(rng_seed)
	return cycle

func seed_rng(rng_seed: int) -> void:
	if rng_seed < 0:
		_rng.randomize()
		_order_rng.randomize()
	else:
		_rng.seed = rng_seed
		_order_rng.seed = rng_seed + 1

# ── Queries ──────────────────────────────────────────────────────────

func is_ashfall() -> bool:
	return phase == Phase.ASH

func is_storming() -> bool:
	return phase == Phase.STORM

func is_collecting() -> bool:
	return phase == Phase.TITHE

## True while something is actually falling — the phases that tax the base.
func is_biting() -> bool:
	return phase == Phase.ASH or phase == Phase.STORM

## True once the player can see it coming — warning or worse.
func is_threatening() -> bool:
	return phase in [Phase.WARNING, Phase.ASH, Phase.STORM, Phase.TITHE]

## What the next storm hits with. Deliberately not announced before it lands:
## the player does not get to know whether this is a minor assessment or a full
## audit until it is already overhead.
func effective_severity() -> int:
	return clampi(severity + deferred_severity, 1, GameConfig.storm_severity_max)

## Seconds until the ash starts falling. Dev tooling only — the HUD stopped being
## a countdown, because a number on screen answers the question the Warning is
## supposed to make the player answer.
func seconds_until_ash() -> float:
	match phase:
		Phase.CALM:
			return seconds_left + GameConfig.get_storm_warning()
		Phase.WARNING:
			return seconds_left
		_:
			return 0.0

# ── The clock ────────────────────────────────────────────────────────

## Drives the cycle. The TITHE phase deliberately does not advance: while the
## Assessors are on the board the world holds its breath, and the countdown to
## the next storm only restarts once the fight is settled.
func advance(delta: float) -> Array:
	if phase == Phase.TITHE or finished or delta <= 0.0:
		return []

	var events: Array = []
	seconds_left -= delta

	# The Warning never ticks: it costs nothing, and costing nothing is exactly
	# what makes it worth spending.
	if is_biting():
		_tick_accum += delta
		var interval: float = maxf(0.1, GameConfig.get_storm_tick_interval())
		while _tick_accum >= interval:
			_tick_accum -= interval
			events.append({"e": "storm_tick", "phase": phase, "left": maxf(0.0, seconds_left)})

	if seconds_left > 0.0:
		return events

	match phase:
		Phase.CALM:
			events.append_array(_enter_warning())
		Phase.WARNING:
			events.append_array(_leave_warning())
		Phase.ASH:
			events.append_array(_enter_storm())
		Phase.STORM:
			events.append_array(_enter_tithe())
	return events

## Ash on the horizon. No severity in this event on purpose: knowing the size in
## advance turns the Warning into a calculation instead of a decision.
func _enter_warning() -> Array:
	phase = Phase.WARNING
	seconds_left = GameConfig.get_storm_warning()
	return [
		{"e": "phase", "phase": phase, "left": seconds_left},
		{"e": "incoming", "seconds": seconds_left},
	]

## Calls the storm now: straight into the Warning, whatever the calm had left.
## Only from CALM — a storm already on its way is not summoned twice. Used by
## the Sandbox tools; the rules of the storm itself do not change.
func summon_now() -> Array:
	if phase != Phase.CALM or finished:
		return []
	forced = true
	return _enter_warning()

## The Warning runs out and the sky decides.
func _leave_warning() -> Array:
	if forced:
		forced = false
		return _enter_ash()
	if _rng.randf() < GameConfig.storm_false_alarm_chance:
		return _false_alarm()
	return _enter_ash()

## One in four it was nothing. The player still paid to prepare, and the
## assessment is only postponed: the Regency does not write anything off.
func _false_alarm() -> Array:
	deferred_severity += maxi(0, GameConfig.storm_false_alarm_carry)
	phase = Phase.CALM
	seconds_left = _roll_interval()
	# La Orden sigue en pie (el Diezmo no ha llegado); el barometro empieza de nuevo.
	_start_calm(seconds_left)
	return [
		{"e": "phase", "phase": phase, "left": seconds_left},
		{"e": "false_alarm", "deferred": deferred_severity},
	]

## Dirty air: production halves and morale bleeds, but nothing comes down. Ash
## dirties, it does not demolish — and that keeps this phase as the last window
## in which repairing a roof is still worth the steel.
func _enter_ash() -> Array:
	phase = Phase.ASH
	seconds_left = GameConfig.get_storm_ash_duration()
	_tick_accum = 0.0
	return [
		{"e": "phase", "phase": phase, "left": seconds_left},
		{"e": "ash_started"},
	]

## Severity is announced here and nowhere earlier.
func _enter_storm() -> Array:
	phase = Phase.STORM
	seconds_left = GameConfig.get_storm_duration()
	_tick_accum = 0.0
	return [
		{"e": "phase", "phase": phase, "left": seconds_left},
		{"e": "storm_started", "severity": effective_severity()},
	]

## The ash clears and the Assessors walk in. Ruin first, bill second — always in
## that order, because a province that just lost its roofs does not argue.
func _enter_tithe() -> Array:
	if trial:
		return _end_trial()
	phase = Phase.TITHE
	seconds_left = 0.0
	var hit: int = effective_severity()
	return [
		{"e": "phase", "phase": phase, "left": 0.0},
		{"e": "storm_ended", "severity": hit},
		{"e": "tithe", "severity": hit},
	]

## La de prueba no cobra: escampa, vuelve la calma y no hay siguiente. Nada de
## `storms_survived`: no se ha sobrevivido a nada que la Regencia anote.
func _end_trial() -> Array:
	var hit: int = effective_severity()
	phase = Phase.CALM
	seconds_left = 0.0
	finished = true
	return [
		{"e": "storm_ended", "severity": hit},
		{"e": "phase", "phase": phase, "left": 0.0},
	]

## Called once the collection is settled, whether it was repelled or paid.
## Re-arms the clock for the next one.
func settle_tithe(footprint: int, era: int, repelled: bool = false) -> Array:
	if phase != Phase.TITHE:
		return []
	storms_survived += 1
	if repelled:
		tithes_repelled += 1
	_first = false
	severity = compute_severity(footprint, era)
	# The deferred assessment rode along with this storm; the books are square.
	deferred_severity = 0
	# La Orden era para esta visita: sus rebajas y su encargo se acaban aqui.
	# StormManager sortea la siguiente al publicar la calma.
	tithe_discounts = {}
	order = {}
	phase = Phase.CALM
	seconds_left = _roll_interval()
	_start_calm(seconds_left)
	return [{"e": "phase", "phase": phase, "left": seconds_left}]

## How long the next calm lasts.
func _roll_interval() -> float:
	var low: float = GameConfig.get_storm_interval_min()
	var high: float = maxf(low, GameConfig.get_storm_interval_max())
	return _rng.randf_range(low, high)

# ── Severity ─────────────────────────────────────────────────────────

## How hard the next one hits. Growth is what raises it: the era you reached and
## the number of producing buildings you run. In the fiction that is the whole
## point — smoke is what puts you back in the ledger.
static func compute_severity(footprint: int, era: int) -> int:
	var from_era: int = GameConfig.storm_severity_per_era * maxi(0, era - 1)
	var per: int = maxi(1, GameConfig.storm_buildings_per_severity)
	var from_smoke: int = int(maxi(0, footprint) / per)
	var from_mode: int = GameConfig.get_storm_severity_bonus()
	return clampi(1 + from_era + from_smoke + from_mode, 1, GameConfig.storm_severity_max)

# ── La Orden de la Regencia ──────────────────────────────────────────

## Suma una rebaja al proximo Diezmo. Aditiva: la misma fuente dos veces suma dos
## veces (dos escaramuzas ganadas valen el doble). Devuelve la rebaja total ya
## con su tope. Vale en calma, Aviso, Ceniza o Tormenta; con los Tasadores en la
## puerta la cuenta ya esta hecha y no se apunta nada.
func add_tithe_discount(source: String, pct: float) -> float:
	if pct <= 0.0 or phase == Phase.TITHE or trial or finished:
		return tithe_discount()
	var key: String = source if source != "" else "otra"
	tithe_discounts[key] = float(tithe_discounts.get(key, 0.0)) + pct
	return tithe_discount()

## La rebaja total del proximo Diezmo, entre 0 y el tope.
func tithe_discount() -> float:
	var total := 0.0
	for key in tithe_discounts:
		total += maxf(0.0, float(tithe_discounts[key]))
	return clampf(total, 0.0, clampf(GameConfig.storm_order_discount_max, 0.0, 1.0))

## Lo que ya rebajo una fuente concreta (sin tope), 0 si nada.
func discount_from(source: String) -> float:
	return maxf(0.0, float(tithe_discounts.get(source, 0.0)))

## Una deuda con la rebaja aplicada. Redondea hacia arriba: la Regencia no
## perdona el resto.
func discounted(amount: int) -> int:
	if amount <= 0:
		return 0
	return ceili(float(amount) * (1.0 - tithe_discount()))

## Sortea el encargo de esta calma entre los recursos que se le pasan (los que la
## colonia ya puede hacer: StormManager decide cuales). La cantidad sale de
## `storm_order_delivery_base` y crece con las tormentas pasadas, con tope.
## Devuelve el encargo (vacio si no hay candidatos validos).
func roll_order(candidates: Array) -> Dictionary:
	var valid: Array = []
	for res in candidates:
		if GameConfig.storm_order_delivery_base.has(String(res)):
			valid.append(String(res))
	if valid.is_empty():
		order = {}
		return order
	var res: String = valid[_order_rng.randi_range(0, valid.size() - 1)]
	var growth: float = minf(
		1.0 + GameConfig.storm_order_delivery_growth * float(storms_survived),
		maxf(1.0, GameConfig.storm_order_delivery_growth_max))
	var amount: int = maxi(1, roundi(float(GameConfig.storm_order_delivery_base[res]) * growth))
	order = {"res": res, "amount": amount, "done": false}
	return order

func has_open_order() -> bool:
	return not order.is_empty() and not bool(order.get("done", false))

## Marca el encargo como entregado y apunta su rebaja. El pago lo hace
## StormManager (el modelo no conoce la bolsa). Devuelve false si no habia
## encargo abierto o ya no se puede (Diezmo en curso).
func complete_order() -> bool:
	if not has_open_order() or phase == Phase.TITHE:
		return false
	order["done"] = true
	add_tithe_discount("entrega", GameConfig.storm_order_delivery_pct)
	return true

## El barometro: cuanto se ha llenado la calma y un margen en minutos que
## contiene el momento de verdad sin decirlo. Fuera de la calma, vacio.
##   fill  0..1, cuanto ha pasado de la calma
##   low   minutos, borde bajo del margen (0 = "menos de `high`")
##   high  minutos, borde alto
## El margen es +-`storm_barometer_margin` alrededor de un centro desplazado al
## azar (`barometer_offset`, menor que el margen): el momento real siempre cae
## dentro, nunca se sabe donde. Cuenta hasta el Aviso, que es lo que se ve llegar.
func barometer() -> Dictionary:
	if phase != Phase.CALM or finished:
		return {}
	var total: float = maxf(calm_total, seconds_left)
	var fill: float = 0.0 if total <= 0.0 else clampf(1.0 - seconds_left / total, 0.0, 1.0)
	var margin: float = maxf(1.0, GameConfig.get_storm_barometer_margin())
	var center: float = seconds_left + barometer_offset
	var low: int = maxi(0, int(floor((center - margin) / 60.0)))
	var high: int = maxi(low + 1, int(ceil((center + margin) / 60.0)))
	return {"fill": fill, "low": low, "high": high}

## Empieza una calma: guarda su largo y sortea el desplazamiento del barometro.
func _start_calm(length: float) -> void:
	calm_total = maxf(0.0, length)
	var spread: float = maxf(0.0, GameConfig.get_storm_barometer_margin()) \
		* clampf(GameConfig.storm_barometer_jitter, 0.0, 0.95)
	barometer_offset = _order_rng.randf_range(-spread, spread)

# ── Persistence ──────────────────────────────────────────────────────

## Save format 2. The Phase enum grew ASH in the middle, so a save written before
## that stores different integers for STORM and TITHE and has to be remapped on
## the way in — otherwise an old save would reload mid-storm as mid-ashfall.
const SAVE_VERSION := 2
const LEGACY_PHASES := {0: Phase.CALM, 1: Phase.WARNING, 2: Phase.STORM, 3: Phase.TITHE}

func to_dict() -> Dictionary:
	return {
		"v": SAVE_VERSION,
		"phase": phase,
		"seconds_left": seconds_left,
		"severity": severity,
		"deferred_severity": deferred_severity,
		"storms_survived": storms_survived,
		"tithes_repelled": tithes_repelled,
		"first": _first,
		"forced": forced,
		"trial": trial,
		"finished": finished,
		"tithe_discounts": tithe_discounts.duplicate(),
		"order": order.duplicate(),
		"calm_total": calm_total,
		"barometer_offset": barometer_offset,
	}

static func from_dict(data: Dictionary) -> StormCycle:
	var cycle := StormCycle.new()
	cycle.seed_rng(-1)
	var version: int = int(data.get("v", 1))
	var stored: int = int(data.get("phase", Phase.CALM))
	cycle.phase = stored if version >= SAVE_VERSION else int(LEGACY_PHASES.get(stored, Phase.CALM))
	cycle.seconds_left = float(data.get("seconds_left", GameConfig.get_storm_first_interval()))
	cycle.severity = int(data.get("severity", 1))
	cycle.deferred_severity = maxi(0, int(data.get("deferred_severity", 0)))
	cycle.storms_survived = int(data.get("storms_survived", 0))
	# Un guardado de antes de este contador no sabe cuantos se echaron: cero, que
	# es lo prudente (la escolta vuelve a su tamano base, no al del tope).
	cycle.tithes_repelled = maxi(0, int(data.get("tithes_repelled", 0)))
	cycle._first = bool(data.get("first", true))
	cycle.forced = bool(data.get("forced", false))
	cycle.trial = bool(data.get("trial", false))
	cycle.finished = bool(data.get("finished", false))
	# La Orden (2026-10-14). Un guardado de antes no la trae: sin rebajas, sin
	# encargo (StormManager sortea uno al cargar) y el barometro con la calma que
	# queda como largo. Se asigna, nunca se suma: cargar dos veces da lo mismo.
	cycle.tithe_discounts = {}
	var saved_discounts: Variant = data.get("tithe_discounts", {})
	if saved_discounts is Dictionary:
		for key in saved_discounts:
			var pct: float = float(saved_discounts[key])
			if pct > 0.0:
				cycle.tithe_discounts[String(key)] = pct
	cycle.order = {}
	var saved_order: Variant = data.get("order", {})
	if saved_order is Dictionary and (saved_order as Dictionary).has("res"):
		cycle.order = {
			"res": String(saved_order["res"]),
			"amount": maxi(1, int(saved_order.get("amount", 1))),
			"done": bool(saved_order.get("done", false)),
		}
	cycle.calm_total = maxf(cycle.seconds_left, float(data.get("calm_total", cycle.seconds_left)))
	cycle.barometer_offset = float(data.get("barometer_offset", 0.0))
	# Un save hecho con los Tasadores en la puerta vuelve con los Tasadores en la
	# puerta. Antes se perdonaba y el reloj volvia a la calma: salir del juego
	# durante el Diezmo era la forma de no pagarlo. El tablero no se guarda, asi
	# que quien reanuda el cobro es StormManager, al terminar la carga.
	if cycle.phase == Phase.TITHE:
		cycle.seconds_left = 0.0
	return cycle
