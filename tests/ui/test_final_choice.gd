extends GdUnitTestSuite
## Final con eleccion (v1.2, decision de Bryan 2026-10-25): tras ganar el
## Ataque Final el libro del Impuesto queda en la mesa. FIRMAR abre la fase del
## archipielago (Volverse el Imperio); QUEMAR deja la isla libre (sin fase, sin
## cobros), con un titulo y el emblema del sol. La eleccion es una, se guarda en
## la clave "empire" y la pantalla de victoria la pregunta (tambien al cargar).
##
## Toca autoloads de verdad: cada caso los deja como los encontro.

const FinalAuditScript := preload("res://scripts/combat/FinalAudit.gd")
const ColonyIdentity := preload("res://scripts/services/ColonyIdentity.gd")
const Objectives := preload("res://scripts/services/Objectives.gd")

const STATS := {"time_played": 3700.0, "buildings_built": 30, "trades_completed": 12, "milestones": 9}

var _saved_empire: Dictionary = {}
var _saved_progression: Dictionary = {}
var _saved_mode := 0
var _saved_tier := 0

func before_test() -> void:
	_saved_empire = EmpireManager.get_save_data()
	_saved_progression = ProgressionManager.get_save_data()
	_saved_mode = GameMode.current
	_saved_tier = GameMode.tier
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	EmpireManager.reset()
	var audit: FinalAudit = FinalAuditScript.create(5, {"infantry": 3}, 3, 70.0)
	audit.state = FinalAudit.State.WON
	ProgressionManager.final_audit = audit

func after_test() -> void:
	ProgressionManager.final_audit = null
	ProgressionManager.load_save_data(_saved_progression)
	EmpireManager.load_save_data(_saved_empire)
	GameMode.begin_run(_saved_mode, _saved_tier)

func _screen() -> CanvasLayer:
	var screen: CanvasLayer = auto_free(load("res://scenes/ui/VictoryScreen.tscn").instantiate())
	add_child(screen)
	return screen

# ── El servicio ──────────────────────────────────────────────────────

func test_winning_leaves_the_book_on_the_table() -> void:
	assert_bool(EmpireManager.choice_pending()).is_true()
	assert_bool(EmpireManager.is_active()).is_false()
	assert_str(EmpireManager.ending()).is_equal("")

func test_no_book_before_winning_or_without_the_phase() -> void:
	ProgressionManager.final_audit = null
	assert_bool(EmpireManager.choice_pending()).is_false()
	assert_bool(EmpireManager.choose_ending(EmpireManager.ENDING_BURN)).is_false()
	var audit: FinalAudit = FinalAuditScript.create(5, {"infantry": 3}, 3, 70.0)
	audit.state = FinalAudit.State.WON
	ProgressionManager.final_audit = audit
	GameMode.begin_run(GameMode.Mode.BUILDER)
	assert_bool(EmpireManager.choice_pending()).is_false()

func test_signing_opens_the_archipelago() -> void:
	var got: Array = []
	var probe := func(choice: String) -> void: got.append(choice)
	EventBus.ending_chosen.connect(probe)
	assert_bool(EmpireManager.choose_ending(EmpireManager.ENDING_SIGN)).is_true()
	EventBus.ending_chosen.disconnect(probe)
	assert_array(got).is_equal([EmpireManager.ENDING_SIGN])
	assert_bool(EmpireManager.is_active()).is_true()
	assert_bool(EmpireManager.is_free()).is_false()
	assert_bool(EmpireManager.get_book().started).is_true()
	assert_bool(EmpireManager.choice_pending()).is_false()

func test_burning_frees_the_island_without_the_phase() -> void:
	assert_bool(EmpireManager.choose_ending(EmpireManager.ENDING_BURN)).is_true()
	assert_bool(EmpireManager.is_free()).is_true()
	assert_bool(EmpireManager.is_active()).is_false()
	assert_bool(EmpireManager.get_book().started).is_false()
	assert_str(EmpireManager.next_target()).is_equal("")
	# Su titulo y el emblema del sol (antes de su rango).
	assert_str(EmpireManager.title_key()).is_equal(EmpireManager.BURN_TITLE_KEY)
	assert_bool(ColonyIdentity.empire_grants("emblems", "sun")).is_true()
	assert_bool(ColonyIdentity.empire_grants("emblems", "airship")).is_false()

func test_the_choice_is_made_once() -> void:
	assert_bool(EmpireManager.choose_ending(EmpireManager.ENDING_BURN)).is_true()
	assert_bool(EmpireManager.choose_ending(EmpireManager.ENDING_SIGN)).is_false()
	assert_bool(EmpireManager.choose_ending("eat")).is_false()
	assert_str(EmpireManager.ending()).is_equal(EmpireManager.ENDING_BURN)

func test_an_unknown_choice_is_refused() -> void:
	assert_bool(EmpireManager.choose_ending("eat")).is_false()
	assert_bool(EmpireManager.choice_pending()).is_true()

func test_the_choice_travels_in_the_save() -> void:
	EmpireManager.choose_ending(EmpireManager.ENDING_BURN)
	var data: Dictionary = EmpireManager.get_save_data()
	assert_str(String(data.get("ending", ""))).is_equal(EmpireManager.ENDING_BURN)
	EmpireManager.reset()
	assert_str(EmpireManager.ending()).is_equal("")
	EmpireManager.load_save_data(data)
	assert_bool(EmpireManager.is_free()).is_true()
	# Idempotente: cargar dos veces no cambia nada.
	EmpireManager.load_save_data(data)
	assert_str(EmpireManager.ending()).is_equal(EmpireManager.ENDING_BURN)

func test_what_to_do_asks_about_the_book() -> void:
	var halted: bool = StormManager.is_halted()
	if not halted:
		# ¿QUE HACER? solo mira el libro con la Tormenta parada para siempre.
		return
	assert_str(String(Objectives.next_step().get("why", ""))).is_equal("OBJ_WHY_BOOK")

func test_every_text_exists_in_both_languages() -> void:
	var before := Tr.get_locale()
	for locale in ["es", "en"]:
		Tr.set_locale(locale)
		for key in ["BTN_END_BOOK", "END_BOOK_TEASER", "END_BOOK_RIBBON", "END_BOOK_INTRO",
				"END_SIGN_WHO", "END_SIGN_SAYS", "END_SIGN_WHAT", "BTN_END_SIGN",
				"END_BURN_WHO", "END_BURN_SAYS", "END_BURN_WHAT", "BTN_END_BURN",
				"END_SIGN_RIBBON", "END_SIGN_BODY", "END_SIGN_REPLY", "END_SIGN_CODA",
				"END_BURN_RIBBON", "END_BURN_BODY", "END_BURN_REPLY", "END_BURN_REWARD",
				"END_BURN_CODA", "END_BURN_TITLE", "MSG_END_BURN", "OBJ_WHY_BOOK"]:
			assert_str(Tr.t(key)).override_failure_message("%s/%s" % [locale, key]).is_not_equal(key)
	Tr.set_locale(before)

# ── La pantalla ──────────────────────────────────────────────────────

func test_the_book_shows_both_instructors_and_both_choices() -> void:
	var screen := _screen()
	screen._on_victory_achieved(STATS)
	(screen.find_child("BookButton", true, false) as Button).pressed.emit()
	assert_str(screen.current_step()).is_equal("choice")
	assert_object(screen.find_child("Choose_sign", true, false)).is_not_null()
	assert_object(screen.find_child("Choose_burn", true, false)).is_not_null()
	assert_bool(_has_label(screen, Tr.t("END_SIGN_SAYS"))).is_true()
	assert_bool(_has_label(screen, Tr.t("END_BURN_SAYS"))).is_true()

func test_burning_shows_the_free_island() -> void:
	var screen := _screen()
	screen.show_choice()
	(screen.find_child("Choose_burn", true, false) as Button).pressed.emit()
	assert_str(screen.current_step()).is_equal("burn")
	assert_bool(EmpireManager.is_free()).is_true()
	assert_object(screen.find_child("EndingReward", true, false)).is_not_null()
	assert_object(screen.find_child("ArchipelagoButton", true, false)).is_null()
	assert_bool(_has_label(screen, Tr.t("END_BURN_REPLY"))).is_true()

func test_signing_shows_the_archipelago_button() -> void:
	var screen := _screen()
	screen.show_choice()
	(screen.find_child("Choose_sign", true, false) as Button).pressed.emit()
	assert_str(screen.current_step()).is_equal("sign")
	assert_bool(EmpireManager.is_active()).is_true()
	assert_object(screen.find_child("ArchipelagoButton", true, false)).is_not_null()
	assert_bool(_has_label(screen, Tr.t("END_SIGN_CODA"))).is_true()

func test_a_saved_game_with_the_book_on_the_table_asks_again() -> void:
	var screen := _screen()
	assert_bool(screen.is_showing()).is_false()
	var started: bool = GameManager.is_started()
	screen._offer_pending_choice()
	# Solo con la partida en marcha (en la suite puede no estarlo).
	assert_bool(screen.is_showing()).is_equal(started)

func _has_label(node: Node, text: String) -> bool:
	if node is Label and (node as Label).text == text:
		return true
	for child in node.get_children():
		if _has_label(child, text):
			return true
	return false
