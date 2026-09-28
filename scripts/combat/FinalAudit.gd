extends RefCounted
class_name FinalAudit
## The siege that replaces winning. A headquarters at level 3 no longer ends the
## game: it summons the Regency's last audit, and the audit has to be survived.
## Pure state — no nodes, no signals, no timers — so a whole siege can be fought
## out headless in a test.
##
## Like Expedition and Encounter, every mutating method returns an Array of event
## dictionaries instead of emitting anything. ProgressionManager drains that list
## and republishes it on the EventBus (constitution, principles I and IV).
##
## Three rules hold this together, and none of them is negotiable:
##   * **Attrition across waves.** The garrison carries its damage from one wave
##     into the next. Nothing heals and nobody is retrained in between — this is
##     the actual difficulty curve, not the scaling below.
##   * **Permadeath.** A unit that falls stays in `garrison` as a casualty and
##     never stands again in this siege.
##   * **No game over.** Losing costs the maximum Tithe and leaves the town in
##     ruins, but the siege can be summoned again once the army is rebuilt. The
##     victory is earned; it is never raffled.
##
## The waves themselves are never saved: they are rebuilt from `seed_value` and
## the era, exactly the way Expedition rebuilds its map, so a save can never
## drift out of sync with the siege it describes.

const CombatUnitScript := preload("res://scripts/combat/CombatUnit.gd")
const Rules := preload("res://scripts/combat/CombatRules.gd")

enum State { PENDING, ACTIVE, WON, LOST }

const PLAYER := 0
const ENEMY := 1

var seed_value: int = 0
var era: int = 1
var state: int = State.PENDING
## Array[Dictionary]: index, roster (unit_id -> count), scale.
var waves: Array = []
## The wave being fought. Equal to waves.size() once the last one is broken.
var current_wave: int = 0
## CombatUnit, the living and the fallen. Nobody joins after the first wave.
var garrison: Array = []
var morale_snapshot: float = 50.0
## How many times the Regency has come down. Losing does not end the game, so
## this is the only record that it ever happened.
var summons: int = 1

## uid counter, unique inside this siege and shared with the waves it fields, so
## no two units on a board can ever collide (data-model, CombatUnit.uid).
var _next_uid: int = 1

# ── Construction ─────────────────────────────────────────────────────

## Calls the audit down. `garrison_counts` is `unit_id -> count` as it stands at
## home: whatever is there is what fights every wave. `p_morale` freezes the
## town's spirit for the whole siege, the way an expedition freezes it at launch.
##
## The siege opens PENDING, not ACTIVE: being summoned and being under attack are
## two different things, and the player is owed the moment in between.
static func create(p_seed: int, garrison_counts: Dictionary, p_era: int = 1, p_morale: float = 50.0) -> FinalAudit:
	var audit := FinalAudit.new()
	audit.seed_value = p_seed
	audit.era = maxi(1, p_era)
	audit.morale_snapshot = p_morale
	audit.state = State.PENDING
	audit.current_wave = 0
	audit.summons = 1
	audit._build_waves()
	audit._muster(garrison_counts)
	return audit

## The one place a RandomNumberGenerator is born in this file. `randf()` on the
## global generator is banned here on purpose: the save only stores the seed, so
## the same seed has to rebuild the same siege, wave for wave, every time.
static func make_rng(p_seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	return rng

func next_uid() -> int:
	var uid: int = _next_uid
	_next_uid += 1
	return uid

## Rolls the whole siege at once, in wave order, so the stream stays stable no
## matter how the composition below evolves.
func _build_waves() -> void:
	var rng := make_rng(seed_value)
	var cfg: Vector2i = GameConfig.final_audit_waves
	var low: int = maxi(1, mini(cfg.x, cfg.y))
	var high: int = maxi(low, maxi(cfg.x, cfg.y))
	var total: int = rng.randi_range(low, high)
	waves = []
	for i in range(total):
		waves.append({
			"index": i,
			"scale": wave_scale(i, total),
			"roster": _compose(rng, i, total),
		})

## Turns whatever is at home into the garrison, stamping each unit with the
## spirit the town had when the Regency was summoned. Returns what it built.
func _muster(garrison_counts: Dictionary) -> Array:
	var attack_mod: float = Rules.morale_attack_mod(morale_snapshot)
	var initiative_bonus: int = Rules.morale_initiative_bonus(morale_snapshot)
	for unit_id in garrison_counts.keys():
		for i in range(int(garrison_counts[unit_id])):
			var unit: CombatUnit = CombatUnitScript.create(next_uid(), String(unit_id), PLAYER, 1.0)
			unit.morale_attack_mod = attack_mod
			unit.morale_initiative_bonus = initiative_bonus
			garrison.append(unit)
	return garrison

# ── Wave shape ───────────────────────────────────────────────────────

## How much heavier than the opening wave this one is. The wave number and the
## era push in the same direction; the closing wave multiplies whatever came out.
##
## This is what keeps the siege climbing after the board is full: the cap on
## bodies is `combat_deploy_cap`, but there is no cap on what a body hits for.
func wave_scale(index: int, total: int) -> float:
	var scale: float = 1.0 \
		+ GameConfig.final_audit_scale_per_wave * float(maxi(0, index)) \
		+ GameConfig.final_audit_scale_per_era * float(maxi(0, era - 1))
	if index >= total - 1:
		scale *= GameConfig.final_audit_last_wave_multiplier
	return scale

## Bodies in this wave, never more than the board holds.
func wave_slots(index: int) -> int:
	return clampi(
		GameConfig.final_audit_base_slots + GameConfig.final_audit_slots_per_wave * maxi(0, index),
		1,
		maxi(1, GameConfig.combat_deploy_cap)
	)

## Composition, not just a headcount: the first wave is a plain line, the guns
## come with the second, and the armour only rolls in once the wave number and
## the era both allow it. A wave has to look different before it looks bigger, or
## the siege is one fight repeated five times.
##
## Only the counts come from here; the stat multiplier is wave_scale().
func _compose(rng: RandomNumberGenerator, index: int, total: int) -> Dictionary:
	var slots: int = wave_slots(index)

	var guns: int = 0
	if index > 0 and _is_available("artillery"):
		guns = maxi(1, slots / maxi(1, GameConfig.final_audit_artillery_share))
		# The one coin flip of the whole siege. Without it the same era would
		# always field the same squads and the seed would decide nothing.
		if rng.randf() < GameConfig.final_audit_extra_gun_chance:
			guns += 1

	var armour: int = 0
	if index >= GameConfig.final_audit_armour_wave and _is_available("vehicle"):
		armour = 1
		if index >= total - 1:
			armour += 1

	# The board is the same 8x8 it always was. When the heavy pieces do not fit,
	# the line is what gives way — the Regency does not send fewer tanks.
	armour = mini(armour, maxi(0, slots - 1))
	guns = mini(guns, maxi(0, slots - armour - 1))
	var line: int = maxi(1, slots - guns - armour)

	var roster: Dictionary = {"infantry": line}
	if guns > 0:
		roster["artillery"] = guns
	if armour > 0:
		roster["vehicle"] = armour
	return roster

func _is_available(unit_id: String) -> bool:
	return era >= int(GameConfig.get_unit_def(unit_id).get("era", 1))

# ── Queries ──────────────────────────────────────────────────────────

func is_pending() -> bool:
	return state == State.PENDING

func is_active() -> bool:
	return state == State.ACTIVE

func is_resolved() -> bool:
	return state == State.WON or state == State.LOST

func is_won() -> bool:
	return state == State.WON

func is_lost() -> bool:
	return state == State.LOST

func wave_count() -> int:
	return waves.size()

func waves_cleared() -> int:
	return clampi(current_wave, 0, wave_count())

func waves_remaining() -> int:
	return maxi(0, wave_count() - current_wave)

func at_last_wave() -> bool:
	return current_wave >= wave_count() - 1

func wave_at(index: int) -> Dictionary:
	if index < 0 or index >= waves.size():
		return {}
	return waves[index]

func current_wave_data() -> Dictionary:
	return wave_at(current_wave)

## A single comparable number for "how heavy is this wave", used by the UI and by
## the tests that check the siege actually climbs.
func wave_power(index: int) -> float:
	var wave: Dictionary = wave_at(index)
	if wave.is_empty():
		return 0.0
	var total: float = 0.0
	var roster: Dictionary = wave["roster"]
	for unit_id in roster:
		var power: int = int(GameConfig.get_unit_def(unit_id).get("power", 1))
		total += float(power) * float(roster[unit_id])
	return total * float(wave["scale"])

func living_garrison() -> Array:
	return Rules.living_units(garrison, PLAYER)

func casualties() -> Array:
	var fallen: Array = []
	for unit in garrison:
		if not unit.is_alive():
			fallen.append(unit)
	return fallen

func is_garrison_wiped() -> bool:
	return living_garrison().is_empty()

# ── The board of the current wave ────────────────────────────────────

## Fields the wave that is coming down. Fresh CombatUnits every time, so a wave
## retried after a reload never inherits damage the player already dealt — but
## their uids come from the siege counter and can never clash with the garrison.
func build_enemy_units() -> Array:
	var wave: Dictionary = current_wave_data()
	if wave.is_empty():
		return []
	var scale: float = float(wave["scale"])
	var units: Array = []
	var roster: Dictionary = wave["roster"]
	for unit_id in roster.keys():
		for i in range(int(roster[unit_id])):
			units.append(CombatUnitScript.create(next_uid(), String(unit_id), ENEMY, scale))
	return units

## Everyone who stands on the next board: the survivors exactly as they are,
## wounds included, plus whatever the Regency sent this time. This is where the
## attrition actually happens — the same CombatUnit objects, wave after wave.
func build_encounter_units() -> Array:
	var units: Array = living_garrison()
	units.append_array(build_enemy_units())
	return units

## Between waves the survivors step off the board but keep their damage. Same
## contract as Encounter.release_survivors(), for the same reason.
func release_survivors() -> void:
	for unit in garrison:
		if unit.is_alive():
			unit.leave_board()

# ── Transitions ──────────────────────────────────────────────────────

## Opens the siege. Call once, after the Regency has been summoned.
func begin() -> Array:
	if not is_pending():
		return []
	state = State.ACTIVE
	return [{"e": "final_audit_started", "waves": wave_count(), "summons": summons}]

## The wave is broken. The survivors step off keeping every wound, the count
## moves on, and breaking the last one is the whole game.
func clear_wave() -> Array:
	if not is_active() or waves.is_empty():
		return []
	release_survivors()
	var cleared: int = current_wave
	current_wave += 1
	var events: Array = [{
		"e": "final_audit_wave_cleared",
		"wave": cleared,
		"remaining": waves_remaining(),
	}]
	# A wave can be broken by the last unit standing falling with it. There is
	# then nobody left for the next one and the Regency walks in over the bodies.
	if current_wave < wave_count() and is_garrison_wiped():
		state = State.LOST
		events.append({"e": "final_audit_lost", "wave": cleared})
		return events
	if current_wave >= wave_count():
		state = State.WON
		events.append({"e": "final_audit_won", "waves": wave_count(), "summons": summons})
	return events

## The garrison is gone. There is no game over: the Regency collects the maximum
## Tithe and leaves the town in ruins, and the siege waits to be summoned again.
func lose() -> Array:
	if not is_active():
		return []
	state = State.LOST
	return [{"e": "final_audit_lost", "wave": current_wave}]

## What it takes to call the Regency back down: a siege that was lost and an army
## rebuilt to at least the floor in GameConfig. Losing costs; it does not close
## the door, and it does not leave the door open either.
func can_resummon(garrison_counts: Dictionary) -> bool:
	return is_lost() and _roster_size(garrison_counts) >= GameConfig.final_audit_resummon_min_units

## Summons the audit again on a fresh army and a fresh seed. Nothing survives the
## old siege — the dead least of all — except the count of how many times the
## Regency has already been here.
func resummon(p_seed: int, garrison_counts: Dictionary, p_era: int = -1, p_morale: float = -1.0) -> Array:
	if not can_resummon(garrison_counts):
		return []
	seed_value = p_seed
	if p_era > 0:
		era = maxi(1, p_era)
	if p_morale >= 0.0:
		morale_snapshot = p_morale
	state = State.PENDING
	current_wave = 0
	garrison = []
	summons += 1
	_build_waves()
	_muster(garrison_counts)
	return [{"e": "final_audit_summoned", "waves": wave_count(), "summons": summons}]

# ── Result ───────────────────────────────────────────────────────────

## What ProgressionManager hands to the victory screen, or to the Tithe.
func result_summary() -> Dictionary:
	return {
		"won": is_won(),
		"waves": wave_count(),
		"waves_cleared": waves_cleared(),
		"summons": summons,
		"survivors": _tally(living_garrison()),
		"casualties": _tally(casualties()),
	}

func _tally(units: Array) -> Dictionary:
	var counts: Dictionary = {}
	for unit in units:
		counts[unit.unit_id] = int(counts.get(unit.unit_id, 0)) + 1
	return counts

static func _roster_size(roster: Dictionary) -> int:
	var total: int = 0
	for count in roster.values():
		total += int(count)
	return total

# ── Persistence ──────────────────────────────────────────────────────

## The waves are deliberately absent: they are rebuilt from the seed and the era,
## which keeps the save small and makes it impossible for a stale wave list to
## drift away from the seed that produced it (same call Expedition makes for its
## map). `current_wave` is all the progress there is to write down.
func to_dict() -> Dictionary:
	var units: Array = []
	for unit in garrison:
		units.append(unit.to_dict())
	return {
		"seed": seed_value,
		"era": era,
		"state": state,
		"current_wave": current_wave,
		"summons": summons,
		"morale_snapshot": morale_snapshot,
		"garrison": units,
	}

## Rebuilds a siege from a save. A save written before the audit existed has no
## key at all, which simply means "no siege" and is never an error (constitution,
## principle V). Returns null for anything that is not one, so the caller can
## treat "no key", "empty dict" and "never summoned" the same way.
static func from_dict(data: Dictionary, default_era: int = 1) -> FinalAudit:
	if data.is_empty() or not data.has("seed"):
		return null
	var audit := FinalAudit.new()
	audit.seed_value = int(data.get("seed", 0))
	audit.era = maxi(1, int(data.get("era", default_era)))
	audit.state = int(data.get("state", State.PENDING))
	audit.summons = maxi(1, int(data.get("summons", 1)))
	audit.morale_snapshot = float(data.get("morale_snapshot", 50.0))
	# The era has to be in place before the waves are rolled: it is half of what
	# decides their shape.
	audit._build_waves()
	audit.current_wave = clampi(int(data.get("current_wave", 0)), 0, audit.wave_count())

	# The morale modifiers are recomputed rather than stored: they are a pure
	# function of the snapshot, and one less field is one less thing to drift.
	var attack_mod: float = Rules.morale_attack_mod(audit.morale_snapshot)
	var initiative_bonus: int = Rules.morale_initiative_bonus(audit.morale_snapshot)
	var highest_uid: int = 0
	for unit_data in data.get("garrison", []):
		var unit: CombatUnit = CombatUnitScript.from_dict(unit_data)
		unit.side = PLAYER
		unit.morale_attack_mod = attack_mod
		unit.morale_initiative_bonus = initiative_bonus
		highest_uid = maxi(highest_uid, unit.uid)
		audit.garrison.append(unit)
	audit._next_uid = highest_uid + 1
	return audit
