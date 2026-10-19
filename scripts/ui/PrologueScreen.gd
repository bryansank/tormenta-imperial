extends CanvasLayer
## El prologo: el lore contado como un expediente de la Regencia sobre nuestra
## isla. Pantalla completa, papel, maquina de escribir, sello de lacre y, en el
## margen, las notas a mano de los Amortizados, que cuentan lo que el papel calla.
##
## Es a proposito lo contrario del tutorial: el tutorial es laton sobre el mapa
## y dice que tocar; esto es un documento que se lee y no pide nada. Antes los
## dos iban en el mismo modal y el jugador se saltaba las diez paginas o leia
## instrucciones sin ver donde se aplicaban (docs/07 bug 12).
##
##   Saltar historia   ● ● ○   ◀ Atras   Siguiente ▶
##
## - Atras y Siguiente, y deslizar el dedo a izquierda o derecha. Flechas, Intro
##   y Esc en teclado.
## - El texto sale entero, de golpe (sin maquina de escribir ni tampon que cae:
##   rediseno 2026-10, docs/28 §0.6 "sin animacion").
## - Estilo nuevo (fase 2, docs/28): el folio es una ventana crema con borde
##   grueso y letra redonda (Baloo 2 / Nunito Sans); la nota al margen conserva
##   su letra a mano. Las laminas (PrologueEngraving), el sello y el tampon se
##   quedan como estaban.
## - Pausa el juego mientras esta abierto (si no lo estaba ya) y se procesa
##   siempre: se reabre desde el menu de pausa con el arbol parado.
##
## No sabe de partidas ni de modos: quien lo abre (TutorialPanel, a peticion de
## TutorialManager) le dice que variante contar. Avisa con `closed`.

signal closed()
signal page_changed(index: int)

## Encima de todo, tambien de la pausa y del menu principal (30): cuando se abre
## es lo unico que hay en pantalla.
const LAYER := 32
const CT := preload("res://scripts/ui/CartoonTheme.gd")

## Paginas por variante, cuatro como mucho: el prologo se lee de un tiron y el
## detalle queda para la partida. Cada una son claves PRO_<id>_TITLE/_BODY/_NOTE y, si la
## pagina lleva sello de tampon, PRO_<id>_STAMP. La "4" (2026-10-04) es la hoja
## final antes de jugar: que vamos a hacer (construir desde cero, economia,
## soldados, pelear contra el Imperio), sin instrucciones de botones.
const VARIANTS := {
	"full": ["1", "2", "3", "4"],
	# Constructor: no hay Tormenta ni Diezmo que explicar. La portada y un cierre
	# propio: el expediente esta "en tramite" y no se despacha ceniza.
	"short": ["1", "B"],
}
const STAMPED := ["1", "3", "B"]

## Caracteres por segundo de la maquina de escribir, y tope de lo que dura.
const TYPE_CPS := 80.0
const TYPE_MAX_SEC := 3.0
## Deslizamiento minimo (px de lienzo) para pasar de pagina.
const SWIPE_MIN := 70.0
const SHEET_MAX := Vector2(860, 640)
const FOOTER_H := 64.0
const EDGE := 16.0
## La lamina (PrologueEngraving, 2026-10-18): al lado del texto si el folio es
## ancho, encima si es estrecho, y fuera si no cabe (ver layout_for).
const ART_SIDE_MIN_W := 600.0
const ART_TOP_MIN_H := 330.0
## Lo que el sello de lacre ocupa al pie de la columna de la lamina.
const SEAL_ROOM := 96.0

var _variant := "full"
var _pages: Array = []
var _page := 0
var _open := false
var _paused_by_me := false
var _typing: Tween = null
var _swipe_from := Vector2.INF

var _root: Control
var _sheet: Control
var _paper: TextureRect
var _frame: Panel
var _title: Label
var _folio: Label
var _scroll: ScrollContainer
var _content: BoxContainer
var _art_col: VBoxContainer
var _art: Control
var _seal_room: Control
var _body: Label
var _note: Label
var _seal: Control
var _stamp: PanelContainer
var _stamp_label: Label
var _dots: HBoxContainer
var _hint: Label
var _back_btn: Button
var _next_btn: Button
var _skip_btn: Button

func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("prologue_screen")
	_build()
	visible = false
	get_viewport().size_changed.connect(_relayout)

# ── API ──────────────────────────────────────────────────────────────

func open(variant: String = "full") -> void:
	_variant = variant if VARIANTS.has(variant) else "full"
	_pages = VARIANTS[_variant]
	_page = 0
	_open = true
	visible = true
	if is_inside_tree() and not get_tree().paused:
		get_tree().paused = true
		_paused_by_me = true
	_rebuild_dots()
	_relayout()
	_render(true)
	_next_btn.grab_focus.call_deferred()

## Cerrar es cerrar: leido entero o saltado, el prologo queda visto.
func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	_stop_typing()
	if _paused_by_me and is_inside_tree():
		_paused_by_me = false
		get_tree().paused = false
	closed.emit()

func is_open() -> bool:
	return _open

func current_page() -> int:
	return _page

func page_count() -> int:
	return _pages.size()

func variant() -> String:
	return _variant

func is_typing() -> bool:
	return _typing != null and _typing.is_valid() and _typing.is_running()

func next_page() -> void:
	if not _open:
		return
	if is_typing():
		_finish_typing()
		return
	if _page >= _pages.size() - 1:
		close()
		return
	_page += 1
	_render(true)

func prev_page() -> void:
	if not _open or _page <= 0:
		return
	_page -= 1
	# Hacia atras ya se leyo: sin maquina de escribir.
	_render(false)

func go_to_page(index: int) -> void:
	if not _open:
		return
	_page = clampi(index, 0, _pages.size() - 1)
	_render(false)

func back_button() -> Button:
	return _back_btn

func next_button() -> Button:
	return _next_btn

func skip_button() -> Button:
	return _skip_btn

func body_text() -> String:
	return _body.text

func title_text() -> String:
	return _title.text

## La lamina del folio (PrologueEngraving). Publico para las pruebas.
func art() -> Control:
	return _art

## Donde va la lamina en un folio de `sheet` px: "side" (columna a la derecha
## del texto, `art` = su ancho), "top" (franja encima, `art` = su alto) o
## "none" (no cabe: solo texto). Pura, para las pruebas.
static func layout_for(sheet: Vector2) -> Dictionary:
	if sheet.x >= ART_SIDE_MIN_W:
		return {"mode": "side", "art": clampf(sheet.x * 0.36, 170.0, 320.0)}
	if sheet.y >= ART_TOP_MIN_H:
		return {"mode": "top", "art": clampf(sheet.y * 0.28, 90.0, 150.0)}
	return {"mode": "none", "art": 0.0}

# ── Construccion ─────────────────────────────────────────────────────

func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	# El fondo: la pizarra oscura del HUD, para que el folio sea lo unico claro.
	var desk := ColorRect.new()
	desk.set_anchors_preset(Control.PRESET_FULL_RECT)
	desk.color = CT.c("hud", "BG")
	desk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(desk)

	_sheet = Control.new()
	_sheet.name = "Sheet"
	_sheet.mouse_filter = Control.MOUSE_FILTER_PASS
	_sheet.gui_input.connect(_on_sheet_input)
	_root.add_child(_sheet)

	# El folio: la ventana crema del estilo nuevo, borde grueso y esquinas
	# redondas (docs/28 §6). `_paper` queda como el relleno, por compatibilidad.
	_paper = TextureRect.new()
	_paper.name = "Paper"
	_paper.set_anchors_preset(Control.PRESET_FULL_RECT)
	_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet.add_child(_paper)
	_frame = Panel.new()
	_frame.name = "Frame"
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame.add_theme_stylebox_override("panel", CT.window_style())
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet.add_child(_frame)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)

	# Sin membrete (2026-09-28): la linea "IMPERIO SIN OCASO · REGENCIA ·
	# CONTADURIA..." y el subtitulo del expediente cargaban la hoja de nombres
	# antes de contar nada. El folio empieza por su titulo.
	var title_row := HBoxContainer.new()
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(title_row)
	_title = CT.label("", "title", CT.text("window"))
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_row.add_child(_title)
	_folio = CT.label("", "small", CT.text("window", true))
	_folio.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	title_row.add_child(_folio)

	# Texto y lamina: lado a lado en un folio ancho, la lamina encima en uno
	# estrecho (BoxContainer.vertical, lo decide _relayout con layout_for).
	_content = BoxContainer.new()
	_content.name = "Content"
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 18)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_content)

	_scroll = ScrollContainer.new()
	# El prologo pasa folio deslizando: su texto no se arrastra (DragScroll).
	_scroll.set_meta("no_drag_scroll", true)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_content.add_child(_scroll)

	# La lamina del folio: un grabado a tinta (PrologueEngraving), con hueco
	# debajo para el sello de lacre cuando va al lado del texto.
	_art_col = VBoxContainer.new()
	_art_col.name = "ArtColumn"
	_art_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art_col.add_theme_constant_override("separation", 0)
	_content.add_child(_art_col)
	_art = preload("res://scripts/ui/PrologueEngraving.gd").new()
	_art.name = "Art"
	_art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_art_col.add_child(_art)
	_seal_room = Control.new()
	_seal_room.name = "SealRoom"
	_seal_room.custom_minimum_size = Vector2(0, SEAL_ROOM)
	_seal_room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art_col.add_child(_seal_room)
	var body_col := VBoxContainer.new()
	body_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_col.add_theme_constant_override("separation", 14)
	body_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(body_col)

	# 22 (antes 21): con la lamina al lado el folio ya no queda vacio y la
	# letra se lee mejor en tableta.
	_body = CT.label("", "body", CT.text("window"))
	_body.name = "Body"
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_col.add_child(_body)

	# La nota al margen: otra mano, otra tinta. Es la voz de los nuestros.
	_note = Label.new()
	_note.name = "Note"
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hf := UITheme.hand_font()
	if hf != null:
		_note.add_theme_font_override("font", hf)
	_note.add_theme_font_size_override("font_size", UITheme.scaled_font(30, UITheme.text_scale))
	_note.add_theme_color_override("font_color", UITheme.INK_NOTE)
	body_col.add_child(_note)

	# Sello de lacre, abajo a la derecha del folio.
	_seal = preload("res://scripts/ui/RegenciaSeal.gd").new()
	_seal.name = "Seal"
	_seal.set("letter_font", CT.title_font())
	_seal.set("ring_font", CT.bold_font())
	_seal.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_seal.offset_left = -118
	_seal.offset_top = -118
	_seal.offset_right = -26
	_seal.offset_bottom = -26
	_sheet.add_child(_seal)

	# El tampon: "FIRMADO" en la portada, "REABIERTO" al final.
	_stamp = PanelContainer.new()
	_stamp.name = "Stamp"
	var ss := StyleBoxFlat.new()
	ss.bg_color = Color(0, 0, 0, 0)
	ss.border_color = UITheme.SEAL_RED
	ss.set_border_width_all(4)
	ss.set_corner_radius_all(3)
	ss.content_margin_left = 16
	ss.content_margin_right = 16
	ss.content_margin_top = 4
	ss.content_margin_bottom = 4
	_stamp.add_theme_stylebox_override("panel", ss)
	_stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stamp_label = CT.label("", "display", UITheme.SEAL_RED)
	_stamp.add_child(_stamp_label)
	_stamp.visible = false
	_sheet.add_child(_stamp)

	# ── Pie: fuera del papel, sobre la mesa ──
	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.add_theme_constant_override("separation", 10)
	footer.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(footer)
	footer.set_meta("footer", true)

	_skip_btn = CT.text_button(Tr.t("BTN_PROLOGUE_SKIP"), "", "secondary", CT.menu_h("btn"))
	_skip_btn.name = "SkipButton"
	_skip_btn.pressed.connect(close)
	footer.add_child(_skip_btn)

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_child(mid)
	_dots = HBoxContainer.new()
	_dots.name = "Dots"
	_dots.alignment = BoxContainer.ALIGNMENT_CENTER
	_dots.add_theme_constant_override("separation", 10)
	_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(_dots)
	_hint = CT.label("", "small", CT.c("hud", "TEXT_DIM"))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(_hint)

	# Atras: redondo, solo la flecha (el nombre al mantener pulsado).
	_back_btn = CT.round_button("back", "secondary", CT.menu_h("btn"), "", "window") as Button
	_back_btn.name = "BackButton"
	_back_btn.tooltip_text = Tr.t("BTN_PROLOGUE_BACK")
	_back_btn.set_meta("text", Tr.t("BTN_PROLOGUE_BACK"))
	_back_btn.pressed.connect(prev_page)
	footer.add_child(_back_btn)

	_next_btn = CT.text_button(Tr.t("BTN_PROLOGUE_NEXT"), "next", "primary", CT.menu_h("btn"))
	_next_btn.name = "NextButton"
	_next_btn.pressed.connect(next_page)
	footer.add_child(_next_btn)

## Etiqueta de maquina de escribir (la letra de antes). Ya no se usa en el folio;
## se queda para quien la pida.
func _ink_label(text: String, px: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var f := UITheme.typewriter_font()
	if f != null:
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", UITheme.scaled_font(px, UITheme.text_scale))
	l.add_theme_color_override("font_color", color)
	return l

func _ink_rule() -> Control:
	var r := ColorRect.new()
	r.color = Color(UITheme.INK, 0.55)
	r.custom_minimum_size = Vector2(0, 2)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

func _ink_button(text: String, primary: bool) -> Button:
	return CT.text_button(text, "", "primary" if primary else "secondary", CT.menu_h("btn"))

## Cambia el texto de una pastilla (su etiqueta y la meta "text").
func _set_button_text(b: Button, text_s: String) -> void:
	b.set_meta("text", text_s)
	for l in b.find_children("*", "Label", true, false):
		(l as Label).text = text_s
		return

func _rebuild_dots() -> void:
	for d in _dots.get_children():
		d.queue_free()
	for i in _pages.size():
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(12, 12)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_dots.add_child(dot)

func _paint_dots() -> void:
	var i := 0
	for d in _dots.get_children():
		if d.is_queued_for_deletion():
			continue
		var s := StyleBoxFlat.new()
		s.set_corner_radius_all(6)
		var on := i == _page
		s.bg_color = CT.sem("ACCENT") if on else CT.c("hud", "CARD_ALT")
		s.border_color = CT.INK
		s.set_border_width_all(2)
		(d as Panel).add_theme_stylebox_override("panel", s)
		i += 1

# ── Paginas ──────────────────────────────────────────────────────────

func _render(typewriter: bool) -> void:
	var id: String = _pages[_page]
	_title.text = Tr.t("PRO_%s_TITLE" % id)
	_folio.text = Tr.t("PRO_FOLIO") % [_page + 1, _pages.size()]
	_body.text = Tr.t("PRO_%s_BODY" % id)
	_note.text = Tr.t("PRO_%s_NOTE" % id)
	_scroll.scroll_vertical = 0
	var last := _page >= _pages.size() - 1
	_back_btn.disabled = _page == 0
	_set_button_text(_next_btn, Tr.t("BTN_PROLOGUE_START") if last else Tr.t("BTN_PROLOGUE_NEXT"))
	_hint.text = Tr.ti("PRO_HINT")
	_paint_dots()
	_art.call("set_folio", id)
	_place_stamp(id)
	# Sin maquina de escribir (docs/28 §0.6): el folio sale entero, de golpe.
	# `typewriter` se queda en la firma por quien ya la llamaba.
	_finish_typing()
	page_changed.emit(_page)

func _finish_typing() -> void:
	_stop_typing()
	_body.visible_ratio = 1.0
	_note.modulate.a = 1.0
	_art.modulate.a = 1.0
	_stamp.scale = Vector2.ONE
	_stamp.modulate.a = 0.85

func _stop_typing() -> void:
	if _typing != null and _typing.is_valid():
		_typing.kill()
	_typing = null

func _place_stamp(id: String) -> void:
	_stamp.visible = id in STAMPED
	if not _stamp.visible:
		return
	_stamp_label.text = Tr.t("PRO_%s_STAMP" % id)
	_stamp.reset_size()
	var sz := _stamp.get_combined_minimum_size()
	_stamp.size = sz
	_stamp.pivot_offset = sz * 0.5
	_stamp.rotation_degrees = -9.0
	_stamp.position = stamp_position(_sheet.size, sz, Rect2())
	# Con la lamina a la vista, el tampon va encima de su parte de abajo (un
	# golpe sobre el grabado): se mira cuando los contenedores ya colocaron.
	_place_stamp_on_art.call_deferred()

## Donde cae el tampon de `stamp` px en un folio de `sheet` px. Con lamina
## (`art`, en coordenadas del folio) y sitio, sobre su parte de abajo,
## centrado; si no, en el blanco de abajo a la izquierda del sello, torcido
## como un golpe de tampon y nunca encima del texto. Pura, para las pruebas.
static func stamp_position(sheet: Vector2, stamp: Vector2, art: Rect2) -> Vector2:
	if art.size.x > stamp.x * 0.8 and art.size.y > stamp.y * 2.0:
		return Vector2(art.position.x + (art.size.x - stamp.x) * 0.5, art.end.y - stamp.y - art.size.y * 0.12)
	return Vector2(sheet.x - stamp.x - 150.0, sheet.y - stamp.y - 52.0)

func _place_stamp_on_art() -> void:
	if _stamp == null or not _stamp.visible or _art == null or not _art.is_visible_in_tree():
		return
	var r := Rect2(_art.global_position - _sheet.global_position, _art.size)
	_stamp.position = stamp_position(_sheet.size, _stamp.size, r)

func _relayout() -> void:
	if _sheet == null:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var w: float = minf(SHEET_MAX.x, vp.x - EDGE * 2.0)
	var h: float = minf(SHEET_MAX.y, vp.y - FOOTER_H - EDGE * 3.0)
	_sheet.position = Vector2((vp.x - w) * 0.5, maxf(EDGE, (vp.y - FOOTER_H - h) * 0.5 - EDGE * 0.5))
	_sheet.size = Vector2(w, h)
	_layout_art(Vector2(w, h))
	var footer: Control = _root.get_node("Footer")
	footer.offset_left = (vp.x - w) * 0.5
	footer.offset_right = -(vp.x - w) * 0.5
	footer.offset_top = -FOOTER_H - EDGE * 0.5
	footer.offset_bottom = -EDGE * 0.5
	if _open and not _pages.is_empty():
		_place_stamp(_pages[_page])

## Coloca la lamina segun layout_for: al lado (con hueco para el sello), encima
## o fuera. El texto conserva su scroll por si no cabe.
func _layout_art(sheet: Vector2) -> void:
	var lay := layout_for(sheet)
	match String(lay["mode"]):
		"side":
			_art_col.visible = true
			_content.vertical = false
			_content.move_child(_art_col, 1)
			_art_col.custom_minimum_size = Vector2(float(lay["art"]), 0)
			_seal_room.visible = true
		"top":
			_art_col.visible = true
			_content.vertical = true
			_content.move_child(_art_col, 0)
			_art_col.custom_minimum_size = Vector2(0, float(lay["art"]))
			_seal_room.visible = false
		_:
			_art_col.visible = false

# ── Entrada ──────────────────────────────────────────────────────────

func _on_sheet_input(event: InputEvent) -> void:
	# Un toque corto en el papel (sin deslizar) completa el texto.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_typing():
			_finish_typing()

func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_RIGHT, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				next_page()
			KEY_LEFT, KEY_BACKSPACE:
				prev_page()
			KEY_ESCAPE:
				close()
			_:
				return
		get_viewport().set_input_as_handled()
		return
	# Deslizar: vale el dedo y el raton. Un toque llega por los dos caminos (el
	# raton emulado); el primero que suelta decide y el segundo ya no tiene inicio.
	var press := false
	var release := false
	var pos := Vector2.ZERO
	if event is InputEventScreenTouch and event.index == 0:
		press = event.pressed
		release = not event.pressed
		pos = event.position
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		press = event.pressed
		release = not event.pressed
		pos = event.position
	else:
		return
	if press and _swipe_from == Vector2.INF:
		_swipe_from = pos
	elif release and _swipe_from != Vector2.INF:
		var d := pos - _swipe_from
		_swipe_from = Vector2.INF
		handle_swipe(d)

## Un gesto de `delta` pixeles. Publico para las pruebas.
func handle_swipe(delta: Vector2) -> bool:
	if absf(delta.x) < SWIPE_MIN or absf(delta.x) < absf(delta.y) * 1.5:
		return false
	if delta.x < 0.0:
		# Hacia la izquierda: la pagina siguiente, como pasar una hoja.
		if is_typing():
			_finish_typing()
		if _page < _pages.size() - 1:
			_page += 1
			_render(false)
	else:
		prev_page()
	get_viewport().set_input_as_handled()
	return true
