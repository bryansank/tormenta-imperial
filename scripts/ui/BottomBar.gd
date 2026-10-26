extends CanvasLayer
## La barra de abajo del rediseno (docs/28 §12, feat/ui2-hud, 2026-10-18).
##
## CONSTRUIR (verde, grande) queda en el centro: es el boton de ConstructionMenu
## (grupo "hud_build_button") y esta barra no lo dibuja, le deja su hueco. A los
## lados, botones redondos azules ("abrir", docs/28 §5) con icono y, en PC y
## tablet, el nombre debajo; en telefono solo el icono (el nombre al mantener):
##
##   [Ejercito] [Misiones]   [ CONSTRUIR ]   [Mercado] [Investigar] [Ayuda]
##
## - Ejercito y Misiones abren ArmyPanel y SkirmishPanel. Sin un edificio que
##   entrene tropa (Cuartel, Astillero, Aerodromo), gris con candado y el porque
##   al mantener. Misiones lleva un punto rojo cuando hay motivo para salir
##   (CombatManager.sortie_reason(), lo mismo que decia el viejo boton
##   ESCARAMUZAS, que esta barra sustituye y oculta).
## - Mercado e Investigar abren MarketPanel y TechTreePanel si existe su
##   edificio (Mercado, Laboratorio) terminado y con carretera; si no, gris con
##   candado y el porque ("Falta un Mercado", "Sin carretera").
## - Ayuda abre el indice de ayuda (grupo "help_index").
##
## Sin animaciones y sin _process: se repinta con senales. Las entradas que
## salieron del menu ☰ (Ejercito, Misiones, Ayuda) viven aqui.

const LAYER := 10
## [id, glifo de CartoonIcon, clave Tr del nombre]. Izquierda y derecha de
## CONSTRUIR.
const LEFT_ITEMS := [["army", "army", "HUD_BAR_ARMY"], ["missions", "missions", "HUD_BAR_MISSIONS"]]
const RIGHT_ITEMS := [["market", "market", "HUD_BAR_MARKET"], ["research", "research", "HUD_BAR_RESEARCH"],
	["help", "help", "HUD_BAR_HELP"]]
## Panel hermano que abre cada boton.
const PANELS := {"army": "ArmyPanel", "missions": "SkirmishPanel", "market": "MarketPanel",
	"research": "TechTreePanel"}
## Edificio que abre Mercado e Investigar (BuildingInfoPanel.SCREENS).
const BUILDINGS := {"market": "market", "research": "laboratory"}
## Hueco entre CONSTRUIR y los redondos, y entre redondos.
const GAP_BUILD := 10.0
const GAP := 8.0
const GAP_PC := 14.0
## Ancho de CONSTRUIR si aun no existe (ConstructionMenu.BUILD_BTN_W).
const BUILD_W_FALLBACK := 240.0

var _dock: HBoxContainer
var _left: HBoxContainer
var _right: HBoxContainer
var _build_gap: Control
## CONSTRUIR, parte de la barra (2026-10-19: el boton suelto de ConstructionMenu
## se montaba sobre los redondos). Abre ConstructionMenu; lleva el grupo
## "hud_build_button" que busca el tutorial.
var _build_btn: Button
var _build_cell: VBoxContainer
var _build_spacer: Control
var _buttons: Dictionary = {}   # id -> Button
var _cells: Dictionary = {}     # id -> Control (el boton o su columna con nombre)
var _locks: Dictionary = {}     # id -> Control (el candado pequeno)
var _dot: Panel
## Por que esta bloqueado cada boton ("" = abierto).
var _reasons: Dictionary = {}

func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("bottom_bar")
	_setup_ui()
	for sig in [EventBus.army_changed, EventBus.sortie_offers_changed, EventBus.campaign_changed,
			EventBus.game_load_completed, EventBus.game_new_started, EventBus.encounter_closed]:
		(sig as Signal).connect(refresh)
	EventBus.building_placed.connect(func(_d, _c): refresh())
	EventBus.building_demolished.connect(func(_n, _c): refresh())
	EventBus.building_moved.connect(func(_f, _t): refresh.call_deferred())
	EventBus.building_upgrade_completed.connect(func(_n, _l): refresh())
	EventBus.era_advanced.connect(func(_e): refresh())
	EventBus.expedition_started.connect(func(_id, _n): refresh())
	EventBus.expedition_ended.connect(func(_r, _rw, _c): refresh())
	EventBus.final_audit_summoned.connect(func(_w, _s): refresh())
	EventBus.storm_phase_changed.connect(func(_p, _s): refresh())
	EventBus.workers_changed.connect(func(_u, _t): _refresh_queued())
	EventBus.resource_changed.connect(func(res, _amount, _delta): if String(res) == "parts": refresh())
	# Una obra que acaba (el Mercado, el Laboratorio) cambia el candado.
	EventBus.construction_completed.connect(func(_n): refresh())
	UILayoutManager.layout_changed.connect(_fit_gap.call_deferred)
	_hide_old_skirmish_button.call_deferred()
	refresh.call_deferred()
	_fit_gap.call_deferred()
	_watch_covers.call_deferred()

## Tapada por el combate (BattleScreen: tablero, mapa de la expedicion, parte),
## la barra se esconde: seguia recibiendo el raton por debajo y su tooltip
## ("Elegir un edificio y colocarlo en el mapa") salia encima del tablero (QA
## de escritorio, 2026-10-26). Al cerrarse el combate vuelve.
func _watch_covers() -> void:
	if not is_inside_tree():
		return
	for n in get_tree().get_nodes_in_group("battle_screen"):
		if not n.visibility_changed.is_connected(_sync_covered):
			n.visibility_changed.connect(_sync_covered)
	_sync_covered()

func is_covered() -> bool:
	if not is_inside_tree():
		return false
	for n in get_tree().get_nodes_in_group("battle_screen"):
		if n.visible:
			return true
	return false

func _sync_covered() -> void:
	visible = not is_covered()

func _setup_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_dock = HBoxContainer.new()
	_dock.name = "BarDock"
	_dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dock.alignment = BoxContainer.ALIGNMENT_CENTER
	_dock.add_theme_constant_override("separation", int(GAP_BUILD))
	UILayoutManager.apply_layout("BottomBar", _dock)
	root.add_child(_dock)

	var sep := int(GAP if CartoonTheme.phone else GAP_PC)
	_left = _group("Left", sep)
	_dock.add_child(_left)
	# CONSTRUIR en el centro, en la misma fila y con la misma linea de abajo que
	# los redondos (debajo, el hueco del nombre que llevan ellos en PC).
	_build_cell = VBoxContainer.new()
	_build_cell.name = "BuildCell"
	_build_cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_cell.size_flags_vertical = Control.SIZE_SHRINK_END
	_build_cell.add_theme_constant_override("separation", 0)
	_dock.add_child(_build_cell)
	_build_btn = CartoonTheme.pill_button(Tr.t("BTN_BUILD_BIG"), "build", "primary", CartoonTheme.bar_build_h(),
		"hud", "title")
	_build_btn.name = "BarBuild"
	_build_btn.add_to_group("hud_build_button")
	_build_btn.tooltip_text = Tr.t("BTN_BUILD_HINT")
	_build_btn.focus_mode = Control.FOCUS_NONE
	_build_btn.pressed.connect(_on_build_pressed)
	_build_cell.add_child(_build_btn)
	_build_spacer = Control.new()
	_build_spacer.name = "BuildCaptionGap"
	_build_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_cell.add_child(_build_spacer)
	# Compatibilidad: el viejo hueco (ya sin ancho) por si alguien lo busca.
	_build_gap = Control.new()
	_build_gap.name = "BuildGap"
	_build_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_gap.visible = false
	_build_cell.add_child(_build_gap)
	_right = _group("Right", sep)
	_dock.add_child(_right)

	for it in LEFT_ITEMS:
		_add_item(_left, it)
	for it in RIGHT_ITEMS:
		_add_item(_right, it)
	_dot = CartoonTheme.red_dot(_buttons["missions"])
	_dot.visible = false
	HudRegistry.register("BottomBar", _dock)

func _group(node_name: String, sep: int) -> HBoxContainer:
	var g := HBoxContainer.new()
	g.name = node_name
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.alignment = BoxContainer.ALIGNMENT_CENTER
	g.add_theme_constant_override("separation", sep)
	g.size_flags_vertical = Control.SIZE_SHRINK_END
	return g

## Nombre debajo en PC y tablet; en telefono solo icono (docs/28 §4.1).
static func shows_captions() -> bool:
	return not CartoonTheme.phone

func _add_item(group: HBoxContainer, it: Array) -> void:
	var id: String = it[0]
	var caption := Tr.t(String(it[2]))
	var d := CartoonTheme.bar_round()
	var cell: Control = CartoonTheme.round_button(String(it[1]), "open", d,
		caption if shows_captions() else "", "hud")
	var btn: Button = cell.get_meta("button") if cell.has_meta("button") else cell as Button
	cell.name = "Cell_" + id
	btn.name = "Bar_" + id
	btn.tooltip_text = caption
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_to_group("hud_bar_" + id)
	btn.pressed.connect(_on_pressed.bind(id))
	cell.size_flags_vertical = Control.SIZE_SHRINK_END
	if shows_captions():
		# El nombre no recorta: la columna mide al menos el redondo y un poco.
		cell.custom_minimum_size.x = d + 14
	group.add_child(cell)
	_buttons[id] = btn
	_cells[id] = cell
	# El candado: pequeno, abajo a la derecha del redondo; solo si esta cerrado.
	var lock := CartoonTheme.make_glyph("lock", roundi(d * 0.4))
	lock.name = "Lock"
	lock.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	lock.offset_left = -d * 0.4 + 6
	lock.offset_top = -d * 0.4 + 2
	lock.offset_right = 6
	lock.offset_bottom = 2
	lock.visible = false
	btn.add_child(lock)
	_locks[id] = lock

## CONSTRUIR se ajusta al lienzo: con palabra en PC, tablet y telefono
## apaisado; en vertical (estrecho) solo el martillo, para que la fila quepa en
## 400 px. Debajo, el alto del nombre de los redondos (alinea las bases).
func _fit_gap() -> void:
	if _build_btn == null or not is_inside_tree():
		return
	var narrow: bool = UILayoutManager.is_narrow()
	var want := "" if narrow else Tr.t("BTN_BUILD_BIG")
	if bool(_build_btn.get_meta("narrow", false)) != narrow:
		var parent := _build_btn.get_parent()
		var idx := _build_btn.get_index()
		parent.remove_child(_build_btn)
		_build_btn.queue_free()
		_build_btn = CartoonTheme.pill_button(want, "build", "primary", CartoonTheme.bar_build_h(), "hud", "title")
		_build_btn.name = "BarBuild"
		_build_btn.add_to_group("hud_build_button")
		_build_btn.tooltip_text = Tr.t("BTN_BUILD_HINT")
		_build_btn.focus_mode = Control.FOCUS_NONE
		_build_btn.pressed.connect(_on_build_pressed)
		_build_btn.set_meta("narrow", narrow)
		parent.add_child(_build_btn)
		parent.move_child(_build_btn, idx)
	_build_btn.custom_minimum_size.x = maxf(_build_btn.custom_minimum_size.x,
		float(CartoonTheme.bar_build_h()) * (1.3 if narrow else 2.6))
	_build_spacer.custom_minimum_size.y = _caption_h() if shows_captions() else 0.0

## Lo que mide el nombre bajo un redondo (para alinear CONSTRUIR con ellos).
func _caption_h() -> float:
	for id in _cells:
		var cell: Control = _cells[id]
		var btn: Control = _buttons[id]
		if is_instance_valid(cell) and cell != btn:
			return maxf(0.0, cell.get_combined_minimum_size().y - btn.get_combined_minimum_size().y)
	return 0.0

func _on_build_pressed() -> void:
	var cm := _sibling("ConstructionMenu")
	if cm == null:
		return
	if cm.has_method("_toggle_panel"):
		cm._toggle_panel()
	elif cm.has_method("open"):
		cm.open()

## El CONSTRUIR de la barra (pruebas, ConstructionMenu.build_button()).
func build_button() -> Button:
	return _build_btn

# ── Estado ─────────────────────────────────────────────────────────────

var _queued := false
func _refresh_queued() -> void:
	if _queued:
		return
	_queued = true
	(func():
		_queued = false
		refresh()).call_deferred()

## Candados, porques y el punto rojo. Publico para pruebas.
func refresh() -> void:
	if _buttons.is_empty():
		return
	var military: bool = ArmyManager.has_military_building()
	_set_reason("army", "" if military else Tr.t("HUD_BAR_LOCK_ARMY"))
	_set_reason("missions", "" if military else Tr.t("HUD_BAR_LOCK_ARMY"))
	_set_reason("market", building_lock_reason("market"))
	_set_reason("research", building_lock_reason("laboratory"))
	_set_reason("help", "" if _help_panel() != null else Tr.t("HUD_BAR_LOCK_HELP"))
	var reason: String = CombatManager.sortie_reason() if military else ""
	_dot.visible = reason != ""
	var mbtn: Button = _buttons["missions"]
	if military:
		mbtn.tooltip_text = Tr.t(reason) if reason != "" else Tr.t("HUD_BAR_MISSIONS")
		(_buttons["army"] as Button).tooltip_text = "%s · %s" % [Tr.t("HUD_BAR_ARMY"), Tr.t("HUD_BAR_ARMY_GO")]

func _set_reason(id: String, why: String) -> void:
	_reasons[id] = why
	var btn: Button = _buttons[id]
	btn.disabled = why != ""
	(_locks[id] as Control).visible = why != ""
	var caption := Tr.t(String(_item(id)[2]))
	btn.tooltip_text = caption if why == "" else "%s: %s" % [caption, why]

func _item(id: String) -> Array:
	for it in LEFT_ITEMS + RIGHT_ITEMS:
		if String(it[0]) == id:
			return it
	return ["", "", ""]

## Por que no se abre la pantalla de un edificio (Mercado, Laboratorio): "" si
## hay uno terminado y con carretera. Lee GridManager y ProductionManager.
static func building_lock_reason(building_id: String) -> String:
	var any := false
	var finished := false
	for info in GridManager.get_all_buildings():
		var data: BuildingData = info.get("data")
		if data == null or data.id != building_id:
			continue
		any = true
		var node: Node = info.get("node")
		if node == null or ProductionManager.is_constructing(node):
			continue
		finished = true
		if bool(node.get_meta("connected", true)):
			return ""
	if not any:
		return Tr.t("HUD_BAR_LOCK_MARKET" if building_id == "market" else "HUD_BAR_LOCK_LAB")
	if not finished:
		return Tr.t("HUD_BAR_LOCK_BUILDING")
	return Tr.t("HUD_BAR_LOCK_ROAD")

## Si un boton esta abierto (pruebas).
func is_open_for(id: String) -> bool:
	return String(_reasons.get(id, "")) == ""

func reason_for(id: String) -> String:
	return String(_reasons.get(id, ""))

func button(id: String) -> Button:
	return _buttons.get(id) as Button

func has_missions_dot() -> bool:
	return _dot != null and _dot.visible

# ── Abrir ──────────────────────────────────────────────────────────────

func _on_pressed(id: String) -> void:
	if String(_reasons.get(id, "")) != "":
		return
	# Ejercito (2026-10-19): se entrena en los Cuarteles. El boton lleva al
	# edificio militar (centra la camara y abre su ficha con ENTRENAR); con
	# varios, cada toque va al siguiente.
	if id == "army":
		go_to_military()
		return
	if id == "help":
		var help := _help_panel()
		if help != null:
			UIManager.close_all_windows()
			help.open()
		return
	var panel := _sibling(String(PANELS.get(id, "")))
	if panel == null:
		return
	if _panel_is_open(panel):
		# Tocar el mismo boton con su ventana abierta la cierra.
		if panel.has_method("toggle"):
			panel.toggle()
		elif panel.has_method("_toggle_panel"):
			panel._toggle_panel()
		elif panel.has_method("close"):
			panel.close()
		return
	if panel.has_method("open"):
		panel.open()
	elif panel.has_method("toggle"):
		panel.toggle()
	elif panel.has_method("_toggle_panel"):
		panel._toggle_panel()

var _military_turn := 0

## Centra la camara en el siguiente edificio militar terminado y abre su ficha.
## Devuelve el nodo (o null si no hay ninguno). Publico para pruebas y sondas.
func go_to_military() -> Node:
	var found: Array = []
	for info in GridManager.get_all_buildings():
		var data: BuildingData = info.get("data")
		if data == null or not (String(data.id) in GameConfig.MILITARY_BUILDINGS):
			continue
		var node: Node = info.get("node")
		if node == null or not is_instance_valid(node):
			continue
		found.append(info)
	if found.is_empty():
		return null
	var info: Dictionary = found[_military_turn % found.size()]
	_military_turn += 1
	var node: Node = info["node"]
	UIManager.close_all_windows()
	_center_camera_on(info)
	EventBus.building_clicked.emit(node, info["data"])
	return node

func _center_camera_on(info: Dictionary) -> void:
	var scene := get_tree().current_scene if is_inside_tree() else null
	if scene == null:
		return
	var cam: Node = scene.get_node_or_null("MonumentalCamera")
	if cam == null:
		cam = scene.get_node_or_null("Camera2D")
	if cam == null or not cam.has_method("get_state") or not cam.has_method("set_state"):
		return
	var cells: Array = info.get("cells", [info.get("origin_cell", Vector2i.ZERO)])
	var sum := Vector3.ZERO
	for cell in cells:
		sum += GridManager.cell_to_world(cell)
	sum /= float(maxi(cells.size(), 1))
	var st: Dictionary = cam.get_state()
	st["target_x"] = sum.x
	st["target_y"] = sum.z
	cam.set_state(st)

static func _panel_is_open(panel: Node) -> bool:
	if panel.has_method("is_open"):
		return bool(panel.is_open())
	return panel.get("_is_open") == true

func _help_panel() -> Node:
	if not is_inside_tree():
		return null
	var p: Node = get_tree().get_first_node_in_group("help_index")
	if p != null and p.has_method("open"):
		return p
	return null

func _sibling(node_name: String) -> Node:
	if node_name == "":
		return null
	var parent := get_parent()
	if parent != null:
		var n := parent.get_node_or_null(node_name)
		if n != null:
			return n
	return null

## El viejo boton ESCARAMUZAS (SkirmishButton) hacia lo mismo que Misiones: con
## la barra en pantalla se oculta (sigue en la escena para quien lo busque).
func _hide_old_skirmish_button() -> void:
	var old := _sibling("SkirmishButton") as CanvasLayer
	if old != null:
		old.visible = false
