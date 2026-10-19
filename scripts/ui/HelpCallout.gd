extends PanelContainer
## Una ayuda en pantalla: el globo junto a un control del HUD o la tarjeta de
## consejo. Siempre tiene ✕ y siempre se cierra sola.
##
##   [?] Titulo ··················· (✕)
##   Una frase.                    [ mas ]
##   ▬▬▬▬▬▬▬▬▬▬▬▬▬▬░░░░░░░░   <- lo que le queda, se vacia hasta cerrarse
##
## Estilo nuevo (fase 2, docs/28 §9 y §11): un bocadillo crema con tinta gruesa
## y UNA frase (la primera del texto). "Mas" despliega el resto en la misma
## tarjeta; desplegada, el reloj se para (quien lee no pierde el texto).
##
## El tiempo sale del largo del texto (HelpCatalog.auto_close_seconds: de 6 a 12
## s) y se para mientras el dedo o el raton estan encima. Cerrar con ✕ o dejar
## que se agote es lo mismo para quien la muestra: `closed(id, reason)`, y la
## ayuda queda vista. Sin animaciones: aparece y se va al instante.

signal closed(help_id: String, reason: String)

const CT := preload("res://scripts/ui/CartoonTheme.gd")
const REASON_CLOSE := "close"
const REASON_TIMEOUT := "timeout"
const BAR_HEIGHT := 6
const HelpCatalog := preload("res://scripts/ui/HelpCatalog.gd")

var help_id := ""
var _title: Label
var _body: Label
var _more_btn: Button
var _close_btn: Button
var _bar_bg: Panel
var _bar: Panel
var _full_text := ""
var _short_text := ""
var _expanded := false
var _duration := 8.0
var _left := 8.0
var _running := false
var _hover := false
var _held := false

func _init() -> void:
	name = "HelpCallout"
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", CT.bubble_style(true))
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vbox)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(head)

	var ic := CT.make_glyph("help", 24, CT.sem("INFO"))
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(ic)
	_title = CT.label("", "button", CT.text("window"))
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(_title)

	# La ✕: roja y redonda (docs/28 §5), con zona de dedo.
	_close_btn = CT.round_button("close", "danger", maxi(40, int(UITheme.touch_px(40.0))), "", "window") as Button
	_close_btn.name = "CloseButton"
	_close_btn.tooltip_text = Tr.t("BTN_HELP_CLOSE")
	_close_btn.focus_mode = Control.FOCUS_NONE
	_close_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_close_btn.pressed.connect(func(): finish(REASON_CLOSE))
	head.add_child(_close_btn)

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(line)
	_body = CT.para("", "window", false, "body")
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(_body)
	_more_btn = CT.text_button(Tr.t("UI2M_HELP_MORE"), "", "info", CT.menu_h("small"), "body")
	_more_btn.name = "MoreButton"
	_more_btn.focus_mode = Control.FOCUS_NONE
	_more_btn.size_flags_vertical = Control.SIZE_SHRINK_END
	_more_btn.pressed.connect(toggle_more)
	line.add_child(_more_btn)

	# La barra de tiempo: un carril y un relleno que encoge.
	_bar_bg = Panel.new()
	_bar_bg.name = "TimerBar"
	_bar_bg.custom_minimum_size = Vector2(0, BAR_HEIGHT)
	_bar_bg.add_theme_stylebox_override("panel", CT.box(CT.c("window", "WELL"), Color(0, 0, 0, 0), 0, 3, 0))
	_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_bar_bg)
	_bar = Panel.new()
	_bar.add_theme_stylebox_override("panel", CT.box(CT.sem("INFO"), Color(0, 0, 0, 0), 0, 3, 0))
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_bg.add_child(_bar)

	mouse_entered.connect(func():
		if not _touch_style():
			_hover = true)
	mouse_exited.connect(func(): _hover = false)
	set_process(false)

## Rellena el texto. No la ensena ni arranca el reloj: eso es start().
## En pantalla, la primera frase; "Mas" despliega el resto.
func setup(id: String, title_text: String, body_text_s: String) -> void:
	help_id = id
	_title.text = title_text
	_title.visible = title_text != ""
	_full_text = body_text_s
	_short_text = first_sentence(body_text_s)
	_expanded = false
	_render_body()

## La primera frase de `text` (hasta el primer punto, cierre de exclamacion o
## de pregunta, o el primer salto de linea). Pura, para las pruebas.
static func first_sentence(text: String) -> String:
	var t := text.strip_edges()
	var cut := -1
	for mark in [". ", "! ", "? ", ".\n", "!\n", "?\n", "\n"]:
		var at := t.find(mark)
		if at >= 8 and (cut < 0 or at < cut):
			cut = at
	if cut < 0:
		return t
	var end := cut + (1 if t[cut] != "\n" else 0)
	return t.substr(0, end).strip_edges()

func _render_body() -> void:
	var has_more := _short_text != _full_text.strip_edges()
	_body.text = _full_text if _expanded else _short_text
	_more_btn.visible = has_more
	var l := _more_btn.find_children("*", "Label", true, false)
	if not l.is_empty():
		(l[0] as Label).text = Tr.t("UI2M_HELP_LESS" if _expanded else "UI2M_HELP_MORE")

## "Mas" / "Menos": el texto entero en la misma tarjeta. Desplegada, el reloj
## no corre.
func toggle_more() -> void:
	_expanded = not _expanded
	_render_body()

func is_expanded() -> bool:
	return _expanded

## Ensena y arranca la cuenta atras. `seconds` <= 0: la del largo del texto.
func start(seconds: float = -1.0) -> void:
	_duration = seconds if seconds > 0.0 else HelpCatalog.auto_close_seconds(_title.text + " " + _short_text)
	_left = _duration
	_running = true
	_hover = false
	_held = false
	visible = true
	_update_bar()
	set_process(true)

## La quita sin avisar a nadie (se va a volver a ensenar: una ventana se abrio
## encima, la Tormenta la callo). No cuenta como vista.
func suspend() -> void:
	_running = false
	visible = false
	set_process(false)

func finish(reason: String) -> void:
	if not visible and not _running:
		return
	_running = false
	visible = false
	set_process(false)
	closed.emit(help_id, reason)

func is_running() -> bool:
	return _running and visible

func is_timer_paused() -> bool:
	return _hover or _held or _expanded

func time_left() -> float:
	return _left

func duration() -> float:
	return _duration

func close_button() -> Button:
	return _close_btn

func more_button() -> Button:
	return _more_btn

## El texto entero de la ayuda (aunque en pantalla se vea solo la primera frase).
func body_text() -> String:
	return _full_text

## La etiqueta del texto en pantalla.
func body_label() -> Label:
	return _body

## Avanza el reloj a mano. Lo usa _process y lo usan las pruebas.
func tick(delta: float) -> void:
	if not _running:
		return
	if not is_timer_paused():
		_left -= delta
	_update_bar()
	if _left <= 0.0:
		finish(REASON_TIMEOUT)

func _process(delta: float) -> void:
	tick(delta)

func _update_bar() -> void:
	if _bar == null or _bar_bg == null:
		return
	var ratio: float = clampf(_left / maxf(_duration, 0.001), 0.0, 1.0)
	_bar.position = Vector2.ZERO
	_bar.size = Vector2(_bar_bg.size.x * ratio, BAR_HEIGHT)

## El dedo encima para el reloj mientras este apoyado. Con raton basta pasar por
## encima (mouse_entered). Un toque emula tambien un raton que se queda "encima"
## al levantar el dedo: por eso en tactil solo cuenta el dedo apoyado.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_held = (event as InputEventScreenTouch).pressed
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_held = (event as InputEventMouseButton).pressed

func _touch_style() -> bool:
	return Tr.input_style() == "touch"
