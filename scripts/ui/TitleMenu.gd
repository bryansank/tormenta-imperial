extends CanvasLayer
## El menu principal. Sale al arrancar, encima de la partida ya cargada y con el
## arbol en pausa: la isla se ve detras, quieta, y nada corre hasta que el
## jugador elige.
##
##   Continuar      la ultima partida jugada (la activa, ya cargada detras),
##                  solo si hay algo que continuar (se cargo una partida, o ya
##                  se estuvo jugando en esta sesion) y no esta terminada
##   Nueva partida  abre el selector de modo (GameManager.request_new_game).
##                  Nunca borra: crea otra partida (con cinco, pide borrar una)
##   Partidas  n/5  la lista de partidas guardadas (SavesPanel): cargar, borrar
##   Ajustes        abre el SettingsPanel de siempre, que funciona en pausa, sobre
##                  la ilustracion del menu: la partida no se ve detras
##   Salir
##
## No carga ni guarda nada por su cuenta: GameManager ya arranco la partida
## antes de que este nodo existiera. El menu solo decide cuando se suelta.

const CT := preload("res://scripts/ui/CartoonTheme.gd")

const LAYER := 30
const CARD_WIDTH := 340.0
## Por debajo de esta proporcion (ancho/alto) la pantalla es de movil en
## vertical: la ilustracion recorta el titulo, asi que se escribe encima.
const PORTRAIT_RATIO := 1.0

const KEYART_PATH := "res://assets/branding/keyart.png"
const LOGO_PATH := "res://assets/branding/logo.png"

## El menu sale una vez por sesion, al arrancar, y no cada vez que se recarga la
## isla (nueva partida) o se cambia de vista 3D/2D. La marca vive en GameManager
## (GameManager.title_dismissed): un autoload sobrevive a cualquier cambio de
## escena, y una static var solo mientras el motor no descargue este script.

var _root: Control
var _art: TextureRect
var _shade: ColorRect
var _brand: VBoxContainer
var _card: PanelContainer
var _continue_btn: Button
var _new_btn: Button
var _saves_btn: Button
var _settings_btn: Button
var _quit_btn: Button
## "Partida en curso: Campana", bajo Continuar. Discreto: el modo se ve, no manda.
var _mode_label: Label

var _paused_by_me := false
## Pantalla prestada abierta encima (Ajustes) y su process_mode original.
var _sub: CanvasLayer = null
var _sub_mode: int = Node.PROCESS_MODE_INHERIT
var _sub_layer: int = 1

func _ready() -> void:
	layer = LAYER
	# El menu tiene que responder con el arbol en pausa: es quien lo pausa.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_ui()
	visible = false
	UIManager.window_closed.connect(_on_window_closed)
	UIManager.window_opened.connect(func(_w): _pin_sub_layer())
	get_viewport().size_changed.connect(_relayout)
	# El menu sale antes de que GameManager cargue (lo hace cuando la escena
	# entera esta lista): al terminar la carga se sabe que hay que continuar y
	# en que modo.
	EventBus.game_load_completed.connect(_on_game_ready)
	EventBus.game_new_started.connect(_on_game_ready)
	if should_show_on_launch():
		open_menu()

## Sin ventana (tests, --headless) no hay menu: pausaria el arbol de las pruebas.
## `--no-title` tras `--` lo salta tambien, para las sondas de tools/.
func should_show_on_launch() -> bool:
	if GameManager.title_dismissed:
		return false
	if DisplayServer.get_name() == "headless":
		return false
	# La escena se va a la otra vista en este mismo frame (ViewRouter): el menu
	# lo abre la escena que llega, no esta, que muere antes de poder enfocarlo.
	if GameManager.is_start_held():
		return false
	return not OS.get_cmdline_user_args().has("--no-title")

## Hay una partida que merece "Continuar": se cargo al arrancar, o el jugador ya
## ha estado jugando en esta sesion (vuelve aqui desde la pausa).
##
## Una partida terminada (Supervivencia perdida) no se continua: se ve, pero
## solo ofrece empezar otra.
func has_game_to_continue() -> bool:
	if GameMode.is_run_over():
		return false
	return GameManager.loaded_from_save or GameManager.title_dismissed

func is_open() -> bool:
	return visible

## Olvida si el menu ya salio en esta sesion. Solo para pruebas: en partida la
## marca vive hasta cerrar el juego.
static func set_dismissed_for_tests(dismissed: bool) -> void:
	GameManager.title_dismissed = dismissed

# ── Construccion ─────────────────────────────────────────────────────

func _setup_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var base := ColorRect.new()
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.color = CT.c("hud", "BG")
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(base)

	_art = TextureRect.new()
	_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(KEYART_PATH):
		_art.texture = load(KEYART_PATH)
	_root.add_child(_art)

	# Un velo para que la tarjeta se lea sobre la ilustracion sin apagarla.
	_shade = ColorRect.new()
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.color = Color(0.0, 0.0, 0.0, 0.2)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_shade)

	# Emblema y nombre: solo en vertical, donde la ilustracion recorta su titulo.
	_brand = VBoxContainer.new()
	_brand.alignment = BoxContainer.ALIGNMENT_CENTER
	_brand.add_theme_constant_override("separation", 4)
	_brand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_brand)
	var logo := TextureRect.new()
	logo.custom_minimum_size = Vector2(88, 88)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(LOGO_PATH):
		logo.texture = load(LOGO_PATH)
	_brand.add_child(logo)
	var name_label := CT.label(Tr.t("LBL_TITLE_GAME"), "display", CT.WHITE, true)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_brand.add_child(name_label)

	# La tarjeta: crema con borde grueso (docs/28 §6), sin titulo ni cinta: los
	# botones dicen lo que son. Verde = la accion principal (Continuar o, sin
	# partida, Nueva partida), rojo = Salir, el resto crema (docs/28 §5).
	var small := CT.is_phone()
	_card = PanelContainer.new()
	_card.name = "Card"
	var st := CT.window_style()
	st.set_content_margin_all(10 if small else 18)
	_card.add_theme_stylebox_override("panel", st)
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6 if small else 10)
	_card.add_child(column)

	var hh: int = CT.menu_h("small" if small else "btn")
	_continue_btn = _menu_button(Tr.t("UI2M_TITLE_CONTINUE"), "next", "primary", CT.menu_h("btn" if small else "big"), _on_continue)
	_continue_btn.name = "ContinueButton"
	column.add_child(_continue_btn)
	_mode_label = CT.label("", "small", CT.text("window", true))
	_mode_label.name = "RunMode"
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_mode_label)
	_new_btn = _menu_button(Tr.t("BTN_NEW_GAME"), "plus", "secondary", hh, _on_new_game)
	_new_btn.name = "NewGameButton"
	_new_btn.set_meta("pill_h", hh)
	column.add_child(_new_btn)
	_saves_btn = _menu_button(Tr.t("BTN_SAVES"), "game", "secondary", hh, _on_saves)
	_saves_btn.name = "SavesButton"
	column.add_child(_saves_btn)
	_settings_btn = _menu_button(Tr.t("BTN_SETTINGS"), "settings", "secondary", hh, _on_settings)
	_settings_btn.name = "SettingsButton"
	column.add_child(_settings_btn)
	_quit_btn = _menu_button(Tr.t("BTN_QUIT"), "close", "danger", hh, _on_quit)
	_quit_btn.name = "QuitButton"
	column.add_child(_quit_btn)

	_relayout()

## Un boton del menu: pastilla a lo ancho con [icono] Palabra. El texto vive en
## una etiqueta (meta "label"); `Button.text` se queda vacio.
func _menu_button(text_s: String, glyph: String, kind_s: String, hh: int, cb: Callable) -> Button:
	var b := CT.pill_button(text_s, glyph, kind_s, hh)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.set_meta("text", text_s)
	b.pressed.connect(cb)
	return b

## El texto de un boton del menu (pruebas y sondas).
func button_text(b: Button) -> String:
	var l := b.find_children("*", "Label", true, false)
	return (l[0] as Label).text if not l.is_empty() else b.text

func _vp() -> Vector2:
	return get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280, 720)

## Horizontal: la ilustracion ya trae el titulo abajo, la tarjeta va a la
## izquierda sobre el cielo. Vertical: emblema y nombre arriba, tarjeta debajo.
func _relayout() -> void:
	if _card == null:
		return
	var vp: Vector2 = _vp()
	var small := CT.is_phone()
	var portrait: bool = vp.x / maxf(vp.y, 1.0) < PORTRAIT_RATIO
	_brand.visible = portrait and _card.visible
	var width: float = minf(CARD_WIDTH if not small else 280.0, vp.x - ModalKit.EDGE * 2.0)
	_card.custom_minimum_size = Vector2(width, 0)
	_card.reset_size()
	var card_h: float = _card.get_combined_minimum_size().y
	# En vertical la ilustracion se estira por debajo de la pantalla: su franja
	# de titulo queda fuera, en vez de salir recortada ("ENTA IMP").
	_art.offset_bottom = vp.y * 0.4 if portrait else 0.0
	_shade.color.a = 0.45 if portrait else 0.2
	if portrait:
		_brand.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_brand.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_brand.offset_left = -vp.x * 0.5 + ModalKit.EDGE
		_brand.offset_right = vp.x * 0.5 - ModalKit.EDGE
		_brand.offset_top = 24.0
		_brand.offset_bottom = 220.0
		_card.set_anchors_preset(Control.PRESET_CENTER)
		_card.offset_left = -width * 0.5
		_card.offset_right = width * 0.5
		_card.offset_top = 110.0 - card_h * 0.5
		_card.offset_bottom = 110.0 + card_h * 0.5
	else:
		# Pegada a la izquierda y algo por encima del centro: abajo esta el titulo.
		# Sin salirse por arriba (telefono apaisado: ronda visual de la 1.1).
		var lift := title_card_lift(vp.y, card_h)
		_card.anchor_left = 0.0
		_card.anchor_right = 0.0
		_card.anchor_top = 0.5
		_card.anchor_bottom = 0.5
		var left := 24.0 if small else 56.0
		_card.offset_left = left
		_card.offset_right = left + width
		_card.offset_top = -card_h * 0.5 - lift
		_card.offset_bottom = card_h * 0.5 - lift

## Cuanto sube la tarjeta sobre el centro (horizontal): 60 px, o lo que quepa
## sin que su borde de arriba baje de ModalKit.EDGE.
static func title_card_lift(vp_h: float, card_h: float) -> float:
	return clampf((vp_h - card_h) * 0.5 - ModalKit.EDGE, 0.0, 60.0)

# ── Abrir / cerrar ───────────────────────────────────────────────────

func open_menu() -> void:
	_refresh_buttons()
	_relayout()
	_root.visible = true
	visible = true
	if not get_tree().paused:
		get_tree().paused = true
		_paused_by_me = true
	_focus_default.call_deferred()

## Diferido, y solo si el menu sigue en el arbol: una recarga o un cambio de
## escena en el mismo frame lo dejaba fuera y grab_focus fallaba.
func _focus_default() -> void:
	var btn: Button = _continue_btn if _continue_btn.visible else _new_btn
	if is_instance_valid(btn) and btn.is_inside_tree() and btn.is_visible_in_tree():
		btn.grab_focus()

## Suelta el menu y, si lo pauso el, el juego.
func close_menu() -> void:
	GameManager.title_dismissed = true
	visible = false
	_close_sub()
	if _paused_by_me:
		_paused_by_me = false
		get_tree().paused = false

func _refresh_buttons() -> void:
	_continue_btn.visible = has_game_to_continue()
	# Sin partida que continuar, NUEVA PARTIDA es la accion principal: verde.
	CT.set_pill_kind(_new_btn, "secondary" if _continue_btn.visible else "primary", int(_new_btn.get_meta("pill_h", CT.BTN)))
	_mode_label.visible = _continue_btn.visible
	_mode_label.text = Tr.t("LBL_TITLE_RUN_MODE") % GameMode.display_name()
	var saves: int = GameManager.list_saves().size()
	var saves_label := _saves_btn.find_children("*", "Label", true, false)
	if not saves_label.is_empty():
		(saves_label[0] as Label).text = "%s  %d/%d" % [Tr.t("BTN_SAVES"), saves, GameManager.MAX_SAVES]
	_saves_btn.visible = saves > 0

func _on_game_ready() -> void:
	if visible:
		_refresh_buttons()

func _exit_tree() -> void:
	# Recargar la escena (nueva partida) con el menu abierto no puede dejar el
	# arbol nuevo congelado.
	if _paused_by_me and get_tree() != null:
		get_tree().paused = false

# ── Botones ──────────────────────────────────────────────────────────

func _on_continue() -> void:
	close_menu()

## Abre el selector de modo (o, con las cinco ocupadas, la lista para hacer
## sitio). Elegir recarga la escena en una partida nueva; GameManager suelta el
## menu (title_dismissed) para que la nueva arranque con su intro.
func _on_new_game() -> void:
	GameManager.request_new_game()

## La lista de partidas, encima del menu. Cargar una suelta el menu y abre esa.
func _on_saves() -> void:
	var panel: CanvasLayer = GameManager.open_saves_list()
	if panel != null:
		panel.tree_exited.connect(func():
			if is_inside_tree() and visible:
				_refresh_buttons())

func _on_settings() -> void:
	var settings: CanvasLayer = _find_sibling("SettingsPanel")
	if settings == null or not settings.has_method("toggle"):
		return
	_open_sub(settings)
	settings.toggle()

func _on_quit() -> void:
	get_tree().quit()

# ── Pantallas prestadas ──────────────────────────────────────────────

## Ajustes vive en su propio panel y en la pila de UIManager. Con el arbol en
## pausa no recibiria clics: se le deja procesar mientras esta abierto y se le
## devuelve su modo al cerrarse. Del menu se esconden solo la tarjeta y el
## emblema: la ilustracion se queda de fondo, porque Ajustes abierto desde el
## menu principal es parte del menu, no una ventana sobre la isla.
##
## Y se pone POR ENCIMA de todo mientras dura (bug 1): UIManager la dejaba en la
## capa 13 y cualquier cosa por encima (la intro del tutorial, capa 17, que se
## abria detras del menu) se comia los toques. La capa se vuelve a fijar cada
## vez que UIManager reordena su pila y en cada frame.
func _open_sub(panel: CanvasLayer) -> void:
	_sub = panel
	_sub_mode = panel.process_mode
	_sub_layer = panel.layer
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_pin_sub_layer()
	_card.visible = false
	_brand.visible = false

func _pin_sub_layer() -> void:
	if _sub != null and is_instance_valid(_sub):
		_sub.layer = LAYER + 1

func _process(_delta: float) -> void:
	if _sub != null:
		_pin_sub_layer()

## Pantalla prestada abierta, para pruebas.
func borrowed() -> CanvasLayer:
	return _sub

func _close_sub() -> void:
	if _sub != null and is_instance_valid(_sub):
		_sub.process_mode = _sub_mode
		_sub.layer = _sub_layer
	_sub = null
	_card.visible = true
	_relayout()

func _on_window_closed(window: CanvasLayer) -> void:
	if _sub != null and window == _sub:
		_close_sub()

func _find_sibling(node_name: String) -> Node:
	var parent: Node = get_parent()
	if parent != null:
		var sibling: Node = parent.get_node_or_null(node_name)
		if sibling != null:
			return sibling
	return get_tree().root.find_child(node_name, true, false)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		# ESC con Ajustes encima cierra Ajustes (UIManager esta en pausa y no lo
		# haria); con el menu solo, no hace nada: no hay "detras" al que volver.
		if _sub != null and _sub.has_method("toggle"):
			_sub.toggle()
		get_viewport().set_input_as_handled()
