extends GdUnitTestSuite
## Las vistas previas del tablero (docs/15 §3 "Ensenar el combate"): funciones
## puras de CombatRules. Que digan lo mismo que el golpe de verdad, que no toquen
## nada y que el alcance enemigo y la ✕ de la artilleria salgan bien en el borde.

const Rules := preload("res://scripts/combat/CombatRules.gd")
const CombatUnitScript := preload("res://scripts/combat/CombatUnit.gd")
const EncounterScript := preload("res://scripts/combat/Encounter.gd")

const PLAYER := 0
const ENEMY := 1
const BOARD := Vector2i(8, 8)

var _uid := 0

func before_test() -> void:
	_uid = 0

func _unit(unit_id: String, side: int, pos: Vector2i) -> CombatUnit:
	_uid += 1
	var u := CombatUnitScript.create(_uid, unit_id, side, 1.0)
	u.position = pos
	return u

# ── preview_damage ───────────────────────────────────────────────────

func test_preview_matches_the_real_hit() -> void:
	for a in ["infantry", "artillery", "vehicle"]:
		for b in ["infantry", "artillery", "vehicle"]:
			var att := _unit(a, PLAYER, Vector2i(0, 0))
			var tgt := _unit(b, ENEMY, Vector2i(0, 2))
			var p: Dictionary = Rules.preview_damage(att, tgt)
			assert_int(int(p["damage"])).is_equal(Rules.damage(att, tgt))
			assert_int(int(p["matchup"])).is_equal(Rules.type_matchup(a, b))

func test_preview_does_not_touch_the_target() -> void:
	var att := _unit("artillery", PLAYER, Vector2i(0, 0))
	var tgt := _unit("vehicle", ENEMY, Vector2i(0, 2))
	var before := tgt.hp
	var p: Dictionary = Rules.preview_damage(att, tgt)
	assert_int(tgt.hp).is_equal(before)
	assert_int(int(p["hp"])).is_equal(before)
	assert_int(int(p["hp_after"])).is_equal(before - int(p["damage"]))
	assert_bool(bool(p["kills"])).is_false()

func test_preview_says_when_it_kills() -> void:
	var att := _unit("vehicle", PLAYER, Vector2i(0, 0))
	var tgt := _unit("infantry", ENEMY, Vector2i(0, 1))
	tgt.hp = 1
	var p: Dictionary = Rules.preview_damage(att, tgt)
	assert_bool(bool(p["kills"])).is_true()
	assert_int(int(p["hp_after"])).is_equal(0)

func test_preview_counts_a_defending_target() -> void:
	var att := _unit("infantry", PLAYER, Vector2i(0, 0))
	var tgt := _unit("vehicle", ENEMY, Vector2i(0, 1))
	var open_hit: int = int(Rules.preview_damage(att, tgt)["damage"])
	tgt.defending = true
	assert_int(int(Rules.preview_damage(att, tgt)["damage"])).is_less_equal(open_hit)

# ── min_range_cells / fire_cells_from ────────────────────────────────

func test_artillery_cannot_fire_at_its_neighbours() -> void:
	var art := _unit("artillery", PLAYER, Vector2i(3, 3))
	var cells: Array = Rules.min_range_cells(art, BOARD)
	assert_array(cells).contains_exactly_in_any_order([Vector2i(2, 3), Vector2i(4, 3), Vector2i(3, 2), Vector2i(3, 4)])

func test_min_range_cells_stay_on_the_board() -> void:
	var art := _unit("artillery", PLAYER, Vector2i(0, 0))
	assert_array(Rules.min_range_cells(art, BOARD)).contains_exactly_in_any_order([Vector2i(1, 0), Vector2i(0, 1)])

func test_melee_units_have_no_cross() -> void:
	assert_array(Rules.min_range_cells(_unit("infantry", PLAYER, Vector2i(3, 3)), BOARD)).is_empty()
	assert_array(Rules.min_range_cells(_unit("vehicle", PLAYER, Vector2i(3, 3)), BOARD)).is_empty()

func test_fire_cells_are_between_min_and_max_range() -> void:
	var art := _unit("artillery", PLAYER, Vector2i(4, 4))
	var cells: Array = Rules.fire_cells_from(art, art.position, BOARD)
	assert_bool(cells.is_empty()).is_false()
	for c in cells:
		var d := Rules.manhattan(art.position, c)
		assert_int(d).is_between(art.min_range(), art.attack_range())
	assert_bool(cells.has(Vector2i(4, 5))).is_false()
	assert_bool(cells.has(Vector2i(4, 6))).is_true()

# ── threat_cells ─────────────────────────────────────────────────────

func test_threat_covers_move_plus_reach() -> void:
	var enemy := _unit("infantry", ENEMY, Vector2i(4, 0))
	var mine := _unit("infantry", PLAYER, Vector2i(4, 7))
	var threat: Array = Rules.threat_cells([enemy, mine], ENEMY, BOARD)
	# Mueve 3 y pega a 1: hasta la fila 4 en su columna, no la 5.
	assert_bool(threat.has(Vector2i(4, 4))).is_true()
	assert_bool(threat.has(Vector2i(4, 5))).is_false()
	for c in threat:
		assert_bool(Rules.in_board(c, BOARD)).is_true()

func test_threat_ignores_the_other_side_and_the_dead() -> void:
	var enemy := _unit("infantry", ENEMY, Vector2i(0, 0))
	enemy.hp = 0
	var mine := _unit("vehicle", PLAYER, Vector2i(7, 7))
	assert_array(Rules.threat_cells([enemy, mine], ENEMY, BOARD)).is_empty()

func test_threat_does_not_move_anyone() -> void:
	var enemy := _unit("vehicle", ENEMY, Vector2i(2, 1))
	var mine := _unit("artillery", PLAYER, Vector2i(5, 6))
	Rules.threat_cells([enemy, mine], ENEMY, BOARD)
	assert_that(enemy.position).is_equal(Vector2i(2, 1))
	assert_that(mine.position).is_equal(Vector2i(5, 6))
