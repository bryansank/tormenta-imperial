extends GdUnitTestSuite
## Los instructores (feat/instructores, docs/23 §2.6): la Capitana Ada Remache
## (colonia) y el Sargento Mayor Casimiro Bombarda (combate). Un busto dibujado
## por codigo junto a la tarjeta del tutorial, la de consejo y los partes de
## guerra; se pega a la tarjeta sin tapar lo senalado, se encoge o se oculta si
## no cabe, habla mientras se escribe el texto y Ajustes > Interfaz lo oculta.
##
## Toca GameConfig.ui_instructors_visible en memoria (sin guardar) y lo
## restaura; el estado del tutorial tambien.

const Bust := preload("res://scripts/ui/InstructorBust.gd")
const WarReport := preload("res://scripts/ui/WarReportScreen.gd")
const HelpCatalog := preload("res://scripts/ui/HelpCatalog.gd")

var _saved_visible := true
var _saved_locale := "es"

func before_test() -> void:
	_saved_visible = GameConfig.ui_instructors_visible
	GameConfig.ui_instructors_visible = true
	_saved_locale = Tr.get_locale()

func after_test() -> void:
	GameConfig.ui_instructors_visible = _saved_visible
	Tr.set_locale(_saved_locale)

func _bust() -> Control:
	var b: Control = auto_free(Bust.new())
	add_child(b)
	return b

# ── Colocacion ───────────────────────────────────────────────────────

func test_the_bust_sits_left_of_the_card_looking_at_it() -> void:
	var vp := Vector2(1280, 720)
	var card := Rect2(410, 500, 460, 120)
	var d: Dictionary = Bust.dock_rect(vp, card, Bust.BASE_SIZE)
	assert_bool(d.is_empty()).is_false()
	var r: Rect2 = d["rect"]
	assert_float(r.end.x).is_less_equal(card.position.x)
	assert_float(r.end.y).is_equal_approx(card.end.y, 0.5)
	assert_int(int(d["facing"])).is_equal(1)
	assert_bool(r.intersects(card)).is_false()

func test_without_room_on_the_left_it_goes_right_and_looks_back() -> void:
	var vp := Vector2(1280, 720)
	var card := Rect2(20, 500, 460, 120)
	var d: Dictionary = Bust.dock_rect(vp, card, Bust.BASE_SIZE)
	var r: Rect2 = d["rect"]
	assert_float(r.position.x).is_greater_equal(card.end.x)
	assert_int(int(d["facing"])).is_equal(-1)

func test_it_never_covers_what_the_tutorial_points_at() -> void:
	var vp := Vector2(1280, 720)
	var card := Rect2(410, 500, 460, 120)
	# Lo senalado justo a la izquierda de la tarjeta.
	var focus := Rect2(250, 480, 150, 150)
	var d: Dictionary = Bust.dock_rect(vp, card, Bust.BASE_SIZE, [focus])
	assert_bool(d.is_empty()).is_false()
	assert_bool((d["rect"] as Rect2).intersects(focus)).is_false()

func test_on_a_narrow_phone_it_shrinks_or_hides_but_stays_on_screen() -> void:
	var vp := Vector2(400, 720)
	var card := Rect2(16, 400, 368, 160)
	var d: Dictionary = Bust.dock_rect(vp, card, Bust.base_size_for(vp))
	if not d.is_empty():
		var r: Rect2 = d["rect"]
		assert_bool(Rect2(Vector2(16, 16), vp - Vector2(32, 32)).encloses(r)).is_true()
		assert_bool(r.intersects(Rect2(card.position + Vector2(0, 8), card.size - Vector2(0, 8)))).is_false()
	# Sin sitio en ningun lado (la tarjeta llena la pantalla): se oculta.
	var full := Rect2(16, 16, 368, 688)
	assert_bool(Bust.dock_rect(vp, full, Bust.base_size_for(vp)).is_empty()).is_true()

func test_a_phone_gets_the_small_bust() -> void:
	assert_vector(Bust.base_size_for(Vector2(800, 400))).is_equal(Bust.SMALL_SIZE)
	assert_vector(Bust.base_size_for(Vector2(1280, 720))).is_equal(Bust.BASE_SIZE)

func test_dock_to_hides_it_when_the_setting_is_off() -> void:
	var b := _bust()
	GameConfig.ui_instructors_visible = false
	assert_bool(b.dock_to(Vector2(1280, 720), Rect2(410, 500, 460, 120))).is_false()
	assert_bool(b.visible).is_false()
	GameConfig.ui_instructors_visible = true
	assert_bool(b.dock_to(Vector2(1280, 720), Rect2(410, 500, 460, 120))).is_true()
	assert_bool(b.visible).is_true()

# ── Caras y voces ────────────────────────────────────────────────────

func test_every_tutorial_step_has_a_known_face() -> void:
	for step in TutorialManager.GUIDE_STEPS:
		assert_bool(Bust.expression_for_step(step) in Bust.EXPRESSIONS).is_true()
	for step in TutorialManager.COMBAT_STEPS:
		assert_bool(Bust.expression_for_combat_step(step) in Bust.EXPRESSIONS).is_true()
	assert_str(Bust.expression_for_step("done")).is_equal("happy")
	assert_str(Bust.expression_for_step("need_house")).is_equal("worried")

func test_storm_and_army_tips_are_the_sergeants() -> void:
	assert_str(Bust.who_for_category("storm")).is_equal(Bust.COMBAT)
	assert_str(Bust.who_for_category("army")).is_equal(Bust.COMBAT)
	assert_str(Bust.who_for_category("economy")).is_equal(Bust.COLONY)
	assert_str(Bust.who_for_category("basics")).is_equal(Bust.COLONY)
	for cat in HelpCatalog.CATEGORIES:
		assert_bool(Bust.expression_for_category(cat) in Bust.EXPRESSIONS).is_true()

func test_six_expressions_and_unknown_falls_back() -> void:
	assert_int(Bust.EXPRESSIONS.size()).is_equal(6)
	var b := _bust()
	b.set_expression("nonsense")
	assert_str(b.expression).is_equal("point")
	b.set_who("nobody")
	assert_str(b.who).is_equal(Bust.COLONY)

func test_every_face_of_both_draws_without_errors() -> void:
	var b := _bust()
	b.size = Bust.BASE_SIZE
	for who in Bust.WHO:
		for e in Bust.EXPRESSIONS:
			for dir in [1, -1]:
				b.show_as(who, e, dir)
				b.mouth_open = not b.mouth_open
				await get_tree().process_frame
	assert_bool(is_instance_valid(b)).is_true()

## Las caras en circulo (CartoonTheme.CaptainFace y la InstructorFace de la 1.2)
## llaman a _draw_ada / _draw_bombarda: el mismo retrato que el busto, con su
## boca y sin brazos. Siguen existiendo y pintan todas las caras.
func test_the_round_faces_use_the_same_portrait() -> void:
	var face: Control = auto_free(CartoonTheme.captain_face(64))
	add_child(face)
	var sarge: Control = auto_free(_SargeFace.new())
	sarge.size = Vector2(64, 64)
	add_child(sarge)
	for e in Bust.EXPRESSIONS:
		face.set("mood", e)
		sarge.mood = e
		sarge.queue_redraw()
		await get_tree().process_frame
	assert_bool(is_instance_valid(face) and is_instance_valid(sarge)).is_true()

class _SargeFace extends Control:
	var mood := "happy"

	func _draw() -> void:
		var h := size.y * 2.15
		Bust._draw_bombarda(self, Rect2(Vector2(size.x * 0.5 - h * 0.4, -0.1 * h), Vector2(h * 0.8, h)), mood)

# ── Hablar ───────────────────────────────────────────────────────────

func test_speaking_types_the_text_and_moves_the_mouth() -> void:
	var b := _bust()
	var label: Label = auto_free(Label.new())
	add_child(label)
	label.text = "Toca CONSTRUIR y elige el Aserradero."
	b.speak(label)
	assert_bool(b.is_speaking()).is_true()
	assert_float(label.visible_ratio).is_less(1.0)
	# El texto escrito poco a poco no cambia el tamano de la tarjeta.
	assert_int(label.visible_characters_behavior).is_equal(TextServer.VC_CHARS_AFTER_SHAPING)
	b.finish_speaking()
	assert_bool(b.is_speaking()).is_false()
	assert_bool(b.mouth_open).is_false()
	assert_float(label.visible_ratio).is_equal(1.0)

func test_hidden_instructors_do_not_type_the_text() -> void:
	GameConfig.ui_instructors_visible = false
	var b := _bust()
	var label: Label = auto_free(Label.new())
	add_child(label)
	label.text = "Hola"
	b.speak(label)
	assert_bool(b.is_speaking()).is_false()
	assert_float(label.visible_ratio).is_equal(1.0)

func test_talking_time_is_bounded() -> void:
	assert_float(Bust.talk_seconds(1)).is_equal(Bust.TALK_MIN)
	assert_float(Bust.talk_seconds(5000)).is_equal(Bust.TALK_MAX)

# ── Textos ───────────────────────────────────────────────────────────

func test_names_ranks_and_quotes_exist_in_both_languages() -> void:
	var keys: Array = ["HUD_INSTRUCTORS", "INSTR_SIGNED", "INSTR_COLONY_MOTTO", "INSTR_COMBAT_MOTTO"]
	for who in Bust.WHO:
		keys.append_array([Bust.name_key(who), Bust.rank_key(who), Bust.short_key(who)])
	for c in WarReport.QUOTE_CASES:
		for n in WarReport.QUOTE_VARIANTS:
			keys.append(WarReport.quote_key(c, n))
	for locale in ["es", "en"]:
		Tr.set_locale(locale)
		for k in keys:
			assert_str(Tr.t(k)).is_not_equal(k)

func test_the_sergeant_rotates_his_lines() -> void:
	var seen := {}
	for n in 6:
		seen[WarReport.quote_key("DEFENSE_WON", n)] = true
	assert_int(seen.size()).is_equal(WarReport.QUOTE_VARIANTS)
	assert_str(WarReport.quote_case_for(WarReport.Kind.DEFENSE, false)).is_equal("DEFENSE_LOST")
	assert_str(WarReport.quote_case_for(WarReport.Kind.TITHE, true)).is_equal("TITHE_REPELLED")
	assert_str(WarReport.quote_case_for(WarReport.Kind.TRIAL, false)).is_equal("TRIAL_TAKEN")
	assert_str(WarReport.quote_face(WarReport.Kind.TITHE, false)).is_equal("angry")

func test_a_war_report_carries_a_sergeant_line() -> void:
	var screen: CanvasLayer = auto_free(load("res://scenes/ui/WarReportScreen.tscn").instantiate())
	add_child(screen)
	screen.set_process(false)
	EventBus.tithe_resolved.emit(true, {})
	await get_tree().process_frame
	if not screen.try_show_next():
		return  # Un asedio en marcha en este proceso: no hay parte del Diezmo.
	assert_bool(screen.is_instructor_shown()).is_true()
	assert_str(screen.quote_case()).is_equal("TITHE_REPELLED")
	assert_str(screen.quote_text()).is_not_empty()
	assert_str(screen.quote_text()).is_not_equal(WarReport.quote_key("TITHE_REPELLED", 0))
	screen.close_current()
	assert_bool(screen.instructor().is_speaking()).is_false()

# ── Ajustes ──────────────────────────────────────────────────────────

func test_the_setting_lives_in_the_interface_tab_list() -> void:
	assert_bool("Instructors" in HudRegistry.hideable_ids()).is_true()
	assert_bool("Instructors" in HudRegistry.movable_ids()).is_false()
	HudRegistry.set_hidden("Instructors", true, false)
	assert_bool(GameConfig.ui_instructors_visible).is_false()
	assert_bool(HudRegistry.is_hidden("Instructors")).is_true()
	HudRegistry.set_hidden("Instructors", false, false)
	assert_bool(GameConfig.ui_instructors_visible).is_true()
