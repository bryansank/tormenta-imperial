extends CanvasLayer
## El panel del tutorial. Dos piezas en una capa:
##  - la intro paginada (modal, con fondo oscuro): el lore entero y despues
##    como se juega, con "Siguiente" y un "Saltar" siempre a la vista;
##  - la tarjeta de consejo (no modal, abajo al centro): el juego sigue detras,
##    y se quita con "Entendido".
##
## No decide nada: TutorialManager dice que ensenar y cuando, por EventBus. Este
## panel solo pinta y avisa de vuelta cuando la intro se cierra, que es lo que la
## marca como vista. Asi el manager se prueba sin escena y el panel sin partida.

## Las paginas, en orden. Primero el mundo (03_LORE.md condensado), despues como
## se juega. Los textos viven en Tr; aqui solo las claves.
const PAGES := [
	{"title": "TUT_INTRO_1_TITLE", "body": "TUT_INTRO_1_BODY", "section": "LBL_TUTORIAL_SECTION_LORE"},
	{"title": "TUT_INTRO_2_TITLE", "body": "TUT_INTRO_2_BODY", "section": "LBL_TUTORIAL_SECTION_LORE"},
	{"title": "TUT_INTRO_3_TITLE", "body": "TUT_INTRO_3_BODY", "section": "LBL_TUTORIAL_SECTION_LORE"},
	{"title": "TUT_INTRO_4_TITLE", "body": "TUT_INTRO_4_BODY", "section": "LBL_TUTORIAL_SECTION_LORE"},
	{"title": "TUT_INTRO_5_TITLE", "body": "TUT_INTRO_5_BODY", "section": "LBL_TUTORIAL_SECTION_LORE"},
	{"title": "TUT_INTRO_6_TITLE", "body": "TUT_INTRO_6_BODY", "section": "LBL_TUTORIAL_SECTION_LORE"},
	{"title": "TUT_PLAY_1_TITLE", "body": "TUT_PLAY_1_BODY", "section": "LBL_TUTORIAL_SECTION_PLAY"},
	{"title": "TUT_PLAY_2_TITLE", "body": "TUT_PLAY_2_BODY", "section": "LBL_TUTORIAL_SECTION_PLAY"},
	{"title": "TUT_PLAY_3_TITLE", "body": "TUT_PLAY_3_BODY", "section": "LBL_TUTORIAL_SECTION_PLAY"},
	{"title": "TUT_PLAY_4_TITLE", "body": "TUT_PLAY_4_BODY", "section": "LBL_TUTORIAL_SECTION_PLAY"},
]

## Por encima de los globos del HelperPanel (14), de los modales (15) y del
## indicador de la Tormenta (16): mientras se lee la intro no hay nada mas
## importante en pantalla. Solo el tablero (18) y la victoria (20) quedan arriba.
const INTRO_LAYER := 17
## Tamano maximo de la tarjeta de la intro; se recorta al viewport para que en
## una pantalla estrecha (400x720) no se salga.
const CARD_MAX := Vector2(760, 560)
## Ancho de la tarjeta de consejo.
const TIP_WIDTH := 480.0
## Hueco que se deja bajo la tarjeta de consejo: el boton CONSTRUIR vive en el
## slot bottom_center (20 px del borde, ~50 de alto) y no hay que taparlo.
const TIP_BOTTOM_GAP := 88.0
## Margen minimo a los bordes de pantalla.
const EDGE := 16.0

var _root: Control
var _backdrop: ColorRect
var _card: PanelContainer
var _title_label: Label
var _section_label: Label
var _scroll: ScrollContainer
var _body_label: Label
var _page_label: Label
var _next_btn: Button
var _skip_btn: Button
var _page := 0
var _intro_open := false

var _tip_card: PanelContainer
var _tip_title: Label
var _tip_body: Label
var _tip_showing := false
## Consejos que llegaron mientras habia otro (o la intro) en pantalla. Se
## ensenan de uno en uno: dos tarjetas a la vez no se leen ninguna.
var _tip_queue: Array[Dictionary] = []

func _ready() -> void:
	layer = INTRO_LAYER
	_setup_ui()
	# En la pila de UIManager para que ESC lo cierre y para que el resto de la
	# interfaz sepa que hay un modal abierto (los globos del tutorial viejo se
	# esconden por eso). El id no esta en UILayoutConfig.PANEL_SLOTS a proposito:
	# tocar ese archivo es de otro agente, y sin slot UIManager solo lo apila.
	UIManager.register_panel(self, "TutorialPanel")
	# La pila reasigna `layer` a 12+posicion cada vez que se abre o cierra una
	# ventana, y eso dejaria la intro debajo de los globos (14). Se vuelve a
	# fijar despues de cada cambio de pila mientras la intro este abierta.
	UIManager.window_opened.connect(_pin_layer)
	UIManager.window_closed.connect(_pin_layer)

	EventBus.tutorial_intro_requested.connect(_open_intro)
	EventBus.tutorial_tip_requested.connect(_on_tip_requested)
	UILayoutManager.layout_changed.connect(_fit_to_viewport)

# ── Construccion ─────────────────────────────────────────────────────

func _setup_ui() -> void:
	# El slot full_overlay de UILayoutConfig es exactamente esto: anclas 0..1 sin
	# margenes. Se aplica a mano porque el id de este panel no esta en
	# PANEL_SLOTS (ver _ready) y apply_layout avisaria de slot desconocido.
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_build_intro()
	_build_tip()

func _build_intro() -> void:
	# Fondo oscuro que come el clic: la intro es modal. No se cierra al pinchar
	# fuera a proposito, para eso esta "Saltar".
	_backdrop = UITheme.make_backdrop()
	_backdrop.visible = false
	_root.add_child(_backdrop)

	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", UITheme.make_war_table_style())
	_card.set_anchors_preset(Control.PRESET_CENTER)
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.grow_vertical = Control.GROW_DIRECTION_BOTH
	_card.visible = false
	_root.add_child(_card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UITheme.SEPARATION)
	_card.add_child(vbox)

	# La X de la cabecera es otro "Saltar": cerrar es cerrar.
	var header := UITheme.make_panel_header("", _close)
	_title_label = header.get_child(0) as Label
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(header)

	_section_label = UITheme.make_label("", "small", UITheme.TEXT_DIM)
	vbox.add_child(_section_label)

	vbox.add_child(UITheme.make_separator())

	# El cuerpo va en un scroll con la tarjeta a tamano fijo: si un idioma o una
	# pantalla baja no dan para el texto, se desplaza en vez de salirse.
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_scroll)

	_body_label = UITheme.make_label("", "body", UITheme.TEXT)
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body_label)

	vbox.add_child(UITheme.make_separator())

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", UITheme.SEPARATION)
	vbox.add_child(footer)

	_skip_btn = Button.new()
	_skip_btn.text = Tr.t("BTN_TUTORIAL_SKIP")
	_skip_btn.custom_minimum_size = Vector2(140, UITheme.MIN_BTN_H)
	UITheme.style_button(_skip_btn, UITheme.BTN, UITheme.FONT_BUTTON)
	_skip_btn.pressed.connect(_close)
	footer.add_child(_skip_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_child(spacer)

	_page_label = UITheme.make_label("", "small", UITheme.TEXT_DIM)
	_page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(_page_label)

	_next_btn = Button.new()
	_next_btn.text = Tr.t("BTN_TUTORIAL_NEXT")
	_next_btn.custom_minimum_size = Vector2(180, UITheme.MIN_BTN_H)
	UITheme.style_button(_next_btn, UITheme.ACCENT.darkened(0.2), UITheme.FONT_BUTTON)
	_next_btn.pressed.connect(_next_page)
	footer.add_child(_next_btn)

func _build_tip() -> void:
	_tip_card = PanelContainer.new()
	_tip_card.add_theme_stylebox_override("panel", UITheme.make_panel_style())
	# Abajo al centro, creciendo hacia arriba desde encima del boton CONSTRUIR.
	_tip_card.anchor_left = 0.5
	_tip_card.anchor_right = 0.5
	_tip_card.anchor_top = 1.0
	_tip_card.anchor_bottom = 1.0
	_tip_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_tip_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_tip_card.visible = false
	_root.add_child(_tip_card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_tip_card.add_child(vbox)

	_tip_title = UITheme.make_label("", "section", UITheme.WARNING)
	_tip_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_tip_title)

	_tip_body = UITheme.make_label("", "body", UITheme.TEXT)
	_tip_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_tip_body)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(row)

	var ok := Button.new()
	ok.text = Tr.t("BTN_TUTORIAL_OK")
	ok.custom_minimum_size = Vector2(150, UITheme.MIN_BTN_H)
	UITheme.style_button(ok, UITheme.ACCENT.darkened(0.2), UITheme.FONT_BUTTON)
	ok.pressed.connect(_dismiss_tip)
	row.add_child(ok)

## Recorta las dos tarjetas al viewport. Se repite al cambiar de tamano de
## ventana (pantalla completa, movil).
func _fit_to_viewport() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var w: float = minf(CARD_MAX.x, vp.x - EDGE * 2.0)
	var h: float = minf(CARD_MAX.y, vp.y - EDGE * 2.0)
	_card.custom_minimum_size = Vector2(w, h)
	_card.offset_left = -w * 0.5
	_card.offset_right = w * 0.5
	_card.offset_top = -h * 0.5
	_card.offset_bottom = h * 0.5

	var tw: float = minf(TIP_WIDTH, vp.x - EDGE * 2.0)
	_tip_card.custom_minimum_size = Vector2(tw, 0)
	_tip_card.offset_left = -tw * 0.5
	_tip_card.offset_right = tw * 0.5
	_tip_card.offset_bottom = -TIP_BOTTOM_GAP
	_tip_card.offset_top = -TIP_BOTTOM_GAP

# ── Intro ────────────────────────────────────────────────────────────

func _open_intro() -> void:
	_page = 0
	_intro_open = true
	_fit_to_viewport()
	_render_page()
	_backdrop.visible = true
	_card.visible = true
	UIManager.open_window(self)
	_pin_layer()

func _render_page() -> void:
	var p: Dictionary = PAGES[_page]
	_title_label.text = Tr.t(p["title"])
	_section_label.text = Tr.t(p["section"])
	_body_label.text = Tr.t(p["body"])
	_page_label.text = Tr.t("LBL_TUTORIAL_PAGE") % [_page + 1, PAGES.size()]
	var last: bool = _page >= PAGES.size() - 1
	_next_btn.text = Tr.t("BTN_TUTORIAL_START") if last else Tr.t("BTN_TUTORIAL_NEXT")
	_scroll.scroll_vertical = 0

func _next_page() -> void:
	if not _intro_open:
		return
	if _page >= PAGES.size() - 1:
		_close()
		return
	_page += 1
	_render_page()

## Salta a una pagina concreta. Para herramientas y pruebas; el jugador va con
## "Siguiente".
func go_to_page(index: int) -> void:
	if not _intro_open:
		return
	_page = clampi(index, 0, PAGES.size() - 1)
	_render_page()

## Cerrar es cerrar: leida entera o saltada, la intro queda vista. UIManager
## llama aqui con ESC.
func _close() -> void:
	if not _intro_open:
		return
	_intro_open = false
	_backdrop.visible = false
	_card.visible = false
	UIManager.close_window(self)
	EventBus.tutorial_intro_closed.emit()
	# Lo que llego mientras se leia, ahora.
	_show_next_tip()

func _pin_layer(_window: CanvasLayer = null) -> void:
	if _intro_open:
		layer = INTRO_LAYER

func is_intro_open() -> bool:
	return _intro_open

func current_page() -> int:
	return _page

func page_count() -> int:
	return PAGES.size()

# ── Consejos ─────────────────────────────────────────────────────────

func _on_tip_requested(tip_id: String, title: String, body: String) -> void:
	_tip_queue.append({"id": tip_id, "title": title, "body": body})
	_show_next_tip()

func _show_next_tip() -> void:
	if _tip_showing or _intro_open or _tip_queue.is_empty():
		return
	var tip: Dictionary = _tip_queue.pop_front()
	_tip_showing = true
	_fit_to_viewport()
	_tip_title.text = String(tip["title"])
	_tip_body.text = String(tip["body"])
	_tip_card.visible = true
	# Un fundido corto para que entre en vez de aparecer: llama la vista sin
	# interrumpir.
	_tip_card.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_tip_card, "modulate:a", 1.0, 0.25)

func _dismiss_tip() -> void:
	_tip_showing = false
	_tip_card.visible = false
	_show_next_tip()

func is_tip_showing() -> bool:
	return _tip_showing

func pending_tips() -> int:
	return _tip_queue.size()
