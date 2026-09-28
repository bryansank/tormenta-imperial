extends CanvasLayer
## Panel that explains the game goals and "What to do".
## Toggled via EventBus.

var _panel: PanelContainer
var _backdrop: ColorRect
var _obj_btn: Button
var _is_open := false
var _now_title: Label
var _now_why: Label
var _now_blocker: Label
var _route_box: VBoxContainer
var _refresh_left := 0.0

const Objectives := preload("res://scripts/services/Objectives.gd")
## Cada cuanto se recalcula el paso con el panel abierto. Lo que cambia la
## respuesta (una obra que acaba, oro que entra) pasa todo el rato; un segundo es
## lo bastante vivo para leerlo y no cuesta nada.
const REFRESH_EVERY := 1.0
## Lo que pide el modo de esta partida. Se rellena al abrir: el panel se
## construye antes de que la partida cargue y sepa en que modo esta.
var _mode_header: Label
var _mode_goal: Label

func _ready() -> void:
	layer = 15 # Higher than other UI
	_setup_ui()
	EventBus.objective_panel_toggled.connect(toggle)
	UIManager.register_panel(self, "ObjectivePanel")

func _setup_ui() -> void:
	# Root control holds the always-present sidebar button; the modal itself
	# (backdrop + panel) is toggled independently so the button stays visible.
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Sidebar button ("¿Qué hacer?") — lives in the hamburger menu
	_obj_btn = Button.new()
	_obj_btn.text = Tr.t("BTN_OBJECTIVES")
	_obj_btn.custom_minimum_size = Vector2(164, UILayoutConfig.SIDEBAR_BTN_HEIGHT)
	_obj_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_obj_btn.offset_left = -176
	_obj_btn.offset_top = UILayoutManager.get_sidebar_button_offset("ObjectivePanel.button")
	UITheme.style_card_button(_obj_btn, UITheme.BTN.lightened(0.05), UITheme.INFO)
	_obj_btn.pressed.connect(toggle)
	_obj_btn.visible = false  # Start collapsed with sidebar
	root.add_child(_obj_btn)
	EventBus.sidebar_toggled.connect(func(vis: bool): _obj_btn.visible = vis)

	# Backdrop
	_backdrop = UITheme.make_backdrop()
	_backdrop.visible = false
	_backdrop.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			toggle()
	)
	root.add_child(_backdrop)

	_panel = PanelContainer.new()
	_panel.visible = false
	UILayoutManager.apply_layout("ObjectivePanel", _panel)
	_panel.add_theme_stylebox_override("panel", UITheme.make_war_table_style())
	_panel.gui_input.connect(func(event): if event is InputEventMouseButton and event.pressed: UIManager.focus_window(self))
	root.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	margin.add_child(vbox)

	# Header
	var header := UITheme.make_panel_header(Tr.t("LBL_OBJ_TITLE"), toggle)
	vbox.add_child(header)

	vbox.add_child(UITheme.make_separator())

	# Content - Scrollable
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 20)
	scroll.add_child(content)

	# El modo primero: en Constructor o Sandbox el objetivo no es el asedio.
	_mode_header = UITheme.section_header("", UITheme.ACCENT)
	content.add_child(_mode_header)
	_mode_goal = UITheme.make_label("", "body", UITheme.TEXT_BRIGHT)
	_mode_goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_mode_goal)
	content.add_child(UITheme.make_separator())

	# ── AHORA: el siguiente paso, calculado desde la partida (Objectives) ──
	# Antes esto eran cinco pasos fijos, y tres eran falsos: construir un Nucleo
	# (ya lo tienes y no se construye), "conectar" con almacenes (no se conecta
	# nada) y desbloquear edificios con el arbol tecnologico (los desbloquean
	# otros edificios). Ahora dice lo que toca, por que, y que falta.
	content.add_child(UITheme.section_header(Tr.t("OBJ_NOW")))
	_now_title = UITheme.make_label("", "section", UITheme.TEXT_BRIGHT)
	_now_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_now_title)
	_now_why = UITheme.make_label("", "body", UITheme.TEXT)
	_now_why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_now_why)
	_now_blocker = UITheme.make_label("", "body", UITheme.WARNING)
	_now_blocker.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_now_blocker)

	# ── EL CAMINO: la linea entera, con lo hecho marcado ──
	content.add_child(UITheme.make_separator())
	content.add_child(UITheme.section_header(Tr.t("OBJ_ROUTE")))
	_route_box = VBoxContainer.new()
	_route_box.add_theme_constant_override("separation", 4)
	content.add_child(_route_box)

	# La mision la dice la cabecera del modo (arriba): en Constructor o Sandbox no
	# hay asedio que sobrevivir.
	content.add_child(UITheme.make_separator())
	var tip := UITheme.make_label(Tr.t("OBJ_TIP_TEXT"), "small", UITheme.ACCENT)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(tip)

	# Close Button at bottom
	var close_btn := Button.new()
	close_btn.text = Tr.t("BTN_UNDERSTOOD")
	UITheme.style_button(close_btn, UITheme.POSITIVE, UITheme.FONT_SECTION)
	close_btn.pressed.connect(toggle)
	vbox.add_child(close_btn)

func toggle() -> void:
	_is_open = not _is_open
	if _is_open:
		refresh_mode()
	_panel.visible = _is_open
	_backdrop.visible = _is_open
	if _is_open:
		refresh()
		UIManager.open_panel(self)
	else:
		UIManager.close_panel(self)

func _toggle_panel() -> void:
	toggle()

func _process(delta: float) -> void:
	if not _is_open:
		return
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		refresh()

## Vuelve a preguntar el paso y repinta. Publico para los tests.
func refresh() -> void:
	_refresh_left = REFRESH_EVERY
	var step: Dictionary = Objectives.next_step()
	var text: Dictionary = Objectives.describe(step)
	_now_title.text = String(text["title"])
	_now_why.text = String(text["why"])
	_now_blocker.text = String(text["blocker"])
	_now_blocker.visible = String(text["blocker"]) != ""
	_paint_route()

## La linea de Objectives.LINE, una fila por paso: hecho, el de ahora, o por hacer.
func _paint_route() -> void:
	for child in _route_box.get_children():
		child.queue_free()
	for row in Objectives.route():
		var mark: String = "✔ " if bool(row["done"]) else ("▶ " if bool(row["current"]) else "· ")
		var color: Color = UITheme.TEXT_DIM if bool(row["done"]) else (UITheme.ACCENT if bool(row["current"]) else UITheme.TEXT)
		var label := UITheme.make_label(mark + String(row["text"]), "small", color)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_route_box.add_child(label)

func get_now_text() -> Dictionary:
	return {"title": _now_title.text, "why": _now_why.text, "blocker": _now_blocker.text}

# ── modos-de-juego ──

func refresh_mode() -> void:
	_mode_header.text = Tr.t("LBL_OBJ_MODE") % GameMode.display_name().to_upper()
	_mode_goal.text = Tr.t(GameMode.goal_key())
