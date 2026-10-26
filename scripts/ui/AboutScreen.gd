extends CanvasLayer
## "De que va" (tutorial corto, decision de Bryan 2026-10-24): la PRIMERA pantalla
## de una partida nueva, antes del lore. Que es el juego y cual es la meta, en dos
## o tres frases, y tres iconos:
##
##   [construir] Construye y junta recursos
##   [ejercito]  Entrena tu ejercito
##   [tormenta]  Aguanta la Tormenta y gana
##
##                                   [ ¡VAMOS! ]
##
## Despues sale el lore corto (PrologueScreen, dos folios) y el tutorial practico.
## La abre TutorialPanel cuando TutorialManager pide el prologo de una partida
## nueva (no cuando se pide "Historia" desde el menu). No pausa: tapa la pantalla
## y se lleva los toques. Avisa con `closed`.

signal closed()

const CT := preload("res://scripts/ui/CartoonTheme.gd")

const LAYER := 33
const MAX_SIZE := Vector2(760, 520)
## Los tres bloques: glifo de CartoonIcon y su frase (clave de Tr).
const BLOCKS := [["build", "ABOUT_BUILD"], ["army", "ABOUT_ARMY"], ["storm", "ABOUT_STORM"]]

var _root: Control
var _window: Control
var _row: BoxContainer
var _open := false
var _small := false

func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("about_screen")
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
	var w := CT.menu_window(Tr.t("ABOUT_TITLE"), CT.sem("INFO"), _small, false)
	_window = w["root"]
	_window.name = "AboutWindow"
	_root.add_child(_window)
	var column: VBoxContainer = w["body"]
	column.add_theme_constant_override("separation", 12)

	var scroll := ScrollContainer.new()
	scroll.name = "AboutScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 14)
	scroll.add_child(inner)

	var body := CT.para(Tr.t("ABOUT_BODY"), "window", false, "body")
	body.name = "AboutBody"
	inner.add_child(body)

	_row = HBoxContainer.new()
	_row.name = "AboutBlocks"
	_row.add_theme_constant_override("separation", 12)
	inner.add_child(_row)
	for b in BLOCKS:
		_row.add_child(_block(String(b[0]), Tr.t(String(b[1]))))

	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(foot)
	var ok := CT.text_button(Tr.t("ABOUT_OK"), "next", "primary", CT.menu_h("btn"))
	ok.name = "AboutOk"
	ok.pressed.connect(close)
	foot.add_child(ok)

## Un bloque: el icono grande y su frase debajo.
func _block(glyph: String, text_s: String) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	var ic := CT.make_glyph(glyph, 40 if _small else 56)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(ic)
	var l := CT.para(text_s, "window", false, "small")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)
	return box

func _relayout() -> void:
	if _window == null or not is_inside_tree():
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	CT.place_window(_window, vp, MAX_SIZE, _small)

func open() -> void:
	_open = true
	visible = true
	_relayout()

## `silent`: se cierra sin avisar (quien la cierra no quiere el lore detras).
func close(silent: bool = false) -> void:
	if not _open:
		return
	_open = false
	visible = false
	if not silent:
		closed.emit()

func is_open() -> bool:
	return _open

## La frase de cada bloque, en orden (pruebas).
func block_texts() -> Array:
	var out: Array = []
	for b in BLOCKS:
		out.append(Tr.t(String(b[1])))
	return out

func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_ESCAPE or event.keycode == KEY_ENTER):
		close()
		get_viewport().set_input_as_handled()
