extends CanvasLayer
## El reloj de la Tormenta en pantalla. Sin esto el Aviso solo existe como un
## mensaje que se va, y todo el diseño se cae: la Tormenta funciona porque el
## jugador la ve venir y decide con tiempo.
##
## No guarda estado: lee StormManager y se redibuja. Como el resto de la interfaz.
##
## Detalle deliberado: **la cuenta atrás permanente no aparece hasta haber
## sobrevivido a la primera tormenta.** Antes de eso solo se ve el Aviso. Así el
## jugador descubre que la Tormenta tiene horario en vez de que se lo digan —
## que es exactamente el segundo acto del lore.

var _root: Control
var _panel: PanelContainer
var _label: Label
var _bar: ProgressBar
var _pulse := 0.0

func _ready() -> void:
	# Por encima de los globos del tutorial (14) y de los paneles modales (15) a
	# proposito: saber cuanto falta para la ceniza importa igual —o mas— mientras
	# estas gastando en el mercado. Es el unico HUD que gana a un modal.
	layer = 16
	_setup_ui()
	EventBus.storm_phase_changed.connect(func(_p, _s): _refresh())
	EventBus.storm_incoming.connect(func(_s, _sev): _refresh())
	EventBus.storm_started.connect(func(_sev): _refresh())
	EventBus.storm_tick.connect(func(_left): _refresh())
	EventBus.storm_ended.connect(func(_sev): _refresh())
	EventBus.tithe_resolved.connect(func(_paid, _taken): _refresh())
	_refresh()

func _process(delta: float) -> void:
	if not _panel.visible:
		return
	_update_countdown()
	# Mientras cae, el panel late. Un numero quieto no transmite urgencia.
	if StormManager.is_storming():
		_pulse += delta * 4.0
		_panel.modulate.a = 0.75 + 0.25 * sin(_pulse)
	else:
		_panel.modulate.a = 1.0

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

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(vbox)

	_label = UITheme.make_label("", "section", UITheme.TEXT_BRIGHT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_label)

	_bar = UITheme.make_progress_bar(UITheme.WARNING, 8)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_bar)

# ── Refresco ─────────────────────────────────────────────────────────

func _refresh() -> void:
	if _panel == null:
		return
	var phase: int = StormManager.get_phase()
	_panel.visible = _should_show(phase)
	if not _panel.visible:
		return
	_style_for(phase)
	_update_countdown()

## El banner aparece siempre que haya algo encima, y ademas durante la calma
## solo una vez el jugador ya sabe que esto vuelve.
func _should_show(phase: int) -> bool:
	if not StormManager.is_armed():
		return false
	match phase:
		StormCycle.Phase.WARNING, StormCycle.Phase.STORM:
			return true
		StormCycle.Phase.CALM:
			return StormManager.storms_survived() > 0
		_:
			return false   # durante la cobranza manda el tablero

func _style_for(phase: int) -> void:
	var storming: bool = phase == StormCycle.Phase.STORM
	var warning: bool = phase == StormCycle.Phase.WARNING
	var tint: Color = UITheme.DANGER if storming else (UITheme.WARNING if warning else UITheme.TEXT_DIM)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.06, 0.05, 0.92)
	style.set_corner_radius_all(UITheme.CORNER)
	style.set_content_margin_all(8)
	style.border_color = tint
	style.set_border_width_all(3 if storming else 2)
	_panel.add_theme_stylebox_override("panel", style)

	UITheme.set_label_color(_label, tint if storming or warning else UITheme.TEXT_DIM)
	var fill := StyleBoxFlat.new()
	fill.bg_color = tint
	fill.set_corner_radius_all(1)
	_bar.add_theme_stylebox_override("fill", fill)

func _update_countdown() -> void:
	var phase: int = StormManager.get_phase()
	if phase == StormCycle.Phase.STORM:
		_label.text = "%s  ·  %s" % [Tr.t("STORM_OVERHEAD"), _clock(_storm_seconds_left())]
		_bar.value = 1.0 - clampf(_storm_seconds_left() / maxf(1.0, GameConfig.get_storm_duration()), 0.0, 1.0)
		return
	var left: float = StormManager.seconds_until_impact()
	_label.text = Tr.t("STORM_COUNTDOWN") % _clock(left)
	var full: float = GameConfig.get_storm_interval(false) + GameConfig.get_storm_warning()
	_bar.value = 1.0 - clampf(left / maxf(1.0, full), 0.0, 1.0)

func _storm_seconds_left() -> float:
	var cycle: StormCycle = StormManager.get_cycle()
	return maxf(0.0, cycle.seconds_left) if cycle != null else 0.0

func _clock(seconds: float) -> String:
	var total: int = maxi(0, ceili(seconds))
	return "%d:%02d" % [total / 60, total % 60]
