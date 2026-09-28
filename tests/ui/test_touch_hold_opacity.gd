extends GdUnitTestSuite
## Controles en pantalla: mantener pulsado repite (bug 5), son semitransparentes
## (bug 7) y sus contenedores no se comen el dedo (bug 8).
##
## Zoom y giro disparaban una vez y al SOLTAR (Button.pressed). Ahora disparan al
## tocar y, mantenidos mas de GameConfig.hold_repeat_delay_sec, siguen solos. La
## opacidad sale de GameConfig.ui_touch_controls_opacity y un boton pulsado se ve
## entero. Toca settings.cfg: se devuelve byte a byte, como test_touch_controls.

const OSC := preload("res://scripts/ui/OnScreenControls.gd")

var _osc: CanvasLayer = null
var _zooms: Array = []
var _rots: Array = []
var _brots := 0
var _saved_opacity := 0.45
var _had_file := false
var _file_bytes := PackedByteArray()

func before_test() -> void:
	_saved_opacity = GameConfig.ui_touch_controls_opacity
	_had_file = FileAccess.file_exists(GameConfig.USER_SETTINGS_PATH)
	if _had_file:
		_file_bytes = FileAccess.get_file_as_bytes(GameConfig.USER_SETTINGS_PATH)
	_zooms = []
	_rots = []
	_brots = 0
	EventBus.camera_zoom_requested.connect(_on_zoom)
	EventBus.camera_rotate_step_requested.connect(_on_rot)
	EventBus.building_rotate_requested.connect(_on_brot)
	_osc = auto_free(OSC.new())
	add_child(_osc)
	# En headless el perfil es PC y los controles no se ven: aqui se fuerzan.
	_osc.visible = true

func after_test() -> void:
	EventBus.camera_zoom_requested.disconnect(_on_zoom)
	EventBus.camera_rotate_step_requested.disconnect(_on_rot)
	EventBus.building_rotate_requested.disconnect(_on_brot)
	GameConfig.ui_touch_controls_opacity = _saved_opacity
	if _had_file:
		var f := FileAccess.open(GameConfig.USER_SETTINGS_PATH, FileAccess.WRITE)
		f.store_buffer(_file_bytes)
		f.close()
	elif FileAccess.file_exists(GameConfig.USER_SETTINGS_PATH):
		DirAccess.remove_absolute(GameConfig.USER_SETTINGS_PATH)

func _on_zoom(a: float) -> void:
	_zooms.append(a)

func _on_rot(d: float) -> void:
	_rots.append(d)

func _on_brot() -> void:
	_brots += 1

func _btn(name: String) -> Button:
	return _osc.find_child(name, true, false) as Button

func _run(seconds: float) -> void:
	var dt := 1.0 / 60.0
	var t := 0.0
	while t < seconds:
		_osc._process(dt)
		t += dt

func _sum(a: Array) -> float:
	var s := 0.0
	for v in a:
		s += float(v)
	return s

# ── Mantener pulsado ──

func test_zoom_fires_on_touch_not_on_release() -> void:
	var plus := _btn("ZoomIn")
	assert_int(plus.action_mode).is_equal(BaseButton.ACTION_MODE_BUTTON_PRESS)
	plus.button_down.emit()
	assert_array(_zooms).has_size(1)
	plus.button_up.emit()
	assert_array(_zooms).has_size(1)

func test_holding_zoom_keeps_zooming() -> void:
	var plus := _btn("ZoomIn")
	plus.button_down.emit()
	_run(1.0)
	assert_int(_zooms.size()).is_greater(10)
	# Siempre hacia el mismo lado: acercar.
	for z in _zooms:
		assert_float(float(z)).is_less(0.0)
	var n := _zooms.size()
	plus.button_up.emit()
	_run(0.5)
	assert_array(_zooms).has_size(n)

func test_a_short_tap_is_a_single_step() -> void:
	var minus := _btn("ZoomOut")
	minus.button_down.emit()
	_run(GameConfig.hold_repeat_delay_sec * 0.5)
	minus.button_up.emit()
	_run(0.5)
	assert_array(_zooms).is_equal([1.0])

func test_holding_rotate_keeps_turning_after_the_first_step() -> void:
	var right := _btn("RotateRight")
	# Sin Camera3D la fila de giro se oculta (vista 2D); aqui se quiere ver.
	right.get_parent().visible = true
	right.button_down.emit()
	assert_array(_rots).is_equal([OSC.ROTATE_STEP_DEGREES])
	_run(1.3)
	right.button_up.emit()
	# 45 del toque + ~1 s de giro continuo.
	var expected := OSC.ROTATE_STEP_DEGREES + GameConfig.hold_rotate_degrees_per_sec * (1.3 - GameConfig.hold_repeat_delay_sec)
	assert_float(_sum(_rots)).is_equal_approx(expected, 5.0)

func test_holding_rotate_building_repeats_slowly() -> void:
	var rb: Button = _osc._rotate_building_btn
	rb.visible = true
	rb.button_down.emit()
	assert_int(_brots).is_equal(1)
	_run(GameConfig.hold_repeat_delay_sec + OSC.BUILDING_ROTATE_REPEAT_SEC * 2.0 + 0.01)
	rb.button_up.emit()
	# El toque, el primer repetido al pasar el retardo... y uno cada 0.45 s.
	assert_int(_brots).is_between(3, 4)

func test_every_action_button_reacts_on_press() -> void:
	for btn in _osc.get_buttons():
		if btn == _osc._cancel_placement_btn:
			continue
		assert_int((btn as Button).action_mode).is_equal(BaseButton.ACTION_MODE_BUTTON_PRESS)

# ── Opacidad ──

func test_buttons_start_at_the_configured_opacity() -> void:
	_osc.set_opacity(0.45)
	for btn in _osc.get_buttons():
		assert_float((btn as Button).modulate.a).is_equal_approx(0.45, 0.001)

func test_a_pressed_button_shows_in_full() -> void:
	_osc.set_opacity(0.45)
	_osc.release_fade_sec = 0.0
	var plus := _btn("ZoomIn")
	plus.button_down.emit()
	assert_float(plus.modulate.a).is_equal_approx(1.0, 0.01)
	# Los demas siguen transparentes.
	assert_float(_btn("ZoomOut").modulate.a).is_equal_approx(0.45, 0.01)
	plus.button_up.emit()
	assert_float(plus.modulate.a).is_equal_approx(0.45, 0.01)

func test_the_setting_reaches_the_controls_and_persists() -> void:
	GameConfig.set_touch_controls_opacity(0.3)
	for btn in _osc.get_buttons():
		assert_float((btn as Button).modulate.a).is_equal_approx(0.3, 0.001)
	var cf := ConfigFile.new()
	assert_int(cf.load(GameConfig.USER_SETTINGS_PATH)).is_equal(OK)
	assert_float(float(cf.get_value("ui", "touch_controls_opacity", -1.0))).is_equal_approx(0.3, 0.001)
	GameConfig.ui_touch_controls_opacity = 0.9
	GameConfig.load_user_settings()
	assert_float(GameConfig.ui_touch_controls_opacity).is_equal_approx(0.3, 0.001)

func test_the_opacity_is_clamped() -> void:
	GameConfig.set_touch_controls_opacity(0.0, false)
	assert_float(GameConfig.ui_touch_controls_opacity).is_equal(GameConfig.TOUCH_OPACITY_MIN)
	GameConfig.set_touch_controls_opacity(3.0, false)
	assert_float(GameConfig.ui_touch_controls_opacity).is_equal(GameConfig.TOUCH_OPACITY_MAX)

# ── Solo los botones paran el dedo (bug 8) ──

func test_only_buttons_stop_the_finger() -> void:
	_osc._set_placing(true)
	var offenders: Array = []
	for n in _all(_osc):
		if n is Control and not (n is BaseButton):
			if (n as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
				offenders.append(str(_osc.get_path_to(n)))
	assert_array(offenders).is_empty()

func _all(n: Node, out: Array = []) -> Array:
	out.append(n)
	for c in n.get_children():
		_all(c, out)
	return out
