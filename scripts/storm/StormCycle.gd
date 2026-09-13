extends RefCounted
class_name StormCycle
## The clock the whole game is measured against: calm, warning, storm, tithe.
##
## Pure state — no nodes, no EventBus, no timers. `advance(delta)` returns an Array
## of event dictionaries and StormManager republishes them (same contract as
## Encounter). That is what lets a hundred storm cycles run headless in a test.
##
## The storm is **dispatched, not rolled**. It arrives on a schedule the player can
## read, because a disaster you cannot prepare for is noise, not pressure.

enum Phase {
	CALM,      ## Counting down. Nothing on the horizon yet.
	WARNING,   ## Announced. The player can still act on it.
	STORM,     ## Overhead. Production crawls, morale bleeds, roofs go.
	TITHE,     ## The Assessors are on the board. The clock is held.
}

var phase: int = Phase.CALM
var seconds_left: float = 0.0
var severity: int = 1
var storms_survived: int = 0
## Only the first storm gets the long fuse and the gentle severity.
var _first: bool = true
var _tick_accum: float = 0.0

# ── Construction ─────────────────────────────────────────────────────

static func create() -> StormCycle:
	var cycle := StormCycle.new()
	cycle.phase = Phase.CALM
	cycle.seconds_left = GameConfig.get_storm_interval(true)
	cycle.severity = GameConfig.storm_first_severity
	return cycle

# ── Queries ──────────────────────────────────────────────────────────

func is_storming() -> bool:
	return phase == Phase.STORM

func is_collecting() -> bool:
	return phase == Phase.TITHE

## True once the player can see it coming — warning or worse.
func is_threatening() -> bool:
	return phase in [Phase.WARNING, Phase.STORM, Phase.TITHE]

## Seconds until the ash actually lands, for the countdown in the HUD.
func seconds_until_impact() -> float:
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

	if phase == Phase.STORM:
		_tick_accum += delta
		var interval: float = maxf(0.1, GameConfig.get_storm_tick_interval())
		while _tick_accum >= interval:
			_tick_accum -= interval
			events.append({"e": "storm_tick", "left": maxf(0.0, seconds_left)})

	if seconds_left > 0.0:
		return events

	match phase:
		Phase.CALM:
			events.append_array(_enter_warning())
		Phase.WARNING:
			events.append_array(_enter_storm())
		Phase.STORM:
			events.append_array(_enter_tithe())
	return events

func _enter_warning() -> Array:
	phase = Phase.WARNING
	seconds_left = GameConfig.get_storm_warning()
	return [
		{"e": "phase", "phase": phase, "left": seconds_left},
		{"e": "incoming", "seconds": seconds_left, "severity": severity},
	]

func _enter_storm() -> Array:
	phase = Phase.STORM
	seconds_left = GameConfig.get_storm_duration()
	_tick_accum = 0.0
	return [
		{"e": "phase", "phase": phase, "left": seconds_left},
		{"e": "storm_started", "severity": severity},
	]

## The ash clears and the Assessors walk in. Ruin first, bill second — always in
## that order, because a province that just lost its roofs does not argue.
func _enter_tithe() -> Array:
	phase = Phase.TITHE
	seconds_left = 0.0
	return [
		{"e": "phase", "phase": phase, "left": 0.0},
		{"e": "storm_ended", "severity": severity},
		{"e": "tithe", "severity": severity},
	]

## Called once the collection is settled, whether it was repelled or paid.
## Re-arms the clock for the next one.
func settle_tithe(footprint: int, era: int) -> Array:
	if phase != Phase.TITHE:
		return []
	storms_survived += 1
	_first = false
	severity = compute_severity(footprint, era)
	phase = Phase.CALM
	seconds_left = GameConfig.get_storm_interval(false)
	return [{"e": "phase", "phase": phase, "left": seconds_left}]

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

func to_dict() -> Dictionary:
	return {
		"phase": phase,
		"seconds_left": seconds_left,
		"severity": severity,
		"storms_survived": storms_survived,
		"first": _first,
	}

static func from_dict(data: Dictionary) -> StormCycle:
	var cycle := StormCycle.new()
	cycle.phase = int(data.get("phase", Phase.CALM))
	cycle.seconds_left = float(data.get("seconds_left", GameConfig.get_storm_interval(true)))
	cycle.severity = int(data.get("severity", 1))
	cycle.storms_survived = int(data.get("storms_survived", 0))
	cycle._first = bool(data.get("first", true))
	# A save made mid-collection would restore a board that no longer exists, so
	# the fight is forgiven and the clock restarts calm.
	if cycle.phase == Phase.TITHE:
		cycle.phase = Phase.CALM
		cycle.seconds_left = GameConfig.get_storm_interval(false)
	return cycle
