extends CanvasLayer
## La pantalla de la expedicion. Un unico overlay a pantalla completa con cuatro
## vistas que nunca se ven a la vez:
##
##   * **Tablero** — el 8x8 del encuentro, con orden de turno y acciones.
##   * **Mapa** — los nodos de la expedicion en columnas por profundidad.
##   * **Draft** — el modal de mejoras tras ganar un nodo que no era el jefe.
##   * **Parte final** — lo que se trajo la columna: botin y bajas.
##
## No posee estado de combate: lee `CombatManager` y se redibuja con cada senal
## (constitucion, principio IV). Cada clic vuelve por la API publica del manager,
## asi que una accion ilegal no se puede ni expresar aqui — las reglas la
## rechazan y la pantalla nunca tiene que saber por que.
##
## El nucleo de la expedicion (`launch_expedition`, `select_node`, `apply_draft`,
## `abandon_expedition`...) lo construye otro servicio; mientras no exista, cada
## llamada va protegida con `has_method()` y la vista se limita a no mentir.

const Rules := preload("res://scripts/combat/CombatRules.gd")

const PLAYER := 0
const ENEMY := 1

## Roles de resalte, aparte de los colores de bando para que el tablero siga
## siendo legible sin depender solo del tono.
const COL_EMPTY := Color(0.11, 0.12, 0.10)
const COL_MOVE := Color(0.20, 0.33, 0.45)
const COL_TARGET := Color(0.48, 0.18, 0.14)

## Margen y separacion del lienzo del mapa, en pixeles.
const MAP_PAD := 16
const MAP_COL_GAP := 54
const MAP_ROW_GAP := 22

enum View { NONE, BOARD, MAP }

## Senales internas de la vista (no van al EventBus): existen para que las
## pruebas y el modo dev puedan seguir la intencion del jugador sin depender de
## que el nucleo de la expedicion este cableado todavia.
signal map_node_chosen(node_index: int)
signal draft_option_chosen(option_index: int)
signal abandon_confirmed()

# ── Tablero ──────────────────────────────────────────────────────────

var _root: Control
var _backdrop: ColorRect
var _board_view: Control
var _grid: GridContainer
var _cells: Array = []              ## Button, row-major, index = y * width + x
var _cell_bars: Array = []          ## ProgressBar alineado con _cells

var _title_label: Label
var _round_label: Label
var _turn_label: Label
var _order_box: HBoxContainer
var _defend_btn: Button
var _wait_btn: Button
var _end_btn: Button
var _abandon_board_btn: Button
var _result_panel: PanelContainer
var _result_title: Label
var _result_detail: Label

var _board: Vector2i = Vector2i(8, 8)
var _cell_size: int = 52
var _board_open := false

# ── Mapa ─────────────────────────────────────────────────────────────

var _map_view: Control
var _map_title: Label
var _map_progress: Label
var _map_bonuses: Label
var _map_scroll: ScrollContainer
var _map_canvas: Control
var _abandon_map_btn: Button
var _map_buttons: Array = []        ## Button por nodo, alineado con el mapa
var _node_positions: Array = []     ## Vector2, esquina superior izquierda
var _node_size: int = 56

## La expedicion que se esta pintando. Es una copia de lectura de lo que dice
## CombatManager, nunca una fuente propia: se refresca en cada apertura.
var _run = null

# ── Draft y parte final ──────────────────────────────────────────────

var _draft_backdrop: ColorRect
var _draft_panel: PanelContainer
var _draft_cards: VBoxContainer
var _draft_options: Array = []
var _pending_draft: Array = []

var _report_panel: PanelContainer
var _report_title: Label
var _report_detail: Label

var _confirm_dialog: ConfirmationDialog

var _view: int = View.NONE

func _ready() -> void:
	# Por encima de cualquier panel de la base, incluidos los avisos del tutorial
	# (14) y las ranuras modales (15): el tablero es un modo, no una ventana, y
	# nada de la base puede dibujarse encima. Solo la pantalla de victoria (20)
	# lo supera.
	#
	# Se deja fuera de la pila de ventanas de UIManager a proposito: esa pila
	# reasigna `layer` como `_base_layer + posicion`, lo que devolveria el
	# tablero por debajo de los paneles que debe tapar. Ademas hace que ESC
	# cierre la ventana de arriba, y una pelea no es algo que se deba poder
	# quitar de en medio con una tecla. El fondo a pantalla completa es lo que
	# la hace modal.
	layer = 18
	_setup_ui()
	visible = false

	EventBus.encounter_started.connect(_on_encounter_started)
	EventBus.turn_started.connect(_on_turn_started)
	EventBus.unit_moved.connect(_on_unit_moved)
	EventBus.unit_attacked.connect(_on_unit_attacked)
	EventBus.unit_defended.connect(func(_uid): _refresh())
	EventBus.unit_died.connect(_on_unit_died)
	EventBus.encounter_ended.connect(_on_encounter_ended)
	EventBus.expedition_started.connect(_on_expedition_started)
	EventBus.expedition_node_selected.connect(_on_expedition_node_selected)
	EventBus.expedition_ended.connect(_on_expedition_ended)
	EventBus.draft_offered.connect(_on_draft_offered)
	EventBus.draft_applied.connect(_on_draft_applied)
	EventBus.game_load_completed.connect(_on_game_load_completed)
	# `expedition_resumed` lo declara el nucleo de la expedicion; mientras no
	# exista, reanudar se cubre con `game_load_completed`.
	if EventBus.has_signal("expedition_resumed"):
		EventBus.connect("expedition_resumed", Callable(self, "_on_expedition_resumed"))
	get_viewport().size_changed.connect(_on_viewport_resized)

# ── Construccion ─────────────────────────────────────────────────────

func _setup_ui() -> void:
	_root = Control.new()
	UILayoutManager.apply_layout("BattleScreen", _root)
	add_child(_root)

	# Bastante opaco como para sacar la base de juego: esto es otro modo y debe
	# sentirse como tal.
	_backdrop = ColorRect.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = Color(0.03, 0.04, 0.03, 0.93)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_backdrop)

	_build_board_view()
	_build_map_view()
	_build_result_panel()
	_build_draft_panel()
	_build_report_panel()
	_build_confirm_dialog()

func _build_board_view() -> void:
	_board_view = Control.new()
	_board_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_board_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board_view.visible = false
	_root.add_child(_board_view)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 10)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board_view.add_child(column)

	# Cabecera: que pelea es esta, y cuanto tiempo queda dentro.
	var header := HBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_theme_constant_override("separation", 24)
	_title_label = UITheme.make_label("", "title", UITheme.ACCENT)
	header.add_child(_title_label)
	_round_label = UITheme.make_label("", "section", UITheme.TEXT_DIM)
	header.add_child(_round_label)
	column.add_child(header)

	_turn_label = UITheme.make_label("", "section", UITheme.TEXT)
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_turn_label)

	# Franja de iniciativa: la ronda entera, en el orden en que va a pasar (FR-006).
	_order_box = HBoxContainer.new()
	_order_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_order_box.add_theme_constant_override("separation", 4)
	column.add_child(_order_box)

	var grid_center := HBoxContainer.new()
	grid_center.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(grid_center)

	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 2)
	_grid.add_theme_constant_override("v_separation", 2)
	grid_center.add_child(_grid)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 8)
	_defend_btn = _make_action(Tr.t("BTN_DEFEND"), func(): _act_defend())
	_wait_btn = _make_action(Tr.t("BTN_WAIT"), func(): _act_wait())
	_end_btn = _make_action(Tr.t("BTN_END_TURN"), func(): _act_end_turn())
	actions.add_child(_defend_btn)
	actions.add_child(_wait_btn)
	actions.add_child(_end_btn)
	# Abandonar tambien desde el tablero: una expedicion se puede cortar sin
	# tener que ganar antes el encuentro que la esta matando.
	_abandon_board_btn = _make_action(Tr.t("BTN_ABANDON"), func(): _ask_abandon())
	UITheme.style_button(_abandon_board_btn, UITheme.DANGER.darkened(0.25), UITheme.FONT_BUTTON)
	_abandon_board_btn.visible = false
	actions.add_child(_abandon_board_btn)
	column.add_child(actions)

func _make_action(text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(132, UITheme.MIN_BTN_H + 4)
	UITheme.style_button(btn, UITheme.BTN, UITheme.FONT_BUTTON)
	btn.pressed.connect(callback)
	return btn

func _build_result_panel() -> void:
	_result_panel = PanelContainer.new()
	_result_panel.set_anchors_preset(Control.PRESET_CENTER)
	_result_panel.custom_minimum_size = Vector2(340, 0)
	_result_panel.add_theme_stylebox_override("panel", UITheme.make_war_table_style())
	_result_panel.visible = false
	_root.add_child(_result_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UITheme.SEPARATION)
	_result_panel.add_child(vbox)

	_result_title = UITheme.make_label("", "title", UITheme.ACCENT)
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_result_title)

	_result_detail = UITheme.make_label("", "body", UITheme.TEXT_DIM)
	_result_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_result_detail)

	var close := Button.new()
	close.text = Tr.t("BTN_CLOSE")
	close.custom_minimum_size = Vector2(0, UITheme.MIN_BTN_H)
	UITheme.style_button(close, UITheme.BTN, UITheme.FONT_BUTTON)
	close.pressed.connect(_close_board)
	vbox.add_child(close)

# ── Vista de mapa ────────────────────────────────────────────────────

func _build_map_view() -> void:
	_map_view = Control.new()
	_map_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_view.visible = false
	_root.add_child(_map_view)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = UITheme.MARGIN
	column.offset_top = UITheme.MARGIN
	column.offset_right = -UITheme.MARGIN
	column.offset_bottom = -UITheme.MARGIN
	column.add_theme_constant_override("separation", UITheme.SEPARATION)
	_map_view.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	_map_title = UITheme.make_label(Tr.t("LBL_EXPEDITION_MAP"), "title", UITheme.ACCENT)
	_map_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_map_title)
	_map_progress = UITheme.make_label("", "section", UITheme.TEXT_DIM)
	header.add_child(_map_progress)
	column.add_child(header)

	# Los bonos del draft van en la cabecera del mapa porque son la razon por la
	# que el jugador mira el mapa: deciden si la ruta arriesgada ya es asumible.
	_map_bonuses = UITheme.make_label("", "small", UITheme.POSITIVE)
	_map_bonuses.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_map_bonuses)

	_map_scroll = ScrollContainer.new()
	_map_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_map_scroll)

	_map_canvas = Control.new()
	_map_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_canvas.draw.connect(_draw_map_links)
	_map_scroll.add_child(_map_canvas)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 8)
	_abandon_map_btn = _make_action(Tr.t("BTN_ABANDON"), func(): _ask_abandon())
	UITheme.style_button(_abandon_map_btn, UITheme.DANGER.darkened(0.25), UITheme.FONT_BUTTON)
	footer.add_child(_abandon_map_btn)
	column.add_child(footer)

func _build_draft_panel() -> void:
	# El draft no se puede esquivar: siempre hay al menos dos opciones aplicables
	# y una de ellas tiene que elegirse antes de volver al mapa (SC-009).
	_draft_backdrop = ColorRect.new()
	_draft_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draft_backdrop.color = Color(0.02, 0.03, 0.02, 0.75)
	_draft_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_draft_backdrop.visible = false
	_root.add_child(_draft_backdrop)

	_draft_panel = PanelContainer.new()
	_draft_panel.set_anchors_preset(Control.PRESET_CENTER)
	_draft_panel.custom_minimum_size = Vector2(360, 0)
	_draft_panel.add_theme_stylebox_override("panel", UITheme.make_war_table_style())
	_draft_panel.visible = false
	_root.add_child(_draft_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UITheme.SEPARATION)
	_draft_panel.add_child(vbox)

	var title := UITheme.make_label(Tr.t("LBL_DRAFT_TITLE"), "title", UITheme.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_draft_cards = VBoxContainer.new()
	_draft_cards.add_theme_constant_override("separation", 6)
	vbox.add_child(_draft_cards)

func _build_report_panel() -> void:
	_report_panel = PanelContainer.new()
	_report_panel.set_anchors_preset(Control.PRESET_CENTER)
	_report_panel.custom_minimum_size = Vector2(360, 0)
	_report_panel.add_theme_stylebox_override("panel", UITheme.make_war_table_style())
	_report_panel.visible = false
	_root.add_child(_report_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UITheme.SEPARATION)
	_report_panel.add_child(vbox)

	_report_title = UITheme.make_label("", "title", UITheme.ACCENT)
	_report_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_report_title)

	_report_detail = UITheme.make_label("", "body", UITheme.TEXT_DIM)
	_report_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_report_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_report_detail)

	var back := Button.new()
	back.text = Tr.t("BTN_BACK_TO_BASE")
	back.custom_minimum_size = Vector2(0, UITheme.MIN_BTN_H)
	UITheme.style_button(back, UITheme.BTN, UITheme.FONT_BUTTON)
	back.pressed.connect(_close_all)
	vbox.add_child(back)

func _build_confirm_dialog() -> void:
	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.title = Tr.t("BTN_ABANDON")
	_confirm_dialog.dialog_text = Tr.t("MSG_CONFIRM_ABANDON")
	_confirm_dialog.ok_button_text = Tr.t("BTN_ABANDON")
	_confirm_dialog.confirmed.connect(_do_abandon)
	_root.add_child(_confirm_dialog)

# ── Lectura de la expedicion ─────────────────────────────────────────

## Toda consulta de expedicion pasa por aqui: mientras `CombatManager` no tenga
## la capa de expedicion, la pantalla se comporta como si no hubiera ninguna.
func _fetch_expedition():
	if CombatManager.has_method("get_expedition"):
		return CombatManager.get_expedition()
	return null

func has_expedition() -> bool:
	if CombatManager.has_method("has_active_expedition"):
		return CombatManager.has_active_expedition()
	return _run != null and _run.is_active()

func current_view() -> int:
	return _view

# ── Construccion del tablero ─────────────────────────────────────────

## Las celdas se reconstruyen solo cuando cambia el tamano del tablero o el de la
## ventana; un refresco normal se limita a reestilarlas.
func _build_grid() -> void:
	for child in _grid.get_children():
		child.queue_free()
	_cells.clear()
	_cell_bars.clear()

	_grid.columns = _board.x
	for y in range(_board.y):
		for x in range(_board.x):
			var cell := Button.new()
			cell.custom_minimum_size = Vector2(_cell_size, _cell_size)
			cell.focus_mode = Control.FOCUS_NONE
			cell.clip_text = true
			cell.add_theme_font_size_override("font_size", maxi(12, _cell_size / 3))
			var heavy := UITheme.heavy_font()
			if heavy:
				cell.add_theme_font_override("font", heavy)
			var coords := Vector2i(x, y)
			cell.pressed.connect(func(): _on_cell_pressed(coords))
			_grid.add_child(cell)
			_cells.append(cell)

			# La vida se lee como una barra bajo la letra — el unico numero que
			# el jugador mira constantemente no deberia necesitar un tooltip.
			var bar := ProgressBar.new()
			bar.show_percentage = false
			bar.max_value = 1.0
			bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
			bar.offset_left = 4
			bar.offset_right = -4
			bar.offset_top = -8
			bar.offset_bottom = -3
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_child(bar)
			_cell_bars.append(bar)

## Mantiene el tablero dentro de la ventana de un movil sin dejar que las celdas
## bajen de un tamano tocable (quickstart E9).
func _recalculate_cell_size() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var by_width: float = (vp.x * 0.92) / float(_board.x)
	var by_height: float = (vp.y * 0.58) / float(_board.y)
	_cell_size = int(clampf(minf(by_width, by_height), 34.0, 62.0))

## Lo mismo para el mapa: el nodo es un boton y un boton tiene que poder pulsarse
## con el pulgar, asi que nunca baja de 44 px (T021, quickstart E9).
func _recalculate_node_size() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_node_size = int(clampf(minf(vp.x * 0.14, vp.y * 0.12), float(UITheme.MIN_BTN_H), 64.0))

func _on_viewport_resized() -> void:
	if _view == View.BOARD:
		var previous := _cell_size
		_recalculate_cell_size()
		if previous != _cell_size:
			_build_grid()
		_refresh()
	elif _view == View.MAP:
		var previous_node := _node_size
		_recalculate_node_size()
		if previous_node != _node_size:
			_build_map()
		else:
			_refresh_map()

# ── Senales de expedicion ────────────────────────────────────────────

func _on_expedition_started(_expedition_id: int, _node_count: int) -> void:
	open_map()

func _on_expedition_resumed(_expedition_id: int) -> void:
	open_map()

func _on_expedition_node_selected(_node_index: int) -> void:
	if _view != View.MAP:
		return
	var fresh = _fetch_expedition()
	if fresh != null:
		_run = fresh
	_refresh_map()

func _on_game_load_completed() -> void:
	if has_expedition():
		open_map()

func _on_expedition_ended(result: int, rewards: Dictionary, casualties: Dictionary) -> void:
	_pending_draft.clear()
	_close_draft()
	_result_panel.visible = false
	_board_view.visible = false
	_map_view.visible = false
	_board_open = false
	_view = View.NONE
	_run = null

	match result:
		0:
			_report_title.text = Tr.t("LBL_VICTORY")
			_report_title.add_theme_color_override("font_color", UITheme.POSITIVE)
		2:
			_report_title.text = Tr.t("LBL_ABANDONED")
			_report_title.add_theme_color_override("font_color", UITheme.WARNING)
		_:
			_report_title.text = Tr.t("LBL_DEFEAT")
			_report_title.add_theme_color_override("font_color", UITheme.DANGER)

	var lines: Array = []
	if rewards.is_empty():
		lines.append(Tr.t("LBL_NO_REWARDS"))
	else:
		lines.append("%s: %s" % [Tr.t("LBL_REWARDS"), _resource_list(rewards)])
	if casualties.is_empty():
		lines.append(Tr.t("LBL_NO_CASUALTIES"))
	else:
		lines.append("%s: %s" % [Tr.t("LBL_CASUALTIES"), _unit_list(casualties)])
	_report_detail.text = "\n".join(lines)

	_report_panel.visible = true
	visible = true

# ── Draft ────────────────────────────────────────────────────────────

func _on_draft_offered(options: Array) -> void:
	_pending_draft = options.duplicate()
	# Si el parte del encuentro sigue en pantalla, el draft espera su turno: dos
	# modales a la vez convierten la recompensa en un accidente.
	if _result_panel.visible:
		return
	_open_draft()

func _open_draft() -> void:
	_draft_options = _pending_draft.duplicate()
	_pending_draft.clear()
	if _draft_options.is_empty():
		return
	for child in _draft_cards.get_children():
		child.queue_free()
	for i in range(_draft_options.size()):
		_draft_cards.add_child(_make_draft_card(i, _draft_options[i]))
	_draft_backdrop.visible = true
	_draft_panel.visible = true
	visible = true

func _make_draft_card(index: int, option: Dictionary) -> Button:
	var card := Button.new()
	card.text = draft_text(option)
	card.custom_minimum_size = Vector2(0, UITheme.MIN_BTN_H + 8)
	card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.style_card_button(card, UITheme.CARD_BG, UITheme.ACCENT)
	card.pressed.connect(func(): _choose_draft(index))
	return card

## El texto de una mejora, con su numero puesto. `label_key` trae la frase y
## `effect` el valor; una clave sin hueco se muestra tal cual en vez de reventar.
func draft_text(option: Dictionary) -> String:
	var effect: Dictionary = option.get("effect", {})
	var key: String = String(option.get("label_key", option.get("id", "")))
	var phrase: String = Tr.t(key)
	var text: String = phrase
	if phrase.contains("%"):
		if effect.has("heal_pct"):
			text = phrase % roundi(float(effect["heal_pct"]) * 100.0)
		else:
			text = phrase % int(effect.get("delta", 0))
	var applies: String = String(option.get("applies_to", "all"))
	if applies != "all":
		text += "  (%s)" % Tr.t(GameConfig.get_unit_def(applies).get("name", applies))
	return text

func _choose_draft(index: int) -> void:
	if index < 0 or index >= _draft_options.size():
		return
	draft_option_chosen.emit(index)
	_close_draft()
	if CombatManager.has_method("apply_draft"):
		CombatManager.apply_draft(index)
	else:
		open_map()

func _close_draft() -> void:
	_draft_panel.visible = false
	_draft_backdrop.visible = false
	_draft_options.clear()

func _on_draft_applied(_option: Dictionary) -> void:
	_close_draft()
	open_map()

func draft_card_count() -> int:
	return _draft_cards.get_child_count() if _draft_cards != null else 0

func is_draft_open() -> bool:
	return _draft_panel != null and _draft_panel.visible

# ── Mapa ─────────────────────────────────────────────────────────────

## Abre la vista de mapa. `run` permite pintar una expedicion concreta (modo dev
## y pruebas); sin argumento se lee la que tenga `CombatManager`.
func open_map(run = null) -> void:
	_run = run if run != null else _fetch_expedition()
	if _run == null:
		return
	_recalculate_node_size()
	_build_map()
	_view = View.MAP
	_board_open = false
	_board_view.visible = false
	_result_panel.visible = false
	_report_panel.visible = false
	_map_view.visible = true
	visible = true

func _build_map() -> void:
	for child in _map_canvas.get_children():
		child.queue_free()
	_map_buttons.clear()
	_node_positions.clear()
	if _run == null:
		return

	var map: Array = _run.map
	_node_positions.resize(map.size())

	# Columnas por profundidad: el mapa se lee de izquierda a derecha, que es la
	# direccion en la que solo se puede avanzar.
	var by_depth: Dictionary = {}
	var max_depth: int = 0
	for node in map:
		var depth: int = int(node.get("depth", 0))
		if not by_depth.has(depth):
			by_depth[depth] = []
		by_depth[depth].append(int(node.get("index", 0)))
		max_depth = maxi(max_depth, depth)

	var widest: int = 1
	for depth in by_depth:
		widest = maxi(widest, by_depth[depth].size())

	var col_w: int = _node_size + MAP_COL_GAP
	var row_h: int = _node_size + MAP_ROW_GAP
	for depth in range(max_depth + 1):
		var column: Array = by_depth.get(depth, [])
		var offset: float = float(widest - column.size()) * float(row_h) * 0.5
		for row in range(column.size()):
			_node_positions[column[row]] = Vector2(
				float(MAP_PAD + depth * col_w),
				float(MAP_PAD) + offset + float(row * row_h)
			)

	_map_canvas.custom_minimum_size = Vector2(
		float(MAP_PAD * 2 + max_depth * col_w + _node_size),
		float(MAP_PAD * 2 + (widest - 1) * row_h + _node_size)
	)

	for i in range(map.size()):
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(_node_size, _node_size)
		btn.size = Vector2(_node_size, _node_size)
		btn.position = _node_positions[i]
		btn.focus_mode = Control.FOCUS_NONE
		btn.clip_text = true
		var index := i
		btn.pressed.connect(func(): _choose_node(index))
		_map_canvas.add_child(btn)
		_map_buttons.append(btn)

	_refresh_map()

func _refresh_map() -> void:
	if _run == null or _map_buttons.is_empty():
		return
	var map: Array = _run.map
	var exits: Array = _run.current_exits()
	var current: int = _run.current_node
	var active: bool = _run.is_active()

	for i in range(mini(map.size(), _map_buttons.size())):
		var node: Dictionary = map[i]
		var btn: Button = _map_buttons[i]
		var is_boss: bool = bool(node.get("is_boss", false))
		var cleared: bool = bool(node.get("cleared", false))
		var reachable: bool = active and exits.has(i)

		btn.text = Tr.t("LBL_BOSS") if is_boss else str(_roster_size(node))
		btn.disabled = not reachable
		btn.tooltip_text = _node_tooltip(node, i == current, cleared, reachable)
		_style_node(btn, i == current, cleared, reachable, is_boss, int(node.get("risk", 0)))

	_map_progress.text = Tr.t("LBL_EXPEDITION_PROGRESS") % [_run.nodes_cleared(), map.size()]
	_map_bonuses.text = _draft_summary()
	_abandon_map_btn.visible = active
	_map_canvas.queue_redraw()

## El riesgo se pinta en el fondo y se dice con palabras en el tooltip: el color
## solo nunca es suficiente.
func _style_node(btn: Button, is_current: bool, cleared: bool, reachable: bool, is_boss: bool, risk: int) -> void:
	var background: Color = _risk_color(risk).darkened(0.55)
	var border: Color = UITheme.ACCENT_DIM
	var width: int = 1

	if is_boss:
		background = UITheme.DANGER.darkened(0.3)
		border = UITheme.DANGER
		width = 2
	if cleared:
		background = UITheme.POSITIVE.darkened(0.6)
		border = UITheme.POSITIVE
		width = 2
	if reachable:
		border = UITheme.WARNING
		width = 3
	if is_current:
		border = UITheme.ACCENT
		width = 4

	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.set_corner_radius_all(UITheme.CORNER)
	style.border_color = border
	style.set_border_width_all(width)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		btn.add_theme_stylebox_override(state, style)
	var text_color: Color = UITheme.TEXT_BRIGHT if (reachable or is_current) else UITheme.TEXT_DIM
	btn.add_theme_color_override("font_color", text_color)
	btn.add_theme_color_override("font_disabled_color", text_color)
	btn.add_theme_color_override("font_hover_color", UITheme.TEXT_BRIGHT)
	btn.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)

func _risk_color(risk: int) -> Color:
	match clampi(risk, 0, 2):
		0:
			return UITheme.POSITIVE
		1:
			return UITheme.WARNING
		_:
			return UITheme.DANGER

func _risk_text(risk: int) -> String:
	match clampi(risk, 0, 2):
		0:
			return Tr.t("LBL_RISK_LOW")
		1:
			return Tr.t("LBL_RISK_MED")
		_:
			return Tr.t("LBL_RISK_HIGH")

func _node_tooltip(node: Dictionary, is_current: bool, cleared: bool, reachable: bool) -> String:
	var lines: Array = [_risk_text(int(node.get("risk", 0)))]
	lines.append(Tr.t("LBL_NODE_ENEMIES") % _roster_size(node))
	if bool(node.get("is_boss", false)):
		lines.append(Tr.t("LBL_BOSS"))
	if is_current:
		lines.append(Tr.t("LBL_NODE_CURRENT"))
	elif cleared:
		lines.append(Tr.t("LBL_NODE_CLEARED"))
	elif not reachable:
		lines.append(Tr.t("LBL_NODE_LOCKED"))
	return "\n".join(lines)

func _roster_size(node: Dictionary) -> int:
	var total: int = 0
	for count in node.get("enemy_roster", {}).values():
		total += int(count)
	return total

## Las rutas, dibujadas a mano sobre el lienzo: una linea por salida. Las que
## salen del nodo actual se encienden, el resto se quedan en el fondo.
func _draw_map_links() -> void:
	if _run == null or _node_positions.is_empty():
		return
	var half: float = float(_node_size) * 0.5
	var current: int = _run.current_node
	for node in _run.map:
		var from_index: int = int(node.get("index", 0))
		if from_index >= _node_positions.size():
			continue
		var from_point: Vector2 = _node_positions[from_index] + Vector2(float(_node_size), half)
		for exit_index in node.get("exits", []):
			var to_index: int = int(exit_index)
			if to_index < 0 or to_index >= _node_positions.size():
				continue
			var to_point: Vector2 = _node_positions[to_index] + Vector2(0.0, half)
			var live: bool = from_index == current
			var color: Color = UITheme.ACCENT if live else UITheme.ACCENT_DIM
			_map_canvas.draw_line(from_point, to_point, color, 3.0 if live else 2.0)

## Lo que la columna lleva encima ahora mismo, en el orden en que lo eligio.
func _draft_summary() -> String:
	if _run == null or _run.draft_picks.is_empty():
		return Tr.t("LBL_NO_DRAFT_BONUSES")
	var parts: Array = []
	for option in _run.draft_picks:
		parts.append(draft_text(option))
	return Tr.t("LBL_DRAFT_BONUSES") % "   ".join(parts)

func _choose_node(index: int) -> void:
	if _run == null or not _run.can_select(index):
		return
	map_node_chosen.emit(index)
	if CombatManager.has_method("select_node"):
		CombatManager.select_node(index)

func map_button_count() -> int:
	return _map_buttons.size()

func map_button(index: int) -> Button:
	if index < 0 or index >= _map_buttons.size():
		return null
	return _map_buttons[index]

# ── Abandono ─────────────────────────────────────────────────────────

func _ask_abandon() -> void:
	_confirm_dialog.dialog_text = Tr.t("MSG_CONFIRM_ABANDON")
	_confirm_dialog.popup_centered()

func _do_abandon() -> void:
	abandon_confirmed.emit()
	if CombatManager.has_method("abandon_expedition"):
		CombatManager.abandon_expedition()

func is_confirming_abandon() -> bool:
	return _confirm_dialog != null and _confirm_dialog.visible

# ── Senales de encuentro ─────────────────────────────────────────────

func _on_encounter_started(index: int, is_boss: bool) -> void:
	_board = CombatManager.get_board_size()
	_recalculate_cell_size()
	_build_grid()
	_title_label.text = _encounter_title(index, is_boss)
	_result_panel.visible = false
	_report_panel.visible = false
	_open_board()
	_refresh()

## El encuentro de una expedicion se numera; el suelto no, porque no hay ninguna
## serie de la que forme parte.
func _encounter_title(index: int, is_boss: bool) -> String:
	if is_boss:
		return "%s  %s" % [Tr.t("LBL_ENCOUNTER_N") % (index + 1), Tr.t("LBL_BOSS")]
	if has_expedition():
		return Tr.t("LBL_ENCOUNTER_N") % (index + 1)
	return Tr.t("LBL_SKIRMISH_FIGHT")

func _on_turn_started(_side: int, _uid: int) -> void:
	_refresh()

func _on_unit_moved(_uid: int, _from: Vector2i, _to: Vector2i) -> void:
	_refresh()

func _on_unit_attacked(_attacker_uid: int, target_uid: int, damage: int) -> void:
	var target := CombatManager.get_unit(target_uid)
	if target != null:
		_spawn_damage_number(target.position, damage)
	_refresh()

func _on_unit_died(_uid: int, _side: int) -> void:
	_refresh()

func _on_encounter_ended(victory: bool, turns_used: int) -> void:
	_refresh()
	_result_title.text = Tr.t("LBL_VICTORY") if victory else Tr.t("LBL_DEFEAT")
	_result_title.add_theme_color_override("font_color", UITheme.POSITIVE if victory else UITheme.DANGER)
	_result_detail.text = _result_text(turns_used)
	_result_panel.visible = true
	_set_actions_enabled(false)

## Lo que costo y lo que pago la pelea. Los muertos se nombran, porque una lista
## de unidades que no vuelven es la parte que el jugador tiene que sentir.
func _result_text(turns_used: int) -> String:
	var lines: Array = [Tr.t("LBL_ROUND") % [turns_used, CombatManager.get_turn_limit()]]
	var result: Dictionary = CombatManager.get_last_result()
	if result.is_empty():
		return "\n".join(lines)

	var rewards: Dictionary = result.get("rewards", {})
	if not rewards.is_empty():
		lines.append("%s: %s" % [Tr.t("LBL_REWARDS"), _resource_list(rewards)])

	var casualties: Dictionary = result.get("casualties", {})
	if casualties.is_empty():
		lines.append(Tr.t("LBL_NO_CASUALTIES"))
	else:
		lines.append("%s: %s" % [Tr.t("LBL_CASUALTIES"), _unit_list(casualties)])

	var morale_delta: int = int(result.get("morale_delta", 0))
	if morale_delta != 0:
		lines.append(Tr.t("LBL_MORALE_DELTA") % morale_delta)
	return "\n".join(lines)

func _resource_list(amounts: Dictionary) -> String:
	var parts: Array = []
	for res_name in amounts:
		parts.append("%d %s" % [int(amounts[res_name]), Tr.res_name(res_name)])
	return "   ".join(parts)

func _unit_list(counts: Dictionary) -> String:
	var parts: Array = []
	for unit_id in counts:
		var def := GameConfig.get_unit_def(unit_id)
		parts.append("%d %s" % [int(counts[unit_id]), Tr.t(def.get("name", unit_id))])
	return "   ".join(parts)

# ── Refresco del tablero ─────────────────────────────────────────────

func _refresh() -> void:
	if not _board_open or _cells.is_empty():
		return
	_refresh_header()
	_refresh_cells()
	_refresh_order()
	_refresh_actions()

func _refresh_header() -> void:
	_round_label.text = Tr.t("LBL_ROUND") % [CombatManager.get_round(), CombatManager.get_turn_limit()]
	var active := CombatManager.get_active_unit()
	if active == null:
		_turn_label.text = ""
		return
	var is_player: bool = active.side == PLAYER
	_turn_label.text = Tr.t("LBL_TURN_PLAYER") if is_player else Tr.t("LBL_TURN_ENEMY")
	_turn_label.add_theme_color_override("font_color", UITheme.POSITIVE if is_player else UITheme.DANGER)

func _refresh_cells() -> void:
	var active := CombatManager.get_active_unit()
	var moves: Array = []
	var targets: Array = []
	if active != null and CombatManager.is_player_turn():
		moves = CombatManager.get_valid_moves(active.uid)
		targets = CombatManager.get_valid_targets(active.uid)

	for y in range(_board.y):
		for x in range(_board.x):
			var index: int = y * _board.x + x
			var cell: Button = _cells[index]
			var bar: ProgressBar = _cell_bars[index]
			var coords := Vector2i(x, y)
			var unit := CombatManager.get_unit_at(coords)
			_style_cell(cell, bar, coords, unit, active, moves, targets)

func _style_cell(cell: Button, bar: ProgressBar, coords: Vector2i, unit: CombatUnit,
		active: CombatUnit, moves: Array, targets: Array) -> void:
	var background: Color = COL_EMPTY
	var border: Color = UITheme.ACCENT_DIM
	var border_width: int = 1

	if unit == null:
		cell.text = ""
		bar.visible = false
		if moves.has(coords):
			background = COL_MOVE
			border = UITheme.INFO
	else:
		cell.text = _unit_glyph(unit)
		bar.visible = true
		bar.value = float(unit.hp) / float(maxi(1, unit.max_hp))
		_style_health_bar(bar, unit)
		background = UITheme.POSITIVE.darkened(0.45) if unit.side == PLAYER else UITheme.DANGER.darkened(0.35)
		border = UITheme.POSITIVE if unit.side == PLAYER else UITheme.DANGER
		if targets.has(unit.uid):
			background = COL_TARGET
			border = UITheme.WARNING
			border_width = 3
		if unit.defending:
			border = UITheme.INFO
			border_width = 3
		if active != null and unit.uid == active.uid:
			border = UITheme.ACCENT
			border_width = 4

	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.set_corner_radius_all(UITheme.CORNER)
	style.border_color = border
	style.set_border_width_all(border_width)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		cell.add_theme_stylebox_override(state, style)
	cell.add_theme_color_override("font_color", UITheme.TEXT_BRIGHT)
	cell.add_theme_color_override("font_hover_color", UITheme.TEXT_BRIGHT)

func _style_health_bar(bar: ProgressBar, unit: CombatUnit) -> void:
	var ratio: float = float(unit.hp) / float(maxi(1, unit.max_hp))
	var fill := StyleBoxFlat.new()
	fill.bg_color = UITheme.POSITIVE if ratio > 0.5 else (UITheme.WARNING if ratio > 0.25 else UITheme.DANGER)
	fill.set_corner_radius_all(1)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.05, 0.04, 0.9)
	bg.set_corner_radius_all(1)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", bg)

## Una letra por tipo de unidad, tomada del nombre traducido para que siga
## leyendose en ingles. Los iconos de verdad son trabajo de arte, dejado aparte.
func _unit_glyph(unit: CombatUnit) -> String:
	var def := GameConfig.get_unit_def(unit.unit_id)
	var label: String = Tr.t(def.get("name", unit.unit_id))
	return label.substr(0, 1).to_upper() if label != "" else "?"

## La franja de iniciativa: quien actua, en orden, con el actual encendido.
func _refresh_order() -> void:
	for child in _order_box.get_children():
		child.queue_free()
	var active := CombatManager.get_active_unit()
	for uid in CombatManager.get_turn_order():
		var unit := CombatManager.get_unit(uid)
		if unit == null or not unit.is_alive():
			continue
		var chip := Label.new()
		chip.text = _unit_glyph(unit)
		chip.custom_minimum_size = Vector2(26, 26)
		chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		chip.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
		var is_active: bool = active != null and uid == active.uid
		var tint: Color = UITheme.POSITIVE if unit.side == PLAYER else UITheme.DANGER
		chip.add_theme_color_override("font_color", UITheme.TEXT_BRIGHT if is_active else UITheme.TEXT_DIM)
		var style := StyleBoxFlat.new()
		style.bg_color = tint.darkened(0.2 if is_active else 0.6)
		style.set_corner_radius_all(UITheme.CORNER)
		style.border_color = UITheme.ACCENT if is_active else UITheme.ACCENT_DIM
		style.set_border_width_all(2 if is_active else 1)
		chip.add_theme_stylebox_override("normal", style)
		# Una unidad que ya actuo se apaga, para que la franja muestre lo que queda.
		chip.modulate.a = 1.0 if not unit.has_acted else 0.45
		_order_box.add_child(chip)

func _refresh_actions() -> void:
	_set_actions_enabled(CombatManager.is_player_turn())
	_abandon_board_btn.visible = has_expedition()

func _set_actions_enabled(enabled: bool) -> void:
	_defend_btn.disabled = not enabled
	_wait_btn.disabled = not enabled
	_end_btn.disabled = not enabled

# ── Entrada ──────────────────────────────────────────────────────────

## Un clic, un significado: un enemigo en rango es un ataque, una celda
## encendida es un movimiento, lo demas no es nada. Sin modos, sin clic derecho.
func _on_cell_pressed(coords: Vector2i) -> void:
	if not CombatManager.is_player_turn():
		return
	var active := CombatManager.get_active_unit()
	if active == null or active.side != PLAYER:
		return

	var occupant := CombatManager.get_unit_at(coords)
	if occupant != null and occupant.side == ENEMY:
		if CombatManager.get_valid_targets(active.uid).has(occupant.uid):
			CombatManager.attack(active.uid, occupant.uid)
		return
	if occupant == null and CombatManager.get_valid_moves(active.uid).has(coords):
		CombatManager.move_unit(active.uid, coords)

func _act_defend() -> void:
	var active := CombatManager.get_active_unit()
	if active != null:
		CombatManager.defend(active.uid)

func _act_wait() -> void:
	var active := CombatManager.get_active_unit()
	if active != null:
		CombatManager.wait_unit(active.uid)

func _act_end_turn() -> void:
	CombatManager.end_turn()

# ── Numeros de dano ──────────────────────────────────────────────────

## Un numero que sube desde el objetivo y se apaga. Sin el, un golpe son dos
## barras que cambian y el jugador nunca siente el intercambio.
func _spawn_damage_number(cell: Vector2i, amount: int) -> void:
	var index: int = cell.y * _board.x + cell.x
	if cell.x < 0 or index < 0 or index >= _cells.size():
		return
	var anchor: Button = _cells[index]
	var label := UITheme.make_label("-%d" % amount, "title", UITheme.DANGER.lightened(0.35))
	label.z_index = 20
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(label)
	label.global_position = anchor.global_position + Vector2(float(_cell_size) * 0.25, 0.0)

	var tween := label.create_tween()
	tween.tween_property(label, "global_position:y", label.global_position.y - 42.0, 0.9).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.9).set_delay(0.25)
	tween.tween_callback(label.queue_free)

# ── Abrir / cerrar ───────────────────────────────────────────────────

func _open_board() -> void:
	_board_open = true
	_view = View.BOARD
	_map_view.visible = false
	_board_view.visible = true
	visible = true

## Cerrar el parte de un encuentro no es cerrar la expedicion: si queda mapa por
## delante, se vuelve a el; si hay draft pendiente, se ofrece antes.
func _close_board() -> void:
	_board_open = false
	_board_view.visible = false
	_result_panel.visible = false
	CombatManager.end_encounter()

	# Cerrar la oleada de un asedio ABRE la siguiente, y lo hace dentro de esa
	# llamada: report_audit_wave encadena hasta encounter_started sin soltar el
	# hilo. Si se sigue de largo, la cola de este metodo esconde el tablero que
	# se acaba de abrir y deja la partida sin forma de continuar el asedio.
	if _board_open:
		return

	if _report_panel.visible:
		# La expedicion ya se cerro mientras se leia el parte: manda el informe.
		return
	if not _pending_draft.is_empty():
		open_map()
		_open_draft()
		return
	if has_expedition():
		open_map()
		return
	_close_all()

func _close_all() -> void:
	_board_open = false
	_view = View.NONE
	_run = null
	_pending_draft.clear()
	_close_draft()
	_board_view.visible = false
	_map_view.visible = false
	_result_panel.visible = false
	_report_panel.visible = false
	visible = false
