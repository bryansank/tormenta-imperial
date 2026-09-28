extends GdUnitTestSuite
## TutorialPanel: aloja el prologo y pinta los pasos del tutorial guiado sobre la
## interfaz real (velo con hueco, marco, flecha y una linea de texto). Se prueba
## que el prologo se abre a peticion y avisa al cerrar, que un paso ensena su
## texto y su numero, que el velo no se come ningun toque, que "Saltar tutorial"
## lo salta, y que la tarjeta nunca tapa lo que senala.

var _closed := 0
var _saved: Dictionary = {}

func before_test() -> void:
	_closed = 0
	_saved = TutorialManager.get_save_data()
	TutorialManager.reset()
	EventBus.tutorial_intro_closed.connect(_count_closed)

func after_test() -> void:
	EventBus.tutorial_intro_closed.disconnect(_count_closed)
	get_tree().paused = false
	TutorialManager.load_save_data(_saved)

func _count_closed() -> void:
	_closed += 1

func _panel() -> CanvasLayer:
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/TutorialPanel.tscn").instantiate())
	add_child(panel)
	return panel

# ── Prologo ──────────────────────────────────────────────────────────

func test_the_prologue_opens_on_request_and_reports_its_close() -> void:
	var panel := _panel()
	await await_idle_frame()
	assert_bool(panel.is_intro_open()).is_false()
	TutorialManager.show_prologue()
	var open: bool = panel.is_intro_open()
	var page: int = panel.current_page()
	panel._close()
	assert_bool(open).is_true()
	assert_int(page).is_equal(0)
	assert_bool(panel.is_intro_open()).is_false()
	assert_int(_closed).is_equal(1)
	assert_bool(TutorialManager.intro_seen).is_true()

func test_the_prologue_is_not_a_window_of_the_stack() -> void:
	# Pantalla completa propia, por encima de todo: no entra en la pila de
	# UIManager (que le cambiaria la capa) ni la cierra un ESC de ventana.
	var panel := _panel()
	await await_idle_frame()
	TutorialManager.show_prologue()
	var in_stack: bool = UIManager._window_stack.has(panel.prologue())
	panel._close()
	assert_bool(in_stack).is_false()

# ── Pasos del tutorial ───────────────────────────────────────────────

func _start_guide() -> void:
	TutorialManager.intro_seen = true
	TutorialManager.start_guide(false)

func test_a_step_shows_its_line_and_number() -> void:
	var panel := _panel()
	await await_idle_frame()
	_start_guide()
	await await_idle_frame()
	assert_str(panel.current_step()).is_equal("open_build")
	assert_bool(panel.is_coach_visible()).is_true()
	assert_str(panel.coach_text()).is_not_empty()
	var badge: Label = panel.find_child("Badge", true, false)
	assert_str(badge.text).contains("1")
	assert_str(badge.text).contains(str(TutorialManager.GUIDE_TOTAL))

func test_the_veil_never_eats_a_touch() -> void:
	# Fuera de orden tiene que poder tocarse todo: solo la tarjeta para el dedo.
	var panel := _panel()
	await await_idle_frame()
	_start_guide()
	await await_idle_frame()
	for c in panel.find_child("Coach", true, false).find_children("*", "Control", true, false):
		var ctl := c as Control
		var in_card: bool = ctl.name == "CoachCard" or panel.find_child("CoachCard", true, false).is_ancestor_of(ctl)
		if not in_card:
			assert_int(ctl.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)

func test_skip_tutorial_skips_it() -> void:
	var panel := _panel()
	await await_idle_frame()
	_start_guide()
	await await_idle_frame()
	panel.skip_button().pressed.emit()
	await await_idle_frame()
	assert_str(TutorialManager.guide_state).is_equal(TutorialManager.GUIDE_SKIPPED)
	assert_bool(panel.is_coach_visible()).is_false()

func test_the_coach_hides_while_paused() -> void:
	var panel := _panel()
	await await_idle_frame()
	_start_guide()
	await await_idle_frame()
	# Con el arbol en pausa el runner se para: nada de esperar frames, el
	# _process del panel se llama a mano.
	get_tree().paused = true
	panel._process(0.016)
	var hidden_paused: bool = not panel.is_coach_visible()
	get_tree().paused = false
	panel._process(0.016)
	assert_bool(hidden_paused).is_true()
	assert_bool(panel.is_coach_visible()).is_true()

func test_the_coach_hides_while_the_prologue_is_open() -> void:
	var panel := _panel()
	await await_idle_frame()
	_start_guide()
	TutorialManager.show_prologue()
	panel._process(0.016)
	var hidden: bool = not panel.is_coach_visible()
	panel._close()
	assert_bool(hidden).is_true()

## QA en tableta (flujo 04): en el paso del aserradero la tarjeta tapaba el ✓
## CONSTRUIR AQUI. Con el ✓ a la vista, la tarjeta se aparta del bosque y del ✓.
func test_the_card_never_covers_the_touch_confirm_button() -> void:
	var TP := load("res://scripts/ui/TutorialPanel.gd")
	var vp := Vector2(1024, 640)
	var size := Vector2(420, 140)
	var forest := Rect2(Vector2(410, 435) - Vector2(40, 40), Vector2(80, 80))
	var confirm := Rect2(445, 225, 150, 42)
	var pos: Vector2 = TP.card_position(vp, size, TP.with_confirm(forest, confirm))
	var card := Rect2(pos, size)
	assert_bool(card.intersects(confirm)).is_false()
	assert_bool(card.intersects(forest)).is_false()
	assert_bool(TP.with_confirm(forest, Rect2()) == forest).is_true()

func test_the_card_goes_beside_its_target_and_never_on_it() -> void:
	var TP := load("res://scripts/ui/TutorialPanel.gd")
	var vp := Vector2(1280, 720)
	var size := Vector2(460, 120)
	for target in [Rect2(1220, 10, 44, 44), Rect2(520, 650, 240, 54), Rect2(80, 200, 150, 130), Rect2()]:
		var pos: Vector2 = TP.card_position(vp, size, target)
		var card := Rect2(pos, size)
		assert_bool(Rect2(Vector2.ZERO, vp).encloses(card)).is_true()
		if target.size != Vector2.ZERO:
			assert_bool(card.intersects(target)).is_false()
