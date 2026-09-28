extends PanelContainer
## Una ayuda en pantalla: el globo junto a un control del HUD o la tarjeta de
## consejo. Siempre tiene ✕ y siempre se cierra sola.
##
##   [TITULO ················ ✕]
##   texto
##   ▬▬▬▬▬▬▬▬▬▬▬▬▬▬░░░░░░░░   <- lo que le queda, se vacia hasta cerrarse
##
## El tiempo sale del largo del texto (HelpCatalog.auto_close_seconds: de 6 a 12
## s) y se para mientras el dedo o el raton estan encima: quien esta leyendo no
## pierde el texto a media frase. Cerrar con ✕ o dejar que se agote es lo mismo
## para quien la muestra: `closed(id, reason)`, y la ayuda queda vista.
##
## Estilo azul acero (UITheme.INFO): es el color de la ayuda en todo el juego. El
## lore va en pergamino (PrologueScreen) y el tutorial en laton (TutorialPanel);
## asi no se confunden.

signal closed(help_id: String, reason: String)

const REASON_CLOSE := "close"
const REASON_TIMEOUT := "timeout"
const BAR_HEIGHT := 4
const HelpCatalog := preload("res://scripts/ui/HelpCatalog.gd")

var help_id := ""
var _title: Label
var _body: Label
var _close_btn: Button
var _bar_bg: ColorRect
var _bar: ColorRect
var _duration := 8.0
var _left := 8.0
var _running := false
var _hover := false
var _held := false

func _init() -> void:
	name = "HelpCallout"
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UITheme.make_hud_card_style(UITheme.INFO, 2))
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vbox)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(head)

	_title = UITheme.make_label("", "small", UITheme.INFO.lightened(0.6))
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_title)

	_close_btn = Button.new()
	_close_btn.name = "CloseButton"
	_close_btn.text = "✕"
	_close_btn.tooltip_text = Tr.t("BTN_HELP_CLOSE")
	_close_btn.focus_mode = Control.FOCUS_NONE
	var side: float = UITheme.touch_px(30.0)
	_close_btn.custom_minimum_size = Vector2(side, side)
	UITheme.style_button(_close_btn, UITheme.BTN, UITheme.FONT_SMALL)
	_close_btn.pressed.connect(func(): finish(REASON_CLOSE))
	head.add_child(_close_btn)

	_body = UITheme.make_label("", "small", UITheme.TEXT_BRIGHT)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_body)

	# La barra de tiempo: un fondo y un relleno que encoge. ColorRect y no
	# ProgressBar para que mida 4 px de verdad (la ProgressBar tiene minimo).
	_bar_bg = ColorRect.new()
	_bar_bg.name = "TimerBar"
	_bar_bg.color = Color(UITheme.INFO, 0.25)
	_bar_bg.custom_minimum_size = Vector2(0, BAR_HEIGHT)
	_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_bar_bg)
	_bar = ColorRect.new()
	_bar.color = UITheme.INFO.lightened(0.3)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_bg.add_child(_bar)

	mouse_entered.connect(func():
		if not _touch_style():
			_hover = true)
	mouse_exited.connect(func(): _hover = false)
	set_process(false)

## Rellena el texto. No la ensena ni arranca el reloj: eso es start().
func setup(id: String, title_text: String, body_text: String) -> void:
	help_id = id
	_title.text = title_text
	_title.visible = title_text != ""
	_body.text = body_text

## Ensena y arranca la cuenta atras. `seconds` <= 0: la del largo del texto.
func start(seconds: float = -1.0) -> void:
	_duration = seconds if seconds > 0.0 else HelpCatalog.auto_close_seconds(_title.text + " " + _body.text)
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
	return _hover or _held

func time_left() -> float:
	return _left

func duration() -> float:
	return _duration

func close_button() -> Button:
	return _close_btn

func body_text() -> String:
	return _body.text

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
