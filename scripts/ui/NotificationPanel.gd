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
##
## Avisos (Bryan, 2026-10-18: "las alertas se sobreponen a todo, se ve feo"):
## UN solo sitio, la columna izquierda bajo los recursos (slot toast_area), y
## tambien para los logros, la era nueva y el ascenso de rango (categoria
## "achievement": ProgressPanel y RankPanel ya no pintan placas propias). Como
## mucho 2 a la vez (1 en telefono), el resto en cola y los repetidos agrupados
## ("×3") en AlertQueue. Compactos: icono + una frase, ✕, se van solos, sin
## animaciones. Con una ventana o el tablero abiertos, o con la tarjeta del
## tutorial o un consejo encima de la columna, esperan; solo un aviso de peligro
## se ve, pequeno.

const AlertQueue := preload("res://scripts/ui/AlertQueue.gd")

const MAX_LOG_ENTRIES := 50
## Avisos visibles a la vez: 2; 1 en telefono o cuando no caben dos entre la
## columna izquierda y la cruceta.
const MAX_TOASTS := 2
const MAX_TOASTS_NARROW := 1
## Alto de referencia de un aviso (dos lineas) y ancho del normal y el compacto.
const TOAST_H := 50.0
const TOAST_W := 340.0
const TOAST_W_COMPACT := 300.0
## Los avisos van en su propia capa, por encima del tablero de batalla (18) y
## por debajo de la pantalla de victoria (20): con una ventana o el tablero
## abiertos solo puede verse uno de peligro, pequeno, y tiene que verse. El
## registro se queda en la 11. Ni este panel ni la subcapa estan en la pila de
## UIManager, asi que nadie les reasigna la capa.
const TOAST_LAYER := 19
## Mientras la intro del tutorial (17) esta abierta, los avisos vuelven debajo
## de ella: en ese momento la intro es lo unico que se lee.
const TOAST_LAYER_UNDER_INTRO := 11
## Cada cuanto se mira si algo tapa la columna (tarjeta del tutorial, consejo).
const BLOCK_CHECK_SECONDS := 0.25

var _panel: PanelContainer
var _toast_layer: CanvasLayer
var _is_open := false
var _log_entries: Array = []
var _log_vbox: VBoxContainer
var _toast_container: VBoxContainer
## Con algo abierto, el unico aviso de peligro se aparta a la esquina de abajo a
## la izquierda (libre con CONSTRUIR, la ficha, Ajustes y el tablero), en vez
## de tapar el contenido de la ventana o la cabecera del tablero.
var _edge_container: VBoxContainer
## La cola de avisos (pura): lo que se ve y lo que espera.
var _alerts := AlertQueue.new()
var _check_left := 0.0
## Lo que se pinto la ultima vez: para no rehacer los nodos sin motivo.
var _drawn_sig := ""
## Si lo pintado es el aviso pequeno de "hay una ventana abierta" (una linea).
var _busy_drawn := false

func _ready() -> void:
	layer = 11
	_setup_ui()
	EventBus.notification_posted.connect(_on_notification)
	EventBus.phase_advanced.connect(_on_phase_advanced)
	EventBus.tutorial_intro_requested.connect(func():
		_toast_layer.layer = TOAST_LAYER_UNDER_INTRO
		_pump())
	EventBus.tutorial_intro_closed.connect(func():
		_toast_layer.layer = TOAST_LAYER
		_pump.call_deferred())
	# Una ventana abierta (CONSTRUIR, ficha, Ejercito, Misiones, Ajustes...):
	# los avisos esperan; al cerrarla, salen.
	UIManager.window_opened.connect(func(_w): _pump())
	UIManager.window_closed.connect(func(_w): _pump.call_deferred())
	UILayoutManager.layout_changed.connect(func(): _pump.call_deferred())
	# La expedicion pasa fuera de la base: si no deja rastro aqui, el jugador
	# vuelve al mapa sin saber que se trajo ni a quien dejo por el camino.
	EventBus.expedition_started.connect(_on_expedition_started)
	EventBus.expedition_ended.connect(_on_expedition_ended)
	EventBus.encounter_closed.connect(release_held)
	# Otra partida: lo que esperaba era de la anterior.
	EventBus.game_load_completed.connect(func():
		_alerts.clear()
		_pump())
	set_process(false)

func _setup_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# La columna de avisos, en su propia capa para verse sobre el tablero.
	_toast_layer = CanvasLayer.new()
	_toast_layer.layer = TOAST_LAYER
	add_child(_toast_layer)
	var toast_root := Control.new()
	toast_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	toast_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_layer.add_child(toast_root)
	_toast_container = VBoxContainer.new()
	_toast_container.name = "Alerts"
	UILayoutManager.apply_layout("NotificationPanel.toasts", _toast_container)
	_toast_container.add_theme_constant_override("separation", 4)
	_toast_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_root.add_child(_toast_container)
	HudRegistry.register("NotificationPanel.toasts", _toast_container)
	_edge_container = VBoxContainer.new()
	_edge_container.name = "EdgeAlert"
	_edge_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_edge_container.offset_left = 10.0
	_edge_container.offset_top = 10.0
	_edge_container.offset_right = -10.0
	_edge_container.offset_bottom = -10.0
	_edge_container.alignment = BoxContainer.ALIGNMENT_END
	toast_root.add_child(_edge_container)

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
	# En pantalla, solo lo que pide atencion: peligros, advertencias, los avisos
	# marcados "notice" (un material nuevo), la columna que sale o vuelve y los
	# logros (hito, era, rango). Lo de rutina va solo al registro.
	if not shows_toast(category):
		return
	_alerts.post(message, category, color)
	_pump()

## Con un tablero abierto (pelea o parte de la pelea).
static func holds_toasts() -> bool:
	return CombatManager.is_board_open()

## Avisos esperando su turno (una ventana o el tablero abiertos, o ya estan en
## pantalla los que caben).
func held_count() -> int:
	return _alerts.waiting_count()

## Al cerrarse el tablero, lo que esperaba sale.
func release_held() -> void:
	_pump()

## La cola de avisos (tests y sondas).
func alerts() -> RefCounted:
	return _alerts

## Los avisos en pantalla ahora (nodos).
func shown_toasts() -> Array:
	var out: Array = []
	for box in [_toast_container, _edge_container]:
		out.append_array(box.get_children().filter(func(c): return not c.is_queued_for_deletion()))
	return out

## Algo abierto encima: los avisos esperan (salvo uno de peligro, pequeno).
func is_busy() -> bool:
	if holds_toasts() or _is_open:
		return true
	for w in UIManager.open_windows():
		if is_instance_valid(w) and w != self:
			return true
	if not is_inside_tree():
		return false
	for n in get_tree().get_nodes_in_group("modal_screen"):
		if n.has_method("is_showing") and n.is_showing():
			return true
	for n in get_tree().get_nodes_in_group("tutorial_panel"):
		if n.has_method("is_intro_open") and n.is_intro_open():
			return true
	return _column_blocked()

## La tarjeta del tutorial o un consejo (grupo "alert_blocker") tapan la
## columna de avisos.
func _column_blocked() -> bool:
	var col := column_rect()
	for n in get_tree().get_nodes_in_group("alert_blocker"):
		var c := n as Control
		if c != null and c.is_visible_in_tree() and c.get_global_rect().intersects(col):
			return true
	return false

## Donde caen los avisos aunque aun no haya ninguno: la esquina del contenedor
## con el ancho y el alto de dos avisos.
func column_rect() -> Rect2:
	var pos := _toast_container.global_position
	return Rect2(pos, Vector2(maxf(_toast_container.size.x, TOAST_W), maxf(_toast_container.size.y, TOAST_H * 2.0)))

## Pantalla pequena: telefono, o lienzo estrecho (vertical).
func is_compact() -> bool:
	return UILayoutManager.is_narrow() or DeviceProfile.current() == DeviceProfile.PHONE

## Cuantos caben: 2, o 1 en telefono o si entre la columna y la cruceta (con
## los controles en pantalla) no hay sitio para dos.
func capacity() -> int:
	if is_compact():
		return MAX_TOASTS_NARROW
	var vp := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280, 720)
	var floor_y := vp.y
	if GameConfig.onscreen_controls_visible():
		floor_y -= UILayoutConfig.TOUCH_CONTROLS_MARGIN + UILayoutConfig.TOUCH_DPAD_SIDE * UILayoutManager.touch_controls_scale()
	var room := floor_y - _toast_container.global_position.y
	return MAX_TOASTS if room >= TOAST_H * 2.0 + 8.0 else MAX_TOASTS_NARROW

## Coloca la cola y repinta si cambio algo.
func _pump() -> void:
	if _toast_container == null or not is_inside_tree():
		return
	var busy := is_busy()
	_alerts.arrange(capacity(), busy)
	_redraw(busy)
	set_process(not _alerts.shown.is_empty() or not _alerts.waiting.is_empty())

func _process(delta: float) -> void:
	if _alerts.tick(delta):
		_pump()
		return
	# La tarjeta del tutorial se mueve sin senal: se mira a ratos.
	_check_left -= delta
	if _check_left <= 0.0:
		_check_left = BLOCK_CHECK_SECONDS
		_pump()

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

## Pinta lo que se ve: un aviso por entrada (icono + una frase + "×N" + ✕).
## Sin animaciones: aparece y desaparece.
func _redraw(busy: bool = false) -> void:
	# Con una ventana abierta, el de peligro va en una linea; en telefono, dos
	# como mucho y mas estrecho.
	var compact := busy or is_compact()
	var parts: Array = []
	for e in _alerts.shown:
		parts.append("%s#%d" % [e["key"], int(e["count"])])
	var sig := "%s|%s|%s" % [compact, busy, ",".join(parts)]
	if sig == _drawn_sig and shown_toasts().size() == _alerts.shown.size():
		return
	_drawn_sig = sig
	_busy_drawn = busy
	for box in [_toast_container, _edge_container]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	var target: VBoxContainer = _edge_container if busy else _toast_container
	for e in _alerts.shown:
		var toast := _make_toast(e, compact)
		toast.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		target.add_child(toast)
	# Sin hijos el contenedor encoge (los globos apilados debajo suben).
	_toast_container.reset_size()

func _make_toast(e: Dictionary, compact: bool) -> PanelContainer:
	var color: Color = e["color"]
	var category := String(e["category"])
	var text: String
	if bool(e["summary"]):
		text = Tr.t("MSG_MORE_NOTICES") % int(e["count"])
	else:
		text = headline(String(e["text"]))
	if UITheme.is_cartoon():
		return _make_cartoon_toast(e, text, category, compact)
	var toast := PanelContainer.new()
	toast.name = "Alert"
	toast.set_meta("alert_key", String(e["key"]))
	toast.add_theme_stylebox_override("panel", UITheme.make_hud_card_style(color.darkened(0.3), 1, true))
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.tooltip_text = String(e["text"])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.add_child(row)
	row.add_child(_make_icon(category, color))
	var label := UITheme.make_label(text, "small", color)
	label.name = "Text"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.max_lines_visible = 1 if _busy_drawn else 2
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.custom_minimum_size.x = (TOAST_W_COMPACT if compact else TOAST_W) - 80.0
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	if int(e["count"]) > 1 and not bool(e["summary"]):
		var count := UITheme.make_label("×%d" % int(e["count"]), "small", UITheme.TEXT_BRIGHT)
		count.name = "Count"
		count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(count)
	var close := Button.new()
	close.name = "Close"
	close.text = "✕"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	var side := UITheme.touch_px(22.0 if compact else 26.0)
	close.custom_minimum_size = Vector2(side, side)
	close.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	close.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	close.tooltip_text = Tr.t("BTN_CLOSE")
	var key := String(e["key"])
	close.pressed.connect(func():
		_alerts.dismiss(key)
		_pump())
	row.add_child(close)
	return toast

## Estilo maqueta (docs/28 §10, feat/ui2-hud): la pieza CartoonTheme.notice()
## (icono con forma propia por tipo + una frase + "×N" + X, franja del color
## del tipo). Solo cambia el ESTILO: cola, colocacion y tiempos son los de
## siempre (AlertQueue). En telefono tocar el aviso entero lo cierra (la X
## dibujada es pequena). Los nodos conservan sus nombres (Alert, Text, Count,
## Close) para quien los busque.
func _make_cartoon_toast(e: Dictionary, text: String, category: String, compact: bool) -> PanelContainer:
	var tone := CartoonTheme.notice_tone(category)
	var toast := CartoonTheme.notice(text, CartoonTheme.notice_glyph(category), tone,
		1 if bool(e["summary"]) else int(e["count"]))
	toast.name = "Alert"
	toast.set_meta("alert_key", String(e["key"]))
	toast.tooltip_text = String(e["text"])
	var key := String(e["key"])
	var parts := CartoonTheme.notice_parts(toast)
	var label := parts["label"] as Label
	if label != null:
		label.name = "Text"
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.max_lines_visible = 1 if _busy_drawn else 2
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.custom_minimum_size.x = (TOAST_W_COMPACT if compact else TOAST_W) - 96.0
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if parts["count"] != null:
		(parts["count"] as Control).name = "Count"
	var close := parts["close"] as Button
	if close != null:
		close.name = "Close"
		close.focus_mode = Control.FOCUS_NONE
		close.tooltip_text = Tr.t("BTN_CLOSE")
		close.pressed.connect(func():
			_alerts.dismiss(key)
			_pump())
	# Telefono: el aviso entero se cierra de un toque.
	if CartoonTheme.phone:
		toast.mouse_filter = Control.MOUSE_FILTER_STOP
		toast.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				toast.accept_event()
				_alerts.dismiss(key)
				_pump())
	else:
		toast.mouse_filter = Control.MOUSE_FILTER_PASS
	return toast

## El icono: un cuadrito del color del aviso con un signo, para no depender solo
## del color (peligro y advertencia "!", logro "▲", columna "»", resto "i").
func _make_icon(category: String, color: Color) -> Control:
	var box := PanelContainer.new()
	box.name = "Icon"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = color.darkened(0.15)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	box.add_theme_stylebox_override("panel", sb)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var glyph := UITheme.make_label(icon_glyph(category), "small", UITheme.BG_DARK)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.custom_minimum_size.x = 10
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(glyph)
	return box

static func icon_glyph(category: String) -> String:
	match category:
		"danger", "warning":
			return "!"
		"achievement":
			return "▲"
		"combat":
			return "»"
	return "i"

## Una frase: hasta el primer punto y seguido (el texto entero va en el
## registro y en la ayuda emergente del aviso). Si la primera es muy corta,
## entero.
static func headline(text: String) -> String:
	var cut := -1
	for mark in [". ", "! ", "? "]:
		var at := text.find(mark)
		if at >= 12 and (cut < 0 or at < cut):
			cut = at
	if cut >= 0:
		return text.substr(0, cut + 1)
	return text

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
## "achievement": hito, era nueva y ascenso de rango (ProgressPanel, RankPanel).
static func shows_toast(category: String) -> bool:
	return category in ["warning", "danger", "notice", "combat", "achievement"]

## El registro, abierto desde el menu.
func open_log() -> void:
	if not _is_open:
		_toggle_panel()

func is_open() -> bool:
	return _is_open

func _toggle_panel() -> void:
	_is_open = not _is_open
	_panel.visible = _is_open
	_pump()

# ── Fases ──

func _on_phase_advanced(new_phase: int) -> void:
	# Notify the player about the new phase
	var phase_msg: String = Tr.t("PHASE_%d" % new_phase)
	if phase_msg != "PHASE_%d" % new_phase:
		EventBus.notification_posted.emit(phase_msg, "info", UITheme.ACCENT)
