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

# ── Obra por edificio y por instancia ────────────────────────────────

const ALL_IDS := ["nucleo", "house", "sawmill", "gold_mine", "warehouse", "foundry", "barracks",
	"refinery", "tower", "headquarters", "market", "laboratory", "garden", "fountain", "statue", "road"]
const FRAMES := ["box", "chimney", "gable", "tower", "tanks", "dome", "plinth", "basin", "hall",
	"headframe", "low", "mast"]
const PILES := ["planks", "beams", "bricks", "logs", "sawdust", "rivets", "pipes", "drums", "sacks",
	"stone", "crates", "sandbags", "gravel", "soil"]

func test_the_same_instance_always_gets_the_same_seed() -> void:
	var a := LookRule.site_seed("house", Vector2i(10, 12))
	assert_int(LookRule.site_seed("house", Vector2i(10, 12))).is_equal(a)
	assert_int(a).is_greater_equal(0)
	# Ni hash() ni el azar global: un valor fijo, el mismo en cualquier sesion.
	assert_int(LookRule.site_seed("house", Vector2i(10, 12))).is_equal(LookRule.site_seed("house", Vector2i(10, 12)))

func test_neighbours_and_other_buildings_get_other_seeds() -> void:
	var seeds := {}
	for x in range(0, 40, 2):
		for y in range(0, 40, 2):
			seeds[LookRule.site_seed("house", Vector2i(x, y))] = true
	assert_int(seeds.size()).is_equal(400)
	assert_int(LookRule.site_seed("house", Vector2i(5, 5))).is_not_equal(LookRule.site_seed("sawmill", Vector2i(5, 5)))

func test_the_same_seed_gives_the_same_layout() -> void:
	var style := LookRule.site_style("house")
	var seed_val := LookRule.site_seed("house", Vector2i(10, 12))
	assert_dict(LookRule.site_layout(seed_val, style, 2)).is_equal(LookRule.site_layout(seed_val, style, 2))

func test_two_houses_side_by_side_are_laid_out_differently() -> void:
	var style := LookRule.site_style("house")
	var a := LookRule.site_layout(LookRule.site_seed("house", Vector2i(10, 12)), style, 2)
	var b := LookRule.site_layout(LookRule.site_seed("house", Vector2i(12, 12)), style, 2)
	assert_dict(a).is_not_equal(b)
	# Y no solo en el numero: cambia donde va algo que se ve.
	var visible_a := [a["gate_side"], a["scaffold_side"], a["crane_corner"], a["piles"][0]["pos"]]
	var visible_b := [b["gate_side"], b["scaffold_side"], b["crane_corner"], b["piles"][0]["pos"]]
	assert_array(visible_a).is_not_equal(visible_b)

func test_every_building_has_a_site_style_of_its_own() -> void:
	var seen := {}
	for id in ALL_IDS:
		if id == "road":
			continue
		var style := LookRule.site_style(id)
		assert_bool(String(style["frame"]) in FRAMES).override_failure_message(id).is_true()
		assert_str(String(style["frame_mat"])).is_not_empty()
		for kind in style["piles"]:
			assert_bool(String(kind) in PILES).override_failure_message("%s: %s" % [id, kind]).is_true()
		var key := JSON.stringify(style, "", true)
		assert_bool(seen.has(key)).override_failure_message("%s repite el estilo de %s" % [id, seen.get(key, "")]).is_false()
		seen[key] = id
		# Nadie se queda con el estilo por defecto.
		assert_dict(style).is_not_equal(LookRule.site_style(""))

func test_styles_hint_at_the_finished_building() -> void:
	assert_str(String(LookRule.site_style("foundry")["frame"])).is_equal("chimney")
	assert_str(String(LookRule.site_style("house")["frame"])).is_equal("gable")
	assert_str(String(LookRule.site_style("tower")["frame"])).is_equal("tower")
	assert_array(LookRule.site_style("sawmill")["piles"]).contains(["logs", "sawdust"])
	assert_array(LookRule.site_style("refinery")["piles"]).contains(["pipes", "drums"])
	assert_array(LookRule.site_style("statue")["piles"]).contains(["stone"])
	assert_str(String(LookRule.site_style("foundry")["site_fx"])).is_equal("sparks")
	assert_str(String(LookRule.site_style("statue")["site_fx"])).is_equal("dust")

func test_unknown_buildings_fall_back_to_the_default_style() -> void:
	var d := LookRule.site_style("no_existe")
	for k in GameConfig.construction_style_default:
		assert_that(d[k]).is_equal(GameConfig.construction_style_default[k])

func test_seed_of_reads_the_grid_cell_and_survives_re_registering() -> void:
	# Lo que viaja en la partida es la celda de origen: al cargar, el edificio
	# se vuelve a registrar en ella y la obra sale igual.
	var data: BuildingData = load("res://data/buildings/house.tres")
	var cell := Vector2i(3, 3)
	var a: Node3D = auto_free(Node3D.new())
	if not GridManager.can_place(cell, data.grid_size):
		return
	assert_bool(GridManager.place_building(cell, data, a)).is_true()
	var seed_a := LookRule.seed_of(a, data)
	assert_int(seed_a).is_equal(LookRule.site_seed("house", cell))
	GridManager.remove_building(a)
	var b: Node2D = auto_free(Node2D.new())
	b.position = Vector2(999, 999)
	assert_bool(GridManager.place_building(cell, data, b)).is_true()
	assert_int(LookRule.seed_of(b, data)).is_equal(seed_a)
	GridManager.remove_building(b)
