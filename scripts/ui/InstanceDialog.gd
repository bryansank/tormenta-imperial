extends CanvasLayer
## El aviso y la pregunta de una sola copia abierta (InstanceGuard). Sale antes de
## cargar la partida, por encima de todo (incluido el menu principal), y lo crea
## GameManager colgando de si mismo.
##
##   CHECKING       "Comprobando si hay otra copia abierta...", sin botones:
##                  mientras GameManager espera a que se aclaren copias sueltas.
##   ALREADY_OPEN   "Tormenta Imperial ya está abierto" y un boton Cerrar; se
##                  cierra solo a los AUTO_CLOSE segundos. Emite `declined`.
##   OTHER_VERSION  "Está abierta la versión X. ¿Cerrarla y abrir esta (Y)?" con
##                  SÍ (`accepted`) y NO (`declined`). Tras el SÍ, GameManager
##                  llama a show_waiting() y, si la otra no muere, a show_failed().
## show_action() cambia de uno a otro sin cerrar el dialogo.

signal accepted
signal declined

const Guard := preload("res://scripts/services/InstanceGuard.gd")
const LAYER := 100
const MAX_WIDTH := 560.0
const AUTO_CLOSE := 4.0
## Ninguna accion de InstanceGuard.Action: el estado de espera.
const CHECKING := -1

var _action: int = Guard.Action.ALREADY_OPEN
var _other_version := ""
var _my_version := ""
var _card: PanelContainer
var _column: VBoxContainer
var _done := false

## Antes de add_child. `other_version` vacio = una version anterior sin numero.
func setup(action: int, other_version: String, my_version: String) -> void:
	_action = action
	_other_version = other_version
	_my_version = my_version

func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	root.add_child(ModalKit.make_backdrop(0.85))
	_card = ModalKit.make_card()
	_column = _card.get_child(0) as VBoxContainer
	root.add_child(_card)
	_build()
	_fit()
	get_viewport().size_changed.connect(_fit)

func _fit() -> void:
	ModalKit.fit_center(_card, MAX_WIDTH, get_viewport().get_visible_rect().size)

## Cambia lo que dice: CHECKING, ALREADY_OPEN u OTHER_VERSION.
func show_action(action: int, other_version: String) -> void:
	_action = action
	_other_version = other_version
	if is_node_ready():
		_clear()
		_build()

func _build() -> void:
	if _action == CHECKING:
		_column.add_child(ModalKit.make_text(Tr.t("LBL_INSTANCE_CHECKING"), "section", UITheme.ACCENT))
	elif _action == Guard.Action.OTHER_VERSION:
		_build_question()
	else:
		_build_already_open()
	if is_node_ready():
		_fit.call_deferred()

func _clear() -> void:
	for child in _column.get_children():
		_column.remove_child(child)
		child.queue_free()

func _build_already_open() -> void:
	_column.add_child(ModalKit.make_text(Tr.t("LBL_INSTANCE_ALREADY_OPEN"), "section", UITheme.ACCENT))
	_column.add_child(ModalKit.make_text(Tr.t("LBL_INSTANCE_ALREADY_OPEN_BODY")))
	var btn := ModalKit.make_menu_button(Tr.t("BTN_CLOSE"), UITheme.BTN, _decline)
	_column.add_child(btn)
	btn.grab_focus.call_deferred()
	get_tree().create_timer(AUTO_CLOSE, true).timeout.connect(_decline)

func _build_question() -> void:
	var other: String = _other_version if _other_version != "" else Tr.t("LBL_INSTANCE_OLD_VERSION")
	_column.add_child(ModalKit.make_text(Tr.t("LBL_INSTANCE_OTHER_TITLE"), "section", UITheme.WARNING))
	_column.add_child(ModalKit.make_text(Tr.t("LBL_INSTANCE_OTHER_ASK") % [other, _my_version]))
	_column.add_child(ModalKit.make_text(Tr.t("LBL_INSTANCE_OTHER_NOTE"), "small", UITheme.TEXT_DIM))
	var yes := ModalKit.make_menu_button(Tr.t("BTN_INSTANCE_CLOSE_OTHER"), UITheme.DANGER, _accept)
	var no := ModalKit.make_menu_button(Tr.t("BTN_INSTANCE_KEEP_OTHER"), UITheme.BTN, _decline)
	_column.add_child(yes)
	_column.add_child(no)
	no.grab_focus.call_deferred()

## Tras el SI: la otra se esta cerrando.
func show_waiting() -> void:
	_clear()
	_column.add_child(ModalKit.make_text(Tr.t("LBL_INSTANCE_CLOSING"), "section", UITheme.ACCENT))

## La otra no murio a tiempo: se avisa y se sale.
func show_failed() -> void:
	_clear()
	_done = false
	_column.add_child(ModalKit.make_text(Tr.t("LBL_INSTANCE_CLOSE_FAILED"), "section", UITheme.DANGER))
	var btn := ModalKit.make_menu_button(Tr.t("BTN_CLOSE"), UITheme.BTN, _decline)
	_column.add_child(btn)
	btn.grab_focus.call_deferred()

func _accept() -> void:
	if _done:
		return
	_done = true
	accepted.emit()

func _decline() -> void:
	if _done:
		return
	_done = true
	declined.emit()
