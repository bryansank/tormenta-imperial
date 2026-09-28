extends GdUnitTestSuite
## Bug 1: "en Ajustes no me deja ajustar nada; todo esta pegado, sin accion".
## La intro del tutorial (capa 17, congelada por la pausa) quedaba encima de
## Ajustes, que UIManager dejaba en la capa 13, y se comia todos los toques.
##
## Aqui se abre Ajustes desde los tres sitios de donde sale (el menu principal,
## el menu de la partida y la partida sin menu), con una capa-trampa a pantalla
## completa en la capa 17 que hace de intro, y se pulsa DE VERDAD: eventos de
## raton empujados al viewport en el centro del deslizador y del interruptor.
## Si algo tapa Ajustes o Ajustes no procesa en pausa, el valor no cambia.
##
## Layout: el panel se construye y se deja maquetar con el arbol en marcha
## (con el arbol en pausa el runner de gdUnit se pararia); la pausa se pone
## justo antes de pulsar y se quita al terminar.

const SettingsParking := preload("res://tests/save/settings_parking.gd")

var _parked: Dictionary
var _audio := {}
var _nodes: Array = []

func before_test() -> void:
	get_tree().paused = false
	_parked = SettingsParking.park()
	_audio = {"master": GameConfig.audio_master_volume, "music": GameConfig.audio_music_volume,
		"sfx": GameConfig.audio_sfx_volume, "enabled": GameConfig.audio_music_enabled}
	TitleMenuScript().set_dismissed_for_tests(false)

func after_test() -> void:
	get_tree().paused = false
	for n in _nodes:
		if is_instance_valid(n):
			var s: Node = n.get_node_or_null("SettingsPanel")
			if s != null and s.is_open():
				s.set("_needs_rebuild", false)
				s.toggle()
			n.free()
	_nodes.clear()
	UIManager.reset()
	AudioManager.set_master_volume(_audio["master"])
	AudioManager.set_music_volume(_audio["music"])
	AudioManager.set_sfx_volume(_audio["sfx"])
	GameConfig.audio_music_enabled = _audio["enabled"]
	SettingsParking.restore(_parked)
	TitleMenuScript().set_dismissed_for_tests(true)

func TitleMenuScript() -> GDScript:
	return load("res://scripts/ui/TitleMenu.gd")

## Una "escena de juego" minima: los hermanos que se buscan entre si por
## nombre, y la trampa de la capa 17 que hacia de intro.
func _game() -> Node:
	var root := Node.new()
	root.name = "FakeMain"
	var settings: CanvasLayer = load("res://scenes/ui/SettingsPanel.tscn").instantiate()
	settings.name = "SettingsPanel"
	root.add_child(settings)
	var trap := CanvasLayer.new()
	trap.name = "IntroTrap"
	trap.layer = 17
	var wall := ColorRect.new()
	wall.color = Color(0, 0, 0, 0.01)
	wall.mouse_filter = Control.MOUSE_FILTER_STOP
	wall.set_anchors_preset(Control.PRESET_FULL_RECT)
	trap.add_child(wall)
	root.add_child(trap)
	var pause: CanvasLayer = load("res://scenes/ui/PauseMenu.tscn").instantiate()
	pause.name = "PauseMenu"
	root.add_child(pause)
	var title: CanvasLayer = load("res://scenes/ui/TitleMenu.tscn").instantiate()
	title.name = "TitleMenu"
	root.add_child(title)
	add_child(root)
	_nodes.append(root)
	return root

func _settings(root: Node) -> CanvasLayer:
	return root.get_node("SettingsPanel")

func _frames(n: int) -> void:
	var was: bool = get_tree().paused
	get_tree().paused = false
	for i in n:
		await get_tree().process_frame
	get_tree().paused = was

## Un clic de raton (pulsar y soltar) en `pos`, empujado al viewport.
func _click(pos: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = pos
		e.global_position = pos
		get_viewport().push_input(e, true)

func _center(c: Control) -> Vector2:
	return c.get_global_rect().get_center()

## La capa de Ajustes gana a toda otra CanvasLayer visible (menus incluidos).
func _settings_on_top(root: Node) -> bool:
	var s := _settings(root)
	for child in root.get_children():
		if child == s or not (child is CanvasLayer) or not (child as CanvasLayer).visible:
			continue
		if (child as CanvasLayer).layer >= s.layer:
			return false
	return true

## Pulsa el deslizador de volumen general cerca de su extremo izquierdo y el
## interruptor de la rejilla. Devuelve [volumen antes, despues, rejilla antes, despues].
func _poke(root: Node) -> Array:
	var s := _settings(root)
	var tabs: TabContainer = s.find_child("SettingsTabs", true, false)
	var out: Array = []
	tabs.current_tab = 0
	await _frames(3)
	var slider: HSlider = s.find_child("Slider_master", true, false)
	var before_v: float = GameConfig.audio_master_volume
	var r := slider.get_global_rect()
	_click(Vector2(r.position.x + r.size.x * 0.1, r.get_center().y))
	out.append(before_v)
	out.append(GameConfig.audio_master_volume)
	tabs.current_tab = 1
	await _frames(3)
	var grid: CheckButton = s.find_child("GridCheck", true, false)
	var before_g: bool = GameConfig.ui_grid_visible
	_click(_center(grid))
	out.append(before_g)
	out.append(GameConfig.ui_grid_visible)
	return out

func _assert_poked(values: Array, where: String) -> void:
	assert_bool(absf(float(values[1]) - float(values[0])) > 0.01) \
		.override_failure_message("%s: el volumen no cambio (%.2f)" % [where, values[1]]).is_true()
	assert_bool(values[3]).override_failure_message("%s: la rejilla no cambio" % where).is_not_equal(values[2])

func test_settings_respond_from_the_title_menu() -> void:
	GameConfig.audio_master_volume = 0.9
	GameConfig.ui_grid_visible = true
	var root := _game()
	await _frames(2)
	var title: CanvasLayer = root.get_node("TitleMenu")
	title.open_menu()
	title._on_settings()
	await _frames(4)
	get_tree().paused = true
	var on_top := _settings_on_top(root)
	var values: Array = await _poke(root)
	var mode: int = _settings(root).process_mode
	title.close_menu()
	get_tree().paused = false
	assert_bool(on_top).override_failure_message("Ajustes no esta por encima de la intro").is_true()
	assert_int(mode).is_equal(Node.PROCESS_MODE_ALWAYS)
	_assert_poked(values, "menu principal")

func test_settings_respond_from_the_game_menu() -> void:
	GameConfig.audio_master_volume = 0.9
	GameConfig.ui_grid_visible = true
	var root := _game()
	await _frames(2)
	var menu: CanvasLayer = root.get_node("PauseMenu")
	menu.menu_button().pressed.emit()
	var paused: bool = get_tree().paused
	menu.entry("Game_Settings").pressed.emit()
	await _frames(4)
	get_tree().paused = true
	var on_top := _settings_on_top(root)
	var values: Array = await _poke(root)
	menu.resume()
	get_tree().paused = false
	assert_bool(paused).is_true()
	assert_bool(on_top).override_failure_message("Ajustes no esta por encima del menu").is_true()
	_assert_poked(values, "menu de la partida")

func test_settings_respond_during_play() -> void:
	GameConfig.audio_master_volume = 0.9
	GameConfig.ui_grid_visible = true
	var root := _game()
	root.get_node("IntroTrap").visible = false   # partida normal, sin intro
	await _frames(2)
	_settings(root).toggle()
	await _frames(4)
	var values: Array = await _poke(root)
	_assert_poked(values, "en partida")

## Cerrar Ajustes devuelve su capa y su modo, y el menu vuelve a verse.
func test_closing_borrowed_settings_gives_everything_back() -> void:
	var root := _game()
	await _frames(2)
	var s := _settings(root)
	var menu: CanvasLayer = root.get_node("PauseMenu")
	menu.menu_button().pressed.emit()
	menu.entry("Game_Settings").pressed.emit()
	var borrowed_layer: int = s.layer
	s.toggle()
	var back_layer: int = s.layer
	var card_back: bool = menu.get("_root").visible
	menu.resume()
	assert_int(borrowed_layer).is_greater(menu.layer)
	assert_int(back_layer).is_less(menu.layer)
	assert_int(s.process_mode).is_equal(Node.PROCESS_MODE_INHERIT)
	assert_bool(card_back).is_true()

## Bug 7 (la parte de Ajustes): los controles en pantalla se transparentan
## desde Ajustes > Controles, y se nota al momento.
func test_touch_controls_opacity_slider_applies_at_once() -> void:
	var saved: float = GameConfig.ui_touch_controls_opacity
	var root := _game()
	var osc: CanvasLayer = load("res://scenes/ui/OnScreenControls.tscn").instantiate()
	root.add_child(osc)
	var slider: HSlider = _settings(root).find_child("Slider_touch_opacity", true, false)
	slider.value = 0.4
	var applied: float = osc.current_opacity()
	var stored: float = GameConfig.ui_touch_controls_opacity
	GameConfig.set_touch_controls_opacity(saved)
	assert_object(slider).is_not_null()
	assert_float(applied).is_equal_approx(0.4, 0.01)
	assert_float(stored).is_equal_approx(0.4, 0.01)
	# Nunca invisibles del todo: el minimo es TOUCH_OPACITY_MIN.
	assert_float(slider.min_value).is_equal_approx(GameConfig.TOUCH_OPACITY_MIN, 0.001)
