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
## No guarda estado: lee StormManager y se redibuja. Como el resto de la interfaz.

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

func _ready() -> void:
	# Por encima de los globos del tutorial (14) y de los paneles modales (15) a
	# proposito: saber que hay en el cielo importa igual —o mas— mientras estas
	# gastando en el mercado. Es el unico HUD que gana a un modal.
	layer = 16
	_setup_ui()
	EventBus.storm_phase_changed.connect(func(_p, _s): _refresh())
	EventBus.storm_incoming.connect(func(_s): _refresh())
	EventBus.storm_false_alarm.connect(func(_d): _refresh())
	EventBus.storm_ash_started.connect(_refresh)
	EventBus.storm_started.connect(func(_sev): _refresh())
	EventBus.storm_tick.connect(func(_p, _left): _refresh())
	EventBus.storm_ended.connect(func(_sev): _refresh())
	EventBus.tithe_resolved.connect(func(_paid, _taken): _refresh())
	_refresh()

## El latido sustituye al numero: cuanto mas rapido late, peor esta la cosa. Es
## la unica pista de intensidad que da el panel, y es deliberadamente vaga.
func _process(delta: float) -> void:
	if not _panel.visible:
		return
	var beat: float = _beat_rate(StormManager.get_phase())
	if beat <= 0.0:
		_panel.modulate.a = 1.0
		return
	_pulse += delta * beat
	_panel.modulate.a = 0.75 + 0.25 * sin(_pulse)

func _setup_ui() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UILayoutManager.apply_layout("StormHUD", _root)
	add_child(_root)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	_root.add_child(_panel)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 10)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(hbox)

	_icon = PhaseIcon.new()
	_icon.custom_minimum_size = Vector2(26, 26)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(_icon)

	_label = UITheme.make_label("", "section", UITheme.TEXT_BRIGHT)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(_label)

# ── Refresco ─────────────────────────────────────────────────────────

func _refresh() -> void:
	if _panel == null:
		return
	var phase: int = StormManager.get_phase()
	_panel.visible = _should_show(phase)
	if not _panel.visible:
		_panel.modulate.a = 1.0
		return
	_style_for(phase)

## En calma no hay nada que indicar: un banner permanente que dice "tranquilo"
## acaba siendo mobiliario y deja de leerse cuando por fin cambia.
func _should_show(phase: int) -> bool:
	if not StormManager.is_armed():
		return false
	return phase in [StormCycle.Phase.WARNING, StormCycle.Phase.ASH,
		StormCycle.Phase.STORM, StormCycle.Phase.TITHE]

func _style_for(phase: int) -> void:
	var tint: Color = _tint_for(phase)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.06, 0.05, 0.92)
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
			return UITheme.CAT_PRODUCTION
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
