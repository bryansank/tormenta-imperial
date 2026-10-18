extends GdUnitTestSuite
## Avisos (Bryan, 2026-10-18: "las alertas se sobreponen a todo, se ve feo"):
## un solo sitio (la columna izquierda, slot toast_area), como mucho 2 a la vez
## (1 en telefono), el resto en cola, repetidos agrupados ("×3"), icono + una
## frase + ✕, y con una ventana abierta solo un peligro pequeno. AlertQueue es
## la regla pura; NotificationPanel la pinta.

const AlertQueue := preload("res://scripts/ui/AlertQueue.gd")

var _profile_saved := ""
var _vp_saved := Vector2.ZERO

func before_test() -> void:
	CombatManager.reset()
	_profile_saved = GameConfig.ui_device_profile
	_vp_saved = UILayoutManager._viewport_size

func after_test() -> void:
	CombatManager.end_encounter()
	CombatManager.reset()
	GameConfig.ui_device_profile = _profile_saved
	DeviceProfile.apply_all()
	UILayoutManager._viewport_size = _vp_saved
	for w in UIManager.open_windows():
		UIManager.close_window(w)

# ── La regla pura ─────────────────────────────────────────────────────

func test_repeated_notices_group_into_one() -> void:
	var q := AlertQueue.new()
	for i in 3:
		q.post("Almacén lleno", "warning", Color.YELLOW)
	q.arrange(2, false)
	assert_int(q.shown.size()).is_equal(1)
	assert_int(int(q.shown[0]["count"])).is_equal(3)

func test_at_most_cap_on_screen_and_the_rest_wait_in_order() -> void:
	var q := AlertQueue.new()
	for t in ["uno", "dos", "tres"]:
		q.post(t, "warning", Color.YELLOW)
	q.arrange(2, false)
	assert_array(q.shown.map(func(e): return e["text"])).is_equal(["uno", "dos"])
	assert_int(q.waiting.size()).is_equal(1)
	# Se va uno (tiempo) y entra el siguiente.
	assert_bool(q.tick(AlertQueue.DURATION + 0.1)).is_true()
	q.arrange(2, false)
	assert_array(q.shown.map(func(e): return e["text"])).contains(["tres"])

func test_a_danger_jumps_ahead_of_a_plain_notice() -> void:
	var q := AlertQueue.new()
	q.post("Almacén lleno", "warning", Color.YELLOW)
	q.arrange(1, false)
	q.post("¡Ceniza!", "danger", Color.RED)
	q.arrange(1, false)
	assert_str(String(q.shown[0]["text"])).is_equal("¡Ceniza!")
	# El otro no se pierde: espera con su cuenta.
	assert_str(String(q.waiting[0]["text"])).is_equal("Almacén lleno")

func test_with_a_window_open_only_one_danger_shows() -> void:
	var q := AlertQueue.new()
	q.post("Sin madera", "warning", Color.YELLOW)
	q.post("Logro", "achievement", Color.WHITE)
	q.post("¡Ceniza!", "danger", Color.RED)
	q.post("¡Fuego!", "danger", Color.RED)
	q.arrange(2, true)
	assert_int(q.shown.size()).is_equal(1)
	assert_str(String(q.shown[0]["category"])).is_equal("danger")
	# Al cerrar la ventana vuelven los que esperaban.
	q.arrange(2, false)
	assert_int(q.shown.size()).is_equal(2)

func test_the_queue_does_not_grow_without_end() -> void:
	var q := AlertQueue.new()
	for i in 12:
		q.post("aviso %d" % i, "warning", Color.YELLOW)
	assert_int(q.waiting.size()).is_less_equal(AlertQueue.MAX_WAITING)
	assert_int(q.waiting_count()).is_equal(12)
	assert_bool(q.waiting.any(func(e): return bool(e["summary"]))).is_true()

func test_dismiss_removes_it_at_once() -> void:
	var q := AlertQueue.new()
	q.post("uno", "warning", Color.YELLOW)
	q.arrange(2, false)
	q.dismiss(String(q.shown[0]["key"]))
	assert_int(q.shown.size()).is_equal(0)

# ── El panel ──────────────────────────────────────────────────────────

func _notifications() -> CanvasLayer:
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/NotificationPanel.tscn").instantiate())
	add_child(panel)
	return panel

func test_a_toast_is_an_icon_a_sentence_a_count_and_a_close_button() -> void:
	var panel := _notifications()
	await await_idle_frame()
	for i in 3:
		EventBus.notification_posted.emit("Almacén lleno: se perdieron 40. Construye otro Almacén.", "warning", UITheme.WARNING)
	var toasts: Array = panel.shown_toasts()
	assert_int(toasts.size()).is_equal(1)
	var toast: Control = toasts[0]
	assert_object(toast.find_child("Icon", true, false)).is_not_null()
	assert_str((toast.find_child("Text", true, false) as Label).text).is_equal("Almacén lleno: se perdieron 40.")
	assert_str((toast.find_child("Count", true, false) as Label).text).is_equal("×3")
	# El texto entero, en la ayuda emergente y en el registro.
	assert_str(toast.tooltip_text).contains("Construye otro")
	var close := toast.find_child("Close", true, false) as Button
	close.pressed.emit()
	assert_int(panel.shown_toasts().size()).is_equal(0)

func test_two_at_most_on_pc_and_one_on_a_phone() -> void:
	GameConfig.ui_device_profile = "pc"
	DeviceProfile.apply_all()
	UILayoutManager._viewport_size = Vector2(1280, 720)
	var panel := _notifications()
	await await_idle_frame()
	for t in ["Sin madera", "Sin oro", "Moral baja", "Hambre"]:
		EventBus.notification_posted.emit(t, "warning", UITheme.WARNING)
	assert_int(panel.shown_toasts().size()).is_equal(2)
	assert_int(panel.held_count()).is_equal(2)
	GameConfig.ui_device_profile = "phone"
	DeviceProfile.apply_all()
	EventBus.notification_posted.emit("Otro", "warning", UITheme.WARNING)
	assert_int(panel.shown_toasts().size()).is_equal(1)

func test_an_open_window_holds_the_notices_back() -> void:
	var panel := _notifications()
	await await_idle_frame()
	var window: CanvasLayer = auto_free(CanvasLayer.new())
	add_child(window)
	UIManager.open_window(window)
	EventBus.notification_posted.emit("Sin madera", "warning", UITheme.WARNING)
	assert_int(panel.shown_toasts().size()).is_equal(0)
	EventBus.notification_posted.emit("¡Ceniza!", "danger", UITheme.DANGER)
	assert_int(panel.shown_toasts().size()).is_equal(1)
	UIManager.close_window(window)
	await await_idle_frame()
	assert_int(panel.shown_toasts().size()).is_greater_equal(1)
	assert_int(panel.held_count()).is_equal(0 if panel.capacity() >= 2 else 1)

func test_a_card_over_the_column_holds_them_back() -> void:
	var panel := _notifications()
	await await_idle_frame()
	var layer: CanvasLayer = auto_free(CanvasLayer.new())
	add_child(layer)
	var card := Panel.new()
	card.add_to_group("alert_blocker")
	layer.add_child(card)
	card.global_position = panel.column_rect().position
	card.size = Vector2(200, 100)
	EventBus.notification_posted.emit("Sin madera", "warning", UITheme.WARNING)
	assert_int(panel.shown_toasts().size()).is_equal(0)
	card.visible = false
	panel._pump()
	assert_int(panel.shown_toasts().size()).is_equal(1)

func test_the_column_lives_under_the_resources_not_over_build() -> void:
	var slot: Dictionary = UILayoutConfig.SLOTS["toast_area"]
	# Tras el registro (oculto casi siempre: le cede su sitio bajo los recursos,
	# o bajo la Tormenta cuando esta baja a la izquierda).
	assert_str(String(slot.get("stack_after", ""))).is_equal("NotificationPanel.log")
	var anchor: Rect2 = slot["anchor"]
	assert_float(anchor.position.y).is_equal(0.0)
	assert_float(anchor.position.x).is_equal(0.0)
	assert_bool(UILayoutConfig.COLUMN_NARROW_SLOTS.has("toast_area")).is_false()
	# Y el globo de los recursos, bajo los avisos.
	assert_str(String(UILayoutConfig.SLOTS["tip_left"]["stack_after"])).is_equal("NotificationPanel.toasts")

func test_headline_keeps_one_sentence() -> void:
	var NP := load("res://scripts/ui/NotificationPanel.gd")
	assert_str(NP.headline("¡La ceniza llega en 30 s! Guarda la madera.")).is_equal("¡La ceniza llega en 30 s!")
	assert_str(NP.headline("Sin madera")).is_equal("Sin madera")
	assert_str(NP.headline("Ok. Corto")).is_equal("Ok. Corto")

func test_the_summary_goes_last() -> void:
	var q := AlertQueue.new()
	for i in 8:
		q.post("aviso %d" % i, "warning", Color.YELLOW)
	q.arrange(1, false)
	assert_bool(bool(q.shown[0]["summary"])).is_false()
	# Hasta que no quede otra cosa, el resumen no sale.
	while q.waiting.size() > 1:
		q.tick(AlertQueue.DURATION + 0.1)
		q.arrange(1, false)
		assert_bool(bool(q.shown[0]["summary"])).is_false()
