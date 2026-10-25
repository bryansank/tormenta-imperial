extends CanvasLayer
## La FICHA del edificio o del yacimiento (rediseno fase 2, docs/28-guia-ui.md;
## maqueta en tools/ui_mockup/mock_screens.gd, build_building_sheet).
##
## Panel lateral a la derecha (sin velo: el edificio se sigue viendo), con la
## cinta de laton y el nombre. Dentro, de arriba abajo:
##   * "Nivel 2 de 3" con su barra, y el estado en una palabra.
##   * Lo que hace en fichas de cifra: "+6 [madera] cada 12 s", "[obrero] 2".
##   * La obra (barra), lo acumulado y RECOGER, el cultivo (HarvestSection).
##   * REPARAR (ambar) con su coste, si esta tocado.
##   * MEJORAR (verde) con su coste y, apagado, el porque debajo.
##   * Los procesos del taller (ProcessActionsPanel / ProcessCard).
## Y abajo, fuera del scroll, las acciones por intencion: ABRIR (azul: Mercado,
## Laboratorio), retirar trabajadores, MOVER y GIRAR (crema) y derribar (rojo,
## solo icono; pide confirmacion).
##
## Menos texto: la descripcion va en el tooltip de la cinta, cada boton lleva su
## explicacion en el tooltip (mantener pulsado en tactil) y lo que no se puede
## dice su porque en 2-3 palabras.

const CT := preload("res://scripts/ui/CartoonTheme.gd")
const Rules := preload("res://scripts/buildings/PlacementRules.gd")
const TextKit := preload("res://scripts/ui/TextKit.gd")
const HelpText := preload("res://scripts/ui/BuildingHelpText.gd")
const TrainingSectionScript := preload("res://scripts/ui/TrainingSection.gd")

## La ventana entera (cinta + panel + X): la coloca UILayoutManager en el slot
## "right_panel" (PC) o _fit_layout() (telefono).
var _panel: Control
var _win: Dictionary = {}
var _scroll: ScrollContainer
var _vbox: VBoxContainer
var _title_label: Label
## Estado en una palabra ("Trabajando", "Sin carretera"...) junto al nivel.
var _level_label: Label
var _level_row: HBoxContainer
var _level_bar: ProgressBar
var _production_container: PanelContainer
## Fichas de lo que hace: "+6 [madera] cada 12 s", trabajadores, moral.
var _production_box: HBoxContainer
var _construction_container: VBoxContainer
var _construction_label: Label
var _construction_bar: ProgressBar
var _deposit_uses_label: Label
var _name_container: HBoxContainer
var _name_edit: LineEdit
var _upgrade_container: VBoxContainer
var _upgrade_btn: Button
## Lo que da la mejora ("Madera: 6 → 9 cada 12 s").
var _upgrade_cost_label: Label
var _upgrade_cost_row: HFlowContainer
## "Nivel 1 de 3" (arriba, con la barra), el aviso de repuestos, POR QUE el
## boton esta apagado y, en los que no se mejoran, una linea que lo dice.
var _upgrade_level_label: Label
var _upgrade_parts_label: Label
var _upgrade_why_label: Label
var _no_upgrade_label: Label
var _upgrade_refresh_queued := false
var _repair_container: PanelContainer
var _repair_btn: Button
var _repair_label: Label
var _repair_cost_row: HFlowContainer
## La cabecera de los procesos: solo con procesos que ofrecer.
var _actions_header: Control
var _actions_sep: Control
## Fila de acciones de abajo (mover, girar, derribar...).
var _actions_box: HFlowContainer
## ENTRENAR en los edificios militares (2026-10-19): las unidades de ESE edificio.
var _training: VBoxContainer
var _move_container: Control
var _move_btn: Button
var _rotate_btn: Button
## El boton que abre la pantalla del edificio: el Mercado abre el comercio y el
## Laboratorio el arbol tecnologico.
var _open_btn: Button
## Retirar / poner los trabajadores de este edificio.
var _workers_btn: Button
var _workers_hint: Label
var _demolish_btn: Button
var _close_btn: Button
var _confirm_container: VBoxContainer
var _confirm_label: Label

var _process_panel: ProcessActionsPanel
## PARA RECOGER y, en la Granja, CULTIVO.
var _harvest: VBoxContainer = null
var _selected_node: Node = null
var _selected_data: BuildingData = null
var _selected_deposit_id: String = ""
var _is_deposit: bool = false
var _demolish_pending: bool = false
var _phone := false

func _ready() -> void:
	layer = 10
	_build_ui()
	_panel.visible = false
	UIManager.register_panel(self, "BuildingInfoPanel")

	EventBus.building_clicked.connect(_on_building_clicked)
	EventBus.building_deselected.connect(_on_deselected)
	EventBus.deposit_clicked.connect(_on_deposit_clicked)
	EventBus.process_completed.connect(_on_process_event)
	EventBus.mining_completed.connect(_on_mining_event)
	EventBus.construction_completed.connect(_on_construction_completed)
	EventBus.workers_changed.connect(func(_u, _t): if _workers_btn != null and _panel.visible: _refresh_workers_toggle())
	EventBus.building_upgrade_completed.connect(_on_upgrade_completed)
	# El boton MEJORAR y su "por que" siguen a lo que hay.
	EventBus.resource_changed.connect(func(_t, _a, _d): _on_resources_changed())
	EventBus.building_selected_for_placement.connect(func(_d): _hide_panel())
	EventBus.building_demolished.connect(func(_n, _c): _hide_panel())
	EventBus.deposit_depleted.connect(func(n, _id): if n == _selected_node: _hide_panel())
	UILayoutManager.layout_changed.connect(_fit_layout)
	get_viewport().size_changed.connect(_fit_layout)

func _process(_delta: float) -> void:
	if not _selected_node or not _panel.visible:
		return
	if not is_instance_valid(_selected_node):
		_hide_panel()
		return
	_process_panel.update_progress(_selected_node, _is_deposit, _selected_data)
	_update_construction()
	if _training != null and _training.visible:
		_training.update_progress()
	if _harvest != null and not _is_deposit:
		_harvest.refresh()

# ── UI Construction ──

func _vp() -> Vector2:
	return get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280, 720)

func _build_ui() -> void:
	_phone = CT.is_phone()
	_win = CT.window("", CT.sem("ACCENT"))
	_panel = _win["root"]
	_panel.name = "InfoWindow"
	(_win["panel"] as Control).gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			UIManager.focus_window(self))
	# La etiqueta de la cinta es el titulo (la unica etiqueta al crearla).
	_title_label = _panel.find_children("*", "Label", true, false)[0] as Label
	# En un panel lateral estrecho la cinta lleva letra de titulo, no de cartel.
	var tc := CT.on_fill(CT.sem("ACCENT"))
	CT.style_label(_title_label, "title", tc["color"], tc["outline"])
	_title_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_close_btn = _win["close"]
	_close_btn.tooltip_text = Tr.t("UI2C_CLOSE")
	_close_btn.pressed.connect(_hide_panel)
	UILayoutManager.apply_layout("BuildingInfoPanel", _panel)

	var body: VBoxContainer = _win["body"]
	body.add_theme_constant_override("separation", 6 if _phone else 10)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_scroll)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 8 if _phone else CT.GAP)
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_vbox)

	# ── Nivel "2 de 3" con su barra, y el estado en una palabra ──
	_level_row = HBoxContainer.new()
	_level_row.name = "LevelRow"
	_level_row.add_theme_constant_override("separation", 8)
	_upgrade_level_label = CT.label("", "button", CT.text("window"))
	_upgrade_level_label.name = "UpgradeLevel"
	_level_row.add_child(_upgrade_level_label)
	_level_bar = CT.level_bar(1, GameConfig.max_building_level)
	_level_row.add_child(_level_bar)
	_vbox.add_child(_level_row)
	_level_label = CT.label("", "small", CT.text("window", true))
	_level_label.name = "StatusLine"
	_level_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_level_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_vbox.add_child(_level_label)

	# ── Lo que hace: fichas de cifra ──
	_production_container = PanelContainer.new()
	var prod_style := CT.card_style("window")
	prod_style.set_content_margin_all(6 if _phone else 10)
	_production_container.add_theme_stylebox_override("panel", prod_style)
	_production_box = HBoxContainer.new()
	_production_box.name = "Production"
	_production_box.add_theme_constant_override("separation", 16)
	_production_container.add_child(_production_box)
	_vbox.add_child(_production_container)

	# ── Obra ──
	_construction_container = VBoxContainer.new()
	_construction_container.add_theme_constant_override("separation", 4)
	_construction_label = CT.label("", "body", CT.text("window"))
	_construction_bar = CT.progress(0.0, CT.sem("WARNING"), "window", 14)
	_construction_container.add_child(_construction_label)
	_construction_container.add_child(_construction_bar)
	_vbox.add_child(_construction_container)

	_harvest = preload("res://scripts/ui/HarvestSection.gd").new()
	_harvest.visible = false
	_vbox.add_child(_harvest)

	_training = TrainingSectionScript.new()
	_training.visible = false
	_training.open_army_requested.connect(_on_open_army)
	_vbox.add_child(_training)

	# ── Yacimiento: usos y, al mantener, a mano o con su edificio ──
	_deposit_uses_label = CT.para("", "window")
	_deposit_uses_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_vbox.add_child(_deposit_uses_label)

	# ── Nombre del Nucleo ──
	_name_container = HBoxContainer.new()
	_name_container.add_theme_constant_override("separation", 6)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = Tr.t("LBL_BUILDING_NAME_PLACEHOLDER")
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.max_length = 20
	_name_edit.custom_minimum_size.y = CT.h("small")
	_name_edit.add_theme_font_override("font", CT.body_font())
	_name_edit.add_theme_font_size_override("font_size", CT.fs("body"))
	_name_edit.add_theme_color_override("font_color", CT.text("window"))
	_name_edit.add_theme_color_override("font_placeholder_color", CT.text("window", true))
	_name_edit.add_theme_stylebox_override("normal", CT.well_style("window", 12, 8))
	_name_edit.add_theme_stylebox_override("focus", CT.box(CT.c("window", "WELL"), CT.sem("ACCENT"), 2, 12, 8))
	_name_edit.text_submitted.connect(func(_t): _on_rename())
	var name_btn := CT.pill_button("", "check", "primary", CT.h("small"))
	name_btn.tooltip_text = Tr.t("BTN_RENAME")
	name_btn.pressed.connect(_on_rename)
	_name_container.add_child(_name_edit)
	_name_container.add_child(name_btn)
	_vbox.add_child(_name_container)

	# ── Reparar: antes que mejorar (en ruinas es lo unico que importa) ──
	_repair_container = PanelContainer.new()
	_repair_container.name = "RepairCard"
	var rep_style := CT.card_style("window", false, CT.c("window", "CARD").lerp(CT.sem("WARNING"), 0.12))
	rep_style.set_content_margin_all(6 if _phone else 10)
	_repair_container.add_theme_stylebox_override("panel", rep_style)
	var rep_col := VBoxContainer.new()
	rep_col.add_theme_constant_override("separation", 6)
	_repair_container.add_child(rep_col)
	_repair_label = CT.label("", "body", CT.text("window"))
	_repair_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rep_col.add_child(_repair_label)
	# Se parte como la de mejorar: el coste baja bajo el boton si no cabe.
	var rep_row := HFlowContainer.new()
	rep_row.add_theme_constant_override("h_separation", 6)
	rep_row.add_theme_constant_override("v_separation", 4)
	_repair_btn = CT.pill_button(Tr.t("UI2C_BTN_REPAIR"), "wrench", "warn", CT.h("btn"))
	# Grupos para que el tutorial los senale (HelpTargets: info_repair, info_move,
	# info_demolish, info_demolish_confirm).
	_repair_btn.add_to_group("hud_info_repair")
	_repair_btn.tooltip_text = Tr.t("UI2C_TIP_REPAIR")
	_repair_btn.pressed.connect(_on_repair)
	rep_row.add_child(_repair_btn)
	_repair_cost_row = CT.cost_flow()
	_repair_cost_row.name = "RepairCost"
	_repair_cost_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_repair_cost_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rep_row.add_child(_repair_cost_row)
	rep_col.add_child(rep_row)
	_repair_container.visible = false
	_vbox.add_child(_repair_container)

	# ── Mejorar: la accion principal, con su coste al lado ──
	_upgrade_container = VBoxContainer.new()
	_upgrade_container.name = "UpgradeBox"
	_upgrade_container.add_theme_constant_override("separation", 4)
	_upgrade_cost_label = CT.para("", "window", true, "small")
	_upgrade_cost_label.name = "UpgradeEffect"
	_upgrade_container.add_child(_upgrade_cost_label)
	# Se parte (coste debajo del boton) si no cabe: nada pasa del ancho de la ficha.
	var up_row := HFlowContainer.new()
	up_row.add_theme_constant_override("h_separation", 6)
	up_row.add_theme_constant_override("v_separation", 4)
	_upgrade_btn = CT.pill_button(Tr.t("UI2C_BTN_UPGRADE"), "upgrade", "primary", CT.h("btn"))
	_upgrade_btn.name = "UpgradeButton"
	_upgrade_btn.pressed.connect(_on_upgrade)
	up_row.add_child(_upgrade_btn)
	# Las fichas del coste tambien bajan de linea: el Cuartel General pide siete
	# cosas y la ficha salia 340 px por la derecha.
	_upgrade_cost_row = CT.cost_flow()
	_upgrade_cost_row.name = "UpgradeCost"
	_upgrade_cost_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_upgrade_cost_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	up_row.add_child(_upgrade_cost_row)
	_upgrade_container.add_child(up_row)
	# El nivel 3 de los que producen pide repuestos: se avisa antes de pulsar.
	_upgrade_parts_label = CT.para("", "window", false, "small")
	_upgrade_parts_label.name = "UpgradeParts"
	_upgrade_parts_label.add_theme_color_override("font_color", CT.tone_color("warning"))
	_upgrade_parts_label.visible = false
	_upgrade_container.add_child(_upgrade_parts_label)
	# Con el boton apagado, por que (en gris el boton, en rojo el porque).
	_upgrade_why_label = CT.why_label()
	_upgrade_why_label.name = "UpgradeWhy"
	_upgrade_why_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_upgrade_container.add_child(_upgrade_why_label)
	# Mejora, su efecto, el boton y el coste en una sola tarjeta: se leen juntos.
	var up_card := PanelContainer.new()
	up_card.name = "UpgradeCard"
	var up_style := CT.card_style("window")
	up_style.set_content_margin_all(6 if _phone else 10)
	up_card.add_theme_stylebox_override("panel", up_style)
	up_card.add_child(_upgrade_container)
	_upgrade_container.visibility_changed.connect(func(): up_card.visible = _upgrade_container.visible)
	_vbox.add_child(up_card)
	# Los que no se mejoran lo dicen, con su porque, en gris.
	_no_upgrade_label = CT.para("", "window", true, "small")
	_no_upgrade_label.name = "NoUpgrade"
	_no_upgrade_label.visible = false
	_vbox.add_child(_no_upgrade_label)

	# ── Procesos del taller ──
	_actions_sep = Control.new()
	_actions_sep.custom_minimum_size.y = 2
	_vbox.add_child(_actions_sep)
	_actions_header = CT.section(Tr.t("LBL_ACTIONS"), "build")
	_vbox.add_child(_actions_header)
	var processes_box := VBoxContainer.new()
	processes_box.add_theme_constant_override("separation", 6)
	_vbox.add_child(processes_box)
	var progress_container := VBoxContainer.new()
	progress_container.add_theme_constant_override("separation", 4)
	var progress_label := CT.label("", "small", CT.text("window"))
	var progress_bar := CT.progress(0.0, CT.sem("ACCENT"), "window", 14)
	progress_container.add_child(progress_label)
	progress_container.add_child(progress_bar)
	_vbox.add_child(progress_container)
	_process_panel = ProcessActionsPanel.new(processes_box, progress_container, progress_bar, progress_label)

	# ── Abajo, fuera del scroll: abrir, trabajadores, mover, girar, derribar ──
	_open_btn = CT.pill_button("", "market", "open", CT.h("btn"))
	_open_btn.name = "OpenBuildingScreen"
	_open_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_open_btn.pressed.connect(_on_open_screen)
	_open_btn.visible = false
	body.add_child(_open_btn)

	# Se parte en dos filas si no cabe: cada boton lleva su nombre corto (en
	# telefono solo el icono, con el nombre al mantener pulsado).
	_actions_box = HFlowContainer.new()
	_actions_box.name = "InfoActions"
	_actions_box.add_theme_constant_override("h_separation", 6)
	_actions_box.add_theme_constant_override("v_separation", 6)
	body.add_child(_actions_box)

	# Trabajadores: el jugador decide si este edificio trabaja. Solo icono: el
	# estado esta arriba y la explicacion, en el tooltip.
	_workers_btn = CT.pill_button("" if _phone else Tr.t("UI2F_BTN_WORKERS"), "workers_off", "secondary", CT.h("small"), "window", "body")
	_workers_btn.name = "WorkersToggle"
	_workers_btn.pressed.connect(_on_toggle_workers)
	_actions_box.add_child(_workers_btn)
	_workers_hint = CT.label("", "small", CT.text("window", true))
	_workers_hint.name = "WorkersHint"
	_workers_hint.visible = false

	_move_btn = CT.pill_button("" if _phone else Tr.t("UI2C_BTN_MOVE"), "move", "secondary", CT.h("small"), "window", "body")
	_move_btn.name = "MoveButton"
	_move_btn.add_to_group("hud_info_move")
	_move_btn.tooltip_text = Tr.t("LBL_MOVE_HINT")
	_move_btn.pressed.connect(_on_move)
	_move_container = _move_btn
	_actions_box.add_child(_move_btn)

	_rotate_btn = CT.pill_button("" if _phone else Tr.t("UI2F_BTN_ROTATE"), "", "secondary", CT.h("small"), "window", "body")
	_rotate_btn.name = "RotateButton"
	var rot_glyph := CT.rotate_glyph(roundi(CT.h("small") * 0.56))
	_rotate_btn.get_child(0).add_child(rot_glyph)
	_rotate_btn.get_child(0).move_child(rot_glyph, 0)
	_rotate_btn.tooltip_text = Tr.t("UI2C_TIP_ROTATE")
	_rotate_btn.pressed.connect(_on_rotate)
	_actions_box.add_child(_rotate_btn)

	# Derribar: rojo y solo icono; el nombre al mantener. Pide confirmacion.
	_demolish_btn = CT.pill_button("" if _phone else Tr.t("UI2F_BTN_DEMOLISH"), "demolish", "danger", CT.h("small"), "window", "body")
	_demolish_btn.name = "DemolishButton"
	_demolish_btn.add_to_group("hud_info_demolish")
	_demolish_btn.tooltip_text = Tr.t("UI2C_TIP_DEMOLISH")
	_demolish_btn.pressed.connect(_on_demolish)
	_actions_box.add_child(_demolish_btn)

	# Confirmacion de derribo: una frase y dos botones.
	_confirm_container = VBoxContainer.new()
	_confirm_container.add_theme_constant_override("separation", 6)
	_confirm_container.visible = false
	_confirm_label = CT.para("", "window")
	_confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_container.add_child(_confirm_label)
	var confirm_row := HBoxContainer.new()
	confirm_row.add_theme_constant_override("separation", 8)
	confirm_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var yes_btn := CT.pill_button(Tr.t("UI2C_BTN_DEMOLISH"), "demolish", "danger", CT.h("btn"))
	yes_btn.add_to_group("hud_info_demolish_confirm")
	yes_btn.pressed.connect(_confirm_demolish)
	var no_btn := CT.pill_button(Tr.t("BTN_CANCEL"), "", "secondary", CT.h("btn"))
	no_btn.pressed.connect(_cancel_demolish)
	confirm_row.add_child(yes_btn)
	confirm_row.add_child(no_btn)
	_confirm_container.add_child(confirm_row)
	body.add_child(_confirm_container)

	add_child(_panel)
	_fit_layout()

## PC y tablet: donde diga el slot "right_panel". Telefono: a la derecha, de
## arriba abajo, con medio lienzo de ancho como mucho (el edificio se ve a la
## izquierda).
func _fit_layout() -> void:
	if _panel == null or not is_inside_tree():
		return
	var vp := _vp()
	var ph := CT.is_phone()
	_phone = ph
	if not ph:
		UILayoutManager.apply_layout("BuildingInfoPanel", _panel)
		CT.fit_desktop(_win)
		# Tablet: la zona segura (muesca, bordes curvos) tampoco se pisa.
		var safe := _safe_right()
		if safe > 0.0:
			_panel.offset_left -= safe
			_panel.offset_right -= safe
		return
	var width := minf(330.0, vp.x * 0.52)
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	# Margen con el borde (y la zona segura del telefono): nunca pegado.
	var edge := 14.0 + _safe_right()
	# El ☰ redondo vive arriba a la derecha: la ficha (y su X) van a su
	# izquierda para no quedar debajo (ronda ui3, 2026-10-19).
	edge = maxf(edge, _menu_clearance(vp))
	_panel.offset_left = -edge - width
	_panel.offset_right = -edge
	_panel.offset_top = 2.0
	# Por encima de la barra de abajo: tapaba CONSTRUIR a medias.
	_panel.offset_bottom = -float(CT.bar_build_h() + 14)
	_panel.custom_minimum_size = Vector2.ZERO
	var s := CT.window_style()
	s.set_content_margin_all(10)
	(_win["panel"] as PanelContainer).add_theme_stylebox_override("panel", s)
	_close_btn.offset_left = -_close_btn.custom_minimum_size.x - 2
	_close_btn.offset_right = -2

## Cuanto hay que apartarse del borde derecho para no caer debajo del ☰ (el
## boton del menu, arriba a la derecha). 0 si no esta o no se ve.
func _menu_clearance(vp: Vector2) -> float:
	var menu := get_tree().get_first_node_in_group("hud_menu_button") as Control
	if menu == null or not is_instance_valid(menu) or not menu.is_visible_in_tree():
		return 0.0
	var r := menu.get_global_rect()
	if r.size.x <= 0.0 or r.position.y > 80.0 or r.position.x < vp.x * 0.5:
		return 0.0
	return vp.x - r.position.x + 6.0

## Lo que tapa la muesca o los bordes curvos a la derecha, en pixeles logicos.
## Solo en movil: en escritorio la "zona segura" es la del monitor (sin la
## barra de tareas) y no dice nada de la ventana.
func _safe_right() -> float:
	if not is_inside_tree() or DisplayServer.get_name() == "headless" or not OS.has_feature("mobile"):
		return 0.0
	var safe := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	if safe.size.x <= 0 or win.x <= 0:
		return 0.0
	var px := float(win.x - (safe.position.x + safe.size.x))
	return clampf(px / maxf(get_tree().root.content_scale_factor, 0.01), 0.0, 48.0)

## "Ver ejercito" de ENTRENAR: el resumen (tropa, sueldo, regimiento).
func _on_open_army() -> void:
	var army := get_parent().get_node_or_null("ArmyPanel") if get_parent() != null else null
	if army != null and army.has_method("open"):
		army.open()

# ── Event Handlers ──

func _on_building_clicked(building_node: Node, building_data: Resource) -> void:
	_selected_node = building_node
	_selected_data = building_data as BuildingData
	_selected_deposit_id = ""
	_is_deposit = false
	_demolish_pending = false
	_show_building_panel()

func _on_deposit_clicked(deposit_node: Node, deposit_id: String, _cell: Vector2i) -> void:
	_selected_node = deposit_node
	_selected_data = null
	_selected_deposit_id = deposit_id
	_is_deposit = true
	_demolish_pending = false
	_show_deposit_panel()

func _on_deselected() -> void:
	_hide_panel()

func _on_process_event(node: Node, _pid: String) -> void:
	if node == _selected_node:
		_process_panel.update_progress(_selected_node, _is_deposit, _selected_data)

func _on_mining_event(node: Node, _pid: String) -> void:
	if node == _selected_node:
		_process_panel.update_progress(_selected_node, _is_deposit, _selected_data)
		if _is_deposit and is_instance_valid(_selected_node):
			_update_deposit_uses()

func _on_construction_completed(node: Node) -> void:
	if node == _selected_node:
		_show_building_panel()

func _on_upgrade_completed(node: Node, _new_level: int) -> void:
	if node == _selected_node:
		_show_building_panel()

# ── Panel Display ──

func _show_building_panel() -> void:
	_fit_layout()
	_cancel_demolish()
	var custom_name: String = _selected_node.get_meta("custom_name", "")
	_title_label.text = custom_name if not custom_name.is_empty() else _selected_data.get_display_name()
	_title_label.tooltip_text = _selected_data.get_description()

	var level: int = _selected_node.get_meta("level", 1)
	var is_building := ProductionManager.is_constructing(_selected_node)
	# Nivel "2 de 3" con su barra: solo en lo que se mejora.
	_upgrade_level_label.text = HelpText.level_of_text(level)
	_level_bar.value = float(level) / float(maxi(GameConfig.max_building_level, 1))
	_level_row.visible = Rules.upgrade_does_something(_selected_data) and not is_building
	# El estado en una palabra; la linea entera de siempre, en el tooltip.
	_level_label.tooltip_text = level_line(_selected_data, level)
	_refresh_status_line()

	# Lo que hace (con el multiplicador de nivel): fichas de cifra.
	for child in _production_box.get_children():
		_production_box.remove_child(child)
		child.free()
	var prod := production_amounts(_selected_data, level)
	if not prod.is_empty():
		var interval := GameConfig.get_production_interval(_selected_data.production_interval)
		for res_id in prod:
			var chip := CT.stat_chip("res:" + String(res_id), "+%d" % int(prod[res_id]),
				Tr.t("FMT_EVERY") % TextKit.short_time(interval), "window", CT.positive_text())
			_production_box.add_child(chip)
	if _selected_data.workers_required > 0:
		_production_box.add_child(CT.stat_chip("res:workers", str(_selected_data.workers_required), Tr.t("UI2C_CHIP_WORK"), "window"))
	if _selected_data.population_capacity > 0:
		var room: int = _selected_data.population_capacity if _selected_data.is_core else \
			int(_selected_data.population_capacity * GameConfig.level_mult(GameConfig.upgrade_capacity_multiplier, level))
		_production_box.add_child(CT.stat_chip("res:workers", "+%d" % room, Tr.t("UI2C_CHIP_ROOM"), "window"))
	if _selected_data.morale_bonus > 0:
		_production_box.add_child(CT.stat_chip("res:morale", "+%d" % _selected_data.morale_bonus, Tr.t("UI2C_CHIP_MORALE"), "window"))
	_production_container.visible = _production_box.get_child_count() > 0

	_deposit_uses_label.visible = false
	_harvest.show_for(_selected_node, _selected_data)
	var military: bool = String(_selected_data.id) in GameConfig.MILITARY_BUILDINGS and not is_building
	_training.visible = military
	if military:
		_training.setup(String(_selected_data.id))
	_refresh_workers_toggle()
	_refresh_open_button()

	_construction_container.visible = is_building
	if is_building:
		_update_construction()

	_name_container.visible = _selected_data.is_core and not is_building
	if _selected_data.is_core:
		_name_edit.text = custom_name

	_refresh_repair()
	_refresh_upgrade()

	var movable: bool = not _selected_data.is_core and not is_building
	_move_btn.visible = movable
	_rotate_btn.visible = movable and _selected_data.id != Rules.ROAD_ID
	_demolish_btn.visible = not _selected_data.is_core
	_actions_box.visible = true

	_process_panel.populate_building(_selected_node, _selected_data, is_building)
	_set_actions_header(_process_panel.action_count() > 0)
	_scroll.scroll_vertical = 0
	_panel.visible = true
	(func(): CT.sync_ribbon_pad(_win)).call_deferred()
	set_process(true)
	UIManager.open_panel(self)

## El estado en una palabra (o dos): en obras, sin carretera, sin trabajadores,
## retirados, sin veta o trabajando. Lo mismo que dice su placa en el mapa.
func _refresh_status_line() -> void:
	if _selected_node == null or not is_instance_valid(_selected_node) or _selected_data == null or _is_deposit:
		_level_label.visible = false
		return
	var text := ""
	if ProductionManager.is_constructing(_selected_node):
		text = ""
	elif BuildingHealth.is_ruined(_selected_node):
		text = Tr.t("LBL_RUINED")
	elif not bool(_selected_node.get_meta("connected", true)):
		text = Tr.t("UI2C_STATUS_NO_ROAD")
	elif _selected_data.workers_required > 0:
		if not bool(_selected_node.get_meta("has_vein", true)):
			text = Tr.t("LBL_NO_VEIN_SHORT")
		elif bool(_selected_node.get_meta("workers_off", false)):
			text = Tr.t("LBL_WORKERS_OFF_SHORT")
		else:
			text = Tr.t("LBL_WORKERS_ON_SHORT") % _selected_data.workers_required
	_level_label.text = text
	_level_label.visible = text != ""

## La seccion de mejora: lo que da el siguiente nivel con sus numeros, el coste
## al lado de MEJORAR, el aviso de repuestos y, con el boton apagado, por que.
## Un edificio que no se mejora lo dice en una linea gris. En obras, nada.
func _refresh_upgrade() -> void:
	_upgrade_why_label.visible = false
	_upgrade_parts_label.visible = false
	_no_upgrade_label.visible = false
	if _selected_node == null or not is_instance_valid(_selected_node) or _selected_data == null or _is_deposit:
		_upgrade_container.visible = false
		return
	var level: int = _selected_node.get_meta("level", 1)
	var next_level := level + 1
	var top := GameConfig.max_building_level
	var is_building := ProductionManager.is_constructing(_selected_node)
	if not Rules.upgrade_does_something(_selected_data):
		_upgrade_container.visible = false
		var why := HelpText.no_upgrade_text(_selected_data)
		_no_upgrade_label.text = why
		_no_upgrade_label.visible = why != "" and not is_building
		return
	if is_building:
		_upgrade_container.visible = false
		return
	_upgrade_level_label.text = HelpText.level_of_text(level)
	_upgrade_container.visible = true
	if next_level > top:
		_upgrade_cost_label.text = Tr.t("TOPE_MAX_LEVEL")
		_upgrade_cost_label.visible = true
		_upgrade_cost_row.visible = false
		_upgrade_btn.visible = false
		return
	var cost := GameConfig.get_upgrade_cost(_selected_data, next_level)
	_upgrade_btn.visible = true
	_upgrade_btn.tooltip_text = Tr.t("LBL_UPGRADE_TO") % [next_level]
	# Que da la mejora, con sus numeros; el coste en iconos al lado del boton.
	var effects: Array = Rules.upgrade_effect_lines(_selected_data, level)
	_upgrade_cost_label.text = "\n".join(effects)
	_upgrade_cost_label.visible = not effects.is_empty()
	CT.fill_cost_strip(_upgrade_cost_row, by_name(cost), missing_by_name(cost))
	_upgrade_cost_row.visible = true
	var parts := HelpText.parts_note(_selected_data, next_level)
	_upgrade_parts_label.text = parts
	_upgrade_parts_label.visible = parts != ""
	var blocks: Array = HelpText.upgrade_block_lines(_selected_data, _selected_node)
	_upgrade_btn.disabled = not blocks.is_empty() or not ResourceManager.can_afford(cost)
	_upgrade_why_label.text = "\n".join(blocks)
	_upgrade_why_label.visible = not blocks.is_empty()

## Cambian los recursos con la ficha abierta: se repinta una vez al final del
## fotograma (llega una senal por recurso).
func _on_resources_changed() -> void:
	if _upgrade_refresh_queued or not _panel.visible or _is_deposit or _selected_data == null:
		return
	_upgrade_refresh_queued = true
	_flush_upgrade_refresh.call_deferred()

func _flush_upgrade_refresh() -> void:
	_upgrade_refresh_queued = false
	if _panel.visible and not _is_deposit and _selected_data != null:
		_refresh_upgrade()
		_refresh_repair()

func _show_deposit_panel() -> void:
	_fit_layout()
	_cancel_demolish()
	var display_name := _selected_deposit_id
	for child in _selected_node.get_children():
		if child is Label3D or child is Label:
			display_name = child.text
			break
	_title_label.text = display_name
	_title_label.tooltip_text = Tr.t("LBL_NATURAL_RESOURCE")
	_level_row.visible = false
	_level_label.visible = false
	_production_container.visible = false
	_harvest.visible = false
	_training.visible = false
	_construction_container.visible = false
	_name_container.visible = false
	_upgrade_container.visible = false
	_no_upgrade_label.visible = false
	_actions_box.visible = false
	_update_deposit_uses()
	_refresh_workers_toggle()
	_refresh_open_button()
	_repair_container.visible = false
	_process_panel.populate_deposit(_selected_node, _selected_deposit_id)
	_set_actions_header(_process_panel.action_count() > 0)
	_scroll.scroll_vertical = 0
	_panel.visible = true
	(func(): CT.sync_ribbon_pad(_win)).call_deferred()
	set_process(true)
	UIManager.open_panel(self)

## Pantalla de cada edificio que la tiene: id -> [nodo de la escena, clave Tr].
const SCREENS := {
	"market": ["MarketPanel", "BTN_OPEN_MARKET"],
	"laboratory": ["TechTreePanel", "BTN_OPEN_LAB"],
}
## El icono del boton ABRIR de cada una.
const SCREEN_GLYPHS := {"market": "market", "laboratory": "research"}

func _refresh_open_button() -> void:
	var id: String = _selected_data.id if _selected_data != null and not _is_deposit else ""
	var entry: Array = SCREENS.get(id, [])
	var ready: bool = not entry.is_empty() and not ProductionManager.is_constructing(_selected_node)
	_open_btn.visible = ready
	if ready:
		# Rehecho con su icono y su palabra (Mercado o Laboratorio).
		for child in _open_btn.get_children():
			_open_btn.remove_child(child)
			child.queue_free()
		var fresh := CT.pill_button(Tr.t(String(entry[1])).to_upper(), String(SCREEN_GLYPHS.get(id, "")), "open", CT.h("btn"))
		var content := fresh.get_child(0)
		fresh.remove_child(content)
		fresh.free()
		content.set_anchors_preset(Control.PRESET_FULL_RECT)
		content.offset_bottom = -CT.LIP
		_open_btn.add_child(content)
		var connected := bool(_selected_node.get_meta("connected", true))
		_open_btn.disabled = not connected
		_open_btn.tooltip_text = Tr.t("UI2C_STATUS_NO_ROAD") if not connected else ""

func _on_open_screen() -> void:
	var entry: Array = SCREENS.get(_selected_data.id if _selected_data != null else "", [])
	if entry.is_empty():
		return
	var scene := get_tree().current_scene
	var panel: Node = scene.get_node_or_null(String(entry[0])) if scene != null else null
	if panel == null:
		return
	_hide_panel()
	if panel.has_method("open"):
		panel.open()
	elif panel.get("_is_open") != true and panel.has_method("toggle"):
		panel.toggle()
	elif panel.get("_is_open") != true and panel.has_method("_toggle_panel"):
		panel._toggle_panel()

## El boton de trabajadores: solo en edificios que los usan. Retirar (crema,
## icono de retirar) o poner (verde, icono de obrero).
func _refresh_workers_toggle() -> void:
	var uses: bool = _selected_node != null and is_instance_valid(_selected_node) and not _is_deposit \
		and _selected_data != null and _selected_data.workers_required > 0
	_workers_btn.visible = uses
	_workers_hint.visible = false
	if not uses:
		return
	var off: bool = bool(_selected_node.get_meta("workers_off", false))
	if not bool(_selected_node.get_meta("has_vein", true)):
		_workers_hint.text = Tr.t("LBL_NO_VEIN_SHORT")
		_workers_btn.tooltip_text = Tr.t("LBL_NO_VEIN_HINT")
	elif off:
		_workers_hint.text = Tr.t("LBL_WORKERS_OFF_SHORT")
		_workers_btn.tooltip_text = "%s\n%s" % [Tr.t("BTN_WORKERS_ON"), Tr.t("LBL_WORKERS_OFF_HINT") % _selected_data.workers_required]
	else:
		_workers_hint.text = Tr.t("LBL_WORKERS_ON_SHORT") % _selected_data.workers_required
		_workers_btn.tooltip_text = "%s\n%s" % [Tr.t("BTN_WORKERS_OFF"), Tr.t("LBL_WORKERS_ON_HINT") % _selected_data.workers_required]
	_workers_btn.text = ""
	if _workers_btn.get_meta("off_state", -1) != int(off):
		_workers_btn.set_meta("off_state", int(off))
		CT.set_pill_kind(_workers_btn, "primary" if off else "secondary", CT.h("small"))
	_refresh_status_line()

func _on_toggle_workers() -> void:
	if _selected_node == null or not is_instance_valid(_selected_node):
		return
	PopulationManager.set_workers_off(_selected_node, not bool(_selected_node.get_meta("workers_off", false)))
	_refresh_workers_toggle()
	GameManager.request_save()

func _update_deposit_uses() -> void:
	if _selected_node and _selected_node.has_meta("uses_remaining"):
		var uses: int = _selected_node.get_meta("uses_remaining")
		# Los usos a la vista; la diferencia entre sacarlo a mano (se agota) y
		# ponerle su edificio (produce sin gastarlo), al mantener pulsado.
		var key := _selected_deposit_id.to_upper()
		var short := Tr.t("DEP_SHORT_" + key)
		var hint := Tr.t("DEP_HINT_" + key)
		_deposit_uses_label.text = Tr.t("LBL_DEPOSIT_USES") % [uses]
		if GameConfig.is_endless_deposit(_selected_deposit_id):
			_deposit_uses_label.text = Tr.t("LBL_DEPOSIT_ENDLESS")
		var tip: Array = []
		if short != "DEP_SHORT_" + key:
			tip.append(short)
		if hint != "DEP_HINT_" + key:
			tip.append(hint)
		_deposit_uses_label.tooltip_text = "\n".join(tip)
		_deposit_uses_label.visible = true
	else:
		_deposit_uses_label.visible = false

func _hide_panel() -> void:
	if _panel.visible:
		UIManager.close_panel(self)
	_panel.visible = false
	set_process(false)
	_selected_node = null
	_selected_data = null
	_selected_deposit_id = ""
	_demolish_pending = false

func _toggle_panel() -> void:
	_hide_panel()

# ── Actions ──

func _on_rename() -> void:
	if not _selected_node or not _selected_data or not _selected_data.is_core:
		return
	var new_name := _name_edit.text.strip_edges()
	if new_name.is_empty():
		return
	_selected_node.set_meta("custom_name", new_name)
	_title_label.text = new_name
	var label_node := _selected_node.get_node_or_null("NameLabel")
	if label_node and (label_node is Label3D or label_node is Label):
		label_node.text = new_name
	EventBus.building_renamed.emit(_selected_node, new_name)

## Un edificio tocado ensena cuanto le queda y cuanto cuesta levantarlo. En
## ruinas, ademas, avisa de que no produce nada mientras tanto.
func _refresh_repair() -> void:
	if _selected_node == null or not is_instance_valid(_selected_node) or _is_deposit:
		_repair_container.visible = false
		return
	if not BuildingHealth.is_damaged(_selected_node):
		_repair_container.visible = false
		return
	var ruined: bool = BuildingHealth.is_ruined(_selected_node)
	var pct: int = roundi(BuildingHealth.get_health_ratio(_selected_node) * 100.0)
	var cost := BuildingHealth.repair_cost(_selected_node)
	_repair_label.text = Tr.t("LBL_RUINED") if ruined else Tr.t("LBL_DAMAGED") % pct
	_repair_label.add_theme_color_override("font_color", CT.danger_text() if ruined else CT.text("window"))
	CT.fill_cost_strip(_repair_cost_row, by_name(cost), missing_by_name(cost))
	_repair_btn.disabled = not BuildingHealth.can_repair(_selected_node)["ok"]
	_repair_container.visible = true

func _on_repair() -> void:
	if _selected_node == null or not is_instance_valid(_selected_node):
		return
	if BuildingHealth.repair(_selected_node):
		_refresh_repair()
		_refresh_status_line()

func _on_upgrade() -> void:
	if not _selected_node or not _selected_data:
		return
	var level: int = _selected_node.get_meta("level", 1)
	var next_level := level + 1
	if next_level > GameConfig.max_building_level:
		return
	ProductionManager.start_upgrade(_selected_node, _selected_data, next_level)
	_show_building_panel()

func _on_move() -> void:
	if not _selected_node or _is_deposit:
		return
	if _selected_data and _selected_data.is_core:
		return
	EventBus.request_move_building.emit(_selected_node)
	_hide_panel()

## GIRAR: lo levanta como MOVER y gira el fantasma un cuarto de vuelta; se
## suelta donde estaba (o en otro sitio) con el mismo gesto de siempre.
func _on_rotate() -> void:
	if not _selected_node or _is_deposit:
		return
	if _selected_data and _selected_data.is_core:
		return
	EventBus.request_move_building.emit(_selected_node)
	_hide_panel()
	EventBus.building_rotate_requested.emit()

func _on_demolish() -> void:
	if not _selected_node or _is_deposit:
		return
	if _selected_data and _selected_data.is_core:
		return
	_demolish_pending = true
	var refund_pct := int(GameConfig.demolish_refund_ratio * 100)
	var text := Tr.t("FMT_DEMOLISH_CONFIRM") % [_selected_data.get_display_name(), refund_pct]
	# Demoler con un proceso en curso ya no lo quema en silencio: se dice lo que
	# vuelve de el antes de que el jugador confirme.
	if ProcessManager.is_busy(_selected_node):
		var in_progress := ProcessManager.get_refund_preview(_selected_node)
		var amounts := Tr.amount_list(in_progress) if not in_progress.is_empty() else Tr.t("LBL_FREE")
		text += "\n" + Tr.t("FMT_DEMOLISH_IN_PROGRESS") % amounts
	_confirm_label.text = text
	_confirm_container.visible = true
	_actions_box.visible = false

func _confirm_demolish() -> void:
	if _demolish_pending and _selected_node:
		EventBus.request_demolish_building.emit(_selected_node)
	_demolish_pending = false
	_confirm_container.visible = false
	_actions_box.visible = true

func _cancel_demolish() -> void:
	_demolish_pending = false
	_confirm_container.visible = false
	_actions_box.visible = true

# ── Construction ──

func _update_construction() -> void:
	if not _selected_node or _is_deposit:
		_construction_container.visible = false
		return
	if not ProductionManager.is_constructing(_selected_node):
		_construction_container.visible = false
		return
	_construction_container.visible = true
	var progress := ProductionManager.get_construction_progress(_selected_node)
	_construction_bar.value = progress
	var remaining := ProductionManager.get_construction_remaining(_selected_node)
	_construction_label.text = Tr.t("FMT_CONSTRUCTION_SHORT") % [int(progress * 100), TextKit.short_time(remaining)]

# ── Textos cortos (publicos y estaticos para las pruebas) ──

## "Nv 1 · 2 trabajadores · +6 trabajadores · +5 moral".
static func level_line(data: BuildingData, level: int) -> String:
	var parts: Array = [Tr.t("LBL_LEVEL_SHORT") % level]
	if data.workers_required > 0:
		parts.append(Tr.t("LBL_WORKERS_SHORT") % data.workers_required)
	if data.population_capacity > 0:
		parts.append(Tr.t("LBL_CARD_WORKERS") % data.population_capacity)
	if data.morale_bonus > 0:
		parts.append(Tr.t("LBL_MORALE_BONUS") % data.morale_bonus)
	return " · ".join(parts)

## Lo que produce por ciclo a este nivel, por nombre de recurso.
static func production_amounts(data: BuildingData, level: int) -> Dictionary:
	var mult := GameConfig.get_production_multiplier(level)
	var out := {}
	# La Granja rinde lo que diga su cultivo, que lo ensena su seccion.
	if data.id == ProductionManager.FARM_ID:
		return out
	for pair in [["gold", data.produces_gold], ["steel", data.produces_steel], ["oil", data.produces_oil], ["wood", data.produces_wood], ["food", data.produces_food]]:
		if int(pair[1]) > 0:
			out[pair[0]] = int(int(pair[1]) * mult)
	return out

## Un coste por tipo (ResourceManager.Type) pasado a nombre de recurso.
static func by_name(cost: Dictionary) -> Dictionary:
	var out := {}
	for type in cost:
		out[ResourceManager.get_type_name(type)] = int(cost[type])
	return out

## Lo que falta para pagar `cost` (por tipo), por nombre de recurso.
static func missing_by_name(cost: Dictionary) -> Dictionary:
	var out := {}
	for type in cost:
		var short: int = int(cost[type]) - ResourceManager.get_amount(type)
		if short > 0:
			out[ResourceManager.get_type_name(type)] = short
	return out

func _set_actions_header(shown: bool) -> void:
	_actions_header.visible = shown
	_actions_sep.visible = shown
