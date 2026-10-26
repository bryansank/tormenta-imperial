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
## `abandon_expedition`...) vive en `CombatManager` y la pantalla solo lo llama:
## aqui no se decide nada, ni siquiera si un nodo es elegible.
##
## **El tablero se ve en 3D** (2026-10-12, docs/15 §3 "El tablero 3D"): una
## maqueta con unidades de juguete (scripts/combat_view/, escena
## scenes/combat/Board3D.tscn) dentro de un SubViewport, y esta pantalla pone
## encima la cabecera, la franja de iniciativa y los botones. Las reglas no
## cambian: la maqueta recibe los mismos eventos y cuenta lo que ya paso a su
## ritmo, y mientras anima (`_board_busy()`) no se deja actuar ni se saca el
## parte. El tablero 2D de siempre sigue aqui como alternativa: en la vista 2D
## del mapa y sin pantalla (pruebas headless). Ver `pick_board_style()`.
##
## **Dos vistas 3D** (2026-10-14, docs/15 §3 "Las dos vistas"): la frontal
## ("front", por defecto: los dos bandos cara a cara, sin casillas; tocar a un
## enemigo acerca a la unidad y dispara, FrontOrders) y el tablero 8x8 ("board").
## Las dos son la misma maqueta (Board3D.set_style) y mueven el MISMO Encounter
## con las mismas llamadas a CombatManager. La preferencia es del dispositivo
## (GameConfig.ui_combat_view, settings.cfg) y se cambia en Ajustes o con el
## boton de la cabecera, tambien a mitad de pelea.
##
## **Piel nueva** (rediseno fase 2, feat/ui2-ejercito, docs/28): la cabecera es
## una ficha oscura del HUD; la barra de acciones, botones pastilla con icono (en
## telefono solo el icono, la palabra al mantener); el parte, el draft y el
## informe final, ventanas crema. Las reglas, el tablero y la maqueta 3D no
## cambian: esto es solo la piel.

const ColonyByline := preload("res://scripts/ui/ColonyByline.gd")
const Rules := preload("res://scripts/combat/CombatRules.gd")
const Board3DView := preload("res://scripts/combat_view/BoardViewport3D.gd")
const BoardTerrain := preload("res://scripts/combat_view/BoardTerrain3D.gd")
const BoardLayout := preload("res://scripts/combat_view/BoardLayout3D.gd")
const WorldLook := preload("res://scripts/map/WorldLook.gd")
const ViewMode := preload("res://scripts/view2d/ViewMode.gd")
const Orders := preload("res://scripts/combat_view/FrontOrders.gd")
## Para las lineas del botin exclusivo (las mismas palabras que la seleccion).
const SkirmishPanelScript := preload("res://scripts/ui/SkirmishPanel.gd")
const UnitCardScript := preload("res://scripts/ui/UnitCard.gd")
const CT := preload("res://scripts/ui/CartoonTheme.gd")

const PLAYER := 0
const ENEMY := 1

## Roles de resalte (vacia, movimiento, objetivo): UITheme.BOARD_*, aparte de
## los colores de bando para que el tablero siga siendo legible sin depender
## solo del tono. Son tokens: la paleta de daltonismo los cambia.

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
var _cell_icons: Array = []         ## TextureRect alineado con _cells
## Marca de bando alineada con _cells: circulo arriba a la izquierda para los
## nuestros, rombo arriba a la derecha para el enemigo. Forma Y posicion, para
## que el bando se lea sin depender del verde y el rojo (daltonismo, sol en la
## pantalla del movil).
var _cell_marks: Array = []
## Etiqueta de vista previa alineada con _cells: "-18" sobre un objetivo, "✕"
## sobre un enemigo demasiado cerca para la artilleria (tablero 2D).
var _cell_previews: Array = []

# ── Ensenar el combate (2026-10-14, docs/15 §3 "Ensenar el combate") ──

## "VER ALCANCE ENEMIGO": tine las casillas a las que el enemigo llega y dispara
## en su turno. Del jugador, no de la partida: no se guarda.
var _threat_btn: Button
var _show_threat := false
## Lo calculado en el ultimo refresco (una vez por evento, nunca por fotograma).
var _ov_threat: Dictionary = {}     ## cell -> true
var _ov_no_fire: Dictionary = {}    ## cell -> true
var _ov_fire: Dictionary = {}       ## cell -> true (leccion de artilleria)
var _ov_previews: Dictionary = {}   ## uid -> texto encima de la pieza
var _threat_key := ""
var _threat_cache: Array = []
## La ficha abierta (UnitCard) y de quien es.
var _unit_card = null                ## UnitCard (PanelContainer)
var _unit_card_uid := -1

var _title_label: Label
var _round_label: Label
var _turn_label: Label
var _order_box: HBoxContainer
var _defend_btn: Button
var _wait_btn: Button
var _end_btn: Button
var _abandon_board_btn: Button
## RESOLVER SOLO (doc 21 §3.4, D6 = A): en el Diezmo y en incursiones, con la
## fuerza doble. Lo decide CombatManager.can_auto_resolve().
var _auto_btn: Button
var _result_panel: PanelContainer
var _result_title: Label
var _result_detail: Label

var _board: Vector2i = Vector2i(8, 8)
var _cell_size: int = 52
var _board_open := false

# ── Tablero 3D ───────────────────────────────────────────────────────

## "3d" o "2d": como se pinta el tablero abierto (se decide al abrirlo).
var _board_style := "2d"
## Forzado por pruebas y sondas ("2d" / "3d"); "" = lo que diga `pick_board_style()`.
var _forced_style := ""
## Escenario forzado de la maqueta (sondas): "" = el de la semilla.
var _forced_scene := ""
## El terreno del encuentro abierto (mar y aire, 1.1): casilla -> "land" /
## "water" / "shore", vacio = todo tierra. Se lee al refrescar las casillas y
## solo pinta el fondo de las vacias: que se puede pisar lo dicen las reglas.
var _terrain_now: Dictionary = {}
## La cobertura del Bastion (Encounter.cover, feat/edificios-defensa-vida):
## casilla -> defensa de mas. Vacio casi siempre; solo en el Impuesto y el asedio.
var _cover_now: Dictionary = {}
var _board3d = null                 ## BoardViewport3D, creado la primera vez
var _board_column: VBoxContainer
var _grid_center: HBoxContainer
var _board_spacer: Control
var _actions_row: Container
var _speed_btn: Button
var _view_btn: Button
var _header_margin: MarginContainer
const PauseMenuScript := preload("res://scripts/ui/PauseMenu.gd")
var _advance_btn: Button
## Forzada por pruebas y sondas ("front" / "board"); "" = GameConfig.ui_combat_view.
var _forced_view := ""
## Lo que espera a que la maqueta termine de animar: el parte, el draft, el
## informe final. Nunca se ensena el resultado de algo que aun no se ha visto.
var _deferred_ui: Array = []
## Si esta pantalla apago el 3D del mapa de la base (el tablero 3D lo tapa entero).
var _world_paused := false

# ── Mapa ─────────────────────────────────────────────────────────────

var _map_view: Control
## Tres campanas (feat/tres-campanas): el fondo del mapa de una mision de mar
## (agua) o de aire (cielo). Un rectangulo de color: nada que dibujar por fotograma.
var _map_sky: ColorRect
var _map_title: Label
var _map_progress: Label
var _map_bonuses: Label
var _map_scroll: ScrollContainer
var _map_canvas: Control
var _abandon_map_btn: Button
var _map_buttons: Array = []        ## Button por nodo, alineado con el mapa
var _node_positions: Array = []     ## Vector2, esquina superior izquierda
var _node_size: int = 56
var _map_risk_labels: Array = []    ## Label de riesgo bajo cada nodo
var _map_hint: Label

## Con el dedo no hay tooltip: el primer toque en un nodo lo ARMA (lo marca y
## dice su riesgo en la cabecera) y solo el segundo toque sobre el mismo nodo
## entra. Con raton, un clic basta: el tooltip ya lo conto todo.
var _touch_mode := false
var _armed_node: int = -1

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
## El botin y las bajas del informe final en iconos, encima de las lineas.
var _report_icons: HFlowContainer

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
	# TutorialPanel busca aqui a donde senalar en el combate guiado (coach_anchor).
	add_to_group("battle_screen")
	_setup_ui()
	visible = false

	EventBus.encounter_started.connect(_on_encounter_started)
	EventBus.turn_started.connect(_on_turn_started)
	EventBus.unit_moved.connect(_on_unit_moved)
	EventBus.unit_attacked.connect(_on_unit_attacked)
	EventBus.unit_defended.connect(_on_unit_defended)
	EventBus.unit_died.connect(_on_unit_died)
	EventBus.encounter_ended.connect(_on_encounter_ended)
	EventBus.expedition_started.connect(_on_expedition_started)
	EventBus.expedition_node_selected.connect(_on_expedition_node_selected)
	EventBus.expedition_ended.connect(_on_expedition_ended)
	EventBus.draft_offered.connect(_on_draft_offered)
	EventBus.draft_applied.connect(_on_draft_applied)
	EventBus.game_load_completed.connect(_on_game_load_completed)
	EventBus.expedition_resumed.connect(_on_expedition_resumed)
	# El combate guiado enciende capas (alcance enemigo, zona de tiro): repintar.
	EventBus.combat_lesson_step_changed.connect(func(_step): _refresh())
	get_viewport().size_changed.connect(_on_viewport_resized)
	# Red de seguridad: si la carga ocurrio antes de que este panel escuchara,
	# expedition_resumed y draft_offered se perdieron. Se le pregunta al servicio.
	sync_with_state.call_deferred()

# ── Construccion ─────────────────────────────────────────────────────

func _setup_ui() -> void:
	_root = Control.new()
	UILayoutManager.apply_layout("BattleScreen", _root)
	add_child(_root)

	# Bastante opaco como para sacar la base de juego: esto es otro modo y debe
	# sentirse como tal.
	_backdrop = ColorRect.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = Color(CT.c("hud", "BG").darkened(0.25), 0.94)
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
	_board_column = column

	# Cabecera: que pelea es esta, cuanto tiempo queda dentro y de quien es el
	# turno, en una sola fila (2026-10-04: el turno iba en una linea propia).
	# Fila que PARTE en un movil (HFlowContainer): con la bandera del pais y el
	# boton x1/x2 ya no cabe en 400 px, y una fila rigida mas ancha que la
	# pantalla ensanchaba la columna entera y sacaba el tablero por la derecha.
	var header := HFlowContainer.new()
	header.name = "BoardHeader"
	header.alignment = FlowContainer.ALIGNMENT_CENTER
	header.add_theme_constant_override("h_separation", 24)
	header.add_theme_constant_override("v_separation", 4)
	# Nuestro lado: la bandera y el nombre del pais.
	header.add_theme_constant_override("h_separation", 14)
	header.add_child(ColonyByline.new("small", CT.text("hud", true)))
	_title_label = CT.label("", "button", CT.sem("ACCENT"))
	header.add_child(_title_label)
	# "Ronda 3 / 20" en corto: [reloj] 3/20, y que significa al mantener.
	_round_label = CT.label("", "number", CT.text("hud", true))
	_round_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_round_label.tooltip_text = Tr.t("ARMY2_ROUND_TIP")
	header.add_child(_round_label)
	_turn_label = CT.label("", "button", CT.text("hud"))
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(_turn_label)
	# x1 / x2 propio: el boton del HUD (capa 10) queda tapado por el tablero (18).
	_speed_btn = Button.new()
	_speed_btn.name = "BoardSpeed"
	_speed_btn.focus_mode = Control.FOCUS_NONE
	_speed_btn.custom_minimum_size = Vector2(56, 0)
	_speed_btn.pressed.connect(GameConfig.toggle_game_speed)
	header.add_child(_speed_btn)
	EventBus.game_speed_changed.connect(func(_s): _refresh_speed_button())
	_refresh_speed_button()
	# FRENTE / TABLERO: la otra vista de la pelea, al momento y guardada como
	# preferencia. Solo con la maqueta 3D (el tablero 2D no tiene frente).
	_view_btn = Button.new()
	_view_btn.name = "BoardViewToggle"
	_view_btn.focus_mode = Control.FOCUS_NONE
	_view_btn.custom_minimum_size = Vector2(0, 0)
	_view_btn.tooltip_text = Tr.t("LBL_COMBAT_VIEW_TIP")
	_view_btn.pressed.connect(toggle_combat_view)
	_view_btn.visible = false
	header.add_child(_view_btn)
	# Hueco a los dos lados para el boton ☰ MENU, que flota arriba a la derecha
	# por encima del tablero: en tablet la fila llegaba hasta el y el boton
	# Tablero/Frente quedaba debajo. A los dos lados para que siga centrada.
	_header_margin = MarginContainer.new()
	_header_margin.name = "BoardHeaderMargin"
	_header_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# La cabecera es una ficha oscura y fina del HUD (docs/28 §2.2), centrada.
	var header_card := PanelContainer.new()
	header_card.name = "BoardHeaderCard"
	header_card.add_theme_stylebox_override("panel", CT.hud_style())
	header_card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	header_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_card.add_child(header)
	_header_margin.add_child(header_card)
	column.add_child(_header_margin)
	_fit_header()
	HudRegistry.register("BattleScreen.turn", _turn_label)

	# Franja de iniciativa: la ronda entera, en el orden en que va a pasar (FR-006).
	_order_box = HBoxContainer.new()
	_order_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_order_box.add_theme_constant_override("separation", 5)
	column.add_child(_order_box)

	var grid_center := HBoxContainer.new()
	grid_center.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(grid_center)
	_grid_center = grid_center

	# Con el tablero 3D la maqueta ocupa toda la pantalla por detras: la columna
	# deja la cabecera arriba y los botones abajo, y este hueco en medio.
	_board_spacer = Control.new()
	_board_spacer.name = "Board3DSpacer"
	_board_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board_spacer.visible = false
	column.add_child(_board_spacer)

	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 2)
	_grid.add_theme_constant_override("v_separation", 2)
	grid_center.add_child(_grid)

	# Los botones tambien parten en dos filas si no caben (tres de 132 px y el
	# de abandonar no entran en un movil de 400).
	# La barra de acciones: pastillas con icono; TERMINAR TURNO es la principal
	# (verde). En telefono solo el icono (la palabra al mantener pulsado), para
	# que quepan en una fila y el tablero conserve su alto.
	var actions := HFlowContainer.new()
	actions.name = "BoardActions"
	actions.alignment = FlowContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("h_separation", 8)
	actions.add_theme_constant_override("v_separation", 6)
	_defend_btn = _make_action(Tr.t("BTN_DEFEND"), func(): _act_defend(), "army", "secondary")
	_defend_btn.name = "DefendButton"
	_wait_btn = _make_action(Tr.t("BTN_WAIT"), func(): _act_wait(), "clock", "secondary")
	_wait_btn.name = "WaitButton"
	_end_btn = _make_action(Tr.t("BTN_END_TURN"), func(): _act_end_turn(), "next", "primary")
	_end_btn.name = "EndTurnButton"
	# AVANZAR: solo en el frente, donde no hay casillas que tocar para moverse.
	_advance_btn = _make_action(Tr.t("BTN_ADVANCE"), func(): _act_advance(), "upgrade", "open")
	_advance_btn.name = "AdvanceButton"
	_advance_btn.visible = false
	actions.add_child(_advance_btn)
	# VER ALCANCE ENEMIGO (docs/15 §3, "Ensenar el combate"): conmuta, no actua.
	_threat_btn = _make_action(Tr.t("BTN_SHOW_THREAT"), func(): toggle_threat(), "access", "secondary")
	_threat_btn.name = "ThreatButton"
	_threat_btn.set_meta("tip", Tr.ti("LBL_THREAT_TIP"))
	actions.add_child(_threat_btn)
	actions.add_child(_defend_btn)
	actions.add_child(_wait_btn)
	actions.add_child(_end_btn)
	# Abandonar tambien desde el tablero: una expedicion se puede cortar sin
	# tener que ganar antes el encuentro que la esta matando.
	_abandon_board_btn = _make_action(Tr.t("BTN_ABANDON"), func(): _ask_abandon(), "back", "danger")
	_abandon_board_btn.name = "AbandonButton"
	_abandon_board_btn.visible = false
	actions.add_child(_abandon_board_btn)
	_auto_btn = _make_action(Tr.t("BTN_AUTO_RESOLVE"), func(): _act_auto_resolve(), "raid", "warn")
	_auto_btn.name = "AutoResolveButton"
	_auto_btn.set_meta("tip", Tr.t("HINT_AUTO_RESOLVE"))
	_auto_btn.visible = false
	actions.add_child(_auto_btn)
	column.add_child(actions)
	_actions_row = actions
	_skin_actions()

## Un boton de la barra de acciones. Su piel la pone _skin_action (texto o solo
## icono segun la pantalla).
func _make_action(text: String, callback: Callable, glyph: String = "", kind: String = "secondary") -> Button:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.set_meta("label", text)
	btn.set_meta("glyph", glyph)
	btn.set_meta("kind", kind)
	btn.pressed.connect(callback)
	_skin_action(btn)
	return btn

## Telefono (lienzo bajo): solo el icono y la palabra al mantener; si no,
## [icono] Palabra. Lo que diga el boton, siempre tambien en su tooltip.
func _skin_action(btn: Button, kind_override: String = "") -> void:
	var phone := CT.is_phone() if is_inside_tree() else CT.phone
	var label := String(btn.get_meta("label", btn.text))
	var glyph := String(btn.get_meta("glyph", ""))
	btn.text = "" if (phone and glyph != "") else label
	var tip := String(btn.get_meta("tip", ""))
	btn.tooltip_text = label if tip == "" else "%s\n%s" % [label, tip]
	var kind := kind_override if kind_override != "" else String(btn.get_meta("kind", "secondary"))
	CT.style_pill(btn, kind, 48 if phone else CT.BTN_SMALL, "hud", glyph)

func _skin_actions() -> void:
	for btn in [_advance_btn, _threat_btn, _defend_btn, _wait_btn, _end_btn, _abandon_board_btn, _auto_btn, _abandon_map_btn]:
		if btn != null:
			_skin_action(btn)
	_style_threat_button()

func _build_result_panel() -> void:
	_result_panel = PanelContainer.new()
	_result_panel.set_anchors_preset(Control.PRESET_CENTER)
	# Crece hacia los dos lados desde el centro: sin esto la esquina de arriba a
	# la izquierda quedaba en el centro y el panel salia corrido abajo a la derecha.
	_result_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_result_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_result_panel.custom_minimum_size = Vector2(340, 0)
	_result_panel.add_theme_stylebox_override("panel", CT.window_style())
	_result_panel.visible = false
	_root.add_child(_result_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_result_panel.add_child(vbox)

	_result_title = CT.label("", "display", CT.text("window"))
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_result_title)

	_result_detail = CT.label("", "body", CT.text("window", true))
	_result_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_detail.custom_minimum_size.x = 300
	vbox.add_child(_result_detail)

	var close := CT.pill_button(Tr.t("BTN_CLOSE"), "check", "primary", CT.h("big"))
	close.name = "ResultClose"
	close.pressed.connect(_close_board)
	vbox.add_child(close)

# ── Vista de mapa ────────────────────────────────────────────────────

func _build_map_view() -> void:
	_map_view = Control.new()
	_map_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_view.visible = false
	_root.add_child(_map_view)

	_map_sky = ColorRect.new()
	_map_sky.name = "MapSky"
	_map_sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_sky.visible = false
	_map_view.add_child(_map_sky)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = UITheme.MARGIN
	column.offset_top = UITheme.MARGIN
	column.offset_right = -UITheme.MARGIN
	column.offset_bottom = -UITheme.MARGIN
	column.add_theme_constant_override("separation", UITheme.SEPARATION)
	_map_view.add_child(column)

	# Cabecera en una ficha oscura del HUD: que campana y mision es, y por donde
	# va la columna ([banderin] 2/5).
	var header_card := PanelContainer.new()
	header_card.name = "MapHeader"
	header_card.add_theme_stylebox_override("panel", CT.hud_style())
	column.add_child(header_card)
	var header_col := VBoxContainer.new()
	header_col.add_theme_constant_override("separation", 2)
	header_card.add_child(header_col)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	header.add_child(CT.make_glyph("missions", 28))
	_map_title = CT.label(Tr.t("LBL_EXPEDITION_MAP"), "title", CT.text("hud"))
	_map_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_title.clip_text = true
	header.add_child(_map_title)
	_map_progress = CT.label("", "number", CT.text("hud", true))
	header.add_child(_map_progress)
	header_col.add_child(header)

	# Los bonos del draft van en la cabecera del mapa porque son la razon por la
	# que el jugador mira el mapa: deciden si la ruta arriesgada ya es asumible.
	_map_bonuses = CT.label("", "small", CT.tone_color("positive", "hud"))
	_map_bonuses.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header_col.add_child(_map_bonuses)

	# Lo que diria el tooltip, escrito: con el dedo es la unica forma de saber
	# que hay detras de un nodo antes de entrar en el.
	_map_hint = CT.label("", "small", CT.text("hud", true))
	_map_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header_col.add_child(_map_hint)

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
	_abandon_map_btn = _make_action(Tr.t("BTN_ABANDON"), func(): _ask_abandon(), "back", "danger")
	_abandon_map_btn.name = "AbandonMapButton"
	footer.add_child(_abandon_map_btn)
	column.add_child(footer)

func _build_draft_panel() -> void:
	# El draft no se puede esquivar: siempre hay al menos dos opciones aplicables
	# y una de ellas tiene que elegirse antes de volver al mapa (SC-009).
	_draft_backdrop = ColorRect.new()
	_draft_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draft_backdrop.color = Color(0.05, 0.04, 0.03, 0.6 if UITheme.high_contrast else 0.42)
	_draft_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_draft_backdrop.visible = false
	_root.add_child(_draft_backdrop)

	_draft_panel = PanelContainer.new()
	_draft_panel.set_anchors_preset(Control.PRESET_CENTER)
	# Crece hacia los dos lados desde el centro: sin esto la esquina de arriba a
	# la izquierda quedaba en el centro y el panel salia corrido abajo a la derecha.
	_draft_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_draft_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_draft_panel.custom_minimum_size = Vector2(360, 0)
	_draft_panel.add_theme_stylebox_override("panel", CT.window_style())
	_draft_panel.visible = false
	_root.add_child(_draft_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_draft_panel.add_child(vbox)

	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 8)
	head.add_child(CT.make_glyph("star", 30))
	var title := CT.label(Tr.t("LBL_DRAFT_TITLE"), "title", CT.text("window"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(title)
	vbox.add_child(head)

	_draft_cards = VBoxContainer.new()
	_draft_cards.add_theme_constant_override("separation", 8)
	vbox.add_child(_draft_cards)

func _build_report_panel() -> void:
	_report_panel = PanelContainer.new()
	_report_panel.set_anchors_preset(Control.PRESET_CENTER)
	# Crece hacia los dos lados desde el centro: sin esto la esquina de arriba a
	# la izquierda quedaba en el centro y el panel salia corrido abajo a la derecha.
	_report_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_report_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_report_panel.custom_minimum_size = Vector2(360, 0)
	_report_panel.add_theme_stylebox_override("panel", CT.window_style())
	_report_panel.visible = false
	_root.add_child(_report_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_report_panel.add_child(vbox)

	_report_title = CT.label("", "display", CT.text("window"))
	_report_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_report_title)

	# Botin (+) y bajas en iconos; debajo, las lineas cortas.
	_report_icons = HFlowContainer.new()
	_report_icons.name = "ReportIcons"
	_report_icons.alignment = FlowContainer.ALIGNMENT_CENTER
	_report_icons.add_theme_constant_override("h_separation", 10)
	_report_icons.add_theme_constant_override("v_separation", 4)
	vbox.add_child(_report_icons)

	_report_detail = CT.label("", "body", CT.text("window", true))
	_report_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_report_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_report_detail.custom_minimum_size.x = 320
	vbox.add_child(_report_detail)

	var back := CT.pill_button(Tr.t("BTN_BACK_TO_BASE"), "back", "primary", CT.h("big"))
	back.name = "BackToBase"
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
	return CombatManager.get_expedition()

func has_expedition() -> bool:
	return CombatManager.has_active_expedition()

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
	_cell_icons.clear()
	_cell_marks.clear()
	_cell_previews.clear()

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

			# La silueta del tipo de unidad. Va de hijo y no de `icon` del boton
			# porque asi se le reserva el hueco justo: todo el alto menos la
			# franja de abajo, que es de la barra de vida. Se tine desde fuera.
			var icon := TextureRect.new()
			icon.set_anchors_preset(Control.PRESET_FULL_RECT)
			icon.offset_left = 5
			icon.offset_right = -5
			icon.offset_top = 3
			icon.offset_bottom = -10
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon.visible = false
			cell.add_child(icon)
			_cell_icons.append(icon)

			# La vida se lee como una barra bajo la silueta — el unico numero que
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

			var mark := Panel.new()
			mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
			mark.visible = false
			cell.add_child(mark)
			_cell_marks.append(mark)

			# Dano previsto ("-18") o "✕" encima de la pieza: con el dedo no hay
			# tooltip, asi que se escribe en la casilla.
			var preview := Label.new()
			preview.set_anchors_preset(Control.PRESET_TOP_WIDE)
			preview.offset_top = -2
			preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			preview.add_theme_font_size_override("font_size", maxi(11, _cell_size / 4))
			preview.add_theme_color_override("font_outline_color", UITheme.OUTLINE_COLOR)
			preview.add_theme_constant_override("outline_size", 4)
			preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
			preview.visible = false
			cell.add_child(preview)
			_cell_previews.append(preview)

## Mantiene el tablero dentro de la ventana de un movil sin dejar que las celdas
## bajen de un tamano tocable (quickstart E9).
func _recalculate_cell_size() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	# Se descuentan los huecos entre casillas (2 px) y el borde del marco: con
	# 400 px la ultima columna se salia un pixel (402 de 401).
	var gaps := 2.0 * float(_board.x - 1) + 12.0
	var by_width: float = (vp.x * 0.92 - gaps) / float(_board.x)
	var by_height: float = (vp.y * 0.58 - 2.0 * float(_board.y - 1)) / float(_board.y)
	_cell_size = int(clampf(minf(by_width, by_height), 34.0, 62.0))

## Lo mismo para el mapa: el nodo es un boton y un boton tiene que poder pulsarse
## con el pulgar, asi que nunca baja de 44 px (T021, quickstart E9).
func _recalculate_node_size() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_node_size = int(clampf(minf(vp.x * 0.14, vp.y * 0.12), float(UITheme.MIN_BTN_H), 64.0))

## Reserva a cada lado de la cabecera el ancho del boton ☰ MENU (el de
## PauseMenu: palabra entera, o solo el icono en pantallas estrechas).
func _fit_header() -> void:
	if _header_margin == null:
		return
	var narrow: bool = get_viewport().get_visible_rect().size.x < UILayoutConfig.NARROW_WIDTH
	var btn_w: float = UITheme.MIN_BTN_H if narrow else PauseMenuScript.MENU_BTN_MIN_W
	var reserve := int(btn_w + 2.0 * PauseMenuScript.MENU_BTN_MARGIN)
	_header_margin.add_theme_constant_override("margin_left", reserve)
	_header_margin.add_theme_constant_override("margin_right", reserve)

func _on_viewport_resized() -> void:
	_fit_header()
	_skin_actions()
	if _view == View.BOARD and _uses_3d():
		_queue_margin_update()
		_refresh()
	elif _view == View.BOARD:
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
	_armed_node = -1
	_refresh_map()

func _on_game_load_completed() -> void:
	if has_expedition():
		open_map()

## Pone la pantalla al dia con CombatManager sin esperar a ninguna senal: mapa si
## hay campana, y el draft si hay cartas sin elegir. Sin esto, un draft pendiente
## cargado a espaldas de la UI dejaba el mapa sin respuesta (select_node rechaza
## mientras haya draft) y la partida bloqueada. Idempotente: si la senal ya
## llego, no hace nada.
func sync_with_state() -> void:
	if not has_expedition() or CombatManager.is_board_open():
		return
	if _view == View.NONE:
		open_map()
	if CombatManager.has_pending_draft() and not is_draft_open() and _pending_draft.is_empty():
		_on_draft_offered(CombatManager.get_draft_options())

func _on_expedition_ended(result: int, rewards: Dictionary, casualties: Dictionary) -> void:
	# Con la maqueta animando la ultima caida, el informe espera a que se vea.
	_after_board_animations(_show_expedition_report.bind(result, rewards, casualties))

func _show_expedition_report(result: int, rewards: Dictionary, casualties: Dictionary) -> void:
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
			_report_title.add_theme_color_override("font_color", CT.tone_color("positive"))
		2:
			_report_title.text = Tr.t("LBL_ABANDONED")
			_report_title.add_theme_color_override("font_color", CT.tone_color("warning"))
		_:
			_report_title.text = Tr.t("LBL_DEFEAT")
			_report_title.add_theme_color_override("font_color", CT.tone_color("danger"))
	for child in _report_icons.get_children():
		_report_icons.remove_child(child)
		child.queue_free()
	if not rewards.is_empty():
		_report_icons.add_child(CT.cost_row(rewards, {}, "+"))
	if not casualties.is_empty():
		_report_icons.add_child(CT.roster_discs(casualties, CT.kind_fill("disabled"), 40))
	_report_icons.visible = _report_icons.get_child_count() > 0

	var lines: Array = []
	if rewards.is_empty():
		lines.append(Tr.t("LBL_NO_REWARDS"))
	else:
		lines.append("%s: %s" % [Tr.t("LBL_REWARDS"), _resource_list(rewards)])
	if casualties.is_empty():
		lines.append(Tr.t("LBL_NO_CASUALTIES"))
	else:
		lines.append("%s: %s" % [Tr.t("LBL_CASUALTIES"), _unit_list(casualties)])
	# Lo que solo se consigue fuera (repuestos, colonos, planos, rebaja del
	# Diezmo), ya aplicado a la colonia: lo deja CombatManager en el parte.
	var last: Dictionary = CombatManager.get_last_result()
	if bool(last.get("expedition", false)):
		for text in SkirmishPanelScript.loot_lines(last.get("loot", {})):
			lines.append(String(text))
		# Tres campanas: como queda la campana (el progreso se apunta justo
		# despues de este parte, asi que se cuenta desde la mision jugada).
		var domain: String = String(last.get("campaign_domain", ""))
		if domain != "":
			var camp_name: String = Tr.t("CAMP_NAME_" + domain.to_upper())
			if result == 0:
				lines.append(Tr.t("CAMP_REPORT_WON") % [camp_name,
					maxi(1, CombatManager.campaign_mission_number(domain, int(last.get("campaign_mission", 0)))),
					CombatManager.campaign_total(domain)])
				if bool(last.get("campaign_boss", false)):
					lines.append(Tr.t("CAMP_REPORT_BOSS") % camp_name)
					# Una sola llave: el jefe entrega su pieza del CG nivel 3.
					if GameConfig.hq_needs_pieces(GameConfig.max_building_level):
						lines.append(Tr.t("CAMP_REPORT_PIECE") % CombatManager.piece_name(domain))
			else:
				lines.append(Tr.t("CAMP_REPORT_RETRY"))
		# Volverse el Imperio: como queda la isla (el progreso se apunta justo
		# despues de este parte: se cuenta desde la mision jugada).
		var island: String = String(last.get("conquest_island", ""))
		if island != "":
			var island_name: String = Tr.t(ConquestGenerator.island_name_key(island))
			var played: int = int(last.get("conquest_mission", 0))
			if result == 0:
				lines.append(Tr.t("EMP_REPORT_WON") % [island_name, played + 1, ConquestGenerator.mission_count(island)])
				if ConquestGenerator.is_final(island, played):
					lines.append(Tr.t("EMP_REPORT_CONQUERED") % island_name)
			else:
				lines.append(Tr.t("CAMP_REPORT_RETRY"))
	_report_detail.text = "\n".join(lines)

	_report_panel.visible = true
	visible = true
	_sync_world_render()

# ── Draft ────────────────────────────────────────────────────────────

func _on_draft_offered(options: Array) -> void:
	_pending_draft = options.duplicate()
	_after_board_animations(_offer_pending_draft)

func _offer_pending_draft() -> void:
	# Si el parte del encuentro sigue en pantalla, el draft espera su turno: dos
	# modales a la vez convierten la recompensa en un accidente.
	if _result_panel.visible or _pending_draft.is_empty():
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
	card.custom_minimum_size = Vector2(0, 64)
	card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	CT.army_card_button(card)
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
	CombatManager.apply_draft(index)

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
	_armed_node = -1
	_build_map()
	_paint_map_domain()
	_view = View.MAP
	_board_open = false
	_board_view.visible = false
	_result_panel.visible = false
	_report_panel.visible = false
	_map_view.visible = true
	visible = true
	_sync_world_render()

## Tres campanas: el titulo dice que campana y que mision es, y el fondo pinta
## el agua (mar) o el cielo (aire). Fuera de campana, el mapa de siempre.
func _paint_map_domain() -> void:
	var domain: String = ""
	var mission: int = -1
	if _run != null and _run.has_method("campaign_domain"):
		domain = _run.campaign_domain()
		mission = _run.campaign_mission()
	_map_title.text = Tr.t("LBL_EXPEDITION_MAP")
	_map_sky.visible = false
	# Volverse el Imperio: una mision de conquista dice la isla y la mision, y
	# pinta el fondo de su medio como las campanas.
	if domain == "" and _run != null and _run.has_method("is_conquest") and _run.is_conquest():
		domain = _run.conquest_domain()
		var island: String = _run.conquest_island()
		_map_title.text = "%s · %s" % [Tr.t(ConquestGenerator.island_name_key(island)),
			Tr.t(ConquestGenerator.mission_name_key(island, _run.conquest_mission()))]
	elif domain != "":
		_map_title.text = "%s · %s" % [Tr.t("CAMP_NAME_" + domain.to_upper()),
			Tr.t(ExpeditionGenerator.campaign_mission_name_key(domain, mission))]
	if domain == "":
		return
	match domain:
		"sea":
			_map_sky.color = Color(UITheme.BOARD_WATER, 0.55)
			_map_sky.visible = true
		"air":
			_map_sky.color = Color(UITheme.INFO.lightened(0.15), 0.25)
			_map_sky.visible = true

## Que campana es el mapa abierto ("" si no es de campana). Para pruebas.
func map_domain() -> String:
	if _run == null or not _run.has_method("campaign_domain"):
		return ""
	return _run.campaign_domain()

func _build_map() -> void:
	for child in _map_canvas.get_children():
		child.queue_free()
	_map_buttons.clear()
	_map_risk_labels.clear()
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
		float(MAP_PAD * 2 + (widest - 1) * row_h + _node_size + MAP_ROW_GAP)
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

		# El riesgo, escrito bajo el nodo. El color del fondo lo repite, pero
		# el color solo no basta, y el tooltip no existe en un movil.
		var risk_label := CT.label("", "small", CT.text("hud", true))
		risk_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		risk_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		risk_label.clip_text = true
		risk_label.size = Vector2(float(_node_size + MAP_COL_GAP - 4), float(MAP_ROW_GAP))
		risk_label.position = _node_positions[i] + Vector2(-float(MAP_COL_GAP - 4) * 0.5, float(_node_size))
		_map_canvas.add_child(risk_label)
		_map_risk_labels.append(risk_label)

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
		var reachable: bool = _run.can_select(i)
		# El nodo en el que esta la columna y que aun no se ha peleado (una partida
		# cargada a mitad de nodo): se pulsa para volver a su tablero. Hasta
		# ganarlo, ninguna salida se enciende.
		var fightable: bool = i == current and _run.needs_fight()

		btn.text = Tr.t("LBL_BOSS") if is_boss else str(_roster_size(node))
		# Un soldado junto al numero: dice que son enemigos (ronda de pruebas 1.0).
		# En mar y aire, el barco o el avion que mas trae (ronda de pruebas 1.1).
		btn.icon = null if is_boss else UITheme.unit_icon(node_lead_unit(node), 24)
		btn.add_theme_constant_override("icon_max_width", 22)
		btn.add_theme_color_override("icon_normal_color", CT.WHITE)
		btn.add_theme_color_override("icon_disabled_color", CT.c("hud", "TEXT_DIM"))
		btn.disabled = not (reachable or fightable)
		btn.tooltip_text = _node_tooltip(node, i == current, cleared, reachable)
		if fightable:
			btn.tooltip_text += "\n" + Tr.t("LBL_NODE_FIGHT")
		_style_node(btn, i == current, cleared, reachable, is_boss, int(node.get("risk", 0)), i == _armed_node)
		if i < _map_risk_labels.size():
			var risk_label: Label = _map_risk_labels[i]
			risk_label.text = node_risk_text(i)
			var risk_col: Color = _risk_color(int(node.get("risk", 0))).lightened(0.35)
			risk_label.add_theme_color_override("font_color", risk_col if (reachable or fightable or i == _armed_node) else CT.text("hud", true))

	_map_progress.text = Tr.t("LBL_EXPEDITION_PROGRESS") % [_run.nodes_cleared(), map.size()]
	_map_bonuses.text = _draft_summary()
	_map_hint.text = map_hint_text()
	_abandon_map_btn.visible = active
	_map_canvas.queue_redraw()

## El riesgo se pinta en el fondo y se dice con palabras en el tooltip: el color
## solo nunca es suficiente.
func _style_node(btn: Button, is_current: bool, cleared: bool, reachable: bool, is_boss: bool, risk: int, armed: bool = false) -> void:
	# Piel de juguete (docs/28): fichas redondas con tinta, color vivo por
	# riesgo donde se puede ir, apagado donde no.
	var background: Color = _risk_color(risk)
	var border: Color = CT.INK
	var width: int = 3

	if is_boss:
		background = CT.sem("DANGER")
	if cleared:
		background = CT.sem("POSITIVE")
	if not (reachable or is_current or cleared):
		background = background.lerp(CT.c("hud", "CARD_ALT"), 0.7)
	if is_current:
		border = CT.sem("ACCENT")
		width = 5
	if armed:
		# Armado por un primer toque: brilla y se aclara, para que el segundo
		# toque se sienta como confirmar, no como adivinar.
		background = background.lightened(0.25)
		border = CT.WHITE
		width = 6

	var style := CT.box(background, border, width, int(_node_size * 0.5), 2, 0, 2 if (reachable or is_current) else 0, "hud")
	var hover := CT.box(background.lightened(0.12), border, width, int(_node_size * 0.5), 2, 0, 2 if (reachable or is_current) else 0, "hud")
	for state in ["normal", "pressed", "disabled", "focus"]:
		btn.add_theme_stylebox_override(state, style)
	btn.add_theme_stylebox_override("hover", hover)
	var text_color: Color = CT.WHITE if (reachable or is_current or cleared) else CT.c("hud", "TEXT_DIM")
	btn.add_theme_color_override("font_color", text_color)
	btn.add_theme_color_override("font_disabled_color", text_color)
	btn.add_theme_color_override("font_hover_color", CT.WHITE)
	btn.add_theme_color_override("font_outline_color", CT.INK)
	btn.add_theme_constant_override("outline_size", 4)
	btn.add_theme_font_override("font", CT.title_font())
	btn.add_theme_font_size_override("font_size", CT.fs("small"))

func _risk_color(risk: int) -> Color:
	match clampi(risk, 0, 2):
		0:
			return CT.sem("POSITIVE")
		1:
			return CT.sem("WARNING")
		_:
			return CT.sem("DANGER")

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

## El texto que va bajo el nodo: su riesgo en palabras. El del jefe tambien lo
## dice, porque el jefe siempre es riesgo alto y eso tiene que leerse.
func node_risk_text(index: int) -> String:
	if _run == null or index < 0 or index >= _run.map.size():
		return ""
	var node: Dictionary = _run.map[index]
	if bool(node.get("cleared", false)):
		return Tr.t("LBL_NODE_CLEARED")
	return _risk_text(int(node.get("risk", 0)))

## La linea bajo la cabecera del mapa. Con un nodo armado describe ese nodo y
## pide el segundo toque; si no, explica como se entra segun el dispositivo.
func map_hint_text() -> String:
	if _run == null or not _run.is_active():
		return ""
	if _armed_node >= 0 and _armed_node < _run.map.size():
		var node: Dictionary = _run.map[_armed_node]
		var parts: Array = [_risk_text(int(node.get("risk", 0))), Tr.t("LBL_NODE_ENEMIES") % _roster_size(node)]
		if bool(node.get("is_boss", false)):
			parts.append(Tr.t("LBL_BOSS"))
		return "%s. %s" % [" - ".join(parts), Tr.t("LBL_NODE_TAP_AGAIN")]
	return Tr.t("LBL_NODE_PICK_TOUCH") if _touch_mode else Tr.t("LBL_NODE_PICK_MOUSE")

## La unidad que mas trae el enemigo en ese nodo (la del icono del mapa); un
## soldado si no trae a nadie.
static func node_lead_unit(node: Dictionary) -> String:
	var best := "infantry"
	var most := 0
	var roster: Dictionary = node.get("enemy_roster", {})
	for id in roster:
		if int(roster[id]) > most:
			most = int(roster[id])
			best = String(id)
	return best

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
			var color: Color = CT.sem("ACCENT") if live else CT.c("hud", "CARD_BORDER")
			# Con tinta debajo: el camino de juguete se lee sobre la pizarra.
			_map_canvas.draw_line(from_point, to_point, CT.INK, 8.0 if live else 6.0, true)
			_map_canvas.draw_line(from_point, to_point, color, 5.0 if live else 3.0, true)

## Lo que la columna lleva encima ahora mismo, en el orden en que lo eligio.
func _draft_summary() -> String:
	if _run == null or _run.draft_picks.is_empty():
		return Tr.t("LBL_NO_DRAFT_BONUSES")
	var parts: Array = []
	for option in _run.draft_picks:
		parts.append(draft_text(option))
	return Tr.t("LBL_DRAFT_BONUSES") % "   ".join(parts)

func _choose_node(index: int) -> void:
	if _run == null:
		return
	if index == _run.current_node and _run.needs_fight():
		CombatManager.enter_current_node()
		return
	if not _run.can_select(index):
		return
	# Con el dedo, el primer toque solo arma el nodo: sin tooltip, entrar al
	# primer toque es entrar a ciegas en un nodo de riesgo alto.
	if _touch_mode and _armed_node != index:
		_armed_node = index
		_refresh_map()
		return
	_armed_node = -1
	map_node_chosen.emit(index)
	CombatManager.select_node(index)

## El nodo armado por un primer toque, o -1.
func armed_node() -> int:
	return _armed_node

## Fuerza el modo tactil (pruebas). En partida lo decide `_input`.
func set_touch_mode(enabled: bool) -> void:
	_touch_mode = enabled
	if _board3d != null:
		_board3d.set_touch_mode(enabled)
	if not enabled:
		_armed_node = -1
	if _view == View.MAP:
		_refresh_map()

## Aprende si el jugador usa el dedo o el raton. Un toque real llega como
## ScreenTouch antes que el raton emulado; un raton de verdad no trae el id de
## emulacion. No consume nada: solo mira.
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if not _touch_mode:
			set_touch_mode(true)
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		if _touch_mode:
			set_touch_mode(false)

func map_button_count() -> int:
	return _map_buttons.size()

func map_button(index: int) -> Button:
	if index < 0 or index >= _map_buttons.size():
		return null
	return _map_buttons[index]

## Acceso a una casilla del tablero por coordenadas, para pruebas y depuracion.
func board_cell(coords: Vector2i) -> Button:
	var index: int = _cell_index(coords)
	return null if index < 0 else _cells[index]

## El retrato de una casilla. Sin textura y oculto mientras la casilla este vacia.
func board_cell_icon(coords: Vector2i) -> TextureRect:
	var index: int = _cell_index(coords)
	return null if index < 0 else _cell_icons[index]

## La marca de bando de una casilla. Lleva meta "side" = "ally" / "enemy" / "".
func board_cell_mark(coords: Vector2i) -> Panel:
	var index: int = _cell_index(coords)
	return null if index < 0 or index >= _cell_marks.size() else _cell_marks[index]

## Las fichas de la franja de iniciativa, en el orden en que van a jugar.
func order_chips() -> Array:
	return _order_box.get_children() if _order_box != null else []

func _cell_index(coords: Vector2i) -> int:
	if coords.x < 0 or coords.y < 0 or coords.x >= _board.x or coords.y >= _board.y:
		return -1
	var index: int = coords.y * _board.x + coords.x
	return index if index < _cells.size() else -1

# ── Abandono ─────────────────────────────────────────────────────────

func _ask_abandon() -> void:
	_confirm_dialog.dialog_text = Tr.t("MSG_CONFIRM_ABANDON")
	_confirm_dialog.popup_centered()

func _do_abandon() -> void:
	abandon_confirmed.emit()
	CombatManager.abandon_expedition()

func is_confirming_abandon() -> bool:
	return _confirm_dialog != null and _confirm_dialog.visible

# ── Senales de encuentro ─────────────────────────────────────────────

func _on_encounter_started(index: int, is_boss: bool) -> void:
	_board = CombatManager.get_board_size()
	_board_style = _forced_style if _forced_style != "" else pick_board_style(
		DisplayServer.get_name(), ViewMode.current(get_tree()), _graphics_quality())
	_title_label.text = _encounter_title(index, is_boss)
	_result_panel.visible = false
	_report_panel.visible = false
	if _board_style == "3d":
		_open_board_3d(index)
	else:
		_show_board_2d()
		_recalculate_cell_size()
		_build_grid()
	_refresh_view_button()
	_open_board()
	_refresh()

## El encuentro de una expedicion se numera; el suelto no, porque no hay ninguna
## serie de la que forme parte.
func _encounter_title(index: int, is_boss: bool) -> String:
	if is_boss:
		return "%s  %s" % [Tr.t("LBL_ENCOUNTER_N") % (index + 1), Tr.t("LBL_BOSS")]
	if has_expedition():
		return Tr.t("LBL_ENCOUNTER_N") % (index + 1)
	# Un tablero de defensa (el Diezmo, el Impuesto de prueba) no es una mision.
	if CombatManager.is_defending():
		return Tr.t("LBL_DEFENSE_FIGHT")
	return Tr.t("LBL_SKIRMISH_FIGHT")

func _on_turn_started(side: int, uid: int) -> void:
	if _board_open and _uses_3d():
		_board3d.board.push({"e": "turn", "side": side, "uid": uid})
	_refresh()

func _on_unit_moved(uid: int, from: Vector2i, to: Vector2i) -> void:
	if _board_open and _uses_3d():
		_board3d.board.push({"e": "move", "uid": uid, "from": from, "to": to})
	_refresh()

func _on_unit_attacked(attacker_uid: int, target_uid: int, damage: int) -> void:
	if _board_open and _uses_3d():
		_board3d.board.push({"e": "attack", "attacker": attacker_uid, "target": target_uid, "damage": damage})
	else:
		var target := CombatManager.get_unit(target_uid)
		if target != null:
			_spawn_damage_number(target.position, damage)
	_refresh()

func _on_unit_died(uid: int, _side: int) -> void:
	if _board_open and _uses_3d():
		_board3d.board.push({"e": "die", "uid": uid})
	_refresh()

func _on_unit_defended(uid: int) -> void:
	if _board_open and _uses_3d():
		_board3d.board.push({"e": "defend", "uid": uid})
	_refresh()

func _on_encounter_ended(victory: bool, turns_used: int) -> void:
	_set_actions_enabled(false)
	# En 3D el parte sale cuando la maqueta termina de contar la pelea.
	_after_board_animations(_show_encounter_result.bind(victory, turns_used))

func _show_encounter_result(victory: bool, turns_used: int) -> void:
	close_unit_card()
	_refresh()
	_result_title.text = Tr.t("LBL_VICTORY") if victory else Tr.t("LBL_DEFEAT")
	_result_title.add_theme_color_override("font_color", CT.tone_color("positive" if victory else "danger"))
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

	# Una dotacion caida deja su torre dañada (CombatManager.damage_towers_for_lost_crews).
	var towers: int = int(result.get("towers_damaged", 0))
	if towers > 0:
		lines.append(Tr.t("LBL_REPORT_TOWERS_DAMAGED") % towers)

	var morale_delta: int = int(result.get("morale_delta", 0))
	if morale_delta != 0:
		lines.append(Tr.t("LBL_MORALE_DELTA") % morale_delta)

	# Salidas (doc 21 §3): como acabo, lo exclusivo del nodo y la cura al seguir.
	if bool(result.get("routed", false)):
		lines.insert(0, Tr.t("LBL_ENEMY_ROUTED"))
	if bool(result.get("auto_resolved", false)):
		lines.insert(0, Tr.t("LBL_AUTO_RESOLVED"))
	for text in SkirmishPanelScript.loot_lines(result.get("loot", {})):
		lines.append(String(text))
	var healed: float = float(result.get("healed_pct", 0.0))
	if healed > 0.0:
		lines.append(Tr.t("LBL_HEALED_BETWEEN") % roundi(healed * 100.0))
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
	if not _board_open:
		return
	_compute_overlays()
	_refresh_unit_card()
	if _uses_3d():
		_refresh_header()
		_refresh_board3d()
		_refresh_order()
		_refresh_actions()
		return
	if _cells.is_empty():
		return
	_refresh_header()
	_refresh_cells()
	_refresh_order()
	_refresh_actions()

func _refresh_header() -> void:
	# Al agotar el tope el contador ya ha pasado a la ronda siguiente: la
	# cabecera decia "Ronda 21 / 20" detras del parte de derrota.
	var limit := CombatManager.get_turn_limit()
	_round_label.text = Tr.t("ARMY2_ROUND") % [mini(CombatManager.get_round(), limit), limit]
	_round_label.tooltip_text = "%s\n%s" % [Tr.t("LBL_ROUND") % [mini(CombatManager.get_round(), limit), limit], Tr.t("ARMY2_ROUND_TIP")]
	var active := CombatManager.get_active_unit()
	if active == null:
		_turn_label.text = ""
		return
	var is_player: bool = active.side == PLAYER
	_turn_label.text = Tr.t("LBL_TURN_PLAYER") if is_player else Tr.t("LBL_TURN_ENEMY")
	_turn_label.add_theme_color_override("font_color", CT.tone_color("positive" if is_player else "danger", "hud"))

func _refresh_cells() -> void:
	var active := CombatManager.get_active_unit()
	var moves: Array = []
	var targets: Array = []
	if active != null and CombatManager.is_player_turn():
		moves = CombatManager.get_valid_moves(active.uid)
		targets = CombatManager.get_valid_targets(active.uid)

	var boss: int = boss_uid()
	_terrain_now = BoardLayout.terrain_of(CombatManager.get_encounter())
	var enc_now = CombatManager.get_encounter()
	_cover_now = (enc_now.cover as Dictionary).duplicate() if enc_now != null and enc_now.get("cover") is Dictionary else {}

	for y in range(_board.y):
		for x in range(_board.x):
			var index: int = y * _board.x + x
			var cell: Button = _cells[index]
			var bar: ProgressBar = _cell_bars[index]
			var icon: TextureRect = _cell_icons[index]
			var coords := Vector2i(x, y)
			var unit := CombatManager.get_unit_at(coords)
			_style_cell(cell, bar, icon, coords, unit, active, moves, targets, boss)
			_paint_air_overhead(cell, coords, unit)
			if index < _cell_marks.size():
				_paint_side_mark(_cell_marks[index], unit)
			if index < _cell_previews.size():
				_paint_cell_preview(_cell_previews[index], unit, targets)

## Tierra con agua al lado (en cruz): un islote del mar abierto. En la costa
## la tierra toca la orilla, no el agua, asi que no cuenta.
static func is_islet(terrain: Dictionary, cell: Vector2i) -> bool:
	if terrain.is_empty() or BoardLayout.cell_kind(terrain, cell) != BoardLayout.TERRAIN_LAND:
		return false
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if terrain.has(cell + d) and BoardLayout.cell_kind(terrain, cell + d) == BoardLayout.TERRAIN_WATER:
			return true
	return false

func _style_cell(cell: Button, bar: ProgressBar, icon: TextureRect, coords: Vector2i,
		unit: CombatUnit, active: CombatUnit, moves: Array, targets: Array,
		boss: int = -1) -> void:
	var background: Color = UITheme.BOARD_EMPTY
	var border: Color = UITheme.ACCENT_DIM
	var border_width: int = 1
	var text_color: Color = UITheme.TEXT_BRIGHT
	var is_boss := false

	if unit == null:
		cell.text = ""
		icon.texture = null
		icon.visible = false
		bar.visible = false
		match BoardLayout.cell_kind(_terrain_now, coords):
			BoardLayout.TERRAIN_WATER:
				background = UITheme.BOARD_WATER
				border = UITheme.INFO.darkened(0.2)
			BoardLayout.TERRAIN_SHORE:
				background = UITheme.BOARD_SHORE
			_:
				# Un islote del mar abierto (tierra que toca agua sin orilla): roca,
				# no una casilla vacia casi negra (ronda visual de la 1.1).
				if is_islet(_terrain_now, coords):
					background = UITheme.BOARD_SHORE.darkened(0.1)
					border = UITheme.BOARD_SHORE.lightened(0.3)
					border_width = 2
		# Parapeto del Bastion: casilla de sacos (borde de laton); quien se
		# ponga encima defiende mas. Se dice en el tooltip.
		cell.tooltip_text = ""
		if _cover_now.has(coords):
			background = UITheme.BOARD_SHORE.lerp(UITheme.ACCENT_DIM, 0.5)
			border = UITheme.ACCENT
			border_width = 2
			cell.tooltip_text = Tr.t("LBL_COVER_CELL_TIP") % int(_cover_now[coords])
		if _ov_no_fire.has(coords):
			# Demasiado cerca para la artilleria: ✕ en la casilla.
			cell.text = "✕"
			text_color = UITheme.DANGER.lightened(0.3)
		if moves.has(coords):
			background = UITheme.BOARD_MOVE
			border = UITheme.WARNING if _ov_threat.has(coords) else UITheme.INFO
			if _ov_threat.has(coords):
				border_width = 2
		elif _ov_fire.has(coords):
			background = UITheme.DANGER.darkened(0.45)
		elif _ov_threat.has(coords):
			background = UITheme.WARNING.darkened(0.5)
	else:
		is_boss = boss >= 0 and unit.uid == boss
		text_color = _paint_unit_face(cell, icon, unit)
		bar.visible = true
		bar.value = float(unit.hp) / float(maxi(1, unit.max_hp))
		_style_health_bar(bar, unit)
		background = UITheme.POSITIVE.darkened(0.45) if unit.side == PLAYER else UITheme.DANGER.darkened(0.35)
		border = UITheme.POSITIVE if unit.side == PLAYER else UITheme.DANGER
		if _cover_now.has(coords) and unit.layer() != "air":
			# A cubierto tras el parapeto: borde de laton (lo de abajo manda).
			border = UITheme.ACCENT
			border_width = 2
		if targets.has(unit.uid):
			background = UITheme.BOARD_TARGET
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
	# El jefe va el ultimo a proposito: el halo de laton se suma a lo que ya
	# diga el borde (activo, alcanzable, en guardia) en vez de taparlo.
	if is_boss:
		UITheme.mark_boss(style)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		cell.add_theme_stylebox_override(state, style)
	cell.add_theme_color_override("font_color", text_color)
	cell.add_theme_color_override("font_hover_color", text_color)

## Aire y mar: un avion encima de una unidad de superficie no tiene casilla
## propia en 2D (la casilla pinta la de superficie, get_unit_at). Sin marca, el
## avion desaparecia. Su silueta pequena arriba en el centro, con el tinte de su
## bando, dice "aqui arriba vuela uno" (ronda visual de la 1.1). La etiqueta se
## crea la primera vez que hace falta y luego solo se muestra u oculta.
func board_air_mark(coords: Vector2i) -> TextureRect:
	var index: int = coords.y * _board.x + coords.x
	if index < 0 or index >= _cells.size():
		return null
	return _cells[index].get_node_or_null("AirOverhead") as TextureRect

func _paint_air_overhead(cell: Button, coords: Vector2i, shown: CombatUnit) -> void:
	var flier: CombatUnit = null
	if shown != null and shown.layer() != "air":
		var enc = CombatManager.get_encounter()
		if enc != null:
			flier = enc.get_unit_at_layer(coords, "air")
	var mark: TextureRect = cell.get_node_or_null("AirOverhead") as TextureRect
	if flier == null:
		if mark != null:
			mark.visible = false
		return
	if mark == null:
		mark = TextureRect.new()
		mark.name = "AirOverhead"
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cell.add_child(mark)
	var side := float(_cell_size) * 0.42
	mark.size = Vector2(side, side)
	mark.position = Vector2((float(_cell_size) - side) * 0.5, -side * 0.35)
	mark.texture = UITheme.unit_icon(flier.unit_id, int(side))
	mark.modulate = UITheme.unit_face_color(flier.side == PLAYER, flier.has_acted).lightened(0.15)
	mark.visible = true

## La cara de una unidad: la silueta de su tipo, tenida con el color de su bando
## y apagada si ya gasto el turno. Si el PNG no esta en disco se vuelve a la
## inicial del nombre, que es como se pintaba antes — una unidad sin icono se
## sigue viendo, que es lo unico innegociable.
##
## Devuelve el color con el que hay que escribir el texto de la celda, para que
## la inicial de repuesto distinga bando igual que lo haria el icono.
func _paint_unit_face(cell: Button, icon: TextureRect, unit: CombatUnit) -> Color:
	var tint: Color = UITheme.unit_face_color(unit.side == PLAYER, unit.has_acted)
	# La escala del sistema de iconos que cabe en la celda (34-62 px).
	var texture := UITheme.unit_icon(unit.unit_id, _cell_size)
	icon.texture = texture
	icon.visible = texture != null
	icon.modulate = tint
	cell.text = "" if texture != null else _unit_glyph(unit)
	return tint

## Circulo arriba a la izquierda = nuestro; rombo arriba a la derecha = enemigo.
## Dos formas en dos esquinas: se distinguen en gris, de lejos y con el pulgar
## tapando media casilla.
func _paint_side_mark(mark: Panel, unit: CombatUnit) -> void:
	if unit == null:
		mark.visible = false
		mark.set_meta("side", "")
		return
	var is_player: bool = unit.side == PLAYER
	var side_size: float = maxf(8.0, float(_cell_size) * 0.2)
	mark.size = Vector2(side_size, side_size)
	mark.pivot_offset = mark.size * 0.5
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.unit_icon_tint(is_player)
	style.border_color = UITheme.OUTLINE_COLOR
	style.set_border_width_all(2)
	# Nuestras fichas llevan el color del regimiento (Cuartel > REGIMIENTO; de
	# serie, el de la colonia). El bando lo sigue diciendo la FORMA (circulo /
	# rombo), asi que el color es libre. Con estrellas, un aro de laton.
	var look: Dictionary = ArmyManager.get_regiment_look() if is_player else {}
	if is_player:
		style.bg_color = look["color"]
		if int(look["stars"]) > 0:
			style.border_color = UITheme.ACCENT
	mark.set_meta("colony_color", String(look["color_id"]) if is_player else "")
	if is_player:
		style.set_corner_radius_all(int(side_size))
		mark.rotation = 0.0
		mark.position = Vector2(4.0, 4.0)
	else:
		style.set_corner_radius_all(0)
		mark.rotation = deg_to_rad(45.0)
		mark.position = Vector2(float(_cell_size) - side_size - 5.0, 5.0)
	mark.add_theme_stylebox_override("panel", style)
	mark.set_meta("side", "ally" if is_player else "enemy")
	mark.visible = true

func _style_health_bar(bar: ProgressBar, unit: CombatUnit) -> void:
	var ratio: float = float(unit.hp) / float(maxi(1, unit.max_hp))
	var fill := StyleBoxFlat.new()
	fill.bg_color = UITheme.POSITIVE if ratio > 0.5 else (UITheme.WARNING if ratio > 0.25 else UITheme.DANGER)
	fill.set_corner_radius_all(1)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(UITheme.BG_DARK, 0.9)
	bg.set_corner_radius_all(1)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", bg)

## Una letra por tipo de unidad, tomada del nombre traducido para que siga
## leyendose en ingles. Es el repuesto de la silueta: solo se ve si el PNG del
## icono no esta importado.
func _unit_glyph(unit: CombatUnit) -> String:
	var def := GameConfig.get_unit_def(unit.unit_id)
	var label: String = Tr.t(def.get("name", unit.unit_id))
	return label.substr(0, 1).to_upper() if label != "" else "?"

## Cual de los enemigos lleva el marco de jefe, o -1 si esta pelea no es la del
## jefe. El encuentro sabe que lo es pero no quien: la banda del jefe es la
## escuadra de siempre mas la pieza mas pesada que la era puede poner, asi que el
## jefe es el enemigo de mas poder y, a igualdad, el mas duro.
##
## Se mira sobre todas las unidades del encuentro, vivas o muertas, para que
## matarlo no ascienda a otra al puesto. En la era 1, donde el enemigo solo puede
## fielder infanteria, todos empatan y el marco recae en el primero que formo:
## sigue siendo uno solo, que es lo que el jugador necesita ver.
func boss_uid() -> int:
	var encounter: Encounter = CombatManager.get_encounter()
	if encounter == null or not encounter.is_boss:
		return -1
	var best: int = -1
	var best_power: int = -1
	var best_hp: int = -1
	for unit in encounter.units:
		if unit.side != ENEMY:
			continue
		var power: int = unit.power()
		if power > best_power or (power == best_power and unit.max_hp > best_hp):
			best = unit.uid
			best_power = power
			best_hp = unit.max_hp
	return best

## La franja de iniciativa: quien actua, en orden, con el actual encendido. Las
## fichas llevan la misma silueta que el tablero, a su tamano, para que mirar la
## franja y mirar el tablero sea mirar lo mismo.
func _refresh_order() -> void:
	for child in _order_box.get_children():
		child.queue_free()
	var active := CombatManager.get_active_unit()
	var boss: int = boss_uid()
	for uid in CombatManager.get_turn_order():
		var unit := CombatManager.get_unit(uid)
		if unit == null or not unit.is_alive():
			continue
		var chip := Label.new()
		chip.custom_minimum_size = Vector2(30, 30)
		chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		chip.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
		var is_active: bool = active != null and uid == active.uid
		var tint: Color = CT.sem("POSITIVE") if unit.side == PLAYER else CT.sem("DANGER")
		_paint_order_face(chip, unit, is_active)
		var style := StyleBoxFlat.new()
		style.bg_color = tint if is_active else tint.darkened(0.35)
		style.anti_aliasing = true
		# La forma dice el bando: ficha redonda la nuestra, cuadrada la suya. Es
		# la misma pareja circulo/esquina que la marca de las casillas.
		style.set_corner_radius_all(15 if unit.side == PLAYER else 3)
		chip.set_meta("side", "ally" if unit.side == PLAYER else "enemy")
		# Quien es, en el tooltip: la ficha solo lleva la silueta.
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		chip.tooltip_text = chip_tooltip(unit)
		style.border_color = CT.sem("ACCENT") if is_active else CT.INK
		style.set_border_width_all(3 if is_active else 2)
		if boss >= 0 and uid == boss:
			UITheme.mark_boss(style)
		chip.add_theme_stylebox_override("normal", style)
		# Una unidad que ya actuo se apaga, para que la franja muestre lo que queda.
		chip.modulate.a = 1.0 if not unit.has_acted else 0.45
		_order_box.add_child(chip)

## "Infanteria · 12/20" (y JEFE si lo es): lo que dice el tooltip de una ficha.
func chip_tooltip(unit: CombatUnit) -> String:
	var def := GameConfig.get_unit_def(unit.unit_id)
	var text := "%s · %d/%d" % [Tr.t(def.get("name", unit.unit_id)), unit.hp, unit.max_hp]
	if unit.uid == boss_uid():
		text += " · " + Tr.t("LBL_BOSS")
	return text

## El retrato de una ficha de iniciativa. Mismo trato que en la celda: silueta si
## la hay, inicial si no. El apagado de "ya actuo" lo pone `chip.modulate`, que
## arrastra tambien al icono, asi que aqui el tinte va siempre a plena opacidad.
func _paint_order_face(chip: Label, unit: CombatUnit, is_active: bool) -> void:
	# Ficha de 26 px: la silueta de la escala pequena, trazada para esa medida.
	var texture := UITheme.unit_icon(unit.unit_id, 24)
	if texture == null:
		chip.text = _unit_glyph(unit)
		chip.add_theme_color_override("font_color", UITheme.TEXT_BRIGHT if is_active else UITheme.TEXT_DIM)
		return
	chip.text = ""
	var icon := TextureRect.new()
	icon.texture = texture
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 3
	icon.offset_right = -3
	icon.offset_top = 3
	icon.offset_bottom = -3
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.modulate = UITheme.unit_icon_tint(unit.side == PLAYER)
	if not is_active:
		icon.modulate = icon.modulate.darkened(0.25)
	chip.add_child(icon)

func _refresh_actions() -> void:
	_set_actions_enabled(CombatManager.is_player_turn() and not _board_busy())
	# Una defensa en pleno campaña no es de la columna: abandonar desde ella no
	# retira a nadie de ese tablero, asi que el boton no se ofrece.
	_abandon_board_btn.visible = has_expedition() and not CombatManager.is_defending()
	# RESOLVER SOLO solo se ve cuando vale (incursion o Diezmo, fuerza doble).
	_auto_btn.visible = CombatManager.can_auto_resolve()
	_auto_btn.disabled = not (CombatManager.is_player_turn() and not _board_busy())

func _set_actions_enabled(enabled: bool) -> void:
	_defend_btn.disabled = not enabled
	_wait_btn.disabled = not enabled
	_end_btn.disabled = not enabled
	_advance_btn.visible = is_front_view()
	var active: CombatUnit = CombatManager.get_active_unit() if enabled else null
	_advance_btn.disabled = active == null or \
		Orders.advance_cell(CombatManager.get_encounter(), active.uid) == Orders.NO_CELL

# ── Entrada ──────────────────────────────────────────────────────────

## Un clic, un significado: un enemigo en rango es un ataque, una celda
## encendida es un movimiento, lo demas no es nada. Sin modos, sin clic derecho.
func _on_cell_pressed(coords: Vector2i) -> void:
	# Mientras la maqueta cuenta lo ultimo que paso, el tablero no se toca: se
	# jugaria sobre algo que el jugador aun no ha visto.
	if _board_busy():
		return
	var occupant := CombatManager.get_unit_at(coords)
	if not CombatManager.is_player_turn():
		_show_unit(occupant)
		return
	var active := CombatManager.get_active_unit()
	if active == null or active.side != PLAYER:
		return

	if occupant != null and occupant.side == ENEMY:
		if CombatManager.get_valid_targets(active.uid).has(occupant.uid):
			CombatManager.attack(active.uid, occupant.uid)
		elif not (is_front_view() and order_attack(active.uid, occupant.uid)):
			_show_unit(occupant)
		return
	if occupant != null:
		# Tocar una pieza propia dice quien es (con el dedo no hay tooltip): su
		# ficha. Es el paso 1 del combate guiado.
		_show_unit(occupant)
		if occupant.side == PLAYER:
			TutorialManager.note_combat_fact("selected")
		return
	if occupant == null and CombatManager.get_valid_moves(active.uid).has(coords):
		close_unit_card()
		CombatManager.move_unit(active.uid, coords)

## El frente: "acercate y dispara". Si el objetivo no esta a tiro pero se le
## llega moviendo, la unidad va a la casilla de FrontOrders.approach_cell y
## ataca: las dos MISMAS llamadas que daria el jugador en el tablero 8x8.
func order_attack(uid: int, target_uid: int) -> bool:
	var cell: Vector2i = Orders.approach_cell(CombatManager.get_encounter(), uid, target_uid)
	if cell == Orders.NO_CELL:
		return false
	var unit := CombatManager.get_unit(uid)
	if unit != null and cell != unit.position and not CombatManager.move_unit(uid, cell):
		return false
	return CombatManager.attack(uid, target_uid)

## AVANZAR (frente): la unidad va a donde la llevaria el mando (CombatAI), sin
## atacar; despues el jugador elige objetivo, defiende o espera.
func _act_advance() -> void:
	if _board_busy():
		return
	var active := CombatManager.get_active_unit()
	if active == null or active.side != PLAYER:
		return
	var cell: Vector2i = Orders.advance_cell(CombatManager.get_encounter(), active.uid)
	if cell != Orders.NO_CELL:
		CombatManager.move_unit(active.uid, cell)

## Juega el resto del tablero de un tiron con la IA (AutoResolver). El parte
## sale como siempre, con "Resuelto solo".
func _act_auto_resolve() -> void:
	if _board_busy() or not CombatManager.is_player_turn():
		return
	CombatManager.auto_resolve_current()

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
	_sync_world_render()

## Cerrar el parte de un encuentro no es cerrar la expedicion: si queda mapa por
## delante, se vuelve a el; si hay draft pendiente, se ofrece antes.
func _close_board() -> void:
	close_unit_card()
	_board_open = false
	_board_view.visible = false
	_result_panel.visible = false
	_sync_world_render()
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
	_sync_world_render()

# ── Tablero 3D ───────────────────────────────────────────────────────

## Como se pinta el tablero: "3d" (la maqueta) salvo donde no tiene sentido.
##   * Sin pantalla ("headless": pruebas, sondas sin ventana) no hay nada que
##     ver: el 2D de siempre, que ademas es el que fijan las pruebas de lectura.
##   * En la vista 2D del mapa (docs/18) el jugador eligio lo plano: el tablero
##     2D, que es de su misma familia.
##   * En la calidad "minimal" de WorldLook tambien es 3D, simplificado: sin
##     sombras, sin polvo, sin vaiven de camara y a 0,7 de resolucion. Mientras
##     el tablero esta abierto el 3D del mapa se apaga (tapa la pantalla
##     entera), asi que la maqueta cuesta MENOS que el mapa que el equipo ya
##     mueve: medido en docs/15 §3, "Rendimiento".
static func pick_board_style(display_name: String, view_mode: String, _quality: String) -> String:
	if display_name == "headless":
		return "2d"
	if view_mode == ViewMode.MODE_2D:
		return "2d"
	return "3d"

## Fuerza el estilo del proximo tablero ("2d", "3d" o "" para el automatico).
## Pruebas y sondas.
func force_board_style(style: String) -> void:
	_forced_style = style if style in ["2d", "3d"] else ""

## Fuerza el escenario de la maqueta (BoardTerrain3D.SCENES, o "" para el de la
## semilla). Sondas.
func force_board_scene(scene: String) -> void:
	_forced_scene = scene if scene in BoardTerrain.SCENES else ""

func board_style() -> String:
	return _board_style

## La vista de la maqueta 3D: "front" (por defecto) o "board". Con el tablero 2D
## no aplica, pero devuelve igual la preferencia.
##
## En calidad "minimal" manda el tablero: es la vista medida mas barata (0,32 ms
## de GPU en Mobile, docs/15 §3) y la frontal pinta mas suelo hasta el horizonte,
## arboledas lejanas y un cielo. La preferencia guardada no se toca: al subir la
## calidad vuelve la frontal.
func combat_view() -> String:
	if _forced_view != "":
		return _forced_view
	if _graphics_quality() == "minimal":
		return "board"
	return GameConfig.ui_combat_view if GameConfig.ui_combat_view in GameConfig.COMBAT_VIEWS else "front"

## Hay una pelea en pantalla en la vista frontal.
func is_front_view() -> bool:
	return _uses_3d() and combat_view() == "front"

## Fuerza la vista de la maqueta ("front" / "board", o "" para la preferencia),
## sin tocar settings.cfg. Pruebas y sondas.
func force_combat_view(view: String) -> void:
	_forced_view = view if view in GameConfig.COMBAT_VIEWS else ""
	_apply_combat_view()

## Cambia a la otra vista: la guarda como preferencia y la aplica ya, tambien a
## mitad de pelea (si la maqueta esta contando algo, al terminar).
func set_combat_view(view: String) -> void:
	if not view in GameConfig.COMBAT_VIEWS:
		return
	_forced_view = ""
	GameConfig.set_combat_view(view)
	_refresh_view_button()
	_after_board_animations(_apply_combat_view)

func toggle_combat_view() -> void:
	set_combat_view("board" if combat_view() == "front" else "front")

func _apply_combat_view() -> void:
	_refresh_view_button()
	if _board3d == null or not _board_open:
		return
	_board3d.board.set_style(combat_view())
	_queue_margin_update()
	_refresh()

func _refresh_view_button() -> void:
	if _view_btn == null:
		return
	_view_btn.visible = _board_style == "3d"
	# El boton dice a donde lleva, no donde se esta.
	var other := "OPT_COMBAT_VIEW_BOARD" if combat_view() == "front" else "OPT_COMBAT_VIEW_FRONT"
	_view_btn.text = Tr.t(other)
	CT.style_pill(_view_btn, "secondary", 44 if not CT.phone else 48, "hud", "", "small")

func view_button() -> Button:
	return _view_btn

func advance_button() -> Button:
	return _advance_btn

## La vista 3D (BoardViewport3D), o null si nunca se abrio un tablero 3D.
func board3d():
	return _board3d

func _uses_3d() -> bool:
	return _board_style == "3d" and _board3d != null

## La maqueta esta contando algo: no se actua ni se saca el parte.
func _board_busy() -> bool:
	return _uses_3d() and _board3d.board.is_busy()

func _graphics_quality() -> String:
	return WorldLook.effective_quality(GameConfig.ui_graphics_quality, RenderingServer.get_current_rendering_method())

func _ensure_board3d() -> void:
	if _board3d != null:
		return
	_board3d = Board3DView.new()
	_board_view.add_child(_board3d)
	# Detras de la cabecera y los botones: es el fondo de la vista.
	_board_view.move_child(_board3d, 0)
	_board3d.cell_pressed.connect(_on_cell_pressed)
	_board3d.board.idle.connect(_on_board3d_idle)
	_board3d.tooltip_provider = _board3d_tooltip
	_board3d.set_touch_mode(_touch_mode)
	# El hueco de la maqueta depende de donde acaban la cabecera y los botones.
	_board3d.resized.connect(_queue_margin_update)
	_actions_row.resized.connect(_queue_margin_update)

func _open_board_3d(index: int) -> void:
	_ensure_board3d()
	_board3d.visible = true
	_grid_center.visible = false
	_board_spacer.visible = true
	_board_column.offset_top = UITheme.MARGIN
	_board_column.offset_bottom = -UITheme.MARGIN
	var quality := _graphics_quality()
	var settings: Dictionary = WorldLook.settings_for(quality, RenderingServer.get_current_rendering_method())
	settings["high"] = quality == "high"
	_board3d.apply_quality(settings)
	var encounter: Encounter = CombatManager.get_encounter()
	if encounter == null:
		return
	var seed_value: int = index * 7919 + encounter.units.size() * 31 + (1 if encounter.is_defense else 0)
	_board3d.board.setup(encounter, {
		"scene": _forced_scene if _forced_scene != "" else board_scene_for(encounter, seed_value),
		"team_color": ArmyManager.get_regiment_look()["color"],
		"regiment": ArmyManager.get_regiment_look(),
		"boss_uid": boss_uid(),
		"crew_uids": encounter.back_row_uids,
		"seed": seed_value,
		"style": combat_view(),
	})
	_queue_margin_update()

## El decorado de la maqueta: con agua en el tablero, la playa (el mar de su
## fondo sigue al de las casillas); si no, el de siempre por semilla.
static func board_scene_for(encounter, seed_value: int) -> String:
	if BoardLayout.has_water(BoardLayout.terrain_of(encounter)):
		return BoardTerrain.SCENE_BEACH
	return BoardTerrain.pick_scene(seed_value, encounter.is_defense if encounter != null else false)

func _show_board_2d() -> void:
	if _board3d != null:
		_board3d.visible = false
	_grid_center.visible = true
	_board_spacer.visible = false
	_board_column.offset_top = 0
	_board_column.offset_bottom = 0

## Recalcula el hueco cuando los contenedores ya se han colocado (dos fotogramas:
## la columna acaba de hacerse visible y aun no ha repartido su alto).
func _queue_margin_update() -> void:
	if not _uses_3d() or not is_inside_tree():
		return
	await get_tree().process_frame
	await get_tree().process_frame
	_update_board3d_margins()

## Lo que tapan la cabecera y los botones, para que la camara encaje la maqueta
## en el hueco de en medio.
func _update_board3d_margins() -> void:
	if not _uses_3d() or not _board3d.is_inside_tree() or not _board3d.is_visible_in_tree():
		return
	if _actions_row.size.y <= 0.0:
		return
	var top_y: float = _order_box.get_global_rect().end.y - _board3d.global_position.y + 6.0
	var bottom_y: float = _board3d.size.y - (_actions_row.global_position.y - _board3d.global_position.y) + 6.0
	_board3d.board.set_safe_margins(maxf(top_y, 40.0), maxf(bottom_y, 40.0))

func _refresh_board3d() -> void:
	var b = _board3d.board
	if b.is_busy():
		return
	var active := CombatManager.get_active_unit()
	if active == null:
		b.clear_marks()
		b.set_overlays([], [])
		return
	b.set_overlays(_ov_threat.keys(), _ov_no_fire.keys(), _ov_fire.keys())
	if CombatManager.is_player_turn():
		# En el frente el aro rojo va en todo enemigo al que se llega este turno,
		# moviendose o no (tocarlo acerca y dispara); en el tablero, solo a tiro.
		var targets: Array = _player_targets(active)
		b.show_state(active.uid, CombatManager.get_valid_moves(active.uid), targets, target_hints(active, targets), _ov_previews)
	else:
		b.show_state(active.uid, [], [])

## La ventaja de tipo del atacante contra cada objetivo a tiro: uid -> +1 / -1
## (los neutros no van). Es lo que pinta "Buen objetivo" / "Mal objetivo".
func target_hints(attacker: CombatUnit, targets: Array) -> Dictionary:
	var out := {}
	for uid in targets:
		var t := CombatManager.get_unit(int(uid))
		if t == null:
			continue
		var m: int = Rules.type_matchup(attacker.unit_id, t.unit_id)
		if m != 0:
			out[int(uid)] = m
	return out

func _refresh_speed_button() -> void:
	if _speed_btn == null:
		return
	var fast := GameConfig.game_speed > 1.0
	_speed_btn.text = "x%d" % int(GameConfig.game_speed)
	_speed_btn.tooltip_text = Tr.ti("LBL_GAME_SPEED_TIP")
	CT.style_pill(_speed_btn, "accent" if fast else "secondary", 44 if not CT.phone else 48, "hud", "", "small")

func speed_button() -> Button:
	return _speed_btn

## Dice quien es una pieza tocada: nombre y vida (y JEFE), sobre ella.
func _inspect_3d(unit: CombatUnit) -> void:
	if unit == null or not _uses_3d():
		return
	_board3d.board.inspect(unit.uid, chip_tooltip(unit))

func _board3d_tooltip(cell: Vector2i) -> String:
	var unit := CombatManager.get_unit_at(cell)
	if unit == null:
		return ""
	# Con raton, el dano previsto tambien al pasar por encima.
	if _ov_previews.has(unit.uid):
		return "%s\n%s" % [chip_tooltip(unit), _ov_previews[unit.uid]]
	return chip_tooltip(unit)

func _on_board3d_idle() -> void:
	_refresh()
	# Lo que esperaba a que la maqueta terminara, en el orden en que llego. Si
	# algo de ello vuelve a poner la maqueta a animar, el resto sigue esperando.
	while not _deferred_ui.is_empty() and not _board_busy():
		var fn: Callable = _deferred_ui.pop_front()
		fn.call()

## Ejecuta `fn` ya, o cuando la maqueta termine de animar si esta en ello.
func _after_board_animations(fn: Callable) -> void:
	if _board_busy() or not _deferred_ui.is_empty():
		_deferred_ui.append(fn)
		return
	fn.call()

## Con el tablero 3D en pantalla el mapa de la base no se ve (la maqueta lo tapa
## entero): se deja de dibujar su 3D y la GPU solo pinta la pelea. Se devuelve
## en cuanto se cierra el tablero o se vuelve al mapa de la expedicion.
func _sync_world_render() -> void:
	var want: bool = visible and _view == View.BOARD and _board_view.visible and _uses_3d()
	if want == _world_paused:
		return
	var vp := get_viewport()
	if vp == null:
		return
	_world_paused = want
	vp.disable_3d = want

func _exit_tree() -> void:
	if _world_paused and get_viewport() != null:
		get_viewport().disable_3d = false
		_world_paused = false

# ══════════════════════════════════════════════════════════════════════
# ── Ensenar el combate (2026-10-14, docs/15 §3, docs/23 §2.4) ──
# ══════════════════════════════════════════════════════════════════════
# Vistas previas (dano al apuntar, alcance enemigo, ✕ del alcance minimo), la
# ficha de unidad y a donde senala el combate guiado. Todo se calcula en
# _refresh(), que corre por evento del combate, nunca por fotograma. Las
# cuentas son de CombatRules (puras); aqui solo se pintan.

## A quien puede atacar ahora la unidad activa: en el frente, todo enemigo al
## que llega moviendose (tocarlo acerca y dispara); en el tablero, solo a tiro.
func _player_targets(active: CombatUnit) -> Array:
	if is_front_view():
		return Orders.reachable_targets(CombatManager.get_encounter(), active.uid)
	return CombatManager.get_valid_targets(active.uid)

func _compute_overlays() -> void:
	_ov_threat = {}
	_ov_no_fire = {}
	_ov_fire = {}
	_ov_previews = {}
	var encounter: Encounter = CombatManager.get_encounter()
	var active := CombatManager.get_active_unit()
	if encounter == null or active == null:
		return
	if threat_visible():
		for cell in _threat_cells(encounter):
			_ov_threat[cell] = true
	if not CombatManager.is_player_turn() or active.side != PLAYER:
		return
	for cell in Rules.min_range_cells(active, _board):
		_ov_no_fire[cell] = true
	if TutorialManager.combat_step() == "c_art_range":
		for cell in Rules.fire_cells_from(active, active.position, _board):
			_ov_fire[cell] = true
	_ov_previews = target_previews(active, _player_targets(active))

## Las casillas a las que llega el enemigo, recalculadas solo si algo se movio
## o murio (la clave son las posiciones de los vivos).
func _threat_cells(encounter: Encounter) -> Array:
	var parts: PackedStringArray = []
	for u in encounter.units:
		if u.is_alive():
			parts.append("%d:%d,%d" % [u.uid, u.position.x, u.position.y])
	var key := "|".join(parts)
	if key != _threat_key:
		_threat_key = key
		# Aire y mar: con el terreno del tablero (los barcos no andan por tierra).
		_threat_cache = Rules.threat_cells(encounter.units, ENEMY, _board, encounter.terrain)
	return _threat_cache

## Se ve el alcance enemigo: lo pidio el jugador o lo ensena el combate guiado.
func threat_visible() -> bool:
	return _show_threat or TutorialManager.combat_step() == "c_enemy_turn"

func toggle_threat() -> void:
	_show_threat = not _show_threat
	_style_threat_button()
	_refresh()

func threat_button() -> Button:
	return _threat_btn

func _style_threat_button() -> void:
	if _threat_btn == null:
		return
	_threat_btn.set_meta("label", Tr.t("BTN_HIDE_THREAT") if _show_threat else Tr.t("BTN_SHOW_THREAT"))
	_skin_action(_threat_btn, "warn" if _show_threat else "secondary")

## Lo que se escribe encima de cada pieza: el dano previsto sobre los objetivos
## ("16-20 de 75", "70-80 ¡Cae!"; sin rango, "-18 de 75") y "✕ Muy cerca" sobre el enemigo pegado a una
## artilleria. uid -> texto. Publica para las pruebas.
func target_previews(attacker: CombatUnit, targets: Array) -> Dictionary:
	var out := {}
	for uid in targets:
		var t := CombatManager.get_unit(int(uid))
		if t == null:
			continue
		# Con la cobertura del Bastion de su casilla (0 casi siempre).
		var enc = CombatManager.get_encounter()
		var cov: int = enc.cover_for(t) if enc != null and enc.has_method("cover_for") else 0
		out[int(uid)] = preview_text(Rules.preview_damage(attacker, t, cov))
	if attacker.min_range() > 1:
		for u in CombatManager.get_units():
			if u.side == attacker.side or not u.is_alive() or out.has(u.uid):
				continue
			if Rules.manhattan(attacker.position, u.position) < attacker.min_range():
				out[u.uid] = Tr.t("LBL_PREVIEW_TOO_CLOSE")
	return out

## Con azar en el dano (feat/ritmo-colono) el golpe es un rango: "8-11 de 75",
## "8-11 ¡Cae!" (cae hasta con el minimo) o "8-11 ¿Cae?" (cae con un buen golpe).
## Sin rango (dano pequeno o combat_damage_spread = 0), lo de siempre.
static func preview_text(p: Dictionary) -> String:
	var lo: int = int(p.get("damage_min", p.get("damage", 0)))
	var hi: int = int(p.get("damage_max", p.get("damage", 0)))
	if lo == hi:
		if bool(p.get("kills", false)):
			return Tr.t("LBL_PREVIEW_KILL") % int(p.get("damage", 0))
		return Tr.t("LBL_PREVIEW_DAMAGE") % [int(p.get("damage", 0)), int(p.get("hp", 0))]
	if bool(p.get("kills", false)):
		return Tr.t("LBL_PREVIEW_KILL_RANGE") % [lo, hi]
	if bool(p.get("may_kill", false)):
		return Tr.t("LBL_PREVIEW_MAY_KILL") % [lo, hi]
	return Tr.t("LBL_PREVIEW_DAMAGE_RANGE") % [lo, hi, int(p.get("hp", 0))]

## La vista previa en una casilla del tablero 2D.
func _paint_cell_preview(label: Label, unit: CombatUnit, targets: Array) -> void:
	if unit == null or not _ov_previews.has(unit.uid):
		label.visible = false
		return
	label.text = String(_ov_previews[unit.uid])
	var col: Color = UITheme.TEXT_BRIGHT if targets.has(unit.uid) else UITheme.DANGER.lightened(0.35)
	label.add_theme_color_override("font_color", col)
	label.visible = true

## La vista previa escrita en la casilla `coords` del tablero 2D (pruebas).
func board_cell_preview(coords: Vector2i) -> String:
	var index: int = _cell_index(coords)
	if index < 0 or index >= _cell_previews.size():
		return ""
	var l: Label = _cell_previews[index]
	return l.text if l.visible else ""

func overlay_threat_cells() -> Array:
	return _ov_threat.keys()

func overlay_no_fire_cells() -> Array:
	return _ov_no_fire.keys()

func overlay_previews() -> Dictionary:
	return _ov_previews.duplicate()

# ── Ficha de unidad ──────────────────────────────────────────────────

## Tocar una pieza: su nombre encima (3D) y su ficha a la izquierda.
func _show_unit(unit: CombatUnit) -> void:
	if unit == null:
		return
	_inspect_3d(unit)
	open_unit_card(unit)

func open_unit_card(unit: CombatUnit) -> void:
	if unit == null:
		return
	if _unit_card == null:
		_unit_card = UnitCardScript.new()
		_unit_card.name = "BoardUnitCard"
		_root.add_child(_unit_card)
		_unit_card.closed.connect(close_unit_card)
		# A la izquierda, centrada en alto: no tapa los botones de abajo ni la
		# cabecera, y el pulgar derecho sigue libre para el tablero.
		_unit_card.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_unit_card_uid = unit.uid
	_unit_card.setup(unit.unit_id, unit, true)
	_unit_card.visible = true
	_place_unit_card()

## A la izquierda y centrada en alto, medida con su contenido de ahora: anclada
## al centro crecia hacia arriba al rehacerse y se salia por arriba, encima de
## la bandera y el nombre del pais (tableta, ronda de pruebas 1.0).
func _place_unit_card() -> void:
	if _unit_card == null:
		return
	_unit_card.reset_size()
	var area: Vector2 = _root.size if _root.size.y > 0.0 else get_viewport().get_visible_rect().size
	var h: float = _unit_card.get_combined_minimum_size().y
	var top := 96.0
	var y := clampf((area.y - h) * 0.5, top, maxf(top, area.y - h - 96.0))
	_unit_card.position = Vector2(UITheme.MARGIN, y)

func close_unit_card() -> void:
	_unit_card_uid = -1
	if _unit_card != null:
		_unit_card.visible = false

func unit_card() -> PanelContainer:
	return _unit_card if _unit_card != null and _unit_card.visible else null

## La ficha abierta sigue a su unidad (vida, mejoras); si cayo, se cierra.
func _refresh_unit_card() -> void:
	if _unit_card == null or not _unit_card.visible:
		return
	var u := CombatManager.get_unit(_unit_card_uid)
	if u == null or not u.is_alive():
		close_unit_card()
		return
	_unit_card.setup(u.unit_id, u, true)
	_place_unit_card()

# ── A donde senala el combate guiado (TutorialPanel) ─────────────────

## El sitio en pantalla (coordenadas globales del lienzo) de `target`, uno de
## los de TutorialManager.COMBAT_STEPS: {"rect": Rect2} para un boton o una
## casilla 2D, {"point": Vector2} para una pieza o casilla 3D, {"busy": true}
## mientras la maqueta anima (la marca espera a que se vea lo que paso) o {}.
func coach_anchor(target: String) -> Dictionary:
	if not _board_open or not visible:
		return {}
	match target:
		"":
			return {}
		"end_turn_button":
			return _control_anchor(_end_btn)
		"defend_button":
			return _control_anchor(_defend_btn)
		"threat_button":
			return _control_anchor(_threat_btn)
	if _board_busy():
		return {"busy": true}
	var active := CombatManager.get_active_unit()
	if active == null:
		return {}
	match target:
		"active_unit":
			return _unit_anchor(active)
		"target_unit":
			var uid := coach_target_uid(active)
			return _unit_anchor(CombatManager.get_unit(uid)) if uid >= 0 else {}
		"move_cell":
			var cell := coach_move_cell(active)
			return _cell_anchor(cell) if cell.x >= 0 else {}
	return {}

## El objetivo que senala el paso "Ataca": el de ventaja si lo hay, si no el
## mas tocado. -1 si no hay ninguno.
func coach_target_uid(active: CombatUnit) -> int:
	var best := -1
	var best_score := -INF
	for uid in _player_targets(active):
		var t := CombatManager.get_unit(int(uid))
		if t == null:
			continue
		var score: float = float(Rules.type_matchup(active.unit_id, t.unit_id)) * 1000.0 - float(t.hp)
		if score > best_score:
			best_score = score
			best = int(uid)
	return best

## La casilla que senala el paso "Muevete": la de las alcanzables que mas cerca
## queda del enemigo mas cercano (la que acerca a la pelea).
func coach_move_cell(active: CombatUnit) -> Vector2i:
	var moves: Array = CombatManager.get_valid_moves(active.uid)
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for cell in moves:
		for u in CombatManager.get_units():
			if u.side == active.side or not u.is_alive():
				continue
			var d: int = Rules.manhattan(cell, u.position)
			if d < best_d:
				best_d = d
				best = cell
	return best

func _control_anchor(c: Control) -> Dictionary:
	if c == null or not c.is_visible_in_tree():
		return {}
	return {"rect": c.get_global_rect()}

func _unit_anchor(unit: CombatUnit) -> Dictionary:
	if unit == null or not unit.is_alive():
		return {}
	if _uses_3d():
		return {"point": _board3d_to_canvas(_board3d.board.unit_screen(unit.uid))}
	var cell := board_cell(unit.position)
	return {"rect": cell.get_global_rect()} if cell != null else {}

func _cell_anchor(coords: Vector2i) -> Dictionary:
	if _uses_3d():
		return {"point": _board3d_to_canvas(_board3d.board.cell_screen(coords))}
	var cell := board_cell(coords)
	return {"rect": cell.get_global_rect()} if cell != null else {}

## Un punto del SubViewport de la maqueta, en el lienzo de la pantalla.
func _board3d_to_canvas(p: Vector2) -> Vector2:
	return _board3d.get_global_transform() * _board3d.to_local_point(p)
