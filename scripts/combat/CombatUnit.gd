extends RefCounted
class_name CombatUnit
## One unit inside an expedition. Survives between encounters carrying its damage
## (attrition); dying removes it permanently.
##
## Base stats come from GameConfig.combat_unit_stats. Draft bonuses and the base's
## morale modify the derived getters, never the stored stats.

var uid: int = 0
var unit_id: String = ""
var side: int = 0            ## 0 = player, 1 = enemy
var hp: int = 0
var max_hp: int = 0
var position: Vector2i = Vector2i(-1, -1)
var has_acted: bool = false
var moved_this_turn: bool = false
var defending: bool = false
var draft_bonuses: Dictionary = {}   ## stat name -> int delta (player only)
## Enemy-only difficulty multiplier applied to hp/atk when the roster is generated.
var scale: float = 1.0
## Morale multiplier captured when the expedition launched (player only).
var morale_attack_mod: float = 1.0
var morale_initiative_bonus: int = 0

static func create(p_uid: int, p_unit_id: String, p_side: int, p_scale: float = 1.0) -> CombatUnit:
	var unit := CombatUnit.new()
	unit.uid = p_uid
	unit.unit_id = p_unit_id
	unit.side = p_side
	unit.scale = p_scale
	var stats: Dictionary = GameConfig.get_combat_stats(p_unit_id)
	unit.max_hp = maxi(1, roundi(float(stats.get("hp", 10)) * p_scale))
	unit.hp = unit.max_hp
	return unit

func _base(stat: String, fallback: int) -> int:
	var stats: Dictionary = GameConfig.get_combat_stats(unit_id)
	return int(stats.get(stat, fallback))

func is_alive() -> bool:
	return hp > 0

func attack_power() -> int:
	var value := float(_base("atk", 1) + int(draft_bonuses.get("atk", 0))) * scale
	return maxi(1, roundi(value * morale_attack_mod))

func defense() -> int:
	var value := _base("def", 0) + int(draft_bonuses.get("def", 0))
	return value * 2 if defending else value

func move_range() -> int:
	return maxi(0, _base("move", 1) + int(draft_bonuses.get("move", 0)))

func attack_range() -> int:
	return maxi(1, _base("range", 1))

func min_range() -> int:
	return maxi(1, _base("min_range", 1))

func initiative() -> int:
	return _base("initiative", 1) + int(draft_bonuses.get("initiative", 0)) + morale_initiative_bonus

## Power contribution, reused for AI target priority.
func power() -> int:
	var def: Dictionary = GameConfig.get_unit_def(unit_id)
	return int(def.get("power", 1))

func take_damage(amount: int) -> void:
	hp = maxi(0, hp - amount)

func heal_percent(pct: float) -> void:
	hp = mini(max_hp, hp + maxi(1, roundi(float(max_hp) * pct)))

func begin_turn() -> void:
	has_acted = false
	moved_this_turn = false
	defending = false

## Between encounters: leave the board but keep the damage (FR-011).
func leave_board() -> void:
	position = Vector2i(-1, -1)
	has_acted = false
	moved_this_turn = false
	defending = false

func restore_full_health() -> void:
	hp = max_hp

func to_dict() -> Dictionary:
	return {
		"uid": uid,
		"unit_id": unit_id,
		"side": side,
		"hp": hp,
		"max_hp": max_hp,
		"draft_bonuses": draft_bonuses.duplicate(),
		"scale": scale,
	}

static func from_dict(data: Dictionary) -> CombatUnit:
	var unit := CombatUnit.new()
	unit.uid = int(data.get("uid", 0))
	unit.unit_id = String(data.get("unit_id", ""))
	unit.side = int(data.get("side", 0))
	unit.max_hp = int(data.get("max_hp", 1))
	unit.hp = int(data.get("hp", unit.max_hp))
	unit.draft_bonuses = data.get("draft_bonuses", {}).duplicate()
	unit.scale = float(data.get("scale", 1.0))
	return unit
