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

# ── Revision (feat/ui3-tutorial) ─────────────────────────────────────

## Un paso de espera que ya salio una vez vuelve plegado: los recursos bajan y
## suben alrededor del coste y la tarjeta no debe saltar cada vez.
func test_a_waiting_step_seen_once_comes_back_folded() -> void:
	var panel := _panel()
	await await_idle_frame()
	panel._on_step_changed("need_sawmill")
	assert_bool(panel.is_folded()).is_false()
	panel.set_folded(true)
	panel._on_step_changed("open_build")
	panel._on_step_changed("need_sawmill")
	assert_bool(panel.is_folded()).is_true()

## Tras una espera, el paso de accion sale UNA vez como "¡Ya puedes!" (abierto,
## con su flecha), se puede plegar y el recordatorio lo dice.
func test_after_a_wait_the_action_card_opens_once_as_ready() -> void:
	var panel := _panel()
	await await_idle_frame()
	panel._on_step_changed("need_sawmill")
	panel._on_step_changed("open_build")
	assert_bool(panel.is_ready_card()).is_true()
	assert_bool(panel.is_folded()).is_false()
	var badge: Label = panel.find_child("Badge", true, false)
	assert_str(badge.text).starts_with(Tr.t("TUT3_READY_BADGE"))
	assert_bool((panel.find_child("GuideLater", true, false) as Control).visible).is_true()
	panel.set_folded(true)
	panel._layout_folded(0.1)
	assert_bool(panel.is_folded()).is_true()
	assert_str(panel.reminder_text()).is_equal(Tr.t("TUT3_CHIP_READY") % Tr.t("TUT3_READY_BUILD"))
	# La segunda vez ya no: es un paso de accion como siempre.
	panel._on_step_changed("need_sawmill")
	panel._on_step_changed("open_build")
	assert_bool(panel.is_ready_card()).is_false()
	assert_bool(panel.is_folded()).is_false()
	panel.set_folded(true)
	assert_bool(panel.is_folded()).is_false()

## El recordatorio es UNA linea: el paso de ahora de la lista, nunca un "✓"
## de lo ya hecho ni la lista entera.
func test_the_reminder_is_one_line_with_the_current_item() -> void:
	var panel := _panel()
	await await_idle_frame()
	panel._on_step_changed("need_barracks")
	panel.set_folded(true)
	panel._layout_folded(0.1)
	var text: String = panel.reminder_text()
	assert_str(text).is_not_empty()
	assert_str(text).not_contains("\n")
	assert_str(text).not_contains("✓")
	var cur: Dictionary = TutorialManager.need_plan("barracks").get("current", {})
	if not cur.is_empty():
		assert_str(text).is_equal(String(cur.get("short", cur.get("text", ""))))

func test_the_first_look_lasts_longer_for_long_texts() -> void:
	var script: GDScript = load("res://scripts/ui/TutorialPanel.gd")
	assert_float(script.fold_seconds("corto")).is_equal(script.FOLD_SECONDS)
	assert_float(script.fold_seconds("x".repeat(1000))).is_equal(script.FOLD_SECONDS_MAX)

## Recoger espera mientras el Aserradero no ha cortado nada (sin icono que tocar).
func test_collect_waits_until_there_is_wood() -> void:
	var panel := _panel()
	await await_idle_frame()
	panel._on_step_changed("collect")
	assert_bool(panel.is_waiting_now()).is_true()
