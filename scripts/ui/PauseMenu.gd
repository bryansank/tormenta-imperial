extends CanvasLayer
## El MENU de la partida: uno solo (bug 9). Antes habia dos que competian, la
## pausa II arriba a la izquierda y el ☰ desplegable arriba a la derecha, con
## Ajustes en los dos y "Menu principal" solo en uno. Ahora hay un boton
## "☰ MENU" en la esquina superior derecha que abre una tarjeta con dos grupos:
##
##   COLONIA  Que hacer · Progreso · Mercado · Tecnologia · Ejercito ·
##            Escaramuzas · Sandbox        (solo lo que ya esta disponible)
##   PARTIDA  Reanudar · Guardar · Ajustes · Musica · Ayuda · Historia ·
##            Menu principal · Guardar y salir
##
## - Con el menu abierto la partida esta en pausa de verdad (`get_tree().paused`).
##   Todo lo que no marque PROCESS_MODE_ALWAYS se para; este menu y la musica no.
## - Elegir algo de COLONIA cierra el menu, quita la pausa y abre ese panel.
## - Lo de PARTIDA que es una pantalla (Ajustes, Ayuda, Historia) se abre con la
##   pausa puesta y, al cerrarla, se vuelve aqui. Esa pantalla prestada se pone
##   POR ENCIMA de todo mientras dura (bug 1: la intro, en la capa 17, tapaba
##   Ajustes, que UIManager dejaba en la 13, y se comia los toques).
## - El boton SIEMPRE abre el menu (bug 3): si hay ventanas abiertas las cierra,
##   si hay un edificio en la mano lo suelta, y luego abre. Antes no hacia nada.
## - ESC y el boton atras de Android (quit_on_go_back=false en project.godot)
##   son lo mismo: cierran la ventana de arriba, sueltan el edificio o, si no
##   hay nada de eso, abren o cierran este menu.
##
## El nombre del nodo sigue siendo PauseMenu (escenas, TitleMenu, LayoutEditor
## y los tests lo buscan asi).

const LAYER := 30
## Tarjeta: dos columnas en apaisado, una (con scroll) en pantalla estrecha.
const CARD_WIDTH_WIDE := 640.0
const CARD_WIDTH_NARROW := 360.0
const TWO_COLUMNS_MIN_WIDTH := 700.0
## Alto que se deja fuera del scroll: titulo, modo, margenes.
const CHROME_H := 150.0
## El boton del menu: esquina superior derecha, con palabra y no solo icono.
const MENU_BTN_MARGIN := 10.0
const MENU_BTN_MIN_W := 118.0

## Entradas de COLONIA: [id, clave Tr, nodo hermano].
const COLONY_ENTRIES := [
	["objectives", "BTN_OBJECTIVES", "ObjectivePanel"],
	["progress", "BTN_PROGRESS", "ProgressPanel"],
	["market", "BTN_MARKET", "MarketPanel"],
	["tech", "BTN_TECH", "TechTreePanel"],
	["army", "BTN_ARMY", "ArmyPanel"],
	["skirmish", "BTN_SKIRMISH", "SkirmishPanel"],
	["sandbox", "BTN_SANDBOX", "SandboxPanel"],
]

var _root: Control
var _backdrop: ColorRect
var _card: PanelContainer
var _scroll: ScrollContainer
var _groups: GridContainer
var _status: Label
## El modo de la partida, bajo el titulo. Se rellena al abrir: al construirse el
## menu la partida aun no ha cargado.
var _mode_label: Label
var _menu_btn: Button
var _colony_buttons: Dictionary = {}   # id -> Button
var _music_btn: Button
var _help_btn: Button
var _resume_btn: Button

var _open := false
var _paused_by_me := false
## Pantalla prestada abierta encima (Ajustes, Ayuda, la intro) y lo suyo que se
## le cambia mientras tanto: process_mode y capa.
var _sub: CanvasLayer = null
var _sub_mode: int = Node.PROCESS_MODE_INHERIT
var _sub_layer: int = 1

func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("game_menu")
	_setup_ui()
	UIManager.window_closed.connect(_on_window_closed)
	UIManager.window_opened.connect(func(_w): _pin_sub_layer())
	EventBus.tutorial_intro_closed.connect(_on_intro_closed)
	EventBus.music_toggled.connect(func(_on): _sync_music())
	get_viewport().size_changed.connect(_relayout)

# ── Construccion ─────────────────────────────────────────────────────

func _setup_ui() -> void:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	# El unico boton de menu: siempre a la vista, arriba a la derecha.
	_menu_btn = Button.new()
	_menu_btn.name = "MenuButton"
	_menu_btn.text = Tr.t("BTN_GAME_MENU")
	_menu_btn.tooltip_text = Tr.ti("BTN_GAME_MENU_HINT")
	_menu_btn.focus_mode = Control.FOCUS_NONE
	UITheme.style_button(_menu_btn, UITheme.BTN, UITheme.FONT_SECTION)
	_menu_btn.custom_minimum_size = Vector2(MENU_BTN_MIN_W, UITheme.MIN_BTN_H)
	_menu_btn.pressed.connect(request_open)
	overlay.add_child(_menu_btn)

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	add_child(_root)

	_backdrop = ModalKit.make_backdrop(0.62)
	# Tocar fuera de la tarjeta es "Reanudar", como en cualquier menu de movil.
	_backdrop.gui_input.connect(func(e: InputEvent):
		if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
			resume())
	_root.add_child(_backdrop)

	_card = ModalKit.make_card(8)
	_card.name = "MenuCard"
	_root.add_child(_card)
	var column: VBoxContainer = _card.get_child(0)

	var title_row := HBoxContainer.new()
	column.add_child(title_row)
	var title := UITheme.make_label(Tr.t("LBL_GAME_MENU_TITLE"), "title", UITheme.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var close := Button.new()
	close.name = "CloseMenu"
	close.text = "✕"
	close.tooltip_text = Tr.t("BTN_RESUME")
	close.focus_mode = Control.FOCUS_NONE
	UITheme.style_button(close, UITheme.BTN, UITheme.FONT_SECTION)
	close.custom_minimum_size = Vector2(UITheme.MIN_BTN_H, UITheme.MIN_BTN_H)
	close.pressed.connect(resume)
	title_row.add_child(close)

	_mode_label = UITheme.make_label("", "small", UITheme.ACCENT)
	_mode_label.name = "ModeLabel"
	column.add_child(_mode_label)
	column.add_child(UITheme.make_separator())

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	# Aire a los lados: el recorte del scroll se comia el borde de los botones
	# y, a la derecha, deja sitio a la barra de desplazamiento en el movil.
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_left", 6)
	pad.add_theme_constant_override("margin_right", 10)
	pad.add_theme_constant_override("margin_bottom", 4)
	_scroll.add_child(pad)
	_groups = GridContainer.new()
	_groups.columns = 2
	_groups.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_groups.add_theme_constant_override("h_separation", 16)
	_groups.add_theme_constant_override("v_separation", 12)
	pad.add_child(_groups)

	# ── COLONIA ──
	var colony := _make_group("ColonyGroup", Tr.t("LBL_MENU_GROUP_COLONY"), Tr.t("LBL_MENU_GROUP_COLONY_HINT"))
	for entry in COLONY_ENTRIES:
		var id: String = entry[0]
		var sibling: String = entry[2]
		var btn := ModalKit.make_menu_button(Tr.t(entry[1]), UITheme.BTN, func(): open_colony_panel(sibling))
		btn.name = "Colony_" + id
		colony.add_child(btn)
		_colony_buttons[id] = btn

	# ── PARTIDA ──
	var game := _make_group("GameGroup", Tr.t("LBL_MENU_GROUP_GAME"), Tr.t("LBL_PAUSE_SUBTITLE"))
	_resume_btn = _add_game_button(game, "Resume", Tr.t("BTN_RESUME"), UITheme.POSITIVE, resume)
	_add_game_button(game, "Save", Tr.t("BTN_SAVE_GAME"), UITheme.BTN, save)
	_add_game_button(game, "Settings", Tr.t("BTN_SETTINGS"), UITheme.BTN, _on_settings)
	_music_btn = _add_game_button(game, "Music", "", UITheme.BTN, AudioManager.toggle_music)
	_help_btn = _add_game_button(game, "Help", Tr.t("BTN_HELP"), UITheme.INFO, _on_help)
	_add_game_button(game, "Story", Tr.t("BTN_STORY"), UITheme.BTN, _on_story)
	_add_game_button(game, "MainMenu", Tr.t("BTN_MAIN_MENU"), UITheme.BTN, _on_main_menu)
	_add_game_button(game, "Quit", Tr.t("BTN_SAVE_QUIT"), UITheme.DANGER, _on_quit)

	_status = ModalKit.make_text("", "small", UITheme.POSITIVE)
	_status.visible = false
	column.add_child(_status)

	_sync_music()
	_relayout()

func _make_group(node_name: String, title: String, hint: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = node_name
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	box.add_theme_constant_override("separation", 6)
	box.add_child(UITheme.section_header(title))
	var sub := UITheme.make_label(hint, "small", UITheme.TEXT_DIM)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(sub)
	_groups.add_child(box)
	return box

func _add_game_button(group: VBoxContainer, id: String, text: String, color: Color, cb: Callable) -> Button:
	var btn := ModalKit.make_menu_button(text, color, cb)
	btn.name = "Game_" + id
	group.add_child(btn)
	return btn

func _relayout() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var wide: bool = vp.x >= TWO_COLUMNS_MIN_WIDTH
	if _groups != null:
		_groups.columns = 2 if wide else 1
	if _card != null:
		ModalKit.fit_center(_card, CARD_WIDTH_WIDE if wide else CARD_WIDTH_NARROW, vp)
		_fit_scroll(vp)
	if _menu_btn != null:
		_place_menu_button()

## Alto del scroll: lo que piden los grupos, sin pasar de la pantalla. En una
## tablet apaisada caben enteros; en un movil en vertical se desplaza.
func _fit_scroll(vp: Vector2) -> void:
	if _scroll == null or _groups == null:
		return
	var wanted: float = _groups.get_combined_minimum_size().y
	_scroll.custom_minimum_size.y = clampf(wanted, 120.0, maxf(120.0, vp.y - CHROME_H))

func _place_menu_button() -> void:
	_menu_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	var w: float = maxf(MENU_BTN_MIN_W, _menu_btn.get_combined_minimum_size().x)
	var h: float = maxf(UITheme.MIN_BTN_H, _menu_btn.get_combined_minimum_size().y)
	_menu_btn.offset_right = -MENU_BTN_MARGIN
	_menu_btn.offset_left = -MENU_BTN_MARGIN - w
	_menu_btn.offset_top = MENU_BTN_MARGIN
	_menu_btn.offset_bottom = MENU_BTN_MARGIN + h

## El boton del menu, para pruebas (antes el II; se conserva el nombre).
func pause_button() -> Button:
	return _menu_btn

func menu_button() -> Button:
	return _menu_btn

## Una entrada del menu por su nombre de nodo (Colony_market, Game_MainMenu...).
func entry(node_name: String) -> Button:
	return _card.find_child(node_name, true, false) as Button

# ── Cuando se puede abrir ────────────────────────────────────────────

## Solo para ESC: ESC es antes de quien lo necesita (una ventana abierta se
## cierra en UIManager, un edificio en la mano se suelta en BuildingPlacer). Y
## con el menu principal encima, o el arbol ya en pausa por otro, no se apila.
## El BOTON no pasa por aqui: siempre abre (request_open).
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
	if _title_open():
		return false
	return true

func is_open() -> bool:
	return _open

## El boton ☰: nunca falla en silencio. Suelta el edificio en la mano y cierra
## las ventanas abiertas (el mismo camino que ESC), y abre. Con el menu
## principal encima no hay partida a la que poner menu: no hace nada (el boton
## ni se ve, esta tapado).
func request_open() -> void:
	if _open:
		resume()
		return
	if _title_open():
		return
	var placer: Node = _find_sibling("BuildingPlacer")
	if placer != null and placer.has_method("is_idle") and not placer.is_idle():
		EventBus.building_placement_cancelled.emit()
	UIManager.close_all_windows()
	open_pause()

func _title_open() -> bool:
	var title: Node = _find_sibling("TitleMenu")
	return title != null and title.has_method("is_open") and title.is_open()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE):
		return
	if _open:
		# Con una pantalla prestada encima, ESC la cierra (UIManager esta en
		# pausa y no lo haria). Con la intro encima no se toca: tiene "Saltar".
		if _sub != null:
			_close_borrowed()
		else:
			resume()
		get_viewport().set_input_as_handled()
		return
	if can_pause():
		open_pause()
		get_viewport().set_input_as_handled()

## El boton atras de Android es ESC: cierra la ventana de arriba, suelta el
## edificio, cierra Ajustes en el menu principal o abre/cierra este menu. Con
## quit_on_go_back=false el motor ya no cierra la aplicacion por su cuenta.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		go_back()

func go_back() -> void:
	for pressed in [true, false]:
		var esc := InputEventKey.new()
		esc.keycode = KEY_ESCAPE
		esc.physical_keycode = KEY_ESCAPE
		esc.pressed = pressed
		Input.parse_input_event(esc)

# ── Abrir / cerrar ───────────────────────────────────────────────────

func open_pause() -> void:
	_open = true
	_status.visible = false
	_mode_label.text = Tr.t("LBL_MODE_CURRENT") % GameMode.display_name()
	_refresh_entries()
	_relayout()
	_root.visible = true
	_menu_btn.visible = false
	if not get_tree().paused:
		get_tree().paused = true
		_paused_by_me = true
	_resume_btn.grab_focus.call_deferred()

func open_menu() -> void:
	request_open()

func resume() -> void:
	_close_sub()
	_open = false
	_root.visible = false
	_menu_btn.visible = true
	if _paused_by_me:
		_paused_by_me = false
		get_tree().paused = false

func _exit_tree() -> void:
	if _paused_by_me and get_tree() != null:
		get_tree().paused = false

## Lo que ya esta disponible, y nada mas (antes la columna ☰ dejaba huecos):
## Mercado desde la fase de economia, Ejercito y Escaramuzas con un Cuartel,
## Sandbox en su modo, Ayuda si el panel existe.
func _refresh_entries() -> void:
	for entry_def in COLONY_ENTRIES:
		var id: String = entry_def[0]
		var btn: Button = _colony_buttons[id]
		btn.visible = _find_sibling(entry_def[2]) != null and is_colony_entry_available(id)
	_help_btn.visible = _help_panel() != null
	_sync_music()
	if _groups != null:
		_fit_scroll.call_deferred(get_viewport().get_visible_rect().size)

static func is_colony_entry_available(id: String) -> bool:
	match id:
		"market":
			return ProgressionManager.current_phase >= GameConfig.Phase.ECONOMY
		"army", "skirmish":
			return ArmyManager.barracks_count() > 0
		"sandbox":
			return GameMode.sandbox_tools()
	return true

func _sync_music() -> void:
	if _music_btn != null:
		_music_btn.text = Tr.t("BTN_MUSIC_ON") if AudioManager.is_music_enabled() else Tr.t("BTN_MUSIC_OFF")

# ── COLONIA ──────────────────────────────────────────────────────────

## Cierra el menu, quita la pausa y abre ese panel (si ya estaba abierto, lo
## deja abierto: nunca lo cierra).
func open_colony_panel(sibling: String) -> void:
	var panel: Node = _find_sibling(sibling)
	resume()
	if panel == null:
		return
	if panel.has_method("is_open") and panel.is_open():
		return
	if panel.get("_is_open") == true:
		return
	if panel.has_method("open"):
		panel.open()
	elif panel.has_method("toggle"):
		panel.toggle()
	elif panel.has_method("_toggle_panel"):
		panel._toggle_panel()

# ── PARTIDA ──────────────────────────────────────────────────────────

## Guarda y lo dice aqui mismo: los avisos de la esquina van por debajo de este
## menu y, con el juego parado, no se desvanecerian.
##
## Y dice la verdad: este menu puede abrirse encima del tablero, y con una pelea
## abierta GameManager no escribe, deja el guardado pendiente hasta que termine.
## Entonces no se dice "guardada", se dice cuando se guardara.
func save() -> void:
	_save_now()
	var deferred: bool = GameManager.is_started() and GameManager.has_pending_save()
	var key := "MSG_SAVE_AFTER_FIGHT" if deferred else "MSG_GAME_SAVED"
	var color: Color = UITheme.WARNING if deferred else UITheme.POSITIVE
	_status.text = Tr.t(key)
	_status.add_theme_color_override("font_color", color)
	_status.visible = true
	EventBus.notification_posted.emit(Tr.t(key), "warning" if deferred else "success", color)

## Guarda si hay partida en marcha. Sin escena de juego (pruebas) no hay nada.
func _save_now() -> void:
	if GameManager.is_started():
		GameManager.save_game()

func _on_settings() -> void:
	var settings: Node = _find_sibling("SettingsPanel")
	if settings == null or not settings.has_method("toggle"):
		return
	_open_sub(settings)
	if not (settings.has_method("is_open") and settings.is_open()):
		settings.toggle()

## AYUDA: el indice de ayuda (grupo "help_index", del frente de ayudas). Si no
## existe, la entrada ni sale (_refresh_entries).
func _on_help() -> void:
	var help: Node = _help_panel()
	if help == null:
		return
	if help is CanvasLayer:
		_open_sub(help)
	help.open()

func _help_panel() -> Node:
	if not is_inside_tree():
		return null
	var p: Node = get_tree().get_first_node_in_group("help_index")
	if p != null and p.has_method("open"):
		return p
	return null

## Vuelve a contar el lore. La intro es modal y vive en TutorialPanel; se abre
## con el juego todavia en pausa y, al cerrarla, se vuelve a este menu.
func _on_story() -> void:
	var tutorial: Node = _find_sibling("TutorialPanel")
	if tutorial != null:
		_open_sub(tutorial)
	TutorialManager.show_intro()

## Guarda y cede el sitio al menu principal. La pausa cambia de manos en la misma
## llamada: se suelta aqui y el menu principal la vuelve a tomar como suya, para
## que su "Continuar" sepa que tiene que soltarla. Funciona abra lo que abra el
## jugador antes: se cierran ventanas y se suelta el edificio.
func _on_main_menu() -> void:
	var title: Node = _find_sibling("TitleMenu")
	if title == null or not title.has_method("open_menu"):
		return
	_save_now()
	resume()
	var placer: Node = _find_sibling("BuildingPlacer")
	if placer != null and placer.has_method("is_idle") and not placer.is_idle():
		EventBus.building_placement_cancelled.emit()
	UIManager.close_all_windows()
	title.open_menu()

func _on_quit() -> void:
	_save_now()
	get_tree().quit()

# ── Pantallas prestadas ──────────────────────────────────────────────

## La pantalla prestada procesa con el arbol en pausa y se pone por encima de
## este menu (y de todo lo demas) hasta que se cierra. UIManager reordena las
## capas de su pila cada vez que se abre o cierra algo: la capa se vuelve a
## fijar entonces y en cada frame mientras dure.
func _open_sub(panel: Node) -> void:
	if _sub != null and _sub != panel:
		_close_sub()
	_sub = panel as CanvasLayer
	_sub_mode = panel.process_mode
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	if _sub != null:
		_sub_layer = _sub.layer
	_pin_sub_layer()
	_root.visible = false

func _pin_sub_layer() -> void:
	if _sub != null and is_instance_valid(_sub):
		_sub.layer = LAYER + 1

func _process(_delta: float) -> void:
	if _sub == null:
		return
	if not is_instance_valid(_sub):
		_sub = null
		if _open:
			_root.visible = true
		return
	_pin_sub_layer()
	# Un panel que se cierra por su cuenta sin pasar por UIManager (el indice
	# de ayuda, por ejemplo) tambien devuelve el menu.
	if _sub.has_method("is_open") and not _sub.is_open() and String(_sub.name) != "TutorialPanel":
		_close_sub()

## Pantalla prestada abierta, para pruebas.
func borrowed() -> CanvasLayer:
	return _sub

func _close_borrowed() -> void:
	if _sub == null:
		return
	if String(_sub.name) == "TutorialPanel":
		return
	if _sub.has_method("is_open") and _sub.is_open():
		if _sub.has_method("toggle"):
			_sub.toggle()
		elif _sub.has_method("close"):
			_sub.close()
	_close_sub()

func _close_sub() -> void:
	if _sub != null and is_instance_valid(_sub):
		_sub.process_mode = _sub_mode
		_sub.layer = _sub_layer
	_sub = null
	if _open:
		_root.visible = true

func _on_window_closed(window: CanvasLayer) -> void:
	# La intro se cierra por tutorial_intro_closed; aqui el resto.
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
