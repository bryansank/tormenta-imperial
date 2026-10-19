extends GdUnitTestSuite
## Pasos de espera plegados (queja de Bryan, 2026-10-19: "cuando no tienes los
## recursos el tutorial se vuelve molesto"): need_* y wait_* se pliegan a un
## recordatorio pequeno, sin flecha, aro ni velo; tocarlo los abre; tras mucho
## rato sin avance se resalta (nunca vuelve la tarjeta grande sola). Los pasos de
## accion no se pliegan.

var _saved: Dictionary = {}

func before_test() -> void:
	_saved = TutorialManager.get_save_data()

func after_test() -> void:
	TutorialManager.load_save_data(_saved)

func _panel() -> CanvasLayer:
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/TutorialPanel.tscn").instantiate())
	add_child(panel)
	return panel

func test_waiting_steps_are_need_and_wait() -> void:
	var script: GDScript = load("res://scripts/ui/TutorialPanel.gd")
	assert_bool(script.is_waiting_step("need_sawmill")).is_true()
	assert_bool(script.is_waiting_step("wait_barracks")).is_true()
	assert_bool(script.is_waiting_step("open_build")).is_false()
	assert_bool(script.is_waiting_step("place_sawmill")).is_false()

func test_a_waiting_step_folds_into_a_reminder_without_arrow_or_veil() -> void:
	var panel := _panel()
	await await_idle_frame()
	panel._on_step_changed("need_sawmill")
	assert_bool(panel.is_folded()).is_false()
	assert_bool((panel.find_child("GuideLater", true, false) as Control).visible).is_true()
	panel.set_folded(true)
	panel._layout_folded(0.1)
	assert_bool(panel.is_folded()).is_true()
	assert_bool(panel.reminder().visible).is_true()
	assert_bool((panel.find_child("CoachCard", true, false) as Control).visible).is_false()
	assert_bool((panel.find_child("Arrow", true, false) as Control).visible).is_false()
	assert_bool((panel.find_child("Ring", true, false) as Control).visible).is_false()
	for r in panel._dim:
		assert_bool((r as Control).visible).is_false()
	# Tocar el recordatorio vuelve a abrir la tarjeta.
	panel.reminder().pressed.emit()
	assert_bool(panel.is_folded()).is_false()

func test_a_long_wait_only_highlights_the_reminder() -> void:
	var panel := _panel()
	await await_idle_frame()
	panel._on_step_changed("wait_sawmill")
	panel.set_folded(true)
	panel._layout_folded(panel.IDLE_REMIND_SECONDS + 1.0)
	assert_bool(panel._chip_hot).is_true()
	assert_bool(panel.is_folded()).is_true()

func test_action_steps_never_fold() -> void:
	var panel := _panel()
	await await_idle_frame()
	panel._on_step_changed("open_build")
	panel.set_folded(true)
	assert_bool(panel.is_folded()).is_false()
	assert_bool((panel.find_child("GuideLater", true, false) as Control).visible).is_false()
