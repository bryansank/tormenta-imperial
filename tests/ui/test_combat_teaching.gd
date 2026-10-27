extends GdUnitTestSuite
## Ensenar el combate en la pantalla de verdad (tablero 2D, que es el de
## headless): el combate guiado empieza con la primera pelea y senala a la
## unidad, tocar una pieza abre su ficha y cuenta como el paso 1, el alcance
## enemigo se enciende con su boton y los objetivos llevan su dano previsto.

var _saved_tutorial: Dictionary = {}

func before_test() -> void:
	_saved_tutorial = TutorialManager.get_save_data()
	TutorialManager.reset()
	CombatManager.reset()

func after_test() -> void:
	CombatManager.end_encounter()
	CombatManager.reset()
	TutorialManager.load_save_data(_saved_tutorial)

func _screen() -> CanvasLayer:
	var screen: CanvasLayer = auto_free(load("res://scenes/ui/BattleScreen.tscn").instantiate())
	add_child(screen)
	screen.force_board_style("2d")
	return screen

func _open(screen: CanvasLayer, mine_ids: Array, enemy: Dictionary) -> void:
	var mine: Array = []
	var uid := 1
	for id in mine_ids:
		mine.append(CombatUnit.create(uid, id, Encounter.PLAYER, 1.0))
		uid += 1
	CombatManager.start_encounter_with_units(mine, enemy, false, 0, false, [])
	await await_idle_frame()

func test_first_fight_starts_the_basics_lesson() -> void:
	var screen := _screen()
	await await_idle_frame()
	await _open(screen, ["infantry"], {"infantry": 1})
	assert_str(TutorialManager.combat_lesson()).is_equal("basics")
	if CombatManager.is_player_turn():
		assert_str(TutorialManager.combat_step()).is_equal("c_select")
		var a: Dictionary = screen.coach_anchor("active_unit")
		assert_bool(a.has("rect")).is_true()

func test_the_board_tip_is_not_shown_over_the_lesson() -> void:
	var screen := _screen()
	await await_idle_frame()
	var tips: Array = []
	var grab := func(id, _t, _b): tips.append(id)
	EventBus.tutorial_tip_requested.connect(grab)
	await _open(screen, ["infantry"], {"infantry": 1})
	EventBus.tutorial_tip_requested.disconnect(grab)
	assert_bool(tips.has("encounter")).is_false()
	assert_bool(TutorialManager.has_seen_tip("encounter")).is_true()

func test_tapping_your_unit_opens_its_card_and_counts_as_step_one() -> void:
	var screen := _screen()
	await await_idle_frame()
	await _open(screen, ["infantry"], {"infantry": 1})
	if not CombatManager.is_player_turn():
		return
	var active: CombatUnit = CombatManager.get_active_unit()
	screen._on_cell_pressed(active.position)
	assert_object(screen.unit_card()).is_not_null()
	assert_str(TutorialManager.combat_step()).is_not_equal("c_select")

func test_targets_carry_their_predicted_damage() -> void:
	var screen := _screen()
	await await_idle_frame()
	await _open(screen, ["infantry"], {"infantry": 1})
	if not CombatManager.is_player_turn():
		return
	var active: CombatUnit = CombatManager.get_active_unit()
	var enemy: CombatUnit = null
	for u in CombatManager.get_units():
		if u.side == Encounter.ENEMY:
			enemy = u
	var previews: Dictionary = screen.target_previews(active, [enemy.uid])
	# Con el azar del dano (feat/ritmo-colono) la vista previa ensena el rango:
	# "8-11 de 75". Sin rango, el dano de siempre.
	var p: Dictionary = CombatRules.preview_damage(active, enemy)
	assert_str(String(previews[enemy.uid])).contains(str(int(p["damage_min"])))
	assert_str(String(previews[enemy.uid])).contains(str(int(p["damage_max"])))

func test_threat_button_paints_the_enemy_reach() -> void:
	TutorialManager.combat_lessons_done.append("basics")
	var screen := _screen()
	await await_idle_frame()
	await _open(screen, ["infantry"], {"infantry": 1})
	assert_array(screen.overlay_threat_cells()).is_empty()
	screen.toggle_threat()
	assert_bool(screen.overlay_threat_cells().is_empty()).is_false()
	screen.toggle_threat()
	assert_array(screen.overlay_threat_cells()).is_empty()

func test_artillery_marks_its_neighbours() -> void:
	TutorialManager.combat_lessons_done.append("basics")
	TutorialManager.combat_lessons_done.append("artillery")
	var screen := _screen()
	await await_idle_frame()
	await _open(screen, ["artillery"], {"infantry": 1})
	var active: CombatUnit = CombatManager.get_active_unit()
	if active == null or active.side != Encounter.PLAYER:
		return
	var cross: Array = screen.overlay_no_fire_cells()
	assert_bool(cross.is_empty()).is_false()
	for c in cross:
		assert_int(CombatRules.manhattan(c, active.position)).is_less(active.min_range())
