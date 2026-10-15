extends GdUnitTestSuite
## El combate guiado (docs/23 §2.4): que leccion toca, que paso sale de cada
## situacion (derive_combat_step, pura), que "Saltar" solo exista del paso 4 en
## adelante y que lo dado se guarde, se cargue sin duplicar y se olvide con reset().

var _saved: Dictionary = {}

func before_test() -> void:
	_saved = TutorialManager.get_save_data()
	TutorialManager.reset()

func after_test() -> void:
	TutorialManager.load_save_data(_saved)

# ── Que leccion toca ─────────────────────────────────────────────────

func test_first_fight_teaches_the_basics() -> void:
	assert_str(TutorialManager.lesson_for([], ["infantry"])).is_equal("basics")

func test_artillery_waits_for_the_basics() -> void:
	assert_str(TutorialManager.lesson_for([], ["artillery"])).is_equal("basics")
	assert_str(TutorialManager.lesson_for(["basics"], ["artillery", "infantry"])).is_equal("artillery")

func test_nothing_once_both_are_done() -> void:
	assert_str(TutorialManager.lesson_for(["basics", "artillery"], ["artillery"])).is_equal("")
	assert_str(TutorialManager.lesson_for(["basics"], ["infantry"])).is_equal("")

# ── Lo basico, paso a paso ───────────────────────────────────────────

func _basics(f: Dictionary) -> String:
	return TutorialManager.derive_combat_step("basics", f)

func test_basics_start_by_selecting() -> void:
	assert_str(_basics({"player_turn": true, "can_move": true})).is_equal("c_select")

func test_then_move_then_attack() -> void:
	assert_str(_basics({"player_turn": true, "selected": true, "can_move": true})).is_equal("c_move")
	assert_str(_basics({"player_turn": true, "selected": true, "moved": true, "has_targets": true})).is_equal("c_attack")

func test_out_of_reach_points_at_end_turn() -> void:
	assert_str(_basics({"player_turn": true, "moved": true, "has_targets": false})).is_equal("c_attack_far")

func test_moving_counts_as_selecting() -> void:
	# Quien mueve sin tocar antes su pieza no vuelve al paso 1.
	assert_str(_basics({"player_turn": true, "moved": true, "has_targets": true})).is_equal("c_attack")

func test_enemy_turn_is_shown_once() -> void:
	assert_str(_basics({"enemy_turn": true})).is_equal("c_enemy_turn")
	assert_str(_basics({"enemy_turn": true, "enemy_seen": true})).is_equal("")

func test_defend_only_if_hurt() -> void:
	var base := {"player_turn": true, "selected": true, "moved": true, "attacked": true, "enemy_seen": true}
	assert_str(_basics(base)).is_equal("done")
	var hurt := base.duplicate()
	hurt["hurt"] = true
	assert_str(_basics(hurt)).is_equal("c_defend")
	hurt["defend_closed"] = true
	assert_str(_basics(hurt)).is_equal("done")

func test_waits_while_other_units_play() -> void:
	# Ya ataco, el enemigo aun no ha jugado y le toca a otra nuestra: nada.
	assert_str(_basics({"player_turn": true, "attacked": true})).is_equal("")

# ── Artilleria ───────────────────────────────────────────────────────

func test_artillery_lesson() -> void:
	assert_str(TutorialManager.derive_combat_step("artillery", {"player_turn": true})).is_equal("")
	assert_str(TutorialManager.derive_combat_step("artillery", {"player_turn": true, "art_active": true})).is_equal("c_art_range")
	assert_str(TutorialManager.derive_combat_step("artillery", {"art_shown": true})).is_equal("c_type_circle")
	assert_str(TutorialManager.derive_combat_step("artillery", {"art_shown": true, "circle_closed": true})).is_equal("done")

# ── Pasos ────────────────────────────────────────────────────────────

func test_no_skip_in_the_first_three_steps() -> void:
	for id in ["c_select", "c_move", "c_attack", "c_attack_far"]:
		assert_bool(TutorialManager.combat_step_skippable(id)).is_false()
	for id in ["c_enemy_turn", "c_defend", "c_art_range", "c_type_circle"]:
		assert_bool(TutorialManager.combat_step_skippable(id)).is_true()

func test_every_step_has_text_in_both_languages() -> void:
	var locale := Tr.get_locale()
	for loc in ["es", "en"]:
		Tr.set_locale(loc)
		for id in TutorialManager.COMBAT_STEPS:
			var key := String(TutorialManager.COMBAT_STEPS[id]["text"])
			assert_str(Tr.t(key)).is_not_equal(key)
	Tr.set_locale(locale)

func test_step_numbers_go_up_to_the_total() -> void:
	var top := 0
	for id in TutorialManager.COMBAT_STEPS:
		top = maxi(top, TutorialManager.combat_step_number(id))
	assert_int(top).is_equal(TutorialManager.COMBAT_TOTAL)

# ── Guardado ─────────────────────────────────────────────────────────

func test_lessons_round_trip_and_load_twice() -> void:
	TutorialManager.combat_lessons_done.append("basics")
	var data := TutorialManager.get_save_data()
	TutorialManager.reset()
	TutorialManager.load_save_data(data)
	TutorialManager.load_save_data(data)
	assert_array(TutorialManager.combat_lessons_done).contains_exactly(["basics"])

func test_reset_forgets_the_lessons() -> void:
	TutorialManager.combat_lessons_done.append("basics")
	TutorialManager.reset()
	assert_array(TutorialManager.combat_lessons_done).is_empty()
	assert_str(TutorialManager.combat_step()).is_equal("")

func test_old_save_after_first_sortie_skips_the_basics() -> void:
	TutorialManager.load_save_data({"intro_seen": true, "guide_state": "done", "first_sortie_done": true})
	assert_bool(TutorialManager.is_combat_lesson_done("basics")).is_true()
	assert_bool(TutorialManager.is_combat_lesson_done("artillery")).is_false()

func test_old_save_before_first_sortie_teaches_everything() -> void:
	TutorialManager.load_save_data({"intro_seen": true, "guide_state": "done", "first_sortie_done": false})
	assert_array(TutorialManager.combat_lessons_done).is_empty()

func test_unknown_lessons_are_ignored() -> void:
	TutorialManager.load_save_data({"combat_lessons_done": ["basics", "naval", 3]})
	assert_array(TutorialManager.combat_lessons_done).contains_exactly(["basics"])

func test_replay_clears_the_lessons_without_a_board() -> void:
	TutorialManager.combat_lessons_done.append("basics")
	TutorialManager.combat_lessons_done.append("artillery")
	TutorialManager.replay_combat_lessons()
	assert_array(TutorialManager.combat_lessons_done).is_empty()
