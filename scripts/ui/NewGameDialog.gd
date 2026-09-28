extends CanvasLayer
## "Nueva partida": el selector de modo y, si hay algo que perder, la
## confirmacion. Sustituye al ConfirmationDialog con el tema por defecto de
## Godot (en el emulador de Android salia gris y diminuto).
##
##   Paso 1  cuatro tarjetas (nombre, dificultad, una linea) y lo que pide el
##           modo elegido. Tocar una tarjeta la elige; EMPEZAR sigue.
##   Paso 2  solo con `ask_confirm`: "se borrara la partida actual (modo X)".
##
## No borra nada por su cuenta: emite `confirmed` con `chosen_mode` puesto, o
## `canceled`, y quien lo abrio (GameManager.request_new_game) decide. Lo crea
## GameManager y cuelga de el, asi que sobrevive a la recarga de escena y
## funciona igual en la vista 3D y en la 2D.
##
## Tactil primero: cada tarjeta es un boton de 44 px o mas, y la rejilla pasa de
## 4 columnas a 2 y a 1 segun el ancho (1280x800, 1024x768, movil en vertical).

signal confirmed
signal canceled

const LAYER := 40
const MAX_WIDTH := 1000.0
const CARD_MIN_H := 150.0
const WIDE := 900.0
const MEDIUM := 520.0

## El modo elegido. Lo lee quien escucha `confirmed`.
var chosen_mode: int = GameMode.DEFAULT

var _ask_confirm := true
var _current_mode: int = GameMode.DEFAULT

var _root: Control
var _card: PanelContainer
var _pick_box: VBoxContainer
var _confirm_box: VBoxContainer
var _grid: GridContainer
var _scroll: ScrollContainer
var _goal_label: Label
var _confirm_label: Label
var _start_btn: Button
var _cards: Dictionary = {}   ## mode -> Button

## Antes de add_child. `current_mode` es el de la partida que se perderia.
func setup(ask_confirm: bool, current_mode: int) -> void:
	_ask_confirm = ask_confirm
	_current_mode = current_mode
	chosen_mode = current_mode

func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_ui()
	_select(chosen_mode)
	_show_pick()
	get_viewport().size_changed.connect(_relayout)
	_relayout()

# ── Construccion ─────────────────────────────────────────────────────

func _setup_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_root.add_child(ModalKit.make_backdrop(0.72))

	_card = ModalKit.make_card(10)
	_root.add_child(_card)
	var column: VBoxContainer = _card.get_child(0)

	# ── Paso 1: elegir modo ──
	_pick_box = VBoxContainer.new()
	_pick_box.add_theme_constant_override("separation", 10)
	column.add_child(_pick_box)
	_pick_box.add_child(ModalKit.make_text(Tr.t("BTN_NEW_GAME"), "title", UITheme.ACCENT))
	_pick_box.add_child(ModalKit.make_text(Tr.t("LBL_MODE_PICK"), "small", UITheme.TEXT_DIM))
	_pick_box.add_child(UITheme.make_separator())

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_pick_box.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	_scroll.add_child(_grid)
	for mode in GameMode.ORDER:
		var btn := _make_mode_card(mode)
		_cards[mode] = btn
		_grid.add_child(btn)

	_goal_label = ModalKit.make_text("", "body", UITheme.TEXT)
	_pick_box.add_child(_goal_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_pick_box.add_child(row)
	row.add_child(ModalKit.make_menu_button(Tr.t("BTN_CANCEL"), UITheme.BTN, cancel))
	_start_btn = ModalKit.make_menu_button(Tr.t("BTN_MODE_START"), UITheme.POSITIVE, _on_start)
	row.add_child(_start_btn)

	# ── Paso 2: confirmar que se borra ──
	_confirm_box = VBoxContainer.new()
	_confirm_box.add_theme_constant_override("separation", 12)
	column.add_child(_confirm_box)
	_confirm_box.add_child(ModalKit.make_text(Tr.t("BTN_NEW_GAME"), "title", UITheme.DANGER))
	_confirm_label = ModalKit.make_text("", "body", UITheme.TEXT)
	_confirm_box.add_child(_confirm_label)
	var confirm_row := HBoxContainer.new()
	confirm_row.add_theme_constant_override("separation", 12)
	_confirm_box.add_child(confirm_row)
	confirm_row.add_child(ModalKit.make_menu_button(Tr.t("BTN_MODE_BACK"), UITheme.BTN, _show_pick))
	confirm_row.add_child(ModalKit.make_menu_button(Tr.t("BTN_MODE_WIPE_START"), UITheme.DANGER, confirm))

## Una tarjeta: boton alto, con nombre, etiqueta de dificultad y una linea.
func _make_mode_card(mode: int) -> Button:
	var color: Color = mode_color(mode)
	var btn := Button.new()
	btn.name = "Mode_%s" % GameMode.key_of(mode)
	btn.toggle_mode = true
	btn.focus_mode = Control.FOCUS_ALL
	btn.clip_contents = true
	btn.custom_minimum_size = Vector2(0, CARD_MIN_H)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_card_button(btn, UITheme.CARD_BG, color)
	btn.pressed.connect(_select.bind(mode))

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 16
	box.offset_right = -10
	box.offset_top = 10
	box.offset_bottom = -10
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(box)

	var name_label := UITheme.make_label(Tr.t(GameMode.name_key(mode)), "section", UITheme.TEXT_BRIGHT)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)
	var tag := UITheme.make_label(Tr.t(GameMode.tag_key(mode)).to_upper(), "small", color.lightened(0.35))
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(tag)
	var desc := UITheme.make_label(Tr.t(GameMode.desc_key(mode)), "small", UITheme.TEXT)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(desc)
	# El boton no crece con sus hijos: se le pasa el alto que pide el texto.
	box.minimum_size_changed.connect(func():
		btn.custom_minimum_size.y = maxf(CARD_MIN_H, box.get_combined_minimum_size().y + 20.0))
	return btn

## El color de cada modo: el de su dificultad.
static func mode_color(mode: int) -> Color:
	match mode:
		GameMode.Mode.BUILDER:
			return UITheme.POSITIVE
		GameMode.Mode.SURVIVAL:
			return UITheme.DANGER
		GameMode.Mode.SANDBOX:
			return UITheme.INFO
		_:
			return UITheme.ACCENT

# ── Colocacion ───────────────────────────────────────────────────────

## Columnas de tarjetas para un ancho de tarjeta dado: 4 en una tableta o PC en
## horizontal (1024 px o mas), 2 en una pantalla estrecha, 1 en un movil en
## vertical.
static func columns_for(card_width: float) -> int:
	if card_width >= WIDE:
		return 4
	if card_width >= MEDIUM:
		return 2
	return 1

func _relayout() -> void:
	if _card == null:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	ModalKit.fit_center(_card, MAX_WIDTH, vp)
	_grid.columns = columns_for(_card.custom_minimum_size.x)
	# Lo que no quepa en alto se desplaza: el resto de la tarjeta (titulo,
	# objetivo, botones) necesita unos 300 px.
	var rows: int = ceili(float(_cards.size()) / float(_grid.columns))
	var wanted: float = float(rows) * (CARD_MIN_H + 10.0) + 30.0
	_scroll.custom_minimum_size = Vector2(0, clampf(wanted, CARD_MIN_H, maxf(CARD_MIN_H, vp.y - 320.0)))

# ── Pasos ────────────────────────────────────────────────────────────

func _select(mode: int) -> void:
	chosen_mode = mode
	for m in _cards:
		(_cards[m] as Button).set_pressed_no_signal(m == mode)
	_goal_label.text = Tr.t(GameMode.goal_key(mode))

func _show_pick() -> void:
	_pick_box.visible = true
	_confirm_box.visible = false
	(_cards.get(chosen_mode, _start_btn) as Control).grab_focus.call_deferred()

func is_confirming() -> bool:
	return _confirm_box.visible

func _on_start() -> void:
	if not _ask_confirm:
		confirm()
		return
	_confirm_label.text = Tr.t("CONFIRM_NEW_GAME_MODE") % [
		GameMode.display_name(_current_mode), GameMode.display_name(chosen_mode)]
	_pick_box.visible = false
	_confirm_box.visible = true

## Elige y sigue. Publicos para las pruebas y para quien quiera saltarse la UI.
func pick(mode: int) -> void:
	_select(mode)
	_on_start()

func confirm() -> void:
	confirmed.emit()

func cancel() -> void:
	canceled.emit()

func mode_card(mode: int) -> Button:
	return _cards.get(mode, null)

## `_input` y no `_unhandled_input`: el dialogo cuelga de un autoload, y el
## menu principal (en la escena) se come el ESC antes que cualquier autoload.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if is_confirming():
			_show_pick()
		else:
			cancel()
		get_viewport().set_input_as_handled()
