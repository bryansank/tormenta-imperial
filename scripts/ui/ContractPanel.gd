extends CanvasLayer
## ENCARGOS: el tablon con los tres encargos (la Regencia, los vecinos y el
## contrabandista). Se abre desde ☰ MENU > COLONIA > ENCARGOS.
##
## Iconos y cifras antes que frases: cada tarjeta es
##   [Quien]                         3:20
##   ███████████░░░░  (plazo)
##   Piden  [madera] 60   (en rojo lo que falta)
##   Dan    [moral] +8 · [oro] +30 · Diezmo −10 %
##   [ ENTREGAR ]  [ No, gracias ]
## Quien es cada uno y que significa cada premio va en los tooltips (en tactil,
## mantener pulsado).
##
## El panel solo lee ContractManager y le llama (deliver/discard); no guarda
## estado del tablon.
##
## Rediseno fase 2 (feat/ui2-ejercito, docs/28): ventana crema con cinta de
## laton; cada encargo, una tarjeta con quien lo pide en una pastilla de su
## color, el reloj, lo que piden y lo que dan en iconos, ENTREGAR (verde) y
## descartar (solo icono). En PC las tres tarjetas lado a lado; en telefono, en
## columna con scroll.

const TextKit := preload("res://scripts/ui/TextKit.gd")
const BoardScript := preload("res://scripts/economy/ContractBoard.gd")
const CT := preload("res://scripts/ui/CartoonTheme.gd")

## Tope de la ventana en PC (en telefono va a pantalla completa).
const MAX_SIZE := Vector2(1080, 520)
## Iconos de la fila de premios.
const ICON_PX := 24
## Cada cuanto se repintan los relojes con el panel abierto.
const TICK_EVERY := 0.25

var _win: Dictionary = {}
var _holder: Control
var _panel: PanelContainer
var _backdrop: ColorRect
var _is_open := false
var _list: BoxContainer
var _scroll: ScrollContainer
var _footer: Label
## source -> {"time": Label, "bar": ProgressBar} de las tarjetas con encargo.
var _clocks: Dictionary = {}
## source -> Label de "Otro encargo en 1:20" de las tarjetas vacias.
var _waits: Dictionary = {}
var _tick_left := 0.0
var _refresh_queued := false

func _ready() -> void:
	layer = 11
	_setup_ui()
	UIManager.register_panel(self, "ContractPanel.modal")
	EventBus.contract_board_changed.connect(_request_refresh)
	# Lo que entra o sale de la bolsa cambia lo que falta y si se puede entregar.
	EventBus.resource_changed.connect(func(_r, _a, _d): _request_refresh())
	EventBus.era_advanced.connect(func(_e): _request_refresh())
	EventBus.game_load_completed.connect(_request_refresh)
	get_viewport().size_changed.connect(_on_viewport_resized)
	set_process(false)

func _setup_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_win = CT.modal_window(root, Tr.t("LBL_CONTRACTS_TITLE"), CT.sem("ACCENT"))
	_holder = _win["holder"]
	_holder.visible = false
	_backdrop = _win["veil"]
	_backdrop.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: close())
	_panel = _win["panel"]
	_panel.name = "Modal"
	_panel.gui_input.connect(func(event): if event is InputEventMouseButton and event.pressed: UIManager.focus_window(self))
	(_win["close"] as Button).pressed.connect(close)
	(_win["close"] as Button).tooltip_text = Tr.t("BTN_CLOSE")
	# De que va el tablon, al mantener pulsado la cinta.
	(_win["ribbon"] as Control).mouse_filter = Control.MOUSE_FILTER_PASS
	(_win["ribbon"] as Control).tooltip_text = Tr.t("LBL_CONTRACTS_HINT")
	var vbox: VBoxContainer = _win["body"]

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_scroll)
	_build_list()

	_footer = CT.label("", "small", CT.text("window", true))
	_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_footer)
	_fit()

## Telefono: tarjetas en columna. PC: lado a lado.
func _build_list() -> void:
	var phone := CT.is_phone()
	if _list != null and ((_list is VBoxContainer) == phone):
		return
	if _list != null:
		_scroll.remove_child(_list)
		_list.queue_free()
	_list = VBoxContainer.new() if phone else HBoxContainer.new()
	_list.name = "Cards"
	_list.add_theme_constant_override("separation", 8 if phone else 12)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)

func _vp() -> Vector2:
	return get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280, 720)

func _fit() -> void:
	CT.fit_window(_win, _vp(), MAX_SIZE)

func _on_viewport_resized() -> void:
	_fit()
	if _is_open:
		_build_list()
		refresh()

# ── Abrir y cerrar ───────────────────────────────────────────────────

func is_open() -> bool:
	return _is_open

func open() -> void:
	if _is_open:
		return
	_set_open(true)

func close() -> void:
	if not _is_open:
		return
	_set_open(false)

func toggle() -> void:
	_set_open(not _is_open)

## Lo llama UIManager (ESC, el boton atras, otra ventana en el mismo sitio).
func _close() -> void:
	close()

func _set_open(value: bool) -> void:
	_is_open = value
	_holder.visible = value
	set_process(value)
	if value:
		_fit()
		_build_list()
		refresh()
		UIManager.open_panel(self)
	else:
		UIManager.close_panel(self)

# ── Repintar ─────────────────────────────────────────────────────────

## Las senales repintan solo con el panel abierto, y una vez por fotograma.
func _request_refresh(_arg = null) -> void:
	if not _is_open or _refresh_queued:
		return
	_refresh_queued = true
	_flush_refresh.call_deferred()

func _flush_refresh() -> void:
	_refresh_queued = false
	if _is_open:
		refresh()

func _process(delta: float) -> void:
	if not _is_open:
		return
	_tick_left -= delta
	if _tick_left > 0.0:
		return
	_tick_left = TICK_EVERY
	_update_clocks()

## Rehace las tres tarjetas. Publico para los tests.
func refresh() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_clocks.clear()
	_waits.clear()
	for source in BoardScript.SOURCES:
		_list.add_child(_make_card(source))
	_footer.text = Tr.t("LBL_CONTRACT_HARD") if GameMode.is_governor() else Tr.t("LBL_CONTRACT_EASY")
	_footer.visible = not CT.is_phone()
	_update_clocks()

func _update_clocks() -> void:
	for source in _clocks:
		var contract: Dictionary = ContractManager.get_contract(source)
		if contract.is_empty():
			continue
		var refs: Dictionary = _clocks[source]
		var frac: float = BoardScript.time_fraction(contract)
		(refs["time"] as Label).text = TextKit.short_time(float(contract.get("seconds_left", 0.0)))
		(refs["bar"] as ProgressBar).value = frac
	for source in _waits:
		var label := _waits[source] as Label
		label.text = _wait_text(source)

func _source_color(source: String) -> Color:
	match source:
		"regency":
			return CT.sem("DANGER")
		"neighbors":
			return CT.sem("POSITIVE")
	return CT.sem("INFO")

func _make_card(source: String) -> PanelContainer:
	var color := _source_color(source)
	var contract: Dictionary = ContractManager.get_contract(source)
	var phone := CT.is_phone()
	var card := PanelContainer.new()
	card.name = "Card_" + source
	var style := CT.card_style("window", false, CT.c("window", "CARD_ALT") if contract.is_empty() else Color(0, 0, 0, 0))
	style.set_content_margin_all(8 if phone else 12)
	card.add_theme_stylebox_override("panel", style)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)

	# Quien lo pide (pastilla de su color; quien es, al mantener) · reloj.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	var who := CT.badge(Tr.t(ContractManager.source_name_key(source)), color)
	who.mouse_filter = Control.MOUSE_FILTER_PASS
	who.tooltip_text = Tr.t(ContractManager.source_name_key(source) + "_TIP")
	who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(who)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(gap)
	var rep: int = ContractManager.get_reputation(source)
	if GameMode.is_governor() and rep < 0:
		var pays := CT.label(Tr.t("LBL_CONTRACT_PAYS") % roundi(ContractManager.get_board().reward_mult(source) * 100.0),
			"small", CT.tone_color("warning"))
		pays.name = "Pays"
		pays.mouse_filter = Control.MOUSE_FILTER_PASS
		pays.tooltip_text = Tr.t("LBL_CONTRACT_PAYS_TIP")
		top.add_child(pays)
	box.add_child(top)

	if contract.is_empty():
		var wait_row := CT.icon_line("clock", _wait_text(source), "", "window", "body")
		var wait := wait_row.get_node("Text") as Label
		wait.name = "Wait"
		box.add_child(wait_row)
		_waits[source] = wait
		return card

	var clock_icon := CT.make_glyph("clock", 22)
	clock_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(clock_icon)
	var time := CT.label("", "number", CT.text("window"))
	time.name = "Time"
	time.mouse_filter = Control.MOUSE_FILTER_PASS
	time.tooltip_text = Tr.t("LBL_CONTRACT_TIME_TIP")
	top.add_child(time)
	var bar := CT.progress(1.0, color, "window", 12)
	bar.name = "Clock"
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(bar)
	_clocks[source] = {"time": time, "bar": bar}

	# Piden: en rojo lo que falta.
	var missing: Dictionary = ContractManager.missing_for(source)
	var ask_row := HBoxContainer.new()
	ask_row.name = "Ask"
	ask_row.add_theme_constant_override("separation", 10)
	ask_row.add_child(_row_label(Tr.t("LBL_CONTRACT_ASK")))
	var ask := CT.cost_row(contract.get("ask", {}), missing)
	ask.tooltip_text = Tr.t("LBL_CONTRACT_MISSING_TIP")
	ask_row.add_child(ask)
	box.add_child(ask_row)

	# Dan: el premio entero, a la vista.
	var give_row := HFlowContainer.new()
	give_row.name = "Give"
	give_row.add_theme_constant_override("h_separation", 8)
	give_row.add_theme_constant_override("v_separation", 4)
	give_row.add_child(_row_label(Tr.t("LBL_CONTRACT_GIVE")))
	_fill_reward(give_row, contract.get("reward", {}))
	box.add_child(give_row)

	# Botones a dedo: ENTREGAR (verde, la accion) y descartar (solo icono).
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(spacer)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	var can: bool = ContractManager.can_deliver(source)
	var deliver := CT.pill_button(Tr.t("BTN_CONTRACT_DELIVER"), "check", "primary", CT.h("btn"))
	deliver.name = "Deliver"
	deliver.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deliver.disabled = not can
	if not can:
		deliver.tooltip_text = Tr.t("LBL_CONTRACT_MISSING_TIP")
	deliver.pressed.connect(func():
		if ContractManager.deliver(source):
			refresh()
	)
	buttons.add_child(deliver)
	var discard := CT.pill_button("", "close", "secondary", CT.h("btn"))
	discard.name = "Discard"
	discard.tooltip_text = Tr.t("BTN_CONTRACT_DISCARD")
	discard.pressed.connect(func():
		if ContractManager.discard(source):
			refresh()
	)
	buttons.add_child(discard)
	box.add_child(buttons)
	return card

func _row_label(text: String) -> Label:
	var label := CT.label(text, "small", CT.text("window", true))
	label.custom_minimum_size.x = 56
	return label

## Premio: recursos con su icono (+cifra), moral y colonos con el suyo, la
## rebaja del Diezmo con su porcentaje.
func _fill_reward(row: Container, reward: Dictionary) -> void:
	var resources := {}
	for kind in reward:
		var amount: int = int(reward[kind])
		match String(kind):
			"morale":
				row.add_child(_icon_chip("morale", "+%d" % amount, Tr.t("LBL_CONTRACT_MORALE_TIP")))
			"colonists":
				row.add_child(_icon_chip("workers", "+%d" % amount, Tr.t("LBL_CONTRACT_PEOPLE_TIP")))
			"tithe_discount":
				var tithe := CT.badge(Tr.t("LBL_CONTRACT_TITHE") % amount, CT.sem("POSITIVE"), "storm")
				tithe.name = "Tithe"
				tithe.mouse_filter = Control.MOUSE_FILTER_PASS
				tithe.tooltip_text = Tr.t("LBL_CONTRACT_TITHE_TIP")
				row.add_child(tithe)
			_:
				resources[String(kind)] = amount
	if not resources.is_empty():
		row.add_child(CT.cost_row(resources, {}, "+"))

func _icon_chip(icon_id: String, text: String, tip: String) -> HBoxContainer:
	var chip := HBoxContainer.new()
	chip.name = "Chip_" + icon_id
	chip.add_theme_constant_override("separation", 4)
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	chip.tooltip_text = tip
	chip.add_child(UITheme.make_icon(icon_id, ICON_PX))
	chip.add_child(CT.label(text, "number", CT.tone_color("positive")))
	return chip

func _wait_text(source: String) -> String:
	if not ContractManager.is_source_open(source):
		return Tr.t("LBL_CONTRACT_LOCKED") % int(GameConfig.contract_source_era.get(source, 1))
	var left: float = ContractManager.seconds_until_next(source)
	if left <= 0.0:
		return Tr.t("LBL_CONTRACT_SOON")
	return Tr.t("LBL_CONTRACT_NEXT") % TextKit.short_time(left)
