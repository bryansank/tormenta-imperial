extends GdUnitTestSuite
## feat/ritmo-colono (decisiones de Bryan, 2026-10-25):
##   * el azar del dano, sembrado por combate (misma semilla = mismo combate) y
##     la vista previa con su rango;
##   * la Visita: solo uno de cada tres Impuestos en el tablero, el resto con
##     parte automatico y la opcion de pelearlo;
##   * una sola llave: los jefes de campana entregan las piezas del CG nivel 3;
##   * los tres capitulos y el ritmo de Colono (menos misiones, menos material).
##
## Toca los autoloads de verdad; cada caso los deja como estaban.

const EncounterScript := preload("res://scripts/combat/Encounter.gd")
const UnitScript := preload("res://scripts/combat/CombatUnit.gd")
const Rules := preload("res://scripts/combat/CombatRules.gd")
const Resolver := preload("res://scripts/combat/AutoResolver.gd")
const Chapters := preload("res://scripts/services/Chapters.gd")
const BookScript := preload("res://scripts/combat/CampaignBook.gd")

var _storm_saved: Dictionary = {}
var _army_saved: Dictionary = {}
## El rango: estas pruebas ganan peleas y piezas (XP); sin devolverlo, otra suite
## veria subir de rango y sus consejos.
var _rank_saved: Dictionary = {}
var _progression_saved: Dictionary = {}
var _campaigns_saved: Dictionary = {}
var _spread_saved := 0.0
var _tier_saved := 0
var _auto: Array = []
var _tithes: Array = []
var _chapters: Array = []

func before_test() -> void:
	_storm_saved = StormManager.get_save_data()
	_army_saved = ArmyManager.get_save_data()
	_rank_saved = RankManager.get_save_data()
	_progression_saved = ProgressionManager.get_save_data()
	_campaigns_saved = CombatManager.get_campaigns_save_data()
	_spread_saved = GameConfig.combat_damage_spread
	_tier_saved = GameMode.tier
	StormManager.reset()
	CombatManager.reset()
	ArmyManager.reset()
	_auto = []
	_tithes = []
	_chapters = []
	EventBus.defense_auto_resolved.connect(_on_auto)
	EventBus.tithe_resolved.connect(_on_tithe)
	EventBus.chapter_completed.connect(_on_chapter)

func after_test() -> void:
	EventBus.defense_auto_resolved.disconnect(_on_auto)
	EventBus.tithe_resolved.disconnect(_on_tithe)
	EventBus.chapter_completed.disconnect(_on_chapter)
	CombatManager.reset()
	GameConfig.combat_damage_spread = _spread_saved
	GameMode.tier = _tier_saved
	ProgressionManager.load_save_data(_progression_saved)
	CombatManager.load_campaigns_save_data(_campaigns_saved)
	StormManager.load_save_data(_storm_saved)
	ArmyManager.load_save_data(_army_saved)
	RankManager.load_save_data(_rank_saved)

func _on_auto(victory: bool, rounds: int, summary: Dictionary) -> void:
	_auto.append([victory, rounds, summary])

func _on_tithe(repelled: bool, taken: Dictionary) -> void:
	_tithes.append([repelled, taken])

func _on_chapter(n: int) -> void:
	_chapters.append(n)

func _given_army(units: Dictionary) -> void:
	ArmyManager.load_save_data({"units": units, "training": [], "upkeep_accum": 0.0})

func _duel(seed_value: int) -> Dictionary:
	var units: Array = [UnitScript.create(1, "infantry", 0), UnitScript.create(2, "infantry", 0),
		UnitScript.create(3, "infantry", 1), UnitScript.create(4, "artillery", 1)]
	var e: Encounter = EncounterScript.create(units, 0, false, false)
	e.seed_rng(seed_value)
	return Resolver.resolve(e)

func _hits(events: Array) -> Array:
	var out: Array = []
	for ev in events:
		if String(ev.get("e", "")) == "unit_attacked":
			out.append(int(ev["damage"]))
	return out

# ── El azar del dano ────────────────────────────────────────────────

func test_a_hit_falls_inside_its_range_around_the_expected_damage() -> void:
	GameConfig.combat_damage_spread = 0.12
	var a: CombatUnit = UnitScript.create(1, "vehicle", 0)
	var t: CombatUnit = UnitScript.create(2, "infantry", 1)
	var mean: int = Rules.damage(a, t)
	var r: Vector2i = Rules.damage_range(a, t)
	assert_int(r.x).is_less(mean)
	assert_int(r.y).is_greater(mean)
	assert_int(Rules.rolled_damage(a, t, 0.0)).is_equal(r.x)
	assert_int(Rules.rolled_damage(a, t, 0.9999)).is_equal(r.y)
	for i in range(20):
		var d: int = Rules.rolled_damage(a, t, float(i) / 20.0)
		assert_int(d).is_between(r.x, r.y)

func test_no_spread_is_the_old_fixed_damage() -> void:
	GameConfig.combat_damage_spread = 0.0
	var a: CombatUnit = UnitScript.create(1, "artillery", 0)
	var t: CombatUnit = UnitScript.create(2, "vehicle", 1)
	var r: Vector2i = Rules.damage_range(a, t)
	assert_int(r.x).is_equal(r.y)
	assert_int(r.x).is_equal(Rules.damage(a, t))

func test_the_same_seed_is_the_same_fight() -> void:
	GameConfig.combat_damage_spread = 0.12
	var one: Dictionary = _duel(777)
	var two: Dictionary = _duel(777)
	assert_array(_hits(one["events"])).is_equal(_hits(two["events"]))
	assert_bool(bool(one["victory"])).is_equal(bool(two["victory"]))
	assert_int(int(one["rounds"])).is_equal(int(two["rounds"]))

func test_another_seed_rolls_other_hits() -> void:
	GameConfig.combat_damage_spread = 0.12
	var base: Array = _hits(_duel(1)["events"])
	var differs := false
	for s in range(2, 12):
		if _hits(_duel(s)["events"]) != base:
			differs = true
			break
	assert_bool(differs).is_true()

func test_an_unseeded_board_is_still_reproducible() -> void:
	GameConfig.combat_damage_spread = 0.12
	var make := func() -> Encounter:
		return EncounterScript.create([UnitScript.create(1, "infantry", 0), UnitScript.create(2, "infantry", 1)], 0, false, false)
	var a: Encounter = make.call()
	var b: Encounter = make.call()
	assert_int(a.rng_seed).is_equal(b.rng_seed)
	assert_array(_hits(Resolver.resolve(a)["events"])).is_equal(_hits(Resolver.resolve(b)["events"]))

func test_the_preview_shows_the_range() -> void:
	GameConfig.combat_damage_spread = 0.12
	var a: CombatUnit = UnitScript.create(1, "vehicle", 0)
	var t: CombatUnit = UnitScript.create(2, "infantry", 1)
	var p: Dictionary = Rules.preview_damage(a, t)
	assert_int(int(p["damage_min"])).is_less(int(p["damage_max"]))
	var text: String = preload("res://scripts/ui/BattleScreen.gd").preview_text(p)
	assert_str(text).contains("%d-%d" % [int(p["damage_min"]), int(p["damage_max"])])
	# Un golpe que puede tumbarlo, pero no seguro.
	t.hp = int(p["damage_max"])
	var maybe: Dictionary = Rules.preview_damage(a, t)
	assert_bool(bool(maybe["may_kill"])).is_true()
	assert_bool(bool(maybe["kills"])).is_false()

# ── La Visita: uno de cada tres Impuestos en el tablero ──────────────

func _collecting(survived: int) -> void:
	var cycle: StormCycle = StormManager.get_cycle()
	cycle.storms_survived = survived
	cycle.phase = StormCycle.Phase.TITHE

func test_the_first_real_tax_and_every_third_are_the_visit() -> void:
	var due: Array = []
	for survived in range(7):
		StormManager.get_cycle().storms_survived = survived
		due.append(StormManager.is_visit_due())
	assert_array(due).is_equal([true, false, false, true, false, false, true])

func test_a_routine_tax_offers_to_fight_and_then_resolves_alone() -> void:
	_given_army({"infantry": 5, "artillery": 2})
	_collecting(1)
	StormManager._begin_tithe(1)
	assert_bool(StormManager.is_tithe_choice_open()).is_true()
	assert_bool(CombatManager.is_board_open()).is_false()
	StormManager._tick_tithe_choice(GameConfig.storm_tithe_choice_seconds + 1.0)
	assert_bool(StormManager.is_tithe_choice_open()).is_false()
	assert_int(_auto.size()).is_equal(1)
	assert_str(String((_auto[0][2] as Dictionary).get("reason", ""))).is_equal("auto_tithe")
	assert_int(_tithes.size()).is_equal(1)
	assert_bool(CombatManager.is_board_open()).is_false()

func test_the_player_can_fight_a_routine_tax_on_the_board() -> void:
	_given_army({"infantry": 5})
	_collecting(2)
	StormManager._begin_tithe(1)
	assert_bool(StormManager.fight_this_tithe()).is_true()
	assert_bool(CombatManager.is_board_open()).is_true()
	assert_bool(CombatManager.is_defending()).is_true()
	assert_array(_auto).is_empty()

func test_the_visit_opens_the_board_straight_away() -> void:
	_given_army({"infantry": 5})
	_collecting(3)
	StormManager._begin_tithe(1)
	assert_bool(StormManager.is_tithe_choice_open()).is_false()
	assert_bool(CombatManager.is_board_open()).is_true()

func test_the_report_says_when_the_next_visit_comes() -> void:
	StormManager.get_cycle().storms_survived = 1
	assert_int(StormManager.tithes_before_visit()).is_equal(2)
	StormManager.get_cycle().storms_survived = 3
	assert_int(StormManager.tithes_before_visit()).is_equal(0)

# ── Una sola llave: las piezas del CG nivel 3 ────────────────────────

func test_hq_level_3_asks_for_the_three_pieces() -> void:
	CombatManager.load_campaigns_save_data({"seed": 3})
	assert_array(CombatManager.hq_missing_pieces(3)).is_equal(["land", "sea", "air"])
	assert_array(CombatManager.hq_missing_pieces(2)).is_empty()
	assert_str(CombatManager.hq_pieces_text()).is_not_empty()
	var full := {"seed": 3, "progress": {}}
	for d in ["land", "sea", "air"]:
		full["progress"][d] = BookScript.base_total(d)
	CombatManager.load_campaigns_save_data(full)
	assert_array(CombatManager.hq_missing_pieces(3)).is_empty()
	assert_str(CombatManager.hq_pieces_text()).is_empty()

func test_the_final_assault_has_a_single_key() -> void:
	ProgressionManager.milestones_completed = {}
	assert_bool(ProgressionManager.final_audit_ready()).is_false()
	ProgressionManager.milestones_completed = {"hq_max": true}
	CombatManager.load_campaigns_save_data({"seed": 3})
	# El CG nivel 3 ya pidio las piezas: con el, el Ataque Final esta listo.
	assert_bool(ProgressionManager.final_audit_ready()).is_true()

func test_colonist_hq_asks_for_less_material_and_bag() -> void:
	var hq: BuildingData = load("res://data/buildings/headquarters.tres")
	GameMode.tier = GameMode.Tier.GOVERNOR
	var full: Dictionary = GameConfig.get_upgrade_cost(hq, 3)
	GameMode.tier = GameMode.Tier.COLONIST
	var col: Dictionary = GameConfig.get_upgrade_cost(hq, 3)
	var beams: int = ResourceManager.Type.BEAMS
	var gold: int = ResourceManager.Type.GOLD
	assert_int(int(col[beams])).is_less(int(full[beams]))
	# Y tres cuartos de la bolsa (hq_resource_mult); Gobernador la entera.
	assert_int(int(col[gold])).is_equal(roundi(float(full[gold]) * GameConfig.game_tier_rules["colonist"]["hq_resource_mult"]))
	assert_int(int(full[gold])).is_equal(int(GameConfig.hq_upgrade_costs[3]["gold"]))

# ── Los capitulos ────────────────────────────────────────────────────

func test_chapters_follow_the_eras_and_the_pieces() -> void:
	CombatManager.load_campaigns_save_data({"seed": 3})
	ProgressionManager.reset()
	assert_int(Chapters.current()).is_equal(1)
	ProgressionManager.current_era = 2
	assert_int(Chapters.current()).is_equal(2)
	ProgressionManager.current_era = 3
	# La era 3 sola no cierra el II: falta la pieza de Tierra.
	assert_int(Chapters.current()).is_equal(2)
	CombatManager.load_campaigns_save_data({"seed": 3, "progress": {"land": BookScript.base_total("land")}})
	assert_int(Chapters.current()).is_equal(3)

func test_closing_chapters_emits_once_and_in_order() -> void:
	CombatManager.load_campaigns_save_data({"seed": 3, "progress": {"land": BookScript.base_total("land")}})
	ProgressionManager.reset()
	ProgressionManager.current_era = 3
	ProgressionManager.check_chapters()
	ProgressionManager.check_chapters()
	assert_array(_chapters).is_equal([1, 2])
	assert_array(ProgressionManager.get_save_data()["chapters"]).is_equal([1, 2])

func test_an_old_save_closes_its_chapters_silently() -> void:
	CombatManager.load_campaigns_save_data({"seed": 3})
	var data: Dictionary = ProgressionManager.get_save_data()
	data["current_era"] = 2
	data.erase("chapters")
	ProgressionManager.load_save_data(data)
	ProgressionManager._sync_chapters_silently()
	assert_bool(ProgressionManager.is_chapter_closed(1)).is_true()
	assert_array(_chapters).is_empty()

func test_chapter_texts_exist_in_both_languages() -> void:
	var keys: Array = ["CHAPTER_N", "CHAPTER_DONE", "CHAPTER_NEXT", "CHAPTER_OBJ", "BTN_CHAPTER_GO",
		"HQ3_PIECES_MISSING", "HQ3_PIECES_HOW", "MSG_PIECE_WON", "PIECE_FROM_BOSS", "CAMP_REPORT_PIECE",
		"STORM_TITHE_AUTO_OFFER", "MSG_TITHE_AUTO_WON", "MSG_TITHE_AUTO_LOST", "BTN_FIGHT_TITHE",
		"LBL_REPORT_AUTO_KICKER", "LBL_REPORT_NEXT_VISIT", "LBL_REPORT_NEXT_VISIT_1",
		"LBL_PREVIEW_DAMAGE_RANGE", "LBL_PREVIEW_KILL_RANGE", "LBL_PREVIEW_MAY_KILL"]
	for n in range(1, 4):
		keys.append("CHAPTER_%d_TITLE" % n)
		keys.append("CHAPTER_%d_GOAL" % n)
		keys.append("CHAPTER_%d_CLOSE" % n)
	for n in range(1, 4):
		for goal in Chapters.goals(n):
			keys.append(String(goal["key"]))
	var saved: String = Tr.get_locale()
	for locale in ["es", "en"]:
		Tr.set_locale(locale)
		for key in keys:
			assert_str(Tr.t(String(key))).override_failure_message("%s sin %s" % [locale, key]).is_not_equal(String(key))
	Tr.set_locale(saved)

## La rebaja por derrota se queda (medido: sin ella, con solo el azar, una de cada
## cuatro misiones dificiles no caia en 4 intentos; docs/16 "Azar del dano"), pero
## ya no es oculta: el panel de MISIONES ensena cuanto ha perdido el enemigo.
func test_the_retry_ease_is_shown_as_a_percentage() -> void:
	CombatManager.load_campaigns_save_data({"seed": 3, "fails": {"land": 2}})
	var want: int = roundi((1.0 - maxf(GameConfig.campaign_retry_floor, pow(GameConfig.campaign_retry_ease, 2.0))) * 100.0)
	assert_int(CombatManager.campaign_retry_ease_pct("land")).is_equal(want)
	assert_int(want).is_greater(0)
	CombatManager.load_campaigns_save_data({"seed": 3})
	assert_int(CombatManager.campaign_retry_ease_pct("land")).is_equal(0)

## Colono baja una oleada al asedio (3-4); Gobernador el de siempre (4-5).
func test_colonist_siege_has_one_wave_less() -> void:
	GameMode.tier = GameMode.Tier.COLONIST
	var col: Vector2i = GameConfig.get_final_audit_waves()
	GameMode.tier = GameMode.Tier.GOVERNOR
	var gob: Vector2i = GameConfig.get_final_audit_waves()
	assert_int(gob.x).is_equal(GameConfig.final_audit_waves.x)
	assert_int(col.x).is_equal(gob.x - 1)
	assert_int(col.y).is_equal(gob.y - 1)
