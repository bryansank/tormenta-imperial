extends CanvasLayer
## El menu principal. Sale al arrancar, encima de la partida ya cargada y con el
## arbol en pausa: la isla se ve detras, quieta, y nada corre hasta que el
## jugador elige.
##
##   Continuar      solo si hay algo que continuar (se cargo una partida, o ya
##                  se estuvo jugando en esta sesion)
##   Nueva partida  con confirmacion via GameManager.request_new_game() cuando
##                  hay algo que perder; sin ella si la isla es nueva
##   Ajustes        abre el SettingsPanel de siempre, que funciona en pausa
##   Salir
##
## No carga ni guarda nada por su cuenta: GameManager ya arranco la partida
## antes de que este nodo existiera. El menu solo decide cuando se suelta.

const LAYER := 30
const CARD_WIDTH := 360.0
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
var _settings_btn: Button
var _quit_btn: Button

var _paused_by_me := false
## Pantalla prestada abierta encima (Ajustes) y su process_mode original.
var _sub: CanvasLayer = null
var _sub_mode: int = Node.PROCESS_MODE_INHERIT

func _ready() -> void:
	layer = LAYER
	# El menu tiene que responder con el arbol en pausa: es quien lo pausa.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_ui()
	visible = false
	UIManager.window_closed.connect(_on_window_closed)
	get_viewport().size_changed.connect(_relayout)
	if should_show_on_launch():
		open_menu()

## Sin ventana (tests, --headless) no hay menu: pausaria el arbol de las pruebas.
## `--no-title` tras `--` lo salta tambien, para las sondas de tools/.
func should_show_on_launch() -> bool:
	if GameManager.title_dismissed:
		return false
	if DisplayServer.get_name() == "headless":
		return false
	return not OS.get_cmdline_user_args().has("--no-title")

## Hay una partida que merece "Continuar": se cargo al arrancar, o el jugador ya
## ha estado jugando en esta sesion (vuelve aqui desde la pausa).
func has_game_to_continue() -> bool:
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
	base.color = UITheme.BG_DARK
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
	_shade.color = Color(0.0, 0.0, 0.0, 0.25)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_shade)

	# Emblema y nombre: solo en vertical, donde la ilustracion recorta su titulo.
	_brand = VBoxContainer.new()
	_brand.alignment = BoxContainer.ALIGNMENT_CENTER
	_brand.add_theme_constant_override("separation", 6)
	_brand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_brand)
	var logo := TextureRect.new()
	logo.custom_minimum_size = Vector2(96, 96)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(LOGO_PATH):
		logo.texture = load(LOGO_PATH)
	_brand.add_child(logo)
	var name_label := ModalKit.make_text(Tr.t("LBL_TITLE_GAME"), "title", UITheme.ACCENT)
	name_label.add_theme_font_size_override("font_size", 30)
	_brand.add_child(name_label)
	_brand.add_child(ModalKit.make_text(Tr.t("LBL_TITLE_MOTTO"), "small", UITheme.TEXT))

	_card = ModalKit.make_card(10)
	_root.add_child(_card)
	var column: VBoxContainer = _card.get_child(0)

	var header := ModalKit.make_text(Tr.t("LBL_TITLE_MENU"), "section", UITheme.ACCENT)
	column.add_child(header)
	column.add_child(UITheme.make_separator())

	_continue_btn = ModalKit.make_menu_button(Tr.t("BTN_TITLE_CONTINUE"), UITheme.POSITIVE, _on_continue)
	column.add_child(_continue_btn)
	_new_btn = ModalKit.make_menu_button(Tr.t("BTN_NEW_GAME"), UITheme.BTN, _on_new_game)
	column.add_child(_new_btn)
	_settings_btn = ModalKit.make_menu_button(Tr.t("BTN_SETTINGS"), UITheme.BTN, _on_settings)
	column.add_child(_settings_btn)
	_quit_btn = ModalKit.make_menu_button(Tr.t("BTN_QUIT"), UITheme.DANGER, _on_quit)
	column.add_child(_quit_btn)

	_relayout()

## Horizontal: la ilustracion ya trae el titulo abajo, la tarjeta va a la
## izquierda sobre el cielo. Vertical: emblema y nombre arriba, tarjeta debajo.
func _relayout() -> void:
	if _card == null:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var portrait: bool = vp.x / maxf(vp.y, 1.0) < PORTRAIT_RATIO
	_brand.visible = portrait
	ModalKit.fit_center(_card, CARD_WIDTH, vp)
	# En vertical la ilustracion se estira por debajo de la pantalla: su franja
	# de titulo queda fuera, en vez de salir recortada ("ENTA IMP").
	_art.offset_bottom = vp.y * 0.4 if portrait else 0.0
	_shade.color.a = 0.45 if portrait else 0.25
	if portrait:
		_brand.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_brand.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_brand.offset_left = -vp.x * 0.5 + ModalKit.EDGE
		_brand.offset_right = vp.x * 0.5 - ModalKit.EDGE
		_brand.offset_top = 24.0
		_brand.offset_bottom = 250.0
		_card.offset_top = 110.0
		_card.offset_bottom = 110.0
	else:
		# Pegada a la izquierda y algo por encima del centro: abajo esta el titulo.
		var width: float = _card.custom_minimum_size.x
		_card.anchor_left = 0.0
		_card.anchor_right = 0.0
		_card.offset_left = 56.0
		_card.offset_right = 56.0 + width
		_card.offset_top = -60.0
		_card.offset_bottom = -60.0

# ── Abrir / cerrar ───────────────────────────────────────────────────

func open_menu() -> void:
	_refresh_buttons()
	_relayout()
	_root.visible = true
	visible = true
	if not get_tree().paused:
		get_tree().paused = true
		_paused_by_me = true
	(_continue_btn if _continue_btn.visible else _new_btn).grab_focus.call_deferred()

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

func _exit_tree() -> void:
	# Recargar la escena (nueva partida) con el menu abierto no puede dejar el
	# arbol nuevo congelado.
	if _paused_by_me and get_tree() != null:
		get_tree().paused = false

# ── Botones ──────────────────────────────────────────────────────────

func _on_continue() -> void:
	close_menu()

## Con una partida que perder, confirma y borra (GameManager recarga la escena).
## Si la isla acaba de nacer no hay nada que borrar: se suelta el menu y empieza.
func _on_new_game() -> void:
	if not has_game_to_continue():
		close_menu()
		return
	var dialog: ConfirmationDialog = GameManager.request_new_game()
	if dialog != null:
		# La escena se recarga al confirmar: el menu no vuelve a salir encima de
		# la partida nueva, que arranca con su intro.
		dialog.confirmed.connect(func(): GameManager.title_dismissed = true)

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
## devuelve su modo al cerrarse. El menu se esconde para no taparlo (su capa
## queda por encima de la de cualquier ventana de la pila).
func _open_sub(panel: CanvasLayer) -> void:
	_sub = panel
	_sub_mode = panel.process_mode
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_root.visible = false

func _close_sub() -> void:
	if _sub != null and is_instance_valid(_sub):
		_sub.process_mode = _sub_mode
	_sub = null
	_root.visible = true

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
