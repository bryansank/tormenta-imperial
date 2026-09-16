extends GdUnitTestSuite
## The Skirmish callout follows the Skirmish sidebar button: it is built from
## the start with its own text, stays hidden until a Barracks stands and the
## sidebar is open, and goes away again when either condition drops.
## ArmyManager.barracks_count() reads current_scene/BuildingPlacer, so a stub
## placer is parked there for the duration of each test.

const HelperPanelScene := preload("res://scenes/ui/HelperPanel.tscn")
const HelperPanelScript := preload("res://scripts/ui/HelperPanel.gd")

class FakePlacer extends Node:
	var barracks := 0
	func count_building(building_id: String) -> int:
		return barracks if building_id == "barracks" else 0

var _panel: CanvasLayer
var _placer: FakePlacer
var _scene: Node
var _made_scene := false
var _saved_helper_visible := true

func before_test() -> void:
	_saved_helper_visible = GameConfig.ui_helper_visible
	GameConfig.ui_helper_visible = true

	_scene = get_tree().current_scene
	if _scene == null:
		_scene = Node.new()
		_scene.name = "SkirmishCalloutTestScene"
		get_tree().root.add_child(_scene)
		get_tree().current_scene = _scene
		_made_scene = true
	_placer = FakePlacer.new()
	_placer.name = "BuildingPlacer"
	_scene.add_child(_placer)

	_panel = HelperPanelScene.instantiate()
	add_child(_panel)

func after_test() -> void:
	remove_child(_panel)
	_panel.free()
	_scene.remove_child(_placer)
	_placer.free()
	if _made_scene:
		get_tree().current_scene = null
		get_tree().root.remove_child(_scene)
		_scene.free()
	GameConfig.ui_helper_visible = _saved_helper_visible

func _callout() -> PanelContainer:
	return _panel.find_child(HelperPanelScript.SKIRMISH_CALLOUT_NAME, true, false) as PanelContainer

## The player opens the sidebar: same signal SkirmishPanel uses to show its button.
func _open_sidebar() -> void:
	EventBus.sidebar_toggled.emit(true)

# ── The callout exists and says the right thing ──────────────────────

func test_the_stub_placer_is_what_army_manager_reads() -> void:
	assert_int(ArmyManager.barracks_count()).is_equal(0)
	_placer.barracks = 1
	assert_int(ArmyManager.barracks_count()).is_equal(1)

func test_the_callout_is_registered_under_its_name() -> void:
	assert_object(_callout()).is_not_null()

func test_there_is_exactly_one_skirmish_callout() -> void:
	var count := 0
	for child in _panel.find_children("*", "PanelContainer", true, false):
		if child.name == HelperPanelScript.SKIRMISH_CALLOUT_NAME:
			count += 1
	assert_int(count).is_equal(1)

func test_the_callout_carries_the_skirmish_help_text() -> void:
	var label := _callout().get_child(0) as Label
	assert_object(label).is_not_null()
	assert_str(label.text).is_equal(Tr.t("LBL_HELP_SKIRMISH"))

func test_the_help_text_exists_in_both_languages() -> void:
	for locale in ["es", "en"]:
		var text: String = String(Tr._STRINGS[locale].get("LBL_HELP_SKIRMISH", ""))
		assert_str(text).override_failure_message("LBL_HELP_SKIRMISH missing for %s" % locale).is_not_empty()
		assert_str(text).is_not_equal("LBL_HELP_SKIRMISH")

# ── It follows the Skirmish button ───────────────────────────────────

func test_hidden_while_no_barracks_stands() -> void:
	_open_sidebar()
	assert_bool(_panel.is_skirmish_callout_shown()).is_false()

func test_hidden_while_the_sidebar_is_closed_even_with_a_barracks() -> void:
	_placer.barracks = 1
	EventBus.sidebar_toggled.emit(false)
	assert_bool(_panel.is_skirmish_callout_shown()).is_false()

func test_shown_once_a_barracks_stands_and_the_sidebar_opens() -> void:
	_placer.barracks = 1
	_open_sidebar()
	assert_bool(_panel.is_skirmish_callout_shown()).is_true()

func test_army_changed_is_enough_to_reveal_it() -> void:
	_open_sidebar()
	_placer.barracks = 1
	EventBus.army_changed.emit()
	assert_bool(_panel.is_skirmish_callout_shown()).is_true()

func test_gone_again_when_the_last_barracks_falls() -> void:
	# The demolition itself is not emitted here: GameManager autosaves on it and
	# PopulationManager reads the node. army_changed follows every barracks loss
	# (capacity drops) and is one of the signals the callout re-checks on.
	_placer.barracks = 1
	_open_sidebar()
	assert_bool(_panel.is_skirmish_callout_shown()).is_true()
	_placer.barracks = 0
	EventBus.army_changed.emit()
	assert_bool(_panel.is_skirmish_callout_shown()).is_false()

func test_gone_when_the_sidebar_closes() -> void:
	_placer.barracks = 1
	_open_sidebar()
	EventBus.sidebar_toggled.emit(false)
	assert_bool(_panel.is_skirmish_callout_shown()).is_false()

# ── It behaves like every other callout ──────────────────────────────

func test_the_helper_toggle_hides_it_with_the_rest() -> void:
	_placer.barracks = 1
	_open_sidebar()
	_panel._set_callouts_visible(false)
	assert_bool(_panel.is_skirmish_callout_shown()).is_false()
	_panel._set_callouts_visible(true)
	assert_bool(_panel.is_skirmish_callout_shown()).is_true()

func test_the_other_callouts_do_not_depend_on_the_barracks() -> void:
	# Only the Skirmish tip is gated; the rest of the guide stays as it was.
	var visible_others := 0
	for child in _panel.find_children("*", "PanelContainer", true, false):
		if child.name != HelperPanelScript.SKIRMISH_CALLOUT_NAME and child.get_parent() == _callout().get_parent() and child.visible:
			visible_others += 1
	assert_int(visible_others).is_greater(0)
