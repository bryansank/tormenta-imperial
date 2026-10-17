extends CanvasLayer
## El indicador de fase de la Tormenta. Dice **en que fase esta** el cielo, y
## nada mas: ni cuanto falta, ni como de fuerte viene.
##
## Antes era una cuenta atras, y la cuenta atras resolvia sola la unica pregunta
## que el juego quiere hacerle al jugador. Con un numero en pantalla, prepararse
## es aritmetica: se gasta en el ultimo segundo y no se arriesga nada. Sin el,
## hay que decidir con el cielo como unica pista — y una de cada cuatro veces
## esa decision se paga para nada, que es exactamente el punto.
##
## Tampoco muestra la severidad: eso se sabe cuando la tormenta ya esta encima.
##
## En calma (desde la Fundicion) ensena el **barometro** (doc 21 D5 = A): una barra
## que se llena y un margen, "3-5 min", nunca el minuto exacto. El margen esta
## movido al azar (StormCycle.barometer()), asi que no se puede cronometrar.
## Tocar el panel abre la **Orden de la Regencia**: lo que se llevara el proximo
## Diezmo y tres formas de pagar menos. La tarjeta se abre sola con cada Orden
## nueva y se cierra con la X.
##
## No guarda estado de partida: lee StormManager y se redibuja. Lo unico suyo es
## si la tarjeta esta abierta, que no viaja en el guardado.

## El icono de cada fase. Formas distintas, no solo colores distintos: quien no
## distinga el ambar del oxido tiene que poder leer la fase igual.
class PhaseIcon extends Control:
	var shape: int = StormCycle.Phase.CALM
	var tint: Color = Color.WHITE

	func set_phase(phase: int, color: Color) -> void:
		shape = phase
		tint = color
		queue_redraw()

	func _draw() -> void:
		var box: Vector2 = size
		var center := box * 0.5
		var radius: float = minf(box.x, box.y) * 0.3
		match shape:
			StormCycle.Phase.WARNING:
				# Un ojo abierto: hay algo en el horizonte y todavia no cae nada.
				draw_arc(center - Vector2(0, radius * 0.3), radius, 0.0, TAU, 24, tint, 2.5, true)
			StormCycle.Phase.ASH:
				# El mismo ojo, ya soltando ceniza.
				draw_arc(center - Vector2(0, radius * 0.6), radius, 0.0, TAU, 24, tint, 2.5, true)
				_draw_fall(center, radius, 2.0)
			StormCycle.Phase.STORM:
				# Lleno y cayendo con todo: la fase que rompe techos.
				draw_circle(center - Vector2(0, radius * 0.6), radius, tint)
				_draw_fall(center, radius, 3.0)
			StormCycle.Phase.TITHE:
				# Un sello. Los Tasadores no son clima, son papeleo con escolta.
				var side: float = radius * 1.7
				draw_rect(Rect2(center - Vector2(side, side) * 0.5, Vector2(side, side)), tint, true)
			_:
				pass

	func _draw_fall(center: Vector2, radius: float, width: float) -> void:
		var top: float = center.y + radius * 0.5
		var bottom: float = center.y + radius * 1.5
		for i in [-1.0, 0.0, 1.0]:
			var x: float = center.x + i * radius * 0.65
			draw_line(Vector2(x, top), Vector2(x, bottom), tint, width)

var _root: Control
var _panel: PanelContainer
var _icon: PhaseIcon
var _label: Label
var _pulse := 0.0

## La fila de la fase (Aviso, Ceniza, Tormenta, Diezmo).
var _phase_row: HBoxContainer
## El barometro de la calma.
var _baro_row: HBoxContainer
var _baro_icon: PhaseIcon
var _baro_bar: ProgressBar
var _baro_label: Label
var _baro_left := 0.0
## La tarjeta de la Orden.
var _card: VBoxContainer
var _card_open := false
var _take_label: Label
var _escort_label: Label
var _delivery_row: HBoxContainer
var _delivery_icon: TextureRect
var _delivery_label: Label
var _deliver_btn: Button
var _towers_label: Label
var _expedition_label: Label

## Cada cuanto se repinta el barometro en calma. No hace falta mas: el margen se
## mueve de minuto en minuto.
const BARO_REFRESH := 1.0

const LAYER_OVER_MODALS := 16
const LAYER_UNDER_MODALS := 11

func _sync_layer() -> void:
	var under: bool = UILayoutManager.is_column_narrow() and UIManager.is_any_window_open()
	layer = LAYER_UNDER_MODALS if under else LAYER_OVER_MODALS

func _ready() -> void:
	# Por encima de los globos del tutorial (14) y de las ventanas modales, que
	# UIManager apila desde la capa 12 (12, 13...), a proposito: saber que hay en
	# el cielo importa igual —o mas— mientras estas gastando en el mercado. Es el
	# unico HUD que gana a un modal. Con cuatro ventanas abiertas a la vez una
	# llegaria a la 16; no pasa en la practica (las del centro se cierran entre si).
	layer = LAYER_OVER_MODALS
	_setup_ui()
	# Cuando la columna central baja a la izquierda (tablet 4:3, movil, escala
	# grande) el indicador cae en mitad de la pantalla: encima de una ventana
	# taparia su contenido. Ahi se queda por debajo de las ventanas.
	UIManager.window_opened.connect(func(_w): _sync_layer())
	UIManager.window_closed.connect(func(_w): _sync_layer())
	UILayoutManager.layout_changed.connect(_sync_layer)
	EventBus.storm_phase_changed.connect(func(_p, _s): _refresh())
	EventBus.storm_incoming.connect(func(_s): _refresh())
	EventBus.storm_false_alarm.connect(func(_d): _refresh())
	EventBus.storm_ash_started.connect(_refresh)
	EventBus.storm_started.connect(func(_sev): _refresh())
	EventBus.storm_tick.connect(func(_p, _left): _refresh())
	EventBus.storm_ended.connect(func(_sev): _refresh())
	EventBus.tithe_resolved.connect(func(_paid, _taken): _refresh())
	EventBus.storm_order_changed.connect(_on_order_changed)
	EventBus.resource_changed.connect(func(_r, _a, _d): if _card_open: _refresh_card())
	EventBus.game_load_completed.connect(_refresh)
	_refresh()

## El latido sustituye al numero: cuanto mas rapido late, peor esta la cosa. Es
## la unica pista de intensidad que da el panel, y es deliberadamente vaga.
func _process(delta: float) -> void:
	if not _panel.visible:
		return
	if _baro_row.visible:
		_baro_left -= delta
		if _baro_left <= 0.0:
			_refresh_barometer()
	var beat: float = _beat_rate(StormManager.get_phase())
	if beat <= 0.0:
		_panel.modulate.a = 1.0
		return
	_pulse += delta * beat
	_panel.modulate.a = 0.75 + 0.25 * sin(_pulse)

func _setup_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Se coloca el panel, no el contenedor: asi el objetivo que se apila debajo
	# ve la altura real del banner, y cuando el banner se oculta (calma) sube a
	# ocupar su sitio en vez de dejar un hueco vacio arriba de la pantalla.
	_panel = PanelContainer.new()
	# Se toca: abre y cierra la Orden. Es pequeno, asi que no le quita mapa a nadie.
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.gui_input.connect(_on_panel_input)
	_panel.visible = false
	UILayoutManager.apply_layout("StormHUD", _panel)
	_root.add_child(_panel)
	HudRegistry.register("StormHUD", _panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(column)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 10)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(hbox)
	_phase_row = hbox

	_icon = PhaseIcon.new()
	_icon.custom_minimum_size = Vector2(26, 26)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(_icon)

	_label = UITheme.make_label("", "section", UITheme.TEXT_BRIGHT)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(_label)

	_setup_barometer(column)
	_setup_card(column)

## El barometro: el ojo del Aviso en apagado, una barra corta y el margen.
func _setup_barometer(parent: Control) -> void:
	_baro_row = HBoxContainer.new()
	_baro_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_baro_row.add_theme_constant_override("separation", 8)
	_baro_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_baro_row.visible = false
	parent.add_child(_baro_row)

	_baro_icon = PhaseIcon.new()
	_baro_icon.custom_minimum_size = Vector2(22, 22)
	_baro_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_baro_row.add_child(_baro_icon)

	_baro_bar = UITheme.make_progress_bar(UITheme.WARNING, 10)
	_baro_bar.custom_minimum_size = Vector2(90, 10)
	_baro_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_baro_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_baro_row.add_child(_baro_bar)

	_baro_label = UITheme.make_label("", "body", UITheme.TEXT)
	_baro_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_baro_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_baro_row.add_child(_baro_label)

## La tarjeta de la Orden. Se construye una vez; _refresh_card() solo reescribe.
func _setup_card(parent: Control) -> void:
	_card = VBoxContainer.new()
	_card.add_theme_constant_override("separation", 4)
	_card.custom_minimum_size = Vector2(300, 0)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.visible = false
	parent.add_child(_card)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(header)
	var title := UITheme.make_label(Tr.t("STORM_ORDER_TITLE"), "section", UITheme.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(title)
	header.add_child(UITheme.make_close_button(close_card))

	_card.add_child(UITheme.make_separator())

	var take_row := _icon_row("gold")
	_take_label = take_row.get_child(1) as Label
	_take_label.tooltip_text = Tr.t("STORM_ORDER_TAKE_TIP")
	_take_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_card.add_child(take_row)

	var escort_row := _icon_row("workers")
	_escort_label = escort_row.get_child(1) as Label
	_card.add_child(escort_row)

	_card.add_child(UITheme.make_label(Tr.t("STORM_ORDER_WAYS"), "small", UITheme.TEXT_DIM))

	_delivery_row = _icon_row("")
	_delivery_icon = _delivery_row.get_child(0) as TextureRect
	_delivery_label = _delivery_row.get_child(1) as Label
	_delivery_label.tooltip_text = Tr.t("STORM_ORDER_DELIVERY_TIP")
	_delivery_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_deliver_btn = Button.new()
	_deliver_btn.text = Tr.t("BTN_ORDER_DELIVER")
	UITheme.style_button(_deliver_btn, UITheme.POSITIVE, UITheme.FONT_SMALL)
	_deliver_btn.pressed.connect(_on_deliver_pressed)
	_delivery_row.add_child(_deliver_btn)
	_card.add_child(_delivery_row)

	_towers_label = UITheme.make_label("", "body", UITheme.TEXT)
	_towers_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_towers_label.tooltip_text = Tr.t("STORM_ORDER_TOWERS_TIP")
	_towers_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_card.add_child(_towers_label)

	_expedition_label = UITheme.make_label("", "body", UITheme.TEXT)
	_expedition_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_expedition_label.tooltip_text = Tr.t("STORM_ORDER_EXPEDITION_TIP")
	_expedition_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_card.add_child(_expedition_label)

## Una fila [icono] texto. Sin icono (id vacio) el hueco queda vacio y el texto
## empieza por el numero igual.
func _icon_row(icon_id: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := UITheme.make_icon(icon_id) if icon_id != "" else TextureRect.new()
	icon.custom_minimum_size = Vector2(UITheme.ICON_SIZE, UITheme.ICON_SIZE)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var label := UITheme.make_label("", "body", UITheme.TEXT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	return row

# ── Refresco ─────────────────────────────────────────────────────────

func _refresh() -> void:
	if _panel == null:
		return
	var phase: int = StormManager.get_phase()
	_panel.visible = _should_show(phase)
	if not _panel.visible:
		_panel.modulate.a = 1.0
		return
	var calm: bool = phase == StormCycle.Phase.CALM
	_phase_row.visible = not calm
	_baro_row.visible = calm
	_style_for(phase)
	if calm:
		_refresh_barometer()
	_refresh_card()

## En calma, antes de la Fundicion, no hay nada que indicar. Desde que el reloj
## esta armado la calma ensena el barometro (doc 21, D5 = A): un margen, no una
## cuenta atras. La tormenta de prueba de la era 1 no trae barometro: se ve solo
## mientras pasa.
func _should_show(phase: int) -> bool:
	# La tormenta de prueba de la era 1 se ve como una de verdad.
	if not StormManager.is_armed() and not StormManager.is_trial_running():
		return false
	if phase == StormCycle.Phase.CALM:
		return not StormManager.is_trial_running() and not StormManager.get_barometer().is_empty()
	return phase in [StormCycle.Phase.WARNING, StormCycle.Phase.ASH,
		StormCycle.Phase.STORM, StormCycle.Phase.TITHE]

## "3–5 min" (o "< 2 min" al final). Nunca un numero solo: el margen es la pista.
func _refresh_barometer() -> void:
	_baro_left = BARO_REFRESH
	var baro: Dictionary = StormManager.get_barometer()
	if baro.is_empty():
		_baro_label.text = ""
		_baro_bar.value = 0.0
		return
	_baro_bar.value = float(baro["fill"])
	_baro_label.text = barometer_text(baro)
	_baro_icon.set_phase(StormCycle.Phase.WARNING, UITheme.readable(
		UITheme.TEXT_DIM.lerp(UITheme.WARNING, float(baro["fill"]))))
	_panel.tooltip_text = Tr.t("STORM_BAROMETER_TIP")

## El texto del margen. Publico para las pruebas.
static func barometer_text(baro: Dictionary) -> String:
	if baro.is_empty():
		return ""
	var low: int = int(baro.get("low", 0))
	var high: int = int(baro.get("high", 1))
	if low <= 0:
		return Tr.t("STORM_BAROMETER_SOON") % high
	return Tr.t("STORM_BAROMETER") % [low, high]

# ── La Orden de la Regencia ──────────────────────────────────────────

func _on_panel_input(event: InputEvent) -> void:
	# Solo el raton: el toque llega aqui tambien como clic emulado, y contar los
	# dos abriria y cerraria la tarjeta en el mismo toque.
	if not (event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if not StormManager.order_visible():
		return
	# Dentro de la tarjeta no se cierra: ahi se lee (y se mantiene pulsado para
	# ver la ayuda de cada linea). Se cierra con su X o tocando el barometro.
	var at: Vector2 = _panel.get_global_transform() * (event as InputEventMouseButton).position
	if _card.visible and _card.get_global_rect().has_point(at):
		return
	_card_open = not _card_open
	_refresh()
	_panel.accept_event()

## Una Orden nueva abre la tarjeta; un cambio en la de siempre solo la repinta.
func _on_order_changed(fresh: bool) -> void:
	if fresh and StormManager.order_visible():
		_card_open = true
	_refresh()

func open_card() -> void:
	_card_open = true
	_refresh()

func close_card() -> void:
	_card_open = false
	_refresh()

func is_card_open() -> bool:
	return _card != null and _card.visible

func _on_deliver_pressed() -> void:
	StormManager.deliver_order()

## Rellena la tarjeta con lo que dice StormManager. Con los Tasadores en la
## puerta no se ensena: la cuenta ya esta hecha.
func _refresh_card() -> void:
	if _card == null:
		return
	var visible_now: bool = _card_open and StormManager.order_visible() \
		and StormManager.get_phase() != StormCycle.Phase.TITHE
	_card.visible = visible_now
	if not visible_now:
		return
	var preview: Dictionary = StormManager.tithe_preview()
	var ratio: int = roundi(float(preview.get("ratio", 0.0)) * 100.0)
	var after: int = roundi(float(preview.get("ratio_after", 0.0)) * 100.0)
	var take: String = Tr.t("STORM_ORDER_TAKE") % ratio if after == ratio \
		else Tr.t("STORM_ORDER_TAKE_CUT") % [ratio, after]
	var floor_after: int = int(preview.get("floor_after", 0))
	if floor_after > 0:
		take += " · " + Tr.t("STORM_ORDER_FLOOR") % floor_after
	_take_label.text = take
	_escort_label.text = Tr.t("STORM_ORDER_ESCORT") % int(preview.get("escort", 0))

	# 1. El encargo.
	var order: Dictionary = StormManager.get_order()
	_delivery_row.visible = not order.is_empty()
	if not order.is_empty():
		var res: String = String(order["res"])
		var pct: int = roundi(GameConfig.storm_order_delivery_pct * 100.0)
		var done: bool = bool(order.get("done", false))
		_delivery_label.text = (("✓ " if done else "") + Tr.t("STORM_ORDER_WAY_DELIVERY")) \
			% [int(order["amount"]), Tr.res_name(res), pct]
		UITheme.set_label_color(_delivery_label, UITheme.TEXT_DIM if done else UITheme.TEXT)
		var tex: Texture2D = UITheme.icon_texture(res, UITheme.ICON_SIZE)
		_delivery_icon.texture = tex
		_deliver_btn.visible = not done
		_deliver_btn.disabled = not StormManager.can_deliver_order()

	# 2. Las torres.
	var towers: Dictionary = StormManager.tower_status()
	var standing: int = int(towers["standing"])
	var goal: int = int(towers["goal"])
	var shown_mitigation: float = float(towers["mitigation"]) if standing >= goal \
		else float(towers["goal_mitigation"])
	_towers_label.text = ("✓ " if standing >= goal else "") + Tr.t("STORM_ORDER_WAY_TOWERS") \
		% [mini(standing, goal), goal, roundi(shown_mitigation * 100.0)]
	UITheme.set_label_color(_towers_label, UITheme.TEXT_DIM if standing >= goal else UITheme.TEXT)

	# 3. La escaramuza: solo cuando su rama la conecta (storm_order_expedition_way).
	_expedition_label.visible = GameConfig.storm_order_expedition_way
	if _expedition_label.visible:
		var won: bool = StormManager.get_discount_from("expedicion") > 0.0
		_expedition_label.text = ("✓ " if won else "") + Tr.t("STORM_ORDER_WAY_EXPEDITION") \
			% roundi(GameConfig.storm_order_expedition_pct * 100.0)
		UITheme.set_label_color(_expedition_label, UITheme.TEXT_DIM if won else UITheme.TEXT)

func _style_for(phase: int) -> void:
	var tint: Color = _tint_for(phase)

	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.HUD_BG
	style.set_corner_radius_all(UITheme.CORNER)
	style.set_content_margin_all(8)
	style.border_color = tint
	style.set_border_width_all(3 if phase == StormCycle.Phase.STORM else 2)
	_panel.add_theme_stylebox_override("panel", style)

	_icon.set_phase(phase, UITheme.readable(tint))
	_label.text = Tr.t(_key_for(phase))
	UITheme.set_label_color(_label, tint)

## El color sube de temperatura con la fase, y el Diezmo se sale de la escala del
## clima a proposito: ya no es cielo, es alguien en la puerta.
func _tint_for(phase: int) -> Color:
	match phase:
		StormCycle.Phase.WARNING:
			return UITheme.WARNING
		StormCycle.Phase.ASH:
			return UITheme.WARNING.lerp(UITheme.DANGER, 0.5)
		StormCycle.Phase.STORM:
			return UITheme.DANGER
		StormCycle.Phase.TITHE:
			return UITheme.ACCENT
		_:
			return UITheme.TEXT_DIM

func _key_for(phase: int) -> String:
	match phase:
		StormCycle.Phase.WARNING:
			return "STORM_PHASE_WARNING"
		StormCycle.Phase.ASH:
			return "STORM_PHASE_ASH"
		StormCycle.Phase.STORM:
			return "STORM_PHASE_STORM"
		StormCycle.Phase.TITHE:
			return "STORM_PHASE_TITHE"
		_:
			return "STORM_PHASE_WARNING"

## Pulsaciones por segundo, en radianes. Cero significa panel quieto.
func _beat_rate(phase: int) -> float:
	match phase:
		StormCycle.Phase.WARNING:
			return 1.5
		StormCycle.Phase.ASH:
			return 2.5
		StormCycle.Phase.STORM:
			return 4.0
		_:
			return 0.0
