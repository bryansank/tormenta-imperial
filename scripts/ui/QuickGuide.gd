extends CanvasLayer
## La guia rapida: como funciona el juego en una sola pantalla, en cuatro
## tarjetas (2026-09-28; estilo nuevo 2026-10, docs/28). Ya no sale sola: la
## abre AYUDA > Como funciona, y sus textos largos tambien viven en AYUDA
## (HelpCatalog: guide_qg_*).
##
##   [recursos]  Recursos     una frase
##   [construir] Extraer      una frase
##   [mercado]   Edificios    una frase
##   [estrella]  Progreso     una frase
##
## Cada tarjeta dice UNA frase (UI2M_QG_*_S); tocarla despliega el texto entero
## (QG_*_B) en la misma tarjeta, y tocarla otra vez lo pliega. No pausa: tapa la
## pantalla y se lleva los toques, y el tutorial no se ensena mientras esta
## abierta (TutorialPanel). Avisa con `closed`.

signal closed()

const CT := preload("res://scripts/ui/CartoonTheme.gd")

const LAYER := 33
const MAX_SIZE := Vector2(980, 600)
## Las cuatro secciones: titulo, frase corta y cuerpo entero (claves de Tr; el
## cuerpo con Tr.ti).
const SECTIONS := [
	["QG_RESOURCES_T", "UI2M_QG_RESOURCES_S", "QG_RESOURCES_B"],
	["QG_EXTRACT_T", "UI2M_QG_EXTRACT_S", "QG_EXTRACT_B"],
	["QG_BUILDINGS_T", "UI2M_QG_BUILDINGS_S", "QG_BUILDINGS_B"],
	["QG_PROGRESS_T", "UI2M_QG_PROGRESS_S", "QG_PROGRESS_B"],
]
## El icono de cada seccion (CartoonIcon, o "res:" para un recurso).
const SECTION_ICONS := ["res:wood", "wrench", "build", "star"]
## El pie: "Manten pulsado para leer" (con Tr.ti: con raton dice "pasa el raton").
const READ_HINT := "QG_READ_HINT"

var _root: Control
var _window: Control
var _card: PanelContainer
var _grid: GridContainer
var _open := false
var _small := false
## Tarjeta -> su texto entero (escondido hasta tocarla).
var _details: Array[Label] = []

func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("quick_guide")
	_build()
	visible = false
	get_viewport().size_changed.connect(_relayout)

func _build() -> void:
	_small = CT.is_phone()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_root.add_child(CT.veil())
	var w := CT.menu_window(Tr.t("UI2M_QG_TITLE"), CT.sem("INFO"), _small)
	_window = w["root"]
	_window.name = "QuickGuideWindow"
	_root.add_child(_window)
	_card = w["panel"]
	(w["close"] as Button).name = "QuickGuideClose"
	(w["close"] as Button).tooltip_text = Tr.t("BTN_CLOSE")
	(w["close"] as Button).pressed.connect(close)
	var column: VBoxContainer = w["body"]

	var scroll := ScrollContainer.new()
	scroll.name = "QuickGuideScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_grid)
	for i in SECTIONS.size():
		_grid.add_child(_section_card(SECTIONS[i], SECTION_ICONS[i]))

	# Como leer lo que no esta escrito: con el raton, el globo; con el dedo,
	# mantener pulsado (TouchTooltip). Una linea, bajo las cuatro tarjetas.
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	column.add_child(foot)
	var read := CT.para(Tr.ti(READ_HINT), "window", true, "small")
	read.name = "QuickGuideReadHint"
	read.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(read)
	var ok := CT.text_button(Tr.t("QG_OK"), "build", "primary", CT.menu_h("btn"))
	ok.name = "QuickGuideOk"
	ok.pressed.connect(close)
	foot.add_child(ok)

## Una tarjeta: [icono] Titulo / una frase; tocarla despliega el texto entero.
func _section_card(sec: Array, glyph: String) -> Button:
	var btn := Button.new()
	btn.name = "Block_" + String(sec[0]).trim_prefix("QG_").trim_suffix("_T").to_lower()
	btn.focus_mode = Control.FOCUS_ALL
	btn.toggle_mode = true
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var n := CT.card_style("window")
	var sel := CT.card_style("window", true)
	for sb in [n, sel]:
		sb.set_content_margin_all(10)
	btn.add_theme_stylebox_override("normal", n)
	btn.add_theme_stylebox_override("hover", n)
	btn.add_theme_stylebox_override("pressed", sel)
	btn.add_theme_stylebox_override("hover_pressed", sel)
	btn.add_theme_stylebox_override("focus", CT.box(Color(0, 0, 0, 0), CT.sem("ACCENT"), 3, CT.RADIUS_CARD + 2, 0))
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 12
	box.offset_right = -12
	box.offset_top = 8
	box.offset_bottom = -8
	btn.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(head)
	var ic := CT.make_glyph(glyph, 30 if _small else 36)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(ic)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(titles)
	titles.add_child(CT.label(Tr.t(String(sec[0])), "button", CT.text("window")))
	var short := CT.para(Tr.ti(String(sec[1])), "window", true, "small")
	titles.add_child(short)
	var more := CT.make_glyph("plus", 22)
	more.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(more)
	var detail := CT.para(Tr.ti(String(sec[2])), "window", false, "body")
	detail.name = "Detail"
	detail.visible = false
	box.add_child(detail)
	_details.append(detail)
	btn.toggled.connect(func(on: bool): detail.visible = on)
	# El boton no crece con sus hijos: se le pasa el alto que pide el texto.
	box.minimum_size_changed.connect(func():
		btn.custom_minimum_size.y = box.get_combined_minimum_size().y + 16.0)
	btn.custom_minimum_size.y = 72.0
	return btn

func _relayout() -> void:
	if _window == null or not is_inside_tree():
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	CT.place_window(_window, vp, MAX_SIZE, _small)
	# Dos columnas si caben (tablet y PC en horizontal, y el telefono apaisado).
	_grid.columns = 2 if minf(MAX_SIZE.x, vp.x) >= 600.0 else 1

func open() -> void:
	_open = true
	visible = true
	_relayout()

func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	closed.emit()

func is_open() -> bool:
	return _open

func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_ESCAPE or event.keycode == KEY_ENTER):
		close()
		get_viewport().set_input_as_handled()
