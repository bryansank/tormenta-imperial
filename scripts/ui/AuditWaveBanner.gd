extends CanvasLayer
## El cartel de la Auditoria Final: "Oleada X de N" cada vez que una formacion
## baja al tablero, con "Oleada rechazada. Quedan N." delante si viene de romper
## la anterior, y la linea de la ultima oleada cuando toca. Sin el, una oleada
## rota solo se notaba porque se abria la siguiente.
##
## Escucha `final_audit_wave_cleared` (nadie mas la escucha) y
## `final_audit_wave_ready`. Las dos llegan en la misma cadena al cerrar el parte
## de una oleada: primero la rota, despues la nueva. Por eso la rota se guarda y
## se escribe encima de la nueva, en un solo cartel.
##
## No bloquea nada: ignora el raton, se desvanece solo y va por encima del
## tablero (18) y por debajo de la victoria (20).

const LAYER := 19
const HOLD_SECONDS := 3.2
const FADE_SECONDS := 0.6
const WIDTH := 460.0

var _panel: PanelContainer
var _cleared_label: Label
var _wave_label: Label
var _note_label: Label
var _tween: Tween
var _pending_cleared: String = ""

func _ready() -> void:
	layer = LAYER
	_setup_ui()
	EventBus.final_audit_wave_cleared.connect(_on_wave_cleared)
	EventBus.final_audit_wave_ready.connect(_on_wave_ready)
	EventBus.final_audit_lost.connect(func(_w): hide_banner())
	EventBus.storm_halted_forever.connect(hide_banner)
	get_viewport().size_changed.connect(_relayout)

func _setup_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_panel = ModalKit.make_card(2)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	root.add_child(_panel)
	var column: VBoxContainer = _panel.get_child(0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_cleared_label = ModalKit.make_text("", "small", UITheme.POSITIVE)
	column.add_child(_cleared_label)
	_wave_label = ModalKit.make_text("", "title", UITheme.ACCENT)
	_wave_label.add_theme_font_size_override("font_size", 30)
	column.add_child(_wave_label)
	_note_label = ModalKit.make_text("", "small", UITheme.WARNING)
	column.add_child(_note_label)
	_relayout()

## Arriba al centro, donde el tablero pone su titulo: se lee sin tapar casillas.
func _relayout() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var width: float = minf(WIDTH, vp.x - ModalKit.EDGE * 2.0)
	_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.custom_minimum_size = Vector2(width, 0)
	_panel.offset_left = -width * 0.5
	_panel.offset_right = width * 0.5
	_panel.offset_top = 70.0
	_panel.offset_bottom = 70.0

func _on_wave_cleared(_wave: int, remaining: int) -> void:
	# La ultima rota es la victoria: de eso ya habla la pantalla de victoria.
	if remaining <= 0:
		_pending_cleared = ""
		return
	_pending_cleared = Tr.t("AUDIT_WAVE_CLEARED") % remaining

func _on_wave_ready(wave: int, _roster: Dictionary, _scale: float) -> void:
	var total: int = 0
	if ProgressionManager.final_audit != null:
		total = ProgressionManager.final_audit.wave_count()
	show_wave(wave, maxi(total, wave + 1), _pending_cleared)
	_pending_cleared = ""

## Pinta el cartel de la oleada `wave` (base 0) de `total`. Publico para pruebas.
func show_wave(wave: int, total: int, cleared_line: String = "") -> void:
	_cleared_label.text = cleared_line
	_cleared_label.visible = cleared_line != ""
	_wave_label.text = Tr.t("AUDIT_WAVE") % [wave + 1, total]
	_note_label.text = note_for(wave, total)
	_note_label.visible = _note_label.text != ""
	_panel.visible = true
	_panel.modulate.a = 1.0
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_interval(HOLD_SECONDS)
	_tween.tween_property(_panel, "modulate:a", 0.0, FADE_SECONDS)
	_tween.tween_callback(func(): _panel.visible = false)

## La linea de abajo: en la primera oleada, que no hay relevos; en la ultima,
## que es la ultima.
static func note_for(wave: int, total: int) -> String:
	if total > 0 and wave >= total - 1:
		return Tr.t("AUDIT_LAST_WAVE")
	if wave == 0:
		return Tr.t("AUDIT_ATTRITION")
	return ""

func hide_banner() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_panel.visible = false
	_pending_cleared = ""

func is_showing() -> bool:
	return _panel.visible

func wave_text() -> String:
	return _wave_label.text

func cleared_text() -> String:
	return _cleared_label.text if _cleared_label.visible else ""

func note_text() -> String:
	return _note_label.text if _note_label.visible else ""
