extends CanvasLayer
## Activity log and notification panel.
## Shows toast notifications and maintains a scrollable history.
## La tarjeta de estado (trabajadores, "en su puesto", moral en palabras) se
## quito en 2026-10: obreros y moral son iconos de la fila de recursos
## (ResourceHUD). Lo urgente (sin madera, sin oro, moral baja, hambre) ya llega
## aqui como aviso de PopulationManager.
## La franja de objetivo de arriba al centro ("Avanza hacia la Victoria
## Imperial...") se quito el 2026-10-05: repetia, peor, lo que dice ¿QUE HACER?
## (Objectives.next_step), que es el unico sitio del siguiente paso.

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
var _is_open := false
var _log_entries: Array = []
var _log_vbox: VBoxContainer
var _toast_container: VBoxContainer
## Avisos retenidos mientras hay un tablero de combate abierto (2026-10-14):
## [mensaje, color]. Van al registro al momento, pero en pantalla salen cuando
## se cierra el tablero (EventBus.encounter_closed): en plena pelea un aviso de
## la colonia distrae y, ademas, se pierde antes de que se pueda leer.
var _held: Array = []

func _ready() -> void:
	layer = 11
	_setup_ui()
	EventBus.notification_posted.connect(_on_notification)
	EventBus.phase_advanced.connect(_on_phase_advanced)
	EventBus.tutorial_intro_requested.connect(func(): _toast_layer.layer = TOAST_LAYER_UNDER_INTRO)
	EventBus.tutorial_intro_closed.connect(func(): _toast_layer.layer = TOAST_LAYER)
	# Con CONSTRUIR abierto, los avisos no tapan la
	# ventana (se metian encima de la lista de edificios).
	UIManager.window_opened.connect(func(_w): _sync_toast_layer())
	UIManager.window_closed.connect(func(_w): _sync_toast_layer.call_deferred())
	# La expedicion pasa fuera de la base: si no deja rastro aqui, el jugador
	# vuelve al mapa sin saber que se trajo ni a quien dejo por el camino.
	EventBus.expedition_started.connect(_on_expedition_started)
	EventBus.expedition_ended.connect(_on_expedition_ended)
	EventBus.encounter_closed.connect(release_held)
	# Otra partida: lo retenido era de la anterior.
	EventBus.game_load_completed.connect(func(): _held.clear())

func _setup_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

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
	# El color lo pone la paleta, no quien avisa (docs/24-paleta.md).
	color = UITheme.notice_color(category, color)
	_log_entries.push_front({"message": message, "category": category, "color": color})
	if _log_entries.size() > MAX_LOG_ENTRIES:
		_log_entries.pop_back()
	_refresh_log()
	# En pantalla, solo lo que pide atencion: peligros, advertencias y los avisos
	# marcados "notice" (un material nuevo, la partida vieja apartada). Lo de
	# rutina ("Camino construido", "Poblacion crecio") va solo al registro.
	if not shows_toast(category):
		return
	# Los del propio combate (salida y vuelta de la columna) si salen.
	if holds_toasts() and category != "combat":
		_held.append([message, color])
		return
	_show_toast(message, color)

## Con un tablero abierto (pelea o parte de la pelea) los avisos esperan.
static func holds_toasts() -> bool:
	return CombatManager.is_board_open()

func held_count() -> int:
	return _held.size()

## Saca lo retenido: los ultimos que caben y, si habia mas, uno que dice
## cuantos quedan en el registro. Si otro tablero se abrio en la misma llamada
## (la oleada siguiente del asedio), sigue esperando.
func release_held() -> void:
	if _held.is_empty() or holds_toasts():
		return
	var cap := MAX_TOASTS_NARROW if UILayoutManager.is_narrow() else MAX_TOASTS
	var items: Array = _held.duplicate()
	_held.clear()
	var extra := 0
	if items.size() > cap:
		extra = items.size() - (cap - 1)
		items = items.slice(items.size() - (cap - 1)) if cap > 1 else []
	for item in items:
		_show_toast(String(item[0]), item[1])
	if extra > 0:
		_show_toast(Tr.t("MSG_HELD_NOTICES") % extra, UITheme.INFO)

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

func _sync_toast_layer() -> void:
	if _toast_layer == null:
		return
	# Solo con CONSTRUIR abierto: los avisos de la Tormenta tienen que seguir
	# encima del tablero y de cualquier otra ventana (test_storm_toasts_over_board).
	var busy := false
	for w in UIManager.open_windows():
		if is_instance_valid(w) and String(w.name) == "ConstructionMenu":
			busy = true
	_toast_layer.layer = TOAST_LAYER_UNDER_INTRO if busy else TOAST_LAYER

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

## Que categorias salen en pantalla ademas de ir al registro. "combat" es la
## salida y la vuelta de la columna (_on_expedition_started/_ended): pasa fuera
## de la base y, sin su aviso, el jugador no sabe que se trajo ni a quien perdio.
static func shows_toast(category: String) -> bool:
	return category in ["warning", "danger", "notice", "combat"]

## El registro, abierto desde el menu.
func open_log() -> void:
	if not _is_open:
		_toggle_panel()

func is_open() -> bool:
	return _is_open

func _toggle_panel() -> void:
	_is_open = not _is_open
	_panel.visible = _is_open

# ── Fases ──

func _on_phase_advanced(new_phase: int) -> void:
	# Notify the player about the new phase
	var phase_msg: String = Tr.t("PHASE_%d" % new_phase)
	if phase_msg != "PHASE_%d" % new_phase:
		EventBus.notification_posted.emit(phase_msg, "info", UITheme.ACCENT)
