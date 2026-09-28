extends CanvasLayer
## Activity log and notification panel.
## Shows toast notifications and maintains a scrollable history.
## Status bar shows population, workers, and morale.

const MAX_LOG_ENTRIES := 50
const TOAST_DURATION := 4.0
## Avisos visibles a la vez (el resto va solo al registro).
const MAX_TOASTS := 3
const MAX_TOASTS_NARROW := 1
## Los avisos van en su propia capa, por encima del tablero de batalla (18) y
## por debajo de la pantalla de victoria (20): la Tormenta tiene que poder avisar
## mientras se pelea (ceniza, Diezmo, la guarnicion que peleo sola). El resto del
## panel (estado, registro) se queda en la 11. Ni este panel ni la subcapa estan
## en la pila de UIManager, asi que nadie les reasigna la capa.
const TOAST_LAYER := 19
## Mientras la intro del tutorial (17) esta abierta, los avisos vuelven debajo
## de ella, donde siempre estuvieron: en ese momento la intro es lo unico que se
## lee, y ningun tablero puede estar abierto.
const TOAST_LAYER_UNDER_INTRO := 11

var _panel: PanelContainer
var _toast_layer: CanvasLayer
var _log_btn: Button
var _is_open := false
var _log_entries: Array = []
var _log_vbox: VBoxContainer
var _toast_container: VBoxContainer
var _pop_label: Label
var _morale_label: Label
var _morale_bar: ProgressBar
var _workers_label: Label
## Las tres explicaciones de la tarjeta de poblacion, que un toque despliega.
var _status_hint: Label
var _status_panel: PanelContainer
var _objective_label: Label

func _ready() -> void:
	layer = 11
	_setup_ui()
	EventBus.notification_posted.connect(_on_notification)
	EventBus.population_changed.connect(_on_population_changed)
	EventBus.morale_changed.connect(_on_morale_changed)
	EventBus.workers_changed.connect(_on_workers_changed)
	EventBus.phase_advanced.connect(_on_phase_advanced)
	EventBus.milestone_completed.connect(func(_m): _update_objective_hint())
	# El modo se sabe al terminar de cargar (o de empezar): el objetivo depende de el.
	EventBus.game_load_completed.connect(_update_objective_hint)
	EventBus.game_new_started.connect(_update_objective_hint)
	EventBus.tutorial_intro_requested.connect(func(): _toast_layer.layer = TOAST_LAYER_UNDER_INTRO)
	EventBus.tutorial_intro_closed.connect(func(): _toast_layer.layer = TOAST_LAYER)
	# La expedicion pasa fuera de la base: si no deja rastro aqui, el jugador
	# vuelve al mapa sin saber que se trajo ni a quien dejo por el camino.
	EventBus.expedition_started.connect(_on_expedition_started)
	EventBus.expedition_ended.connect(_on_expedition_ended)
	_update_status_labels()
	_update_objective_hint()
	# Hide status bar until Phase 1 when pop/morale become relevant
	if ProgressionManager.current_phase < GameConfig.Phase.SETTLEMENT:
		_status_panel.visible = false

func _setup_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Status bar (top-left below HUD)
	_status_panel = PanelContainer.new()
	var status_panel := _status_panel
	UILayoutManager.apply_layout("NotificationPanel.status", status_panel)
	# Misma tarjeta que el panel de recursos, justo encima: se leen como una
	# sola columna de estado (recursos -> poblacion y moral).
	status_panel.add_theme_stylebox_override("panel", UITheme.make_hud_card_style(UITheme.ACCENT, 2, true))
	root.add_child(status_panel)
	HudRegistry.register("NotificationPanel.status", status_panel)

	var status_vbox := VBoxContainer.new()
	status_vbox.add_theme_constant_override("separation", 5)
	status_panel.add_child(status_vbox)

	# Population row with icon
	var pop_row := HBoxContainer.new()
	pop_row.add_theme_constant_override("separation", 6)
	var pop_icon := UITheme.make_label("\u2302", "body", UITheme.CAT_SUPPORT)  # House icon
	pop_row.add_child(pop_icon)
	_pop_label = UITheme.make_label("", "small", UITheme.CAT_SUPPORT)
	pop_row.add_child(_pop_label)
	status_vbox.add_child(pop_row)

	# Workers row with icon
	var work_row := HBoxContainer.new()
	work_row.add_theme_constant_override("separation", 6)
	var work_icon := UITheme.make_label("\u2692", "body", UITheme.INFO)  # Hammer & pick
	work_row.add_child(work_icon)
	_workers_label = UITheme.make_label("", "small", UITheme.INFO)
	work_row.add_child(_workers_label)
	status_vbox.add_child(work_row)

	# Morale row with icon + progress bar
	var morale_row := HBoxContainer.new()
	morale_row.add_theme_constant_override("separation", 6)
	var morale_icon := UITheme.make_label("\u2665", "body", UITheme.WARNING)  # Heart
	morale_row.add_child(morale_icon)
	_morale_label = UITheme.make_label("", "small", UITheme.WARNING)
	morale_row.add_child(_morale_label)
	status_vbox.add_child(morale_row)

	# Que es cada fila, en palabras (bug 11): al pasar el raton sale en el
	# tooltip de la fila y, con el dedo, un toque en la tarjeta despliega las
	# tres explicaciones debajo.
	pop_row.tooltip_text = Tr.t("HINT_HUD_POPULATION")
	work_row.tooltip_text = Tr.t("HINT_HUD_WORKERS")
	morale_row.tooltip_text = Tr.t("HINT_HUD_MORALE")
	for row in [pop_row, work_row, morale_row]:
		(row as Control).mouse_filter = Control.MOUSE_FILTER_STOP
		(row as Control).gui_input.connect(_on_status_tap)

	# Morale bar
	_morale_bar = UITheme.make_progress_bar(UITheme.WARNING, 8)
	_morale_bar.custom_minimum_size.x = 110
	_morale_bar.max_value = 100.0
	_morale_bar.value = PopulationManager.get_morale()
	status_vbox.add_child(_morale_bar)

	_status_hint = UITheme.make_label("%s\n%s\n%s" % [Tr.t("HINT_HUD_POPULATION"),
		Tr.t("HINT_HUD_WORKERS"), Tr.t("HINT_HUD_MORALE")], "small", UITheme.TEXT_DIM)
	_status_hint.name = "StatusHint"
	_status_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_hint.custom_minimum_size.x = 220
	_status_hint.visible = false
	status_vbox.add_child(_status_hint)

	# Log button integrated below status
	_log_btn = Button.new()
	_log_btn.text = Tr.t("BTN_LOG_HUD")
	_log_btn.tooltip_text = Tr.t("HINT_HUD_LOG")
	_log_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_button(_log_btn, UITheme.BTN, UITheme.FONT_SMALL)
	# Sin alto propio: style_button le da MIN_BTN_H (44), el minimo tactil.
	# Antes pedia 28 px, que un pulgar no acierta.
	_log_btn.pressed.connect(_toggle_panel)
	status_vbox.add_child(_log_btn)
	HudRegistry.register("NotificationPanel.log_button", _log_btn)

	# Objective hint (top-center)
	var obj_panel := PanelContainer.new()
	UILayoutManager.apply_layout("NotificationPanel.objective", obj_panel)
	obj_panel.add_theme_stylebox_override("panel", UITheme.make_hud_card_style(UITheme.ACCENT))
	obj_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(obj_panel)
	HudRegistry.register("NotificationPanel.objective", obj_panel)

	_objective_label = UITheme.make_label("", "small", UITheme.ACCENT)
	_objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_objective_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	obj_panel.add_child(_objective_label)

	# Toast container (bottom-left), en su propia capa para verse sobre el tablero.
	_toast_layer = CanvasLayer.new()
	_toast_layer.layer = TOAST_LAYER
	add_child(_toast_layer)
	var toast_root := Control.new()
	toast_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	toast_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_layer.add_child(toast_root)
	_toast_container = VBoxContainer.new()
	UILayoutManager.apply_layout("NotificationPanel.toasts", _toast_container)
	_toast_container.add_theme_constant_override("separation", 4)
	_toast_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_root.add_child(_toast_container)
	HudRegistry.register("NotificationPanel.toasts", _toast_container)

	# Log panel
	_panel = PanelContainer.new()
	UILayoutManager.apply_layout("NotificationPanel.log", _panel)
	_panel.visible = false
	_panel.add_theme_stylebox_override("panel", UITheme.make_war_table_style())
	root.add_child(_panel)
	HudRegistry.register("NotificationPanel.log", _panel)

	var panel_vbox := VBoxContainer.new()
	panel_vbox.add_theme_constant_override("separation", 4)
	_panel.add_child(panel_vbox)

	panel_vbox.add_child(UITheme.make_panel_header(Tr.t("LBL_LOG_TITLE"), _toggle_panel))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel_vbox.add_child(scroll)

	_log_vbox = VBoxContainer.new()
	_log_vbox.add_theme_constant_override("separation", 2)
	_log_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_log_vbox)

func _on_notification(message: String, category: String, color: Color) -> void:
	_log_entries.push_front({"message": message, "category": category, "color": color})
	if _log_entries.size() > MAX_LOG_ENTRIES:
		_log_entries.pop_back()
	_refresh_log()
	_show_toast(message, color)

func _on_expedition_started(_expedition_id: int, node_count: int) -> void:
	_on_notification(Tr.t("MSG_EXPEDITION_STARTED") % node_count, "combat", UITheme.ACCENT)

## El parte de vuelta: que resultado, que botin y a quien no traemos. Las tres
## cosas en una linea, porque un toast se lee de una pasada o no se lee.
func _on_expedition_ended(result: int, rewards: Dictionary, casualties: Dictionary) -> void:
	var fallen: int = 0
	for count in casualties.values():
		fallen += int(count)

	var message: String
	var color: Color
	match result:
		0:
			message = Tr.t("MSG_EXPEDITION_WON") % _spoils_text(rewards)
			color = UITheme.POSITIVE
		2:
			message = Tr.t("MSG_EXPEDITION_ABANDONED")
			color = UITheme.WARNING
		_:
			message = Tr.t("MSG_EXPEDITION_LOST") % fallen
			color = UITheme.DANGER

	if result != 0 and not rewards.is_empty():
		message += "  %s: %s" % [Tr.t("LBL_REWARDS"), _spoils_text(rewards)]
	if result != 1 and fallen > 0:
		message += "  %s: %s" % [Tr.t("LBL_CASUALTIES"), _casualty_text(casualties)]
	_on_notification(message, "combat", color)

func _spoils_text(rewards: Dictionary) -> String:
	if rewards.is_empty():
		return Tr.t("LBL_NO_REWARDS")
	var parts: Array = []
	for res_name in rewards:
		parts.append("%d %s" % [int(rewards[res_name]), Tr.res_name(res_name)])
	return " ".join(parts)

func _casualty_text(casualties: Dictionary) -> String:
	var parts: Array = []
	for unit_id in casualties:
		var def := GameConfig.get_unit_def(unit_id)
		parts.append("%d %s" % [int(casualties[unit_id]), Tr.t(def.get("name", unit_id))])
	return " ".join(parts)

func _show_toast(text: String, color: Color) -> void:
	var toast_bg := PanelContainer.new()
	toast_bg.add_theme_stylebox_override("panel", UITheme.make_hud_card_style(color.darkened(0.3), 1, true))
	toast_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var label := UITheme.make_label(text, "small", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.custom_minimum_size.x = 280
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_bg.add_child(label)
	_toast_container.add_child(toast_bg)
	# Tope de avisos a la vez: en una tablet (lienzo de ~700 de alto) cinco
	# avisos seguidos subian hasta tapar la poblacion y el boton del registro.
	# Los que salen ya estan en el registro.
	var alive: Array = _toast_container.get_children().filter(func(c): return not c.is_queued_for_deletion())
	# En pantalla estrecha (movil en vertical) solo cabe uno entre la columna
	# y CONSTRUIR.
	var cap := MAX_TOASTS_NARROW if UILayoutManager.is_narrow() else MAX_TOASTS
	while alive.size() > cap:
		var oldest: Node = alive.pop_front()
		oldest.queue_free()

	var tween := create_tween()
	tween.tween_interval(TOAST_DURATION)
	tween.tween_property(toast_bg, "modulate:a", 0.0, 1.0)
	tween.tween_callback(toast_bg.queue_free)

func _refresh_log() -> void:
	for child in _log_vbox.get_children():
		child.queue_free()
	for entry in _log_entries:
		var label := UITheme.make_label(entry["message"], "small", entry["color"])
		label.autowrap_mode = TextServer.AUTOWRAP_WORD
		_log_vbox.add_child(label)

func _on_population_changed(current: int, max_pop: int) -> void:
	_pop_label.text = Tr.t("LBL_HUD_POPULATION") % [current, max_pop]

func _on_morale_changed(new_morale: int) -> void:
	_morale_label.text = morale_text(new_morale)
	_morale_bar.value = new_morale
	var color: Color
	if new_morale <= 30:
		color = UITheme.DANGER
	elif new_morale <= 60:
		color = UITheme.WARNING
	else:
		color = UITheme.POSITIVE
	UITheme.set_label_color(_morale_label, color)
	# Update bar fill color
	var fill := _morale_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill:
		fill.bg_color = color

func _on_workers_changed(used: int, total: int) -> void:
	_workers_label.text = workers_text(used, total)

func _update_status_labels() -> void:
	_pop_label.text = Tr.t("LBL_HUD_POPULATION") % [PopulationManager.get_population(), PopulationManager.get_max_population()]
	_workers_label.text = workers_text(PopulationManager.get_used_workers(), PopulationManager.get_population())
	_morale_label.text = morale_text(PopulationManager.get_morale())

## "Obreros: 3 trabajan, 2 libres" en vez de "Trabajadores: 3/5", que no decia
## si eran libres u ocupados.
static func workers_text(used: int, total: int) -> String:
	return Tr.t("LBL_HUD_WORKERS") % [used, maxi(0, total - used)]

## "Moral 75 %: produccion x1.1": lo que la moral HACE, no solo cuanta hay.
static func morale_text(morale: int) -> String:
	return Tr.t("LBL_HUD_MORALE") % [morale, PopulationManager.morale_to_multiplier(morale)]

func _on_status_tap(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_status_hint.visible = not _status_hint.visible
		get_viewport().set_input_as_handled()

## Si las explicaciones de la tarjeta estan desplegadas. Para tests.
func is_status_hint_shown() -> bool:
	return _status_hint != null and _status_hint.visible

func _toggle_panel() -> void:
	_is_open = not _is_open
	_panel.visible = _is_open

# ── Phase & Objective System ──

func _on_phase_advanced(new_phase: int) -> void:
	# Show status bar once consumption kicks in
	if new_phase >= GameConfig.Phase.SETTLEMENT:
		_status_panel.visible = true
	# Notify the player about the new phase
	var phase_msg: String = Tr.t("PHASE_%d" % new_phase)
	if phase_msg != "PHASE_%d" % new_phase:
		EventBus.notification_posted.emit(phase_msg, "info", UITheme.ACCENT)
	_update_objective_hint()

func _update_objective_hint() -> void:
	if not _objective_label:
		return
	# Sandbox lo tiene todo abierto: los pasos de la campana no aplican.
	if GameMode.all_unlocked():
		_objective_label.text = Tr.t(GameMode.goal_key())
		return
	var phase: int = ProgressionManager.current_phase
	var hint: String = ""
	match phase:
		GameConfig.Phase.FOUNDATION:
			hint = Tr.t("OBJ_PHASE_0")
		GameConfig.Phase.SETTLEMENT:
			if not ProgressionManager.is_milestone_completed("first_gold_mine"):
				hint = Tr.t("OBJ_PHASE_1")
			else:
				hint = Tr.t("OBJ_PHASE_1_DONE")
		GameConfig.Phase.ECONOMY:
			if not ProgressionManager.is_milestone_completed("first_warehouse"):
				hint = Tr.t("OBJ_PHASE_2")
			else:
				hint = Tr.t("OBJ_PHASE_2_DONE")
		GameConfig.Phase.SURVIVAL:
			if not ProgressionManager.is_milestone_completed("era_2"):
				hint = Tr.t("OBJ_PHASE_3")
			else:
				hint = Tr.t("OBJ_PHASE_3_DONE")
		_:
			hint = Tr.t("OBJ_PHASE_4")
	_objective_label.text = hint
