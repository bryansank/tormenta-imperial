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
## Only the first storm gets the long fuse and the gentle severity.
var _first: bool = true
var _tick_accum: float = 0.0
## The cycle owns its randomness so a test can seed it and get the same run
## twice. Never the global `randf()`: a model that reads global state is not
## pure, and an unreproducible storm cycle cannot be tested at all.
var _rng := RandomNumberGenerator.new()

# ── Construction ─────────────────────────────────────────────────────

## `rng_seed` below zero means "seed from the system", which is what the game
## does. Tests pass a seed and get the same storm twice.
static func create(rng_seed: int = -1) -> StormCycle:
	var cycle := StormCycle.new()
	cycle.phase = Phase.CALM
	cycle.seconds_left = GameConfig.get_storm_first_interval()
	cycle.severity = GameConfig.storm_first_severity
	cycle.seed_rng(rng_seed)
	return cycle

func seed_rng(rng_seed: int) -> void:
	if rng_seed < 0:
		_rng.randomize()
	else:
		_rng.seed = rng_seed

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
	if phase == Phase.TITHE or delta <= 0.0:
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

## The Warning runs out and the sky decides.
func _leave_warning() -> Array:
	if _rng.randf() < GameConfig.storm_false_alarm_chance:
		return _false_alarm()
	return _enter_ash()

## One in four it was nothing. The player still paid to prepare, and the
## assessment is only postponed: the Regency does not write anything off.
func _false_alarm() -> Array:
	deferred_severity += maxi(0, GameConfig.storm_false_alarm_carry)
	phase = Phase.CALM
	seconds_left = _roll_interval()
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
	phase = Phase.TITHE
	seconds_left = 0.0
	var hit: int = effective_severity()
	return [
		{"e": "phase", "phase": phase, "left": 0.0},
		{"e": "storm_ended", "severity": hit},
		{"e": "tithe", "severity": hit},
	]

## Called once the collection is settled, whether it was repelled or paid.
## Re-arms the clock for the next one.
func settle_tithe(footprint: int, era: int) -> Array:
	if phase != Phase.TITHE:
		return []
	storms_survived += 1
	_first = false
	severity = compute_severity(footprint, era)
	# The deferred assessment rode along with this storm; the books are square.
	deferred_severity = 0
	phase = Phase.CALM
	seconds_left = _roll_interval()
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
	return clampi(1 + from_era + from_smoke, 1, GameConfig.storm_severity_max)

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
		"first": _first,
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
	cycle._first = bool(data.get("first", true))
	# A save made mid-collection would restore a board that no longer exists, so
	# the fight is forgiven and the clock restarts calm.
	if cycle.phase == Phase.TITHE:
		cycle.phase = Phase.CALM
		cycle.seconds_left = cycle._roll_interval()
	return cycle
