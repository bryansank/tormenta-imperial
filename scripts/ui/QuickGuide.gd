extends CanvasLayer
## La guia rapida: como funciona el juego en una sola pantalla, en cuatro
## bloques cortos (2026-09-28). Sale UNA vez por partida, al cerrar el prologo y
## antes del tutorial guiado; despues vive en AYUDA (HelpCatalog: guide_*), con
## los mismos textos.
##
##   RECURSOS    que hay, cuando llega cada uno, el almacen y el taller
##   EXTRAER     a mano se agota; con su edificio especializado, no
##   EDIFICIOS   trabajadores, viviendas y carretera hasta el Nucleo
##   PROGRESO    eras, arbol tecnologico y la Tormenta
##
## No es el lore (eso es el prologo) ni el tutorial (eso son las marcas sobre la
## interfaz): es la chuleta que el jugador lee de un vistazo. No pausa (el
## prologo pauso y ya lo solto): tapa la pantalla y se lleva los toques, y el
## tutorial no se ensena mientras esta abierta (TutorialPanel). Avisa con `closed`.

signal closed()

const LAYER := 33
const MAX_WIDTH := 980.0
## Las cuatro secciones: titulo y cuerpo (claves de Tr; el cuerpo con Tr.ti).
const SECTIONS := [
	["QG_RESOURCES_T", "QG_RESOURCES_B"],
	["QG_EXTRACT_T", "QG_EXTRACT_B"],
	["QG_BUILDINGS_T", "QG_BUILDINGS_B"],
	["QG_PROGRESS_T", "QG_PROGRESS_B"],
]

var _root: Control
var _card: PanelContainer
var _grid: GridContainer
var _open := false

func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("quick_guide")
	_build()
	visible = false
	get_viewport().size_changed.connect(_relayout)

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_root.add_child(ModalKit.make_backdrop(0.75))
	_card = ModalKit.make_card(10)
	_root.add_child(_card)
	var column: VBoxContainer = _card.get_child(0)
	column.add_child(ModalKit.make_text(Tr.t("QG_TITLE"), "title", UITheme.ACCENT))
	column.add_child(UITheme.make_separator())
	var scroll := ScrollContainer.new()
	scroll.name = "QuickGuideScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 16)
	_grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_grid)
	for sec in SECTIONS:
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation", 4)
		box.add_child(ModalKit.make_text(Tr.t(String(sec[0])), "section", UITheme.ACCENT))
		var body := ModalKit.make_text(Tr.ti(String(sec[1])), "body", UITheme.TEXT)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size.x = 200
		box.add_child(body)
		_grid.add_child(box)
	var ok := ModalKit.make_menu_button(Tr.t("QG_OK"), UITheme.POSITIVE, close)
	ok.name = "QuickGuideOk"
	column.add_child(ok)

func _relayout() -> void:
	if _card == null:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	ModalKit.fit_center(_card, MAX_WIDTH, vp)
	# Dos columnas si caben (tablet y PC en horizontal), una en un movil.
	_grid.columns = 2 if _card.custom_minimum_size.x >= 640.0 else 1
	var scroll := _grid.get_parent() as ScrollContainer
	scroll.custom_minimum_size.y = clampf(vp.y - 220.0, 160.0, 520.0)

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
