extends GdUnitTestSuite
## El aspecto de un edificio en el mapa (docs/03, "Aspecto en el mapa"): la
## regla pura que comparten las dos vistas. Obra por fases segun el progreso,
## mejora, ruina, trabajando y quieto, con su orden de prioridad.

const LookRule := preload("res://scripts/buildings/BuildingLook.gd")

func _facts(overrides: Dictionary = {}) -> Dictionary:
	var f := {
		"under_construction": false, "upgrade": false, "progress": 1.0,
		"ruined": false, "working": false, "fx": "smoke",
	}
	f.merge(overrides, true)
	return f

# ── Fases ────────────────────────────────────────────────────────────

func test_three_phases_follow_progress() -> void:
	var t := [0.34, 0.67]
	assert_int(LookRule.phase_for(0.0, t)).is_equal(LookRule.PHASE_FENCE)
	assert_int(LookRule.phase_for(0.33, t)).is_equal(LookRule.PHASE_FENCE)
	assert_int(LookRule.phase_for(0.34, t)).is_equal(LookRule.PHASE_FOUNDATION)
	assert_int(LookRule.phase_for(0.66, t)).is_equal(LookRule.PHASE_FOUNDATION)
	assert_int(LookRule.phase_for(0.67, t)).is_equal(LookRule.PHASE_FRAME)
	assert_int(LookRule.phase_for(1.0, t)).is_equal(LookRule.PHASE_FRAME)

func test_phase_never_leaves_the_three() -> void:
	assert_int(LookRule.phase_for(5.0, [0.1, 0.2, 0.3, 0.4])).is_equal(LookRule.PHASE_COUNT - 1)
	assert_int(LookRule.phase_for(-1.0)).is_equal(0)

func test_default_thresholds_come_from_gameconfig() -> void:
	assert_array(GameConfig.construction_phase_thresholds).has_size(LookRule.PHASE_COUNT - 1)
	assert_int(LookRule.phase_for(0.5)).is_equal(LookRule.phase_for(0.5, GameConfig.construction_phase_thresholds))

func test_footprint_class_is_the_long_side_clamped() -> void:
	assert_int(LookRule.footprint_class(Vector2i(1, 1))).is_equal(1)
	assert_int(LookRule.footprint_class(Vector2i(2, 1))).is_equal(2)
	assert_int(LookRule.footprint_class(Vector2i(2, 2))).is_equal(2)
	assert_int(LookRule.footprint_class(Vector2i(3, 3))).is_equal(3)
	assert_int(LookRule.footprint_class(Vector2i(5, 4))).is_equal(3)

# ── La regla ─────────────────────────────────────────────────────────

func test_construction_picks_the_phase_of_its_progress() -> void:
	var v := LookRule.derive(_facts({"under_construction": true, "progress": 0.5}))
	assert_int(v["look"]).is_equal(LookRule.Look.CONSTRUCTION)
	assert_int(v["phase"]).is_equal(LookRule.PHASE_FOUNDATION)

func test_an_upgrade_is_not_a_new_site() -> void:
	var v := LookRule.derive(_facts({"under_construction": true, "upgrade": true, "progress": 0.1}))
	assert_int(v["look"]).is_equal(LookRule.Look.UPGRADE)

func test_construction_wins_over_ruin() -> void:
	var v := LookRule.derive(_facts({"under_construction": true, "ruined": true, "progress": 0.9}))
	assert_int(v["look"]).is_equal(LookRule.Look.CONSTRUCTION)

func test_ruin_wins_over_working() -> void:
	assert_int(LookRule.derive(_facts({"ruined": true, "working": true}))["look"]).is_equal(LookRule.Look.RUIN)

func test_working_with_an_effect_is_active() -> void:
	assert_int(LookRule.derive(_facts({"working": true}))["look"]).is_equal(LookRule.Look.ACTIVE)

func test_working_without_an_effect_stays_idle() -> void:
	assert_int(LookRule.derive(_facts({"working": true, "fx": ""}))["look"]).is_equal(LookRule.Look.IDLE)

func test_stopped_is_idle() -> void:
	assert_int(LookRule.derive(_facts())["look"]).is_equal(LookRule.Look.IDLE)

func test_every_working_building_has_an_effect_and_houses_do_not() -> void:
	for id in ["nucleo", "sawmill", "gold_mine", "foundry", "refinery", "headquarters",
			"barracks", "warehouse", "market", "laboratory", "tower"]:
		assert_str(LookRule.fx_kind(id)).is_not_empty()
	for id in ["house", "garden", "fountain", "statue", "road"]:
		assert_str(LookRule.fx_kind(id)).is_empty()

# ── Hechos de un edificio real ───────────────────────────────────────

func test_facts_read_the_metas_of_a_node() -> void:
	var data: BuildingData = load("res://data/buildings/foundry.tres")
	var node: Node3D = auto_free(Node3D.new())
	node.set_meta("health", 0)
	var f := LookRule.facts_of(node, data)
	assert_bool(f["ruined"]).is_true()
	assert_bool(f["under_construction"]).is_false()
	assert_bool(f["working"]).is_false()   # sin badge, no trabaja
	assert_str(f["fx"]).is_equal("smoke")
