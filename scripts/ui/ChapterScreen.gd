extends CanvasLayer
## La pantalla corta de cierre de capitulo (feat/ritmo-colono, docs/06
## §Capitulos): "CAPITULO I COMPLETO · Nadie nos mira", una frase del lore, el
## capitulo que empieza con su objetivo y ¡ADELANTE!. Una tarjeta, nada mas.
##
## La crea ObjectivePanel (¿QUE HACER?, que tambien ensena el objetivo del
## capitulo) en las dos escenas, asi que no es un nodo mas de Main.tscn ni de
## Main2D.tscn. Escucha `chapter_completed` (ProgressionManager). Espera a que no
## haya tablero abierto ni otro parte en pantalla: un cierre de capitulo no
## interrumpe una pelea. El capitulo III no saca tarjeta: lo cierra la victoria
## (VictoryScreen). Sin estado de partida: si se cierra el juego antes de verla,
## no vuelve (ProgressionManager ya apunto el capitulo como cerrado).

const CT := preload("res://scripts/ui/CartoonTheme.gd")
const Chapters := preload("res://scripts/services/Chapters.gd")

const LAYER := 19
const CARD_WIDTH := 460.0

var _root: Control
var _win: Dictionary = {}
var _title: Label
var _close_line: Label
var _next_head: Label
var _next_goal: Label
## Capitulos cerrados que esperan su tarjeta.
var _queue: Array = []
var _current: int = 0

func _ready() -> void:
	layer = LAYER
	name = "ChapterScreen"
	add_to_group("modal_screen")
	add_to_group("chapter_screen")
	_setup_ui()
	visible = false
	set_process(false)
	EventBus.chapter_completed.connect(_on_chapter_completed)
	EventBus.game_new_started.connect(_clear)
	EventBus.game_load_completed.connect(_clear)
	# La victoria cierra el capitulo III y abre su pantalla (EL LIBRO): una tarjeta
	# de capitulo que quedara pendiente o a la vista no se queda detras.
	EventBus.victory_achieved.connect(_on_victory)
	get_viewport().size_changed.connect(_relayout)

func _setup_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_win = CT.modal_window(_root, Tr.t("CHAPTER_DONE") % "I", CT.sem("ACCENT"))
	(_win["close"] as Button).pressed.connect(close_current)
	var body: VBoxContainer = _win["body"]
	body.add_theme_constant_override("separation", 8)
	_title = _centered(CT.label("", "title", CT.text("window")))
	_title.name = "ChapterTitle"
	body.add_child(_title)
	_close_line = _centered(CT.label("", "body", CT.text("window")))
	_close_line.name = "ChapterLore"
	body.add_child(_close_line)
	_next_head = _centered(CT.label("", "small", CT.text("window", true)))
	_next_head.name = "NextChapter"
	body.add_child(_next_head)
	_next_goal = _centered(CT.label("", "body", CT.text("window")))
	_next_goal.name = "NextGoal"
	body.add_child(_next_goal)
	var go := CT.pill_button(Tr.t("BTN_CHAPTER_GO"), "next", "primary", CT.h("big"))
	go.name = "Onward"
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	go.pressed.connect(close_current)
	body.add_child(go)

static func _centered(l: Label) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _relayout() -> void:
	if not is_inside_tree() or _win.is_empty():
		return
	CT.fit_card(_win, get_viewport().get_visible_rect().size, CARD_WIDTH)

func _on_chapter_completed(chapter: int) -> void:
	# El III lo cierra la victoria.
	if chapter >= Chapters.COUNT:
		return
	_queue.append(chapter)
	set_process(true)

func _on_victory(_stats: Dictionary = {}) -> void:
	_clear()

func _clear() -> void:
	_queue.clear()
	if visible:
		close_current()

func _process(_delta: float) -> void:
	if not try_show_next():
		set_process(not _queue.is_empty() and not visible)

## Saca la siguiente tarjeta si no hay tablero abierto ni otro parte a la vista.
## true si la ensena. Publico para las pruebas.
func try_show_next() -> bool:
	if visible or _queue.is_empty():
		return false
	if CombatManager.is_board_open() or _other_modal_up():
		return false
	_current = int(_queue.pop_front())
	_paint(_current)
	visible = true
	_relayout()
	_relayout.call_deferred()
	return true

func _other_modal_up() -> bool:
	for n in get_tree().get_nodes_in_group("modal_screen"):
		if n == self:
			continue
		if n.has_method("is_showing"):
			if bool(n.call("is_showing")):
				return true
		elif n is CanvasLayer and (n as CanvasLayer).visible:
			return true
	return false

func _paint(chapter: int) -> void:
	CT.set_ribbon(_win, Tr.t("CHAPTER_DONE") % ["I", "II", "III"][clampi(chapter, 1, Chapters.COUNT) - 1], CT.sem("ACCENT"))
	_title.text = Chapters.title(chapter)
	_close_line.text = Chapters.close_text(chapter)
	var next: int = chapter + 1
	_next_head.text = Tr.t("CHAPTER_NEXT") % Chapters.heading(next)
	_next_goal.text = Chapters.goal_text(next)

func close_current() -> void:
	visible = false
	_current = 0
	set_process(not _queue.is_empty())

func is_showing() -> bool:
	return visible

func current_chapter() -> int:
	return _current

func pending_count() -> int:
	return _queue.size()

func title_text() -> String:
	return _title.text
