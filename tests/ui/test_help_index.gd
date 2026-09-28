extends GdUnitTestSuite
## El indice de AYUDA: el menu ☰ unico lo abre por el grupo "help_index" con
## open(). Lista las basicas siempre y el resto en cuanto se han visto, por
## categoria, respeta el modo (Constructor no habla de la Tormenta) y al tocar
## una la vuelve a abrir.

const IndexScene := preload("res://scenes/ui/HelpIndexPanel.tscn")

var _saved_tutorial: Dictionary = {}
var _saved_mode := 0
var _reopened: Array = []

func before_test() -> void:
	_saved_tutorial = TutorialManager.get_save_data()
	_saved_mode = GameMode.current
	TutorialManager.load_save_data({"intro_seen": true, "guide_state": "done"})
	_reopened.clear()
	EventBus.help_reopen_requested.connect(_on_reopen)

func after_test() -> void:
	EventBus.help_reopen_requested.disconnect(_on_reopen)
	GameMode.current = _saved_mode
	TutorialManager.load_save_data(_saved_tutorial)

func _on_reopen(id: String) -> void:
	_reopened.append(id)

func _index() -> CanvasLayer:
	var idx: CanvasLayer = auto_free(IndexScene.instantiate())
	add_child(idx)
	return idx

func test_it_answers_to_the_help_index_group() -> void:
	var idx := _index()
	var found: Node = get_tree().get_first_node_in_group("help_index")
	assert_object(found).is_not_null()
	assert_bool(found.has_method("open")).is_true()
	idx.open()
	assert_bool(idx.is_open()).is_true()
	assert_bool(UIManager._window_stack.has(idx)).is_true()
	idx.close()
	assert_bool(UIManager._window_stack.has(idx)).is_false()

func test_it_lists_the_basics_before_anything_is_seen() -> void:
	GameMode.current = GameMode.Mode.CAMPAIGN
	var idx := _index()
	var ids: Array = idx.listed_ids()
	assert_array(ids).contains(["callout_build", "callout_objective", "callout_resources", "guide_first_steps", "guide_pool"])
	assert_array(ids).not_contains(["overflow", "market", "callout_skirmish"])

func test_a_seen_tip_joins_the_list() -> void:
	GameMode.current = GameMode.Mode.CAMPAIGN
	TutorialManager.offer_tip("market")
	var idx := _index()
	assert_array(idx.listed_ids()).contains(["market"])

func test_builder_mode_does_not_talk_about_the_storm() -> void:
	GameMode.current = GameMode.Mode.BUILDER
	TutorialManager.tips_seen.append("storm_started")
	var idx := _index()
	var ids: Array = idx.listed_ids()
	assert_array(ids).not_contains(["guide_storm", "storm_started"])
	GameMode.current = GameMode.Mode.CAMPAIGN
	assert_array(idx.listed_ids()).contains(["guide_storm", "storm_started"])

func test_tapping_an_entry_closes_the_index_and_reopens_that_help() -> void:
	var idx := _index()
	idx.open()
	var btn: Button = idx.find_child("Help_callout_resources", true, false)
	assert_object(btn).is_not_null()
	btn.pressed.emit()
	assert_bool(idx.is_open()).is_false()
	assert_array(_reopened).contains_exactly(["callout_resources"])

func test_every_listed_help_has_a_title_and_a_body_in_both_languages() -> void:
	var HC := load("res://scripts/ui/HelpCatalog.gd")
	var saved := Tr.get_locale()
	for loc in ["es", "en"]:
		Tr.set_locale(loc)
		for id in HC.ENTRIES:
			var e: Dictionary = HC.ENTRIES[id]
			assert_str(Tr.t(e["title"])).override_failure_message("%s title %s" % [id, loc]).is_not_equal(e["title"])
			assert_str(Tr.t(e["body"])).override_failure_message("%s body %s" % [id, loc]).is_not_equal(e["body"])
		for cat in HC.CATEGORY_KEYS:
			assert_str(Tr.t(HC.CATEGORY_KEYS[cat])).is_not_equal(HC.CATEGORY_KEYS[cat])
	Tr.set_locale(saved)

func test_every_tip_of_the_manager_is_in_the_catalog() -> void:
	var HC := load("res://scripts/ui/HelpCatalog.gd")
	for tip in TutorialManager.TIPS:
		assert_bool(HC.has(tip)).override_failure_message("falta %s en HelpCatalog" % tip).is_true()
		assert_str(HC.kind(tip)).is_equal("tip")

func test_it_opens_while_the_game_is_paused() -> void:
	# Desde el menu de pausa o el principal.
	var idx := _index()
	get_tree().paused = true
	idx.open()
	var mode: int = idx.process_mode
	idx.close()
	get_tree().paused = false
	assert_int(mode).is_equal(Node.PROCESS_MODE_ALWAYS)
