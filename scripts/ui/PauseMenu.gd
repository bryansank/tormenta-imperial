extends CanvasLayer
## El menu de pausa. ESC (o el boton de pausa, para quien juega con el dedo)
## cuando no hay ninguna ventana de UIManager abierta ni un edificio en la mano.
##
## La pausa es de verdad: `get_tree().paused`. Todo lo que no marque
## PROCESS_MODE_ALWAYS se para — produccion, consumo, la Tormenta, el
## entrenamiento, el turno enemigo del tablero — y este menu, que si lo marca,
## es lo unico que responde. La musica sigue porque AudioManager tambien lo marca.
##
##   Reanudar | Guardar | Ajustes | Historia | Menu principal | Salir
##
## Ajustes y la intro del tutorial son paneles de otros; mientras estan abiertos
## desde aqui se les deja procesar y se les devuelve su modo al cerrarse.

const LAYER := 30
const CARD_WIDTH := 340.0
## El boton de pausa. En pantalla ancha, pegado a la derecha del ancho REAL de
## la barra de recursos y a su altura (UILayoutManager.pause_button_position:
## con cuatro recursos y LIMPIAR la barra pasa de 300 px). En una estrecha
## (movil en vertical) arriba no queda sitio: va abajo al centro, justo encima
## del boton CONSTRUIR (ranura bottom_center) y entre los mandos de camara.
const PAUSE_BTN_SIZE := 44.0
const NARROW_WIDTH := 700.0
const PAUSE_BTN_BOTTOM_NARROW := 84.0

var _root: Control
var _backdrop: ColorRect
var _card: PanelContainer
var _status: Label
var _pause_btn: Button

var _open := false
var _paused_by_me := false
var _sub: CanvasLayer = null
var _sub_mode: int = Node.PROCESS_MODE_INHERIT

func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_ui()
	UIManager.window_closed.connect(_on_window_closed)
	EventBus.tutorial_intro_closed.connect(_on_intro_closed)
	get_viewport().size_changed.connect(_relayout)
	# Va a la derecha del ancho REAL de los recursos: cuando crecen (cuatro
	# recursos, LIMPIAR, letra grande) o se mueven, la pausa se aparta.
	UILayoutManager.panel_rect_changed.connect(func(id: String):
		if id == "ResourceHUD":
			_relayout.call_deferred())
	UILayoutManager.layout_changed.connect(_relayout)
	UILayoutManager.user_layout_changed.connect(_relayout.call_deferred)

# ── Construccion ─────────────────────────────────────────────────────

func _setup_ui() -> void:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	# Pausa tactil: siempre a la vista, junto a la barra de recursos.
	_pause_btn = Button.new()
	_pause_btn.text = "II"
	_pause_btn.tooltip_text = Tr.ti("BTN_PAUSE")
	_pause_btn.focus_mode = Control.FOCUS_NONE
	_pause_btn.custom_minimum_size = Vector2(PAUSE_BTN_SIZE, PAUSE_BTN_SIZE)
	UITheme.style_button(_pause_btn, UITheme.BTN, UITheme.FONT_SECTION)
	_pause_btn.pressed.connect(func(): if can_pause(): open_pause())
	overlay.add_child(_pause_btn)

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	add_child(_root)

	_backdrop = ModalKit.make_backdrop(0.62)
	_root.add_child(_backdrop)

	_card = ModalKit.make_card(10)
	_root.add_child(_card)
	var column: VBoxContainer = _card.get_child(0)

	column.add_child(ModalKit.make_text(Tr.t("LBL_PAUSE_TITLE"), "title", UITheme.ACCENT))
	column.add_child(ModalKit.make_text(Tr.t("LBL_PAUSE_SUBTITLE"), "small", UITheme.TEXT_DIM))
	column.add_child(UITheme.make_separator())
	column.add_child(ModalKit.make_menu_button(Tr.t("BTN_RESUME"), UITheme.POSITIVE, resume))
	column.add_child(ModalKit.make_menu_button(Tr.t("BTN_SAVE_GAME"), UITheme.BTN, save))
	column.add_child(ModalKit.make_menu_button(Tr.t("BTN_SETTINGS"), UITheme.BTN, _on_settings))
	column.add_child(ModalKit.make_menu_button(Tr.t("BTN_STORY"), UITheme.BTN, _on_story))
	column.add_child(ModalKit.make_menu_button(Tr.t("BTN_MAIN_MENU"), UITheme.BTN, _on_main_menu))
	column.add_child(ModalKit.make_menu_button(Tr.t("BTN_SAVE_QUIT"), UITheme.DANGER, _on_quit))

	_status = ModalKit.make_text("", "small", UITheme.POSITIVE)
	_status.visible = false
	column.add_child(_status)

	_relayout()

func _relayout() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if _card != null:
		ModalKit.fit_center(_card, CARD_WIDTH, vp)
	if _pause_btn != null:
		_place_pause_button(vp)

func _place_pause_button(vp: Vector2) -> void:
	if vp.x < NARROW_WIDTH:
		_pause_btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		_pause_btn.offset_left = -PAUSE_BTN_SIZE * 0.5
		_pause_btn.offset_right = PAUSE_BTN_SIZE * 0.5
		_pause_btn.offset_top = -(PAUSE_BTN_BOTTOM_NARROW + PAUSE_BTN_SIZE)
		_pause_btn.offset_bottom = -PAUSE_BTN_BOTTOM_NARROW
	else:
		_pause_btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
		var pos := UILayoutManager.pause_button_position()
		# Dentro de la pantalla aunque los recursos se hayan movido al borde.
		pos.x = clampf(pos.x, 0.0, maxf(0.0, vp.x - PAUSE_BTN_SIZE))
		pos.y = clampf(pos.y, 0.0, maxf(0.0, vp.y - PAUSE_BTN_SIZE))
		_pause_btn.offset_left = pos.x
		_pause_btn.offset_right = pos.x + PAUSE_BTN_SIZE
		_pause_btn.offset_top = pos.y
		_pause_btn.offset_bottom = pos.y + PAUSE_BTN_SIZE

## El boton de pausa, para pruebas.
func pause_button() -> Button:
	return _pause_btn

# ── Cuando se puede pausar ───────────────────────────────────────────

## ESC es de quien lo necesita antes que de la pausa: una ventana abierta se
## cierra (UIManager), un edificio en la mano se suelta (BuildingPlacer). Y con
## el menu principal encima, o el arbol ya en pausa por otro, no se apila nada.
func can_pause() -> bool:
	if _open:
		return false
	if get_tree().paused:
		return false
	if UIManager.is_any_window_open():
		return false
	var placer: Node = _find_sibling("BuildingPlacer")
	if placer != null and placer.has_method("is_idle") and not placer.is_idle():
		return false
	var title: Node = _find_sibling("TitleMenu")
	if title != null and title.has_method("is_open") and title.is_open():
		return false
	return true

func is_open() -> bool:
	return _open

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE):
		return
	if _open:
		# Con Ajustes encima, ESC cierra Ajustes (UIManager esta en pausa). Con la
		# intro encima no se toca: tiene su propio "Saltar".
		if _sub != null:
			if _sub.has_method("toggle"):
				_sub.toggle()
		else:
			resume()
		get_viewport().set_input_as_handled()
		return
	if can_pause():
		open_pause()
		get_viewport().set_input_as_handled()

# ── Abrir / cerrar ───────────────────────────────────────────────────

func open_pause() -> void:
	_open = true
	_status.visible = false
	_relayout()
	_root.visible = true
	_pause_btn.visible = false
	if not get_tree().paused:
		get_tree().paused = true
		_paused_by_me = true
	var first: Control = (_card.get_child(0) as VBoxContainer).get_child(3)
	if first is Button:
		(first as Button).grab_focus.call_deferred()

func resume() -> void:
	_close_sub()
	_open = false
	_root.visible = false
	_pause_btn.visible = true
	if _paused_by_me:
		_paused_by_me = false
		get_tree().paused = false

func _exit_tree() -> void:
	if _paused_by_me and get_tree() != null:
		get_tree().paused = false

# ── Botones ──────────────────────────────────────────────────────────

## Guarda y lo dice aqui mismo: los avisos de la esquina van por debajo de este
## menu y, con el juego parado, no se desvanecerian.
func save() -> void:
	_save_now()
	_status.text = Tr.t("MSG_GAME_SAVED")
	_status.visible = true
	EventBus.notification_posted.emit(Tr.t("MSG_GAME_SAVED"), "success", UITheme.POSITIVE)

## Guarda si hay partida en marcha. Sin escena de juego (pruebas) no hay nada.
func _save_now() -> void:
	if GameManager.is_started():
		GameManager.save_game()

func _on_settings() -> void:
	var settings: Node = _find_sibling("SettingsPanel")
	if settings == null or not settings.has_method("toggle"):
		return
	_open_sub(settings)
	settings.toggle()

## Vuelve a contar el lore. La intro es modal y vive en TutorialPanel; se abre
## con el juego todavia en pausa y, al cerrarla, se vuelve a este menu.
func _on_story() -> void:
	var tutorial: Node = _find_sibling("TutorialPanel")
	if tutorial != null:
		_open_sub(tutorial)
	TutorialManager.show_intro()

## Guarda y cede el sitio al menu principal. La pausa cambia de manos en la misma
## llamada: se suelta aqui y el menu principal la vuelve a tomar como suya, para
## que su "Continuar" sepa que tiene que soltarla.
func _on_main_menu() -> void:
	var title: Node = _find_sibling("TitleMenu")
	if title == null or not title.has_method("open_menu"):
		return
	_save_now()
	resume()
	title.open_menu()

func _on_quit() -> void:
	_save_now()
	get_tree().quit()

# ── Pantallas prestadas ──────────────────────────────────────────────

func _open_sub(panel: Node) -> void:
	_sub = panel
	_sub_mode = panel.process_mode
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_root.visible = false

func _close_sub() -> void:
	if _sub != null and is_instance_valid(_sub):
		_sub.process_mode = _sub_mode
	_sub = null
	if _open:
		_root.visible = true

func _on_window_closed(window: CanvasLayer) -> void:
	# La intro se cierra por tutorial_intro_closed; aqui solo Ajustes.
	if _sub != null and window == _sub and String(_sub.name) != "TutorialPanel":
		_close_sub()

func _on_intro_closed() -> void:
	if _sub != null and String(_sub.name) == "TutorialPanel":
		_close_sub()

func _find_sibling(node_name: String) -> Node:
	var parent: Node = get_parent()
	if parent != null:
		var sibling: Node = parent.get_node_or_null(node_name)
		if sibling != null:
			return sibling
	return null
