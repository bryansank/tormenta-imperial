extends CanvasLayer
## El cartel del Ataque Final: "Oleada X de N" cada vez que una formacion baja
## al tablero, con "Oleada rechazada. Quedan N." delante si viene de romper la
## anterior, y la linea de la ultima oleada cuando toca. Sin el, una oleada rota
## solo se notaba porque se abria la siguiente.
##
## Escucha `final_audit_wave_cleared` (nadie mas la escucha) y
## `final_audit_wave_ready`. Las dos llegan en la misma cadena al cerrar el parte
## de una oleada: primero la rota, despues la nueva. Por eso la rota se guarda y
## se escribe encima de la nueva, en un solo cartel.
##
## Rediseno fase 2 (feat/ui2-ejercito, docs/28): una cinta roja de juguete con
## "Oleada 2 de 4" en grande, arriba al centro; debajo, en una pastilla oscura,
## la linea corta. Sin animacion (docs/28 §0.6): aparece y, pasado HOLD_SECONDS,
## desaparece de golpe. No bloquea nada: ignora el raton y va por encima del
## tablero (18) y por debajo de la victoria (20).

const CT := preload("res://scripts/ui/CartoonTheme.gd")

const LAYER := 19
const HOLD_SECONDS := 3.6
const WIDTH := 460.0

var _panel: VBoxContainer
var _ribbon: PanelContainer
var _cleared_label: Label
var _wave_label: Label
var _note_label: Label
var _note_box: PanelContainer
var _timer: Timer
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

	_panel = VBoxContainer.new()
	_panel.name = "WaveBanner"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_theme_constant_override("separation", 4)
	_panel.visible = false
	root.add_child(_panel)

	# "Oleada rechazada. Quedan 2." en verde, encima.
	_cleared_label = CT.label("", "button", CT.sem("POSITIVE").lightened(0.35), true)
	_cleared_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cleared_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel.add_child(_cleared_label)

	# La cinta con la oleada.
	_ribbon = PanelContainer.new()
	_ribbon.add_theme_stylebox_override("panel", CT.ribbon_style(CT.sem("DANGER")))
	_ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ribbon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := CT.make_glyph("storm", 30 if CT.phone else 38)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var tc := CT.on_fill(CT.sem("DANGER"))
	_wave_label = CT.label("", "display", tc["color"], tc["outline"])
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_wave_label)
	_ribbon.add_child(row)
	_panel.add_child(_ribbon)

	# La linea de abajo (sin relevos / la ultima), en una pastilla del HUD.
	_note_box = PanelContainer.new()
	_note_box.add_theme_stylebox_override("panel", CT.hud_style(CT.sem("WARNING")))
	_note_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_note_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_note_label = CT.label("", "small", CT.text("hud"))
	_note_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note_box.add_child(_note_label)
	_panel.add_child(_note_box)

	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(func(): _panel.visible = false)
	add_child(_timer)
	_relayout()

## Arriba al centro, donde el tablero pone su titulo: se lee sin tapar casillas.
func _relayout() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var phone := CT.phone_canvas(vp)
	var width: float = minf(WIDTH, vp.x - 16.0)
	_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.custom_minimum_size = Vector2(width, 0)
	_panel.offset_left = -width * 0.5
	_panel.offset_right = width * 0.5
	var top := 56.0 if phone else 70.0
	_panel.offset_top = top
	_panel.offset_bottom = top
	_note_label.custom_minimum_size.x = minf(width - 40.0, 380.0)

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
	_note_box.visible = _note_label.text != ""
	_panel.visible = true
	_relayout()
	# Sin desvanecer: se quita de golpe pasado el tiempo.
	if _timer.is_inside_tree():
		_timer.start(HOLD_SECONDS)

## La linea de abajo: en la primera oleada, que no hay relevos; en la ultima,
## que es la ultima.
static func note_for(wave: int, total: int) -> String:
	if total > 0 and wave >= total - 1:
		return Tr.t("AUDIT_LAST_WAVE")
	if wave == 0:
		return Tr.t("AUDIT_ATTRITION")
	return ""

func hide_banner() -> void:
	_timer.stop()
	_panel.visible = false
	_pending_cleared = ""

func is_showing() -> bool:
	return _panel.visible

func wave_text() -> String:
	return _wave_label.text

func cleared_text() -> String:
	return _cleared_label.text if _cleared_label.visible else ""

func note_text() -> String:
	return _note_label.text if _note_box.visible else ""
