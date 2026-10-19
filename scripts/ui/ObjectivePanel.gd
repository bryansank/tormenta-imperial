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
## La meta de la calma (Orden de la Regencia), debajo del paso. Oculta si no toca.
var _calm_goal: Label
## "Sal de escaramuza: ..." (Objectives.sortie_step), solo cuando hay motivo.
var _sortie_line: Label
## Encargos: "Entrega el encargo: Los vecinos" cuando uno ya se puede entregar.
var _now_contract: Label
## Aire y mar: el Astillero o el Aerodromo cuando tocan (Objectives.fleet_step).
var _fleet_line: Label
## Tres campanas (feat/tres-campanas): la siguiente mision que ya se puede jugar
## (Objectives.campaign_step) y lo que falta para el Ataque Final.
var _campaign_line: Label
var _gate_line: Label
var _route_box: VBoxContainer
var _refresh_left := 0.0

const Objectives := preload("res://scripts/services/Objectives.gd")
## Cifras vivas en el porque ({HQ2_COST}, {HQ3_COST}: el coste real del Cuartel
## General, leido de GameConfig; feat/topes-mejoras-ayuda).
const HelpText := preload("res://scripts/ui/BuildingHelpText.gd")
## Cada cuanto se recalcula el paso con el panel abierto. Lo que cambia la
## respuesta (una obra que acaba, oro que entra) pasa todo el rato; un segundo es
## lo bastante vivo para leerlo y no cuesta nada.
const REFRESH_EVERY := 1.0
## El titulo; lo que pide el modo de esta partida va en su tooltip. Se rellena
## al abrir: el panel se construye antes de que la partida cargue y sepa en que
## modo esta.
var _title: Label

func _ready() -> void:
	layer = 15 # Higher than other UI
	_setup_ui()
	EventBus.objective_panel_toggled.connect(toggle)
	UIManager.register_panel(self, "ObjectivePanel")
	# El reloj de refresco solo corre con el panel abierto.
	set_process(false)
	if UITheme.is_cartoon():
		_setup_line()

# ══════════════════════════════════════════════════════════════════════
# LA LINEA DEL SIGUIENTE PASO (rediseno 2026-10, docs/28 §12)
# ══════════════════════════════════════════════════════════════════════
# ¿QUE HACER? deja de ser una entrada del menu ☰: es UNA linea sobre el mapa,
# abajo a la izquierda, con la cara de la Capitana: "Haz una Casa →". Tocar la
# cara la pliega (queda solo la cara) o la despliega; tocar el texto abre este
# panel con el porque y el camino. El porque corto va al mantener pulsado.
# Se oculta mientras el tutorial guiado ensena (ya habla la Capitana) y con el
# menu principal encima. Va en su propia capa de HUD (10): por debajo de las
# ventanas, que la tapan con su velo.

const LINE_LAYER := 10
## Ancho maximo del texto de la linea (se recorta con "…"; entero al mantener).
const LINE_TEXT_MAX := 300.0
const LINE_TEXT_MAX_PHONE := 220.0
## Repaso lento por si algo cambia sin senal (un proceso que acaba).
const LINE_SLOW_REFRESH := 4.0

var _line_layer: CanvasLayer = null
var _line: PanelContainer = null
var _line_face: Control = null
var _line_text: Label = null
var _line_arrow: Control = null
var _line_folded := false
var _line_queued := false

func _setup_line() -> void:
	_line_layer = CanvasLayer.new()
	_line_layer.name = "NextStepLayer"
	_line_layer.layer = LINE_LAYER
	add_child(_line_layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_line_layer.add_child(root)

	_line = PanelContainer.new()
	_line.name = "NextStepLine"
	var st := CartoonTheme.hud_style(CartoonTheme.sem("ACCENT"))
	st.set_content_margin_all(3)
	st.content_margin_right = 12
	st.set_corner_radius_all(30)
	_line.add_theme_stylebox_override("panel", st)
	_line.mouse_filter = Control.MOUSE_FILTER_STOP
	_line.gui_input.connect(_on_line_input)
	_line.add_to_group("hud_next_step")
	root.add_child(_line)
	UILayoutManager.apply_layout("ObjectivePanel.line", _line)
	HudRegistry.register("ObjectivePanel.line", _line)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_line.add_child(row)
	_line_face = CartoonTheme.captain_face(40 if CartoonTheme.phone else 50)
	_line_face.name = "Face"
	row.add_child(_line_face)
	_line_text = CartoonTheme.label("", "button", CartoonTheme.text("hud"))
	_line_text.name = "StepText"
	_line_text.clip_text = true
	_line_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_line_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_line_text)
	_line_arrow = CartoonTheme.make_glyph("next", 18, CartoonTheme.sem("ACCENT"))
	_line_arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_line_arrow)

	for sig in [EventBus.construction_completed, EventBus.building_upgrade_completed,
			EventBus.era_advanced, EventBus.phase_advanced, EventBus.army_changed,
			EventBus.storm_phase_changed, EventBus.tutorial_step_changed]:
		(sig as Signal).connect(func(_a = null, _b = null): queue_line_refresh())
	EventBus.building_placed.connect(func(_d, _c): queue_line_refresh())
	EventBus.building_demolished.connect(func(_n, _c): queue_line_refresh())
	EventBus.resource_changed.connect(func(_r, _a, _d): queue_line_refresh())
	EventBus.game_load_completed.connect(queue_line_refresh)
	EventBus.game_new_started.connect(queue_line_refresh)
	EventBus.tutorial_guide_finished.connect(func(_s): queue_line_refresh())
	EventBus.tutorial_intro_closed.connect(queue_line_refresh)
	var slow := Timer.new()
	slow.name = "LineRefresh"
	slow.wait_time = LINE_SLOW_REFRESH
	slow.autostart = true
	slow.timeout.connect(queue_line_refresh)
	_line_layer.add_child(slow)
	_line_timer = Timer.new()
	_line_timer.name = "LineCoalesce"
	_line_timer.one_shot = true
	_line_timer.wait_time = LINE_COALESCE
	_line_timer.timeout.connect(refresh_line)
	_line_layer.add_child(_line_timer)
	refresh_line.call_deferred()

## Rafagas de senales (un tick de produccion mueve cuatro recursos, una obra
## cobra y coloca): se juntan y se pregunta el paso una vez cada LINE_COALESCE.
const LINE_COALESCE := 0.4
var _line_timer: Timer = null

func queue_line_refresh() -> void:
	if _line == null or _line_queued:
		return
	_line_queued = true
	if _line_timer != null and _line_timer.is_inside_tree():
		_line_timer.start()
	else:
		refresh_line.call_deferred()

## Vuelve a preguntar el paso y repinta la linea. Publico para pruebas.
func refresh_line() -> void:
	_line_queued = false
	if _line == null:
		return
	var hide: bool = TutorialManager.is_coach_active() or TutorialManager.is_title_menu_open() \
		or not GameManager.is_started()
	var step: Dictionary = Objectives.next_step()
	var text: Dictionary = Objectives.describe(step)
	var title := String(text.get("title", ""))
	_line.visible = not hide and title != "" and not HudRegistry.is_hidden("ObjectivePanel.line")
	_line_text.text = title
	var max_w := LINE_TEXT_MAX_PHONE if CartoonTheme.phone else LINE_TEXT_MAX
	var font := _line_text.get_theme_font("font")
	var fsize := _line_text.get_theme_font_size("font_size")
	var w := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x if font != null else max_w
	_line_text.custom_minimum_size.x = minf(w + 2.0, max_w)
	var why := HelpText.live_text(String(text.get("why", "")))
	var blocker := String(text.get("blocker", ""))
	var tip := title
	if why != "":
		tip += "\n" + why
	if blocker != "":
		tip += "\n" + blocker
	_line.tooltip_text = tip + "\n" + Tr.t("HUD_NEXT_TIP")
	_line_text.visible = not _line_folded
	_line_arrow.visible = not _line_folded

## La cara pliega y despliega; el resto de la linea abre el panel.
func _on_line_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	_line.accept_event()
	var at: Vector2 = _line.get_global_transform() * (event as InputEventMouseButton).position
	if _line_face.get_global_rect().grow(6.0).has_point(at) or _line_folded:
		set_line_folded(not _line_folded)
		return
	if not _is_open:
		toggle()

func set_line_folded(folded: bool) -> void:
	_line_folded = folded
	if _line_text != null:
		_line_text.visible = not folded
		_line_arrow.visible = not folded
		_line.reset_size()

func is_line_folded() -> bool:
	return _line_folded

## La linea (pruebas, HelpTargets, PauseMenu.entry("Colony_objectives")).
func line() -> Control:
	return _line

func line_text() -> String:
	return _line_text.text if _line_text != null else ""

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

	# Header. La mision del modo va en el tooltip del titulo (2026-10-04): la
	# ultima linea de EL CAMINO ya la dice, y antes ocupaba la cabecera entera.
	var header := UITheme.make_panel_header(Tr.t("LBL_OBJ_TITLE"), toggle)
	_title = header.get_child(0) as Label
	if _title != null:
		_title.mouse_filter = Control.MOUSE_FILTER_PASS
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
	_calm_goal = UITheme.make_label("", "body", UITheme.WARNING)
	_calm_goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_calm_goal.visible = false
	content.add_child(_calm_goal)
	# Segunda linea (doc 21 §2.4 y §3.6): salir de escaramuza cuando hay motivo.
	# Va aparte del paso de la linea: no lo sustituye, lo acompana.
	_sortie_line = UITheme.make_label("", "body", UITheme.CAT_MILITARY.lightened(0.25))
	_sortie_line.name = "SortieLine"
	_sortie_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sortie_line.visible = false
	content.add_child(_sortie_line)
	_now_contract = UITheme.make_label("", "body", UITheme.POSITIVE)
	_now_contract.name = "ContractStep"
	_now_contract.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_now_contract.visible = false
	content.add_child(_now_contract)
	# Aire y mar: "Construye un Astillero / un Aerodromo" como idea aparte.
	_fleet_line = UITheme.make_label("", "body", UITheme.INFO)
	_fleet_line.name = "FleetStep"
	_fleet_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fleet_line.visible = false
	content.add_child(_fleet_line)
	_campaign_line = UITheme.make_label("", "body", UITheme.CAT_MILITARY.lightened(0.25))
	_campaign_line.name = "CampaignStep"
	_campaign_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_campaign_line.visible = false
	content.add_child(_campaign_line)
	_gate_line = UITheme.make_label("", "small", UITheme.WARNING)
	_gate_line.name = "AuditGateLine"
	_gate_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_gate_line.visible = false
	content.add_child(_gate_line)

	# ── EL CAMINO: la linea entera, con lo hecho marcado ──
	content.add_child(UITheme.make_separator())
	content.add_child(UITheme.section_header(Tr.t("OBJ_ROUTE")))
	_route_box = VBoxContainer.new()
	_route_box.add_theme_constant_override("separation", 4)
	content.add_child(_route_box)

	# La nota de "CONSTRUIR abajo, el resto en MENU" (29 palabras, y con Mercado y
	# Tecnologia ya fuera del menu) se quito el 2026-10-04: lo dicen las ayudas.

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
	set_process(_is_open)
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
	_now_why.text = HelpText.live_text(String(text["why"]))
	_now_blocker.text = String(text["blocker"])
	_now_blocker.visible = String(text["blocker"]) != ""
	var goal: Dictionary = Objectives.calm_goal()
	_calm_goal.text = String(goal.get("text", ""))
	_calm_goal.visible = not goal.is_empty()
	var sortie: Dictionary = Objectives.sortie_step()
	if sortie.is_empty():
		_sortie_line.visible = false
	else:
		var sortie_text: Dictionary = Objectives.describe(sortie)
		_sortie_line.text = "%s\n%s" % [String(sortie_text["title"]), String(sortie_text["why"])]
		_sortie_line.visible = true
	var contract: Dictionary = Objectives.contract_step()
	_now_contract.visible = not contract.is_empty()
	if not contract.is_empty():
		var ctext: Dictionary = Objectives.describe(contract)
		_now_contract.text = "%s\n%s" % [String(ctext["title"]), String(ctext["why"])]
	var fleet: Dictionary = Objectives.fleet_step()
	# No repite el paso principal (si la linea ya pide eso mismo, sobra).
	if not fleet.is_empty() and String(fleet.get("id", "")) == String(step.get("id", "")):
		fleet = {}
	_fleet_line.visible = not fleet.is_empty()
	if not fleet.is_empty():
		var ftext: Dictionary = Objectives.describe(fleet)
		_fleet_line.text = "%s\n%s" % [String(ftext["title"]), String(ftext["why"])]
	var camp: Dictionary = Objectives.campaign_step()
	_campaign_line.visible = not camp.is_empty()
	if not camp.is_empty():
		var camp_text: Dictionary = Objectives.describe(camp)
		_campaign_line.text = "%s\n%s" % [String(camp_text["title"]), String(camp_text["why"])]
	# Lo que falta para el Ataque Final, desde la era 3 (cuando el Cuartel
	# General ya se ve venir). Antes seria ruido.
	var gate: String = Objectives.final_gate_text() if ProgressionManager.current_era >= 3 else ""
	_gate_line.text = gate
	_gate_line.visible = gate != ""
	_paint_route()

## La linea de Objectives.LINE, una fila por paso: hecho, el de ahora, o por hacer.
## Se refresca cada segundo con el panel abierto: las etiquetas que ya hay se
## reescriben (antes se tiraban y se creaban todas cada vez).
func _paint_route() -> void:
	var rows: Array = Objectives.route()
	var labels := _route_box.get_children()
	for i in rows.size():
		var row: Dictionary = rows[i]
		var mark: String = "✔ " if bool(row["done"]) else ("▶ " if bool(row["current"]) else "· ")
		var color: Color = UITheme.TEXT_DIM if bool(row["done"]) else (UITheme.ACCENT if bool(row["current"]) else UITheme.TEXT)
		var text := mark + String(row["text"])
		if i < labels.size():
			var label := labels[i] as Label
			label.text = text
			UITheme.set_label_color(label, color)
		else:
			var label := UITheme.make_label(text, "small", color)
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_route_box.add_child(label)
	for i in range(rows.size(), labels.size()):
		_route_box.remove_child(labels[i])
		labels[i].queue_free()

func get_now_text() -> Dictionary:
	return {"title": _now_title.text, "why": _now_why.text, "blocker": _now_blocker.text}

# ── modos-de-juego ──

func refresh_mode() -> void:
	if _title != null:
		_title.tooltip_text = "%s\n%s" % [Tr.t("LBL_OBJ_MODE") % GameMode.display_name().to_upper(), Tr.t(GameMode.goal_key())]

## La mision del modo, como la ve el jugador (tooltip del titulo). Para pruebas.
func mode_text() -> String:
	return _title.tooltip_text if _title != null else ""
