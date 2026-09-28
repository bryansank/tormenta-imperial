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
##   Saltar historia   ● ● ○ ○ ○ ○   ◀ Atras   Siguiente ▶
##
## - Atras y Siguiente, y deslizar el dedo a izquierda o derecha. Flechas, Intro
##   y Esc en teclado.
## - El texto se escribe solo; pulsar Siguiente (o tocar el papel) mientras se
##   escribe lo completa, y el segundo toque pasa de pagina.
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

## Paginas por variante. Cada una son claves PRO_<id>_TITLE/_BODY/_NOTE y, si la
## pagina lleva sello de tampon, PRO_<id>_STAMP.
const VARIANTS := {
	"full": ["1", "2", "3", "4", "5", "6"],
	# Constructor: no hay Tormenta ni Diezmo que explicar. La portada y un cierre
	# propio: el expediente esta "en tramite" y no se despacha ceniza.
	"short": ["1", "B"],
}
const STAMPED := ["1", "6", "B"]

## Caracteres por segundo de la maquina de escribir, y tope de lo que dura.
const TYPE_CPS := 80.0
const TYPE_MAX_SEC := 3.0
## Deslizamiento minimo (px de lienzo) para pasar de pagina.
const SWIPE_MIN := 70.0
const SHEET_MAX := Vector2(860, 640)
const FOOTER_H := 64.0
const EDGE := 16.0

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
var _letterhead: Label
var _subhead: Label
var _title: Label
var _folio: Label
var _scroll: ScrollContainer
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

# ── Construccion ─────────────────────────────────────────────────────

func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	# La mesa: casi negro con un grano pardo, para que el papel sea lo unico claro.
	var desk := ColorRect.new()
	desk.set_anchors_preset(Control.PRESET_FULL_RECT)
	desk.color = UITheme.DESK_BG
	desk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(desk)
	var grain := TextureRect.new()
	grain.set_anchors_preset(Control.PRESET_FULL_RECT)
	grain.texture = UITheme.desk_texture()
	grain.stretch_mode = TextureRect.STRETCH_TILE
	grain.modulate = Color(1, 1, 1, 0.5)
	grain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(grain)

	_sheet = Control.new()
	_sheet.name = "Sheet"
	_sheet.mouse_filter = Control.MOUSE_FILTER_PASS
	_sheet.gui_input.connect(_on_sheet_input)
	_root.add_child(_sheet)

	_paper = TextureRect.new()
	_paper.set_anchors_preset(Control.PRESET_FULL_RECT)
	_paper.texture = UITheme.parchment_texture()
	_paper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_paper.stretch_mode = TextureRect.STRETCH_SCALE
	_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet.add_child(_paper)
	# Bordes tostados del papel viejo.
	var burn := TextureRect.new()
	burn.set_anchors_preset(Control.PRESET_FULL_RECT)
	burn.texture = UITheme.parchment_edge_texture()
	burn.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	burn.stretch_mode = TextureRect.STRETCH_SCALE
	burn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet.add_child(burn)

	# Doble filete de impreso oficial.
	_frame = Panel.new()
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame.offset_left = 12
	_frame.offset_top = 12
	_frame.offset_right = -12
	_frame.offset_bottom = -12
	var fs := StyleBoxFlat.new()
	fs.bg_color = Color(0, 0, 0, 0)
	fs.border_color = Color(UITheme.INK, 0.45)
	fs.set_border_width_all(1)
	_frame.add_theme_stylebox_override("panel", fs)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet.add_child(_frame)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 44)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 22)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)

	_letterhead = _ink_label(Tr.t("PRO_LETTERHEAD"), 15, UITheme.INK_DIM)
	_letterhead.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_letterhead)
	_subhead = _ink_label(Tr.t("PRO_SUBHEAD"), 13, UITheme.INK_DIM)
	_subhead.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_subhead)
	col.add_child(_ink_rule())

	var title_row := HBoxContainer.new()
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(title_row)
	_title = _ink_label("", 29, UITheme.INK)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_row.add_child(_title)
	_folio = _ink_label("", 14, UITheme.INK_DIM)
	_folio.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	title_row.add_child(_folio)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(_scroll)
	var body_col := VBoxContainer.new()
	body_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_col.add_theme_constant_override("separation", 14)
	body_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(body_col)

	_body = _ink_label("", 21, UITheme.INK)
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
	_seal.set("letter_font", UITheme.typewriter_font())
	_seal.set("ring_font", UITheme.typewriter_font())
	_seal.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_seal.offset_left = -118
	_seal.offset_top = -118
	_seal.offset_right = -26
	_seal.offset_bottom = -26
	_sheet.add_child(_seal)

	# El tampon: "DADO DE BAJA" en la portada, "REABIERTO" al final.
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
	_stamp_label = _ink_label("", 34, UITheme.SEAL_RED)
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

	_skip_btn = _ink_button(Tr.t("BTN_PROLOGUE_SKIP"), false)
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
	_hint = _ink_label("", 13, UITheme.PARCHMENT_DARK)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(_hint)

	_back_btn = _ink_button("◀  " + Tr.t("BTN_PROLOGUE_BACK"), false)
	_back_btn.name = "BackButton"
	_back_btn.pressed.connect(prev_page)
	footer.add_child(_back_btn)

	_next_btn = _ink_button(Tr.t("BTN_PROLOGUE_NEXT") + "  ▶", true)
	_next_btn.name = "NextButton"
	_next_btn.pressed.connect(next_page)
	footer.add_child(_next_btn)

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
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, UITheme.MIN_BTN_H)
	UITheme.style_ink_button(b, primary)
	return b

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
		s.bg_color = UITheme.SEAL_RED if on else Color(UITheme.PARCHMENT_DARK, 0.35)
		s.border_color = UITheme.PARCHMENT
		s.set_border_width_all(1 if on else 0)
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
	_back_btn.modulate.a = 0.35 if _page == 0 else 1.0
	_next_btn.text = (Tr.t("BTN_PROLOGUE_START") if last else Tr.t("BTN_PROLOGUE_NEXT")) + "  ▶"
	_hint.text = Tr.ti("PRO_HINT")
	_paint_dots()
	_place_stamp(id)
	_stop_typing()
	if typewriter:
		_body.visible_ratio = 0.0
		_note.modulate.a = 0.0
		_stamp.modulate.a = 0.0
		var secs: float = minf(TYPE_MAX_SEC, float(_body.text.length()) / TYPE_CPS)
		_typing = create_tween()
		_typing.tween_property(_body, "visible_ratio", 1.0, secs)
		_typing.tween_property(_note, "modulate:a", 1.0, 0.35)
		if _stamp.visible:
			_stamp.scale = Vector2(1.6, 1.6)
			_typing.tween_property(_stamp, "modulate:a", 0.85, 0.08)
			_typing.parallel().tween_property(_stamp, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_finish_typing()
	page_changed.emit(_page)

func _finish_typing() -> void:
	_stop_typing()
	_body.visible_ratio = 1.0
	_note.modulate.a = 1.0
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
	# En el blanco de abajo, a la izquierda del sello, torcido como un golpe de
	# tampon. Nunca encima del texto: el texto ocupa la mitad alta del folio.
	_stamp.size = sz
	_stamp.pivot_offset = sz * 0.5
	_stamp.rotation_degrees = -9.0
	_stamp.position = Vector2(_sheet.size.x - sz.x - 150.0, _sheet.size.y - sz.y - 52.0)

func _relayout() -> void:
	if _sheet == null:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var w: float = minf(SHEET_MAX.x, vp.x - EDGE * 2.0)
	var h: float = minf(SHEET_MAX.y, vp.y - FOOTER_H - EDGE * 3.0)
	_sheet.position = Vector2((vp.x - w) * 0.5, maxf(EDGE, (vp.y - FOOTER_H - h) * 0.5 - EDGE * 0.5))
	_sheet.size = Vector2(w, h)
	var footer: Control = _root.get_node("Footer")
	footer.offset_left = (vp.x - w) * 0.5
	footer.offset_right = -(vp.x - w) * 0.5
	footer.offset_top = -FOOTER_H - EDGE * 0.5
	footer.offset_bottom = -EDGE * 0.5
	if _open and not _pages.is_empty():
		_place_stamp(_pages[_page])

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
